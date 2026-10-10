import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/Home/FolkBoysEntry.dart';
import 'package:folk_guide_app/Pages/BoysDetails.dart';
import 'package:folk_guide_app/Pages/Competition.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/MalaLoading.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/UnseenDot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Pages/GuideSignIn.dart';
import 'ColorProvider.dart';
import 'GuideAuthGate.dart';

class CurvedNavBar extends StatefulWidget {
  final String Guidename;
  const CurvedNavBar(this.Guidename);
  @override
  State<CurvedNavBar> createState() => _CurvedNavBarState();
}

class _CurvedNavBarState extends State<CurvedNavBar> {
  int currentIdx = 1; // Set default index to 1 for CalendarPage
  final List<String> titles = ['Folk analysis', 'FOLK Boys', 'Other tasks'];
  late String adminName = widget.Guidename;
  bool isLoading = true; // Flag to indicate loading state
  late List<Widget> screens; // ✅ declare late

  /// Master Task 2026-09-10, Part 6 item 5, extended by the follow-up
  /// task ("propagate orange dots to intermediate tiles") — one aggregate
  /// "is there anything unseen under this tab" stream per tab that
  /// actually hosts content with unseen state (Other Tasks does not).
  /// Built exactly once here, in `initState()` — never in `build()` —
  /// from `adminName`, which (unlike most screens in this app) is already
  /// known synchronously via the constructor. Every per-feature stream is
  /// shared via `utils/UnseenAggregates.dart` — the SAME functions back
  /// the intermediate tile dots in `Competition.dart`/`FolkBoysEntry.dart`,
  /// so the nav bar and every tile below it read from one source of truth
  /// and can never show a dot at one level but not the other. Entirely
  /// additive — nothing here reads or touches `_usersQuery`,
  /// `_visibleColumns`, drag/drop, or the deletion path.
  late final Stream<bool> _tab0Unseen;
  late final Stream<bool> _tab1Unseen;

  @override
  void initState() {
    super.initState();
    // Initialize screens with placeholders first
    screens = [
      CompetitionPage(), // Placeholder for CompetitionPage
      // FOLK Boys board redesign: this tab's own top-level screen is now
      // `FolkBoysEntryScreen` — one entry tile, which pushes the board
      // workspace (`Home/FolkBoysWorkspace.dart`) as a separate page with a
      // normal back button (Part 4 device-test fix). No more of
      // `Home/MainPage.dart`'s old two-tile `DashboardScreen`.
      FolkBoysEntryScreen(selectedGuide: adminName),
      AdminControlPage()
    ];

    isLoading = false;
    _buildUnseenStreams();
  }

  void _buildUnseenStreams() {
    final guide = adminName;
    final isHod = AdminProfileProvider.viewerIsHod;

    _tab0Unseen = UnseenAggregates.anyOf([
      UnseenAggregates.associationsUnseen(guide, isHod),
      UnseenAggregates.expeditionReflectionsUnseen(guide, isHod),
      UnseenAggregates.serviceAssignmentsUnseen(guide, isHod),
      UnseenAggregates.flaggedMessagesUnseen(guide, isHod),
      UnseenAggregates.goalProposalsUnseen(guide),
    ]);

    _tab1Unseen = UnseenAggregates.anyOf([
      UnseenAggregates.calendarEventsUnseen(guide),
      UnseenAggregates.studentCommentsRosterUnseen(guide, isHod),
      UnseenAggregates.bookCommitmentsRosterUnseen(guide, isHod),
    ]);
  }

  /// Master Task 2026-09-10, Part 6 item 5 — small, restrained, works in
  /// light/dark since `UnseenDot`'s ring colour reads from the current
  /// theme, not a hardcoded one. `CurvedNavigationBar` takes plain
  /// `Widget`s per item; wrapping the icon in a `Stack` here is a drop-in
  /// swap, not a change to how the bar itself lays out or animates items.
  Widget _navIcon(IconData icon, Stream<bool> unseen) {
    return StreamBuilder<bool>(
      stream: unseen,
      builder: (context, snap) => UnseenBadge(
        show: snap.data ?? false,
        offset: const Offset(4, 2),
        child: Icon(icon, size: 30, color: Colors.white),
      ),
    );
  }

