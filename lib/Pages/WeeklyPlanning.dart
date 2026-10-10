import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/CalendarQueries.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/PlanningQueries.dart';
import '../utils/WeekData.dart';
import '../utils/WeekSummary.dart';
import '../widgets/GuideButtons.dart';
import '../widgets/GuideCalendar.dart';
import '../widgets/GuideExpandable.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
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
    final profile = AdminProfileProvider.require();

    if (!mounted) return;
    setState(() {
      _guide = profile.id;
      _isHod = profile.isHod;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final week = currentWeekRange();

    return GuideScaffold(
      body: Column(
        children: [
          const GuideTopBar(title: "This Week"),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                          GuideSpace.pagePadding, 16, GuideSpace.pagePadding, 32),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _weekHeader(week),
                        // Calendar context at the very top: renders NOTHING
                        // when there is nothing current or upcoming.
                        _calendarContextSection(),
                        _goalSection(),
                        _followUpSection(week),
                        _overdueSection(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _weekHeader(({DateTime start, DateTime end}) week) {
    final t = context.gText;
    final fmt = DateFormat('dd MMM');
    // end is exclusive, so the last day shown is the day before it.
    final lastDay = week.end.subtract(const Duration(days: 1));

    return GuideHeroPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.calendar_month_outlined,
                color: GuideColors.heroLabel, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${fmt.format(week.start)} – ${fmt.format(lastDay)}",
                  style: t.screenTitle.copyWith(fontSize: 24, color: GuideColors.heroText),
                ),
                const SizedBox(height: 3),
                Text(
                  _isHod ? "All guides (HOD view)" : "Your students · ${_guide ?? ''}",
                  style: t.heroCaption.copyWith(fontSize: 13),
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
      stream: WeekData.instance.interactionLogs(),
      builder: (context, snapshot) {
        final t = context.gText;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _sectionShell(
            icon: Icons.event_repeat_outlined,
            pastel: GuidePastel.mauve,
            title: "Follow-ups due",
            count: null,
            child: const _SectionSpinner(),
          );
        }

        // status and the date range are matched in Dart — a compound query
        // would need a composite index.
        final due = followUpsDue(snapshot.data?.docs ?? const [], week);

        return _sectionShell(
          icon: Icons.event_repeat_outlined,
          pastel: GuidePastel.mauve,
          title: "Follow-ups due",
          count: due.length,
          child: due.isEmpty
              ? _emptyLine("Nothing scheduled this week")
              : Column(
                  children: due.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              DateFormat('EEE dd').format(item.when),
                              style: t.small.copyWith(
                                  fontWeight: FontWeight.w700, color: context.g.brass),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.student, style: t.cardTitleSmall),
                                if (item.action.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(item.action, style: t.caption),
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
  // submissions moved to the Tasks tab's "Submissions".)
  // ---------------------------------------------------------------------------

  Widget _overdueSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: WeekData.instance.associations(),
      builder: (context, snapshot) {
        final t = context.gText;
        final waiting = snapshot.connectionState == ConnectionState.waiting;
        final overdue = waiting
            ? const <OverdueItem>[]
            : overdueAssociations(snapshot.data?.docs ?? const []);

        return _sectionShell(
          icon: Icons.event_busy_outlined,
          pastel: GuidePastel.clay,
          title: "Overdue meetings",
          count: waiting ? null : overdue.length,
          onOpen: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OverdueAssociationsPage()),
          ),
          openLabel: "Open Overdue Associations",
          child: waiting
              ? const _SectionSpinner()
              : overdue.isEmpty
                  ? _emptyLine("Nothing overdue")
                  : Column(
                      children: overdue.take(5).map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(child: Text(item.student, style: t.body)),
                              Text(
                                item.days == 1 ? "1 day" : "${item.days} days",
                                style: t.small.copyWith(
                                    fontWeight: FontWeight.w700, color: context.g.danger),
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
  // -1. Calendar context — everything relevant from the Guide Calendar,
  // without opening it.
  // ---------------------------------------------------------------------------

  /// HAPPENING NOW (any event whose range covers today) and COMING UP (events
  /// starting within the next 7 days). Renders NOTHING (not even an empty shell)
  /// when both are empty, and defaults to EXPANDED: a bare count would not say
  /// WHAT is happening.
  Widget _calendarContextSection() {
    return FutureBuilder<List<CalendarEvent>>(
      // A guide's own visible events — the SAME visibility rule
      // `GuideCalendarPage` itself reads; no new query shape.
      future: WeekData.instance.events(_guide ?? ''),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();

        final happeningNow = eventsHappeningNow(snap.data!);
        final comingUp = eventsComingUp(snap.data!);
        if (happeningNow.isEmpty && comingUp.isEmpty) {
          return const SizedBox.shrink();
        }

        return _sectionShell(
          icon: Icons.campaign_outlined,
          pastel: GuidePastel.slate,
          title: "Calendar",
          count: happeningNow.length + comingUp.length,
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (happeningNow.isNotEmpty) ...[
                _calendarSubHeader("Happening now", context.g.danger),
                ...happeningNow.map(_calendarEventRow),
              ],
              if (happeningNow.isNotEmpty && comingUp.isNotEmpty) const SizedBox(height: 10),
              if (comingUp.isNotEmpty) ...[
                _calendarSubHeader("Coming up", context.g.brass),
                ...comingUp.map(_calendarEventRow),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _calendarSubHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GuideLabel(text, color: color),
    );
  }

  /// Shows the type and note, not just the title — a guide needs to know what an
  /// event actually MEANS for their week.
  Widget _calendarEventRow(CalendarEvent e) {
    final t = context.gText;
    final dateText = e.isMultiDay
        ? "${DateFormat('dd MMM').format(e.eventDate)} – "
            "${DateFormat('dd MMM').format(e.effectiveEndDate)}"
        : DateFormat('dd MMM').format(e.eventDate);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              dateText,
              style: t.caption.copyWith(fontWeight: FontWeight.w700, color: context.g.brass),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.title, style: t.cardTitleSmall)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.g.chipBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(guideEventTypeLabel(e), style: t.pill),
                    ),
                  ],
                ),
                if (e.note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(e.note, style: t.caption),
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
      stream: WeekData.instance.targets(_guide ?? ''),
      builder: (context, snap) {
        // `totalPhases > 0` — a target whose plan is still generating has no
        // current phase to summarize yet; nothing to show for it here.
        final targets = (snap.data ?? const <CompoundTarget>[])
            .where((t) => t.isActive && t.totalPhases > 0)
            .toList();
        // Renders NOTHING, not even an empty shell, when there is no active
        // compound target.
        if (targets.isEmpty) return const SizedBox.shrink();

        return _sectionShell(
          icon: Icons.flag_outlined,
          pastel: GuidePastel.sage,
          title: "Your targets this week",
          count: targets.length,
          child: Column(children: targets.map(_goalTargetRow).toList()),
        );
      },
    );
  }

  Widget _goalTargetRow(CompoundTarget target) {
    return StreamBuilder<List<CompoundPhase>>(
      stream: WeekData.instance.phases(target.guideId, target.targetId),
      builder: (context, phasesSnap) {
        final phases = phasesSnap.data ?? const <CompoundPhase>[];
        final currentPhase = phases.where((p) => p.phaseNumber == target.currentPhase);
        if (currentPhase.isEmpty) return const SizedBox.shrink();
        return _GoalTargetTile(target: target, phase: currentPhase.first);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Shared section chrome
  // ---------------------------------------------------------------------------

  /// Shared chrome for every top-level section on this page: a card with a tinted
  /// icon tile, the title, a count badge and a chevron; tap to reveal the content
  /// underneath (collapsed by default so a guide scans the headlines first; the
  /// calendar context opens expanded).
  Widget _sectionShell({
    required IconData icon,
    required GuidePastel pastel,
    required String title,
    required int? count,
    required Widget child,
    VoidCallback? onOpen,
    String? openLabel,
    bool initiallyExpanded = false,
  }) {
    final g = context.g;
    final gradient = g.pastel(pastel);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GuideExpandableCard(
        initiallyExpanded: initiallyExpanded,
        headerMinHeight: 64,
        headerPadding: const EdgeInsets.all(14),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(GuideShape.iconTileRadius),
          ),
          child: Icon(icon, size: 20, color: GuideColors.onPastel),
        ),
        title: Text(title),
        titleStyle: context.gText.cardTitle,
        trailing: count == null
            ? null
            : Container(
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$count',
                  style: context.gText.bodyStrong
                      .copyWith(fontSize: 13, color: GuideColors.onPastel),
                ),
              ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              child,
              if (onOpen != null && openLabel != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: GuideSecondaryButton(
                    label: openLabel,
                    icon: Icons.open_in_new_rounded,
                    onPressed: onOpen,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyLine(String text) {
    return Text(text, style: context.gText.small);
  }
}

/// A small spinner for a section that is still loading.
class _SectionSpinner extends StatelessWidget {
  const _SectionSpinner();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
}

/// One target of "Your targets this week": a sage pastel box with the metric, the
/// phase and an overall "N/M tasks done" progress bar; tap it to open the full
/// per-task checklist with real live progress, and a link to the full weekly page
/// (edit / approve / reject actions live there, this stays a summary).
class _GoalTargetTile extends StatefulWidget {
  const _GoalTargetTile({required this.target, required this.phase});

  final CompoundTarget target;
  final CompoundPhase phase;

  @override
  State<_GoalTargetTile> createState() => _GoalTargetTileState();
}

class _GoalTargetTileState extends State<_GoalTargetTile> {
  bool _open = false;
  late final Future<List<TaskProgress>> _progress = WeekData.instance.phaseProgress(
    tasks: widget.phase.tasks,
    guideId: widget.target.guideId,
    metric: widget.target.metric,
  );
  late final Future<Map<String, String>> _names =
      WeekData.instance.studentNames(collectStudentUids(widget.phase.tasks));

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final phase = widget.phase;
    final metric = target.metricInfo;
    final unit = metric?.unit ?? '';
    final t = context.gText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FutureBuilder<List<TaskProgress>>(
        future: _progress,
        builder: (context, snap) {
          final progress = snap.data;
          final total = phase.tasks.length;
          final done = progress?.where((p) => p.complete).length;
          final fraction = progress == null || total == 0 ? 0.0 : done! / total;

          return FutureBuilder<Map<String, String>>(
            future: _names,
            builder: (context, namesSnap) {
              final uidToName = namesSnap.data;
              return Semantics(
                button: true,
                expanded: _open,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _open = !_open),
                  child: GuidePastelBox(
                    pastel: GuidePastel.sage,
                    radius: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                "${metric?.label ?? target.metric} — Phase ${phase.phaseNumber}",
                                style: t.onPastelBody.copyWith(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              progress == null ? '' : '$done/$total',
                              style: t.onPastelSmall,
                            ),
                            const SizedBox(width: 6),
                            AnimatedRotation(
                              turns: _open ? .5 : 0,
                              duration: GuideMotion.of(context, GuideMotion.expand),
                              child: const Icon(Icons.keyboard_arrow_down_rounded,
                                  size: 20, color: GuideColors.onPastelMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GuideProgressBar(value: fraction, onPastel: true),
                        GuideAnimatedSize(
                          child: _open
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      for (var i = 0; i < phase.tasks.length; i++)
                                        _taskLine(
                                          phase.tasks[i],
                                          unit,
                                          progress != null && i < progress.length
                                              ? progress[i]
                                              : null,
                                          uidToName,
                                        ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: GuideSecondaryButton(
                                          label: "Open full page",
                                          icon: Icons.open_in_new_rounded,
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => GoalWeeklyPhasePage(
                                                guideId: target.guideId,
                                                targetId: target.targetId,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _taskLine(
      CompoundTask task, String unit, TaskProgress? progress, Map<String, String>? uidToName) {
    final t = context.gText;
    final g = context.g;
    final fraction = progress == null
        ? 0.0
        : (compoundFraction(actual: progress.actual, target: progress.target) ?? 0.0);
    final complete = progress?.complete ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                complete ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 17,
                color: complete ? g.success : GuideColors.onPastelMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(task.describe(unit, uidToName),
                    style: t.onPastelBody.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Text(progress == null ? '—' : '${progress.actual}/${progress.target}',
                  style: t.onPastelSmall),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: GuideProgressBar(value: fraction, onPastel: true, height: 4),
          ),
        ],
      ),
    );
  }
}
