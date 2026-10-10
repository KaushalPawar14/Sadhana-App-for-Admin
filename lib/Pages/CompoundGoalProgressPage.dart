import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/GoalMetrics.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';

/// Per-target progress page — Part 7 of the compound-target task, updated
/// when chanting switched from a weekly-report aggregation to a self-set
/// commitment field (see `GoalMetrics.dart`'s own history note).
///
/// ---------------------------------------------------------------------------
/// Both metrics are LIVE now — chanting is no longer weekly-only
/// ---------------------------------------------------------------------------
/// Originally chanting could only be computed by the Monday Cloud Function
/// (checking actual reported behaviour meant resolving name-keyed report
/// documents and scanning whole `dates` subcollections). Now that the figure
/// is "how many students have COMMITTED to at least this many rounds/day"
/// (`users/{uid}.commitmentRounds`, a plain field), it is exactly as cheap
/// to check live as Books' lifetime count — see [liveChantingThresholdCount]
/// / [liveBooksThresholdCount] in `GoalCompoundQueries.dart`, which are now
/// symmetric.
///
/// ⚠️ **This counts COMMITMENT, not behaviour.** Every label below says
/// "committed to N+ {unit}", never "chanted N+ this week" or similar — a
/// student's commitment is what they SAID they will do, not a measurement of
/// what they actually did. Silently keeping the old "actual chanting" wording
/// while the underlying data source changed underneath it would misrepresent
/// what the number means.
///
/// Two sections, never blended:
///  1. THIS PHASE — the current phase's own `tasks` checklist, each with
///     real live progress against its own snapshotted group (task-list
///     phase model task, Part 6).
///  2. OVERALL vs. the target's final `studentCountGoal`/`perStudentValueGoal`
///     — unaffected by the task-list rework, since it evaluates the true end
///     goal directly rather than through any one phase's mechanics.
/// "—" for unknown, never 0 — a read failure must never look like a shortfall.
///
/// ⚠️ Scope note: this shows WEEKLY-phase granularity (matching the
/// evaluator's own Monday cadence for phase advancement — display freshness
/// and evaluation cadence are separate concerns), not a day-by-day
/// breakdown — no per-day rounds pipeline exists to build that from, and
/// building one would be a separate, unscoped addition.
///
/// ---------------------------------------------------------------------------
/// Live early-advance check (task-list phase model task, Part 5 item 2)
/// ---------------------------------------------------------------------------
/// Same as `GoalWeeklyPhasePage.dart`: `initState` calls
/// [callCheckAndAdvanceIfAheadOfSchedule] once per page open, so a guide who
/// finishes every task early sees the phase advance without waiting for
/// Monday's sweep.
class CompoundGoalProgressPage extends StatefulWidget {
  final String guideId;
  final String targetId;

  const CompoundGoalProgressPage({
    super.key,
    required this.guideId,
    required this.targetId,
  });

  @override
  State<CompoundGoalProgressPage> createState() => _CompoundGoalProgressPageState();
}

class _CompoundGoalProgressPageState extends State<CompoundGoalProgressPage> {
  String get guideId => widget.guideId;
  String get targetId => widget.targetId;

