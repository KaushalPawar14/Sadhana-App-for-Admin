import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Services/MissingReportNotification.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideDialog.dart';
import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/AbcdeActivity.dart'
    show sadhanaDateKey, latestDayWithPossibleData;
import '../utils/PlanningQueries.dart';
import '../utils/PriorityReasons.dart';
import '../utils/SadhanaReportSource.dart' show fetchDateReports;
import '../utils/SeenMarkers.dart';
import '../utils/StudentScope.dart';
import 'StudentProfilePage.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideWait.dart';

/// Priority students (Phase 6, half 1, item 4).
///
/// **A transparent checklist, never a score.** Each student shows the actual
/// reasons they surfaced, in plain words. Nothing here computes a blended
/// priority number, a rating, a tier or a percentage — the ordering is simply
/// *how many separate concerns* a student has, and every one of them is named
/// on the card so the guide can disagree with any of them.
///
/// LIT axes are checked and displayed **independently** (Section 8): L, I and
/// T each produce their own line, and are never summed or averaged with each
/// other or with anything else.
///
/// Composed from existing data — no new collection (Rule 12). Overdue
/// associations reuse `associationOverdueSince()`; missing submissions reuse
/// `NotificationManager().missingUsernames`.
class PriorityStudentsPage extends StatefulWidget {
  const PriorityStudentsPage({super.key});

  @override
  State<PriorityStudentsPage> createState() => _PriorityStudentsPageState();
}

/// One named concern. Deliberately carries no weight or number — a flag is
/// either present or it is not, and the guide reads the words.
///
/// `kind` names the TYPE of concern (never its wording or its day count, which change daily): it is what
/// "Remove from priority list" remembers, so a removed student comes back only when a NEW kind of concern appears.
typedef _Flag = ({String kind, String label, Color colour});

/// A student with at least one concern, and the concerns themselves.
typedef _Priority = ({String uid, String name, List<_Flag> flags});

class _PriorityStudentsPageState extends State<PriorityStudentsPage> {
  /// A relationship is considered stale after three weeks without contact.
  static const int _staleAfterDays = 21;

  /// A LIT axis at or below this is worth the guide's attention.
  static const int _lowAxis = 2;

  String? _guide;
  bool _isHod = false;
  bool _loading = true;
  bool _rosterFailed = false;

  List<_Priority> _priority = [];
  int _inScope = 0;

  /// This admin's "removed from my priority list" records: student uid -> the concern kinds they had then.
  Map<String, Set<String>> _dismissed = {};
  int _hiddenCount = 0;

  /// Multi-select: long-press a student to start, tap others to add.
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final profile = AdminProfileProvider.require();
    final guide = profile.displayName;
    // Opening this list is "seen" for the automatic priority reasons, the
    // same as the flagged-messages list is for its own dot. Keyed by the
    // admin's ID (what `SeenMarkers.seenAt` is read with), never the display
    // name the rest of this method uses for wording.
    if (profile.id.isNotEmpty) {
      SeenMarkers.markSeen(profile.id, 'priorityReasons');
    }
    final students = await scopedStudents();

    if (students == null) {
      // Fail closed — show nothing rather than another guide's students.
      if (!mounted) return;
      setState(() {
        _guide = guide;
        _isHod = profile.isHod;
        _rosterFailed = true;
        _priority = [];
        _inScope = 0;
        _loading = false;
      });
      return;
    }

    // Reused, not recomputed — the same singleton SubmissionStatusPage reads.
    final missing = <String>{...NotificationManager().missingUsernames};

    // One read per collection, independent of student count. `.first` on the
    // shared streams reuses their scoping rather than rebuilding the queries.
    List<QueryDocumentSnapshot> logs = [];
    List<QueryDocumentSnapshot> associations = [];
    List<QueryDocumentSnapshot> lit = [];

