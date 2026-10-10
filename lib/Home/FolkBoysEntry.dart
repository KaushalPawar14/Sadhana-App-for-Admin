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
    final week = currentWeekRange();
    final data = HomeData.instance;
    _subs.add(data.targets(guide).listen((t) {
      if (mounted) setState(() => _targets = t);
    }, onError: (_) {}));
    _subs.add(data.followUps(week).listen((f) {
      if (mounted) setState(() => _followUps = f);
    }, onError: (_) {}));
    _subs.add(data.overdue().listen((o) {
      if (mounted) setState(() => _overdue = o);
    }, onError: (_) {}));
    _subs.add(data.studentCount().listen((n) {
      if (mounted) setState(() => _studentCount = n);
    }, onError: (_) {}));
    data.events(guide).then((e) {
      if (mounted) setState(() => _events = e);
    }).catchError((_) {});
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

  Widget _targetCard(CompoundTarget t) {
    final metric = t.metricInfo;
    final text = context.gText;
    final fraction = t.totalPhases == 0 ? 0.0 : t.currentPhase / t.totalPhases;
    final guide = _guide ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GoalHomePage(guideId: guide)),
        ),
        child: GuidePastelBox(
          pastel: _pastelFor(t),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      "${metric?.label ?? t.metric} · ${t.studentCountGoal} "
                      "students at ${t.perStudentValueGoal} ${metric?.unit ?? ''}"
                          .trim(),
                      style: text.onPastelBody.copyWith(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text("Phase ${t.currentPhase} of ${t.totalPhases}",
                      style: text.onPastelSmall),
                ],
              ),
              const SizedBox(height: 10),
              GuideProgressBar(value: fraction, onPastel: true),
            ],
          ),
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final guide = _guide;
    final profile = AdminProfileProvider.current;
    final active = _activeTargets;
    final dash = '–';

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
        Padding(
          padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 16, GuideSpace.pagePadding, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hare Krishna,', style: t.small.copyWith(fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                (profile?.displayName.isNotEmpty ?? false)
                    ? profile!.displayName
                    : 'FOLK Guide',
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
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GuideSpace.pagePadding),
          child: GuideHeroCard(
            label: 'This week',
            trailing: _weekLabel,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WeeklyPlanningPage()),
            ),
            stats: [
              GuideHeroStat(_targets == null ? dash : '${active.length}', 'Targets'),
              GuideHeroStat(_followUps == null ? dash : '${_followUps!.length}', 'Follow-ups'),
              GuideHeroStat(_overdue == null ? dash : '${_overdue!.length}', 'Overdue'),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(GuideSpace.pagePadding, 22, GuideSpace.pagePadding, 0),
          child: GuideSectionTitle('Targets'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GuideSpace.pagePadding),
          child: Column(
            children: [
              for (final target in active) _targetCard(target),
              if (_targets != null && active.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: guide == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => GoalHomePage(guideId: guide)),
                            ),
                    child: GuideCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text('No active targets yet. Open Targets to create one.',
                                  style: t.small)),
                          Icon(Icons.chevron_right_rounded, color: context.g.mutedText),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 0),
          child: guide == null
              ? const SizedBox(height: 116)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      // "Any of my roster has an unseen student comment or book
                      // commitment" (see `_boardUnseen`).
                      child: StreamBuilder<bool>(
                        stream: _boardUnseen,
                        builder: (context, snap) => UnseenBadge(
                          show: snap.data ?? false,
                          offset: const Offset(10, 10),
                          child: GuideGradientTile(
                            pastel: GuidePastel.slate,
                            icon: Icons.groups_2_outlined,
                            title: 'FOLK Boys Board',
                            subtitle: _boardSubtitle(),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => FolkBoysWorkspace(selectedGuide: guide)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: GuideSpace.cardGap),
                    Expanded(
                      // A mandatory event only the HOD can post: every other
                      // guide should notice one landed since they last opened
                      // their calendar (`calendarEvents` only).
                      child: HomeData.instance.calendarBadge(
                        child: GuideGradientTile(
                          pastel: GuidePastel.mauve,
                          icon: Icons.calendar_month_outlined,
                          title: 'Calendar',
                          subtitle: _calendarSubtitle(),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => GuideCalendarPage(selectedGuide: guide)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
