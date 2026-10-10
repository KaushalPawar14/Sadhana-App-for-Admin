import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../Pages/FolkGuideSelect.dart';
import '../Pages/GuideCalendarPage.dart';
import '../Services/UpdateFCM.dart';
import '../Services/UpdateToken.dart';
import '../utils/CalendarQueries.dart' show kScopeMandatory;
import '../utils/ColorProvider.dart';
import '../utils/GuideRoster.dart';
import '../utils/UnseenAggregates.dart';
import '../utils/UnseenDot.dart';
import '../utils/UnseenFeatureBadge.dart';
import 'FolkBoysWorkspace.dart';

/// The middle "FOLK Boys" nav tab's own top-level screen (Part 4 of the
/// Phase 1 device-test fixes).
///
/// ---------------------------------------------------------------------------
/// One tile, not the board directly
/// ---------------------------------------------------------------------------
/// The device test asked for the board workspace to sit BEHIND a single
/// entry tile, rather than opening as soon as the tab is shown. Tapping the
/// tile pushes `FolkBoysWorkspace` as a normal page (with a normal back
/// button); this screen itself is the tab's permanent body.
///
/// Reuses `Home/MainPage.dart`'s own `DashboardTile` widget — the exact
/// visual style the old two-tile chooser used (Rule 1: reuse, don't invent a
/// new look) — rather than rebuilding that gradient/shadow/press styling a
/// second time. **Phase 5, Part 4: copied verbatim into this file**, not
/// imported, since `MainPage.dart` is scheduled for full deletion in Phase 6
/// and this was the one live cross-cluster dependency on it (grep-confirmed
/// the only other use of `DashboardTile` is `MainPage.dart`'s own, now-dead,
/// two-tile body). `MainPage.dart` keeps its own copy until Phase 6 deletes
/// that whole file — same "temporary duplicate for one phase" pattern
/// already used for `DobCard` in `Pages/StudentProfilePage.dart`.
///
/// ---------------------------------------------------------------------------
/// Guide resolution + FCM registration now live HERE, on tab entry
/// ---------------------------------------------------------------------------
/// This is the plumbing Phase 1 originally (and correctly) rescued from the
/// old `DashboardScreen` (`Home/MainPage.dart`) — resolving the guide,
/// redirecting to `FolkGuideSelectionPage` if none is set, and re-
/// registering the FCM token into `adminUsers/{guide}.fcmToken` (which
/// `Pages/InteractionLogger.dart`'s HOD-notify path reads). It now runs here,
/// in THIS screen's `initState`, because this is what actually loads the
/// moment the tab is opened — `FolkBoysWorkspace` no longer runs any of this
/// itself, it just receives the already-resolved guide as a constructor
/// param once the tile is tapped.
///
/// ---------------------------------------------------------------------------
/// Restored from the old `DashboardScreen` (drag-fix/seed-removal
/// continuation task) — the fade-in entrance, the theme toggle, and the
/// logged-in guide display
/// ---------------------------------------------------------------------------
/// All three were silently dropped when this screen replaced the old
/// two-tile chooser and were never asked for again until now. Restored
/// EXACTLY, not reimplemented:
///   - `_opacity`/`AnimatedOpacity` — the same 600ms fade-in, starting 100ms
///     after `initState`, byte-for-byte the old timing.
///   - The dark-mode `IconButton` — calls the SAME
///     `ColorProvider.toggleColor()` (`utils/ColorProvider.dart`), which
///     persists to `SharedPreferences['isDarkMode']` and is the one theme
///     mechanism the whole app already shares — nothing new introduced.
///   - "Folk Guide: $guide" text — same wording, same conditional
///     (`if (guide != null)`), same position: a top row, guide name on the
///     left, toggle on the right, above the tile.
/// Grep-confirmed nothing else existed in the old screen to account for:
/// its only other content was the two-tile `ListView` (now one tile, an
/// intentional, already-approved change from the board-redesign task) and
/// the `DashboardTile`/`_DashboardTileState` classes (still reused via the
/// `show DashboardTile` import above, unchanged).
class FolkBoysEntryScreen extends StatefulWidget {
  final String? selectedGuide;

