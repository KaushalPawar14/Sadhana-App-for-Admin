import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/Responsive.dart';
import 'package:intl/intl.dart';

import '../Pages/CompoundGoalProgressPage.dart';
import '../Pages/GoalSetup.dart';
import '../widgets/GuideButtons.dart';
import '../Pages/GuideCalendarPage.dart';
import '../Pages/GuideSignIn.dart';
import '../Pages/PlanPage.dart';
import '../Services/UpdateFCM.dart';
import '../Services/UpdateToken.dart';
import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../Services/HierarchyApi.dart';
import '../utils/CalendarQueries.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/GoalMetrics.dart';
import '../utils/GuideLogout.dart';
import '../utils/HomeData.dart';
import '../utils/PlanData.dart';
import '../utils/PlanToday.dart';
import '../utils/PlanningQueries.dart';
import '../utils/UnseenAggregates.dart';
import '../utils/UnseenDot.dart';
import '../widgets/GuideAppearanceSheet.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideGhost.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideSurface.dart';
import '../theme/GuideTypography.dart';
import '../widgets/GuideTiles.dart';
import '../widgets/PressScale.dart';
import 'FolkBoysWorkspace.dart';

/// The Home tab: the guide's dashboard.
///
/// ---------------------------------------------------------------------------
/// What is on it, and where every number comes from
/// ---------------------------------------------------------------------------
/// Nothing here is new data. Each piece reads a source the app already reads on
/// another screen, scoped to the signed-in admin exactly as that screen is:
///
///  * THIS WEEK (navy)  — "Targets": `compoundTargetsStream(guideId)` (active
///                        targets that have a plan); "To contact" and "Done": the
///                        week's progress in the guide's plan. Opens the Plan
///                        page on THIS WEEK.
///  * TODAY'S TASKS     — three live counts from the same plan (`guidePlans/{id}`,
///                        `PlanCounts`): Follow-ups (interactions students need),
///                        Target tasks (made by the guide's own targets) and Other
///                        tasks. The card, or any one count, opens the Plan page
///                        on TODAY at that section.
///  * Target cards      — the same `compoundTargetsStream` (phase x of y).
///  * Board tile count  — `StudentScope.current().studentsStream()` (the roster
///                        the board lists, role-scoped).
///  * Calendar tile     — `visibleEventsFor(guideId)` (This Week's calendar
///                        context and the Calendar screen itself).
///
/// The guide resolution and FCM re-registration that used to run on the FOLK
/// Boys tab still run here, on tab entry (the tab is built when first opened).
/// The day the app last told the server it was opened (once a day).
String? _openedDay;

class FolkBoysEntryScreen extends StatefulWidget {
  /// For tests: forget that today's first open was already reported.
  static void forgetOpenedDay() => _openedDay = null;

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
  PlanDoc? _plan;
  bool _planLoaded = false;

  /// What is NEW (not seen yet: since he last left the Plan page): the badge on both plan widgets; a tap lists them.
  NewChanges _pending = NewChanges.none;
  String _planOwner = '';
  int? _studentCount;
  List<CalendarEvent>? _events;
  final List<StreamSubscription<Object?>> _subs = [];

