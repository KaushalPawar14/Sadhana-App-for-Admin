import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/PlanData.dart';
import '../utils/SeenMarkers.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideSurface.dart';

/// "Plan": the guide's TODAY and THIS WEEK plans, worked out by the server and shown READ-ONLY (no ticking, no replying: for any help,
/// ask the assistant in a chat).
///
/// Under "Last updated" the page says honestly where the plan stands, from the server's own schedule (never a made-up timer):
///   Up to date                                        nothing has changed since the last update
///   New changes found - updating in N min (at 4:30 PM) changes found, but an update ran less than an hour ago; the countdown runs
///                                                     to `pendingRunAt`, the real time the server will run it. At night (11 PM - 5 AM)
///                                                     nothing runs automatically: "Next update at 6:00 AM"
///   Updating now...                                   the server is working the plan out; then the new plan appears with a short
///                                                     "Updated" highlight
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

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

/// Whether the instant is exactly 6:00 AM India time: the night's changes wait for that run.
bool isSixAmIst(DateTime t) {
  final ist = t.toUtc().add(const Duration(hours: 5, minutes: 30));
  return ist.hour == 6 && ist.minute == 0;
}

/// The status line under "Last updated".
String planStatusText(PlanDoc plan, DateTime now) {
  switch (plan.status) {
    case 'updating':
      return 'Updating now…';
    case 'pending':
      final at = plan.pendingRunAt;
      if (at == null) return 'New changes found — updating soon';
      if (isSixAmIst(at) && at.difference(now).inMinutes >= 60) return 'New changes found — next update at ${planClock(at)}';
      final left = at.difference(now);
      if (left.inSeconds <= 0) return 'New changes found — updating any moment now…';
      if (left.inSeconds < 60) return 'New changes found — updating in ${left.inSeconds} s (at ${planClock(at)})';
      final mins = (left.inSeconds / 60).ceil();
      return 'New changes found — updating in $mins min (at ${planClock(at)})';
    default:
      return 'Up to date';
  }
}

class _PlanPageState extends State<PlanPage> {
  bool _week = false;
  PlanDoc? _plan;
  bool _loaded = false;
  bool _failed = false;
  bool _justUpdated = false;
  DateTime? _lastGenerated;
  StreamSubscription<PlanDoc?>? _sub;
  Timer? _tick;
  Timer? _highlight;

  String get _me => AdminProfileProvider.current?.id ?? '';

