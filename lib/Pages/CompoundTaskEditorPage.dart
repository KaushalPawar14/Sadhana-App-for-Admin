import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/Snackbar.dart';

/// Manual task editor for the CURRENT phase only (restored manual-editing
/// task) — sits ALONGSIDE the AI note-driven regenerate/suggest flow in
/// `CompoundGoalRoadmapPage.dart`, never replacing it. Both are equally
/// available at all times.
///
/// ---------------------------------------------------------------------------
/// CURRENT phase only, by design (Part 2's explicit restriction)
/// ---------------------------------------------------------------------------
/// A future not-yet-active phase gets re-bucketed from real, current data
/// the moment it actually activates (`advanceCompoundTarget` in
/// `functions/goals.js` regenerates the newly-unlocked phase fresh) — hand-
/// typing `studentUids` for a phase that hasn't started yet would already be
/// stale by the time it mattered. So this screen only ever loads and edits
/// whichever phase equals the target's own `currentPhase` — there is no way
/// to navigate it to any other phase.
///
/// ---------------------------------------------------------------------------
/// isHod — same permission split every other write in this feature uses
/// ---------------------------------------------------------------------------
///   - isHod: false (guide, opened from `GoalWeeklyPhasePage.dart`) —
///     [directlyEditPhaseTasks] writes straight to the live phase, no
///     approval, matching the guide's existing direct-edit precedent.
///   - isHod: true (HOD, opened from `CompoundGoalHodReview.dart`) —
///     [proposeManualPhaseEdit] writes into `pendingProposal` instead — the
///     guide sees it as a proposal and approves/rejects exactly like an AI
///     suggestion.
///
/// ---------------------------------------------------------------------------
/// Ladder and already-at-goal enforcement
/// ---------------------------------------------------------------------------
/// Every value task's from/to level dropdown is built ONLY from
/// [effectiveLadder] — there is no text field a level could be typed into
/// off-ladder. The student picker is built ONLY from students whose real
/// current value is BELOW the target's own `perStudentValueGoal` — a
/// student already at the final goal can never appear as a selectable
/// option, "by construction" rather than a runtime check.
class CompoundTaskEditorPage extends StatefulWidget {
  final String guideId;
  final String targetId;
  final bool isHod;
  final String? hodUid;

  const CompoundTaskEditorPage({
    super.key,
    required this.guideId,
    required this.targetId,
    required this.isHod,
    this.hodUid,
  }) : assert(!isHod || hodUid != null,
            'hodUid is required when isHod is true');

  @override
  State<CompoundTaskEditorPage> createState() => _CompoundTaskEditorPageState();
}

/// A value task mid-edit — not yet validated, not yet the real [CompoundTask]
/// shape (which requires non-null levels). Kept separate so an incomplete
/// row (e.g. "from" picked, "to" not yet) can exist on screen without being
/// a lie about what's actually saved.
class _EditableValueTask {
  int? fromLevel;
  int? toLevel;
  Set<String> studentUids;

  _EditableValueTask({this.fromLevel, this.toLevel, Set<String>? studentUids})
      : studentUids = studentUids ?? <String>{};
}

class _CompoundTaskEditorPageState extends State<CompoundTaskEditorPage> {
  bool _loading = true;
  String? _error;
  bool _saving = false;

  CompoundTarget? _target;
  CompoundPhase? _phase;
  List<StudentValue> _roster = const [];

  final _rosterFromController = TextEditingController();
  final _rosterToController = TextEditingController();
  final _noteController = TextEditingController();

