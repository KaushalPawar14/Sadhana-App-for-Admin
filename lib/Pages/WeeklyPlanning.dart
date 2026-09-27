import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Services/UpdateFCM.dart';
import '../utils/CalendarQueries.dart';
import '../utils/ColorProvider.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/GuideRoster.dart';
import '../utils/PlanningQueries.dart';
import 'GoalWeeklyPhasePage.dart';
import 'OverdueAssociations.dart';

/// Monday weekly planning (Phase 6, half 1, item 3).
///
/// A composition, not a fourth source of truth. Originally three sections;
/// two remain here, fully intact and byte-for-byte unchanged (Rule 3 —
/// this file's task list is additive only):
///
///   1. Follow-ups due this week — the only new logic, filtering
///      `approvedSummary.followUpDate` on approved `interactionLogs`.
///   2. Overdue associations — reuses `associationOverdueSince()` from
///      `PlanningQueries.dart`, the same predicate the full dashboard uses.
///
/// The former section 2, "Missing submissions," MOVED to the Guide
/// Calendar page's own today panel (Calendar UI redesign, Part 3 item 3) —
/// it now lives in exactly one place, keyed to whichever day is selected
/// there (defaulting to today), rather than duplicated here as an
/// always-today-only summary. `NotificationManager().missingUsernames` and
/// `scopedStudentNames` are read from `GuideCalendarPage.dart` now; this
/// file no longer references either.
///
/// Section 2 shows a count and a short list, then hands off to its own
/// dashboard. This screen deliberately has no Remind buttons and no deep
/// links into records — it is an overview, not a replacement.
///
/// No new collection (Rule 12). Scoping follows the goal/follow-up
/// sections: the HOD sees every guide's work, anyone else sees only their
/// own.
///
/// ---------------------------------------------------------------------------
/// 0. Compound targets — [_goalSection], now at the TOP of the page
/// ---------------------------------------------------------------------------
/// Shows `_guide`'s OWN active compound targets (not every guide's, even
/// for the HOD) — compound targets are inherently per-guideId, and this
/// section's job is "what does THIS signed-in person need to do this
/// week", the same framing every other section already has. An HOD
/// browsing OTHER guides' targets already has `CompoundGoalHodReview.dart`
/// for that — a different, deliberately separate concern from this
/// screen's own-week summary. Renders NOTHING (not even an empty shell)
/// when `_guide` has no active compound target — same "costs nothing when
/// irrelevant" property `GoalProgressBar.dart` already has.
///
/// Moved above sections 1-3 (task-list phase model task, Part 6 item 2) —
/// those three keep their own original relative order untouched (Rule 3).
/// Each target renders as an [ExpansionTile] — the SAME expand/collapse
/// widget this app already uses elsewhere (`TopWeekResults.dart`,
/// `BookLinkManager.dart`, `PodcastLinkManager.dart`), not a new pattern
/// invented for this screen (Rule 1). Collapsed: name, phase, and an
/// overall "N/M tasks done" progress bar. Expanded: the full per-task
/// checklist with real live progress, same discipline as
/// `GoalWeeklyPhasePage.dart`'s own checklist.
///
/// ---------------------------------------------------------------------------
/// [_sectionShell] — ALL FOUR top-level sections collapsible (consistent-
/// collapsible-sections task, this continuation)
/// ---------------------------------------------------------------------------
/// [_sectionShell] itself is now the SAME [ExpansionTile] card every
/// section already funnels through — a title row (icon, title, count
/// badge) always visible, tap anywhere on it to reveal the real content
/// underneath. This is the ONE shared chrome widget behind
/// [_followUpSection], [_missingSection], [_overdueSection], AND this
/// section's own outer "Your targets this week" wrapper — extending it
/// once made all four collapsible with no changes to any of those four
/// functions' own bodies (presentation-only, Rule 3 — no query/data logic
/// touched anywhere). Collapsed by default on every section (a guide scans
/// four headlines first, then opens whichever needs attention) — a
/// reasonable default, easily swapped for "auto-expand the most urgent
/// one" later if the product owner prefers that instead. The individual
/// target cards inside THIS section (one level deeper — [_goalTargetCard])
/// keep their own separate, pre-existing [ExpansionTile] styling
/// unchanged; they were never one of the four top-level sections this task
/// was about.
class WeeklyPlanningPage extends StatefulWidget {
  const WeeklyPlanningPage({super.key});

  @override
  State<WeeklyPlanningPage> createState() => _WeeklyPlanningPageState();
}

class _WeeklyPlanningPageState extends State<WeeklyPlanningPage> {
  String? _guide;
  bool _isHod = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final guide = await UpdateTokenService().getSavedGuide();

