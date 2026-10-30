import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysEntry.dart';
import 'package:folk_guide_app/Pages/CompoundGoalProgressPage.dart';
import 'package:folk_guide_app/Pages/GoalSetup.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/agent/AgentRoutes.dart';
import 'package:folk_guide_app/theme/AgentLook.dart' show contrastRatio;
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:folk_guide_app/theme/ThemeModeController.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BottomNavBar.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/HomeData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/widgets/GuideNav.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

/// Plain values instead of Firestore.
class FakeHomeData implements HomeData {
  FakeHomeData({
    this.targetList = const [],
    this.students = 20,
    this.eventList = const [],
  });

  final List<CompoundTarget> targetList;
  final int students;
  final List<CalendarEvent> eventList;

  @override
  Stream<List<CompoundTarget>> targets(String guide) => Stream.value(targetList);
  @override
  Stream<int> studentCount() => Stream.value(students);
  @override
  Future<List<CalendarEvent>> events(String guide) async => eventList;
  @override
  Widget calendarBadge({required Widget child}) => child;
}

CompoundTarget target(String metric, int students, int value, int phase, int total, {DateTime? end}) =>
    CompoundTarget.from('G', 't$metric', {
      if (end != null) 'endDate': Timestamp.fromDate(end),
      'metric': metric,
      'studentCountGoal': students,
      'perStudentValueGoal': value,
      'status': 'active',
      'currentPhase': phase,
      'totalPhases': total,
    });

AdminProfile profile(String id, String role) => AdminProfile.fromMap({
      'id': id,
      'displayName': '$id Prabhu',
      'role': role,
      'teamGuide': '',
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

/// A MaterialApp whose theme follows a ThemeModeController, like the real app.
/// A test of the assistant's button asks for the real overlay around the app.
bool _withOverlay = false;

class _App extends StatelessWidget {
  const _App({required this.home});
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: GuideTheme.light,
      darkTheme: GuideTheme.dark,
      themeMode: context.watch<ThemeModeController>().themeMode,
      themeAnimationDuration: Duration.zero,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: _withOverlay ? AgentOverlay(child: c!) : c!,
      ),
      home: home,
    );
  }
}

/// Today's plan as the tests of Home see it: 3 follow-ups (one of them done), 1 target task, 2 other tasks; the week: 6 to contact, 2 done.
PlanDoc homePlan() => planDoc(left: 6, done: 2, today: [
      interactionItem('u1', 'Ravi', ['sadhana']),
      interactionItem('u2', 'Amit', ['doubts', 'target']),
      interactionItem('u3', 'Sohan', ['concern'], done: true),
      interactionItem('u4', 'Mohit', ['target']),
      const PlanItem(id: 'meeting:u9:2026-10-30', kind: 'meeting', title: 'Meet Harsh', forYou: true),
      const PlanItem(id: 'calendar::x', kind: 'calendar', title: 'Midterm'),
    ]);

