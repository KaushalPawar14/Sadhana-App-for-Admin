import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Services/HierarchyApi.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/PlanData.dart';
import '../utils/PlanToday.dart';
import '../utils/Responsive.dart';
import '../utils/PlanTopicActions.dart';
import '../utils/Pronouns.dart';
import '../utils/SeenMarkers.dart';
import 'StudentProfilePage.dart';
import '../widgets/GuideAppBar.dart';
import '../theme/GuideColors.dart';
import '../widgets/Guide3dButton.dart';
import '../widgets/GuideButtons.dart';
import '../widgets/PlanBlocks.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideSurface.dart';

/// "Plan": the guide's TODAY and THIS WEEK plans, worked out by the server and shown READ-ONLY (no ticking, no replying: for any help,
/// ask the assistant in a chat).
///
/// HOW IT STAYS CURRENT. THE PLAN UPDATES ITSELF: within about a minute of any change (a report, an interaction, a book, a doubt, a worry, a commitment, a
/// meeting, a target, a calendar event, an assignment, a Surrender change) the server works it out again (plain code, no AI) and it appears here with a short
/// "Updated" highlight. There is no Refresh button. The page says when it was last updated ("Updated Fri 30 Oct, 6:00 AM").
///
/// WHAT IS NEW. A badge ("3 new") counts the changes the admin has not seen yet, a tap lists them ("New doubt: Testing", "Book finished: Ayush"), and the rows in
/// Today / This week that they concern carry a small "New" tag. SEEN = he opened this page and then LEFT it: the next visit has no tags, the badge on Home is
/// cleared, and what changes after that is a fresh count.
///
/// Opened from Home: THIS WEEK opens the This week tab ([initialWeek]); TODAY'S TASKS (or one of its three counts) opens Today at that
/// section ([section]: Follow-ups, Target tasks or Other tasks).
class PlanPage extends StatefulWidget {
  const PlanPage({super.key, this.initialWeek = false, this.section});

  /// Open on THIS WEEK.
  final bool initialWeek;

  /// On TODAY, scroll to this section when the page opens.
  final PlanGroup? section;

  @override
  State<PlanPage> createState() => _PlanPageState();
}

/// How long the "Updated" highlight stays.
const Duration kPlanUpdatedHighlight = Duration(seconds: 4);

/// "6:00 AM" for the instant, in India time (the server's clock), whatever the phone's own zone.
String planClock(DateTime t) {
  final ist = t.toUtc().add(const Duration(hours: 5, minutes: 30));
  final h = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
  return '$h:${ist.minute.toString().padLeft(2, '0')} ${ist.hour < 12 ? 'AM' : 'PM'}';
}

/// "Updated Fri 30 Oct, 6:00 AM": when the plan was last worked out again (the server does it by itself, within a minute of any change).
String planLastUpdated(PlanDoc plan) {
  final at = plan.generatedAt ?? plan.refreshedAt;
  final stamp = at == null ? '—' : DateFormat('EEE d MMM, h:mm a').format(at.toUtc().add(const Duration(hours: 5, minutes: 30)));
  return 'Updated $stamp';
}

/// The status line under "Updated".
String planStatusText(PlanDoc plan) => plan.status == 'updating' ? 'Updating…' : 'Up to date';

/// The names of Today's three groups, as the page's sections.
const Map<PlanGroup, String> kPlanGroupTitles = {PlanGroup.worry: 'Worries', PlanGroup.target: 'Target tasks', PlanGroup.followUp: 'Follow-ups', PlanGroup.other: 'Other tasks'};


class _PlanPageState extends State<PlanPage> {

  /// 0 Today, 1 This week, 2 Missing reports.
  late int _tab = widget.initialWeek ? 1 : 0;
  bool get _week => _tab == 1;

  /// Students the guide just ignored (they leave the tab at once, before the server's new plan arrives).
  final Set<String> _ignoredNow = {};
  final Set<String> _ignoring = {};
  PlanDoc? _plan;
  bool _loaded = false;
  bool _failed = false;
  bool _justUpdated = false;
  DateTime? _lastGenerated;
  StreamSubscription<PlanDoc?>? _sub;
  StreamSubscription<NewChanges>? _newSub;

  /// What is NEW (not seen yet): the badge, the list a tap shows and the "New" tags. It stays as it was when the page opened plus whatever arrives while it is open;
  /// leaving the page marks it seen.
  NewChanges _new = NewChanges.none;

  /// The new changes he has already looked at in the list (a tap on the badge): the bar says "Nothing new" at once; a change arriving later counts again.
  final Set<String> _listed = {};
  Timer? _highlight;

  static String _key(PendingChange c) => '${c.text}|${c.at?.millisecondsSinceEpoch}';
  int get _unlisted => _new.items.where((c) => !_listed.contains(_key(c))).length;

