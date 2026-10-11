import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/GoalMetrics.dart';
import '../utils/SeenMarkers.dart';
import '../utils/Snackbar.dart';
import 'CompoundGoalRoadmapPage.dart';
import 'CompoundTaskEditorPage.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';

/// The compound target's weekly page — Part 5, this continuation task.
///
/// ⚠️ **NOT** `WeeklyPlanning.dart`. That existing file is an unrelated
/// Monday overview (follow-ups, missing submissions, overdue associations) —
/// confirmed by reading it during discovery. This is a new, distinctly named
/// page so the two are never confused in navigation.
///
/// ---------------------------------------------------------------------------
/// Current-phase-only, always — Part 5's core requirement
/// ---------------------------------------------------------------------------
/// This screen reads exactly ONE phase document: whichever `phaseNumber`
/// equals the target's own `currentPhase`. It never fetches or displays the
/// next phase, regardless of how the CURRENT phase's numbers got there —
/// AI-generated at creation, HOD-proposed-then-approved, or the guide's own
/// direct edit below all look identical here, because all three write to the
/// same one phase document this screen reads. Advancing to the next phase is
/// controlled ENTIRELY by `functions/goals.js`'s `evaluateCompoundTarget`
/// (Part 6) — opening this screen, or anything else client-side, can never
/// move `currentPhase` forward.
///
/// ---------------------------------------------------------------------------
/// Guide-only actions
/// ---------------------------------------------------------------------------
///  1. Approve a pending proposal — [approveProposal].
///  2. Reject a pending proposal — [rejectProposal].
///  3. "Edit tasks" — pushes [CompoundTaskEditorPage] (`isHod: false`), the
///     restored manual editor for the CURRENT phase's tasks (roster count,
///     value tasks with a real student picker) — [directlyEditPhaseTasks]
///     writes straight to the live phase, no approval, same no-approval
///     precedent the old flat "Edit this phase" dialog had.
///  4. "Full roadmap" — pushes [CompoundGoalRoadmapPage] (`isHod: false`),
///     a read-only view of every phase PLUS a free-text suggestion box
///     that regenerates via [callRegenerateCompoundPlan]. This screen's own
///     current-phase-only invariant above is unaffected — the roadmap is a
///     separate, deliberately-opened view, not a widening of this one.
///     Sits ALONGSIDE "Edit tasks", not in place of it — both are always
///     available (restored manual-editing task).
///  5. "Change end date" — [_changeEndDate] writes the new `endDate`
///     ([updateTargetEndDate]) then immediately calls
///     [callRegenerateCompoundPlan] with an explanatory note, showing a
///     blocking dialog throughout so the guide sees this happen rather
///     than the plan silently changing underneath them.
///
/// ---------------------------------------------------------------------------
/// Live early-advance check (task-list phase model task, Part 5 item 2)
/// ---------------------------------------------------------------------------
/// Every time this page opens, `initState` calls
/// [callCheckAndAdvanceIfAheadOfSchedule] once. If every task in the current
/// phase is already genuinely met, the target advances immediately server-
/// side instead of waiting for Monday's sweep — the page's own
/// `StreamBuilder`s simply pick up the new current phase once that write
/// lands. A no-op call (no writes at all) whenever the phase isn't fully met.
class GoalWeeklyPhasePage extends StatefulWidget {
  final String guideId;
  final String targetId;

  const GoalWeeklyPhasePage({
    super.key,
    required this.guideId,
    required this.targetId,
  });

  @override
  State<GoalWeeklyPhasePage> createState() => _GoalWeeklyPhasePageState();
}

