import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/GoalData.dart';
import '../utils/GoalMetrics.dart';
import '../utils/AdminProfile.dart';
import '../utils/Snackbar.dart';
import '../widgets/GuideButtons.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideGhost.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import 'CompoundGoalHodReview.dart';
import 'CompoundGoalProgressPage.dart';
import 'GoalSetup.dart';
import 'GoalWeeklyPhasePage.dart';

/// The ONE reachable entry point for compound targets — replaces the old
/// `GoalSetupPage` as `Home/Dashboard.dart`'s "Semester goal" destination.
///
/// ⚠️ Before this page existed, `CompoundGoalSetupPage`,
/// `CompoundGoalHodReview` and `GoalWeeklyPhasePage`/`CompoundGoalProgressPage`
/// were fully built but reachable from NOWHERE in the app's real navigation
/// — `Dashboard.dart` still pushed the OLD `GoalSetupPage` exclusively (see
/// this task's Part 1 discovery). This page is what actually wires the
/// compound flow in: it lists the guide's own targets (tap through to
/// `GoalWeeklyPhasePage`/`CompoundGoalProgressPage`), offers "+ New target"
/// (`CompoundGoalSetupPage`), and — only for the HOD — a way to reach
/// `CompoundGoalHodReview` to propose changes on any guide's targets.
class GoalHomePage extends StatefulWidget {
  final String guideId;

  const GoalHomePage({super.key, required this.guideId});

  @override
  State<GoalHomePage> createState() => _GoalHomePageState();
}

class _GoalHomePageState extends State<GoalHomePage> {
  String get guideId => widget.guideId;

  // Role check (several HODs may exist; no id is special).
  bool get _isHod => AdminProfileProvider.viewerIsHod;