Future<ThemeModeController> pumpShell(WidgetTester tester, {HomeData? data, AdminProfile? me, PlanDoc? plan, PlanData? planData}) async {
  SharedPreferences.setMockInitialValues({'selected_guide': 'G'});
  final controller = await ThemeModeController.load();
  AdminProfileProvider.instance.debugSet(me ?? profile('G', 'GUIDE'));
  HomeData.instance = data ??
      FakeHomeData(
        targetList: [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)],
      );
  PlanData.instance = planData ?? FixedPlanData(plan ?? homePlan());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeModeController>.value(value: controller),
        ChangeNotifierProvider<ColorProvider>(create: (_) => ColorProvider()),
      ],
      child: const _App(home: CurvedNavBar('G')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    UnseenAggregates.debugDisable = true;
  });
  tearDownAll(() {
    UnseenAggregates.debugDisable = false;
    HomeData.instance = const FirestoreHomeData();
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  testWidgets("THE ASSISTANT'S BUTTON: the real shell on screen shows it (it was there for ~3 seconds BEFORE Home); the shell going takes it away", (tester) async {
    phone(tester, 1.0);
    _withOverlay = true;
    addTearDown(() {
      _withOverlay = false;
      AgentShell.ready.value = false;
    });
    AgentShell.ready.value = false;
    await pumpShell(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(AgentShell.ready.value, isTrue, reason: 'the shell announced itself after its first frame');
    expect(find.byKey(const ValueKey('agent-fab')).hitTestable(), findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(find.byKey(const ValueKey('agent-button-fade'))).opacity, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(AgentShell.ready.value, isFalse, reason: 'the shell is gone: so is the button');
  });

  testWidgets('Home shows the real numbers: hero, target cards, board and calendar tiles', (tester) async {
    phone(tester, 1.0);
    await pumpShell(tester);
    expect(find.text('G Prabhu'), findsOneWidget, reason: 'the guide name, not a mockup name');
    expect(find.text('Hare Krishna,'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    // THIS WEEK: Targets 2, To contact 6, Done 2
    String week(String k) => tester.widget<Text>(find.byKey(ValueKey('home-week-$k-count'))).data!;
    expect(week('targets'), '2');
    expect(week('left'), '6');
    expect(week('done'), '2');
    expect(find.text('Targets'), findsOneWidget, reason: 'the hero stat');
    expect(find.text('To contact'), findsOneWidget);
    expect(find.text('Overdue'), findsNothing, reason: 'the old hero stats are gone');
    expect(find.text('Follow-ups'), findsOneWidget, reason: "today's tasks: the count's name, once");
    expect(find.textContaining('Phase 1 of 8'), findsNothing, reason: 'no per-target cards: status and progress are viewed in the plan');
    expect(find.text('Chanting'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('FOLK'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget, reason: 'chanting and books are set; FOLK is not');
    expect(find.text('FOLK Boys Board'), findsOneWidget);
    expect(find.text('20 boys'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Nothing due today'), findsOneWidget);
    // The nav: Home active with its label, the others icons only
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Analysis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('THE TWO PLAN WIDGETS on Home: THIS WEEK (navy) and TODAY\'S TASKS', () {
    setUp(() => SeenMarkers.debugDisable = true);
    tearDown(() => SeenMarkers.debugDisable = false);

    String count(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey('home-today-$key-count'))).data!;

    testWidgets('both are there, in this order: THIS WEEK first, TODAY\'S TASKS under it; the old hero stats (Overdue ...) are gone', (tester) async {
      phone(tester, 1.0);
      await pumpShell(tester);
      expect(find.byKey(const ValueKey('home-this-week')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-today-tasks')), findsOneWidget);
      expect(find.text("TODAY'S TASKS"), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const ValueKey('home-this-week'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('home-today-tasks'))).dy));
      expect(tester.getTopLeft(find.byKey(const ValueKey('home-today-tasks'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('home-targets-card'))).dy));
      expect(find.text('Overdue'), findsNothing);
    });

    testWidgets('THE THREE COUNTS: follow-ups (interactions students need), target tasks (made by the targets), other tasks; a done one is not counted', (tester) async {
      phone(tester, 1.0);
      await pumpShell(tester);
      // homePlan(): Ravi (sadhana), Amit (doubts + target: a follow-up), Sohan (concern, DONE), Mohit (target only), a meeting, a calendar item
      // a student is ONE card; a section counts every card with a topic in it (Amit's card has a doubt AND a target topic: counted in both)
      expect(count(tester, 'followups'), '2');
      expect(count(tester, 'targets'), '2');
      expect(count(tester, 'other'), '2');
      expect(find.text('Follow-ups'), findsOneWidget);
      expect(find.text('Target tasks'), findsOneWidget);
      expect(find.text('Other tasks'), findsOneWidget);
    });

    testWidgets('the counts are LIVE: a tick lowers one, a new item raises one, with nothing to reopen', (tester) async {
      phone(tester, 1.0);
      final live = ManualPlanData();
      await pumpShell(tester, planData: live);
      expect(count(tester, 'followups'), '–', reason: 'a dash until the plan is there');
      live.c.add(homePlan());
      await tester.pump();
      await tester.pump();
      expect(count(tester, 'followups'), '2');
      // Ravi is ticked, a new doubt shows up in Other tasks, a new target task appears
      live.c.add(planDoc(left: 5, done: 3, today: [
        interactionItem('u1', 'Ravi', ['sadhana'], done: true),
        interactionItem('u2', 'Amit', ['doubts', 'target']),
        interactionItem('u4', 'Mohit', ['target']),
        interactionItem('u5', 'Hari', ['target']),
        const PlanItem(id: 'doubts::x', kind: 'doubtsToAnswer', title: '1 doubt waiting'),
        const PlanItem(id: 'meeting:u9:2026-10-30', kind: 'meeting', title: 'Meet Harsh', forYou: true),
        const PlanItem(id: 'calendar::x', kind: 'calendar', title: 'Midterm'),
      ]));
      await tester.pump();
      await tester.pump();
      expect(count(tester, 'followups'), '1');
      expect(count(tester, 'targets'), '3');
      expect(count(tester, 'other'), '3');
      expect(tester.binding.transientCallbackCount, 0, reason: 'a live update replays nothing');
    });

    testWidgets('a quiet day shows 0 0 0, not blanks', (tester) async {
      phone(tester, 1.0);
      await pumpShell(tester, plan: planDoc());
      expect([count(tester, 'followups'), count(tester, 'targets'), count(tester, 'other')], ['0', '0', '0']);
    });

    testWidgets('THIS WEEK opens the Plan page on its This week tab', (tester) async {
      phone(tester, 1.0);
      await pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('home-this-week')));
      await tester.pumpAndSettle();
      final page = tester.widget<PlanPage>(find.byType(PlanPage));
      expect(page.initialWeek, isTrue);
      expect(page.section, isNull);
      expect(find.byKey(const ValueKey('plan-week-section-interactions')), findsOneWidget, reason: 'the This week tab is showing');
    });

    testWidgets("TODAY'S TASKS (the card) opens the Plan page on the Today tab", (tester) async {
      phone(tester, 1.0);
      await pumpShell(tester);
      await tester.tap(find.text("TODAY'S TASKS"));
      await tester.pumpAndSettle();
      final page = tester.widget<PlanPage>(find.byType(PlanPage));
      expect(page.initialWeek, isFalse);
      expect(page.section, isNull);
      expect(find.textContaining('Today — Friday 30 October'), findsOneWidget);
    });

    for (final e in {'followups': PlanGroup.followUp, 'targets': PlanGroup.target, 'other': PlanGroup.other}.entries) {
      testWidgets('tapping the ${e.key} count opens Today at that section', (tester) async {
        phone(tester, 1.0);
        await pumpShell(tester);
        await tester.tap(find.byKey(ValueKey('home-today-${e.key}')));
        await tester.pumpAndSettle();
        final page = tester.widget<PlanPage>(find.byType(PlanPage));
        expect(page.section, e.value);
        expect(page.initialWeek, isFalse);
        expect(find.byKey(ValueKey('plan-section-${e.key}')), findsOneWidget);
      });
    }

    testWidgets('HOME COUNTS STUDENTS (cards), topics counted inside: a student with a worry, a doubt and a target task is ONE in each section he has a topic in', (tester) async {
      phone(tester, 1.0);
      const ravi = PlanItem(
        id: 'interaction:u1:2026-10-28',
        kind: 'interaction',
        title: 'Interaction with Ravi',
        studentName: 'Ravi',
        studentUid: 'u1',
        points: [
          PlanPoint(text: 'Sounded worried', group: PlanGroup.worry),
          PlanPoint(text: 'Doubt waiting', group: PlanGroup.followUp),
          PlanPoint(text: 'Chanting: 12 → 16 rounds', group: PlanGroup.target),
        ],
        cardGroups: [PlanGroup.worry, PlanGroup.target, PlanGroup.followUp],
      );
      const amit = PlanItem(id: 'student:u2:2026-10-30', kind: 'student', title: 'Amit', studentName: 'Amit', studentUid: 'u2', points: [PlanPoint(text: 'Meeting with him today', group: PlanGroup.other)], cardGroups: [PlanGroup.other]);
      await pumpShell(tester, plan: planDoc(left: 1, today: const [ravi, amit]));
      expect(count(tester, 'followups'), '1', reason: 'Ravi once (his worry and his doubt are inside his card)');
      expect(count(tester, 'targets'), '1');
      expect(count(tester, 'other'), '1', reason: 'Amit');
      final c = PlanCounts.of(planDoc(left: 1, today: const [ravi, amit]));
      expect([c.students, c.cards, c.tasks, c.total], [2, 2, 0, 2], reason: 'two students: two cards, not five topics');
    });

    testWidgets('PENDING CHANGES: both widgets show the live badge and a line; a tap lists them; none pending: no badge', (tester) async {
      phone(tester, 1.0);
      await pumpShell(tester, planData: FixedPlanData(homePlan(), changes: pendingOf(['interaction with Amit', 'interaction with Ravi'])));
      for (final id in ['week', 'today']) {
        expect(find.byKey(ValueKey('home-pending-$id')), findsOneWidget, reason: id);
      }
      expect(find.text('changes not in the plan yet — tap Refresh'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('home-pending-today')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('pending-summary'))).data, '2 changes: interaction with Ravi; interaction with Amit');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await pumpShell(tester);
      expect(find.byKey(const ValueKey('home-pending-week')), findsNothing);
      expect(find.byKey(const ValueKey('home-pending-today')), findsNothing);
    });

    testWidgets('the pending line is live on Home: a change arrives, then the refresh clears it', (tester) async {
      phone(tester, 1.0);
      final live = ManualPlanData();
      await pumpShell(tester, planData: live);
      live.c.add(homePlan());
      live.pendingC.add(PendingChanges.none);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('home-pending-today')), findsNothing);
      live.pendingC.add(pendingOf(["worry from Ravi's AI chat"]));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('home-pending-today')), findsOneWidget);
      expect(find.text('change not in the plan yet — tap Refresh'), findsNWidgets(2));
      live.pendingC.add(PendingChanges.none);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('home-pending-today')), findsNothing);
    });

    testWidgets('A HOD\'S HOME counts HIS OWN plan (his id, not the guide he picked); the guides\' summary lines are not tasks', (tester) async {
      phone(tester, 1.0);
      final asked = <String>[];
      final data = RecordingPlanData(FixedPlanData(PlanDoc(
        todayDate: '2026-10-30',
        todayItems: [
          interactionItem('u1', 'Ravi', ['sadhana']),
          const PlanItem(id: 'guide:G1', kind: 'guideSummary', title: 'Gopal: 3 for today'),
          const PlanItem(id: 'guide:G2', kind: 'guideSummary', title: 'Govinda: 1 for today'),
        ],
        weekOf: '2026-10-26',
        intro: 'x',
        sections: const [],
        generatedAt: DateTime.utc(2026, 10, 30, 4, 10),
        status: 'upToDate',
        changedAt: DateTime.utc(2026, 10, 30, 4, 10),
        batch: const PlanBatch(size: 4, round: 1, members: 1, carried: 0, nextReady: false, done: 0, left: 1),
        progress: const PlanProgress(needed: 1, done: 0, left: 1, summary: 'Interactions needed: 1 · done 0 · left 1', bySource: []),
      )), asked);
      await pumpShell(tester, me: profile('HOD1', 'HOD'), planData: data);
      expect(asked.toSet(), {'HOD1'}, reason: 'the plan read is the HOD\'s own, not the guide G picked');
      expect(find.byKey(const ValueKey('home-today-followups-count')), findsWidgets);
      expect(tester.widget<Text>(find.byKey(const ValueKey('home-today-followups-count'))).data, '1');
      expect(tester.widget<Text>(find.byKey(const ValueKey('home-today-other-count'))).data, '0', reason: 'two guide summaries are not tasks');
    });

    testWidgets('the FIRST OPEN OF THE DAY tells the server once (that is what makes it write Today\'s AI questions); never again that day', (tester) async {
      phone(tester, 1.0);
      FolkBoysEntryScreen.forgetOpenedDay();
      final sent = <Map<String, dynamic>>[];
      HierarchyApi.useForTests((name, data) async {
        sent.add({'name': name, ...data});
        return {'ok': true};
      });
      addTearDown(() => HierarchyApi.useForTests(null));
      await pumpShell(tester);
      expect(sent, [
        {'name': 'refreshPlan', 'open': true}
      ]);
      await tester.pumpWidget(const SizedBox());
      await pumpShell(tester); // opened again the same day: nothing more
      expect(sent.length, 1);
    });

    testWidgets('a failed first-open call is silent: the plan is simply there', (tester) async {
      phone(tester, 1.0);
      FolkBoysEntryScreen.forgetOpenedDay();
      HierarchyApi.useForTests((name, data) async => throw HierarchyException('internal', 'down'));
      addTearDown(() => HierarchyApi.useForTests(null));
      await pumpShell(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('home-today-followups-count')), findsWidgets);
    });

    testWidgets('THE OLD WEEKLY PLANNING PAGE IS GONE: no file, no agent route, no helper', (tester) async {
      expect(File('lib/Pages/WeeklyPlanning.dart').existsSync(), isFalse);
      expect(File('lib/utils/WeekData.dart').existsSync(), isFalse);
      expect(kAgentRoutes.containsKey('week_planning'), isFalse);
      expect(kAgentRoutes.containsKey('plan'), isTrue, reason: 'the assistant\'s Plan page is the one place');
      final home = File('lib/Home/FolkBoysEntry.dart').readAsStringSync();
      expect(home.contains('WeeklyPlanning'), isFalse);
    });

    testWidgets('a failed plan: the cards say so with Retry (never a blank), and the rest of Home is there', (tester) async {
      phone(tester, 1.0, size: const Size(360, 1800));
      final live = ManualPlanData();
      await pumpShell(tester, planData: live);
      live.c.addError('boom');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining("Could not load today's tasks"), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      expect(find.text('FOLK Boys Board'), findsOneWidget);
    });

    for (final wide in [false, true]) {
      for (final dark in [false, true]) {
        for (final scale in kScales) {
          testWidgets('${wide ? 'website 1280' : 'phone 360'}, ${dark ? 'dark' : 'light'}, text scale $scale: THIS WEEK and TODAY\'S TASKS are EXACTLY the same size, nothing overflows, each count is a 48 dp target', (tester) async {
            phone(tester, scale, size: wide ? const Size(1280, 900) : const Size(360, 800));
            await pumpShell(tester);
            if (dark) {
              tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
              addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
              await tester.pump();
            }
            expect(tester.takeException(), isNull);
            final week = tester.getRect(find.byKey(const ValueKey('home-this-week')));
            final today = tester.getRect(find.byKey(const ValueKey('home-today-tasks')));
            expect(today.width, closeTo(week.width, 0.5), reason: 'same width, one column');
            expect(today.height, closeTo(week.height, 0.5), reason: 'same height');
            expect(today.left, closeTo(week.left, 0.5), reason: 'same left edge');
            if (wide) expect(today.width, lessThan(700), reason: 'a compact column on a wide screen');
            for (final k in ['followups', 'targets', 'other']) {
              final r = tester.getRect(find.byKey(ValueKey('home-today-$k')));
              expect(r.height, greaterThanOrEqualTo(48), reason: k);
              expect(r.left >= today.left && r.right <= today.right && r.top >= today.top && r.bottom <= today.bottom, isTrue, reason: '$k inside the card');
            }
            if (scale == 1.0 && !wide) expect(today.height, lessThan(170), reason: 'compact on a phone');
          });
        }
      }
    }

    testWidgets('EVERY COUNT IS ALWAYS THERE, "0" when nothing exists: a HOD with one target and no plan numbers at all', (tester) async {
      phone(tester, 1.0);
      // no progress block, no items: what a HOD with a single target had (the contact / done counts used to be missing)
      await pumpShell(tester, me: profile('H', 'HOD'), data: FakeHomeData(targetList: [target('chanting', 10, 16, 1, 8)]), plan: planDoc());
      String week(String k) => tester.widget<Text>(find.byKey(ValueKey('home-week-$k-count'))).data!;
      expect([week('targets'), week('left'), week('done')], ['1', '0', '0']);
      expect([count(tester, 'followups'), count(tester, 'targets'), count(tester, 'other')], ['0', '0', '0']);
      expect(find.text('To contact'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      // and with no target and no plan document at all
      await tester.pumpWidget(const SizedBox());
      await pumpShell(tester, data: FakeHomeData(targetList: const []), planData: FixedPlanData(null));
      expect([week('targets'), week('left'), week('done')], ['0', '0', '0']);
      expect([count(tester, 'followups'), count(tester, 'targets'), count(tester, 'other')], ['0', '0', '0']);
    });
  });

  group("TODAY'S TASKS IN DARK GREEN (THIS WEEK stays navy)", () {
    /// the gradient painted behind a Home card (the hero panel's own decoration)
    LinearGradient? gradientOf(WidgetTester tester, String key) {
      for (final c in tester.widgetList<Container>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Container)))) {
        final d = c.decoration;
        if (d is BoxDecoration && d.gradient is LinearGradient) return d.gradient as LinearGradient;
      }
      return null;
    }

    Color blend(Color fg) => Color.alphaBlend(fg, GuideColors.todayGradient.colors.last);

    test('the colours: a dark green gradient with the same depth as the navy one, and light text that reads on both ends at 4.5:1 or better', () {
      final navy = GuideColors.heroGradient.colors;
      final green = GuideColors.todayGradient.colors;
      expect(green.length, navy.length, reason: 'the same two-stop depth');
      expect(green.first, const Color(0xFF0E3B2C));
      expect(green.last, const Color(0xFF1C5C42));
      expect(GuideColors.todayGradient.begin, GuideColors.heroGradient.begin);
      expect(GuideColors.todayGradient.end, GuideColors.heroGradient.end);
      // it is green, not navy: the green channel leads at both ends
      for (final c in green) {
        expect(c.g, greaterThan(c.b));
        expect(c.g, greaterThan(c.r));
      }
      for (final bg in green) {
        // the text colours the card uses, over each end of the gradient (the muted one is translucent: blended over the background first)
        expect(contrastRatio(GuideColors.heroText, bg), greaterThanOrEqualTo(4.5), reason: 'the numbers on ${bg.toARGB32().toRadixString(16)}');
        expect(contrastRatio(Color.alphaBlend(GuideColors.heroMuted, bg), bg), greaterThanOrEqualTo(4.5), reason: 'the captions');
        expect(contrastRatio(GuideColors.heroLabel, bg), greaterThanOrEqualTo(4.5), reason: "the TODAY'S TASKS label");
        expect(contrastRatio(blend(GuideColors.heroMuted), bg), greaterThanOrEqualTo(4.5), reason: 'the chevron');
      }
    });

    for (final wide in [false, true]) {
      for (final dark in [false, true]) {
        testWidgets('${wide ? 'website 1280' : 'phone 360'}, ${dark ? 'dark' : 'light'}: TODAY\'S TASKS is the dark green gradient, THIS WEEK is still navy, the text is the light hero text', (tester) async {
          phone(tester, 1.0, size: wide ? const Size(1280, 900) : const Size(360, 800));
          await pumpShell(tester);
          if (dark) {
            tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
            addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
            await tester.pump();
          }
          final week = gradientOf(tester, 'home-this-week')!;
          final today = gradientOf(tester, 'home-today-tasks')!;
          expect(week.colors, GuideColors.heroGradient.colors, reason: 'THIS WEEK stays navy blue');
          expect(today.colors, GuideColors.todayGradient.colors, reason: "TODAY'S TASKS is dark green");
          Color colorOf(Finder f) => tester.widget<Text>(f).style!.color!;
          final card = find.byKey(const ValueKey('home-today-tasks'));
          expect(colorOf(find.descendant(of: card, matching: find.text("TODAY'S TASKS"))), GuideColors.heroLabel);
          for (final k in ['followups', 'targets', 'other']) {
            expect(colorOf(find.byKey(ValueKey('home-today-$k-count'))), GuideColors.heroText, reason: k);
          }
          expect(colorOf(find.descendant(of: card, matching: find.text('Follow-ups'))), GuideColors.heroMuted);
          // measured on what is rendered: every text of the card against the lighter end of the gradient
          for (final tx in tester.widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))) {
            final c = tx.style?.color;
            if (c == null) continue;
            expect(contrastRatio(Color.alphaBlend(c, GuideColors.todayGradient.colors.last), GuideColors.todayGradient.colors.last), greaterThanOrEqualTo(4.5), reason: tx.data);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('the Calendar tile names what is happening or coming up', (tester) async {
    phone(tester, 1.0);
    final today = DateTime.now();
    await pumpShell(
      tester,
      data: FakeHomeData(eventList: [
        CalendarEvent(
          id: 'e1', eventDate: today, endDate: null, type: 'exam', title: 'Midterm',
          note: '', sourceTextBlockId: '', scope: 'mandatory', ownerGuideId: null, notifyOffsets: const [],
        ),
      ]),
    );
    expect(find.text('Midterm'), findsOneWidget);
  });

  group('the TARGETS CARD: three plain themed tiles (Chanting, Reading, FOLK) with a tick or a cross; a Female Enabler has two', () {
    Future<void> shell(WidgetTester tester, List<CompoundTarget> targets, {double scale = 1.0, bool dark = false, AdminProfile? me, Size? size}) async {
      phone(tester, scale, size: size ?? const Size(360, 800));
      await pumpShell(tester, data: FakeHomeData(targetList: targets), me: me);
      if (dark) {
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pump();
      }
    }

    final end = DateTime(2026, 12, 31);
    final chant = target('chanting', 10, 16, 1, 8, end: end);
    final books = target('books', 10, 5, 2, 8, end: end);
    final folk = target('folk', 6, 1, 1, 4, end: end);
    bool isSet(WidgetTester tester, String m) => tester.widget<GuideTargetBadge>(find.byKey(ValueKey('home-target-badge-$m'))).isSet;

    testWidgets('none set: three tiles, each "Not set" with a cross; a "Set a target" button', (tester) async {
      await shell(tester, const []);
      expect(find.byKey(const ValueKey('home-targets-card')), findsOneWidget);
      for (final m in ['chanting', 'books', 'folk']) {
        expect(find.byKey(ValueKey('home-target-$m')), findsOneWidget, reason: m);
        expect(isSet(tester, m), isFalse, reason: m);
      }
      expect(find.text('Chanting'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('FOLK'), findsOneWidget);
      expect(find.text('Not set'), findsNWidgets(3));
      expect(find.text('Set a target'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-view-targets')), findsNothing);
      expect(find.textContaining("You haven't set"), findsNothing, reason: 'the old text card is gone');
    });

    testWidgets('some set: a tick and what it says ("16 rounds by 31 Dec") on the set ones, a cross on the others', (tester) async {
      await shell(tester, [chant, books]);
      expect(isSet(tester, 'chanting'), isTrue);
      expect(isSet(tester, 'books'), isTrue);
      expect(isSet(tester, 'folk'), isFalse);
      expect(find.text('16 rounds by 31 Dec'), findsOneWidget);
      expect(find.text('5 books by 31 Dec'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.text('Set a target'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await shell(tester, [folk]);
      expect(isSet(tester, 'folk'), isTrue);
      expect(find.text('6 FOLK residents by 31 Dec'), findsOneWidget);
      expect(isSet(tester, 'chanting'), isFalse);
      expect(find.text('Not set'), findsNWidgets(2));
    });

    testWidgets('all set: three ticks and "View targets" (no "Set a target"), which opens the targets in the plan', (tester) async {
      await shell(tester, [chant, books, folk]);
      for (final m in ['chanting', 'books', 'folk']) {
        expect(isSet(tester, m), isTrue, reason: m);
      }
      expect(find.text('Not set'), findsNothing);
      expect(find.byKey(const ValueKey('home-set-target')), findsNothing);
      expect(find.text('View targets'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-view-targets')));
      await tester.pumpAndSettle();
      expect(tester.widget<PlanPage>(find.byType(PlanPage)).initialWeek, isTrue, reason: 'the targets are on This week');
    });

    testWidgets('a Female Enabler has two tiles: no FOLK tile (that target is boys only)', (tester) async {
      final fe = profile('F', 'FEMALE_ENABLER');
      await shell(tester, const [], me: fe);
      expect(find.byKey(const ValueKey('home-target-folk')), findsNothing);
      expect(find.text('FOLK'), findsNothing);
      expect(find.text('Not set'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      await shell(tester, [chant, books], me: fe);
      expect(find.byKey(const ValueKey('home-target-folk')), findsNothing);
      expect(find.text('View targets'), findsOneWidget, reason: 'both of hers are set');
      expect(find.byKey(const ValueKey('home-set-target')), findsNothing);
    });

    testWidgets('a finished or abandoned target does not count as set', (tester) async {
      final done = CompoundTarget.from('G', 'old', {'metric': 'chanting', 'status': 'completed', 'currentPhase': 1, 'totalPhases': 1});
      await shell(tester, [done]);
      expect(isSet(tester, 'chanting'), isFalse);
      expect(find.text('Set a target'), findsOneWidget);
    });

    testWidgets('"Set a target" opens the create flow on the FIRST missing type', (tester) async {
      for (final c in [
        (<CompoundTarget>[chant, books], 'folk'),
        (<CompoundTarget>[], 'chanting'),
        (<CompoundTarget>[books], 'chanting'),
        (<CompoundTarget>[chant], 'books'),
      ]) {
        await shell(tester, c.$1);
        await tester.tap(find.byKey(const ValueKey('home-set-target')));
        await tester.pumpAndSettle();
        expect(tester.widget<CompoundGoalSetupPage>(find.byType(CompoundGoalSetupPage)).initialMetric, c.$2, reason: '${c.$1.length} set');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a tile that is not set opens its create flow; a tile that is set opens that target', (tester) async {
      await shell(tester, [chant]);
      await tester.tap(find.byKey(const ValueKey('home-target-books')));
      await tester.pumpAndSettle();
      expect(tester.widget<CompoundGoalSetupPage>(find.byType(CompoundGoalSetupPage)).initialMetric, 'books');
      await tester.pumpWidget(const SizedBox());
      await shell(tester, [chant]);
      await tester.tap(find.byKey(const ValueKey('home-target-chanting')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CompoundGoalProgressPage), findsOneWidget);
      expect(tester.widget<CompoundGoalProgressPage>(find.byType(CompoundGoalProgressPage)).targetId, chant.targetId);
      tester.takeException();
    });

    BoxDecoration? tileDecoration(WidgetTester tester, String m) {
      for (final c in tester.widgetList<Container>(find.descendant(of: find.byKey(ValueKey('home-target-$m')), matching: find.byType(Container)))) {
        final d = c.decoration;
        if (d is BoxDecoration && d.gradient is LinearGradient && d.boxShadow != null && d.boxShadow!.isNotEmpty) return d;
      }
      return null;
    }

    for (final dark in [false, true]) {
      for (final wide in [false, true]) {
        testWidgets('PLAIN THEMED TILES (${dark ? 'dark: soft grey' : 'light: off-white'}, ${wide ? 'website 1280' : 'phone 360'}): all three alike, raised, the same height', (tester) async {
          await shell(tester, [chant], dark: dark, size: wide ? const Size(1280, 900) : const Size(360, 800));
          final want = dark ? GuideColors.targetTileDark : GuideColors.targetTileLight;
          for (final m in ['chanting', 'books', 'folk']) {
            final d = tileDecoration(tester, m)!;
            expect((d.gradient as LinearGradient).colors, want, reason: '$m: one plain colour for every tile (no pastel per target)');
            expect(d.boxShadow!.length, greaterThanOrEqualTo(2), reason: '$m: a raised edge: a soft shadow and a thin highlight');
            expect(d.border, isNotNull);
          }
          final h = [for (final m in ['chanting', 'books', 'folk']) tester.getSize(find.byKey(ValueKey('home-target-$m'))).height];
          expect(h[0], closeTo(h[1], 0.5));
          expect(h[1], closeTo(h[2], 0.5));
          // no pastel box any more
          expect(find.descendant(of: find.byKey(const ValueKey('home-targets-card')), matching: find.byType(GuidePastelBox)), findsNothing, reason: 'the old colourful tiles are gone from the targets card');
        });
      }
    }

    testWidgets('the tile text reads: the theme text colour on the tile is 4.5:1 or better on both ends of the shade, in light and dark', (tester) async {
      for (final dark in [false, true]) {
        await shell(tester, [chant, books], dark: dark);
        final want = dark ? GuideColors.targetTileDark : GuideColors.targetTileLight;
        for (final m in ['chanting', 'books', 'folk']) {
          for (final tx in tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey('home-target-$m')), matching: find.byType(Text)))) {
            final c = tx.style?.color;
            expect(c, isNotNull, reason: '${tx.data}');
            for (final bg in want) {
              expect(contrastRatio(c!, bg), greaterThanOrEqualTo(4.5), reason: '${tx.data} in ${dark ? 'dark' : 'light'} on ${bg.toARGB32().toRadixString(16)}');
            }
          }
        }
        await tester.pumpWidget(const SizedBox());
      }
    });

    test('the tile colours are the theme\'s: off-white light, soft grey dark; the highlight and shadow differ per theme', () {
      expect(GuideColors.targetTileLight.first.computeLuminance(), greaterThan(0.85));
      expect(GuideColors.targetTileDark.first.computeLuminance(), lessThan(0.08));
      expect(GuideColors.targetTileDark.first.computeLuminance(), greaterThan(0.02), reason: 'soft grey, not black');
      expect(GuideColors.targetTileShadowDark, isNot(GuideColors.targetTileShadowLight));
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        for (final wide in [false, true]) {
          testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on ${wide ? '1280 dp' : '360 dp'}: none / some / all set: the card fits, nothing overflows, the button stays a target', (tester) async {
            for (final state in [const <CompoundTarget>[], [chant], [chant, books, folk]]) {
              await shell(tester, state, scale: scale, dark: dark, size: wide ? const Size(1280, 900) : const Size(360, 800));
              expect(tester.takeException(), isNull, reason: '${state.length} set');
              final card = tester.getRect(find.byKey(const ValueKey('home-targets-card')));
              expect(card.width, lessThanOrEqualTo(wide ? 1280 : 360));
              final button = tester.getRect(find.byKey(ValueKey(state.length == 3 ? 'home-view-targets' : 'home-set-target')));
              expect(button.height, greaterThanOrEqualTo(42));
              expect(button.right, lessThanOrEqualTo(card.right));
              for (final m in ['chanting', 'books', 'folk']) {
                final r = tester.getRect(find.byKey(ValueKey('home-target-$m')));
                expect(card.contains(r.topLeft) && card.contains(r.bottomRight), isTrue, reason: '$m inside the card');
              }
              await tester.pumpWidget(const SizedBox());
            }
          });
        }
      }
    }
  });

  group('the TICK and CROSS BADGES are drawn by hand: smooth curves, in both themes', () {
    Future<List<int>> pixels(WidgetTester tester, bool isSet) async {
      late List<int> out;
      await tester.runAsync(() async {
        final rec = ui.PictureRecorder();
        GuideTargetBadgePainter(isSet: isSet).paint(Canvas(rec), const Size(60, 60));
        final img = await rec.endRecording().toImage(60, 60);
        out = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List().toList();
      });
      return out;
    }

    List<int> px(List<int> p, int x, int y) => p.sublist((y * 60 + x) * 4, (y * 60 + x) * 4 + 4);
    int whites(List<int> p) {
      var n = 0;
      for (var i = 0; i < p.length; i += 4) {
        if (p[i] > 235 && p[i + 1] > 235 && p[i + 2] > 235 && p[i + 3] > 235) n++;
      }
      return n;
    }

    testWidgets('a round disc with a white stroke; the tick and the cross are different drawings', (tester) async {
      final tick = await pixels(tester, true);
      final cross = await pixels(tester, false);
      expect(px(tick, 0, 0)[3], 0, reason: 'round: the corner is transparent');
      expect(px(cross, 0, 0)[3], 0);
      expect(whites(tick), greaterThan(60), reason: 'a white tick is drawn');
      expect(whites(cross), greaterThan(60), reason: 'a white cross is drawn');
      expect(tick, isNot(cross));
      // the disc is green for set and red for not set (a pixel near the top of the disc, away from the stroke)
      final g = px(tick, 30, 6);
      final r = px(cross, 30, 6);
      expect(g[1], greaterThan(g[0]), reason: 'set: the green channel leads');
      expect(r[0], greaterThan(r[1]), reason: 'not set: the red channel leads');
    });

    test('the stroke reads on the disc in both themes (3:1 or better for a graphic), and the colours live in the theme', () {
      for (final c in [...GuideColors.targetSetBadge, ...GuideColors.targetUnsetBadge]) {
        expect(contrastRatio(Colors.white, c), greaterThanOrEqualTo(3.0), reason: '${c.toARGB32().toRadixString(16)}');
      }
    });

    testWidgets('the badge is the same, and labelled "Set" / "Not set", in light and dark', (tester) async {
      for (final dark in [false, true]) {
        for (final set in [true, false]) {
          phone(tester, 1.0);
          await tester.pumpWidget(guideHost(Scaffold(body: Center(child: GuideTargetBadge(isSet: set))), dark: dark));
          expect(find.bySemanticsLabel(set ? 'Set' : 'Not set'), findsOneWidget, reason: '$dark $set');
          expect(tester.getSize(find.byType(GuideTargetBadge)), const Size(30, 30));
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  testWidgets('a Female Enabler sees girls, the HOD sees students', (tester) async {
    phone(tester, 1.0);
    await pumpShell(tester, me: profile('F', 'FEMALE_ENABLER'));
    expect(find.text('20 girls'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpShell(tester, me: profile('H', 'HOD'));
    expect(find.text('20 students'), findsOneWidget);
  });

  testWidgets('the three tabs: Home, Analysis, Tasks; each shows its own page', (tester) async {
    phone(tester, 1.0);
    await pumpShell(tester);
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    await tester.pump();
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('Folk analysis'), findsOneWidget);
    for (final label in ['ABCDE', 'Interactions needed', 'Leaderboard']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Week planning'), findsNothing);
    expect(find.text('Guide targets'), findsNothing);
    await tester.tap(find.byIcon(Icons.check_box_outlined));
    await tester.pump();
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Other tasks'), findsOneWidget);
    for (final label in ['Add student', 'Submissions', 'Add admin', 'Notifications']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab state is kept: Home keeps its scroll position after visiting other tabs', (tester) async {
    phone(tester, 1.6, size: const Size(360, 640));
    await pumpShell(tester);
    final scroll = find.descendant(of: find.byType(FolkBoysEntryScreen), matching: find.byType(Scrollable)).first;
    await tester.drag(scroll, const Offset(0, -300));
    await tester.pump();
    final before = tester.state<ScrollableState>(scroll).position.pixels;
    expect(before, greaterThan(50));
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump();
    expect(tester.state<ScrollableState>(scroll).position.pixels, before);
  });

  testWidgets('switching the theme keeps the tab and the scroll position', (tester) async {
    phone(tester, 1.0);
    final controller = await pumpShell(tester);
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    await tester.pump();
    expect(find.text('Folk analysis'), findsOneWidget);
    final lightBg = Theme.of(tester.element(find.text('Folk analysis'))).scaffoldBackgroundColor;
    await controller.setMode(GuideThemeMode.dark);
    await tester.pump();
    await tester.pump();
    expect(find.text('Folk analysis'), findsOneWidget, reason: 'still on the Analysis tab');
    expect(find.text('Analysis'), findsOneWidget, reason: 'the active nav item is unchanged');
    final darkBg = Theme.of(tester.element(find.text('Folk analysis'))).scaffoldBackgroundColor;
    expect(darkBg, isNot(lightBg));
    await controller.setMode(GuideThemeMode.light);
    await tester.pump();
    expect(find.text('Folk analysis'), findsOneWidget);
  });

  testWidgets('the Appearance button offers Light, Dark and Auto and changes the theme at once', (tester) async {
    phone(tester, 1.0);
    final controller = await pumpShell(tester);
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(controller.mode, GuideThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ThemeModeController.prefsKey), 'dark', reason: 'stored on the device');
  });

  testWidgets('the legacy dark setting is migrated; no setting means Auto', (tester) async {
    SharedPreferences.setMockInitialValues({'isDarkMode': true});
    expect((await ThemeModeController.load()).mode, GuideThemeMode.dark);
    SharedPreferences.setMockInitialValues({'isDarkMode': false});
    expect((await ThemeModeController.load()).mode, GuideThemeMode.light);
    SharedPreferences.setMockInitialValues({});
    expect((await ThemeModeController.load()).mode, GuideThemeMode.auto);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('Home, ${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: no overflow, 48 dp targets', (tester) async {
        phone(tester, scale);
        final controller = await pumpShell(tester);
        await controller.setMode(dark ? GuideThemeMode.dark : GuideThemeMode.light);
        await tester.pump();
        expect(tester.takeException(), isNull);
        // the nav and every round button are at least 48 dp
        for (final f in [find.byTooltip('Appearance'), find.byTooltip('Log out')]) {
          final r = tester.getRect(f);
          expect(r.width, greaterThanOrEqualTo(48));
          expect(r.height, greaterThanOrEqualTo(48));
        }
        final nav = tester.getRect(find.byType(GuideFloatingNav));
        expect(nav.height, greaterThanOrEqualTo(68));
        expect(nav.right, lessThanOrEqualTo(360));
        // scroll to the bottom: the tiles clear the floating nav
        final scroll = find.descendant(of: find.byType(FolkBoysEntryScreen), matching: find.byType(Scrollable)).first;
        await tester.drag(scroll, const Offset(0, -2000));
        await tester.pump();
        final tile = tester.getRect(find.text('Calendar'));
        expect(tile.bottom, lessThan(tester.getTopLeft(find.byType(GuideFloatingNav)).dy + 1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final dark in [false, true]) {
    testWidgets('screenshots: Home ${dark ? 'dark' : 'light'} (for looking at)', (tester) async {
      phone(tester, 1.0, size: const Size(390, 844));
      final controller = await pumpShell(tester);
      await controller.setMode(dark ? GuideThemeMode.dark : GuideThemeMode.light);
      await tester.pump();
      await tester.pump();
      await shot(tester, 'home_${dark ? 'dark' : 'light'}');
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pump();
      await tester.pump();
      await shot(tester, 'analysis_${dark ? 'dark' : 'light'}');
      await tester.tap(find.byIcon(Icons.check_box_outlined));
      await tester.pump();
      await tester.pump();
      await shot(tester, 'tasks_${dark ? 'dark' : 'light'}');
    });
  }

  testWidgets('the hero card is the same navy in both themes', (tester) async {
    phone(tester, 1.0);
    final controller = await pumpShell(tester);
    Color heroColor() {
      final box = tester.widget<Container>(find
          .descendant(of: find.byType(GuideHeroCard), matching: find.byType(Container))
          .first);
      return ((box.decoration as BoxDecoration).gradient as LinearGradient).colors.first;
    }

    final light = heroColor();
    await controller.setMode(GuideThemeMode.dark);
    await tester.pump();
    expect(heroColor(), light);
  });
}
