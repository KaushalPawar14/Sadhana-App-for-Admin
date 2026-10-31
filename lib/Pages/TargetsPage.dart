import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/GoalMetrics.dart';
import '../utils/HomeData.dart';
import '../utils/PlanData.dart';
import '../utils/Responsive.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideGhost.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/PressScale.dart';
import 'CompoundGoalProgressPage.dart';
import 'GoalSetup.dart';

/// THE TARGETS PAGE: the guide's targets as big, calm cards, one under another on a phone (side by side on the website): CHANTING in gold, READING in sky blue and FOLK in purple (FOLK only for the roles
/// that have it: not a Female Enabler). Each card is about half the screen tall and says: the goal and its end date (or "Not set" with "Set target"), how far it is ("3 of 5 boys at 16 rounds"), the phase
/// it is in, the students whose turn is next, and its state (Active / Ended — choose / Achieved 🎉). A tap opens that target (where it is deleted or extended), or the create flow when it is not set.
/// The numbers come from the same plan the Today and This week pages read (its one combined line), so they never disagree.

/// What one card says about its target, worked out from the target and the plan's combined This-week line.
class TargetCardData {
  const TargetCardData({required this.metric, required this.target, required this.doneCount, required this.totalCount, required this.next});

  final String metric;
  final CompoundTarget? target;

  /// "3 of 5" (null when the plan has no line for it yet).
  final int? doneCount;
  final int? totalCount;

  /// The combined next step of the students whose turn is next ("Amit — 12 → 16 · invite to FOLK (direct)").
  final List<String> next;

  static const names = {kMetricChanting: 'CHANTING', kMetricBooks: 'READING', kMetricFolk: 'FOLK'};
  static const plainNames = {kMetricChanting: 'Chanting', kMetricBooks: 'Reading', kMetricFolk: 'FOLK'};

  bool get isSet => target != null;

  /// Whether the end date has been reached (the guide deletes or extends the target).
  bool endedOn(DateTime today) {
    final end = target?.endDate;
    if (end == null) return false;
    return !DateTime(end.year, end.month, end.day).isAfter(DateTime(today.year, today.month, today.day));
  }

  /// Every student reached the goal.
  bool get achieved => (totalCount ?? 0) > 0 && (doneCount ?? 0) >= (totalCount ?? 0) || target?.status == kCompoundStatusCompleted;

  /// "Active", "Ended — choose", "Achieved 🎉" or "Not set".
  String stateWords(DateTime today) {
    if (!isSet) return 'Not set';
    if (achieved) return 'Achieved 🎉';
    if (endedOn(today)) return 'Ended — choose';
    return 'Active';
  }

  /// "16 rounds by 31 Dec" / "4 books by 31 Dec" / "5 FOLK residents by 31 Dec" (null when not set).
  String? get goalWords {
    final x = target;
    if (x == null) return null;
    final by = x.endDate == null ? '' : ' by ${DateFormat('d MMM').format(x.endDate!)}';
    switch (x.metric) {
      case kMetricChanting:
        return '${x.perStudentValueGoal} rounds$by';
      case kMetricBooks:
        return '${x.perStudentValueGoal} book${x.perStudentValueGoal == 1 ? '' : 's'}$by';
      default:
        return '${x.studentCountGoal} FOLK resident${x.studentCountGoal == 1 ? '' : 's'}$by';
    }
  }

  /// "3 of 5 boys at 16 rounds" / "2 of 4 students at 4 books" / "1 of 3 boys living in FOLK".
  String? get progressWords {
    final x = target;
    if (x == null || doneCount == null || totalCount == null) return null;
    switch (x.metric) {
      case kMetricChanting:
        return '$doneCount of $totalCount boys at ${x.perStudentValueGoal} rounds';
      case kMetricBooks:
        return '$doneCount of $totalCount students at ${x.perStudentValueGoal} book${x.perStudentValueGoal == 1 ? '' : 's'}';
      default:
        return '$doneCount of $totalCount boys living in FOLK';
    }
  }

  String? get phaseWords {
    final x = target;
    if (x == null || x.totalPhases <= 0) return null;
    return 'Phase ${x.currentPhase} of ${x.totalPhases}';
  }

