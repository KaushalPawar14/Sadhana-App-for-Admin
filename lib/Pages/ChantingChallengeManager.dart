import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Services/HierarchyApi.dart';
import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';

/// Chanting Challenges — a COLLECTIVE roster target.
///
/// A guide sets one target for a date ("500 rounds on Ekadashi"). Every student
/// on their roster contributes their own rounds, and the **sum** across the
/// roster is what has to reach the target. The whole roster succeeds together.
///
/// ⚠️ **This replaced a per-student model on 2026-08-14.** The first version
/// showed each student as individually achieved or not. That was a misreading:
/// it made a large target impossible for any one student and turned a shared
/// goal into a list of individual failures. **There is no per-student pass/fail
/// anywhere in this screen** — a student has either contributed rounds or has
/// not submitted yet.
///
/// ⚠️ **Nothing here computes progress.** The running total, the achieved flag
/// and the missed flag are all written server-side by
/// `functions/challenges.js` — two Firestore triggers that fire on a sadhana
/// report write, plus a daily 02:00 IST sweep that closes expired challenges.
/// Every total is updated inside a Firestore transaction, because two students
/// submitting at once would otherwise lose one of the increments.
///
/// ⚠️ **A student's contribution is locked at their first report for the target
/// date** (changed 2026-08-14). A later edit to that report is ignored, so the
/// total only ever grows — a collective figure a guide has already announced to
/// their roster can never change, or be retracted, underneath them.
///
/// Firestore:
///   chantingChallenges/{autoId}                          — created here
///     currentTotal, status ("active"|"achieved"|"missed"), achievedAt, closedAt
///   chantingChallengeContributions/{challengeId}_{uid}    — read-only here
class ChantingChallengeManagerPage extends StatefulWidget {
  const ChantingChallengeManagerPage({super.key});

  @override
  State<ChantingChallengeManagerPage> createState() =>
      _ChantingChallengeManagerPageState();
}

