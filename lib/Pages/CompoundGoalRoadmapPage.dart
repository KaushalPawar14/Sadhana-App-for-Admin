import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/Snackbar.dart';

/// Full roadmap view — Part 2 (all phases, read-only) + Part 3 (free-text
/// suggestion box), reachable from BOTH the guide's own weekly page and the
/// HOD's review screen (Part 2 item 2).
///
/// ---------------------------------------------------------------------------
/// Deliberately a distinct route, not an expandable section
/// ---------------------------------------------------------------------------
/// `GoalWeeklyPhasePage.dart` must stay current-phase-only by construction
/// (its own header's core invariant) — inlining the full sequence there,
/// even collapsed by default, would put the temptation to widen that
/// screen's own scope one edit away. A separate page keeps "see only what
/// you're checked against right now" and "see the whole plan" as two
/// genuinely different, deliberately chosen views.
///
/// ---------------------------------------------------------------------------
/// [isHod] is the ONLY access-control switch in this file — same trust
/// model every other screen in this app already uses (which screen/flag
/// you're on IS the gate, no server-side role check exists anywhere in this
/// project). It decides where a submitted suggestion goes:
///   - `isHod: false` (opened from `GoalWeeklyPhasePage`) — the suggestion
///     calls [callRegenerateCompoundPlan], which writes DIRECTLY to the
///     live phases. No approval step, matching the guide's existing
///     direct-edit precedent.
///   - `isHod: true` (opened from `CompoundGoalHodReview`) — the suggestion
///     calls [callSuggestCompoundPlan], which writes into
///     `pendingProposal` instead. The guide sees it as a proposal, exactly
///     like the hand-typed one `CompoundGoalHodReview`'s own dialog
///     already builds.
/// Both paths are entirely OPTIONAL — leaving the note blank and just
/// viewing the roadmap needs no submission at all.
class CompoundGoalRoadmapPage extends StatefulWidget {
  final String guideId;
  final String targetId;
  final bool isHod;
  final String? hodUid;

  const CompoundGoalRoadmapPage({
    super.key,
    required this.guideId,
    required this.targetId,
    required this.isHod,
    this.hodUid,
  }) : assert(!isHod || hodUid != null,
            'hodUid is required when isHod is true');

  @override
  State<CompoundGoalRoadmapPage> createState() =>
      _CompoundGoalRoadmapPageState();
}

class _CompoundGoalRoadmapPageState extends State<CompoundGoalRoadmapPage> {
  /// The caller's `isHod` flag, additionally confirmed against the signed-in
  /// admin's ROLE (hierarchy: an Enabler or Guide only ever manages their own
  /// targets; no id is special).
  bool get _isHod => widget.isHod && AdminProfileProvider.viewerIsHod;

  final _noteController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitSuggestion() async {
    setState(() => _submitting = true);
    final note = _noteController.text.trim();
    try {
      if (_isHod) {
        await callSuggestCompoundPlan(
          guideId: widget.guideId,
          targetId: widget.targetId,
          hodUid: widget.hodUid!,
          note: note,
        );
        if (!mounted) return;
        showSnackbar(context, "Suggestion sent to the guide", Colors.green,
            Icons.check_circle);
      } else {
        await callRegenerateCompoundPlan(
          guideId: widget.guideId,
          targetId: widget.targetId,
          note: note,
        );
        if (!mounted) return;
        showSnackbar(context, "Roadmap updated", Colors.green,
            Icons.check_circle);
      }
      if (mounted) _noteController.clear();
    } catch (_) {
      if (mounted) {
        showSnackbar(context, "Could not regenerate the plan — please try again",
            Colors.red, Icons.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

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
              "Full roadmap",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: StreamBuilder<CompoundTarget?>(
            stream: compoundTargetStream(widget.guideId, widget.targetId),
            builder: (context, targetSnap) {
              final target = targetSnap.data;
              if (target == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<List<CompoundPhase>>(
                stream: compoundPhasesStream(widget.guideId, widget.targetId),
                builder: (context, phasesSnap) {
                  final phases = phasesSnap.data ?? const <CompoundPhase>[];
                  return _body(target, phases);
                },
              );
            },
          ),
        );
      },
    );
  }

  /// Real-names task — this page shows EVERY phase at once (unlike
  /// `GoalWeeklyPhasePage.dart`'s current-phase-only view), so names are
  /// resolved ONCE across every phase's tasks combined here, not per
  /// phase row — a student appearing in more than one phase (e.g. the
  /// same tier chained forward across phases) is only ever looked up once.
  Widget _body(CompoundTarget target, List<CompoundPhase> phases) {
    final metric = target.metricInfo;
    final allTasks = phases.expand((p) => p.tasks);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(
          "${metric?.label ?? target.metric} — ${target.studentCountGoal} "
          "students at ${target.perStudentValueGoal} ${metric?.unit ?? ''}",
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          "Read-only — the day-to-day weekly page still shows only your "
          "current phase. This is the whole sequence, for reference.",
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 14),
        if (phases.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              target.totalPhases == 0
                  ? "The plan hasn't been generated yet."
                  : "Loading phases…",
              style: TextStyle(color: Colors.grey.shade600),
            ),
          )
        else
          FutureBuilder<Map<String, String>>(
            future: resolveStudentNames(collectStudentUids(allTasks)),
            builder: (context, namesSnap) {
              final uidToName = namesSnap.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: phases
                    .map((p) => _phaseRow(p, target, metric?.unit ?? '', uidToName))
                    .toList(),
              );
            },
          ),
        const SizedBox(height: 20),
        _suggestionBox(),
      ],
    );
  }

  Widget _phaseRow(CompoundPhase phase, CompoundTarget target, String unit,
      Map<String, String>? uidToName) {
    final (statusLabel, statusColor) = _statusStyle(phase.status);
    final isCurrent = phase.phaseNumber == target.currentPhase;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.teal.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? Colors.teal.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.teal.shade700.withOpacity(.12),
                ),
                child: Text(
                  '${phase.phaseNumber}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: Colors.teal.shade700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  phase.tasks.isEmpty
                      ? "No tasks"
                      : phase.tasks.length == 1
                          ? "1 task"
                          : "${phase.tasks.length} tasks",
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ],
          ),
          if (phase.tasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final task in phase.tasks)
              Padding(
                padding: const EdgeInsets.only(left: 42, bottom: 4),
                child: Text(
                  "• ${task.describe(unit, uidToName)}",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
          ],
        ],
      ),
    );
  }

  (String, Color) _statusStyle(String status) {
    switch (status) {
      case kCompoundPhaseAchieved:
        return ('achieved', Colors.green.shade700);
      case kCompoundPhaseActive:
        return ('active', Colors.teal.shade700);
      case kCompoundPhaseFailed:
        return ('failed', Colors.red.shade700);
      default:
        return ('pending', Colors.grey.shade500);
    }
  }

  Widget _suggestionBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Suggest an improvement to this roadmap",
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            _isHod
                ? "Optional. Your note guides a fresh AI-generated plan, sent "
                    "to the guide as a suggestion — it will not change their "
                    "live plan until they approve it."
                : "Optional. Your note guides a fresh AI-generated plan for "
                    "the rest of your roadmap — applies immediately, no "
                    "approval needed. Already-achieved phases are never "
                    "rewritten.",
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: "e.g. \"Two of my strongest students just left "
                  "FOLK — please slow the roster growth down\"",
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitSuggestion,
              icon: _submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(_submitting
                  ? "Regenerating with AI…"
                  : _isHod
                      ? "Send suggestion"
                      : "Regenerate roadmap"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
