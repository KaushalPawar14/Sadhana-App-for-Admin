import 'package:flutter/material.dart';
import 'package:folk_guide_app/Pages/AbcdeHub.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/Pages/PriorityHub.dart';
import 'package:folk_guide_app/Pages/WeeklyPlanning.dart';
import 'package:provider/provider.dart';
import '../Services/UpdateFCM.dart';
import '../utils/ColorProvider.dart';
import '../utils/GuideRoster.dart';
import '../utils/Snackbar.dart';
import '../utils/UnseenAggregates.dart';
import '../utils/UnseenDot.dart';

class CompetitionPage extends StatefulWidget {

  @override
  State<CompetitionPage> createState() => _CompetitionPageState();
}

class _CompetitionPageState extends State<CompetitionPage> with TickerProviderStateMixin {
  int? selectedIndex;
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  /// Resolved once on load, the same `SharedPreferences['selected_guide']`
  /// every other guide-scoped screen in this app uses (`FolkBoysEntry.dart`,
  /// `Pages/WeeklyPlanning.dart`, the old `Home/Dashboard.dart`) — this page
  /// previously never needed a guide identity at all (ABCDE/Priority
  /// Students/Week Planning don't take one), so nothing here was resolving
  /// it until the "Guide Targets" tile below needed one.
  String? _guide;