class _ChantingChallengeManagerPageState
    extends State<ChantingChallengeManagerPage> {
  final FirebaseFirestore _firestore = GuideDb.instance;

  /// The signed-in admin's id (the creator id stamped on a challenge).
  String get _selectedGuide => AdminProfileProvider.require().id;

  bool get _isHod => AdminProfileProvider.viewerIsHod;

  bool _sending = false;

  /// Part 2 — HOD guide-selection. Empty means the existing default: no
  /// filter, every student (Part 2 item 4). Irrelevant/unused for a
  /// non-HOD guide, who always creates for their own single roster exactly
  /// as before.
  final Set<String> _selectedGuideIds = <String>{};

  /// The same date-id format the sadhana collections use, so the Cloud
  /// Function matches on a plain string with no parsing or timezone ambiguity.
  String _dateKey(DateTime date) => DateFormat('dd-MM-yyyy').format(date);

  // ---------------------------------------------------------------------------
  // Create + notify
  // ---------------------------------------------------------------------------

  /// Notifies every student on this challenge's roster.
  ///
  /// The server builds the roster for the signed-in admin's role (a Guide's
  /// team, an enabler's own students, or — for a HOD — the picked guides'
  /// students / everyone) and applies each student's own notification
  /// preference. The app no longer reads student tokens or preferences.
  ///
  /// [selectedGuideIds] is the HOD's picked-guides set (Part 2) — empty for
  /// everyone else, and for a HOD explicitly choosing "all students".
  Future<(int sent, int total)> _notifyRoster(
    String name,
    int targetRounds,
    DateTime targetDate,
    Set<String> selectedGuideIds,
  ) async {
    final r = await HierarchyApi.instance.sendStudentNotification({
      'kind': 'chanting_challenge',
      'name': name,
      'targetRounds': targetRounds,
      'targetDate': DateFormat('yyyy-MM-dd').format(targetDate),
      if (_isHod) 'ownerIds': selectedGuideIds.toList(),
    });

    final sent = (r['sent'] as num?)?.toInt() ?? 0;
    final total = (r['total'] as num?)?.toInt() ?? 0;
    final optedOut = (r['optedOut'] as num?)?.toInt() ?? 0;

    // `total` is the notifiable roster, so a student who opted out is not
    // counted as a failure in the "sent to X of Y" summary — they were
    // never a target. `optedOut` is logged rather than surfaced: a guide does
    // not need to know which students muted a category.
    if (optedOut > 0) {
      debugPrint("Challenge notification: $optedOut student(s) opted out");
    }

    return (sent, total);
  }

  Future<void> _openCreateSheet() async {
    final guide = _selectedGuide;

    // Fresh each time the sheet opens, so a selection from a previous
    // challenge never lingers into the next one.
    _selectedGuideIds.clear();

    String name = '';
    String rounds = '';
    DateTime? targetDate;
    String? error;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return GuideDialog(
            title: const Text("New Challenge"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (v) => name = v,
                    decoration: InputDecoration(
                      labelText: "Challenge name",
                      hintText: "e.g. Ekadashi together",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    keyboardType: TextInputType.number,
                    onChanged: (v) => rounds = v,
                    decoration: InputDecoration(
                      labelText: "Target rounds (whole roster)",
                      hintText: "500",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => targetDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: "Target date",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      child: Text(
                        targetDate == null
                            ? "Tap to choose"
                            : DateFormat('dd MMM yyyy').format(targetDate!),
                        style: TextStyle(
                          color: targetDate == null
                              ? context.g.mutedText
                              : context.g.text,
                        ),
                      ),
                    ),
                  ),
                  // HOD-only: pick which guides' rosters this challenge
                  // applies to. Not shown to a regular guide — they always
                  // create for their own single roster, exactly as before.
                  if (_isHod) ...[
                    const SizedBox(height: 12),
                    Text(
                      "Guides (leave empty for all students)",
                      style: TextStyle(
                          fontSize: 12, color: context.g.mutedText),
                    ),
                    const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        // Admins that can own male students (everyone but
                        // Female Enablers), by display name.
                        final guideAdmins = AdminProfileProvider.require()
                            .admins
                            .where((a) => a.role != AdminRole.femaleEnabler)
                            .toList()
                          ..sort((a, b) => a.displayName
                              .toLowerCase()
                              .compareTo(b.displayName.toLowerCase()));
                        final guides = guideAdmins.map((a) => a.id).toList();

                        if (guides.isEmpty) {
                          return Text(
                            "No guides found",
                            style: TextStyle(
                                fontSize: 12, color: context.g.mutedText),
                          );
                        }

                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: guides.map((g) {
                            final selected = _selectedGuideIds.contains(g);
                            return FilterChip(
                              label: Text(AdminProfileProvider.require()
                                      .adminById(g)
                                      ?.displayName ??
                                  g),
                              selected: selected,
                              onSelected: (v) => setDialogState(() {
                                if (v) {
                                  _selectedGuideIds.add(g);
                                } else {
                                  _selectedGuideIds.remove(g);
                                }
                              }),
                              selectedColor: context.g.brass
                                  .withValues(alpha: .15),
                              checkmarkColor: context.g.brass,
                              labelStyle: TextStyle(
                                color: selected
                                    ? context.g.brass
                                    : context.g.text,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        style: TextStyle(
                            fontSize: 12, color: context.g.danger)),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    "This is a group target. Every student assigned to you is "
                    "notified now, and their rounds for that date are added "
                    "together automatically. It succeeds the moment the total "
                    "reaches the target.\n\n"
                    "Each student's first report for that date is what counts "
                    "— later edits to it do not change the total.",
                    style:
                        TextStyle(fontSize: 11.5, color: context.g.mutedText),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: context.g.brass),
                onPressed: () {
                  final parsed = int.tryParse(rounds.trim());
                  if (name.trim().isEmpty) {
                    setDialogState(() => error = "Give the challenge a name");
                    return;
                  }
                  if (parsed == null || parsed <= 0) {
                    setDialogState(
                        () => error = "Target rounds must be a whole number");
                    return;
                  }
                  if (targetDate == null) {
                    setDialogState(() => error = "Choose a target date");
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: Text("Create",
                    style: TextStyle(color: context.g.onPrimary)),
              ),
            ],
          );
        },
      ),
    );

    if (created != true || targetDate == null) return;

    final targetRounds = int.parse(rounds.trim());
    final date = targetDate!;
    final profile = AdminProfileProvider.require();

    setState(() => _sending = true);

    // Snapshot before the sheet's own state is gone (the dialog and its
    // StatefulBuilder are already popped by this point).
    final selectedGuideIds = Set<String>.from(_selectedGuideIds);

    try {
      await _firestore.collection('chantingChallenges').add({
        'name': name.trim(),
        'targetRounds': targetRounds,
        // The string the Cloud Function matches on.
        'targetDateKey': _dateKey(date),
        // Kept alongside it for display, sorting and the deadline sweep.
        'targetDate': Timestamp.fromDate(date),
        // The creator's own id (the screen lists a non-HOD's challenges by it).
        'guideId': guide,
        'createdBy': guide,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
        // Seeded explicitly so the trigger's transaction always has a number
        // to add its delta to, rather than treating a missing field as zero.
        'currentTotal': 0,
        // Additive (Rule 12 — justified in functions/challenges.js, the
        // field's first read site). Only ever set on an HOD-created
        // challenge; a guide's own challenge never carries either field, so
        // `checkChallengesFor`'s two new OR clauses simply never match it —
        // the guide-created path is otherwise untouched.
        // A report counts toward a challenge when the student's guideId is in
        // `guideIds` (functions/challenges.js), so a Guide's Male Enablers
        // must be listed next to him. A HOD keeps his picked guides / all.
        'guideIds': profile.isHod
            ? selectedGuideIds.toList()
            : profile.isGuide
                ? [guide, ...profile.myMaleEnablers.map((a) => a.id)]
                : [guide],
        if (_isHod && selectedGuideIds.isEmpty) 'allStudents': true,
      });

      var sent = 0;
      var total = 0;
      var notifyFailed = false;
      try {
        final res = await _notifyRoster(
            name.trim(), targetRounds, date, selectedGuideIds);
        sent = res.$1;
        total = res.$2;
      } catch (_) {
        // The challenge itself is saved; only the push failed.
        notifyFailed = true;
      }

      if (!mounted) return;
      setState(() => _sending = false);
      showSnackbar(
        context,
        notifyFailed
            ? "Challenge created · could not notify students"
            : sent == total
                ? "Challenge created · $sent students notified"
                : "Challenge created · notified $sent of $total "
                    "(the rest have no notification token)",
        context.g.success,
        Icons.check_circle,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showSnackbar(
          context, "Could not create the challenge", context.g.danger, Icons.error);
    }
  }

  /// Master Task Part 1 (2026-09-10) — permanently deletes a challenge:
  /// the challenge doc itself (which carries `summarySeenBy` as one of its
  /// own fields — nothing separate to clean up there) AND every one of
  /// its `chantingChallengeContributions` rows (a top-level collection,
  /// not a subcollection, so it needs its own explicit query+delete —
  /// same shape `StudentDeletion.dart`'s own `_deleteWhereEquals` already
  /// uses for exactly this collection when a STUDENT is deleted, just
  /// filtered on `challengeId` here instead of `studentUid`; that helper
  /// is file-private to `StudentDeletion.dart` so it cannot be imported,
  /// but the pattern — query by equality, batch-delete the matches — is
  /// reused, not reinvented).
  ///
  /// ⚠️ **Never touches `sadhana-reports`/`hostel-sadhana` (Rule 14/15).**
  /// A student's own submitted report is the source data a contribution
  /// was computed FROM; deleting the challenge only removes this
  /// feature's own bookkeeping about it, never the report itself.
  ///
  /// ⚠️ **Permission enforced here, in code — not only by which cards the
  /// list query happens to show.** A non-HOD guide's own challenges are
  /// `createdBy == guide`; an HOD-created challenge that reaches a guide's
  /// roster via `guideIds`/`allStudents` is NOT theirs to delete even
  /// though it appears in their list (exactly the same "visible in the
  /// list, but not yours to mutate" gap `_setStatus` already had — this
  /// function does not share that gap).
  Future<void> _deleteChallenge(
    String docId,
    String name,
    Map<String, dynamic> data,
  ) async {
    final createdBy = (data['createdBy'] ?? '').toString();
    final guide = _selectedGuide;

    if (!_isHod && createdBy != guide) {
      showSnackbar(
        context,
        "Only the guide who created this challenge, or the HOD, can delete it.",
        Colors.red,
        Icons.lock_outline,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: const Text("Delete this challenge?"),
        content: Text(
          "\"${name.isEmpty ? '(untitled)' : name}\" and every student's "
          "contribution to it will be permanently deleted. This cannot be "
          "undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.g.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                Text("Delete", style: TextStyle(color: context.g.onPrimary)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // Bounded by one guide's roster in practice — nowhere near
      // Firestore's 500-write batch limit, so no chunking is needed
      // (unlike `StudentDeletion.dart`'s own helper, which has to handle
      // an unbounded query result across a student's entire history).
      final contribSnap = await StudentScope.current().historyGet(
        'chantingChallengeContributions',
        extraEquals: {'challengeId': docId},
      );

      final batch = _firestore.batch();
      for (final doc in contribSnap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_firestore.collection('chantingChallenges').doc(docId));
      await batch.commit();

      if (!mounted) return;
      showSnackbar(
          context, "Challenge deleted", context.g.success, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not delete the challenge", Colors.red,
          Icons.error);
    }
  }

  /// Closes an active challenge early, or reopens one the sweep closed.
  ///
  /// `achieved` is final and offers no action — a target that was reached
  /// cannot be un-reached. Reopening a missed challenge clears `closedAt` so
  /// the record does not claim two contradictory things at once.
  Future<void> _setStatus(String docId, String status) async {
    try {
      await _firestore.collection('chantingChallenges').doc(docId).update({
        'status': status,
        'closedAt': status == 'missed'
            ? FieldValue.serverTimestamp()
            : FieldValue.delete(),
      });
      if (!mounted) return;
      showSnackbar(context, status == 'active' ? "Reopened" : "Closed as missed",
          context.g.success, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not update", Colors.red, Icons.error);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// The three collective states. Distinct colours so a guide can scan a list
  /// without reading labels.
  (Color colour, IconData icon, String label) _statusStyle(
      String status) {
    switch (status) {
      case 'achieved':
        return (context.g.success, Icons.emoji_events, "Achieved");
      case 'missed':
        return (context.g.warning, Icons.timer_off_outlined, "Missed");
      default:
        return (context.g.brass, Icons.bolt, "Active");
    }
  }

  /// A guide's own challenge now also carries `guideIds` (his team), so the
  /// "Guides: ..." label is only meaningful on a HOD-created challenge.
  bool _createdByHod(String creatorId) {
    final profile = AdminProfileProvider.require();
    if (creatorId == profile.id) return profile.isHod;
    return profile.adminById(creatorId)?.role == AdminRole.hod;
  }

  Widget _challengeCard(String docId, Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString();
    final target = data['targetRounds'] is num
        ? (data['targetRounds'] as num).toInt()
        : 0;
    final total = data['currentTotal'] is num
        ? (data['currentTotal'] as num).toInt()
        : 0;
    final status = (data['status'] ?? 'active').toString();
    final (colour, icon, label) = _statusStyle(status);

    final ts = data['targetDate'];
    final dateText = ts is Timestamp
        ? DateFormat('dd MMM yyyy').format(ts.toDate())
        : (data['targetDateKey'] ?? '').toString();

    // Clamped so an over-achieved total does not overflow the bar.
    final fraction = target <= 0 ? 0.0 : (total / target).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colour.withValues(alpha: .35)),
        boxShadow: context.g.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name.isEmpty ? "(untitled)" : name,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 12, color: colour),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: colour,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // The collective figure, stated as a sum — never as a per-student
          // score.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                "$total",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colour,
                ),
              ),
              Text(
                " / $target rounds together",
                style: TextStyle(fontSize: 12.5, color: context.g.mutedText),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: context.g.chipBackground,
              valueColor: AlwaysStoppedAnimation<Color>(colour),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.event, size: 15, color: context.g.mutedText),
              const SizedBox(width: 5),
              Text(dateText,
                  style:
                      TextStyle(fontSize: 12.5, color: context.g.text)),
              // Multi-guide/all-students metadata is shown to any viewer who
              // can see this card — including a guide seeing an HOD
              // challenge that reaches their own roster via `guideIds`
              // (Part 2) — since "who else is in this" is useful information
              // regardless of role. The plain singular "Guide: X" line stays
              // HOD-only, as it already was: a regular guide's own
              // single-guide challenges need no such label.
              if (data['allStudents'] == true) ...[
                const SizedBox(width: 12),
                Text("All students",
                    style:
                        TextStyle(fontSize: 11, color: context.g.mutedText)),
              ] else if (_createdByHod((data['createdBy'] ?? '').toString()) &&
                  data['guideIds'] is List &&
                  (data['guideIds'] as List).isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  "Guides: ${(data['guideIds'] as List).map((g) => AdminProfileProvider.require().adminById('$g')?.displayName ?? '$g').join(', ')}",
                  style:
                      TextStyle(fontSize: 11, color: context.g.mutedText),
                ),
              ] else if (_isHod &&
                  (data['guideId'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                    "Guide: ${AdminProfileProvider.require().adminById('${data['guideId']}')?.displayName ?? data['guideId']}",
                    style:
                        TextStyle(fontSize: 11, color: context.g.mutedText)),
              ],
            ],
          ),
          // Was a `Row(mainAxisAlignment: spaceBetween)` — on a narrow
          // screen, "Who contributed" plus Close/Reopen plus the delete
          // icon can exceed the card's available width, and a release
          // build silently CLIPS a `Row` overflow (no yellow/black banner
          // like debug mode shows) instead of erasing it — the clipped
          // side is whichever child `spaceBetween` pushed to the far
          // edge, which for this row is the delete button. Same overflow
          // bug class already confirmed elsewhere in this app (Part 4's
          // Submissions-tile report). `Wrap` degrades to a second line
          // instead of clipping, so every action stays reachable
          // regardless of device width — the gating logic, the dialog,
          // and the button itself are unchanged (Part 3: fix the real
          // cause, do not add a second delete button).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => ChallengeContributionsPage(
                      challengeId: docId,
                      challengeName: name,
                      target: target,
                      total: total,
                    ),
                    transitionsBuilder: (_, animation, __, child) =>
                        FadeTransition(opacity: animation, child: child),
                  ),
                ),
                icon: const Icon(Icons.groups, size: 16),
                label: const Text("Who contributed"),
                style: TextButton.styleFrom(
                    foregroundColor: context.g.text),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `achieved` is deliberately final — no close/reopen
                  // action offered (unchanged by this task). Delete
                  // (Master Task Part 1) is available in every status —
                  // before, during, or after — per the product owner's
                  // explicit instruction, and gated in code inside
                  // [_deleteChallenge] itself, not only by this button's
                  // visibility.
                  if (status == 'active')
                    TextButton(
                      onPressed: () => _setStatus(docId, 'missed'),
                      style: TextButton.styleFrom(
                          foregroundColor: context.g.warning),
                      child: const Text("Close"),
                    )
                  else if (status == 'missed')
                    TextButton(
                      onPressed: () => _setStatus(docId, 'active'),
                      style: TextButton.styleFrom(
                          foregroundColor: context.g.brass),
                      child: const Text("Reopen"),
                    ),
                  if (_isHod || (data['createdBy'] ?? '').toString() ==
                      _selectedGuide)
                    IconButton(
                      tooltip: "Delete challenge",
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: context.g.danger,
                      // Shrunk from the default 48x48 min tap target —
                      // reduces how easily this row's total width tips
                      // into overflow on narrow screens in the first
                      // place, while 40x40 stays a reasonable tap size.
                      constraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                      padding: EdgeInsets.zero,
                      onPressed: () => _deleteChallenge(docId, name, data),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        final guide = _selectedGuide;

        return GuideScaffold(
          appBar: GuideAppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Chanting Challenges",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 20,
              ),
            )),
          floatingActionButton: FloatingActionButton.extended(
                  backgroundColor: context.g.brass,
                  onPressed: _sending ? null : _openCreateSheet,
                  icon: _sending
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: const GuideBusyDot(),
                        )
                      : Icon(Icons.add, color: context.g.onPrimary),
                  label: Text(
                    _sending ? "Notifying…" : "New Challenge",
                    style: TextStyle(color: context.g.onPrimary),
                  ),
                ),
          body: StreamBuilder<QuerySnapshot>(
                  // HOD reads every challenge; everyone else only the ones
                  // they created (the rules can prove `guideId == me`).
                  stream: (_isHod
                          ? _firestore.collection('chantingChallenges')
                          : _firestore
                              .collection('chantingChallenges')
                              .where('guideId', isEqualTo: guide))
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text("Could not load challenges",
                            style:
                                TextStyle(color: colorProvider.secondColor)),
                      );
                    }
                    if (!snapshot.hasData) {
                      return GuideWait(snapshot: snapshot);
                    }

                    final docs = snapshot.data!.docs.toList()
                      // Sorted in Dart so no composite index is needed
                      // alongside the guideId filter.
                      ..sort((a, b) {
                        final da =
                            (a.data() as Map<String, dynamic>)['targetDate'];
                        final dbb =
                            (b.data() as Map<String, dynamic>)['targetDate'];
                        if (da is! Timestamp) return 1;
                        if (dbb is! Timestamp) return -1;
                        return dbb.compareTo(da);
                      });

                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(34),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.self_improvement,
                                  size: 46, color: context.g.mutedText),
                              const SizedBox(height: 14),
                              Text(
                                "No challenges yet",
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colorProvider.secondColor),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Set a rounds target for a date. Your students' "
                                "rounds are added together automatically, and "
                                "the roster reaches it as one.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: context.g.mutedText),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
                      children: docs
                          .map((d) => _challengeCard(
                              d.id, d.data() as Map<String, dynamic>))
                          .toList(),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Who contributed to one challenge, and how much.