  @override
  void initState() {
    super.initState();
    callCheckAndAdvanceIfAheadOfSchedule(guideId: guideId, targetId: targetId)
        .catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: AppBar(
            elevation: 0,
            backgroundColor: colorProvider.color,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Target progress",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: StreamBuilder<CompoundTarget?>(
            stream: compoundTargetStream(guideId, targetId),
            builder: (context, targetSnap) {
              final target = targetSnap.data;
              if (target == null || target.totalPhases == 0) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<List<CompoundPhase>>(
                stream: compoundPhasesStream(guideId, targetId),
                builder: (context, phasesSnap) {
                  final phases = phasesSnap.data ?? const <CompoundPhase>[];
                  final currentPhase = phases.where(
                      (p) => p.phaseNumber == target.currentPhase);
                  if (currentPhase.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _body(target, currentPhase.first);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _body(CompoundTarget target, CompoundPhase phase) {
    final metric = target.metricInfo;
    final isChanting = target.metric == kMetricChanting;
    final unit = metric?.unit ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(
          "${metric?.label ?? target.metric} target",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        if (isChanting) ...[
          const SizedBox(height: 4),
          Text(
            "Counts students COMMITTED to this many rounds/day — not actual "
            "chanting this week.",
            style: TextStyle(fontSize: 11, color: context.g.mutedText),
          ),
        ],
        const SizedBox(height: 14),
        Text("This phase — Phase ${phase.phaseNumber}",
            style: TextStyle(fontSize: 12.5, color: context.g.mutedText)),
        const SizedBox(height: 6),
        _taskProgressCard(phase, target, unit),
        const SizedBox(height: 20),
        Text("Overall — the full goal",
            style: TextStyle(fontSize: 12.5, color: context.g.mutedText)),
        const SizedBox(height: 6),
        _liveThresholdCard(
          compute: () => isChanting
              ? liveChantingThresholdCount(
                  guideId: guideId,
                  perStudentValueGoal: target.perStudentValueGoal,
                )
              : liveBooksThresholdCount(
                  guideId: guideId,
                  perStudentValueGoal: target.perStudentValueGoal,
                ),
          target: target.studentCountGoal,
          thresholdValue: target.perStudentValueGoal,
          unit: unit,
          isChanting: isChanting,
        ),
      ],
    );
  }

  /// Task checklist for the current phase, real live progress per task
  /// (task-list phase model task, Part 6) — same rendering as
  /// `GoalWeeklyPhasePage.dart`'s own checklist, kept file-local since the
  /// two screens have distinct enough surrounding layouts that a shared
  /// widget would need its own plumbing for no real gain yet. Names
  /// resolved once per phase, same pattern as that file (real-names task).
  Widget _taskProgressCard(CompoundPhase phase, CompoundTarget target, String unit) {
    if (phase.tasks.isEmpty) {
      return Text("No tasks in this phase.",
          style: TextStyle(fontSize: 13, color: context.g.mutedText));
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.g.border),
      ),
      child: FutureBuilder<List<TaskProgress>>(
        future: livePhaseProgress(
          tasks: phase.tasks,
          guideId: guideId,
          metric: target.metric,
        ),
        builder: (context, snap) {
          final progress = snap.data;
          return FutureBuilder<Map<String, String>>(
            future: resolveStudentNames(collectStudentUids(phase.tasks)),
            builder: (context, namesSnap) {
              final uidToName = namesSnap.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < phase.tasks.length; i++)
                    _taskProgressLine(
                      phase.tasks[i],
                      unit,
                      progress != null && i < progress.length ? progress[i] : null,
                      uidToName,
                      isLast: i == phase.tasks.length - 1,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _taskProgressLine(
    CompoundTask task,
    String unit,
    TaskProgress? progress,
    Map<String, String>? uidToName, {
    required bool isLast,
  }) {
    final fraction = progress == null
        ? null
        : compoundFraction(actual: progress.actual, target: progress.target);
    final complete = progress?.complete ?? false;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.describe(unit, uidToName),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (complete ? context.g.success : context.g.mutedText)
                      .withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  progress == null
                      ? "…"
                      : complete
                          ? "done"
                          : "${progress.actual}/${progress.target}",
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: complete ? context.g.success : context.g.mutedText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction ?? 0,
              minHeight: 6,
              backgroundColor: context.g.chipBackground,
              valueColor: AlwaysStoppedAnimation<Color>(
                complete ? context.g.success : context.g.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveThresholdCard({
    required Future<int> Function() compute,
    required int target,
    required int thresholdValue,
    required String unit,
    required bool isChanting,
  }) {
    return FutureBuilder<int>(
      future: compute(),
      builder: (context, snap) {
        return _card(
          value: snap.data,
          target: target,
          label: isChanting
              ? "committed to $thresholdValue+ $unit"
              : "at $thresholdValue+ $unit",
        );
      },
    );
  }

  Widget _card({
    required int? value,
    required int target,
    required String label,
  }) {
    final fraction = compoundFraction(actual: value, target: target);
    final actualText = value == null ? "—" : '$value';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.g.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "$actualText / $target students $label",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: context.g.success.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text("live",
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: context.g.success)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction ?? 0,
              minHeight: 6,
              backgroundColor: context.g.chipBackground,
              valueColor: AlwaysStoppedAnimation<Color>(
                fraction == null ? context.g.mutedText : context.g.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
