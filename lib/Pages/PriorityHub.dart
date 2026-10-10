import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/StudentScope.dart';
import '../utils/UnseenFeatureBadge.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import 'FlaggedMessages.dart';
import 'PriorityStudents.dart';

/// Priority Students hub — the two "who needs attention" screens, together.
///
/// Reached from the "Priority Students" tile on the Folk Analysis tab (which
/// occupies the slot the never-implemented "Best Performer" tile used to hold).
/// Both destinations are **existing screens opened completely unchanged**; this
/// page only gathers their entry points, the same way `AbcdeHubPage` gathers
/// the five ABCDE screens.
///
/// The two belong together: one lists students flagged by activity signals
/// (stale contact, missing reports, overdue meetings, a low LIT axis), the
/// other lists students flagged by something they wrote in the AI chat. Both
/// answer "who should I reach out to", from different evidence.
///
/// ⚠️ Rule 10 note: `PriorityStudentsPage` surfaces LIT axes as named flags and
/// `FlaggedMessagesPage` surfaces chat distress. Neither is touched here, and
/// this page deliberately shows **no** student data itself — it is navigation
/// only, so nothing on it needs scoping.
class PriorityHubPage extends StatelessWidget {
  const PriorityHubPage({super.key});

  /// Opens a destination with the fade this hub has always used.
  void _open(BuildContext context, Widget destination) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return GuideScaffold(
      body: Column(
        children: [
          const GuideTopBar(title: "Priority students"),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  GuideSpace.pagePadding, 16, GuideSpace.pagePadding, 28),
              children: [
                Text(
                  "Two ways of seeing who needs you — one from their activity, "
                  "one from what they have written.",
                  style: t.body.copyWith(height: 1.55, color: context.g.mutedText),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: GuidePastelRow(
                    pastel: GuidePastel.slate,
                    icon: Icons.flag_outlined,
                    title: "Priority students",
                    description: "Stale contact, missing reports, overdue meetings",
                    onTap: () => _open(context, const PriorityStudentsPage()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  // Master Task 2026-09-10, Part 6 — unseen = a flagged message
                  // since this guide last opened the list. Mirrors
                  // `FlaggedMessagesPage._stream`'s own scoped query exactly.
                  child: UnseenFeatureBadge(
                    featureKey: 'flaggedMessages',
                    timestampField: 'createdAt',
                    dotOffset: const Offset(10, 10),
                    latestQuery: (guide) =>
                        StudentScope.current().historyStream('flaggedChatMessages'),
                    child: GuidePastelRow(
                      pastel: GuidePastel.clay,
                      icon: Icons.chat_bubble_outline_rounded,
                      title: "Flagged messages",
                      description: "Distress signals and pastoral notes from chat",
                      onTap: () => _open(context, const FlaggedMessagesPage()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
