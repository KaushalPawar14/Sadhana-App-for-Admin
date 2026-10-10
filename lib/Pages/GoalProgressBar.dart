import 'package:flutter/material.dart';

import '../utils/GoalCompoundQueries.dart';
import 'GoalHomePage.dart';
import '../theme/GuideTheme.dart';

/// The always-visible goal strip on `Home/Dashboard.dart` — rewritten for the
/// compound-target system when the old aggregate-SUM goal system was
/// retired entirely.
///
/// ⚠️ **This used to read `guideTargets/{guideId}`'s own top-level document**
/// (association/expeditions/old-style chanting/books, one shared phase
/// timeline per guide) via `GoalQueries.dart` — that document schema, and
/// every real document of it, was deleted (see the task that did this).
/// `GoalQueries.dart` itself was deleted alongside it; nothing in this file
/// imports it any more. This widget now streams
/// `guideTargets/{guideId}/targets/**` (the compound system) instead.
///
/// Deliberately a SLIM SUMMARY, not a full per-metric live bar like the old
/// one: a guide may have multiple independent compound targets (a chanting
/// track, a books track) each with its own phase/live-vs-weekly figures —
/// showing all of that inline here would either pick one arbitrarily or
/// crowd the dashboard. `GoalWeeklyPhasePage.dart`/`CompoundGoalProgressPage.dart`
/// already show the real per-target detail; this strip's only job is "you
/// have active targets, tap to see them", exactly like the old bar's own
/// "renders nothing when irrelevant" property.
class GoalProgressBar extends StatelessWidget {
  final String guideId;

  const GoalProgressBar({super.key, required this.guideId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CompoundTarget>>(
      stream: compoundTargetsStream(guideId),
      builder: (context, snap) {
        final targets =
            (snap.data ?? const <CompoundTarget>[]).where((t) => t.isActive).toList();
        if (targets.isEmpty) return const SizedBox.shrink();

        final pendingCount = targets.where((t) => t.pendingProposal != null).length;

        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => GoalHomePage(guideId: guideId)),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.g.surface,
              border: Border(bottom: BorderSide(color: context.g.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.flag, size: 15, color: context.g.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${targets.length} active target${targets.length == 1 ? '' : 's'}"
                    "${pendingCount > 0 ? ' · $pendingCount proposal${pendingCount == 1 ? '' : 's'} pending' : ''}",
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: context.g.mutedText),
              ],
            ),
          ),
        );
      },
    );
  }
}
