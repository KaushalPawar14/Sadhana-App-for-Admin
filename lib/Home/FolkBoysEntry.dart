import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Pages/GoalHomePage.dart';
import '../Pages/GuideCalendarPage.dart';
import '../Pages/GuideSignIn.dart';
import '../Pages/WeeklyPlanning.dart';
import '../Services/UpdateFCM.dart';
import '../Services/UpdateToken.dart';
import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/CalendarQueries.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/GoalMetrics.dart';
import '../utils/GuideLogout.dart';
import '../utils/HomeData.dart';
import '../utils/WeekSummary.dart';
import '../utils/PlanningQueries.dart';
import '../utils/UnseenAggregates.dart';
import '../utils/UnseenDot.dart';
import '../widgets/GuideAppearanceSheet.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideGhost.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import 'FolkBoysWorkspace.dart';

/// The Home tab: the guide's dashboard.
///
/// ---------------------------------------------------------------------------
/// What is on it, and where every number comes from
/// ---------------------------------------------------------------------------
/// Nothing here is new data. Each piece reads a source the app already reads on
/// another screen, scoped to the signed-in admin exactly as that screen is:
///
///  * Hero "Targets"    — `compoundTargetsStream(guideId)` (the stream behind
///                        This Week's "Your targets this week" and the Targets
///                        screen): active targets that have a plan.
///  * Hero "Follow-ups" — `scopedInteractionLogsStream()` (This Week's
///                        "Follow-ups due"), filtered by `followUpsDue`.
///  * Hero "Overdue"    — `scopedAssociationsStream()` (This Week's "Overdue
///                        meetings"), filtered by `overdueAssociations`.
///  * Target cards      — the same `compoundTargetsStream` (phase x of y).
///  * Board tile count  — `StudentScope.current().studentsStream()` (the roster
///                        the board lists, role-scoped).
///  * Calendar tile     — `visibleEventsFor(guideId)` (This Week's calendar
///                        context and the Calendar screen itself).
///
/// The guide resolution and FCM re-registration that used to run on the FOLK
/// Boys tab still run here, on tab entry (the tab is built when first opened).
class FolkBoysEntryScreen extends StatefulWidget {
  final String? selectedGuide;

  const FolkBoysEntryScreen({super.key, this.selectedGuide});

  @override
  State<FolkBoysEntryScreen> createState() => _FolkBoysEntryScreenState();
}

class _FolkBoysEntryScreenState extends State<FolkBoysEntryScreen> {
  String? _guide;

  /// "Any of my roster has an unseen student comment or book commitment" — the
  /// Board tile's dot (same roster helpers the board itself uses). Built once,
  /// never in `build()`.
  Stream<bool>? _boardUnseen;

  List<CompoundTarget>? _targets;
  List<FollowUpItem>? _followUps;
  List<OverdueItem>? _overdue;
  int? _studentCount;
  List<CalendarEvent>? _events;
  final List<StreamSubscription<Object?>> _subs = [];

  /// A source that failed (shown as a frozen ghost with Retry, never a blank).
  bool _targetsFailed = false;
  bool _followUpsFailed = false;
  bool _overdueFailed = false;
  bool _countFailed = false;
  bool _eventsFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTokenForGuide();
      _fetchSavedGuide();
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _fetchSavedGuide() async {
    final guide =
        widget.selectedGuide ?? await UpdateTokenService().getSavedGuide();
    if (!mounted) return;
    setState(() {
      _guide = guide;
      if (guide != null && guide.isNotEmpty) {
        final isHod = AdminProfileProvider.viewerIsHod;
        _boardUnseen = UnseenAggregates.anyOf([
          UnseenAggregates.studentCommentsRosterUnseen(guide, isHod),
          UnseenAggregates.bookCommitmentsRosterUnseen(guide, isHod),
          UnseenAggregates.suggestionsReadyRosterUnseen(guide, isHod),
        ]);
      }
    });
    if (guide != null && guide.isNotEmpty) _listen(guide);
  }