///
/// ⚠️ **Not a scoreboard.** A student appears here with the rounds they
/// submitted for the target date, or does not appear at all because they have
/// not submitted yet. There is no pass, no fail and no ranking — the only
/// verdict in this feature belongs to the roster as a whole.
///
/// Each figure is **locked at the student's first report** for the target date;
/// a later edit to that report does not change it, so what is shown here is
/// always exactly what was counted into the total.
class ChallengeContributionsPage extends StatelessWidget {
  final String challengeId;
  final String challengeName;
  final int target;
  final int total;

  const ChallengeContributionsPage({
    super.key,
    required this.challengeId,
    required this.challengeName,
    required this.target,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              challengeName.isEmpty ? "Contributions" : challengeName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 18,
              ),
            )),
          body: StreamBuilder<QuerySnapshot>(
            // challengeId equality + the viewer's student scope (HOD: all).
            stream: StudentScope.current().historyStream(
              'chantingChallengeContributions',
              extraEquals: {'challengeId': challengeId},
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return GuideWait(snapshot: snapshot);
              }

              final docs = snapshot.data!.docs.toList()
                ..sort((a, b) {
                  final ra = (a.data() as Map<String, dynamic>)['rounds'];
                  final rb = (b.data() as Map<String, dynamic>)['rounds'];
                  final ia = ra is num ? ra.toInt() : 0;
                  final ib = rb is num ? rb.toInt() : 0;
                  return ib.compareTo(ia);
                });

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      "$total of $target rounds, from ${docs.length} "
                      "student${docs.length == 1 ? '' : 's'} so far. "
                      "Anyone not listed has not submitted a report for this "
                      "date yet.\n\n"
                      "Each figure is from that student's first report for the "
                      "date and does not change afterwards.",
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: colorProvider.secondColor.withValues(alpha: .8),
                      ),
                    ),
                  ),
                  if (docs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        "No contributions yet.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: context.g.mutedText),
                      ),
                    ),
                  ...docs.map((d) {
                    final x = d.data() as Map<String, dynamic>;
                    final rounds =
                        x['rounds'] is num ? (x['rounds'] as num).toInt() : 0;
                    final updated = x['updatedAt'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: context.g.surface,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: context.g.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.g.brass.withValues(alpha: .10),
                            ),
                            child: Center(
                              child: Text(
                                "$rounds",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: context.g.brass,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (x['studentName'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                if (updated is Timestamp)
                                  Text(
                                    DateFormat('dd MMM yyyy, hh:mm a')
                                        .format(updated.toDate()),
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: context.g.mutedText),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            rounds == 1 ? "round" : "rounds",
                            style: TextStyle(
                                fontSize: 11.5, color: context.g.mutedText),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
