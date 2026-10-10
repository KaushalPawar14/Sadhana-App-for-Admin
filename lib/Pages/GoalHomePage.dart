import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/AdminProfile.dart';
import '../utils/Snackbar.dart';
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
class GoalHomePage extends StatelessWidget {
  final String guideId;

  const GoalHomePage({super.key, required this.guideId});

  // Role check (several HODs may exist; no id is special).
  bool get _isHod => AdminProfileProvider.viewerIsHod;

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: colorProvider.color,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Your targets",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            actions: [
              if (_isHod)
                IconButton(
                  tooltip: "Review guides' targets",
                  icon: Icon(Icons.rate_review_outlined, color: colorProvider.secondColor),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompoundGoalHodReview(hodUid: guideId),
                    ),
                  ),
                ),
            ],
          ),
          body: StreamBuilder<List<CompoundTarget>>(
            stream: compoundTargetsStream(guideId),
            builder: (context, snap) {
              final targets = (snap.data ?? const <CompoundTarget>[])
                  .where((t) => t.isActive)
                  .toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (targets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        "No active targets yet. Create a compound target — "
                        "\"N students each at a value\" — and get a real, "
                        "AI-generated phase plan from your group's actual "
                        "current numbers.",
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: colorProvider.secondColor.withOpacity(.75),
                        ),
                      ),
                    )
                  else
                    ...targets.map((t) => _CompoundTargetCard(
                          guideId: guideId,
                          target: t,
                        )),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompoundGoalSetupPage(guideId: guideId),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text("New target"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00695C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
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

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final metric = target.metricInfo;
    final needsGeneration = target.totalPhases == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${metric?.label ?? target.metric} — ${target.studentCountGoal} "
            "students at ${target.perStudentValueGoal} ${metric?.unit ?? ''}",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            needsGeneration
                ? "No plan yet — generation didn't complete"
                : "Phase ${target.currentPhase} of ${target.totalPhases}"
                    "${target.pendingProposal != null ? " · proposal pending" : ""}",
            style: TextStyle(
              fontSize: 12,
              color: needsGeneration ? Colors.red.shade700 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          if (needsGeneration)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _retrying ? null : _retry,
                icon: _retrying
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(_retrying ? "Generating…" : "Retry plan generation"),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GoalWeeklyPhasePage(
                          guideId: widget.guideId,
                          targetId: target.targetId,
                        ),
                      ),
                    ),
                    child: const Text("This week"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CompoundGoalProgressPage(
                          guideId: widget.guideId,
                          targetId: target.targetId,
                        ),
                      ),
                    ),
                    child: const Text("Progress"),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