  final List<_EditableValueTask> _valueTasks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rosterFromController.dispose();
    _rosterToController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Students eligible for a value task — everyone on the real roster
  /// EXCEPT those already at the target's own final `perStudentValueGoal`
  /// (Part 2 item 2's system rule, enforced here by construction: this list
  /// is the ONLY source the student picker ever reads from).
  List<StudentValue> get _eligibleRoster {
    final goal = _target?.perStudentValueGoal ?? 0;
    return _roster.where((s) => s.value < goal).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  String get _unit => _target?.metricInfo?.unit ?? '';

  Future<void> _load() async {
    try {
      final targetSnap =
          await compoundTargetRef(widget.guideId, widget.targetId).get();
      if (!targetSnap.exists) {
        setState(() {
          _error = "This target no longer exists.";
          _loading = false;
        });
        return;
      }
      final target =
          CompoundTarget.from(widget.guideId, widget.targetId, targetSnap.data());
      if (target.totalPhases == 0 || target.currentPhase < 1) {
        setState(() {
          _error = "The phase plan is still being generated — nothing to edit yet.";
          _loading = false;
        });
        return;
      }

      final phaseSnap = await compoundPhasesRef(widget.guideId, widget.targetId)
          .doc('${target.currentPhase}')
          .get();
      if (!phaseSnap.exists) {
        setState(() {
          _error = "Could not find the current phase.";
          _loading = false;
        });
        return;
      }
      final phase = CompoundPhase.from(phaseSnap.id, phaseSnap.data() ?? {});
      final roster = await liveRosterWithValues(
        guideId: widget.guideId,
        metric: target.metric,
      );

      CompoundTask? rosterTask;
      for (final t in phase.tasks) {
        if (t.isRoster) {
          rosterTask = t;
          break;
        }
      }

      _rosterFromController.text = rosterTask?.fromCount?.toString() ?? '';
      _rosterToController.text = rosterTask?.toCount?.toString() ?? '';

      _valueTasks.clear();
      for (final t in phase.tasks) {
        if (!t.isRoster) {
          _valueTasks.add(_EditableValueTask(
            fromLevel: t.fromLevel,
            toLevel: t.toLevel,
            studentUids: Set<String>.from(t.studentUids),
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _target = target;
        _phase = phase;
        _roster = roster;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Could not load this phase — please try again.";
        _loading = false;
      });
    }
  }

  void _showMessage(String message) {
    showSnackbar(context, message, Colors.orange, Icons.info);
  }

  /// Pre-fills the new selection with whoever is REALLY at [fromLevel]
  /// today (Part 2 item 2's "helpful starting suggestion") — replaces
  /// whatever was selected before, since a from-level change means the
  /// previous suggestion no longer describes the same group. The guide/HOD
  /// can still freely adjust it afterward via [_pickStudents].
  void _onFromLevelChanged(_EditableValueTask task, int? newFromLevel) {
    final ladder = effectiveLadder(_target!.perStudentValueGoal);
    setState(() {
      task.fromLevel = newFromLevel;
      if (newFromLevel != null) {
        task.studentUids = _eligibleRoster
            .where((s) => tierFor(s.value, ladder) == newFromLevel)
            .map((s) => s.uid)
            .toSet();
      }
    });
  }

  Future<void> _pickStudents(_EditableValueTask task) async {
    final selected = Set<String>.from(task.studentUids);
    final eligible = _eligibleRoster;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Select students"),
          content: SizedBox(
            width: double.maxFinite,
            child: eligible.isEmpty
                ? const Text(
                    "No eligible students — everyone on this roster is "
                    "already at the final goal, or the roster is empty.")
                : ListView(
                    shrinkWrap: true,
                    children: eligible.map((s) {
                      return CheckboxListTile(
                        dense: true,
                        value: selected.contains(s.uid),
                        title: Text(s.name),
                        subtitle: Text('${s.value} $_unit'),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selected.add(s.uid);
                          } else {
                            selected.remove(s.uid);
                          }
                        }),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => task.studentUids = selected);
                Navigator.pop(dialogContext);
              },
              child: const Text("Done"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final target = _target!;

    CompoundTask? rosterTask;
    final fromText = _rosterFromController.text.trim();
    final toText = _rosterToController.text.trim();
    if (fromText.isNotEmpty || toText.isNotEmpty) {
      final from = int.tryParse(fromText);
      final to = int.tryParse(toText);
      if (from == null || to == null || from < 0 || to < from) {
        _showMessage(
            "Roster task: enter whole numbers, with 'to' at least 'from'.");
        return;
      }
      rosterTask = CompoundTask(type: kTaskTypeRoster, fromCount: from, toCount: to);
    }

    final ladderSet = effectiveLadder(target.perStudentValueGoal).toSet();
    final valueTasks = <CompoundTask>[];
    for (var i = 0; i < _valueTasks.length; i++) {
      final t = _valueTasks[i];
      if (t.fromLevel == null || t.toLevel == null) {
        _showMessage("Value task ${i + 1}: choose both a from and to level.");
        return;
      }
      // Defensive — the dropdowns only ever offer ladder values (plus 0 for
      // "not started" on From level only), so this should never actually
      // trip, but it is the block-not-warn guarantee Part 2 item 2 asks for.
      final validFromLevel = t.fromLevel == 0 || ladderSet.contains(t.fromLevel);
      if (!validFromLevel || !ladderSet.contains(t.toLevel)) {
        _showMessage("Value task ${i + 1}: level must be one of "
            "${ladderSet.toList().join(', ')} (or 'Not started' for from).");
        return;
      }
      if (t.toLevel! <= t.fromLevel!) {
        _showMessage(
            "Value task ${i + 1}: the 'to' level must be higher than 'from'.");
        return;
      }
      if (t.studentUids.isEmpty) {
        _showMessage("Value task ${i + 1}: select at least one student.");
        return;
      }
      valueTasks.add(CompoundTask(
        type: kTaskTypeValue,
        fromLevel: t.fromLevel,
        toLevel: t.toLevel,
        studentUids: t.studentUids.toList(),
      ));
    }

    final tasks = [if (rosterTask != null) rosterTask, ...valueTasks];
    if (tasks.isEmpty) {
      _showMessage("Add at least one task before saving.");
      return;
    }

    if (widget.isHod && _noteController.text.trim().isEmpty) {
      _showMessage("Add a short note explaining the change.");
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.isHod) {
        await proposeManualPhaseEdit(
          guideId: widget.guideId,
          targetId: widget.targetId,
          hodUid: widget.hodUid!,
          currentPhaseNumber: target.currentPhase,
          totalPhases: target.totalPhases,
          editedTasks: tasks,
          note: _noteController.text.trim(),
        );
        if (!mounted) return;
        Navigator.pop(context);
        showSnackbar(context, "Proposal sent to the guide", Colors.green,
            Icons.check_circle);
      } else {
        await directlyEditPhaseTasks(
          guideId: widget.guideId,
          targetId: widget.targetId,
          phaseNumber: target.currentPhase,
          tasks: tasks,
        );
        if (!mounted) return;
        Navigator.pop(context);
        showSnackbar(context, "Phase updated", Colors.green, Icons.check_circle);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnackbar(
          context, "Could not save — please try again", Colors.red, Icons.error);
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
              "Edit current phase's tasks",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : _body(),
        );
      },
    );
  }

  Widget _body() {
    final target = _target!;
    final phase = _phase!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(
          "${target.metricInfo?.label ?? target.metric} — "
          "Phase ${phase.phaseNumber} of ${target.totalPhases}",
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          "Editing the CURRENT phase only — future phases are re-planned "
          "fresh from real data once they activate, so they aren't editable "
          "here.",
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        _rosterSection(),
        const SizedBox(height: 16),
        _valueTasksSection(),
        const SizedBox(height: 20),
        if (widget.isHod) ...[
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: "Note to the guide",
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "This does NOT change the guide's live plan — it shows as a "
            "suggestion until they approve or reject it.",
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.isHod ? "Send proposal" : "Save"),
          ),
        ),
      ],
    );
  }

  Widget _rosterSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Roster task (optional)",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            "Plain numbers — not ladder-constrained, matching the AI's own "
            "free-form roster reasoning. Leave both blank for no roster task.",
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rosterFromController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: "From count", isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _rosterToController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: "To count", isDense: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _valueTasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Value tasks",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        for (var i = 0; i < _valueTasks.length; i++) _valueTaskRow(i),
        OutlinedButton.icon(
          onPressed: () => setState(() => _valueTasks.add(_EditableValueTask())),
          icon: const Icon(Icons.add, size: 16),
          label: const Text("Add value task"),
        ),
      ],
    );
  }

  Widget _valueTaskRow(int index) {
    final task = _valueTasks[index];
    final ladder = effectiveLadder(_target!.perStudentValueGoal);
    // "From level" also offers the literal 0 — the one non-ladder sentinel
    // for students with no commitment/progress logged yet ("not started").
    // Investigation task: without this, a guide could never manually create
    // a starting task for real students at value 0 — the exact same gap
    // that made generation produce roster-only roadmaps. "To level" stays
    // ladder-only; a task must always land ON a real rung.
    final fromLevelOptions = [0, ...ladder];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: task.fromLevel,
                  decoration:
                      const InputDecoration(labelText: "From level", isDense: true),
                  items: fromLevelOptions
                      .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v == 0 ? 'Not started' : '$v $_unit')))
                      .toList(),
                  onChanged: (v) => _onFromLevelChanged(task, v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: task.toLevel,
                  decoration:
                      const InputDecoration(labelText: "To level", isDense: true),
                  items: ladder
                      .map((v) => DropdownMenuItem(value: v, child: Text('$v $_unit')))
                      .toList(),
                  onChanged: (v) => setState(() => task.toLevel = v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => setState(() => _valueTasks.removeAt(index)),
              ),
            ],
          ),
          Text(
            "'To' must be higher than 'From' — both from this target's "
            "fixed ladder.",
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: task.fromLevel == null ? null : () => _pickStudents(task),
            icon: const Icon(Icons.people_outline, size: 16),
            label: Text('${task.studentUids.length} student(s) selected'),
          ),
        ],
      ),
    );
  }
}
