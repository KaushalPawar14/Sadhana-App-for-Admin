import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/GoalMetrics.dart';
import '../utils/Snackbar.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideWait.dart';

/// Compound target setup — "N students at value V" (chanting or books).
///
/// ⚠️ **The OLD checkbox-based, multi-metric (association/expeditions/
/// chanting/books) aggregate-target setup flow that used to live in this
/// file — `GoalSetupPage`/`GoalReviewPage`, backed by `GoalQueries.dart` and
/// the client-side `PhasePlanService` stub — has been REMOVED ENTIRELY, not
/// hidden. Association and expeditions are no longer offered as goal
/// metrics anywhere, for anyone. Their real Firestore data (every
/// `guideTargets/{guideId}` top-level document and its own `phases`
/// subcollection) was deleted, and `GoalQueries.dart`/`PhasePlanService.dart`
/// were deleted alongside the UI that was their only caller. This file now
/// contains ONLY the compound-target flow — see `GoalCompoundQueries.dart`'s
/// own header for why the old aggregate-SUM schema could never represent a
/// compound "N students at value V" target in the first place.
///
/// `Home/Dashboard.dart`'s "Semester goal" button now opens `GoalHomePage`
/// (see `Pages/GoalHomePage.dart`), which is the one reachable entry point
/// for both viewing existing compound targets and reaching this setup
/// screen to create a new one — this screen is no longer pushed directly
/// from the dashboard.
class CompoundGoalSetupPage extends StatefulWidget {
  final String guideId;

  /// The metric to start on (the one the guide has not set yet); chanting when null.
  final String? initialMetric;

  const CompoundGoalSetupPage({super.key, required this.guideId, this.initialMetric});

  @override
  State<CompoundGoalSetupPage> createState() => _CompoundGoalSetupPageState();
}

class _CompoundGoalSetupPageState extends State<CompoundGoalSetupPage> {
  late String _metric = widget.initialMetric ?? kMetricChanting;
  final _studentCountController = TextEditingController();
  final _perStudentValueController = TextEditingController();
  DateTime? _endDate;
  bool _submitting = false;

  @override
  void dispose() {
    _studentCountController.dispose();
    _perStudentValueController.dispose();
    super.dispose();
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? now.add(const Duration(days: 90)),
      firstDate: now.add(const Duration(days: 14)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  String? _validate() {
    if (_endDate == null) return "Choose an end date";
    final sc = int.tryParse(_studentCountController.text.trim());
    if (sc == null || sc <= 0) {
      return _metric == kMetricFolk ? "Enter how many of your boys should live in FOLK, as a whole number" : "Enter how many students, as a whole number";
    }
    // a FOLK-residents target has no per-student value: the boy either lives in FOLK or does not
    if (_metric == kMetricFolk) return null;
    final pv = int.tryParse(_perStudentValueController.text.trim());
    if (pv == null || pv <= 0) {
      return _metric == kMetricChanting
          ? "Enter a rounds/day target, as a whole number"
          : "Enter a books target, as a whole number";
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      showSnackbar(context, error, Colors.orange, Icons.info);
      return;
    }

    setState(() => _submitting = true);
    try {
      final targetId = await createCompoundTargetShell(
        guideId: widget.guideId,
        metric: _metric,
        studentCountGoal: int.parse(_studentCountController.text.trim()),
        perStudentValueGoal: _metric == kMetricFolk ? 1 : int.parse(_perStudentValueController.text.trim()),
        endDate: _endDate!,
      );

      final phaseCount = await callGenerateCompoundPlan(
        guideId: widget.guideId,
        targetId: targetId,
      );

      if (!mounted) return;
      showSnackbar(
        context,
        "Plan generated — $phaseCount phase${phaseCount == 1 ? '' : 's'}",
        Colors.green,
        Icons.check_circle,
      );
      Navigator.pop(context);
    } on CompoundTargetLimitException catch (e) {
      // One active target per metric (A1). The guide is told exactly what to
      // do about it, not that something went wrong.
      if (!mounted) return;
      showSnackbar(context, e.message, Colors.orange, Icons.info);
    } catch (e) {
      if (!mounted) return;
      showSnackbar(
        context,
        "Could not generate a plan — please try again",
        Colors.red,
        Icons.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        final metricInfo = goalMetricById(_metric);
        return GuideScaffold(
          appBar: GuideAppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "New compound target",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            )),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Text(
                "A compound target is \"N students each at a value\" — e.g. "
                "20 students at 16 rounds/day. The phase plan is generated "
                "for real by AI from your group's actual current numbers, "
                "not a fixed formula.",
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: colorProvider.secondColor.withValues(alpha: .75),
                ),
              ),
              const SizedBox(height: 16),
              GuideCard(
                padding: const EdgeInsets.all(14),
                // The radio rows paint their ink on the nearest Material.
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Metric",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    for (final id in compoundMetricsFor(AdminProfileProvider.require()))
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: id,
                        groupValue: _metric,
                        title: Text(goalMetricById(id)?.label ?? id),
                        onChanged: (v) => setState(() => _metric = v ?? _metric),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _studentCountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _metric == kMetricFolk ? "How many of your boys live in FOLK" : "How many students",
                        isDense: true,
                      ),
                    ),
                    if (_metric != kMetricFolk) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _perStudentValueController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "At what value, each",
                          suffixText: metricInfo?.unit,
                          isDense: true,
                        ),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "Counted automatically from each boy's residence; the weekly plan steps up to your number by the end date.",
                          style: TextStyle(fontSize: 12.5, height: 1.4, color: colorProvider.secondColor.withValues(alpha: .75)),
                        ),
                      ),
                  ],
                ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: context.g.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.g.border),
                ),
                // Same fix as `AssistantScreen.dart`'s starter cards: a
                // `ListTile` needs an ANCESTOR `Material` to paint its ink
                // splash. This `Container` only has a `decoration`, not a
                // `Material` — without this wrapper, Flutter warns and the
                // splash never renders. `color: Colors.transparent` so the
                // Container's own white/bordered look is untouched.
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event, color: context.g.brass),
                    title: const Text("Goal ends", style: TextStyle(fontSize: 14.5)),
                    subtitle: Text(
                      _endDate == null
                          ? "Tap to choose"
                          : DateFormat('dd MMM yyyy').format(_endDate!),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _endDate == null ? context.g.mutedText : context.g.text,
                      ),
                    ),
                    trailing: const Icon(Icons.edit, size: 18),
                    onTap: _pickEndDate,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: const GuideBusyDot(),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(_submitting
                      ? "Generating with AI…"
                      : "Generate phase plan"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.g.brass,
                    foregroundColor: context.g.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
