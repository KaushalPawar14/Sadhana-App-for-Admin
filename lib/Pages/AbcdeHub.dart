import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/ColorProvider.dart';
import '../utils/GuideRoster.dart';
import '../utils/UnseenFeatureBadge.dart';
import 'AssociationManager.dart';
import 'BookLinkManager.dart';
import 'ChantingChallengeManager.dart';
import 'ExpeditionManager.dart';
import 'ServiceBank.dart';

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
/// **Visual departure, deliberately.** The Admin Hub's `_actionBlob` tiles are
/// flat circles in a single blue. These are rounded rectangles with a diagonal
/// gradient and layered shadows so they read as raised — the distinction is
/// the point, so a guide can tell at a glance that this is a different kind of
/// surface from the hub they came from.
class AbcdeHubPage extends StatelessWidget {
  const AbcdeHubPage({super.key});

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
              "ABCDE",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 20,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  "The five limbs of practice. Chanting is recorded by "
                  "students themselves — set a group target here, and their "
                  "rounds are added together automatically.",
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: colorProvider.secondColor.withOpacity(.75),
                  ),
                ),
              ),

              _AbcdeButton(
                letter: "A",
                title: "Association",
                subtitle: "Meetings, requests and counter-proposals",
                icon: Icons.groups,
                // The per-dimension colours are not invented here — they match
                // the ABCDE activity card on the student profile
                // (AbcdeActivityCard.dart), which in turn follows the Student
                // app's five journey cards. One dimension, one colour,
                // everywhere it appears.
                colours: const [Color(0xFFEF6C00), Color(0xFFFF9800)],
                destination: const AssociationManagerPage(),
                // Master Task 2026-09-10, Part 6 — unseen = a student's own
                // action (request, counter-proposal) since this guide last
                // opened this screen. Single equality filter, reduced
                // client-side (see `UnseenFeatureBadge`'s own doc comment)
                // — no composite index, matching this project's convention.
                wrapBadge: (tile) => UnseenFeatureBadge(
                  featureKey: 'associations',
                  timestampField: 'updatedAt',
                  latestQuery: (guide) {
                    final col =
                        FirebaseFirestore.instance.collection('associations');
                    return (guide == kHodGuideId
                            ? col
                            : col.where('guideId', isEqualTo: guide))
                        .snapshots();
                  },
                  child: tile,
                ),
              ),
              _AbcdeButton(
                letter: "B",
                title: "Books",
                subtitle: "Dropbox links for each book, by level",
                icon: Icons.link,
                colours: const [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                destination: const BookLinkManagerPage(),
              ),
              _AbcdeButton(
                letter: "C",
                title: "Chanting",
                subtitle: "Set a group rounds target for your roster",
                icon: Icons.self_improvement,
                // Teal — the colour C already carries on the ABCDE activity
                // card, so the dimension keeps one identity everywhere.
                colours: const [Color(0xFF00695C), Color(0xFF00897B)],
                destination: const ChantingChallengeManagerPage(),
              ),
              _AbcdeButton(
                letter: "D",
                title: "Devotional Service",
                subtitle: "19 structured services, assignment and competence",
                icon: Icons.volunteer_activism,
                colours: const [Color(0xFFC62828), Color(0xFFE53935)],
                destination: const ServiceBankPage(),
                // Unseen = a student's own status change on an assignment
                // this guide made (`statusUpdatedAt`, Master Task 2026-09-10
                // Part 6).
                wrapBadge: (tile) => UnseenFeatureBadge(
                  featureKey: 'serviceAssignments',
                  timestampField: 'statusUpdatedAt',
                  latestQuery: (guide) {
                    final col = FirebaseFirestore.instance
                        .collection('serviceAssignments');
                    return (guide == kHodGuideId
                            ? col
                            : col.where('assignedByGuideId',
                                isEqualTo: guide))
                        .snapshots();
                  },
                  child: tile,
                ),
              ),
              _AbcdeButton(
                letter: "E",
                title: "Expeditions",
                subtitle: "Trips, registrations and reflections",
                icon: Icons.explore,
                colours: const [Color(0xFF1565C0), Color(0xFF1E88E5)],
                destination: const ExpeditionManagerPage(),
                // Unseen = a newly-submitted reflection on one of this
                // guide's students' registrations (`reflectionSubmittedAt`).
                wrapBadge: (tile) => UnseenFeatureBadge(
                  featureKey: 'expeditionReflections',
                  timestampField: 'reflectionSubmittedAt',
                  latestQuery: (guide) {
                    final col = FirebaseFirestore.instance
                        .collection('expeditionRegistrations');
                    return (guide == kHodGuideId
                            ? col
                            : col.where('guideId', isEqualTo: guide))
                        .snapshots();
                  },
                  child: tile,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A raised, gradient-filled rounded-rectangle button.
///
/// Deliberately unlike the Admin Hub's flat circular blobs: rounded rect,
/// diagonal gradient, and two stacked shadows — a soft coloured one tinted to
/// the button's own hue plus a neutral one — which is what gives the raised
/// look rather than a flat colour block.
class _AbcdeButton extends StatefulWidget {
  final String letter;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colours;
  final Widget destination;

  /// Master Task 2026-09-10, Part 6 — optional, wraps the whole tile with
  /// an [UnseenFeatureBadge] when this limb has its own unseen-content
  /// tracking. Null (the default) renders exactly as before — Chanting (no
  /// guide-facing unseen state of its own) and Books (a static catalog,
  /// out of this task's scope) pass nothing.
  final Widget Function(Widget tile)? wrapBadge;

  const _AbcdeButton({
    required this.letter,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colours,
    required this.destination,
    this.wrapBadge,
  });

  @override
  State<_AbcdeButton> createState() => _AbcdeButtonState();
}

class _AbcdeButtonState extends State<_AbcdeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tile = AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          // Pressing drops the button toward the surface rather than just
          // tinting it, so the raised effect is felt on tap too.
          transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.colours,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              // Tinted to the button's own colour — a neutral grey shadow
              // under a saturated gradient reads as dirt, not depth.
              BoxShadow(
                color: widget.colours.first.withOpacity(_pressed ? .22 : .40),
                blurRadius: _pressed ? 8 : 16,
                offset: Offset(0, _pressed ? 3 : 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(_pressed ? .06 : .12),
                blurRadius: _pressed ? 4 : 10,
                offset: Offset(0, _pressed ? 2 : 5),
              ),
            ],
          ),
          child: Row(
            children: [
              // Letter badge — the ABCDE letter is the thing a guide scans
              // for, so it leads rather than the icon.
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.22),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    widget.letter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.85),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(widget.icon, color: Colors.white.withOpacity(.9), size: 24),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () => Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => widget.destination,
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        ),
        child: widget.wrapBadge != null ? widget.wrapBadge!(tile) : tile,
      ),
    );
  }
}
