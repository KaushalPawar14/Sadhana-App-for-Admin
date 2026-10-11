import 'package:flutter/material.dart';
import 'package:folk_guide_app/Pages/AbcdeHub.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/Pages/Leaderboard.dart';
import 'package:folk_guide_app/Pages/PriorityHub.dart';
import 'package:folk_guide_app/Pages/WeeklyPlanning.dart';
import '../Services/UpdateFCM.dart';
import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/Snackbar.dart';
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
  /// Resolved once on load, the same `SharedPreferences['selected_guide']` every
  /// other guide-scoped screen in this app uses; the "Guide targets" tile needs it.
  String? _guide;

  /// One aggregate stream per tile that leads somewhere with unseen content, built
  /// from the SAME shared `UnseenAggregates` functions the nav bar uses, so a dot
  /// here can never appear or disappear out of step with the nav bar's own dot.
  /// Built once, in the same callback `_guide` is set from — never in `build()`.
  /// "Week planning" has no stream of its own: nothing exclusively lives there.
  Stream<bool>? _abcdeUnseen;
  Stream<bool>? _priorityStudentsUnseen;
  Stream<bool>? _guideTargetsUnseen;

  @override
  void initState() {
    super.initState();
    UpdateTokenService().getSavedGuide().then((guide) {
      if (!mounted || guide == null || guide.isEmpty) return;
      final isHod = AdminProfileProvider.viewerIsHod;
      setState(() {
        _guide = guide;
        _abcdeUnseen = UnseenAggregates.anyOf([
          UnseenAggregates.associationsUnseen(guide, isHod),
          UnseenAggregates.serviceAssignmentsUnseen(guide, isHod),
          UnseenAggregates.expeditionReflectionsUnseen(guide, isHod),
        ]);
        _priorityStudentsUnseen =
            UnseenAggregates.flaggedMessagesUnseen(guide, isHod);
        _guideTargetsUnseen = UnseenAggregates.goalProposalsUnseen(guide);
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

  void _openTargets() {
    final guide = _guide;
    if (guide == null || guide.isEmpty) {
      // Guide identity hasn't resolved yet (or none is set on this device) —
      // fails closed with a message rather than pushing `GoalHomePage` with an
      // empty guideId.
      showSnackbar(
        context,
        'Still loading your guide profile — try again in a moment',
        Colors.yellow,
        Icons.watch_later_outlined,
      );
      return;
    }
    _open(GoalHomePage(guideId: guide));
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
  }) {
    final card = GuideNavCard(
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
                pastel: GuidePastel.slate,
                icon: Icons.event_note_outlined,
                title: 'Week planning',
                subtitle: 'Plan the week ahead',
                onTap: () => _open(const WeeklyPlanningPage()),
              ),
              _card(
                index: 2,
                pastel: GuidePastel.clay,
                icon: Icons.flag_outlined,
                title: 'Priority students',
                subtitle: 'Who needs attention',
                // A small hub over the two "who needs attention" screens.
                onTap: () => _open(const PriorityHubPage()),
                unseen: _priorityStudentsUnseen,
              ),
              _card(
                index: 3,
                pastel: GuidePastel.mauve,
                icon: Icons.track_changes_outlined,
                title: 'Guide targets',
                subtitle: 'Group targets and phases',
                onTap: _openTargets,
                unseen: _guideTargetsUnseen,
              ),
              _card(
                index: 4,
                pastel: GuidePastel.sage,
                icon: Icons.emoji_events_outlined,
                title: 'Leaderboard',
                subtitle: 'FOLK and Hostel & Localite rankings',
                // One ranking at a time: category (FOLK / Hostel & Localite), period,
                // and (HOD only) Boys or Girls; always inside the admin's own scope.
                onTap: () => _open(const LeaderboardPage()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