  /// Opened from a Home count: scroll to that section once the plan is on screen.
  /// One GlobalKey per student card in Today (a tap on his name in This week scrolls to it).
  final Map<String, GlobalKey> _cardKeys = {};

  final Map<String, GlobalKey> _sectionKeys = {for (final id in [kSectionFollowUps, kSectionTargets, kSectionOthers]) id: GlobalKey()};

  /// The blocks the guide collapsed (a tap on a header): they start OPEN, like a to-do list. And the rows he opened (a tap on a row shows its topics).
  final Set<String> _collapsed = {};
  final Set<String> _openRows = {};
  bool _scrolled = false;

  String get _me => AdminProfileProvider.current?.id ?? '';

  @override
  void initState() {
    super.initState();
    // opening the plan clears its orange dot AND the badge on the Home widgets at once (here, before the server has answered; the save goes on in the background)
    if (_me.isNotEmpty) {
      SeenMarkers.markSeen(_me, 'plan').catchError((_) {});
      PlanData.instance.looked(_me, save: false);
    }
    // the live badge and the "New" tags: what changed since the admin last LEFT this page (recorded by the server, no AI). They keep the cursor from before this look,
    // so they stay on the page while the badges outside are already clear.
    _newSub = PlanData.instance.newChanges(_me, forPage: true).listen((p) {
      if (mounted) setState(() => _new = p);
    }, onError: (_) {});
    _sub = PlanData.instance.plan(_me).listen(
      (p) {
        if (!mounted) return;
        final fresh = p?.generatedAt;
        // a new plan arriving while the page is open: a short "Updated" highlight
        final updated = _loaded && fresh != null && _lastGenerated != null && fresh.isAfter(_lastGenerated!);
        setState(() {
          _plan = p;
          _loaded = true;
          _failed = false;
          if (fresh != null) _lastGenerated = fresh;
          if (updated) _justUpdated = true;
        });
        if (updated) {
          _highlight?.cancel();
          _highlight = Timer(kPlanUpdatedHighlight, () {
            if (mounted) setState(() => _justUpdated = false);
          });
          if (_me.isNotEmpty) SeenMarkers.markSeen(_me, 'plan').catchError((_) {});
        }
        if (!_scrolled && widget.section != null && !_week && p != null) {
          _scrolled = true;
          _collapsed.remove(_sectionIdOf(widget.section!));
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSection());
        }
      },
      onError: (_) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  /// A Home count opens the section its tasks are in (a worry is a follow-up).
  static String _sectionIdOf(PlanGroup g) => switch (g) {
        PlanGroup.worry || PlanGroup.followUp => kSectionFollowUps,
        PlanGroup.target => kSectionTargets,
        PlanGroup.other => kSectionOthers,
      };

  void _scrollToSection({bool retry = true}) {
    if (!mounted) return;
    final ctx = _sectionKeys[_sectionIdOf(widget.section!)]?.currentContext;
    if (ctx == null) {
      if (retry) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSection(retry: false));
      return;
    }
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _newSub?.cancel();
    _highlight?.cancel();
    // LEFT: what arrived while he was here is seen now too (the next visit has no "New" tags); the badge outside is cleared at once, not after the server's answer
    if (_me.isNotEmpty) PlanData.instance.leftPlan(_me);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return GuideScaffold(
      appBar: GuideAppBar(
        title: const Text('Plan'),
        bottom: _PlanToggle(tab: _tab, missing: _plan?.missingReports.where((m) => !_ignoredNow.contains(m.studentUid)).length, onChanged: (t) => setState(() => _tab = t)),
      ),
      body: GuideCrossFade(
        child: !_loaded && !_failed
            ? const KeyedSubtree(key: ValueKey('plan-wait'), child: Center(child: CircularProgressIndicator()))
            : _failed
                ? KeyedSubtree(key: const ValueKey('plan-failed'), child: Center(child: Text('Could not load your plan.', style: context.gText.small.copyWith(color: g.mutedText))))
                : KeyedSubtree(key: ValueKey(_tab == 2 ? 'missing' : _week ? 'week' : 'today'), child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final t = context.gText;
    final plan = _plan;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 40),
      // on the website the list keeps a reading width (760 dp) instead of stretching across the window; a phone is unchanged
      child: ContentWidth(
        maxWidth: 760,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _newBar(context),
          const SizedBox(height: 10),
          Text('Read-only — for any help, ask the AI in a chat.', key: const ValueKey('plan-readonly'), style: t.bodyStrong),
          const SizedBox(height: 6),
          Text(
            'The plan updates by itself, within a minute of any change.',
            key: const ValueKey('plan-note'),
            style: t.small.copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          if (plan == null)
            GuideCard(
              padding: const EdgeInsets.all(16),
              child: Text('Your plan is being prepared. It appears here shortly.', key: const ValueKey('plan-empty'), style: t.small),
            )
          else ...[
            _statusCard(context, plan),
            const SizedBox(height: 12),
            if (_tab == 2) ..._missingBody(context, plan) else if (_week) ..._weekBody(context, plan) else ..._todayBody(context, plan),
          ],
        ],
      ),
      ),
    );
  }

