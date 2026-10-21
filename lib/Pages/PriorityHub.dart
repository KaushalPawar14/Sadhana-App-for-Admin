import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/StudentScope.dart';
import '../utils/UnseenAggregates.dart';
import '../utils/UnseenDot.dart';
import '../utils/UnseenFeatureBadge.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import 'FlaggedMessages.dart';
import 'PriorityStudents.dart';
import 'StudentDoubtsPage.dart';
import '../widgets/GuideEntry.dart';

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
class PriorityHubPage extends StatefulWidget {
  const PriorityHubPage({super.key});

  @override
  State<PriorityHubPage> createState() => _PriorityHubPageState();
}

class _PriorityHubPageState extends State<PriorityHubPage> {
  /// "Is any student's doubt waiting for me" - hoisted once (never built in `build()`).
  Stream<bool>? _doubtsUnseen;

  @override
  void initState() {
    super.initState();
    final me = AdminProfileProvider.current?.id ?? '';
    if (me.isNotEmpty) _doubtsUnseen = UnseenAggregates.studentDoubtsUnseen(me, AdminProfileProvider.viewerIsHod);
  }

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
                GuideEntry(
                  child: Text(
                    "Three ways of seeing who needs you — from their activity, "
                    "from what they have written, and from the doubts they ask.",
                    style: t.body.copyWith(height: 1.55, color: context.g.mutedText),
                  ),
                ),
                GuideEntry(
                  index: 1,
                  child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: GuidePastelRow(
                    pastel: GuidePastel.slate,
                    icon: Icons.flag_outlined,
                    title: "Priority students",
                    description: "Stale contact, missing reports, overdue meetings",
                    onTap: () => _open(context, const PriorityStudentsPage()),
                  ),
                ),
                ),
                GuideEntry(
                  index: 2,
                  child: Padding(
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
                ),
                GuideEntry(
                  index: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    // The doubts students sent to their guide while reading: the dot stays until each one is answered
                    // (or opened), whatever happened to the push.
                    child: StreamBuilder<bool>(
                      stream: _doubtsUnseen,
                      builder: (context, snap) => UnseenBadge(
                        key: const ValueKey('doubts-hub-dot'),
                        show: snap.data ?? false,
                        offset: const Offset(10, 10),
                        child: GuidePastelRow(
                          pastel: GuidePastel.sage,
                          icon: Icons.help_outline_rounded,
                          title: "Students' doubts",
                          description: "Questions students asked while reading",
                          onTap: () => _open(context, const StudentDoubtsPage()),
                        ),
                      ),
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