  @override
  void initState() {
    super.initState();
    // opening the plan clears its orange dot
    if (_me.isNotEmpty) SeenMarkers.markSeen(_me, 'plan').catchError((_) {});
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
        _syncTicker();
      },
      onError: (_) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  /// The live countdown ticks only while an update is pending: nothing runs otherwise.
  void _syncTicker() {
    final pending = _plan?.status == 'pending';
    if (pending && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!pending) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _highlight?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return GuideScaffold(
      appBar: GuideAppBar(
        title: const Text('Plan'),
        bottom: _PlanToggle(week: _week, onChanged: (w) => setState(() => _week = w)),
      ),
      body: GuideCrossFade(
        child: !_loaded && !_failed
            ? const KeyedSubtree(key: ValueKey('plan-wait'), child: Center(child: CircularProgressIndicator()))
            : _failed
                ? KeyedSubtree(key: const ValueKey('plan-failed'), child: Center(child: Text('Could not load your plan.', style: context.gText.small.copyWith(color: g.mutedText))))
                : KeyedSubtree(key: ValueKey(_week ? 'week' : 'today'), child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    final plan = _plan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 40),
      children: [
        Text('Read-only — for any help, ask the AI in a chat.', key: const ValueKey('plan-readonly'), style: t.bodyStrong),
        const SizedBox(height: 6),
        Text(
          'Changes you make in the app (e.g. marking a book completed, changing a date) appear here within about an hour. For an instant answer, ask the AI in a chat.',
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
          if (_week) ..._weekBody(context, plan) else ..._todayBody(context, plan),
        ],
        SizedBox(height: g.isDark ? 0 : 0),
      ],
    );
  }

  Widget _statusCard(BuildContext context, PlanDoc plan) {
    final g = context.g;
    final t = context.gText;
    final now = PlanData.instance.now();
    final stamp = plan.generatedAt == null ? '—' : DateFormat('EEE d MMM, h:mm a').format(plan.generatedAt!.toUtc().add(const Duration(hours: 5, minutes: 30)));
    final status = planStatusText(plan, now);
    final busy = plan.status != 'upToDate';
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
          Text('Last updated: $stamp', key: const ValueKey('plan-last-updated'), style: t.small),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _justUpdated ? Icons.check_circle_outline : (plan.status == 'updating' ? Icons.sync : (busy ? Icons.schedule : Icons.check_circle_outline)),
                size: 18,
                color: busy ? g.warning : g.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _justUpdated ? 'Updated' : status,
                  key: const ValueKey('plan-status-text'),
                  style: t.bodyStrong.copyWith(color: busy && !_justUpdated ? g.text : g.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _todayBody(BuildContext context, PlanDoc plan) {
    final t = context.gText;
    final items = plan.todayItems;
    final date = DateTime.tryParse(plan.todayDate);
    return [
      GuideSectionTitle(date == null ? 'Today' : 'Today — ${DateFormat('EEEE d MMMM').format(date)}'),
      const SizedBox(height: 4),
      if (items.isEmpty)
        GuideCard(padding: const EdgeInsets.all(16), child: Text('Nothing is planned for today. A quiet day — enjoy it.', key: const ValueKey('plan-today-empty'), style: t.small))
      else
        for (var i = 0; i < items.length; i++) GuideEntry(index: i, child: _itemCard(context, items[i])),
    ];
  }

  List<Widget> _weekBody(BuildContext context, PlanDoc plan) {
    final t = context.gText;
    return [
      if (plan.intro.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(plan.intro, key: const ValueKey('plan-intro'), style: t.body.copyWith(height: 1.45))),
      if (plan.sections.isEmpty)
        GuideCard(padding: const EdgeInsets.all(16), child: Text('Nothing to plan this week yet.', key: const ValueKey('plan-week-empty'), style: t.small)),
      for (final s in plan.sections) ...[
        Padding(padding: const EdgeInsets.only(top: 8), child: GuideSectionTitle(s.title)),
        const SizedBox(height: 4),
        for (final it in s.items) _itemCard(context, it),
      ],
    ];
  }

  Widget _itemCard(BuildContext context, PlanItem it) {
    final g = context.g;
    final t = context.gText;
    final when = it.scheduledFor.isEmpty ? null : DateTime.tryParse(it.scheduledFor);
    return Padding(
      key: ValueKey('plan-item-${it.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: GuideCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(it.title, style: t.cardTitleSmall),
            if (when != null) ...[
              const SizedBox(height: 2),
              Text(DateFormat('EEE d MMM').format(when), style: t.caption.copyWith(color: g.agent)),
            ],
            if (it.detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(it.detail, style: t.small.copyWith(height: 1.4)),
            ],
            if (it.checkWithHim || it.forYou) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (it.checkWithHim) _tag(context, 'Check with him first'),
                  if (it.forYou) _tag(context, 'For you to do'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String label) {
    final g = context.g;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: g.chipBackground, borderRadius: BorderRadius.circular(GuideShape.chipRadius)),
      child: Text(label, style: context.gText.pill),
    );
  }
}

/// TODAY | THIS WEEK, a two-way toggle under the app bar: each side a 48 dp target, the chosen one in saffron.
class _PlanToggle extends StatelessWidget implements PreferredSizeWidget {
  const _PlanToggle({required this.week, required this.onChanged});

  final bool week;
  final ValueChanged<bool> onChanged;

  @override
  Size get preferredSize => const Size.fromHeight(GuideShape.touchTarget + 12);

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    Widget side(String label, bool isWeek, Key key) {
      final on = week == isWeek;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(isWeek),
            child: Container(
              height: GuideShape.touchTarget,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? g.agentMid : Colors.transparent,
                borderRadius: BorderRadius.circular(GuideShape.chipRadius),
              ),
              child: Text(label, style: t.bodyStrong.copyWith(color: on ? g.onAgent : g.text, letterSpacing: .6)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 4, GuideSpace.pagePadding, 8),
      child: Container(
        decoration: BoxDecoration(color: g.chipBackground, borderRadius: BorderRadius.circular(GuideShape.chipRadius + 2)),
        child: Row(children: [side('TODAY', false, const ValueKey('plan-tab-today')), side('THIS WEEK', true, const ValueKey('plan-tab-week'))]),
      ),
    );
  }
}