  /// All three cards from the targets and the plan.
  static List<TargetCardData> allFrom(List<CompoundTarget> targets, PlanDoc? plan, List<String> metrics) {
    String? journeyTitle;
    var steps = const <PlanStep>[];
    if (plan != null) {
      for (final s in plan.sections) {
        if (s.id != 'targettasks') continue;
        for (final it in s.items) {
          if (it.id == 'weekjourney') {
            journeyTitle = it.title;
            steps = it.steps;
          }
        }
      }
    }
    final parts = (journeyTitle ?? '').split(' · ');
    return [
      for (final m in metrics)
        () {
          CompoundTarget? t;
          for (final x in targets) {
            if (x.isActive && x.metric == m) t = x;
          }
          int? done;
          int? total;
          for (final p in parts) {
            final match = RegExp('^${plainNames[m]} (\\d+) of (\\d+)\$').firstMatch(p);
            if (match != null) {
              done = int.parse(match.group(1)!);
              total = int.parse(match.group(2)!);
            }
          }
          bool mine(PlanStep s) {
            if (s.done) return false;
            final w = s.words;
            switch (m) {
              case kMetricFolk:
                return w.contains('FOLK');
              case kMetricBooks:
                return w.contains('📖');
              default:
                return RegExp(r'\d+ → \d+').hasMatch(w) && !w.contains('📖');
            }
          }

          return TargetCardData(metric: m, target: t, doneCount: done, totalCount: total, next: [for (final s in steps) if (mine(s)) s.words].take(3).toList());
        }(),
    ];
  }
}

class TargetsPage extends StatefulWidget {
  const TargetsPage({super.key, required this.guideId, this.planOwner});

  final String guideId;

  /// Whose plan holds the numbers (a HOD's own); the guide when null.
  final String? planOwner;

  @override
  State<TargetsPage> createState() => _TargetsPageState();
}

class _TargetsPageState extends State<TargetsPage> {
  List<CompoundTarget>? _targets;
  PlanDoc? _plan;
  bool _failed = false;
  final _subs = <dynamic>[];

