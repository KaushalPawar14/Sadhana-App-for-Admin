import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/AdminProfile.dart';
import 'CompoundGoalRoadmapPage.dart';
import 'CompoundTaskEditorPage.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';

/// HOD-facing: browse any guide's compound targets and either open the
/// note-driven AI roadmap/suggestion view or manually edit the current
/// phase's tasks — both equally available (restored manual-editing task).
///
/// ---------------------------------------------------------------------------
/// Read access — reuses the EXISTING HOD gate, does not invent a new one
/// ---------------------------------------------------------------------------
/// Hierarchy: the HOD check is the signed-in admin's ROLE
/// (`AdminProfileProvider.viewerIsHod`), never a special id — several HODs may
/// exist. This screen is itself only ever reachable by a HOD (the caller gates
/// navigation to it) — once here, every admin in the profile's admin list is
/// selectable, matching the same "HOD sees everyone" rule. Enablers and Guides
/// manage only their own targets (`GoalHomePage`).
///
/// ---------------------------------------------------------------------------
/// This screen makes NO writes of its own
/// ---------------------------------------------------------------------------
/// "View roadmap / suggest a change" pushes [CompoundGoalRoadmapPage]
/// (`isHod: true`), which has its own note-driven suggestion box calling
/// `callSuggestCompoundPlan`. "Edit tasks manually" pushes
/// [CompoundTaskEditorPage] (`isHod: true`), whose Save calls
/// `proposeManualPhaseEdit` — a hand-typed edit including a real student
/// picker (a value task's content is a specific student-uid group, so a
/// plain two-number dialog can't represent it; the editor page IS the
/// student-uid-aware form). Both write ONLY `pendingProposal`, never
/// `phases/**` directly. Nothing in this file imports or calls
/// [approveProposal] or [rejectProposal] — those are guide-only, on
/// `GoalWeeklyPhasePage.dart`.
class CompoundGoalHodReview extends StatefulWidget {
  final String hodUid;

  const CompoundGoalHodReview({super.key, required this.hodUid});

  @override
  State<CompoundGoalHodReview> createState() => _CompoundGoalHodReviewState();
}

class _CompoundGoalHodReviewState extends State<CompoundGoalHodReview> {
  String? _selectedGuide;

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
              "Guide compound targets",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Builder(
                  builder: (context) {
                    // Server-filtered admin list (a HOD sees every admin).
                    final List<AdminSummary> admins =
                        AdminProfileProvider.require().admins;
                    return DropdownButtonFormField<String>(
                      initialValue: _selectedGuide,
                      decoration: const InputDecoration(
                        labelText: "Guide",
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: admins
                          .map((a) => DropdownMenuItem(
                              value: a.id, child: Text(a.displayName)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedGuide = v),
                    );
                  },
                ),
              ),
              Expanded(
                child: _selectedGuide == null
                    ? const Center(child: Text("Choose a guide to review"))
                    : _targetsList(_selectedGuide!),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _targetsList(String guideId) {
    return StreamBuilder<List<CompoundTarget>>(
      stream: compoundTargetsStream(guideId),
      builder: (context, snap) {
        final targets =
            (snap.data ?? const <CompoundTarget>[]).where((t) => t.isActive).toList();
        if (targets.isEmpty) {
          return const Center(child: Text("No active compound targets"));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: targets.length,
          itemBuilder: (context, i) => _targetCard(guideId, targets[i]),
        );
      },
    );
  }

  Widget _targetCard(String guideId, CompoundTarget target) {
    final metric = target.metricInfo;
    final pending = target.pendingProposal;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.g.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${metric?.label ?? target.metric} — "
            "${target.studentCountGoal} students at ${target.perStudentValueGoal} "
            "${metric?.unit ?? ''}",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            target.totalPhases == 0
                ? "Plan not generated yet"
                : "Phase ${target.currentPhase} of ${target.totalPhases}",
            style: TextStyle(fontSize: 12, color: context.g.mutedText),
          ),
          if (pending != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.g.warning.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "A proposal is already pending — awaiting the guide's decision.",
                style: TextStyle(fontSize: 11.5, color: context.g.warning),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: target.totalPhases == 0
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompoundGoalRoadmapPage(
                            guideId: guideId,
                            targetId: target.targetId,
                            isHod: true,
                            hodUid: widget.hodUid,
                          ),
                        ),
                      ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text("View roadmap / suggest a change"),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: target.totalPhases == 0 || pending != null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompoundTaskEditorPage(
                            guideId: guideId,
                            targetId: target.targetId,
                            isHod: true,
                            hodUid: widget.hodUid,
                          ),
                        ),
                      ),
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text("Edit tasks manually"),
            ),
          ),
        ],
      ),
    );
  }

}
