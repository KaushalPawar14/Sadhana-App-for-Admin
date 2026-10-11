import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Home/Calendar.dart';
import '../Services/HierarchyApi.dart';
import '../Services/MissingReportNotification.dart';
import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/SadhanaReportSource.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';

/// One scoped student's own submission status for today — just enough to
/// show them in either list and, if tapped, open their own
/// [CalendarPage] (Master Task Part 5 item 4).
typedef _StudentSubmission = ({String name, String role, String uid});

/// Submission status overview (Phase 6, half 1, item 1; reworked and moved
/// here to be the ONE place this lives — Master Task Part 5).
///
/// Shows ALL of the viewer's scoped students for today, in two groups: NOT
/// SUBMITTED first (item 3 — "this is what needs action"), SUBMITTED
/// beneath (so the guide can cross-check). Tapping any student — in either
/// group — opens their own [CalendarPage] (item 4).
///
/// Scoping: the student list is [StudentScope.studentsGet] — a HOD sees every
/// student, a Guide his team plus unassigned males, an enabler his own plus the
/// unassigned of his gender. Reminders go through the server
/// (`sendStudentNotification`, kind `submission_nudge`).
///
/// Item 7 — the data: NEITHER list is derived from
/// `NotificationManager().missingUsernames` anymore. That cache is keyed
/// off the `notification` collection (one doc per FCM-token registration),
/// not `users` — a scoped student who has a `users` doc but, for whatever
/// reason, no `notification` doc yet would never be considered by
/// `MissingReportService.fetchMissingTokens()` at all, so computing
/// "submitted = every scoped student minus every missing one" could
/// silently and wrongly count them as submitted. Instead, this screen
/// checks EVERY scoped student's own report doc directly — same
/// today's-date-id (`MissingReportService.getTodayDateId()`) and the same
/// role-based collection choice (`hostel-sadhana` for `role == 'Stay at
/// Hostel'`, else `sadhana-reports`) that service already established —
/// so every scoped student lands in EXACTLY one of the two groups, never
/// neither.
class SubmissionStatusPage extends StatefulWidget {
  const SubmissionStatusPage({super.key});

  @override
  State<SubmissionStatusPage> createState() => _SubmissionStatusPageState();
}

class _SubmissionStatusPageState extends State<SubmissionStatusPage> {
  bool _loading = true;
  String? _guide;
  bool _isHod = false;

  /// Scoped students with no report for today (Part 5 item 3 — shown
  /// first, "this is what needs action").
  List<_StudentSubmission> _notSubmitted = [];

  /// Scoped students who HAVE submitted today (shown beneath, "so the
  /// guide can cross-check").
  List<_StudentSubmission> _submitted = [];

  /// Total students in scope, so the summary reads "3 of 12" rather than
  /// "3".
  int get _inScope => _notSubmitted.length + _submitted.length;

  /// Names currently mid-send, so a tapped button can show progress.
  final Set<String> _sending = {};

  /// Bulk-send progress. `_bulkDone` counts attempts, `_bulkSent` counts the
  /// ones that actually delivered — they differ when a student has no token.
  bool _bulkRunning = false;
  int _bulkTotal = 0;
  int _bulkDone = 0;
  int _bulkSent = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final profile = AdminProfileProvider.require();
    final guide = profile.displayName;
    final isHod = profile.isHod;

    List<_StudentSubmission> notSubmitted = [];
    List<_StudentSubmission> submitted = [];