  void _logout() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Confirm Logout"),
        content: Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text("Logout")),
        ],
      ),
    );

    if (confirm ?? false) {
      // Real-auth task (2026-09-12): this call already existed before this
      // app had any real Firebase Auth session, so it was previously a
      // no-op. Now that Google Sign-In is real, a plain
      // `FirebaseAuth.instance.signOut()` here — landing on
      // `FolkGuideSelectionPage()` straight after — would leave the picker
      // reachable with no signed-in session behind it, which breaks every
      // Firestore call the very next screen makes. Routed through
      // `GuideAuthGate.signOut()` (Google + Firebase together) and
      // `GuideSignInPage` instead, so "Logout" now does what its own
      // confirmation dialog has always said it does.
      await GuideAuthGate.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_guide');

      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const GuideSignInPage()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            titles[currentIdx],
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 25,
              color: colorProvider.secondColor,
            ),
          ),
          backgroundColor: colorProvider.color,
          actions: [
            if (currentIdx == 1)
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: "Logout",
                onPressed: _logout,
                color: colorProvider.secondColor,
              )
          ],
        ),
        body: isLoading
            ? CustomLoader() // Show loading indicator
            : screens[currentIdx], // Show the correct screen
        // ⚠️ NOT `SafeArea`. That was the bug (fixed 2026-08-14).
        //
        // `SafeArea` insets the bar by `MediaQuery.padding.bottom` and paints
        // nothing in the reserved strip, so whatever is behind shows through:
        //
        //   * Gesture navigation — the system's home-indicator pill is a thin
        //     OVERLAY (~24-34px) and reports a non-zero bottom inset. SafeArea
        //     therefore pushed the whole bar UP by that much and left a bare
        //     strip beneath it, which is exactly the "floating above the screen
        //     edge" symptom.
        //   * 3-button navigation — the opaque system bar reports a larger
        //     inset (~48px), and reserving it is genuinely necessary, otherwise
        //     the bar would sit underneath the system buttons.
        //
        // So the inset itself was right; painting nothing in it was wrong.
        // This `Container` reserves the identical runtime inset but fills it
        // with the bar's OWN colour, so the bar reads as extending to the
        // physical bottom edge on gesture devices while still clearing the
        // opaque bar in 3-button mode. No mode detection, no magic numbers —
        // one expression that adapts because the inset itself differs.
        //
        // `viewPadding` rather than `padding` on purpose: `padding` collapses
        // to zero while a keyboard is open, which would make the strip flicker
        // away mid-typing.
        bottomNavigationBar: Container(
          color: colorProvider.thirdColor,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewPadding.bottom,
          ),
          child: CurvedNavigationBar(
            // Master Task 2026-09-10, Part 6 item 5 — items 0/1 now carry
            // an unseen dot from the two hoisted streams above; item 2
            // (Other Tasks) has no unseen-content feature of its own, so
            // it stays a plain `Icon`, unchanged.
            items: <Widget>[
              _navIcon(Icons.dataset_outlined, _tab0Unseen),
              _navIcon(Icons.mark_unread_chat_alt_outlined, _tab1Unseen),
              const Icon(
                Icons.person,
                size: 30,
                color: Colors.white,
              ),
            ],
            buttonBackgroundColor: colorProvider.thirdColor,
            backgroundColor: colorProvider.color,
            color: colorProvider.thirdColor,
            animationCurve: Curves.easeInOut,
            height: 68,
            animationDuration: const Duration(milliseconds: 250),
            index: currentIdx, // Set the initial selected index
            onTap: (index) {
              setState(() {
                currentIdx = index;
              });
            },
          ),
        ),
      );
    });
  }
}