    if (!mounted) return;
    setState(() {
      _guide = guide;
      _isHod = guide == kHodGuideId;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final week = currentWeekRange();

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            iconTheme: IconThemeData(color: colorProvider.secondColor),
            title: Text(
              "This Week",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _weekHeader(week),
                      const SizedBox(height: 18),
                      // Master Task Part 5 — calendar context, at the VERY
                      // TOP (above the goal section and the three original
                      // sections, all of which keep their own relative
                      // order beneath it unchanged — Rule 3). Renders
                      // NOTHING when there's nothing current or upcoming —
                      // same "costs nothing when irrelevant" property
                      // `_goalSection` already has.
                      _calendarContextSection(),
                      _goalSection(),
                      _followUpSection(week),
                      const SizedBox(height: 18),
                      _overdueSection(),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _weekHeader(({DateTime start, DateTime end}) week) {
    final fmt = DateFormat('dd MMM');
    // end is exclusive, so the last day shown is the day before it.
    final lastDay = week.end.subtract(const Duration(days: 1));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade300],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, color: Colors.white, size: 34),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${fmt.format(week.start)} – ${fmt.format(lastDay)}",
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _isHod
                      ? "All guides (HOD view)"
                      : "Your students · ${_guide ?? ''}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Follow-ups due this week — the only new query in this screen
  // ---------------------------------------------------------------------------

  Widget _followUpSection(({DateTime start, DateTime end}) week) {
    return StreamBuilder<QuerySnapshot>(
      stream: scopedInteractionLogsStream(_guide ?? ''),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _sectionShell(
            icon: Icons.event_repeat,
            colour: Colors.deepPurple,
            title: "Follow-ups due",
            count: null,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        // status and the date range are matched in Dart — a compound query
        // would need a composite index.
        final due = <({String student, DateTime when, String action})>[];

        for (final doc in snapshot.data?.docs ?? []) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['status'] != 'approved') continue;

          final summary = data['approvedSummary'];
          if (summary is! Map<String, dynamic>) continue;

          final raw = summary['followUpDate'];
          if (!fallsInRange(raw, week.start, week.end)) continue;

          due.add((
            student: (data['studentName'] ?? 'Unknown').toString(),
            when: (raw as Timestamp).toDate(),
            action: (summary['recommendedNextAction'] ?? '').toString(),
          ));
        }

        due.sort((a, b) => a.when.compareTo(b.when));

        return _sectionShell(
          icon: Icons.event_repeat,
          colour: Colors.deepPurple,
          title: "Follow-ups due",
          count: due.length,
          child: due.isEmpty
              ? _emptyLine("Nothing scheduled this week")
              : Column(
                  children: due.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 58,
                            child: Text(
                              DateFormat('EEE dd').format(item.when),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.deepPurple.shade700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.student,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (item.action.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.action,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Overdue associations — reused predicate, then handed off. (Missing
  // submissions, formerly section 2 here, moved to the calendar page's own
  // today panel — Calendar UI redesign Part 3 item 3 — so it lives in
  // exactly one place, not two.)
  // ---------------------------------------------------------------------------

  Widget _overdueSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: scopedAssociationsStream(_guide ?? ''),
      builder: (context, snapshot) {
        final waiting = snapshot.connectionState == ConnectionState.waiting;

        final overdue = <({String student, int days})>[];

        if (!waiting) {
          for (final doc in snapshot.data?.docs ?? []) {
            final data = doc.data() as Map<String, dynamic>;
            final since = associationOverdueSince(data);
            if (since == null) continue;
            overdue.add((
              student: (data['studentName'] ?? 'Unknown').toString(),
              days: daysOverdue(since),
            ));
          }
          overdue.sort((a, b) => b.days.compareTo(a.days));
        }

        return _sectionShell(
          icon: Icons.event_busy,
          colour: Colors.red,
          title: "Overdue meetings",
          count: waiting ? null : overdue.length,
          onOpen: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OverdueAssociationsPage()),
          ),
          openLabel: "Open Overdue Associations",
          child: waiting
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: CircularProgressIndicator()),
                )
              : overdue.isEmpty
                  ? _emptyLine("Nothing overdue")
                  : Column(
                      children: overdue.take(5).map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.student,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                item.days == 1
                                    ? "1 day"
                                    : "${item.days} days",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // -1. Calendar context (Master Task Part 5) — the most important section:
  // everything relevant from the Guide Calendar, without opening it.
  // ---------------------------------------------------------------------------

  /// Two things, clearly distinguished (Part 5 item 2):
  ///   - HAPPENING NOW: any event whose range covers today, or a single-day
  ///     event today ([eventsHappeningNow]).
  ///   - COMING UP: events starting within the next 7 days
  ///     ([eventsComingUp]).
  /// Renders NOTHING (not even an empty shell) when both are empty (item
  /// 4) — same "costs nothing when irrelevant" property [_goalSection]
  /// already has, checked BEFORE [_sectionShell] (which always renders its
  /// own chrome) is ever reached, same reasoning as that section's own
  /// early return.
  ///
  /// Defaults to EXPANDED (item 6's own recommendation) — unlike every
  /// other section here, which default to collapsed so a guide scans four
  /// headlines first. This section is different: it's un-actionable at a
  /// glance in collapsed form (a bare count doesn't say WHAT is happening,
  /// only that something is), and it's exactly the "you are currently in
  /// exam week" fact a guide most needs before doing anything else on this
  /// page — worth the extra vertical space by default, with the SAME
  /// collapse affordance every other section has if a guide wants it out
  /// of the way on a later visit.
  Widget _calendarContextSection() {
    return FutureBuilder<List<CalendarEvent>>(
      // A guide's own visible events — the SAME visibility rule
      // `GuideCalendarPage` itself reads (every mandatory event, plus this
      // guide's own personal ones); no new query shape.
      future: visibleEventsFor(_guide ?? ''),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();

        final happeningNow = eventsHappeningNow(snap.data!);
        final comingUp = eventsComingUp(snap.data!);
        if (happeningNow.isEmpty && comingUp.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _sectionShell(
            icon: Icons.campaign,
            colour: Colors.indigo,
            title: "Calendar",
            count: happeningNow.length + comingUp.length,
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (happeningNow.isNotEmpty) ...[
                  _calendarSubHeader("HAPPENING NOW", Colors.red.shade700),
                  ...happeningNow.map(_calendarEventRow),
                ],
                if (happeningNow.isNotEmpty && comingUp.isNotEmpty)
                  const SizedBox(height: 10),
                if (comingUp.isNotEmpty) ...[
                  _calendarSubHeader("COMING UP", Colors.indigo.shade700),
                  ...comingUp.map(_calendarEventRow),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _calendarSubHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: color),
      ),
    );
  }

  /// Shows the type and note, not just the title (item 3) — a guide needs
  /// to know what an event actually MEANS for their week, not just that
  /// something is on the calendar.
  Widget _calendarEventRow(CalendarEvent e) {
    final dateText = e.isMultiDay
        ? "${DateFormat('dd MMM').format(e.eventDate)} – "
            "${DateFormat('dd MMM').format(e.effectiveEndDate)}"
        : DateFormat('dd MMM').format(e.eventDate);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              dateText,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.indigo.shade700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        kEventTypeLabels[e.type] ?? e.type,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo.shade700),
                      ),
                    ),
                  ],
                ),
                if (e.note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    e.note,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 0. Compound targets — the current phase's task checklist, expandable
  // ---------------------------------------------------------------------------

  Widget _goalSection() {
    return StreamBuilder<List<CompoundTarget>>(
      stream: compoundTargetsStream(_guide ?? ''),
      builder: (context, snap) {
        // `totalPhases > 0` — a target whose plan is still generating has no
        // current phase to summarize yet; nothing to show for it here.
        final targets = (snap.data ?? const <CompoundTarget>[])
            .where((t) => t.isActive && t.totalPhases > 0)
            .toList();
        // Renders NOTHING, not even an empty shell, when there is no active
        // compound target — confirmed by this early return, before
        // `_sectionShell` (which always renders its own chrome) is ever
        // reached.
        if (targets.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _sectionShell(
            icon: Icons.flag,
            colour: Colors.teal,
            title: "Your targets this week",
            count: targets.length,
            child: Column(
              children: targets.map(_goalTargetRow).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _goalTargetRow(CompoundTarget target) {
    return StreamBuilder<List<CompoundPhase>>(
      stream: compoundPhasesStream(target.guideId, target.targetId),
      builder: (context, phasesSnap) {
        final phases = phasesSnap.data ?? const <CompoundPhase>[];
        final currentPhase =
            phases.where((p) => p.phaseNumber == target.currentPhase);
        if (currentPhase.isEmpty) return const SizedBox.shrink();
        return _goalTargetCard(target, currentPhase.first);
      },
    );
  }

  /// Collapsed: name, phase, and an overall "N/M tasks done" progress bar.
  /// Expanded: the full per-task checklist with real live progress, plus a
  /// link to the full weekly page (Part 5 item 4) for edit/approve/reject
  /// actions — none of which live here, this stays a summary.
  ///
  /// [ExpansionTile] is this app's OWN existing expand/collapse widget
  /// (`TopWeekResults.dart`, `BookLinkManager.dart`,
  /// `PodcastLinkManager.dart`) — reused here rather than a hand-rolled
  /// collapsible (Rule 1).
  Widget _goalTargetCard(CompoundTarget target, CompoundPhase phase) {
    final metric = target.metricInfo;
    final unit = metric?.unit ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: FutureBuilder<List<TaskProgress>>(
          future: livePhaseProgress(
            tasks: phase.tasks,
            guideId: target.guideId,
            metric: target.metric,
          ),
          builder: (context, snap) {
            final progress = snap.data;
            final total = phase.tasks.length;
            final done = progress?.where((p) => p.complete).length;
            final fraction = progress == null || total == 0
                ? null
                : done! / total;

            return FutureBuilder<Map<String, String>>(
              future: resolveStudentNames(collectStudentUids(phase.tasks)),
              builder: (context, namesSnap) {
                final uidToName = namesSnap.data;
                return ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  leading: Icon(Icons.flag, size: 18, color: Colors.teal.shade700),
                  title: Text(
                    "${metric?.label ?? target.metric} — Phase ${phase.phaseNumber}",
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: fraction ?? 0,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          fraction == null ? Colors.grey.shade400 : Colors.teal.shade700,
                        ),
                      ),
                    ),
                  ),
                  trailing: Text(
                    progress == null ? '' : '$done/$total',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                  ),
                  children: [
                    for (var i = 0; i < phase.tasks.length; i++)
                      _goalTaskLine(
                        phase.tasks[i],
                        unit,
                        progress != null && i < progress.length ? progress[i] : null,
                        uidToName,
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GoalWeeklyPhasePage(
                              guideId: target.guideId,
                              targetId: target.targetId,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: const Text("Open full page", style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _goalTaskLine(
      CompoundTask task, String unit, TaskProgress? progress, Map<String, String>? uidToName) {
    final fraction = progress == null
        ? null
        : compoundFraction(actual: progress.actual, target: progress.target);
    final complete = progress?.complete ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                complete ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 15,
                color: complete ? Colors.green.shade700 : Colors.grey.shade400,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(task.describe(unit, uidToName), style: const TextStyle(fontSize: 13)),
              ),
              Text(
                progress == null ? '—' : '${progress.actual}/${progress.target}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 23),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction ?? 0,
                minHeight: 5,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  complete ? Colors.green.shade700 : Colors.teal.shade700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared section chrome
  // ---------------------------------------------------------------------------

  /// Shared chrome for every top-level section on this page — collapsed by
  /// default (Part 2 item 4's chosen default: a guide opens this page to
  /// scan four headlines first, then taps into whichever one needs
  /// attention, rather than being handed all four fully expanded every
  /// time; easy to flip to "auto-expand the most urgent one" later if the
  /// product owner prefers that instead).
  ///
  /// Same [ExpansionTile] widget `_goalTargetCard`'s own per-target cards
  /// already use (Rule 1) — same call signature as before this task, so
  /// `_followUpSection`/`_missingSection`/`_overdueSection`/`_goalSection`
  /// needed ZERO changes to their own bodies (Rule 3: this is presentation-
  /// only, extending the one shared shell every section already funnels
  /// through, not four separate rewrites). The count badge moves into
  /// [ExpansionTile]'s `title` slot so its own default `trailing` chevron
  /// stays visible — a real expand/collapse affordance, not just an
  /// implicitly-tappable row.
  Widget _sectionShell({
    required IconData icon,
    required MaterialColor colour,
    required String title,
    required int? count,
    required Widget child,
    VoidCallback? onOpen,
    String? openLabel,
    // Master Task Part 5 item 6 — additive, defaults to `false` so the
    // four pre-existing call sites (`_followUpSection`/`_missingSection`/
    // `_overdueSection`/`_goalSection`) are completely unchanged (Rule 3).
    // The new calendar-context section is the one exception, passing
    // `true` — see its own doc comment for why.
    bool initiallyExpanded = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colour.shade50,
            ),
            child: Icon(icon, size: 18, color: colour.shade700),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (count != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: count == 0 ? Colors.green.shade50 : colour.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: count == 0
                          ? Colors.green.shade800
                          : colour.shade800,
                    ),
                  ),
                ),
            ],
          ),
          children: [
            const SizedBox(height: 4),
            child,
            if (onOpen != null && openLabel != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: Text(openLabel, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyLine(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
    );
  }

  /// First five names, with a count of the remainder rather than a silent cut.
}
