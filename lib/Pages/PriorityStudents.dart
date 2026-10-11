import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Services/MissingReportNotification.dart';
import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/PlanningQueries.dart';
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
typedef _Flag = ({String label, Color colour});

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final profile = AdminProfileProvider.require();
    final guide = profile.displayName;
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

    final result = <_Priority>[];

    for (final student in students) {
      final flags = _flagsFor(
        student: student,
        logs: logsByStudent[student.uid] ?? const [],
        associations: assocByStudent[student.uid] ?? const [],
        lit: litByStudent[student.uid] ?? const [],
        missing: missing,
      );

      // No concerns means not a priority. Such a student is simply absent.
      if (flags.isEmpty) continue;

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
      _inScope = students.length;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // The checklist
  // ---------------------------------------------------------------------------

  List<_Flag> _flagsFor({
    required ({String uid, String name}) student,
    required List<Map<String, dynamic>> logs,
    required List<Map<String, dynamic>> associations,
    required List<Map<String, dynamic>> lit,
    required Set<String> missing,
  }) {
    final flags = <_Flag>[];

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
      flags.add((label: "Never logged an interaction", colour: context.g.brass));
    } else {
      final days = daysOverdue(dated.first);
      if (days >= _staleAfterDays) {
        flags.add((
          label: "No interaction in $days days",
          colour: context.g.warning,
        ));
      }
    }

    // --- B. Today's sadhana report ------------------------------------------
    if (missing.contains(student.name)) {
      flags.add((
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
            title: Text("Priority Students"),
            actions: [
              IconButton(
                tooltip: "Refresh",
                icon: Icon(Icons.refresh, color: colorProvider.secondColor),
                onPressed: _loading ? null : _load,
              ),
            ]),
          body: _loading
              ? const GuideWait()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _summaryCard(),
                      const SizedBox(height: 18),
                      if (_rosterFailed)
                        _messageCard("Could not read the student list")
                      else if (_priority.isEmpty)
                        _messageCard(
                          _inScope == 0
                              ? "No students in scope yet"
                              : "No concerns flagged right now",
                        )
                      else
                        ..._priority.map(_studentCard),
                    ],
                  ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
      ),
    );
  }
}