  /// A source that failed (shown as a frozen ghost with Retry, never a blank).
  bool _targetsFailed = false;
  bool _planFailed = false;
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
        ]);
      }
    });
    if (guide != null && guide.isNotEmpty) _listen(guide);
  }

  /// Starts the dashboard's own listeners, once.
  void _listen(String guide) {
    if (_subs.isNotEmpty) return;
    final data = HomeData.instance;
    // the plan widgets are the signed-in admin's OWN (a HOD's too: his own targets, tasks and students; the guides' summaries are on the Plan page)
    final me = AdminProfileProvider.current;
    final planOwner = me != null && me.isHod && me.id.isNotEmpty ? me.id : guide;
    _planOwner = planOwner;
    _openedTheApp(planOwner);
    _subs.add(data.targets(guide).listen((t) {
      if (mounted) setState(() => _targets = t);
    }, onError: (_) {
      if (mounted) setState(() => _targetsFailed = true);
    }));
    _subs.add(PlanData.instance.newChanges(planOwner).listen((p) {
      if (mounted) setState(() => _pending = p);
    }, onError: (_) {}));
    // the plan the server keeps for this guide: live, so the counts follow every tick and every new item
    _subs.add(PlanData.instance.plan(planOwner).listen((p) {
      if (mounted) {
        setState(() {
          _plan = p;
          _planLoaded = true;
          _planFailed = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _planFailed = true);
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

  /// The first open of the day tells the server, which then writes the AI questions for Today's students (once a day; see HierarchyApi.openPlan).
  void _openedTheApp(String planOwner) {
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    if (_openedDay == today || planOwner.isEmpty) return;
    _openedDay = today;
    try {
      HierarchyApi.instance.openPlan();
    } catch (_) {
      // no server to tell (a test, or signed out): nothing to do
    }
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
      _targetsFailed = _planFailed = _countFailed = _eventsFailed = false;
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

  /// The targets this guide may have (chanting, book reading and, for everyone but a Female Enabler, FOLK residents), and which of
  /// them are already set (an active one of that type).
  List<String> get _targetsMissing {
    final me = AdminProfileProvider.current;
    final wanted = me == null ? const [kMetricChanting, kMetricBooks] : compoundMetricsFor(me);
    final all = _targets ?? const <CompoundTarget>[];
    return [for (final m in wanted) if (!all.any((t) => t.isActive && t.metric == m)) m];
  }

  static const _metricWords = {
    kMetricChanting: 'chanting',
    kMetricBooks: 'book-reading',
    kMetricFolk: 'FOLK-residents',
  };

  /// "16 rounds by 31 Dec": what a set target says on its tile.
  static String _targetWords(CompoundTarget x) {
    final by = x.endDate == null ? '' : ' by ${DateFormat('d MMM').format(x.endDate!)}';
    switch (x.metric) {
      case kMetricChanting:
        return '${x.perStudentValueGoal} rounds$by';
      case kMetricBooks:
        return '${x.perStudentValueGoal} book${x.perStudentValueGoal == 1 ? '' : 's'}$by';
      default:
        return '${x.studentCountGoal} FOLK resident${x.studentCountGoal == 1 ? '' : 's'}$by';
    }
  }

  static const _tileLook = {
    kMetricChanting: 'Chanting',
    kMetricBooks: 'Reading',
    kMetricFolk: 'FOLK',
  };

  /// THE TARGETS CARD: one rectangle with a small coloured tile for each target the admin may have (CHANTING, READING, and FOLK residents: not for a
  /// Female Enabler, it is for boys), each with a curvy tick when it is set (and what it says: "16 rounds by 31 Dec") or a curvy cross and "Not
  /// set". A tile opens that target, or the create flow when it is not set. Underneath: "Set a target" (the first missing one) while any is
  /// missing, "View targets" (the targets in the plan) when all are set.
  Widget _targetsCard({bool placeholder = false}) {
    final t = context.gText;
    final me = AdminProfileProvider.current;
    final wanted = me == null ? const [kMetricChanting, kMetricBooks] : compoundMetricsFor(me);
    final all = _targets ?? const <CompoundTarget>[];
    CompoundTarget? setFor(String m) {
      for (final x in all) {
        if (x.isActive && x.metric == m) return x;
      }
      return null;
    }

    final missing = placeholder ? List<String>.of(wanted) : _targetsMissing;
    final guide = _guide;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // narrow (a small phone, or large text): the tiles stack, one under the other, so no word is ever cut
    final stacked = scale > 1.25 || MediaQuery.sizeOf(context).width < 340;

    Widget tile(String metric) {
      final look = _tileLook[metric]!;
      final x = placeholder ? null : setFor(metric);
      // a target whose end date has been reached waits for the guide: delete it, or extend it (in Today)
      final end = x?.endDate;
      final over = end != null && !DateTime(end.year, end.month, end.day).isAfter(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));
      final words = over ? 'Ended — choose' : x != null ? _targetWords(x) : 'Not set';
      final body = _raisedTile(
        child: stacked
            ? Row(
                children: [
                  Expanded(child: _tileText(look, words, t)),
                  const SizedBox(width: 10),
                  GuideTargetBadge(key: ValueKey('home-target-badge-$metric'), isSet: x != null),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(alignment: Alignment.centerRight, child: GuideTargetBadge(key: ValueKey('home-target-badge-$metric'), isSet: x != null)),
                  const SizedBox(height: 4),
                  _tileText(look, words, t),
                ],
              ),
      );
      return Semantics(
        button: !placeholder,
        label: '${look}: $words',
        child: PressScale(
          enabled: !placeholder && guide != null,
          child: GestureDetector(
            key: ValueKey('home-target-$metric'),
            behavior: HitTestBehavior.opaque,
            onTap: placeholder || guide == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => x != null ? CompoundGoalProgressPage(guideId: x.guideId, targetId: x.targetId) : CompoundGoalSetupPage(guideId: guide, initialMetric: metric)),
                    ),
            child: ExcludeSemantics(child: body),
          ),
        ),
      );
    }

    final tiles = [for (final m in wanted) tile(m)];
    return GuideCard(
      key: const ValueKey('home-targets-card'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your targets', style: t.cardTitleSmall),
          const SizedBox(height: 10),
          if (stacked)
            Column(children: [for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(height: 8), tiles[i]]])
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: tiles[i])]],
              ),
            ),
          const SizedBox(height: 12),
          if (missing.isNotEmpty)
            GuideSecondaryButton(
              key: const ValueKey('home-set-target'),
              label: 'Set a target',
              onPressed: placeholder || guide == null
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(builder: (_) => CompoundGoalSetupPage(guideId: guide, initialMetric: missing.first))),
            )
          else
            GuideSecondaryButton(
              key: const ValueKey('home-view-targets'),
              label: 'View targets',
              onPressed: placeholder ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanPage(initialWeek: true))),
            ),
        ],
      ),
    );
  }

  /// A plain themed tile: off-white (light) or soft grey (dark), a gentle shade and a raised ("bumpy") edge: a soft shadow below and a thin highlight
  /// above. The same on a phone and on the website.
  Widget _raisedTile({required Widget child}) {
    final g = context.g;
    final dark = g.isDark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: dark ? GuideColors.targetTileDark : GuideColors.targetTileLight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: g.border),
        boxShadow: [
          BoxShadow(color: dark ? GuideColors.targetTileShadowDark : GuideColors.targetTileShadowLight, blurRadius: 8, offset: const Offset(0, 3)),
          BoxShadow(color: dark ? GuideColors.targetTileHighlightDark : GuideColors.targetTileHighlightLight, blurRadius: 1, offset: const Offset(0, -1)),
        ],
      ),
      child: child,
    );
  }

  /// A tile's words: the name, and what it says (two lines are always reserved, so the tiles are the same height).
  Widget _tileText(String name, String words, GuideTypography t) {
    final g = context.g;
    final small = t.small.copyWith(color: g.text);
    final line = MediaQuery.textScalerOf(context).scale((small.fontSize ?? 13) * 1.3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.cardTitleSmall.copyWith(color: g.text)),
        const SizedBox(height: 3),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: 2 * line),
          child: Text(words, maxLines: 3, overflow: TextOverflow.ellipsis, style: small.copyWith(height: 1.3)),
        ),
      ],
    );
  }

  /// "chanting, book-reading and FOLK-residents".
  static String _joinWords(List<String> w) => w.length <= 1 ? w.join() : '${w.sublist(0, w.length - 1).join(', ')} and ${w.last}';

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

  // The areas of Home that wait for data.
  GuideLoad get _heroState {
    if (_targetsFailed || _planFailed) return GuideLoad.error;
    if (_targets == null || !_planLoaded) return GuideLoad.loading;
    return GuideLoad.content;
  }

  GuideLoad get _todayState {
    if (_planFailed) return GuideLoad.error;
    return _planLoaded ? GuideLoad.content : GuideLoad.loading;
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

  /// THIS WEEK (navy): opens the Plan page on its This week tab (the full plan, target progress, phases and what to do this week). Every count is
  /// always there: a zero is "0", never a missing number.
  Widget _heroCard(List<CompoundTarget> active, {bool placeholder = false}) {
    final progress = placeholder ? null : _plan?.progress;
    String n(int v) => placeholder ? '–' : '$v';
    return GuideHeroCard(
      key: const ValueKey('home-this-week'),
      label: 'This week',
      trailing: _weekLabel,
      onTap: placeholder
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlanPage(initialWeek: true)),
              ),
      footer: placeholder || _pending.count == 0 ? null : _pendingLine('week'),
      stats: [
        GuideHeroStat(n(active.length), 'Targets', valueKey: const ValueKey('home-week-targets-count')),
        GuideHeroStat(n(progress?.left ?? 0), 'To contact', valueKey: const ValueKey('home-week-left-count')),
        GuideHeroStat(n(progress?.done ?? 0), 'Done', valueKey: const ValueKey('home-week-done-count')),
      ],
    );
  }

  /// The two plan widgets stay compact on a wide window (left-aligned, like the tiles); a phone gets the whole width. Both fill exactly the same
  /// width, so THIS WEEK and TODAY'S TASKS are the same size.
  Widget _compact(Widget child) => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kHomeCardMaxWidth), child: SizedBox(width: double.infinity, child: child)),
      );

  /// "3 new" on a dark card: a brass badge and a short line; a tap lists them.
  Widget _pendingLine(String id) {
    final t = context.gText;
    return GestureDetector(
      key: ValueKey('home-pending-$id'),
      behavior: HitTestBehavior.opaque,
      onTap: _showPending,
      child: Row(
        children: [
          PendingBadge(count: _pending.count, onDark: true, onTap: _showPending),
          const SizedBox(width: 8),
          Expanded(child: Text('new — tap to see', style: t.heroCaption, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  /// The list of the new changes: looking at it clears the badge at once (the save to the server goes on in the background).
  void _showPending() {
    final shown = _pending;
    PlanData.instance.looked(_planOwner);
    showNewChanges(context, shown);
  }

  void _openToday([PlanGroup? section]) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlanPage(section: section)),
      );

  /// TODAY'S TASKS: the same card as THIS WEEK (size, shape, layout, texture; only the colour is green) with the same three stats, as today's numbers:
  /// TARGETS (the target tasks of today), TO CONTACT (what is left) and DONE (every task finished today) - the Plan page's "Total · Done · Left" (`TodayView`).
  /// A zero shows as "0". The card, or the Done / To contact stat, opens the Plan page on Today; the Targets stat on its Target tasks.
  Widget _todayCard({bool placeholder = false}) {
    final view = TodayView.of(placeholder ? null : _plan);
    String n(int v) => placeholder ? '–' : '$v';
    GuideHeroStat stat(String key, String label, int value, [PlanGroup? section]) => GuideHeroStat(
          n(value),
          label,
          valueKey: ValueKey('home-today-$key-count'),
          tapKey: ValueKey('home-today-$key'),
          onTap: placeholder ? null : () => _openToday(section),
        );
    return GuideHeroCard(
      key: const ValueKey('home-today-tasks'),
      label: "Today's tasks",
      trailing: DateFormat('EEE d MMM').format(DateTime.now()),
      gradient: GuideColors.todayGradient,
      shadowColor: GuideColors.todayShadow,
      onTap: placeholder ? null : () => _openToday(),
      footer: placeholder || _pending.count == 0 ? null : _pendingLine('today'),
      stats: [
        stat('targets', 'Targets', view.section(kSectionTargets).total, PlanGroup.target),
        stat('left', 'To contact', view.left),
        stat('done', 'Done', view.done),
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

  /// A wide window keeps the Home content in a centred column (a phone: the whole width, as before).
  @override
  Widget build(BuildContext context) => ContentWidth(child: _list(context));

  Widget _list(BuildContext context) {
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
            child: _compact(GuideStateView(
              state: _heroState,
              ghost: GuideGhostOf(
                radius: GuideShape.heroRadius,
                placeholder: _heroCard(const [], placeholder: true),
              ),
              content: _heroState == GuideLoad.content ? _heroCard(active) : const SizedBox.shrink(),
              errorMessage: 'Could not load this week. Check your connection and try again.',
              onRetry: _retry,
            )),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 0),
          child: GuideEntry(
            index: 2,
            child: _compact(GuideStateView(
              state: _todayState,
              ghost: GuideGhostOf(radius: GuideShape.tileRadius, placeholder: _todayCard(placeholder: true)),
              content: _todayState == GuideLoad.content ? _todayCard() : const SizedBox.shrink(),
              errorMessage: "Could not load today's tasks. Check your connection and try again.",
              onRetry: _retry,
            )),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 0),
          child: GuideEntry(
            index: 3,
            child: GuideStateView(
              state: _targetsState == GuideLoad.empty ? GuideLoad.content : _targetsState,
              ghost: GuideGhostOf(radius: GuideShape.tileRadius, placeholder: _targetsCard(placeholder: true)),
              content: _targetsCard(),
              errorMessage: 'Could not load your targets. Check your connection and try again.',
              onRetry: _retry,
            ),
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