  /// Starts the dashboard's own listeners, once.
  void _listen(String guide) {
    if (_subs.isNotEmpty) return;
    final week = currentWeekRange();
    final data = HomeData.instance;
    _subs.add(data.targets(guide).listen((t) {
      if (mounted) setState(() => _targets = t);
    }, onError: (_) {
      if (mounted) setState(() => _targetsFailed = true);
    }));
    _subs.add(data.followUps(week).listen((f) {
      if (mounted) setState(() => _followUps = f);
    }, onError: (_) {
      if (mounted) setState(() => _followUpsFailed = true);
    }));
    _subs.add(data.overdue().listen((o) {
      if (mounted) setState(() => _overdue = o);
    }, onError: (_) {
      if (mounted) setState(() => _overdueFailed = true);
    }));
    _subs.add(data.studentCount().listen((n) {
      if (mounted) setState(() => _studentCount = n);
    }, onError: (_) {
      if (mounted) setState(() => _countFailed = true);
    }));
    data.events(guide).then((e) {
      if (mounted) setState(() => _events = e);
    }).catchError((_) {
      if (mounted) setState(() => _eventsFailed = true);
    });
  }

  /// Retry after a failed source: the same listeners, started again.
  void _retry() {
    final guide = _guide;
    if (guide == null || guide.isEmpty) return;
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    setState(() {
      _targetsFailed = _followUpsFailed = _overdueFailed = _countFailed = _eventsFailed = false;
    });
    _listen(guide);
  }

