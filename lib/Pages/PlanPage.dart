import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Services/HierarchyApi.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/PlanData.dart';
import '../utils/Pronouns.dart';
import '../utils/SeenMarkers.dart';
import 'StudentProfilePage.dart';
import '../widgets/GuideAppBar.dart';
import '../theme/GuideColors.dart';
import '../widgets/GuideButtons.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideSurface.dart';

/// "Plan": the guide's TODAY and THIS WEEK plans, worked out by the server and shown READ-ONLY (no ticking, no replying: for any help,
/// ask the assistant in a chat).
///
/// HOW IT STAYS CURRENT. Ticks, finished items going away and new doubts / worries / items appear BY THEMSELVES (free: no AI). The AI rewrites
/// the plan (new questions) only when asked: the REFRESH button at the top of this page (once per 2 minutes; a HOD also has "Refresh all
/// guides"), every morning at 6 AM, and on Monday morning (This week). Under "Last updated" the page says honestly when and by what:
///   Last updated: Fri 30 Oct, 6:00 AM (daily update)      (by refresh / daily update / weekly update)
///   Refreshing…                                            the AI is writing it now; then the new plan appears with a short "Updated" highlight
///   You can refresh again in N sec                         the 2-minute wait after a refresh
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

/// The server lets a guide refresh once per this long.
const Duration kPlanRefreshGap = Duration(minutes: 2);

/// "6:00 AM" for the instant, in India time (the server's clock), whatever the phone's own zone.
String planClock(DateTime t) {
  final ist = t.toUtc().add(const Duration(hours: 5, minutes: 30));
  final h = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
  return '$h:${ist.minute.toString().padLeft(2, '0')} ${ist.hour < 12 ? 'AM' : 'PM'}';
}

/// "Last updated: Fri 30 Oct, 6:00 AM (daily update)": when the AI last rewrote the plan and by what (a refresh, the 6 AM run, Monday's run).
/// A plan the AI has not rewritten yet shows the time it was worked out, with no "by".
String planLastUpdated(PlanDoc plan) {
  final at = plan.refreshedAt ?? plan.generatedAt;
  final stamp = at == null ? '—' : DateFormat('EEE d MMM, h:mm a').format(at.toUtc().add(const Duration(hours: 5, minutes: 30)));
  final by = plan.refreshedAt == null
      ? ''
      : switch (plan.refreshedBy) {
          'refresh' => ' (by refresh)',
          'open' => ' (first open today)',
          'daily' => ' (daily update)',
          'weekly' => ' (weekly update)',
          _ => '',
        };
  return 'Last updated: $stamp$by';
}

/// The status line under "Last updated".
String planStatusText(PlanDoc plan, {bool refreshing = false}) => refreshing || plan.status == 'updating' ? 'Refreshing…' : 'Up to date';

/// The names of Today's three groups, as the page's sections.
const Map<PlanGroup, String> kPlanGroupTitles = {PlanGroup.worry: 'Worries', PlanGroup.target: 'Target tasks', PlanGroup.followUp: 'Follow-ups', PlanGroup.other: 'Other tasks'};

String _sectionKey(PlanGroup g) => switch (g) { PlanGroup.worry => 'worries', PlanGroup.followUp => 'followups', PlanGroup.target => 'targets', PlanGroup.other => 'other' };

class _PlanPageState extends State<PlanPage> {

  /// The students-a-day number the guide just chose (shown at once, until the server's new plan arrives).
  int? _sizeChosen;
  bool _savingSize = false;

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
  StreamSubscription<PendingChanges>? _pendingSub;
  PendingChanges _pending = PendingChanges.none;
  Timer? _highlight;

  /// Refresh: busy (own / everyone's), the seconds left of the 2-minute wait for each, and the server's refusal in words (the budget).
  bool _refreshing = false;
  bool _refreshingAll = false;
  int _waitOwn = 0;
  int _waitAll = 0;
  Timer? _waitTimer;
  String? _refreshError;

  /// Opened from a Home count: scroll to that section once the plan is on screen.
  /// One GlobalKey per student card in Today (a tap on his name in This week scrolls to it).
  final Map<String, GlobalKey> _cardKeys = {};

