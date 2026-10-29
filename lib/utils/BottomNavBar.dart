import 'package:flutter/material.dart';
import 'Responsive.dart';
import '../widgets/GuideSideNav.dart';
import '../Pages/AgentPage.dart';
import '../agent/AgentOverlay.dart';
import 'package:flutter/services.dart';
import 'package:folk_guide_app/Home/FolkBoysEntry.dart';
import 'package:folk_guide_app/Pages/BoysDetails.dart';
import 'package:folk_guide_app/Pages/Competition.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/UnseenDot.dart';

import '../theme/GuideTheme.dart';
import '../widgets/GuideNav.dart';
import '../widgets/GuideSurface.dart';

/// The app shell: the three tabs behind the floating pill navigation.
///
///   Home      — the dashboard (was the "FOLK Boys" tab: Board + Calendar tiles)
///   Analysis  — ABCDE, Week planning, Priority students, Guide targets
///                (was the "Folk analysis" tab)
///   Tasks     — Add student, Submissions, Add admin, Notifications
///                (was the "Other tasks" tab)
///
/// Every tab is built the first time it is opened and then kept alive
/// (IndexedStack), so switching tabs — or switching the theme — never loses
/// a tab's scroll position or state.
///
/// The class keeps its old name (`CurvedNavBar`) because the splash screen and
/// the sign-in page construct it by that name.
/// Lets something outside the shell (the AI assistant's "Take me there") switch the bottom tab.
///
/// Set [requested] to 0 (Home), 1 (Analysis) or 2 (Tasks); the shell shows that tab and clears it.
class GuideTabRequest {
  GuideTabRequest._();
  static final ValueNotifier<int?> requested = ValueNotifier<int?>(null);
  static void show(int tab) => requested.value = tab;
}

class CurvedNavBar extends StatefulWidget {
  final String Guidename;
  const CurvedNavBar(this.Guidename, {super.key});
  @override
  State<CurvedNavBar> createState() => _CurvedNavBarState();
}

class _CurvedNavBarState extends State<CurvedNavBar> {
  /// Tab indexes.
  static const int tabHome = 0;
  static const int tabAnalysis = 1;

  int currentIdx = tabHome;
  late String adminName = widget.Guidename;

  /// Which tabs have been opened (and are therefore built and kept alive).
  final Set<int> _built = {tabHome};

  /// One aggregate "is there anything unseen under this tab" stream per tab that
  /// hosts content with unseen state (Analysis also carries a HOD's Assistant log). Built exactly once, in
  /// `initState()`, never in `build()`; every per-feature stream is shared via
  /// `utils/UnseenAggregates.dart` — the SAME functions back the tile dots on the
  /// tab pages, so the nav bar and the tiles can never disagree.
  late final Stream<bool> _analysisUnseen;
  late final Stream<bool> _homeUnseen;
  late final Stream<bool> _tasksUnseen;

  @override
  void initState() {
    super.initState();
    _buildUnseenStreams();
    GuideTabRequest.requested.addListener(_onTabRequest);
  }

  @override
  void dispose() {
    GuideTabRequest.requested.removeListener(_onTabRequest);
    super.dispose();
  }

  void _onTabRequest() {
    final tab = GuideTabRequest.requested.value;
    if (tab == null) return;
    GuideTabRequest.requested.value = null;
    if (!mounted || tab < 0 || tab > 2) return;
    setState(() {
      currentIdx = tab;
      _built.add(tab);
    });
  }

  static Stream<bool> _both(Stream<bool> s) => s.asBroadcastStream(onCancel: (_) {});

  void _buildUnseenStreams() {
    final guide = adminName;
    final isHod = AdminProfileProvider.viewerIsHod;

    // Was the "Folk analysis" tab's dot.
    // The phone layout and the computer layout both show these dots; a window can be resized across the breakpoint, so each stream may be
    // listened to again by the other layout (broadcast, and the source stays open).
    _analysisUnseen = _both(UnseenAggregates.anyOf([
      UnseenAggregates.associationsUnseen(guide, isHod),
      UnseenAggregates.expeditionReflectionsUnseen(guide, isHod),
      UnseenAggregates.serviceAssignmentsUnseen(guide, isHod),
      UnseenAggregates.flaggedMessagesUnseen(guide, isHod),
      UnseenAggregates.studentDoubtsUnseen(guide, isHod),
      UnseenAggregates.goalProposalsUnseen(guide),
      // The Assistant log (HOD only) lives in Analysis now: its new entries light the Analysis tab, the card and the entries.
      if (isHod) UnseenAggregates.assistantLogUnseen(AdminProfileProvider.current?.id ?? ''),
    ]));

    // The Tasks tab no longer hosts anything with unseen state.
    _tasksUnseen = _both(Stream.value(false));

    // Was the "FOLK Boys" tab's dot.
    _homeUnseen = _both(UnseenAggregates.anyOf([
      UnseenAggregates.calendarEventsUnseen(guide),
      UnseenAggregates.studentCommentsRosterUnseen(guide, isHod),
      UnseenAggregates.bookCommitmentsRosterUnseen(guide, isHod),
    ]));
  }

