import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Services/HierarchyApi.dart';
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
  /// Interaction cards whose questions were toggled by the guide (a batch card starts open, any other starts closed).
  final Set<String> _toggled = {};

  /// The students-a-day number the guide just chose (shown at once, until the server's new plan arrives).
  int? _sizeChosen;
  bool _savingSize = false;

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
    final students = items.where((i) => i.isInteraction).toList();
    final others = items.where((i) => !i.isInteraction).toList();
    final date = DateTime.tryParse(plan.todayDate);
    return [
      GuideSectionTitle(date == null ? 'Today' : 'Today — ${DateFormat('EEEE d MMMM').format(date)}'),
      const SizedBox(height: 4),
      if (plan.batch != null) _batchCard(context, plan.batch!),
      if (items.isEmpty)
        GuideCard(padding: const EdgeInsets.all(16), child: Text('Nothing is planned for today. A quiet day — enjoy it.', key: const ValueKey('plan-today-empty'), style: t.small))
      else ...[
        for (var i = 0; i < students.length; i++) GuideEntry(index: i, child: _itemCard(context, students[i], total: plan.batch?.members ?? students.length)),
        if (others.isNotEmpty && students.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: GuideSectionTitle('Also today', key: const ValueKey('plan-also-today'))),
        for (var i = 0; i < others.length; i++) GuideEntry(index: students.length + i, child: _itemCard(context, others[i])),
      ],
    ];
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
                Text(b.members == 0 ? 'none needed' : 'done ${b.done} · left ${b.left}', key: const ValueKey('plan-batch-counts'), style: t.bodyStrong.copyWith(color: g.agent)),
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
                IconButton(key: const ValueKey('plan-size-less'), tooltip: 'Fewer students a day', icon: const Icon(Icons.remove_circle_outline), onPressed: size > 1 && !_savingSize ? () => _setSize(size - 1) : null),
                SizedBox(width: 28, child: Text('$size', key: const ValueKey('plan-size'), textAlign: TextAlign.center, style: t.bodyStrong)),
                IconButton(key: const ValueKey('plan-size-more'), tooltip: 'More students a day', icon: const Icon(Icons.add_circle_outline), onPressed: size < 12 && !_savingSize ? () => _setSize(size + 1) : null),
              ],
            ),
          ],
        ),
      ),
    );
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

  List<Widget> _weekBody(BuildContext context, PlanDoc plan) {
    final t = context.gText;
    return [
      if (plan.intro.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(plan.intro, key: const ValueKey('plan-intro'), style: t.body.copyWith(height: 1.45))),
      if (plan.progress != null) _progressCard(context, plan.progress!),
      if (plan.sections.isEmpty)
        GuideCard(padding: const EdgeInsets.all(16), child: Text('Nothing to plan this week yet.', key: const ValueKey('plan-week-empty'), style: t.small)),
      for (final s in plan.sections) ...[
        Padding(padding: const EdgeInsets.only(top: 8), child: GuideSectionTitle(s.title)),
        const SizedBox(height: 4),
        for (final it in s.items) _itemCard(context, it),
      ],
    ];
  }

  /// "Interactions needed: 20 · done 4 · left 16", and the same for each source, as bars.
  Widget _progressCard(BuildContext context, PlanProgress p) {
    final g = context.g;
    final t = context.gText;
    return Padding(
      key: const ValueKey('plan-progress'),
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: GuideCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.summary, key: const ValueKey('plan-progress-summary'), style: t.cardTitleSmall),
            const SizedBox(height: 6),
            for (final s in p.bySource) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: Text(s.label, style: t.small)),
                  Text('done ${s.done} · left ${s.left}', key: ValueKey('plan-progress-${s.id}'), style: t.caption),
                ],
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: s.needed == 0 ? 0 : s.done / s.needed, minHeight: 6, backgroundColor: g.chipBackground, color: g.agentMid),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemCard(BuildContext context, PlanItem it, {int total = 0}) {
    final g = context.g;
    final t = context.gText;
    final when = it.scheduledFor.isEmpty ? null : DateTime.tryParse(it.scheduledFor);
    final inBatch = it.batchPosition != null;
    return Padding(
      key: ValueKey('plan-item-${it.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: GuideCard(
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
                Expanded(child: Text(it.title, style: t.cardTitleSmall)),
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
            if (it.how.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(it.how, key: ValueKey('plan-how-${it.id}'), style: t.small.copyWith(height: 1.4, fontWeight: FontWeight.w600)),
            ],
            if (it.detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(it.detail, style: t.small.copyWith(height: 1.4)),
            ],
            if (it.topicLabels.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Topics: ${it.topicLabels.join(', ')}', key: ValueKey('plan-topic-names-${it.id}'), style: t.caption),
            ],
            if (it.checkWithHim || it.forYou || it.done || it.percent != null || it.carriedOver || it.inToday) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (it.done) _tag(context, 'Done'),
                  if (it.carriedOver) _tag(context, 'Carried over', key: ValueKey('plan-carried-${it.id}')),
                  if (it.inToday) _tag(context, "In today's batch"),
                  if (it.checkWithHim) _tag(context, 'Check with him first'),
                  if (it.forYou && !it.done) _tag(context, 'For you to do'),
                  if (it.percent != null) _tag(context, 'Surrender ${it.percent}%'),
                ],
              ),
            ],
            if (it.topics.isNotEmpty) _topics(context, it),
            if (inBatch && it.reportBack.isNotEmpty && !it.done) ...[
              const SizedBox(height: 6),
              Text(it.reportBack, key: ValueKey('plan-report-${it.id}'), style: t.small.copyWith(height: 1.4, fontWeight: FontWeight.w700, color: g.agent)),
            ],
          ],
        ),
      ),
    );
  }

  /// An interaction's topics: a section of questions and suggestions for EACH reason, opened with a tap (read-only: to record what happened,
  /// tell the assistant).
  Widget _topics(BuildContext context, PlanItem it) {
    final g = context.g;
    final t = context.gText;
    final open = (it.batchPosition != null) != _toggled.contains(it.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: ValueKey('plan-topics-toggle-${it.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _toggled.contains(it.id) ? _toggled.remove(it.id) : _toggled.add(it.id)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
            child: Row(
              children: [
                Expanded(child: Text(open ? 'Hide the questions' : 'Questions and suggestions (${it.topics.length} topic${it.topics.length == 1 ? '' : 's'})', style: t.bodyStrong.copyWith(color: g.agent))),
                Icon(open ? Icons.expand_less : Icons.expand_more, color: g.agent),
              ],
            ),
          ),
        ),
        if (open)
          Column(
            key: ValueKey('plan-topics-${it.id}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (it.briefSource == 'fallback') Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('A plain version: the AI had not written these yet.', style: t.caption)),
              for (final topic in it.topics) ...[
                const SizedBox(height: 6),
                Text(topic.label, style: t.bodyStrong),
                Text(topic.reason, style: t.caption),
                if (topic.meaning.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(topic.meaning, style: t.small.copyWith(height: 1.4))),
                const SizedBox(height: 4),
                for (var i = 0; i < topic.questions.length; i++) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('${i + 1}. ${topic.questions[i]}', style: t.small.copyWith(height: 1.35))),
                for (final s in topic.suggestions) Padding(padding: const EdgeInsets.only(top: 2), child: Text('${it.batchPosition != null ? 'Encourage' : 'Suggestion'}: $s', style: t.small.copyWith(height: 1.35, color: g.mutedText))),
                for (final c in topic.conclusions) Padding(padding: const EdgeInsets.only(top: 2), child: Text('To share: $c', style: t.small.copyWith(height: 1.35, color: g.mutedText))),
              ],
            ],
          ),
      ],
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

/// TODAY | THIS WEEK, a two-way toggle under the app bar: each side a 48 dp target, the chosen one in the assistant's sky blue.
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