  /// The list: looking at it clears the badge here and outside at once.
  void _showList() {
    final shown = _new;
    setState(() => _listed.addAll(shown.items.map(_key)));
    PlanData.instance.looked(_me);
    showNewChanges(context, shown);
  }

  /// THE BADGE at the top: "3 new" (the changes not seen yet; a tap lists them), or "✓ Nothing new". There are no refresh buttons.
  Widget _newBar(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    final unlisted = _unlisted;
    if (unlisted == 0) {
      return Text('✓ Nothing new', key: const ValueKey('plan-pending-ok'), style: t.small.copyWith(color: g.success, fontWeight: FontWeight.w600));
    }
    return GestureDetector(
      key: const ValueKey('plan-pending-line'),
      behavior: HitTestBehavior.opaque,
      onTap: _showList,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
        child: Row(
          children: [
            PendingBadge(key: const ValueKey('plan-refresh-badge'), count: unlisted, onTap: _showList),
            const SizedBox(width: 8),
            Text('new — tap to see', style: t.small.copyWith(color: g.warning, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context, PlanDoc plan) {
    final g = context.g;
    final t = context.gText;
    final refreshing = plan.status == 'updating';
    final status = planStatusText(plan);
    return AnimatedContainer(
      key: const ValueKey('plan-status'),
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _justUpdated ? g.agent.withValues(alpha: .16) : g.surface,
        borderRadius: BorderRadius.circular(GuideShape.cardRadius),
        border: Border.all(color: _justUpdated ? g.agent : g.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(planLastUpdated(plan), key: const ValueKey('plan-last-updated'), style: t.small),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                refreshing && !_justUpdated ? Icons.sync : Icons.check_circle_outline,
                size: 18,
                color: refreshing && !_justUpdated ? g.warning : g.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _justUpdated ? 'Updated' : status,
                  key: const ValueKey('plan-status-text'),
                  style: t.bodyStrong,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// TODAY: a clean TO-DO LIST. ONE summary line ("Total tasks today: N · Done D · Left L") and nothing else above three BLOCKS separated by a divider:
  /// FOLLOW-UPS, TARGET TASKS, OTHER TASKS. Each block has an icon, its name, "done/total" and a circular check (ticked when every task in it is done); a tap
  /// on the header collapses / expands it. Inside, one ROW per task (= one student, in his most important block): a circle, his name with his small
  /// Surrender %, small coloured chips of what the task contains; a tap on the row shows each topic (its circle, title, one line, and its 3D action button).
  /// Done rows stay, dimmed, at the bottom of their block. Nothing is ticked by a tap: the ticks come from the saved records.
  List<Widget> _todayBody(BuildContext context, PlanDoc plan) {
    final t = context.gText;
    final g = context.g;
    final view = TodayView.of(plan);
    var n = 0;
    final out = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: GuideCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Text(view.summaryText, key: const ValueKey('plan-summary'), style: t.cardTitleSmall),
        ),
      ),
      const SizedBox(height: 14),
    ];
    const icons = {kSectionFollowUps: Icons.forum_outlined, kSectionTargets: Icons.flag_outlined, kSectionOthers: Icons.event_note_outlined};
    for (var i = 0; i < view.sections.length; i++) {
      final sec = view.sections[i];
      final open = !_collapsed.contains(sec.id);
      if (i > 0) out.add(const PlanBlockDivider());
      out.add(KeyedSubtree(
        key: _sectionKeys[sec.id],
        child: PlanBlock(
          id: sec.id,
          icon: icons[sec.id] ?? Icons.checklist_rounded,
          title: sec.title,
          done: sec.done,
          total: sec.total,
          open: open,
          onToggle: () => setState(() => open ? _collapsed.add(sec.id) : _collapsed.remove(sec.id)),
          children: [
            for (final it in sec.tasks) GuideEntry(index: n++, child: _taskRow(context, it)),
            if (sec.id == kSectionOthers)
              for (final it in view.information)
                Padding(
                  key: ValueKey('plan-info-${it.id}'),
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                  child: Text(it.title, style: t.small.copyWith(color: g.mutedText)),
                ),
          ],
        ),
      ));
    }
    // a HOD's summary of every guide, below his own plan
    if (view.summaries.isNotEmpty) {
      out.add(const PlanBlockDivider());
      out.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: GuideSectionTitle('Guide by guide', key: const ValueKey('plan-section-guides'))));
      for (final it in view.summaries) {
        out.add(GuideEntry(index: n++, child: _summaryLine(context, it)));
      }
    }
    return out;
  }

  /// A HOD's one line for a guide (what is due, who needs attention).
  Widget _summaryLine(BuildContext context, PlanItem it) {
    final t = context.gText;
    return Padding(
      key: ValueKey('plan-item-${it.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: GuideCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(it.title, key: ValueKey('plan-title-${it.id}'), style: t.cardTitleSmall),
          if (it.detail.isNotEmpty) ...[const SizedBox(height: 4), Text(it.detail, style: t.small.copyWith(height: 1.35))],
        ]),
      ),
    );
  }

  /// The circular checkbox: filled and ticked when done. It is a picture, never a control (nothing is ticked by tapping it).
  Widget _circleCheck(BuildContext context, bool done, {Key? key, double size = 24}) => planCircle(context, done, key: key, size: size);

  /// MISSING REPORTS: every student with no report for 5 or more days (or never). A note, then one card per student with ONE button: Ignore.
  List<Widget> _missingBody(BuildContext context, PlanDoc plan) {
    final t = context.gText;
    final list = plan.missingReports.where((m) => !_ignoredNow.contains(m.studentUid)).toList();
    return [
      Text('You can ask him the reason — tell the AI what he said. Otherwise, ignore.', key: const ValueKey('plan-missing-note'), style: t.bodyStrong.copyWith(height: 1.35)),
      const SizedBox(height: 4),
      Text('Students with no daily report for 5 days or more, or who have never reported.', style: t.small.copyWith(height: 1.35)),
      const SizedBox(height: 8),
      if (list.isEmpty)
        GuideCard(
          padding: const EdgeInsets.all(16),
          child: Text('Nobody is missing their daily report.', key: const ValueKey('plan-missing-empty'), style: t.small),
        )
      else
        for (final m in list) _missingCard(context, m),
    ];
  }

  Widget _missingCard(BuildContext context, MissingReport m) {
    final g = context.g;
    final t = context.gText;
    final busy = _ignoring.contains(m.studentUid);
    return Padding(
      key: ValueKey('plan-missing-${m.studentUid}'),
      padding: const EdgeInsets.only(top: 8),
      child: GuideCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: ValueKey('plan-missing-open-${m.studentUid}'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentProfilePage(studentUid: m.studentUid))),
              child: Text(m.studentName, style: t.cardTitleSmall),
            ),
            const SizedBox(height: 2),
            Text(m.label, key: ValueKey('plan-missing-label-${m.studentUid}'), style: t.small.copyWith(color: g.agent, fontWeight: FontWeight.w600)),
            if (m.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Reason: ${m.reason}', key: ValueKey('plan-missing-reason-${m.studentUid}'), style: t.small.copyWith(height: 1.35)),
            ],
            const SizedBox(height: 8),
            GuideSecondaryButton(key: ValueKey('plan-ignore-${m.studentUid}'), label: 'Ignore', expand: false, onPressed: busy ? null : () => _ignore(m)),
          ],
        ),
      ),
    );
  }

  /// IGNORE, after a confirmation: he never appears in Missing reports again (the AI can undo it); his attitude part counts 0 while ignored.
  Future<void> _ignore(MissingReport m) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text('Ignore ${m.studentName}\'s daily reports?', key: const ValueKey('plan-ignore-title')),
        content: Text(
          '${m.studentName} will not appear in Missing reports again. While ignored, the attitude and willingness part of his Surrender % counts 0 (up to −10%). '
          'He still appears for targets, worries, doubts and Surrender steps. You can tell the AI to stop ignoring him.',
          style: dialogContext.gText.small.copyWith(height: 1.4),
        ),
        actions: [
          TextButton(key: const ValueKey('plan-ignore-cancel'), onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(key: const ValueKey('plan-ignore-confirm'), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Ignore')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _ignoring.add(m.studentUid));
    try {
      final message = await HierarchyApi.instance.studentGuideNote(studentUid: m.studentUid, kind: 'report_ignore');
      if (mounted) {
        setState(() => _ignoredNow.add(m.studentUid));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is HierarchyException ? e.message : 'Could not ignore him. Please try again.')));
    }
    if (mounted) setState(() => _ignoring.remove(m.studentUid));
  }

  /// THIS WEEK: the same to-do look as Today. The totals, then BLOCKS separated by a divider: INTERACTIONS (day by day, "Thu 30 Oct", the names with their
  /// small Surrender %, the done ones ticked; a tap opens that student's card), TARGET TASKS (each target with each student's step, and the roster tasks)
  /// and OTHER TASKS (meetings, trips, competitions, book deadlines, with their dates). No advice text: the details are in Today.
  List<Widget> _weekBody(BuildContext context, PlanDoc plan) {
    final t = context.gText;
    final g = context.g;
    final p = plan.progress ?? PlanProgress.empty;
    PlanSection? held(String id) {
      for (final s in plan.sections) {
        if (s.id == id) return s;
      }
      return null;
    }

    final people = held('interactions')?.items ?? const <PlanItem>[];
    final days = <String, List<PlanItem>>{};
    for (final it in people) {
      (days[it.scheduledFor] ??= []).add(it);
    }
    final dayKeys = days.keys.toList()..sort((a, b) => (a.isEmpty ? '9999' : a).compareTo(b.isEmpty ? '9999' : b));
    final tasks = held('targettasks')?.items ?? const <PlanItem>[];
    final others = held('othertasks')?.items ?? const <PlanItem>[];

    Widget name(PlanItem it) {
      final done = it.done;
      return GestureDetector(
        key: ValueKey('plan-week-name-${it.studentUid}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _openStudent(plan, it),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: done ? g.chipBackground : g.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: g.border)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (done) ...[Icon(Icons.check_rounded, key: ValueKey('plan-week-tick-${it.studentUid}'), size: 16, color: g.success), const SizedBox(width: 4)],
                if (_new.isNewFor(studentUid: it.studentUid)) ...[NewTag(key: ValueKey('plan-week-new-${it.studentUid}')), const SizedBox(width: 4)],
                Flexible(child: Text(it.studentName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong.copyWith(fontSize: 14, color: done ? g.mutedText : g.text, decoration: done ? TextDecoration.lineThrough : null))),
                if (it.percent != null) ...[const SizedBox(width: 6), Text('${it.percent}%', style: t.caption)],
              ],
            ),
          ),
        ),
      );
    }

    String dayTitle(String d) {
      final dt = DateTime.tryParse(d);
      return dt == null ? 'No day yet' : DateFormat('EEE d MMM').format(dt);
    }

    bool collapsed(String id) => _collapsed.contains(id);
    void toggle(String id) => setState(() => collapsed(id) ? _collapsed.remove(id) : _collapsed.add(id));
    final peopleDone = people.where((x) => x.done).length;
    final tasksDone = tasks.where((x) => x.done).length;

    Widget taskRow(PlanItem it) => Container(
          key: ValueKey('plan-week-task-${it.id}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: g.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: g.border)),
          child: Opacity(
            opacity: it.done ? .62 : 1,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                planCircle(context, it.done, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text(it.title, style: t.body.copyWith(height: 1.35, fontWeight: it.steps.isEmpty ? null : FontWeight.w700, decoration: it.done ? TextDecoration.lineThrough : null))),
                          if (_new.isNewFor(isTarget: true)) ...[const SizedBox(width: 6), NewTag(key: ValueKey('plan-week-task-new-${it.id}'))],
                        ],
                      ),
                      // each student's step, the done ones ticked: "Testing 12 → 16", "Amit 8 → 12 ✓"
                      if (it.steps.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < it.steps.length; i++)
                                KeyedSubtree(
                                  key: ValueKey('plan-week-step-${it.id}-$i'),
                                  child: PlanChip(label: it.steps[i].words, color: g.eventTarget, done: it.steps[i].done),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    return [
      // the totals
      Padding(
        key: const ValueKey('plan-progress'),
        padding: const EdgeInsets.only(top: 4),
        child: GuideCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text('Interactions this week: ${p.needed} · Done ${p.done} · Left ${p.left}', key: const ValueKey('plan-progress-summary'), style: t.cardTitleSmall),
        ),
      ),
      const SizedBox(height: 14),
      PlanBlock(
        id: 'week-interactions',
        icon: Icons.forum_outlined,
        title: 'Interactions',
        done: peopleDone,
        total: people.length,
        open: !collapsed('week-interactions'),
        onToggle: () => toggle('week-interactions'),
        emptyText: 'Nothing here this week',
        children: [
          for (final d in dayKeys)
            Padding(
              key: ValueKey('plan-week-day-$d'),
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dayTitle(d), style: t.caption.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final it in days[d]!) name(it)]),
                ],
              ),
            ),
        ],
      ),
      const PlanBlockDivider(),
      PlanBlock(
        id: 'week-targettasks',
        icon: Icons.flag_outlined,
        title: 'Target tasks',
        done: tasksDone,
        total: tasks.length,
        open: !collapsed('week-targettasks'),
        onToggle: () => toggle('week-targettasks'),
        emptyText: 'Nothing here this week',
        children: [for (final it in tasks) taskRow(it)],
      ),
      const PlanBlockDivider(),
      PlanBlock(
        id: 'week-othertasks',
        icon: Icons.event_note_outlined,
        title: 'Other tasks',
        total: others.length,
        showCheck: false,
        open: !collapsed('week-othertasks'),
        onToggle: () => toggle('week-othertasks'),
        emptyText: 'Nothing here this week',
        children: [
          for (final it in others)
            Container(
              key: ValueKey('plan-week-other-${it.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: g.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: g.border)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 78, child: Text(dayTitle(it.scheduledFor), style: t.caption.copyWith(fontWeight: FontWeight.w800))),
                  Expanded(child: Text(it.title, style: t.body.copyWith(height: 1.35))),
                ],
              ),
            ),
        ],
      ),
      // a HOD's summary of every guide, below his own
      for (final s in plan.sections)
        if (s.id == 'guides') ...[
          const PlanBlockDivider(),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: GuideSectionTitle(s.title, key: const ValueKey('plan-week-section-guides'))),
          for (final it in s.items) _summaryLine(context, it),
        ],
    ];
  }

  /// A tap on a name in This week: that student's card in Today (scrolled to), or, when he is planned for another day, his open topics.
  Future<void> _openStudent(PlanDoc plan, PlanItem it) async {
    PlanItem? card;
    for (final c in plan.todayItems) {
      if (c.isCard && c.studentUid == it.studentUid) card = c;
    }
    if (card != null) {
      setState(() {
        _tab = 0;
        _collapsed.remove(todaySectionOf(card!));
        _openRows.add(card.id);
      });
      void go({bool retry = true}) {
        final ctx = _cardKeys[it.studentUid]?.currentContext;
        if (ctx == null) {
          if (retry) WidgetsBinding.instance.addPostFrameCallback((_) => go(retry: false));
          return;
        }
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => go());
      return;
    }
    List<String> needs = const [];
    try {
      needs = await PlanData.instance.needsOf(it.studentUid);
    } catch (_) {
      // the dialog still opens, with the day
    }
    if (!mounted) return;
    final day = DateTime.tryParse(it.scheduledFor);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text('${it.studentName}${it.percent != null ? ' · ${it.percent}%' : ''}', key: const ValueKey('plan-student-dialog-title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (day != null) Text('Planned for ${DateFormat('EEEE d MMMM').format(day)}.', key: const ValueKey('plan-student-dialog-day'), style: dialogContext.gText.small),
            const SizedBox(height: 8),
            if (needs.isEmpty) Text('Nothing open about him right now.', style: dialogContext.gText.small),
            for (final n in needs) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $n', style: dialogContext.gText.small.copyWith(height: 1.35))),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  /// A TO-DO ROW in Today: a circle (ticked when ALL his topics are done, never by tapping), his name with his small Surrender %, and small coloured CHIPS of what
  /// it contains. A tap on the row shows each topic: its circle, its title (struck through with a tick when done), its one line and its 3D action button.
  /// A task that is not about one student (a phase end, a deadline ...) is its title; a tap shows its line. Done rows are dimmed.
  Widget _taskRow(BuildContext context, PlanItem it) {
    final g = context.g;
    final t = context.gText;
    final open = _openRows.contains(it.id);
    final when = it.scheduledFor.isEmpty ? null : DateTime.tryParse(it.scheduledFor);
    TextStyle struck(TextStyle base) => it.done ? base.copyWith(decoration: TextDecoration.lineThrough, color: g.mutedText) : base;
    final name = it.isCard && it.studentName.isNotEmpty ? it.studentName : it.title;
    final seen = <String>{};
    final chips = [
      for (final p in it.points)
        if (seen.add('${p.title}|${p.kind}')) PlanChip(label: p.title.isEmpty ? p.kind : p.title, color: planChipColor(g, p.kind), done: p.done),
    ];
    return Padding(
      key: ValueKey('plan-item-${it.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: it.done ? .62 : 1,
        child: Container(
          key: it.isCard && it.studentUid.isNotEmpty ? _cardKeys.putIfAbsent(it.studentUid, GlobalKey.new) : null,
          decoration: BoxDecoration(color: g.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: open ? g.agent : g.border), boxShadow: g.cardShadow),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: ValueKey('plan-row-${it.id}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => open ? _openRows.remove(it.id) : _openRows.add(it.id)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _circleCheck(context, it.done, key: ValueKey('plan-check-${it.id}'), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(child: Text(name, key: ValueKey('plan-title-${it.id}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: struck(t.cardTitleSmall))),
                                  if (_new.isNewFor(studentUid: it.studentUid, isTarget: it.kind == 'targetTask')) ...[const SizedBox(width: 8), NewTag(key: ValueKey('plan-new-${it.id}'))],
                                  if (it.isInteraction && it.percent != null) ...[const SizedBox(width: 8), Text('${it.percent}%', key: ValueKey('plan-percent-${it.id}'), style: t.caption.copyWith(fontWeight: FontWeight.w700))],
                                ],
                              ),
                              if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(key: ValueKey('plan-chips-${it.id}'), spacing: 6, runSpacing: 6, children: chips)),
                              // the calendar event that shapes this item ("Exams 31 Dec–17 Jan")
                              if (it.calNote.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(children: [
                                    Icon(Icons.event_outlined, size: 14, color: g.mutedText),
                                    const SizedBox(width: 4),
                                    Flexible(child: Text(it.calNote, key: ValueKey('plan-calnote-${it.id}'), style: t.caption)),
                                  ]),
                                ),
                            ],
                          ),
                        ),
                        Icon(open ? Icons.expand_less : Icons.expand_more, color: g.mutedText),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: !open
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        key: ValueKey('plan-row-body-${it.id}'),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (when != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(DateFormat('EEE d MMM').format(when), style: t.caption.copyWith(color: g.agent))),
                            if (it.points.isNotEmpty) ...[
                              for (var i = 0; i < it.points.length; i++) _topicLine(context, it, i),
                              if (it.also.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(it.also, key: ValueKey('plan-also-${it.id}'), style: t.caption.copyWith(height: 1.3))),
                            ] else if (it.detail.isNotEmpty)
                              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(it.detail, key: ValueKey('plan-detail-${it.id}'), style: struck(t.small.copyWith(height: 1.35)))),
                            // a target whose end date has been reached: delete it, or extend its end date
                            if (isEndedTarget(it))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    Guide3dButton(key: ValueKey('plan-target-delete-${it.id}'), label: 'Delete target', onPressed: () => runDeleteEndedTarget(context, _me, it)),
                                    Guide3dButton(key: ValueKey('plan-target-extend-${it.id}'), label: 'Extend end date', onPressed: () => runExtendEndedTarget(context, _me, it)),
                                  ],
                                ),
                              ),
                            if (it.carriedOver || (it.checkWithHim && !it.isCard))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (it.carriedOver) _tag(context, 'Carried over', key: ValueKey('plan-carried-${it.id}')),
                                    if (it.checkWithHim && !it.isCard) _tag(context, pronouned('Check with him first', it.gender, name: it.studentName)),
                                  ],
                                ),
                              ),
                            if (it.isCard && it.studentUid.isNotEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  key: ValueKey('plan-open-${it.id}'),
                                  style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 4)),
                                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentProfilePage(studentUid: it.studentUid))),
                                  child: Text('His profile', style: t.bodyStrong.copyWith(color: g.agent)),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "28 Oct" for a yyyy-MM-dd.
  static String _sinceWords(String day) {
    final d = DateTime.tryParse(day);
    return d == null ? day : DateFormat('d MMM').format(d);
  }

  /// One line inside the Surrender check: a point to discuss (a bullet) or a gap (its circle, ticked by itself when the data is there, and its button).
  Widget _subLine(BuildContext context, PlanItem it, PlanPoint p, int i, int j) {
    final g = context.g;
    final t = context.gText;
    final x = p.sub[j];
    final action = x.isGap && !x.done && !p.done ? subActionOf(x) : null;
    TextStyle struck(TextStyle base) => (x.done || p.done) && x.isGap ? base.copyWith(decoration: TextDecoration.lineThrough, color: g.mutedText) : base;
    return Padding(
      key: ValueKey('plan-sub-${it.id}-$i-$j'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: x.isGap ? planCircle(context, x.done || p.done, key: ValueKey('plan-sub-circle-${it.id}-$i-$j'), size: 16) : Icon(Icons.circle, size: 6, color: g.mutedText),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(x.text, key: ValueKey('plan-sub-text-${it.id}-$i-$j'), style: struck(t.small.copyWith(height: 1.35))),
                if (action != null && it.isCard && it.studentUid.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Guide3dButton(
                      key: ValueKey('plan-sub-action-${it.id}-$i-$j'),
                      label: kTopicActionLabels[action]!,
                      onPressed: () => runStudentAction(context, action, uid: it.studentUid, name: it.studentName, topics: recordTopicsOf(it)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One topic of a task: its circle, its title (struck through when done, with a tick and "done"), its one line and, while open, its 3D action button.
  Widget _topicLine(BuildContext context, PlanItem it, int i) {
    final g = context.g;
    final t = context.gText;
    final p = it.points[i];
    TextStyle struck(TextStyle base) => p.done ? base.copyWith(decoration: TextDecoration.lineThrough, color: g.mutedText) : base;
    return Padding(
      key: ValueKey('plan-point-${it.id}-$i'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: planCircle(context, p.done, key: ValueKey('plan-point-circle-${it.id}-$i'), size: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (p.title.isNotEmpty) Flexible(child: Text(p.title, key: ValueKey('plan-point-title-${it.id}-$i'), style: struck(t.bodyStrong.copyWith(fontSize: 14, color: g.agent)))),
                    if (p.done) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_rounded, key: ValueKey('plan-point-tick-${it.id}-$i'), size: 16, color: g.success),
                      const SizedBox(width: 2),
                      Text('done', key: ValueKey('plan-point-done-${it.id}-$i'), style: t.caption.copyWith(color: g.success, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
                Text(p.text, key: ValueKey('plan-point-text-${it.id}-$i'), style: struck(t.small.copyWith(height: 1.35))),
                // a topic carried over from an earlier day says since when
                if (p.carriedOver && !p.done)
                  Padding(padding: const EdgeInsets.only(top: 4), child: _tag(context, 'Carried over since ${_sinceWords(p.since)}', key: ValueKey('plan-point-carried-${it.id}-$i'))),
                // THE SURRENDER CHECK: what to discuss (the AI's points, prepared once for the crossing) and the data gaps to fill, each with its own button
                for (var j = 0; j < p.sub.length; j++) _subLine(context, it, p, i, j),
                // ONE 3D button per open topic: it opens the place to do it by hand; it never ticks (the topic ticks when the real record is saved there)
                // a confirmed meeting that was never marked: TWO buttons, Completed and Cancelled
                if (!p.done && it.isCard && it.studentUid.isNotEmpty && isUnmarkedMeeting(p))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Guide3dButton(key: ValueKey('plan-meeting-completed-${it.id}-$i'), label: 'Completed', onPressed: () => runMeetingCompleted(context, it, p)),
                        Guide3dButton(key: ValueKey('plan-meeting-cancelled-${it.id}-$i'), label: 'Cancelled', onPressed: () => runMeetingCancelled(context, it, p)),
                      ],
                    ),
                  )
                else if (!p.done && it.isCard && it.studentUid.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // the topic's own button, and (where postponing makes sense) the second one: Later
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Guide3dButton(key: ValueKey('plan-action-${it.id}-$i'), label: kTopicActionLabels[topicActionOf(p)]!, onPressed: () => runTopicAction(context, it, p)),
                          if (isPostponable(p)) Guide3dButton(key: ValueKey('plan-later-${it.id}-$i'), label: 'Later', onPressed: () => showLaterPanel(context, it, p)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, String label, {Key? key}) {
    final g = context.g;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: g.chipBackground, borderRadius: BorderRadius.circular(GuideShape.chipRadius)),
      child: Text(label, style: context.gText.pill),
    );
  }
}

/// The small round badge with the number of NEW changes (the Plan page, the Home plan widgets). Tapping it lists them.
class PendingBadge extends StatelessWidget {
  const PendingBadge({super.key, required this.count, this.onTap, this.onDark = false});

  final int count;
  final VoidCallback? onTap;

  /// On the dark hero cards: a brass pill with dark text; elsewhere the warning colour with white text.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final bg = onDark ? GuideColors.heroLabel : g.warning;
    final fg = onDark ? GuideColors.onPastel : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        label: '$count new',
        child: Container(
          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11), border: Border.all(color: g.pageBackground, width: 1.5)),
          child: Text(count > 99 ? '99+' : '$count', style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800, height: 1.1)),
        ),
      ),
    );
  }
}