  const FolkBoysEntryScreen({super.key, this.selectedGuide});

  @override
  State<FolkBoysEntryScreen> createState() => _FolkBoysEntryScreenState();
}

class _FolkBoysEntryScreenState extends State<FolkBoysEntryScreen> {
  String? _guide;

  /// Restored fade-in — same 100ms delay, same target, as the old
  /// `DashboardScreen._opacity`.
  double _opacity = 0;

  /// Follow-up task, 2026-09-10 ("propagate orange dots to intermediate
  /// tiles") — the "FOLK Boys Board" tile's own dot: any of THIS guide's
  /// roster has an unseen student comment or book commitment, aggregated
  /// via the shared `UnseenAggregates` roster helpers (same rule the
  /// board's own `_visibleColumns` uses — HOD sees everyone, any other
  /// guide sees their own students plus Unassigned — read independently,
  /// never touching `_usersQuery`/`_visibleColumns` themselves). Built
  /// once, from `_fetchSavedGuide()`, never in `build()`.
  Stream<bool>? _boardUnseen;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacity = 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTokenForGuide();
      _fetchSavedGuide();
    });
  }

  // ---------------------------------------------------------------------------
  // Ported unchanged from Home/MainPage.dart's DashboardScreen
  // ---------------------------------------------------------------------------

  Future<void> _fetchSavedGuide() async {
    final guide =
        widget.selectedGuide ?? await UpdateTokenService().getSavedGuide();
    if (!mounted) return;
    setState(() {
      _guide = guide;
      if (guide != null && guide.isNotEmpty) {
        final isHod = guide == kHodGuideId;
        _boardUnseen = UnseenAggregates.anyOf([
          UnseenAggregates.studentCommentsRosterUnseen(guide, isHod),
          UnseenAggregates.bookCommitmentsRosterUnseen(guide, isHod),
        ]);
      }
    });
  }

  Future<void> _updateTokenForGuide() async {
    final guide =
        widget.selectedGuide ?? await UpdateTokenService().getSavedGuide();
    if (guide == null) {
      // Unreachable in practice as of Master Task, 2026-09-14: identity is
      // now resolved and persisted BEFORE `CurvedNavBar` (and therefore
      // this screen) is ever built (`main.dart`'s `SplashScreen` /
      // `Pages/GuideSignIn.dart`), so `widget.selectedGuide` is never null
      // and the `getSavedGuide()` fallback above never returns null either.
      // Left in place defensively rather than removed — `FolkGuideSelect
      // .dart` still exists (confirmed dead, kept per this project's
      // convention) to route to if this somehow still fires.
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => FolkGuideSelectionPage()),
        );
      }
      return;
    }

    try {
      await UpdateTokenService().saveSelectedGuide(guide);
      // Writes only if `guide` is really the signed-in guide.
      await updateAdminFcmToken(guide);
    } catch (e) {
      // ignore: avoid_print
      print("Failed to update FCM token: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final height = mq.size.height;

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        final guide = _guide;
        return Scaffold(
          backgroundColor: colorProvider.color,
          body: AnimatedOpacity(
            duration: const Duration(milliseconds: 600),
            opacity: _opacity,
            curve: Curves.easeIn,
            child: SafeArea(
              // Scroll-only fix — `SingleChildScrollView` around everything
              // is the ENTIRE overflow fix: if content is ever taller than
              // the screen, it scrolls instead of erroring, regardless of
              // tile sizing. Deliberately NOT paired with a
              // `ConstrainedBox(minHeight: ...)` + centred `Column` (an
              // earlier attempt) — that combination pushed the tiles far
              // below the app bar with a large gap on a real device, since
              // "centre within an estimated available height" can only ever
              // be an approximation of the real, per-device space. No
              // `LayoutBuilder` either (that caused a separate framework
              // crash — see the tile block's own comment below). With
              // neither, the Column below is exactly as tall as its
              // children need and starts at the very top — the tiles sit
              // immediately below the guide-name row, at their own tuned
              // size, on every screen; only screens too short for that
              // ever scroll.
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: width * 0.04, vertical: height * 0.02),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    SizedBox(height: height * 0.01),
                    // Restored: logged-in guide display + theme toggle — same
                    // wording, same conditional, same position as the old
                    // `DashboardScreen`.
                    if (guide != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Folk Guide: $guide",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                fontStyle: FontStyle.italic,
                                color: colorProvider.secondColor
                                    .withOpacity(0.8)),
                          ),
                          IconButton(
                              onPressed: () {
                                Provider.of<ColorProvider>(context,
                                        listen: false)
                                    .toggleColor();
                              },
                              icon: Icon(Icons.dark_mode,
                                  color: colorProvider.secondColor, size: 28)),
                        ],
                      ),
                    SizedBox(height: height * 0.04),
                    // Square-tile task — both tiles roughly square,
                    // substantially bigger than the old `height * 0.16`
                    // short rectangles.
                    //
                    // LayoutBuilder REMOVED (crash fix, see below) — sized
                    // from plain `MediaQuery`-derived `width`/`height`
                    // (already computed once at the top of `build()`)
                    // instead: `tileSize = min(width * 0.57, height *
                    // 0.25)`, tuned down from two earlier, larger passes
                    // (`(0.72, 0.34)`, then `(0.62, 0.30)`) after real-device
                    // overflow reports. This exact fraction doesn't have to
                    // be perfect, though: the `SingleChildScrollView` this
                    // whole column now sits in (see `SafeArea`'s own comment
                    // above) is the actual overflow fix — it scrolls instead
                    // of erroring if these numbers are ever still too big on
                    // some device. `gap` keeps scaling with `tileSize`
                    // (`* 0.09`) exactly as before.
                    //
                    // ---------------------------------------------------
                    // Why the LayoutBuilder had to go (real device crash)
                    // ---------------------------------------------------
                    // Real device red screen on tapping "Generate" in the
                    // Guide Calendar's "Add calendar text" sheet:
                    // `RenderObjectWithLayoutCallbackMixin.
                    // scheduleLayoutCallback`: `'debugNeedsLayout' is not
                    // true`, registered by
                    // `EditableTextState._onChangedLiveTextInputStatus` →
                    // `LiveTextInputStatusNotifier.update`. This is a known
                    // Flutter framework issue: `LayoutBuilder`'s own render
                    // object doc comment (`rendering/object.dart`,
                    // `RenderObjectWithLayoutCallbackMixin`) explains that
                    // an **offstage-but-still-mounted** `OverlayEntry` (its
                    // own example: "an Overlay may skip laying out an
                    // offstage OverlayEntry while keeping it in the tree")
                    // can leave a `LayoutBuilder`'s pending rebuild
                    // unresolved. `GuideCalendarPage` is PUSHED on top of
                    // THIS screen (`Navigator.push`, not a replace) — this
                    // screen, and its `LayoutBuilder`, stay mounted-but-
                    // offstage underneath the whole time the calendar's
                    // text field is focused and generating. A focused
                    // `EditableText` reacting to the platform's async
                    // Live-Text-input status (`setState` mid-frame) can
                    // then collide with this offstage `LayoutBuilder`'s own
                    // not-yet-consumed layout callback — exactly the
                    // "'debugNeedsLayout' is not true" contradiction. Fixed
                    // by removing the `LayoutBuilder` entirely rather than
                    // trying to time its rebuild around a route two screens
                    // away — no `LayoutBuilder` anywhere in this route's
                    // stack means this failure mode cannot occur here
                    // again, regardless of what's focused on the screen on
                    // top.
                    //
                    // `DashboardTile` itself is completely unchanged (Rule
                    // 1) — only how it's sized/arranged from outside
                    // changed, never its own internal styling. No longer
                    // wrapped in `Expanded` — that required a bounded-height
                    // Flex ancestor, which this Column no longer has now
                    // that it sits inside a scroll view (overflow fix).
                    guide == null
                        ? const Center(child: CircularProgressIndicator())
                        : Builder(builder: (_) {
                              // Plain local computation, not a widget — no
                              // `LayoutBuilder` needed. `context` for the two
                              // `onTap`s below is this Consumer builder's own
                              // (already in scope, already used by the rest
                              // of this screen — not tied to any sheet/modal
                              // lifecycle the way the calendar bug's context
                              // was).
                              final tileSize = width * 0.57 < height * 0.25
                                  ? width * 0.57
                                  : height * 0.25;
                              final gap = tileSize * 0.09;

                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Follow-up task, 2026-09-10 — "any of
                                    // my roster has an unseen student
                                    // comment or book commitment" (see
                                    // `_boardUnseen`'s own doc comment).
                                    StreamBuilder<bool>(
                                      stream: _boardUnseen,
                                      builder: (context, snap) => UnseenBadge(
                                        show: snap.data ?? false,
                                        child: SizedBox(
                                      width: tileSize,
                                      height: tileSize,
                                      child: DashboardTile(
                                        icon: Lottie.asset(
                                          'assets/emoji/boy.json',
                                          width: 55,
                                          height: 55,
                                        ),
                                        title: "FOLK Boys\nBoard",
                                        gradientColors: [
                                          Colors.deepPurpleAccent,
                                          Colors.lightBlue.shade300,
                                        ],
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => FolkBoysWorkspace(
                                                selectedGuide: guide),
                                          ),
                                        ),
                                      ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: gap),
                                    // Master Task 2026-09-10, Part 6 — a
                                    // mandatory event/text-block only the
                                    // HOD can post (`CalendarQueries.dart`'s
                                    // own `_assertCanMutate`); every other
                                    // guide should notice one landed since
                                    // they last opened their calendar. Only
                                    // `calendarEvents` is watched here —
                                    // the rarer `calendarTextBlocks` isn't
                                    // covered by this dot.
                                    UnseenFeatureBadge(
                                      featureKey: 'calendarEvents',
                                      latestQuery: (g) => FirebaseFirestore
                                          .instance
                                          .collection('calendarEvents')
                                          .where('scope',
                                              isEqualTo: kScopeMandatory)
                                          .snapshots(),
                                      child: SizedBox(
                                        width: tileSize,
                                        height: tileSize,
                                        child: DashboardTile(
                                          icon: const Icon(
                                            Icons.calendar_month,
                                            color: Colors.amberAccent,
                                            size: 55,
                                          ),
                                          title: "Calendar",
                                          gradientColors: [
                                            Colors.blue,
                                            Colors.deepPurple.shade400,
                                          ],
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  GuideCalendarPage(
                                                      selectedGuide: guide),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// DashboardTile — copied verbatim from Home/MainPage.dart (Phase 5, Part 4).
// See this file's header for why a temporary duplicate, not a shared move,
// is the correct reading of "repoint before Phase 6 deletes MainPage.dart".
// -----------------------------------------------------------------------------

class DashboardTile extends StatefulWidget {
  final String title;
  final Widget icon;
  final VoidCallback? onTap;
  final List<Color> gradientColors;

  const DashboardTile({
    required this.title,
    required this.icon,
    required this.gradientColors,
    this.onTap,
  });

  @override
  _DashboardTileState createState() => _DashboardTileState();
}

class _DashboardTileState extends State<DashboardTile> {
  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => isPressed = true),
      onTapUp: (_) => setState(() => isPressed = false),
      onTapCancel: () => setState(() => isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: widget.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: isPressed ? 6 : 14,
              offset: Offset(0, isPressed ? 3 : 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 45,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.6),
                      Colors.white.withOpacity(0.05),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  widget.icon,
                  const SizedBox(height: 12),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