  Widget _pageFor(int index) {
    switch (index) {
      case tabHome:
        return FolkBoysEntryScreen(selectedGuide: adminName);
      case tabAnalysis:
        return CompetitionPage();
      default: // tab 2 — Tasks
        return const AdminControlPage();
    }
  }

  /// A dot for a nav item, shown only while [unseen] says so.
  Widget _dot(Stream<bool> unseen) => StreamBuilder<bool>(
        stream: unseen,
        builder: (context, snap) =>
            (snap.data ?? false) ? const UnseenDot() : const SizedBox.shrink(),
      );

  /// THE COMPUTER LAYOUT (a window at least 900 dp wide): the side navigation, the page, and — when asked for — the assistant as a panel on the
  /// right. The tabs and what they hold are exactly the phone's; only the arrangement changes.
  Widget _desktop(BuildContext context) {
    final g = context.g;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: g.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: g.pageBackground,
        body: GuidePageBackground(
          child: ValueListenableBuilder<bool>(
            valueListenable: AgentSession.panelOpen,
            builder: (context, assistantOpen, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GuideSideNav(
                  index: currentIdx,
                  onTap: (i) => setState(() {
                    currentIdx = i;
                    _built.add(i);
                  }),
                  items: [
                    GuideNavItem(icon: Icons.home_outlined, label: 'Home', badge: _dot(_homeUnseen)),
                    GuideNavItem(icon: Icons.grid_view_rounded, label: 'Analysis', badge: _dot(_analysisUnseen)),
                    GuideNavItem(icon: Icons.check_box_outlined, label: 'Tasks', badge: _dot(_tasksUnseen)),
                  ],
                  assistant: const GuideNavItem(icon: Icons.auto_awesome_outlined, label: 'Assistant'),
                  assistantOpen: assistantOpen,
                  onAssistant: () => AgentSession.panelOpen.value = !assistantOpen,
                ),
                Expanded(
                  child: IndexedStack(
                    index: currentIdx,
                    children: [
                      for (var i = 0; i < 3; i++)
                        _built.contains(i)
                            ? TickerMode(enabled: i == currentIdx, child: i == tabHome ? _pageFor(i) : ContentWidth(child: _pageFor(i)))
                            : const SizedBox.shrink(),
                    ],
                  ),
                ),
                if (assistantOpen)
                  Container(
                    key: const ValueKey('assistant-panel'),
                    width: kAssistantPanelWidth,
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: g.mutedText.withValues(alpha: .18)))),
                    child: AgentPage(onClose: () => AgentSession.panelOpen.value = false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    if (context.isDesktop) return _desktop(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: g.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: g.pageBackground,
        body: GuidePageBackground(
          child: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: currentIdx,
                  children: [
                    for (var i = 0; i < 3; i++)
                      // A tab that is not showing runs no tickers (no breathing ghosts).
                      _built.contains(i)
                          ? TickerMode(enabled: i == currentIdx, child: _pageFor(i))
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: GuideFloatingNav(
                  index: currentIdx,
                  onTap: (i) => setState(() {
                    currentIdx = i;
                    _built.add(i);
                  }),
                  items: [
                    GuideNavItem(
                        icon: Icons.home_outlined,
                        label: 'Home',
                        badge: _dot(_homeUnseen)),
                    GuideNavItem(
                        icon: Icons.grid_view_rounded,
                        label: 'Analysis',
                        badge: _dot(_analysisUnseen)),
                    GuideNavItem(
                        icon: Icons.check_box_outlined,
                        label: 'Tasks',
                        badge: _dot(_tasksUnseen)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