/// The small "New" tag on a row of Today / This week that has something the admin has not seen yet.
class NewTag extends StatelessWidget {
  const NewTag({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: g.warning, borderRadius: BorderRadius.circular(8)),
      child: const Text('New', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1.3)),
    );
  }
}

/// The simple list a tap on the badge shows: one line each, newest first ("New doubt: Testing", "Book finished: Ayush", "New task: Surrender check — Ravi").
Future<void> showNewChanges(BuildContext context, NewChanges changes) => showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.gText;
        return GuideDialog(
          title: Text('${changes.count} new', key: const ValueKey('pending-title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in changes.items) Padding(key: ValueKey('new-change-${c.text}'), padding: const EdgeInsets.only(bottom: 6), child: Text('• ${c.text}', style: t.body.copyWith(fontSize: 14, height: 1.35))),
                const SizedBox(height: 4),
                Text('They are marked "New" in the plan while you are on it.', style: t.caption),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
        );
      },
    );

/// TODAY · THIS WEEK · MISSING REPORTS, a three-way toggle under the app bar: each side a 48 dp target, the chosen one in the assistant's sky blue.
class _PlanToggle extends StatelessWidget implements PreferredSizeWidget {
  const _PlanToggle({required this.tab, required this.onChanged, this.missing});

  /// 0 Today, 1 This week, 2 Missing reports.
  final int tab;

  /// How many students are in Missing reports (null until the plan is there).
  final int? missing;
  final ValueChanged<int> onChanged;

  @override
  Size get preferredSize => const Size.fromHeight(GuideShape.touchTarget + 12);

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    Widget side(String label, int index, Key key) {
      final on = tab == index;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(index),
            child: Container(
              height: GuideShape.touchTarget,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? g.agentMid : Colors.transparent,
                borderRadius: BorderRadius.circular(GuideShape.chipRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(label, maxLines: 2, textAlign: TextAlign.center, style: t.bodyStrong.copyWith(fontSize: 12, height: 1.1, color: on ? g.onAgent : g.text, letterSpacing: .3)),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 4, GuideSpace.pagePadding, 8),
      child: Container(
        decoration: BoxDecoration(color: g.chipBackground, borderRadius: BorderRadius.circular(GuideShape.chipRadius + 2)),
        child: Row(children: [
          side('TODAY', 0, const ValueKey('plan-tab-today')),
          side('THIS WEEK', 1, const ValueKey('plan-tab-week')),
          side(missing == null ? 'MISSING REPORTS' : 'MISSING REPORTS ($missing)', 2, const ValueKey('plan-tab-missing')),
        ]),
      ),
    );
  }
}