  final Map<PlanGroup, GlobalKey> _sectionKeys = {for (final g in PlanGroup.values) g: GlobalKey()};
  bool _scrolled = false;

  String get _me => AdminProfileProvider.current?.id ?? '';

  @override
  void initState() {
    super.initState();
    // opening the plan clears its orange dot
    if (_me.isNotEmpty) SeenMarkers.markSeen(_me, 'plan').catchError((_) {});
    // the live badge: what changed since the last refresh that the AI has not considered yet (counted by the server, no AI)
    _pendingSub = PlanData.instance.pending(_me).listen((p) {
      if (mounted) setState(() => _pending = p);
    }, onError: (_) {});
    _sub = PlanData.instance.plan(_me).listen(
      (p) {
        if (!mounted) return;
        final fresh = p?.generatedAt;
        // a new plan arriving while the page is open: a short "Updated" highlight
        final updated = _loaded && fresh != null && _lastGenerated != null && fresh.isAfter(_lastGenerated!);
        setState(() {
          _plan = p;
          _sizeChosen = null; // the server's own number is the truth again
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
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSection());
        }
      },
      onError: (_) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  void _scrollToSection({bool retry = true}) {
    if (!mounted) return;
    final ctx = _sectionKeys[widget.section]?.currentContext;
    if (ctx == null) {
      if (retry) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSection(retry: false));
      return;
    }
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pendingSub?.cancel();
    _highlight?.cancel();
    _waitTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------

  void _startWait(bool all, int seconds) {
    setState(() => all ? _waitAll = seconds : _waitOwn = seconds);
    _waitTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_waitOwn > 0) _waitOwn--;
        if (_waitAll > 0) _waitAll--;
      });
      if (_waitOwn == 0 && _waitAll == 0) {
        _waitTimer?.cancel();
        _waitTimer = null;
      }
    });
  }

  /// The AI rewrites the plan, now. The server decides (once per 2 minutes, the guide's own plan only, not while the budget is used up).
  Future<void> _refresh({bool all = false}) async {
    if (_refreshing || (all ? _waitAll : _waitOwn) > 0) return;
    setState(() {
      _refreshing = true;
      _refreshingAll = all;
      _refreshError = null;
    });
    try {
      final r = await HierarchyApi.instance.refreshPlan(all: all);
      if (mounted) _startWait(all, r.ok ? kPlanRefreshGap.inSeconds : r.retryInSec);
    } catch (e) {
      if (mounted) setState(() => _refreshError = e is HierarchyException ? e.message : 'Could not refresh the plan. Please try again.');
    }
    if (mounted) setState(() => _refreshing = false);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _refreshBar(context),
          const SizedBox(height: 10),
          Text('Read-only — for any help, ask the AI in a chat.', key: const ValueKey('plan-readonly'), style: t.bodyStrong),
          const SizedBox(height: 6),
          Text(
            'Tap Refresh to update the plan with your latest changes.',
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
    );
  }

  /// REFRESH at the top: one button (a HOD also has "Refresh all guides"), the wait that follows, and the server's refusal in words.
  Widget _refreshBar(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    final hod = AdminProfileProvider.current?.isHod ?? false;
    final ownBusy = _refreshing && !_refreshingAll;
    final allBusy = _refreshing && _refreshingAll;
    final wait = _waitOwn > 0 ? _waitOwn : (hod ? _waitAll : 0);
    final waitText = _waitOwn > 0 ? 'You can refresh again in $_waitOwn sec' : (hod && _waitAll > 0 ? 'You can refresh all guides again in $_waitAll sec' : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // the live badge on the button: how many changes the AI has not considered yet
            Stack(
              clipBehavior: Clip.none,
              children: [
                GuidePrimaryButton(
                  key: const ValueKey('plan-refresh'),
                  label: ownBusy ? 'Refreshing…' : 'Refresh',
                  icon: Icons.refresh_rounded,
                  expand: false,
                  onPressed: _refreshing || _waitOwn > 0 ? null : () => _refresh(),
                ),
                if (_pending.count > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: PendingBadge(key: const ValueKey('plan-refresh-badge'), count: _pending.count, onTap: () => showPendingChanges(context, _pending)),
                  ),
              ],
            ),
            if (hod)
              GuideSecondaryButton(
                key: const ValueKey('plan-refresh-all'),
                label: allBusy ? 'Refreshing…' : 'Refresh all guides',
                icon: Icons.refresh_rounded,
                onPressed: _refreshing || _waitAll > 0 ? null : () => _refresh(all: true),
              ),
          ],
        ),
        // pending changes (tap for the list), or "✓ Up to date"
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _pending.count == 0
              ? Text('✓ Up to date', key: const ValueKey('plan-pending-ok'), style: t.small.copyWith(color: g.success, fontWeight: FontWeight.w600))
              : GestureDetector(
                  key: const ValueKey('plan-pending-line'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showPendingChanges(context, _pending),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${_pending.count} change${_pending.count == 1 ? '' : 's'} the AI has not looked at yet — tap to see', style: t.small.copyWith(color: g.warning, fontWeight: FontWeight.w700, height: 1.3)),
                    ),
                  ),
                ),
        ),
        if (waitText != null && wait > 0 && _refreshError == null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(waitText, key: const ValueKey('plan-refresh-wait'), style: t.caption)),
        if (_refreshError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_refreshError!, key: const ValueKey('plan-refresh-error'), style: t.small.copyWith(color: g.warning, height: 1.4)),
          ),
      ],
    );
  }

  Widget _statusCard(BuildContext context, PlanDoc plan) {
    final g = context.g;
    final t = context.gText;
    final refreshing = _refreshing || plan.status == 'updating';
    final status = planStatusText(plan, refreshing: _refreshing);
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

  /// TODAY: the day's batch, a row of counts, then four sections: Worries, Target tasks, Follow-ups and Other tasks. ONE CARD PER STUDENT: every topic
  /// about him is a one-line point on his one card, which sits in the most important section it has a point in; a section's count includes every
  /// card that has a topic in it. EVERYTHING IS ALWAYS THERE: a count with nothing behind it reads "0" and a section with nothing in it reads
  /// "None yet" (it is never left out).
  List<Widget> _todayBody(BuildContext context, PlanDoc plan) {
    final t = context.gText;
    // a HOD's own tasks first; the summary line of every guide goes BELOW them
    final items = plan.todayItems.where((i) => !i.isGuideSummary).toList();
    final summaries = plan.todayItems.where((i) => i.isGuideSummary).toList();
    final date = DateTime.tryParse(plan.todayDate);
    final students = items.where((i) => i.isInteraction).length;
    final batch = plan.batch ?? const PlanBatch(size: 4, round: 1, members: 0, carried: 0, nextReady: false, done: 0, left: 0);
    final out = <Widget>[
      GuideSectionTitle(date == null ? 'Today' : 'Today — ${DateFormat('EEEE d MMMM').format(date)}'),
      const SizedBox(height: 4),
      _batchCard(context, batch),
      _todayCounts(context, items, plan.progress),
    ];
    var n = 0;
    Widget card(PlanItem it) => GuideEntry(index: n++, child: _itemCard(context, it, total: it.isInteraction ? (plan.batch?.members ?? students) : 0));
    // the summary of every guide, below the HOD's own plan
    final guides = <Widget>[
      if (summaries.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.only(top: 18), child: GuideSectionTitle('Guide by guide', key: const ValueKey('plan-section-guides'))),
        for (final it in summaries) card(it),
      ],
    ];
    if (items.isEmpty) {
      out.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text('Nothing is planned for today. A quiet day — enjoy it.', key: const ValueKey('plan-today-empty'), style: t.small)));
    }
    for (final g in PlanGroup.values) {
      final mine = items.where((i) => i.group == g).toList();
      // every card with a topic in this section, even when his card sits in a more important one (counted, not repeated)
      final count = items.where((i) => !i.done && i.inGroups.contains(g)).length;
      out.add(Padding(
        key: _sectionKeys[g],
        padding: const EdgeInsets.only(top: 14),
        child: GuideSectionTitle(
          kPlanGroupTitles[g]!,
          key: ValueKey('plan-section-${_sectionKey(g)}'),
          trailing: Text('$count', key: ValueKey('plan-section-count-${_sectionKey(g)}'), style: t.bodyStrong),
        ),
      ));
      if (mine.isEmpty) out.add(Padding(padding: const EdgeInsets.only(top: 6), child: Text('None yet', key: ValueKey('plan-section-empty-${_sectionKey(g)}'), style: t.small)));
      for (final it in mine) {
        out.add(card(it));
      }
    }
    return [...out, ...guides];
  }

  /// The day at a glance, every number always shown (0 when there is none): students with a card, interactions done / left, pending this week,
  /// each section's count, meetings, doubts. A student is ONE card however many topics he has.
  Widget _todayCounts(BuildContext context, List<PlanItem> items, PlanProgress? progress) {
    final t = context.gText;
    final g = context.g;
    final open = items.where((i) => !i.done).toList();
    final doubts = open.where((i) => i.kind == 'doubtsToAnswer').fold<int>(0, (n, i) => n + (int.tryParse(RegExp(r'^\d+').stringMatch(i.title) ?? '') ?? 1)) +
        open.where((i) => i.points.any((p) => p.kind == 'doubt')).length;
    int inGroup(PlanGroup grp) => open.where((i) => i.inGroups.contains(grp)).length;
    final counts = <(String, String, int)>[
      ('students', 'Students today', open.where((i) => i.isCard).length),
      ('interactions-done', 'Interactions done', items.where((i) => i.isInteraction && i.done).length),
      ('interactions-left', 'Interactions left', open.where((i) => i.isInteraction).length),
      ('pending', 'Pending this week', progress?.left ?? 0),
      ('worries', 'Worries', inGroup(PlanGroup.worry)),
      ('target-tasks', 'Target tasks', inGroup(PlanGroup.target)),
      ('follow-ups', 'Follow-ups', inGroup(PlanGroup.followUp)),
      ('other-tasks', 'Other tasks', inGroup(PlanGroup.other)),
      ('meetings', 'Meetings', open.where((i) => i.kind == 'meeting' || i.kind == 'meeting_request' || i.points.any((p) => p.kind == 'meeting' || p.kind == 'meeting_request')).length),
      ('doubts', 'Doubts to answer', doubts),
    ];
    return Padding(
      key: const ValueKey('plan-today-counts'),
      padding: const EdgeInsets.only(top: 8),
      child: GuideCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            for (final c in counts)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 84, maxWidth: 140),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${c.$3}', key: ValueKey('plan-count-${c.$1}'), style: t.cardTitleSmall.copyWith(fontSize: 20, color: g.agent)),
                    Text(c.$2, style: t.caption),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The day's batch: how many students, how many done and left, "Next 4 ready", and the guide's own number a day.
  Widget _batchCard(BuildContext context, PlanBatch b) {
    final g = context.g;
    final t = context.gText;
    final size = _sizeChosen ?? b.size;
    return Padding(
      key: const ValueKey('plan-batch'),
      padding: const EdgeInsets.only(top: 8),
      child: GuideCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text("Today's students", style: t.cardTitleSmall)),
                Text('done ${b.done} · left ${b.left}', key: const ValueKey('plan-batch-counts'), style: t.bodyStrong.copyWith(color: g.agent)),
              ],
            ),
            if (b.nextReady) ...[
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerLeft, child: _tag(context, 'Next ${b.size} ready', key: const ValueKey('plan-next-ready'))),
            ],
            if (b.carried > 0) ...[
              const SizedBox(height: 4),
              Text('${b.carried} carried over from an earlier day, on top.', key: const ValueKey('plan-carried-note'), style: t.caption),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: Text('Students a day', style: t.small)),
                _stepButton(context, key: const ValueKey('plan-size-less'), tooltip: 'Fewer students a day', icon: Icons.remove, onPressed: size > 1 && !_savingSize ? () => _setSize(size - 1) : null),
                SizedBox(width: 36, child: Text('$size', key: const ValueKey('plan-size'), textAlign: TextAlign.center, style: t.cardTitleSmall.copyWith(color: g.text))),
                _stepButton(context, key: const ValueKey('plan-size-more'), tooltip: 'More students a day', icon: Icons.add, onPressed: size < 12 && !_savingSize ? () => _setSize(size + 1) : null),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One side of the "Students a day" stepper. Its colours are the theme's own and always legible, light or dark (text on the chip fill, at least
  /// 4.5:1): ENABLED is a filled chip with a strong ring and the page's text colour; DISABLED is an empty ring with the muted text colour.
  Widget _stepButton(BuildContext context, {required Key key, required String tooltip, required IconData icon, required VoidCallback? onPressed}) {
    final g = context.g;
    bool off(Set<WidgetState> s) => s.contains(WidgetState.disabled);
    return IconButton(
      key: key,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        fixedSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStateProperty.resolveWith((s) => CircleBorder(side: BorderSide(color: off(s) ? g.border : g.text, width: off(s) ? 1 : 1.5))),
        backgroundColor: WidgetStateProperty.resolveWith((s) => off(s) ? Colors.transparent : g.chipBackground),
        foregroundColor: WidgetStateProperty.resolveWith((s) => off(s) ? g.mutedText : g.text),
      ),
    );
  }

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

  Future<void> _setSize(int n) async {
    setState(() {
      _sizeChosen = n;
      _savingSize = true;
    });
    try {
      await HierarchyApi.instance.savePlanSettings(dailyBatch: n);
    } catch (e) {
      if (mounted) {
        setState(() => _sizeChosen = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is HierarchyException ? e.message : 'Could not save that. Please try again.')));
      }
    }
    if (mounted) setState(() => _savingSize = false);
  }

  /// THIS WEEK: a clean overview and nothing else. The totals, then INTERACTIONS day by day (names only, the Surrender % small, the done ones
  /// ticked; a tap opens that student's card), TARGET TASKS and OTHER TASKS as short lists. The details (topics, one-line reasons) are only in
  /// TODAY, on each student's card.
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

    Widget header(String text, String key) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 8), child: GuideSectionTitle(text, key: ValueKey(key)));
    Widget none(String key) => Padding(padding: const EdgeInsets.only(top: 2), child: Text('None yet', key: ValueKey(key), style: t.small));

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
                Flexible(child: Text(it.studentName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong.copyWith(fontSize: 14, color: done ? g.mutedText : g.text))),
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

    return [
      // the totals
      Padding(
        key: const ValueKey('plan-progress'),
        padding: const EdgeInsets.only(top: 4),
        child: GuideCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text('Interactions this week: ${p.needed} · done ${p.done} · left ${p.left}', key: const ValueKey('plan-progress-summary'), style: t.cardTitleSmall),
        ),
      ),
      header('Interactions', 'plan-week-section-interactions'),
      if (dayKeys.isEmpty) none('plan-week-empty-interactions'),
      for (final d in dayKeys)
        Padding(
          key: ValueKey('plan-week-day-$d'),
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dayTitle(d), style: t.caption.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final it in days[d]!) name(it)]),
            ],
          ),
        ),
      header('Target tasks', 'plan-week-section-targettasks'),
      if (tasks.isEmpty) none('plan-week-empty-targettasks'),
      for (final it in tasks)
        Padding(
          key: ValueKey('plan-week-task-${it.id}'),
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(it.done ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: it.done ? g.success : g.mutedText),
              const SizedBox(width: 10),
              Expanded(child: Text(it.title, style: t.body.copyWith(height: 1.35))),
            ],
          ),
        ),
      header('Other tasks', 'plan-week-section-othertasks'),
      if (others.isEmpty) none('plan-week-empty-othertasks'),
      for (final it in others)
        Padding(
          key: ValueKey('plan-week-other-${it.id}'),
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 78, child: Text(dayTitle(it.scheduledFor), style: t.caption.copyWith(fontWeight: FontWeight.w700))),
              Expanded(child: Text(it.title, style: t.body.copyWith(height: 1.35))),
            ],
          ),
        ),
      // a HOD's summary of every guide, below his own
      for (final s in plan.sections)
        if (s.id == 'guides') ...[
          header(s.title, 'plan-week-section-guides'),
          for (final it in s.items) _itemCard(context, it),
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
      setState(() => _tab = 0);
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

  /// ONE CARD PER STUDENT, short and factual: his name and Surrender %, then each topic as a TITLE and ONE line with the direction (written by plain
  /// code on the server: no questions, no talking points), and at most one "Also: ..." line. A non-student item (a target task, a phase end ...) is
  /// its title and one line.
  Widget _itemCard(BuildContext context, PlanItem it, {int total = 0}) {
    final g = context.g;
    final t = context.gText;
    final when = it.scheduledFor.isEmpty ? null : DateTime.tryParse(it.scheduledFor);
    final inBatch = it.batchPosition != null;
    return Padding(
      key: ValueKey('plan-item-${it.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: GuideCard(
        key: it.isCard && it.studentUid.isNotEmpty ? _cardKeys.putIfAbsent(it.studentUid, GlobalKey.new) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (it.done) ...[
                  Icon(Icons.check_circle, key: ValueKey('plan-done-${it.id}'), size: 18, color: g.success),
                  const SizedBox(width: 6),
                ],
                // the student's Surrender % beside his name (the list is in that order: highest first, a worry on top)
                Expanded(
                  child: it.isCard && it.studentUid.isNotEmpty
                      ? InkWell(
                          key: ValueKey('plan-open-${it.id}'),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentProfilePage(studentUid: it.studentUid))),
                          child: Text(it.isInteraction && it.percent != null ? '${it.title} · ${it.percent}%' : it.title, key: ValueKey('plan-title-${it.id}'), style: t.cardTitleSmall),
                        )
                      : Text(it.isInteraction && it.percent != null ? '${it.title} · ${it.percent}%' : it.title, key: ValueKey('plan-title-${it.id}'), style: t.cardTitleSmall),
                ),
              ],
            ),
            if (inBatch) ...[
              const SizedBox(height: 2),
              Text('Student ${it.batchPosition}${total > 0 ? ' of $total' : ''}', key: ValueKey('plan-position-${it.id}'), style: t.caption.copyWith(color: g.agent)),
            ],
            if (when != null) ...[
              const SizedBox(height: 2),
              Text(DateFormat('EEE d MMM').format(when), style: t.caption.copyWith(color: g.agent)),
            ],
            // every topic: a title and ONE line
            if (it.points.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < it.points.length; i++)
                Padding(
                  key: ValueKey('plan-point-${it.id}-$i'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (it.points[i].title.isNotEmpty) Text(it.points[i].title, key: ValueKey('plan-point-title-${it.id}-$i'), style: t.bodyStrong.copyWith(fontSize: 14, color: g.agent)),
                      Text(it.points[i].text, key: ValueKey('plan-point-text-${it.id}-$i'), style: t.small.copyWith(height: 1.35)),
                    ],
                  ),
                ),
              if (it.also.isNotEmpty) Text(it.also, key: ValueKey('plan-also-${it.id}'), style: t.caption.copyWith(height: 1.3)),
            ] else if (it.detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(it.detail, style: t.small.copyWith(height: 1.35)),
            ],
            if (it.done || it.carriedOver || (it.checkWithHim && !it.isCard)) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (it.done) _tag(context, 'Done'),
                  if (it.carriedOver) _tag(context, 'Carried over', key: ValueKey('plan-carried-${it.id}')),
                  if (it.checkWithHim && !it.isCard) _tag(context, pronouned('Check with him first', it.gender, name: it.studentName)),
                ],
              ),
            ],
          ],
        ),
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

/// The small round badge with the number of pending changes (the Refresh button, the Home plan widgets). Tapping it lists them.
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
        label: '$count pending change${count == 1 ? '' : 's'}',
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

/// The short list a tap on the badge shows: "2 changes: interaction with Ravi; interaction with Amit", one line each. They are cleared when the plan
/// is refreshed (the AI then considers them).
Future<void> showPendingChanges(BuildContext context, PendingChanges pending) => showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.gText;
        return GuideDialog(
          title: Text('${pending.count} change${pending.count == 1 ? '' : 's'} since the last refresh', key: const ValueKey('pending-title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pending.summary, key: const ValueKey('pending-summary'), style: t.small.copyWith(height: 1.4)),
                const SizedBox(height: 10),
                for (final c in pending.items) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${c.text}', style: t.body.copyWith(fontSize: 14, height: 1.35))),
                const SizedBox(height: 8),
                Text('Tap Refresh and the AI will take them into account.', style: t.caption),
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
