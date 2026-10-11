import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/StudentScope.dart';
import '../utils/UnseenFeatureBadge.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import 'AssociationManager.dart';
import 'BookLinkManager.dart';
import 'ChantingChallengeManager.dart';
import 'ExpeditionManager.dart';
import 'ServiceBank.dart';
import '../widgets/GuideEntry.dart';

/// ABCDE hub — the guide-side entry point for the four ABCDE limbs that have
/// a management screen.
///
/// Reached from the "ABCDE" tile on the Folk Analysis tab. Every destination
/// below is an **existing screen, opened completely unchanged** — this page
/// only gathers four entry points that previously sat as separate circular
/// tiles in the Admin Hub.
///
/// **All five limbs now have a screen.** C — Chanting — was the last gap:
/// until 2026-08-14 this page carried four buttons and a caption explaining
/// that C had no management screen, because japa is self-recorded by students.
/// `ChantingChallengeManagerPage` filled it — a guide does not record chanting
/// here, they set a **collective rounds target** for their whole roster, and a
/// Cloud Function sums the students' own reports towards it. There is no
/// per-student pass or fail; the roster reaches the target together.
///
/// **Look.** Five pastel rows (sand, slate, sage, clay, mauve), each with a
/// serif letter tile, the limb's name, a one-line description and a chevron.
class AbcdeHubPage extends StatelessWidget {
  const AbcdeHubPage({super.key});

  /// Opens a limb's screen with the fade the hub has always used.
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

  Widget _row(
    BuildContext context, {
    required String letter,
    required GuidePastel pastel,
    required String title,
    required String subtitle,
    required Widget destination,
    Widget Function(Widget tile)? wrapBadge,
  }) {
    // The five dimensions keep the pastel family of the Ink & Brass design: sand,
    // slate, sage, clay, mauve (a slightly deeper set in dark mode).
    final row = GuidePastelRow(
      pastel: pastel,
      abcde: true,
      letter: letter,
      title: title,
      description: subtitle,
      onTap: () => _open(context, destination),
    );
    return GuideEntry(
      // A..E rise one after another, after the intro line.
      index: letter.codeUnitAt(0) - 64,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: wrapBadge != null ? wrapBadge(row) : row,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return GuideScaffold(
      body: Column(
        children: [
          const GuideTopBar(title: "ABCDE"),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  GuideSpace.pagePadding, 16, GuideSpace.pagePadding, 28),
              children: [
                GuideEntry(
                  child: Text(
                    "The five limbs of practice. Chanting is recorded by "
                    "students themselves. Set a group target here, and their "
                    "rounds are added together automatically.",
                    style: t.body.copyWith(height: 1.55, color: context.g.mutedText),
                  ),
                ),
                _row(
                  context,
                  letter: "A",
                  pastel: GuidePastel.sand,
                  title: "Association",
                  subtitle: "Meetings, requests and counter-proposals",
                  destination: const AssociationManagerPage(),
                  // Unseen = a student's own action (request, counter-proposal)
                  // since this guide last opened this screen. Single equality
                  // filter, reduced client-side — no composite index.
                  wrapBadge: (tile) => UnseenFeatureBadge(
                    featureKey: 'associations',
                    timestampField: 'updatedAt',
                    dotOffset: const Offset(10, 10),
                    // Scoped history stream (HOD all; others their visible
                    // students) — the old `guideId` stamp is not used.
                    latestQuery: (guide) =>
                        StudentScope.current().historyStream('associations'),
                    child: tile,
                  ),
                ),
                _row(
                  context,
                  letter: "B",
                  pastel: GuidePastel.slate,
                  title: "Books",
                  subtitle: "Dropbox links for each book, by level",
                  destination: const BookLinkManagerPage(),
                ),
                _row(
                  context,
                  letter: "C",
                  pastel: GuidePastel.sage,
                  title: "Chanting",
                  subtitle: "Set a group rounds target for your roster",
                  destination: const ChantingChallengeManagerPage(),
                ),
                _row(
                  context,
                  letter: "D",
                  pastel: GuidePastel.clay,
                  title: "Devotional service",
                  subtitle: "19 structured services, assignment and competence",
                  destination: const ServiceBankPage(),
                  // Unseen = a student's own status change on an assignment this
                  // guide made (`statusUpdatedAt`).
                  wrapBadge: (tile) => UnseenFeatureBadge(
                    featureKey: 'serviceAssignments',
                    timestampField: 'statusUpdatedAt',
                    dotOffset: const Offset(10, 10),
                    latestQuery: (guide) =>
                        StudentScope.current().historyStream('serviceAssignments'),
                    child: tile,
                  ),
                ),
                _row(
                  context,
                  letter: "E",
                  pastel: GuidePastel.mauve,
                  title: "Expeditions",
                  subtitle: "Trips, registrations and reflections",
                  destination: const ExpeditionManagerPage(),
                  // Unseen = a newly-submitted reflection on one of this guide's
                  // students' registrations (`reflectionSubmittedAt`).
                  wrapBadge: (tile) => UnseenFeatureBadge(
                    featureKey: 'expeditionReflections',
                    timestampField: 'reflectionSubmittedAt',
                    dotOffset: const Offset(10, 10),
                    latestQuery: (guide) =>
                        StudentScope.current().historyStream('expeditionRegistrations'),
                    child: tile,
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