    try {
      logs = (await scopedInteractionLogsStream().first).docs;
    } catch (_) {/* a missing signal must not blank the screen */}
    try {
      associations = (await scopedAssociationsStream().first).docs;
    } catch (_) {}
    try {
      // Scoped by the viewer's visible students, not by who wrote the
      // assessment — a reassigned student keeps their history.
      lit = await litAssessmentsForRoster();
    } catch (_) {}

    // Bucket by studentUid once, so the per-student pass is a map lookup
    // rather than a scan of every collection per student.
    final logsByStudent = <String, List<Map<String, dynamic>>>{};
    for (final doc in logs) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = (data['studentUid'] ?? '').toString();
      if (uid.isEmpty) continue;
      logsByStudent.putIfAbsent(uid, () => []).add(data);
    }

    final assocByStudent = <String, List<Map<String, dynamic>>>{};
    for (final doc in associations) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = (data['studentUid'] ?? '').toString();
      if (uid.isEmpty) continue;
      assocByStudent.putIfAbsent(uid, () => []).add(data);
    }

    final litByStudent = <String, List<Map<String, dynamic>>>{};
    for (final doc in lit) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = (data['studentUid'] ?? '').toString();
      if (uid.isEmpty) continue;
      litByStudent.putIfAbsent(uid, () => []).add(data);
    }

    // The full roster documents: the reasons need each student's residence
    // (which report collection is theirs) and their own commitments, which
    // `scopedStudents()` does not carry. Same scoped query, read once.
    final roster = <String, Map<String, dynamic>>{};
    try {
      final snap = await StudentScope.current().studentsGet();
      for (final d in snap.docs) {
        roster[d.id] = d.data();
      }
    } catch (_) {/* no reasons rather than no screen */}

    // Each student's own category's reports. One read per student, in
    // parallel — there is no collection-group query over `dates` (the ids are
    // `dd-MM-yyyy`, which does not sort chronologically, and the rules can only
    // prove a per-student scoped read). Retention keeps about two months, so
    // each read is small. A failure for one student costs that student's
    // reasons, never the screen.
    final reasonsByStudent = <String, List<PriorityReason>>{};
    await Future.wait(students.map((student) async {
      final data = roster[student.uid];
      if (data == null) return;
      try {
        final reports = await fetchDateReports(student.name, (data['role'] ?? '').toString());
        final reasons = priorityReasonsFor(
          days: _windowFor(reports),
          role: (data['role'] ?? '').toString(),
          chantCommitment: _asCommitment(data['commitmentRounds']),
          readingCommitment: _asCommitment(data['readingCommitmentMinutes']),
        );
        if (reasons.isNotEmpty) reasonsByStudent[student.uid] = reasons;
      } catch (_) {}
    }));

    // The students THIS admin already removed from their own priority list (a read failure just shows everyone).
    final dismissed = await _readDismissals(profile.id);

    final result = <_Priority>[];
    var hidden = 0;

    for (final student in students) {
      final flags = _flagsFor(
        student: student,
        logs: logsByStudent[student.uid] ?? const [],
        associations: assocByStudent[student.uid] ?? const [],
        lit: litByStudent[student.uid] ?? const [],
        missing: missing,
        reasons: reasonsByStudent[student.uid] ?? const [],
      );

      // No concerns means not a priority. Such a student is simply absent.
      if (flags.isEmpty) continue;

      // Removed by this admin, and nothing NEW has come up since: stays off their list.
      final removedKinds = dismissed[student.uid];
      if (removedKinds != null && flags.every((f) => removedKinds.contains(f.kind))) {
        hidden++;
        continue;
      }

      result.add((uid: student.uid, name: student.name, flags: flags));
    }

    // Most concerns first; alphabetical within the same count so the order is
    // stable rather than arbitrary.
    result.sort((a, b) {
      final byCount = b.flags.length.compareTo(a.flags.length);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });

    if (!mounted) return;
    setState(() {
      _guide = guide;
      _isHod = profile.isHod;
      _rosterFailed = false;
      _priority = result;
      _dismissed = dismissed;
      _hiddenCount = hidden;
      _selected.clear();
      _inScope = students.length;
      _loading = false;
    });
  }

  Future<Map<String, Set<String>>> _readDismissals(String adminId) async {
    try {
      final snap = await GuideDb.instance
          .collection('priorityDismissals')
          .where('adminId', isEqualTo: adminId)
          .get();
      return {
        for (final d in snap.docs)
          (d.data()['studentUid'] ?? '').toString(): {
            for (final k in (d.data()['kinds'] as List? ?? const [])) k.toString(),
          },
      }..remove('');
    } catch (_) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // Remove from the priority list (multi-select)
  // ---------------------------------------------------------------------------

  void _toggle(String uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  /// Takes the selected students off THIS admin's priority list. It writes one small record per student
  /// (`priorityDismissals/{adminId}__{studentUid}`: adminId, studentUid, kinds, dismissedAt) and nothing else:
  /// the student, their reports, chats, meetings and assessments are never touched.
  Future<void> _removeSelected() async {
    final profile = AdminProfileProvider.require();
    final chosen = _priority.where((p) => _selected.contains(p.uid)).toList();
    if (chosen.isEmpty) return;
    final n = chosen.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text(n == 1 ? "Remove 1 student from your priority list?" : "Remove $n students from your priority list?"),
        content: const Text(
          "This only takes them off your priority list. The students themselves and "
          "everything about them (reports, chats, meetings, assessments) are NOT deleted or changed. "
          "A student comes back to the list if a new kind of concern appears.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(
            key: const ValueKey('confirm-remove-priority'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(n == 1 ? "Remove 1 student" : "Remove $n students",
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final db = GuideDb.instance;
      final batch = db.batch();
      for (final p in chosen) {
        batch.set(db.collection('priorityDismissals').doc('${profile.id}__${p.uid}'), {
          'adminId': profile.id,
          'studentUid': p.uid,
          'kinds': [for (final f in p.flags) f.kind],
          'dismissedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (!mounted) return;
      setState(() => _selected.clear());
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 1 ? "1 student removed from your priority list" : "$n students removed from your priority list"),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not remove them. Nothing was changed.")));
    }
  }

  /// Puts every student this admin removed back on their list (deletes only those small records).
  Future<void> _restoreRemoved() async {
    final profile = AdminProfileProvider.require();
    try {
      final db = GuideDb.instance;
      final batch = db.batch();
      for (final uid in _dismissed.keys) {
        batch.delete(db.collection('priorityDismissals').doc('${profile.id}__$uid'));
      }
      await batch.commit();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not restore them just now.")));
    }
  }

  // ---------------------------------------------------------------------------
  // The checklist
  // ---------------------------------------------------------------------------

  /// A commitment field as a whole number; anything else is 0, which the
  /// reason rules read as "not set" (chanting then falls back to the
  /// standard 16, reading skips its reason entirely).
  static int _asCommitment(Object? v) =>
      v is num && v.isFinite && v > 0 ? v.toInt() : 0;

  /// The 30 calendar days the reasons look at, most recent first.
  ///
  /// The window ENDS AT YESTERDAY (`latestDayWithPossibleData`), not today:
  /// a student who simply has not filed yet this morning is not three days
  /// behind. The server's nightly check uses the same end day, so the app and
  /// the notification never disagree by a day.
  static List<ReportDay> _windowFor(Map<String, Map<String, dynamic>> reports) {
    final last = latestDayWithPossibleData(DateTime.now());
    return [
      for (var i = 0; i < 30; i++)
        () {
          final day = last.subtract(Duration(days: i));
          return ReportDay(day, reports[sadhanaDateKey(day)]);
        }(),
    ];
  }

  List<_Flag> _flagsFor({
    required ({String uid, String name}) student,
    required List<Map<String, dynamic>> logs,
    required List<Map<String, dynamic>> associations,
    required List<Map<String, dynamic>> lit,
    required Set<String> missing,
    required List<PriorityReason> reasons,
  }) {
    final flags = <_Flag>[];

    // --- The automatic sadhana reasons -------------------------------------
    //
    // Each is three days in a row of the same thing going wrong, read from the
    // student's OWN category's reports and their own commitments
    // (`utils/PriorityReasons.dart`). They carry their own stable `kind`, so
    // "Remove from priority list" treats a NEW kind of slip as new — and a
    // reason simply stops being produced the moment it stops being true, which
    // is what makes the card clear itself.
    for (final r in reasons) {
      flags.add((
        kind: r.key,
        label: r.text,
        colour: r.kind == PriorityReasonKind.noReport
            ? context.g.danger
            : context.g.warning,
      ));
    }

    // --- A. Contact staleness ------------------------------------------------
    //
    // Any status, not approved-only: an unapproved draft still means the guide
    // met the student. `interactionDate` survives approval either way.
    final dated = logs
        .map((l) => l['interactionDate'])
        .whereType<Timestamp>()
        .map((t) => t.toDate())
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (dated.isEmpty) {
      // Distinct from a lapse — this student has never been engaged at all,
      // which may simply mean they were added recently.
      flags.add((kind: 'never_logged', label: "Never logged an interaction", colour: context.g.brass));
    } else {
      final days = daysOverdue(dated.first);
      if (days >= _staleAfterDays) {
        flags.add((
          kind: 'stale_contact',
          label: "No interaction in $days days",
          colour: context.g.warning,
        ));
      }
    }

    // --- B. Today's sadhana report ------------------------------------------
    if (missing.contains(student.name)) {
      flags.add((
        kind: 'missing_report',
        label: "Has not submitted today's sadhana report",
        colour: context.g.warning,
      ));
    }

    // --- C. Overdue association ---------------------------------------------
    DateTime? worstOverdue;
    for (final data in associations) {
      final since = associationOverdueSince(data);
      if (since == null) continue;
      if (worstOverdue == null || since.isBefore(worstOverdue)) {
        worstOverdue = since;
      }
    }
    if (worstOverdue != null) {
      flags.add((
        kind: 'overdue_meeting',
        label: "Meeting overdue by ${daysOverdue(worstOverdue)} days",
        colour: context.g.danger,
      ));
    }

    // --- D. Low LIT axes -----------------------------------------------------
    //
    // Each axis is judged on its own and reported on its own. No sum, no
    // average, no combined figure anywhere (Section 8).
    final sortedLit = lit.toList()
      ..sort((a, b) {
        final da = a['assessedAt'];
        final db = b['assessedAt'];
        if (da is! Timestamp) return 1;
        if (db is! Timestamp) return -1;
        return db.compareTo(da);
      });

    if (sortedLit.isNotEmpty) {
      final latest = sortedLit.first;

      void checkAxis(String key, String meaning) {
        final raw = latest[key];
        if (raw is! num) return;
        final value = raw.toInt();
        if (value > _lowAxis) return;
        flags.add((
          kind: 'lit_$key',
          label: "$meaning ($key: $value of 5)",
          colour: context.g.brass,
        ));
      }

      checkAxis('L', 'Low receptivity');
      checkAxis('I', 'Low interest');
      checkAxis('T', 'Little available time');
    }

    // --- E. Follow-up date passed with no contact since ----------------------
    //
    // Approved-only, because `followUpDate` lives in `approvedSummary`.
    DateTime? dueSince;
    for (final log in logs) {
      if (log['status'] != 'approved') continue;
      final summary = log['approvedSummary'];
      if (summary is! Map<String, dynamic>) continue;

      final raw = summary['followUpDate'];
      if (raw is! Timestamp) continue;

      final due = raw.toDate();
      if (!due.isBefore(DateTime.now())) continue;

      if (dueSince == null || due.isBefore(dueSince)) dueSince = due;
    }

    if (dueSince != null) {
      // Only still outstanding if nothing has been logged since it came due.
      final contactedSince = dated.any((d) => d.isAfter(dueSince!));
      if (!contactedSince) {
        flags.add((
          kind: 'follow_up_due',
          label: "Follow-up was due "
              "${DateFormat('dd MMM').format(dueSince)}, no contact since",
          colour: Colors.brown,
        ));
      }
    }

    return flags;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(
            leading: _selecting
                ? IconButton(
                    key: const ValueKey('cancel-selection'),
                    tooltip: "Cancel selection",
                    icon: Icon(Icons.close, color: colorProvider.secondColor),
                    onPressed: () => setState(_selected.clear),
                  )
                : null,
            title: Text(_selecting ? "${_selected.length} selected" : "Priority Students"),
            actions: [
              if (!_selecting)
                IconButton(
                  tooltip: "Refresh",
                  icon: Icon(Icons.refresh, color: colorProvider.secondColor),
                  onPressed: _loading ? null : _load,
                ),
            ]),
          body: _loading
              ? const GuideWait()
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            _summaryCard(),
                            if (_hiddenCount > 0 && !_selecting) _restoreLine(),
                            const SizedBox(height: 18),
                            if (_rosterFailed)
                              _messageCard("Could not read the student list")
                            else if (_priority.isEmpty)
                              _messageCard(
                                _inScope == 0
                                    ? "No students in scope yet"
                                    : "No concerns flagged right now",
                              )
                            else ...[
                              if (!_selecting)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text("Press and hold a student to select, then remove from your list.",
                                      style: TextStyle(fontSize: 11, color: context.g.mutedText)),
                                ),
                              ..._priority.map(_studentCard),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_selecting) _selectionBar(),
                  ],
                ),
        );
      },
    );
  }

  Widget _summaryCard() {
    final count = _priority.length;
    return GuideSummaryBanner(
      tone: count == 0 ? GuideTone.good : GuideTone.warn,
      icon: count == 0 ? Icons.check_circle_outline : Icons.flag_outlined,
      title: count == 0 ? "Nobody flagged" : "$count need attention",
      lines: [
        if (_inScope > 0) "out of $_inScope students",
        _isHod
            ? "All students (HOD view)"
            : "Your students · ${_guide ?? ''}",
      ],
    );
  }

  /// "N removed by you - Restore": the way back (deletes only this admin's own small removal records).
  Widget _restoreLine() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text("$_hiddenCount removed by you.", style: TextStyle(fontSize: 12, color: context.g.mutedText)),
          TextButton(
            key: const ValueKey('restore-removed'),
            onPressed: _restoreRemoved,
            child: const Text("Restore"),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar() {
    final g = context.g;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(color: g.surface, boxShadow: g.cardShadow),
        child: ElevatedButton.icon(
          key: const ValueKey('remove-from-priority'),
          style: ElevatedButton.styleFrom(
            backgroundColor: g.brass,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _removeSelected,
          icon: Icon(Icons.playlist_remove, color: g.onPrimary),
          label: Text("Remove from priority list", style: TextStyle(color: g.onPrimary)),
        ),
      ),
    );
  }

  Widget _messageCard(String text) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.g.mutedText, fontSize: 14),
        ),
      ),
    );
  }

  Widget _studentCard(_Priority item) {
    final picked = _selected.contains(item.uid);
    return GestureDetector(
      key: ValueKey('priority-${item.uid}'),
      behavior: HitTestBehavior.opaque,
      onLongPress: _selecting ? null : () => _toggle(item.uid),
      onTap: _selecting ? () => _toggle(item.uid) : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: picked ? context.g.brass.withValues(alpha: .10) : context.g.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: picked ? context.g.brass : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(picked ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 22, color: picked ? context.g.brass : context.g.mutedText),
                ),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              // A count of named concerns, not a rating. The reasons below are
              // the substance; this is only how the list was ordered.
              Text(
                item.flags.length == 1
                    ? "1 concern"
                    : "${item.flags.length} concerns",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.g.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          /// Every reason, spelled out. The guide decides what matters.
          ...item.flags.map(
            (flag) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: flag.colour,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      flag.label,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (!_selecting) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentProfilePage(studentUid: item.uid),
                  ),
                ),
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text("Open profile"),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}