    try {
      final snap = await StudentScope(profile).studentsGet();

      final today = MissingReportService().getTodayDateId();

      final checks = <Future<void>>[];
      for (final doc in snap.docs) {
        final name = (doc.data()['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final role = (doc.data()['role'] ?? '').toString();
        final uid = doc.id;

        checks.add(Future(() async {
          // Master Task 2026-09-11 — checked against BOTH collections
          // rather than picking one by current role, same reason as
          // `MissingReportService.fetchMissingTokens()`'s own update: a
          // same-day residence change must not make an already-submitted
          // report look missing.
          final report = await fetchMergedDateReport(name, today);

          final entry = (name: name, role: role, uid: uid);
          if (report != null) {
            submitted.add(entry);
          } else {
            notSubmitted.add(entry);
          }
        }));
      }

      await Future.wait(checks);
      notSubmitted.sort((a, b) => a.name.compareTo(b.name));
      submitted.sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      // A failed read must not blank the screen with a WRONG answer (e.g.
      // claiming "everyone submitted") — both lists stay empty, same
      // fail-closed spirit the old code had: a guide sees nothing rather
      // than another guide's data or a guess.
      notSubmitted = [];
      submitted = [];
    }

    if (!mounted) return;
    setState(() {
      _guide = guide;
      _isHod = isHod;
      _notSubmitted = notSubmitted;
      _submitted = submitted;
      _loading = false;
    });
  }

  /// The one and only send path in this screen — used by the per-student
  /// button and by Remind All alike (kind `submission_nudge`; the server builds
  /// the message and applies each student's own preference). Returns how many
  /// notifications actually went out.
  ///
  /// Never throws: a failed send returns 0 so a bulk run continues through the
  /// rest of the list. The server accepts at most 200 students per call, so
  /// callers pass chunks.
  Future<int> _sendReminders(List<String> uids) async {
    if (uids.isEmpty) return 0;
    try {
      final r = await HierarchyApi.instance.sendStudentNotification(
        uids.length == 1
            ? {'kind': 'submission_nudge', 'studentUid': uids.first}
            : {'kind': 'submission_nudge', 'studentUids': uids},
      );
      return (r['sent'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Nudges one student.
  Future<void> _remind(_StudentSubmission student) async {
    final name = student.name;
    setState(() => _sending.add(name));

    final sent = await _sendReminders([student.uid]) > 0;

    if (mounted) {
      showSnackbar(
        context,
        sent ? "Reminder sent to $name" : "Could not send to $name",
        sent ? Colors.green : Colors.red,
        sent ? Icons.check_circle : Icons.error,
      );
      setState(() => _sending.remove(name));
    }
  }

  /// Nudges everyone currently listed as not-submitted, in chunks of 200.
  ///
  /// Iterates the already-scoped `_notSubmitted` list — scoping is not
  /// re-evaluated here, so an admin can never reach beyond their own
  /// students. Chunks run sequentially and independently: one failure does
  /// not stop the rest, and the tally reports what actually went out.
  Future<void> _remindAll() async {
    final targets = _notSubmitted.map((s) => s.uid).toList();
    if (targets.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: const Text("Remind everyone?"),
        content: Text(
          "Send today's sadhana reminder to all ${targets.length} "
          "student${targets.length == 1 ? '' : 's'} listed below?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Send to all"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _bulkRunning = true;
      _bulkTotal = targets.length;
      _bulkDone = 0;
      _bulkSent = 0;
    });

    const chunkSize = 200;
    for (var i = 0; i < targets.length; i += chunkSize) {
      final chunk = targets.sublist(
          i, i + chunkSize > targets.length ? targets.length : i + chunkSize);
      final sent = await _sendReminders(chunk);
      if (!mounted) return;
      setState(() {
        _bulkDone += chunk.length;
        _bulkSent += sent;
      });
    }

    if (!mounted) return;

    final sent = _bulkSent;
    final total = _bulkTotal;
    setState(() => _bulkRunning = false);

    showSnackbar(
      context,
      sent == total
          ? "Reminder sent to all $total"
          : "Sent to $sent of $total — the rest have no notification token",
      sent == total ? context.g.success : context.g.warning,
      sent == total ? Icons.check_circle : Icons.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(
            title: Text("Submission Status"),
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
                      if (_inScope == 0)
                        _emptyCard("No students in scope yet")
                      else ...[
                        // NOT SUBMITTED — first, "this is what needs
                        // action" (Part 5 item 3).
                        if (_notSubmitted.isNotEmpty) ...[
                          _remindAllBar(),
                          const SizedBox(height: 12),
                          ..._notSubmitted
                              .map((s) => _studentCard(s, showRemind: true)),
                        ] else
                          _emptyCard("Everyone has submitted today"),
                        // SUBMITTED — beneath, "so the guide can
                        // cross-check" (Part 5 item 3).
                        if (_submitted.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, left: 2),
                            child: Text(
                              "SUBMITTED (${_submitted.length})",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: colorProvider.secondColor
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          ..._submitted
                              .map((s) => _studentCard(s, showRemind: false)),
                        ],
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _summaryCard() {
    final today = DateFormat('dd MMM yyyy').format(DateTime.now());
    final allSubmitted = _inScope > 0 && _notSubmitted.isEmpty;
    return GuideSummaryBanner(
      tone: allSubmitted ? GuideTone.good : GuideTone.warn,
      icon: allSubmitted ? Icons.check_circle_outline : Icons.pending_actions_outlined,
      title: "${_notSubmitted.length} not submitted",
      lines: [
        _inScope > 0 ? "out of $_inScope students · $today" : today,
        _isHod
            ? "All students (HOD view)"
            : "Students assigned to ${_guide ?? 'you'}",
      ],
    );
  }

  /// Remind All, with live progress while a run is in flight.
  Widget _remindAllBar() {
    if (_bulkRunning) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.g.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: const GuideBusyDot(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                "Sending… $_bulkDone of $_bulkTotal"
                "${_bulkDone > _bulkSent ? ' · $_bulkSent delivered' : ''}",
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _remindAll,
        icon: const Icon(Icons.campaign, size: 18),
        label: Text(
          "Remind all ${_notSubmitted.length}",
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.g.warning,
          foregroundColor: context.g.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: context.g.mutedText, fontSize: 14),
        ),
      ),
    );
  }

  /// Master Task Part 5 item 4 — tapping the card (anywhere except the
  /// Remind button itself) opens this student's own [CalendarPage], so a
  /// guide can verify what was actually submitted. [showRemind] is the
  /// only difference between the two groups' rows — a submitted student
  /// has nothing to be reminded about.
  Widget _studentCard(_StudentSubmission student, {required bool showRemind}) {
    final sending = _sending.contains(student.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CalendarPage(
              username: student.name,
              role: student.role,
              studentUid: student.uid,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: showRemind
                      ? context.g.warning.withValues(alpha: .14)
                      : context.g.success.withValues(alpha: .14),
                ),
                child: Icon(
                  showRemind ? Icons.person_outline : Icons.check,
                  size: 18,
                  color: showRemind ? context.g.warning : context.g.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  student.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              if (showRemind)
                sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: const GuideBusyDot(),
                      )
                    : TextButton.icon(
                        onPressed: () => _remind(student),
                        icon: const Icon(Icons.notifications_active, size: 16),
                        label: const Text("Remind"),
                      )
              else
                Icon(Icons.chevron_right, size: 18, color: context.g.mutedText),
            ],
          ),
        ),
      ),
    );
  }
}