  /// Follow-up task, 2026-09-10 ("propagate orange dots to intermediate
  /// tiles") — one aggregate stream per tile that leads somewhere with
  /// unseen content, built from the SAME shared `UnseenAggregates`
  /// functions the nav bar itself uses (`utils/BottomNavBar.dart`), so a
  /// dot here can never appear or disappear out of step with the nav
  /// bar's own dot. Built once, in the same guide-resolution callback
  /// `_guide` itself is set from — never in `build()`. "Week Planning" has
  /// no stream of its own: nothing exclusively lives there (it re-displays
  /// associations/goals data already tracked at their own source).
  Stream<bool>? _abcdeUnseen;
  Stream<bool>? _priorityStudentsUnseen;
  Stream<bool>? _guideTargetsUnseen;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(6, (index) {
      return AnimationController(
        vsync: this,
        duration: Duration(seconds: 2 + index % 3), // slightly different durations
      )..repeat(reverse: true);
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0, end: 8).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    UpdateTokenService().getSavedGuide().then((guide) {
      if (!mounted || guide == null || guide.isEmpty) return;
      final isHod = guide == kHodGuideId;
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

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> cards = [
      // "Weekly Performance", "Monthly Performance", and "Graphical
      // Analysis" tiles were removed from this grid on 2026-08-29. Weekly/
      // Monthly Performance (and the Results leaderboards reached through
      // them) had no capability found nowhere else — pure read-only views
      // over the `competition` collection — and were deleted outright along
      // with their screens. Graphical Analysis's actual chart content was
      // per-student, not roster-wide, so it was moved into Calendar.dart's
      // "Scores" tab as its own section below the score cards; see
      // `Pages/AllGraph.dart`'s `GraphicalAnalysisSection` and
      // `Home/Calendar.dart`'s `_scoresPanel`. Colours below are otherwise
      // unchanged from before this removal.
      {"title": "ABCDE", "icon": Icons.spa_outlined, "color": Colors.blue.shade500},
      {"title": "Week Planning", "icon": Icons.event_note, "color": Colors.blue.shade500},
      // Was "Best Performer" until 2026-08-14. ⚠️ That tile had no handler and
      // no screen — its only occurrence in the whole app was this line, and it
      // fell through to the "Coming soon" snackbar. There was no leaderboard
      // feature to drop, so nothing was lost or orphaned; the slot was simply
      // repurposed, exactly as the two Results slots were.
      {"title": "Priority Students", "icon": Icons.flag, "color": Colors.blue.shade300},
      // Added 2026-08-29 (Phase 5 follow-up): the Guide Target Planning
      // feature (compound targets, AI phase plans, roadmap, weekly phase
      // page — `Pages/GoalHomePage.dart` and its own sub-screens) had been
      // completely unreachable since the board redesign, and only got a
      // temporary AppBar flag icon on `Home/FolkBoysWorkspace.dart` as a
      // stopgap. This tile is its real, permanent home — same destination
      // the board's icon opened. `Icons.track_changes` deliberately chosen
      // over another `Icons.flag` to avoid visual confusion with "Priority
      // Students" above, which already uses that icon for an unrelated
      // feature. Fills the grid back to an even 2x2 after the three
      // removals earlier this session.
      {"title": "Guide Targets", "icon": Icons.track_changes, "color": Colors.blue.shade400},
    ];

    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        body: Padding(
          padding: const EdgeInsets.only(top: 50, left: 16, right: 16),
          child: GridView.builder(
            itemCount: cards.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 35,
              crossAxisSpacing: 20,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final card = cards[index];
              return GestureDetector(
                onTap: () {
                  if (card['title'] == "Stay at Hostel") {

                    showSnackbar(
                      context,
                      'Coming soon',
                      Colors.yellow,
                      Icons.watch_later_outlined,
                    );
                    return; // 🚨 stop further execution
                  }

                  if (card['title'] == "ABCDE") {
                    // The four ABCDE management screens, gathered from the
                    // Admin Hub on 2026-08-14. Each destination is unchanged.
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const AbcdeHubPage(),
                        transitionsBuilder: (_, animation, __, child) =>
                            FadeTransition(opacity: animation, child: child),
                      ),
                    );
                  } else if (card['title'] == "Priority Students") {
                    // A small hub over the two "who needs attention" screens,
                    // both moved off the Admin Hub on 2026-08-14.
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const PriorityHubPage(),
                        transitionsBuilder: (_, animation, __, child) =>
                            FadeTransition(opacity: animation, child: child),
                      ),
                    );
                  } else if (card['title'] == "Week Planning") {
                    // Relocated here from the Admin Hub's "This Week" tile on
                    // 2026-08-14. Same Phase 6 Monday planning dashboard,
                    // reused as-is — only its entry point moved.
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const WeeklyPlanningPage(),
                        transitionsBuilder: (_, animation, __, child) =>
                            FadeTransition(opacity: animation, child: child),
                      ),
                    );
                  } else if (card['title'] == "Guide Targets") {
                    final guide = _guide;
                    if (guide == null || guide.isEmpty) {
                      // Guide identity hasn't resolved yet (or none is set
                      // on this device) — fails closed with a message rather
                      // than pushing `GoalHomePage` with an empty guideId,
                      // matching every other guide-scoped screen's own
                      // "no guide selected" guard.
                      showSnackbar(
                        context,
                        'Still loading your guide profile — try again in a moment',
                        Colors.yellow,
                        Icons.watch_later_outlined,
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => GoalHomePage(guideId: guide),
                        transitionsBuilder: (_, animation, __, child) =>
                            FadeTransition(opacity: animation, child: child),
                      ),
                    );
                  } else {
                    // Defensive fallback only — every title currently in
                    // `cards` has its own branch above, so this is
                    // unreachable in practice. Left in place the way "Best
                    // Performer" was before it got its own slot.
                    showSnackbar(
                      context,
                      'Coming soon',
                      Colors.yellow,
                      Icons.watch_later_outlined,
                    );
                  }
                },
                child: AnimatedBuilder(
                  animation: _animations[index],
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, -_animations[index].value),
                      child: child,
                    );
                  },
                  // Follow-up task, 2026-09-10 — every tile that leads
                  // somewhere with unseen content shows a dot; "Week
                  // Planning" has none of its own (see `_abcdeUnseen`'s own
                  // doc comment).
                  child: _tileUnseenStream(card['title'] as String) == null
                      ? _cardTile(colorProvider, card, index)
                      : StreamBuilder<bool>(
                          stream: _tileUnseenStream(card['title'] as String),
                          builder: (context, snap) => UnseenBadge(
                            show: snap.data ?? false,
                            // Grid-squeeze fix, 2026-09-10, item 2 — a
                            // more generous inset than the default (tuned
                            // for a small icon) so the dot lands clearly
                            // on this tile's own rounded, shadowed
                            // surface, the same corner on every tile.
                            offset: const Offset(8, 8),
                            // This tile's own `AnimatedContainer` has no
                            // explicit width/height and relies entirely on
                            // the GridView cell's tight constraints to
                            // size itself — the bounded-parent case
                            // `UnseenBadge.fillParent`'s own doc comment
                            // describes (2026-09-11).
                            fillParent: true,
                            child: _cardTile(colorProvider, card, index),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
      );
    });
  }

  /// Pure lookup of an already-built field — never constructs a `Stream`
  /// itself, so calling this from `build()` (twice, for the null-check and
  /// the `StreamBuilder`) never reintroduces the stream-in-build() bug.
  Stream<bool>? _tileUnseenStream(String title) {
    switch (title) {
      case "ABCDE":
        return _abcdeUnseen;
      case "Priority Students":
        return _priorityStudentsUnseen;
      case "Guide Targets":
        return _guideTargetsUnseen;
      default:
        return null;
    }
  }

  /// Extracted unchanged from `itemBuilder` (Master Task 2026-09-10, Part
  /// 6) so it can be wrapped in an unseen badge for one card without
  /// duplicating this widget tree for every other card.
  Widget _cardTile(
      ColorProvider colorProvider, Map<String, dynamic> card, int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: card['color'],
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorProvider.secondColor.withOpacity(0.5),
            offset: const Offset(0, 4),
          ),
        ],
        border: selectedIndex == index
            ? Border.all(color: Colors.yellowAccent, width: 3)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(card['icon'], size: 50, color: Colors.white),
          const SizedBox(height: 16),
          Text(
            card['title'],
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