  @override
  void initState() {
    super.initState();
    _subs.add(HomeData.instance.targets(widget.guideId).listen((t) {
      if (mounted) setState(() => _targets = t);
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    }));
    _subs.add(PlanData.instance.plan(widget.planOwner ?? widget.guideId).listen((p) {
      if (mounted) setState(() => _plan = p);
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  List<String> get _metrics {
    final me = AdminProfileProvider.current;
    return me == null ? const [kMetricChanting, kMetricBooks] : compoundMetricsFor(me);
  }

  void _open(TargetCardData c) {
    final x = c.target;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => x != null ? CompoundGoalProgressPage(guideId: x.guideId, targetId: x.targetId) : CompoundGoalSetupPage(guideId: widget.guideId, initialMetric: c.metric)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _failed ? GuideLoad.error : _targets == null ? GuideLoad.loading : GuideLoad.content;
    final cards = TargetCardData.allFrom(_targets ?? const [], _plan, _metrics);
    final wide = context.isWide;
    // the content column of this window (a computer has the side navigation beside it; at most 1080 dp), less the page padding
    final width = contentWidthOf(context) - 2 * GuideSpace.pagePadding;
    final cardWidth = wide ? (width - GuideSpace.cardGap) / 2 : width;
    return GuideScaffold(
      body: Column(
        children: [
          const GuideTopBar(title: 'Targets'),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, GuideSpace.navClearanceOf(context) + 12),
              child: Align(
                alignment: Alignment.topCenter,
                child: GuideStateView(
                  state: state,
                  ghost: SizedBox(width: width, child: GuideGhostOf(radius: 24, placeholder: _TargetCard(data: TargetCardData(metric: kMetricChanting, target: null, doneCount: null, totalCount: null, next: const []), minHeight: 240, onTap: null))),
                  content: Wrap(
                    key: const ValueKey('targets-list'),
                    spacing: GuideSpace.cardGap,
                    runSpacing: GuideSpace.cardGap,
                    children: [
                      for (var i = 0; i < cards.length; i++)
                        SizedBox(
                          width: cardWidth,
                          child: GuideEntry(index: i, child: _TargetCard(data: cards[i], minHeight: MediaQuery.sizeOf(context).height * 0.5, onTap: () => _open(cards[i]))),
                        ),
                    ],
                  ),
                  errorMessage: 'Could not load your targets. Check your connection and try again.',
                  onRetry: () => setState(() => _failed = false),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.data, required this.minHeight, required this.onTap});

  final TargetCardData data;
  final double minHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final dark = g.isDark;
    final colors = switch (data.metric) {
      kMetricBooks => dark ? GuideColors.targetSkyDark : GuideColors.targetSkyLight,
      kMetricFolk => dark ? GuideColors.targetPurpleDark : GuideColors.targetPurpleLight,
      _ => dark ? GuideColors.targetGoldDark : GuideColors.targetGoldLight,
    };
    final ink = dark ? GuideColors.targetCardTextDark : GuideColors.targetCardTextLight;
    final muted = dark ? GuideColors.targetCardMutedDark : GuideColors.targetCardMutedLight;
    final now = DateTime.now();
    final state = data.stateWords(now);
    final metric = data.metric;
    final icon = metric == kMetricBooks ? Icons.menu_book_outlined : metric == kMetricFolk ? Icons.home_outlined : Icons.self_improvement_outlined;
    final next = data.next;
    return Semantics(
      button: onTap != null,
      label: '${TargetCardData.plainNames[metric]} target: $state',
      child: PressScale(
        enabled: onTap != null,
        child: GestureDetector(
          key: ValueKey('target-card-$metric'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight < 260 ? 260 : minHeight),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: dark ? GuideColors.targetTileShadowDark : GuideColors.targetTileShadowLight, blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: IntrinsicHeight(
              child: DefaultTextStyle.merge(
              style: TextStyle(color: ink),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: ink, size: 26),
                      const SizedBox(width: 10),
                      Expanded(child: Text(TargetCardData.names[metric]!, key: ValueKey('target-title-$metric'), style: t.cardTitleSmall.copyWith(color: ink, letterSpacing: 1.2))),
                      Container(
                        key: ValueKey('target-state-$metric'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: ink.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                        child: Text(state, style: t.small.copyWith(color: ink, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (!data.isSet) ...[
                    Text('Not set', key: ValueKey('target-goal-$metric'), style: t.greeting.copyWith(color: ink, fontSize: 26)),
                    const SizedBox(height: 8),
                    Text(metric == kMetricFolk ? 'Bring boys to live in FOLK, step by step.' : metric == kMetricBooks ? 'Grow how many books each student reads.' : 'Raise the rounds students chant, step by step.', style: t.small.copyWith(color: muted, height: 1.35)),
                    const Spacer(),
                    const SizedBox(height: 18),
                    _CardButton(label: 'Set target', ink: ink, onTap: onTap),
                  ] else ...[
                    Text(data.goalWords ?? '', key: ValueKey('target-goal-$metric'), style: t.greeting.copyWith(color: ink, fontSize: 26)),
                    const SizedBox(height: 10),
                    if (data.progressWords != null) Text(data.progressWords!, key: ValueKey('target-progress-$metric'), style: t.bodyStrong.copyWith(color: ink)),
                    if (data.phaseWords != null) ...[
                      const SizedBox(height: 4),
                      Text(data.phaseWords!, key: ValueKey('target-phase-$metric'), style: t.small.copyWith(color: muted)),
                    ],
                    const SizedBox(height: 14),
                    Text(next.isEmpty ? 'Nobody is waiting for a step right now.' : 'Next', style: t.caption.copyWith(color: muted, fontWeight: FontWeight.w800)),
                    for (var i = 0; i < next.length; i++)
                      Padding(
                        key: ValueKey('target-next-$metric-$i'),
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(next[i], style: t.small.copyWith(color: ink, height: 1.3)),
                      ),
                    const Spacer(),
                    const SizedBox(height: 18),
                    _CardButton(label: state == 'Ended — choose' ? 'Choose: delete or extend' : 'Open target', ink: ink, onTap: onTap),
                  ],
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, required this.ink, required this.onTap});

  final String label;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: ink.withValues(alpha: .14), borderRadius: BorderRadius.circular(16), border: Border.all(color: ink.withValues(alpha: .35))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, style: t.bodyStrong.copyWith(color: ink))),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: ink, size: 20),
          ],
        ),
      ),
    );
  }
}
