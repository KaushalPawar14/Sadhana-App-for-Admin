import 'package:flutter/material.dart';
import 'package:folk_guide_app/Pages/AbcdeHub.dart';
import 'package:folk_guide_app/Pages/Leaderboard.dart';
import 'package:folk_guide_app/Pages/AgentLogPage.dart';
import 'package:folk_guide_app/Pages/PriorityHub.dart';
import '../Services/UpdateFCM.dart';
import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/UnseenAggregates.dart';
import '../utils/UnseenDot.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideTiles.dart';

/// The Analysis tab ("Folk analysis"): five tiles — ABCDE, Week planning,
/// Priority students, Guide targets, Leaderboard. Each opens the same screen as before.
///
/// (The old floating "bob" animation on the tiles — an always-running ticker per
/// tile — is gone; press feedback is the only motion.)
class CompetitionPage extends StatefulWidget {
  const CompetitionPage({super.key});

  @override
  State<CompetitionPage> createState() => _CompetitionPageState();
}

class _CompetitionPageState extends State<CompetitionPage> {
  /// One aggregate stream per tile that leads somewhere with unseen content, built
  /// from the SAME shared `UnseenAggregates` functions the nav bar uses, so a dot
  /// here can never appear or disappear out of step with the nav bar's own dot.
  /// Built once, once the guide is known — never in `build()`.
  Stream<bool>? _abcdeUnseen;
  Stream<bool>? _priorityStudentsUnseen;

  /// A Guide's or Enabler's new Assistant log entry, for a HOD (the log lives here, in Analysis).
  Stream<bool>? _logUnseen;

  @override
  void initState() {
    super.initState();
    // Built once, here (a HOD only: the log is theirs to read).
    final me = AdminProfileProvider.current;
    if (AdminProfileProvider.viewerIsHod && me != null) _logUnseen = UnseenAggregates.assistantLogUnseen(me.id);
    UpdateTokenService().getSavedGuide().then((guide) {
      if (!mounted || guide == null || guide.isEmpty) return;
      final isHod = AdminProfileProvider.viewerIsHod;
      setState(() {
        _abcdeUnseen = UnseenAggregates.anyOf([
          UnseenAggregates.associationsUnseen(guide, isHod),
          UnseenAggregates.serviceAssignmentsUnseen(guide, isHod),
          UnseenAggregates.expeditionReflectionsUnseen(guide, isHod),
        ]);
        _priorityStudentsUnseen = UnseenAggregates.anyOf([
          UnseenAggregates.flaggedMessagesUnseen(guide, isHod),
          UnseenAggregates.studentDoubtsUnseen(guide, isHod),
          UnseenAggregates.priorityReasonsUnseen(guide, isHod),
        ]);
      });
    });
  }

  void _open(Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// A full-width card, with an unseen dot when [unseen] says so.
  Widget _card({
    required int index,
    required GuidePastel pastel,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Stream<bool>? unseen,
    Key? key,
    Key? dotKey,
  }) {
    final card = GuideNavCard(
      key: key,
      pastel: pastel,
      icon: icon,
      title: title,
      description: subtitle,
      onTap: onTap,
    );
    return GuideEntry(
      index: index,
      child: Padding(
        padding: EdgeInsets.only(top: index == 0 ? 0 : GuideSpace.cardGap),
        child: unseen == null
            ? card
            : StreamBuilder<bool>(
                stream: unseen,
                builder: (context, snap) => UnseenBadge(
                  key: dotKey,
                  show: snap.data ?? false,
                  offset: const Offset(10, 10),
                  child: card,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return ListView(
      padding: EdgeInsets.only(bottom: GuideSpace.navClearanceOf(context)),
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                GuideSpace.pagePadding, 28, GuideSpace.pagePadding, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GuideLabel('Insights'),
                const SizedBox(height: 4),
                Text('Folk analysis', style: t.screenTitle),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              GuideSpace.pagePadding, 22, GuideSpace.pagePadding, 0),
          child: Column(
            children: [
              _card(
                index: 0,
                pastel: GuidePastel.sand,
                icon: Icons.spa_outlined,
                title: 'ABCDE',
                subtitle: 'Five limbs of practice',
                // The four ABCDE management screens, gathered in one hub.
                onTap: () => _open(const AbcdeHubPage()),
                unseen: _abcdeUnseen,
              ),
              _card(
                index: 1,
                pastel: GuidePastel.clay,
                icon: Icons.flag_outlined,
                title: 'Interactions needed',
                subtitle: 'Who needs an interaction',
                // A small hub over the three "who needs attention" screens.
                onTap: () => _open(const PriorityHubPage()),
                unseen: _priorityStudentsUnseen,
              ),
              _card(
                index: 2,
                pastel: GuidePastel.sage,
                icon: Icons.emoji_events_outlined,
                title: 'Leaderboard',
                subtitle: 'FOLK and Hostel & Localite rankings',
                // One ranking at a time: category (FOLK / Hostel & Localite), period,
                // and (HOD only) Boys or Girls; always inside the admin's own scope.
                onTap: () => _open(const LeaderboardPage()),
              ),
              // What the AI assistant has done: HODs only (the server's log; the rules let only a HOD read it). It used to be in the Tasks tab.
              if (AdminProfileProvider.viewerIsHod)
                _card(
                  index: 3,
                  pastel: GuidePastel.mauve,
                  icon: Icons.auto_awesome_outlined,
                  title: 'Assistant log',
                  subtitle: 'What the AI assistant did, and for whom',
                  onTap: () => _open(const AgentLogPage()),
                  unseen: _logUnseen,
                  key: const ValueKey('agent-log-card'),
                  dotKey: const ValueKey('agent-log-dot'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