  Future<void> _updateTokenForGuide() async {
    final guide =
        widget.selectedGuide ?? await UpdateTokenService().getSavedGuide();
    if (guide == null) {
      // Unreachable in practice: identity is resolved and persisted BEFORE the
      // shell is built (`main.dart`'s SplashScreen / `GuideSignInPage`). Left in
      // place defensively: if it ever fires, go to the sign-in page.
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GuideSignInPage()),
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

  // ---------------------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------------------

  String get _weekLabel {
    final w = currentWeekRange();
    final last = w.end.subtract(const Duration(days: 1));
    if (w.start.month == last.month) {
      return '${DateFormat('dd').format(w.start)} – ${DateFormat('dd MMM').format(last)}';
    }
    return '${DateFormat('dd MMM').format(w.start)} – ${DateFormat('dd MMM').format(last)}';
  }

  List<CompoundTarget> get _activeTargets => [
        for (final t in _targets ?? const <CompoundTarget>[])
          if (t.isActive && t.totalPhases > 0) t,
      ];

  GuidePastel _pastelFor(CompoundTarget t) => switch (t.metric) {
        kMetricChanting => GuidePastel.sage,
        kMetricBooks => GuidePastel.sand,
        _ => GuidePastel.mauve,
      };

  /// A target card: two single-line rows (name + phase, then the goal) and the
  /// progress bar, so its height is the same for every target (and for its ghost).
  Widget _targetBox({
    required GuidePastel pastel,
    required String title,
    required String goal,
    required String phase,
    required double fraction,
  }) {
    final text = context.gText;
    return GuidePastelBox(
      pastel: pastel,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.onPastelBody.copyWith(fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Text(phase, style: text.onPastelSmall),
            ],
          ),
          const SizedBox(height: 3),
          Text(goal, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.onPastelSmall),
          const SizedBox(height: 10),
          GuideProgressBar(value: fraction, onPastel: true),
        ],
      ),
    );
  }

  Widget _targetCard(CompoundTarget t, int index) {
    final metric = t.metricInfo;
    final fraction = t.totalPhases == 0 ? 0.0 : t.currentPhase / t.totalPhases;
    final guide = _guide ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GuideEntry(
        index: 3 + index,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => GoalHomePage(guideId: guide)),
          ),
          child: _targetBox(
            pastel: _pastelFor(t),
            title: metric?.label ?? t.metric,
            goal: "${t.studentCountGoal} students at ${t.perStudentValueGoal} "
                    "${metric?.unit ?? ''}"
                .trim(),
            phase: "Phase ${t.currentPhase} of ${t.totalPhases}",
            fraction: fraction,
          ),
        ),
      ),
    );
  }

  /// The ghost of one target card: the real card laid out invisibly, then a soft fill.
  Widget _targetGhost() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: GuideGhostOf(
          radius: GuideShape.tileRadius,
          placeholder: _targetBox(
            pastel: GuidePastel.sand,
            title: 'Chanting rounds',
            goal: '20 students at 16 rounds',
            phase: 'Phase 1 of 4',
            fraction: 0,
          ),
        ),
      );

  String _boardSubtitle() {
    final n = _studentCount;
    if (n == null) return '';
    final p = AdminProfileProvider.current;
    final noun = p == null || p.isHod
        ? (n == 1 ? 'student' : 'students')
        : (p.isFemaleEnabler ? (n == 1 ? 'girl' : 'girls') : (n == 1 ? 'boy' : 'boys'));
    return '$n $noun';
  }

  String _calendarSubtitle() {
    final events = _events;
    if (events == null) return '';
    final now = eventsHappeningNow(events);
    if (now.isNotEmpty) {
      final more = now.length - 1;
      return more > 0 ? '${now.first.title} +$more' : now.first.title;
    }
    final soon = eventsComingUp(events);
    if (soon.isNotEmpty) {
      return '${soon.first.title} · ${DateFormat('dd MMM').format(soon.first.eventDate)}';
    }
    return 'Nothing due today';
  }

  // The three areas of Home that wait for data.
  GuideLoad get _heroState {
    if (_targetsFailed || _followUpsFailed || _overdueFailed) return GuideLoad.error;
    if (_targets == null || _followUps == null || _overdue == null) return GuideLoad.loading;
    return GuideLoad.content;
  }

  GuideLoad get _targetsState {
    if (_targetsFailed) return GuideLoad.error;
    if (_targets == null) return GuideLoad.loading;
    return _activeTargets.isEmpty ? GuideLoad.empty : GuideLoad.content;
  }

  /// The two tiles: ghosts until the board count and the calendar load. If a source
  /// fails the tiles still appear (without a subtitle): they are the way into the
  /// Board and the Calendar and must not be lost to a failed count.
  bool get _tilesReady =>
      _guide != null && ((_studentCount != null || _countFailed) && (_events != null || _eventsFailed));

  Widget _heroCard(List<CompoundTarget> active, {bool placeholder = false}) {
    const dash = '–';
    return GuideHeroCard(
      label: 'This week',
      trailing: _weekLabel,
      onTap: placeholder
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WeeklyPlanningPage()),
              ),
      stats: [
        GuideHeroStat(placeholder ? dash : '${active.length}', 'Targets'),
        GuideHeroStat(placeholder ? dash : '${_followUps!.length}', 'Follow-ups'),
        GuideHeroStat(placeholder ? dash : '${_overdue!.length}', 'Overdue'),
      ],
    );
  }

  /// One of the two square tiles. [side] is the square's side: the tile is at least that
  /// tall, and both tiles of the pair grow together if the text needs more room.
  Widget _tile(String guide, {required bool board, required double side, bool placeholder = false}) {
    if (board) {
      final tile = GuideGradientTile(
        pastel: GuidePastel.slate,
        icon: Icons.groups_2_outlined,
        title: 'FOLK Boys Board',
        subtitle: placeholder ? '0 students' : _boardSubtitle(),
        minHeight: side,
        large: true,
        showChevron: false,
        onTap: placeholder
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FolkBoysWorkspace(selectedGuide: guide)),
                ),
      );
      if (placeholder) return tile;
      // The dot counts what this admin can open from the board: a book commitment set by a
      // guide (a dot on that student's card), a comment someone else wrote (a dot on that
      // card's Comments icon) or new suggestions made by the server (a dot on the card's profile
      // icon), for students on this admin's board only.
      return StreamBuilder<bool>(
        stream: _boardUnseen,
        builder: (context, snap) => UnseenBadge(
          show: snap.data ?? false,
          offset: const Offset(10, 10),
          fillParent: true,
          child: tile,
        ),
      );
    }
    final tile = GuideGradientTile(
      pastel: GuidePastel.mauve,
      icon: Icons.calendar_month_outlined,
      title: 'Calendar',
      subtitle: placeholder ? 'Nothing due today' : _calendarSubtitle(),
      minHeight: side,
      large: true,
      showChevron: false,
      onTap: placeholder
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GuideCalendarPage(selectedGuide: guide)),
              ),
    );
    // A mandatory event only the HOD can post: every other guide should notice one
    // landed since they last opened their calendar (`calendarEvents` only).
    return placeholder ? tile : HomeData.instance.calendarBadge(child: tile);
  }

  Widget _tilesRow(String guide) => GuideSquarePair(
        left: (side) => _tile(guide, board: true, side: side),
        right: (side) => _tile(guide, board: false, side: side),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final guide = _guide;
    final profile = AdminProfileProvider.current;
    final active = _activeTargets;

    return ListView(
      padding: EdgeInsets.only(bottom: GuideSpace.navClearanceOf(context)),
      children: [
        GuideTopBar(
          showBack: false,
          titleWidget: GuideLabel(DateFormat('EEEE, d MMMM').format(DateTime.now())),
          actions: [
            GuideRoundButton(
              icon: context.g.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              tooltip: 'Appearance',
              onPressed: () => showGuideAppearanceSheet(context),
            ),
            GuideRoundButton(
              icon: Icons.logout_rounded,
              tooltip: 'Log out',
              onPressed: () => confirmAndLogout(context),
            ),
          ],
        ),
        GuideEntry(
          index: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 16, GuideSpace.pagePadding, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hare Krishna,', style: t.small.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  (profile?.displayName.isNotEmpty ?? false) ? profile!.displayName : 'FOLK Guide',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.greeting,
                ),
                if (profile != null) ...[
                  const SizedBox(height: 4),
                  Text(profile.role.label, style: t.small),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        GuideEntry(
          index: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GuideSpace.pagePadding),
            child: GuideStateView(
              state: _heroState,
              ghost: GuideGhostOf(
                radius: GuideShape.heroRadius,
                placeholder: _heroCard(const [], placeholder: true),
              ),
              content: _heroState == GuideLoad.content ? _heroCard(active) : const SizedBox.shrink(),
              errorMessage: 'Could not load this week. Check your connection and try again.',
              onRetry: _retry,
            ),
          ),
        ),
        const GuideEntry(
          index: 2,
          child: Padding(
            padding: EdgeInsets.fromLTRB(GuideSpace.pagePadding, 22, GuideSpace.pagePadding, 0),
            child: GuideSectionTitle('Targets'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GuideSpace.pagePadding),
          child: GuideStateView(
            state: _targetsState,
            ghost: Column(children: [_targetGhost(), _targetGhost()]),
            content: Column(
              children: [
                for (var i = 0; i < active.length; i++) _targetCard(active[i], i),
              ],
            ),
            emptyMessage: 'No active targets yet. Create your first target to see it here.',
            emptyAction: guide == null
                ? null
                : GuideEmptyAction(
                    'Open targets',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GoalHomePage(guideId: guide)),
                    ),
                    icon: Icons.track_changes_outlined,
                  ),
            errorMessage: 'Could not load your targets. Check your connection and try again.',
            onRetry: _retry,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 0),
          child: GuideEntry(
            index: 4,
            child: GuideCrossFade(
              child: _tilesReady
                  ? KeyedSubtree(key: const ValueKey('tiles'), child: _tilesRow(guide!))
                  : KeyedSubtree(
                      key: const ValueKey('tiles-ghost'),
                      child: GuideGhostArea(
                        child: GuideSquarePair(
                          left: (side) => GuideGhostOf(
                            radius: GuideShape.tileRadius,
                            placeholder: _tile('', board: true, side: side, placeholder: true),
                          ),
                          right: (side) => GuideGhostOf(
                            radius: GuideShape.tileRadius,
                            placeholder: _tile('', board: false, side: side, placeholder: true),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