class _GoalWeeklyPhasePageState extends State<GoalWeeklyPhasePage> {
  String get guideId => widget.guideId;
  String get targetId => widget.targetId;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: a failure here must never block the page itself —
    // the phase still evaluates normally come Monday regardless.
    callCheckAndAdvanceIfAheadOfSchedule(guideId: guideId, targetId: targetId)
        .catchError((_) => false);
    // Master Task 2026-09-10, Part 6 — "seen" for a pending proposal is
    // opening THIS target's own page, not the "Guide Targets" hub tile as
    // a whole — a per-target sub-key so approving/opening one target never
    // marks a different target's own pending proposal seen.
    SeenMarkers.markSeenSub(guideId, 'goalProposals', targetId);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "This week's target",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            )),
          body: StreamBuilder<CompoundTarget?>(
            stream: compoundTargetStream(guideId, targetId),
            builder: (context, targetSnap) {
              final target = targetSnap.data;
              if (target == null) {
                return targetSnap.connectionState == ConnectionState.waiting
                    ? GuideWait(snapshot: targetSnap)
                    : const GuideNotAvailable('This target is no longer available.');
              }
              if (target.totalPhases == 0) {
                return const GuideNotAvailable('The phase plan is still being generated.');
              }

              return StreamBuilder<List<CompoundPhase>>(
                stream: compoundPhasesStream(guideId, targetId),
                builder: (context, phasesSnap) {
                  final phases = phasesSnap.data ?? const <CompoundPhase>[];
                  final currentPhase = phases.where(
                      (p) => p.phaseNumber == target.currentPhase);
                  if (currentPhase.isEmpty) {
                    return phasesSnap.hasData
                        ? const GuideNotAvailable('The plan for this phase is not available yet.')
                        : GuideWait(snapshot: phasesSnap);
                  }
                  return _body(context, target, currentPhase.first);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, CompoundTarget target, CompoundPhase phase) {
    final metric = target.metricInfo;
    final pending = target.pendingProposal;
    final isChanting = target.metric == kMetricChanting;
    final unit = metric?.unit ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (pending != null) _pendingProposalBanner(context, target, pending),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.g.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.g.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Phase ${phase.phaseNumber} of ${target.totalPhases}",
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (isChanting)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    "Value tasks count students who have COMMITTED to this "
                    "many rounds/day, not actual chanting this week.",
                    style: TextStyle(fontSize: 10.5, color: context.g.mutedText),
                  ),
                ),
              _taskChecklist(phase, target, unit),
              const SizedBox(height: 6),
              Text(
                "This is the ONLY phase you're being checked against right "
                "now. It advances automatically every Monday, only once "
                "EVERY task above is genuinely met — or immediately if you "
                "finish early.",
                style: TextStyle(fontSize: 11, color: context.g.mutedText),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompoundTaskEditorPage(
                            guideId: guideId,
                            targetId: targetId,
                            isHod: false,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text("Edit tasks"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompoundGoalRoadmapPage(
                            guideId: guideId,
                            targetId: targetId,
                            isHod: false,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text("Full roadmap"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _changeEndDate(context, target),
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(
                    target.endDate == null
                        ? "Set a new end date"
                        : "Change end date "
                            "(${DateFormat('dd MMM yyyy').format(target.endDate!)})",
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Renders `phase.tasks` as a checklist, one line per task, with real live
  /// progress (task-list phase model task, Part 6 item 1) — e.g. "Bring
  /// roster from 6 to 8 students" or, for a value task, the real students
  /// it applies to by name (real-names task) — each with its own progress
  /// bar computed against real current data.
  ///
  /// Names are resolved ONCE for every value task in THIS phase (nested
  /// inside the existing progress `FutureBuilder`, not a second separate
  /// one) — `GoalWeeklyPhasePage` only ever shows one phase at a time by
  /// construction, so this never needs to span more than that.
  Widget _taskChecklist(CompoundPhase phase, CompoundTarget target, String unit) {
    if (phase.tasks.isEmpty) {
      return Text("No tasks in this phase.",
          style: TextStyle(fontSize: 13, color: context.g.mutedText));
    }
    return FutureBuilder<List<TaskProgress>>(
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
                  _taskLine(
                    phase.tasks[i],
                    unit,
                    progress != null && i < progress.length ? progress[i] : null,
                    uidToName,
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _taskLine(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                complete ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: complete ? context.g.success : context.g.mutedText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.describe(unit, uidToName),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                progress == null ? '—' : '${progress.actual}/${progress.target}',
                style: TextStyle(fontSize: 12, color: context.g.mutedText),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction ?? 0,
                minHeight: 5,
                backgroundColor: context.g.chipBackground,
                valueColor: AlwaysStoppedAnimation<Color>(
                  complete ? context.g.success : context.g.success,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Part 4 — guide-only. Writes the new `endDate` (a direct edit), then
  /// IMMEDIATELY regenerates the remaining phases against it — the guide
  /// sees a blocking "regenerating" dialog throughout rather than a silent
  /// replacement, per the explicit requirement that this must not look like
  /// nothing happened.
  Future<void> _changeEndDate(BuildContext context, CompoundTarget target) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: target.endDate ?? now.add(const Duration(days: 90)),
      firstDate: now.add(const Duration(days: 7)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const GuideDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20, height: 20,
              child: const GuideBusyDot(),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text("Regenerating your roadmap for the new date…"),
            ),
          ],
        ),
      ),
    );

    try {
      await updateTargetEndDate(
        guideId: guideId,
        targetId: targetId,
        endDate: picked,
      );
      await callRegenerateCompoundPlan(
        guideId: guideId,
        targetId: targetId,
        note: "The end date changed to "
            "${DateFormat('dd MMM yyyy').format(picked)} — please "
            "re-pace the remaining phases for the new timeframe.",
      );
      if (!context.mounted) return;
      Navigator.pop(context); // close the loading dialog
      showSnackbar(
        context,
        "End date changed — your roadmap was regenerated for the new "
        "timeframe.",
        Colors.green,
        Icons.check_circle,
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showSnackbar(context, "Could not update the end date — please try again",
          context.g.danger, Icons.error);
    }
  }

  Widget _pendingProposalBanner(
      BuildContext context, CompoundTarget target, CompoundProposal pending) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.g.brass.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.g.brass.withValues(alpha: .14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18, color: context.g.brass),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Suggested by your HOD — not yet applied",
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: context.g.brass),
                ),
              ),
            ],
          ),
          if (pending.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(pending.note, style: TextStyle(fontSize: 12.5, color: context.g.brass)),
          ],
          const SizedBox(height: 8),
          Text(
            "Proposed phases: ${List.generate(
              pending.proposedPhases.length,
              (i) => 'P${i + 1} (${pending.tasksFor(i).length} task'
                  '${pending.tasksFor(i).length == 1 ? '' : 's'})',
            ).join('  ·  ')}",
            style: TextStyle(fontSize: 11.5, color: context.g.brass),
          ),
          const SizedBox(height: 4),
          Text(
            "Open \"Full roadmap\" after approving to see the full task "
            "list for each phase.",
            style: TextStyle(fontSize: 10.5, color: context.g.brass),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _reject(context, target),
                  child: const Text("Reject"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _approve(context, target),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: context.g.brass,
                      foregroundColor: context.g.onPrimary),
                  child: const Text("Approve"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context, CompoundTarget target) async {
    try {
      await approveProposal(guideId: guideId, targetId: targetId);
      if (context.mounted) {
        showSnackbar(context, "Proposal applied", Colors.green, Icons.check_circle);
      }
    } catch (_) {
      if (context.mounted) {
        showSnackbar(context, "Could not apply the proposal", Colors.red, Icons.error);
      }
    }
  }

  Future<void> _reject(BuildContext context, CompoundTarget target) async {
    try {
      await rejectProposal(guideId: guideId, targetId: targetId);
      if (context.mounted) {
        showSnackbar(context, "Proposal rejected", Colors.grey, Icons.info);
      }
    } catch (_) {
      if (context.mounted) {
        showSnackbar(context, "Could not reject the proposal", Colors.red, Icons.error);
      }
    }
  }

}