  /// The ghost of one target card: the real card laid out invisibly, then a soft fill.
  Widget _cardGhost() {
    final sample = CompoundTarget.from(guideId, 'ghost', {
      'metric': kMetricChanting,
      'studentCountGoal': 20,
      'perStudentValueGoal': 16,
      'status': 'active',
      'currentPhase': 1,
      'totalPhases': 8,
    });
    return GuideGhostOf(
      inset: const EdgeInsets.only(bottom: 12),
      placeholder: _CompoundTargetCard(guideId: guideId, target: sample),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GuideScaffold(
      body: Column(
        children: [
          GuideTopBar(
            title: "Your targets",
            actions: [
              if (_isHod)
                GuideRoundButton(
                  icon: Icons.rate_review_outlined,
                  tooltip: "Review guides' targets",
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompoundGoalHodReview(hodUid: guideId),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<CompoundTarget>>(
              stream: GoalData.instance.targets(guideId),
              builder: (context, snap) {
                final targets = (snap.data ?? const <CompoundTarget>[])
                    .where((t) => t.isActive)
                    .toList();
                final state = snap.hasError
                    ? GuideLoad.error
                    : !snap.hasData
                        ? GuideLoad.loading
                        : targets.isEmpty
                            ? GuideLoad.empty
                            : GuideLoad.content;

                return ListView(
                  // Room for the pinned "New target" button.
                  padding: const EdgeInsets.fromLTRB(
                      GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 24),
                  children: [
                    GuideStateView(
                      state: state,
                      ghost: Column(children: [_cardGhost(), _cardGhost()]),
                      content: Column(
                        children: [
                          for (var i = 0; i < targets.length; i++)
                            GuideEntry(
                              index: i,
                              child: _CompoundTargetCard(guideId: guideId, target: targets[i]),
                            ),
                        ],
                      ),
                      emptyMessage: "No active targets yet. Create a compound target — "
                          "\"N students each at a value\" — and get a real, "
                          "AI-generated phase plan from your group's actual "
                          "current numbers.",
                      errorMessage:
                          'Could not load your targets. Check your connection and try again.',
                      onRetry: () => setState(() {}),
                    ),
                  ],
                );
              },
            ),
          ),
          // Pinned at the bottom: a full-width brass button.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  GuideSpace.pagePadding, 8, GuideSpace.pagePadding, 16),
              child: GuidePrimaryButton(
                label: "New target",
                icon: Icons.add_rounded,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompoundGoalSetupPage(guideId: guideId),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One target's card. A [StatefulWidget] (not a plain method on
/// [GoalHomePage]) specifically to hold [_retrying]'s local loading state
/// for the "Retry plan generation" action below.
///
/// ⚠️ **Recoverability, per the task that added this.** A target whose
/// `generateCompoundPlan` call failed (e.g. the function wasn't deployed
/// yet, or a transient OpenAI error) is left with `totalPhases == 0` —
/// a real, saved Firestore document, NOT half-initialized garbage. Before
/// this fix, the only way forward was silence: both action buttons stayed
/// permanently disabled with no way to retry, so a guide's only real option
/// was to abandon the target and create a fresh one (leaving the failed
/// shell orphaned forever, since nothing ever cleans those up).
/// `_retry()` below calls [callGenerateCompoundPlan] on the SAME
/// `guideId`/`targetId` this card already has — the exact function
/// `CompoundGoalSetupPage` calls right after creating a target, just
/// invoked again on an existing shell instead of a new one.
class _CompoundTargetCard extends StatefulWidget {
  final String guideId;
  final CompoundTarget target;

  const _CompoundTargetCard({required this.guideId, required this.target});

  @override
  State<_CompoundTargetCard> createState() => _CompoundTargetCardState();
}

class _CompoundTargetCardState extends State<_CompoundTargetCard> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await callGenerateCompoundPlan(
        guideId: widget.guideId,
        targetId: widget.target.targetId,
      );
      if (!mounted) return;
      showSnackbar(context, "Plan generated", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
        context,
        "Still could not generate a plan — please try again shortly",
        Colors.red,
        Icons.error,
      );
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  bool _deleting = false;

  /// Deletes the target and its phases, after naming what will go.
  ///
  /// The server decides who may (`requireGoalAccess`: the target's own guide,
  /// or a HOD); this only asks, then calls. A target is a plan, not a record
  /// of what happened, so there is nothing to keep once the guide says it is
  /// wrong — and a leftover plan would block the next target of that metric.
  Future<void> _confirmDelete() async {
    final target = widget.target;
    final phases = target.totalPhases;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: const Text('Delete this target?'),
        content: Text(
          phases == 0
              ? 'The target goes for good. You can create a new one straight away.'
              : 'The target and its $phases phase${phases == 1 ? '' : 's'} of '
                  'tasks go for good. You can create a new one straight away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const ValueKey('confirm-delete-target'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await callDeleteCompoundTarget(
        guideId: widget.guideId,
        targetId: target.targetId,
      );
      if (!mounted) return;
      showSnackbar(context, 'Target deleted', Colors.green,
          Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, 'Could not delete the target just now.',
          Colors.red, Icons.error);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final metric = target.metricInfo;
    final needsGeneration = target.totalPhases == 0;
    final t = context.gText;
    final g = context.g;
    final pastel = switch (target.metric) {
      kMetricChanting => GuidePastel.sage,
      kMetricBooks => GuidePastel.sand,
      _ => GuidePastel.mauve,
    };
    final fraction =
        target.totalPhases == 0 ? 0.0 : target.currentPhase / target.totalPhases;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GuideCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_deleting)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                    key: const ValueKey('delete-target'),
                    tooltip: 'Delete this target',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline, size: 18, color: g.mutedText),
                    onPressed: _confirmDelete,
                  ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: g.pastel(pastel),
                    borderRadius: BorderRadius.circular(GuideShape.iconTileRadius),
                  ),
                  child: Icon(
                    target.metric == kMetricBooks
                        ? Icons.menu_book_outlined
                        : Icons.self_improvement_outlined,
                    size: 20,
                    color: GuideColors.onPastel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(metric?.label ?? target.metric,
                          style: t.cardTitle.copyWith(fontSize: 16, height: 1.3)),
                      const SizedBox(height: 3),
                      Text(
                        "${target.studentCountGoal} students at "
                        "${target.perStudentValueGoal} ${metric?.unit ?? ''}",
                        style: t.small,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (needsGeneration)
              Text(
                "No plan yet — generation didn't complete",
                style: t.small.copyWith(color: g.danger),
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      "Phase ${target.currentPhase} of ${target.totalPhases}"
                      "${target.pendingProposal != null ? " · proposal pending" : ""}",
                      style: t.caption,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text("${(fraction * 100).round()}%", style: t.caption),
                ],
              ),
              const SizedBox(height: 6),
              GuideProgressBar(value: fraction),
            ],
            const SizedBox(height: 14),
            if (needsGeneration)
              GuideSecondaryButton(
                expand: true,
                icon: _retrying ? null : Icons.refresh_rounded,
                label: _retrying ? "Generating…" : "Retry plan generation",
                onPressed: _retrying ? null : _retry,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: GuideSecondaryButton(
                      expand: true,
                      label: "This week",
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GoalWeeklyPhasePage(
                            guideId: widget.guideId,
                            targetId: target.targetId,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GuideSecondaryButton(
                      expand: true,
                      label: "Progress",
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompoundGoalProgressPage(
                            guideId: widget.guideId,
                            targetId: target.targetId,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
