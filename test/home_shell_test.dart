import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysEntry.dart';
import 'package:folk_guide_app/Pages/GoalSetup.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/agent/AgentRoutes.dart';
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

CompoundTarget target(String metric, int students, int value, int phase, int total) =>
    CompoundTarget.from('G', 't$metric', {
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
        child: c!,
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

  testWidgets('Home shows the real numbers: hero, target cards, board and calendar tiles', (tester) async {
    phone(tester, 1.0);
    await pumpShell(tester);
    expect(find.text('G Prabhu'), findsOneWidget, reason: 'the guide name, not a mockup name');
    expect(find.text('Hare Krishna,'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    // THIS WEEK: Targets 2, To contact 6, Done 2
    final hero = find.byType(GuideHeroCard);
    expect(find.descendant(of: hero, matching: find.text('2')), findsNWidgets(2), reason: 'targets and done');
    expect(find.descendant(of: hero, matching: find.text('6')), findsOneWidget);
    expect(find.text('Targets'), findsOneWidget, reason: 'the hero stat; the target cards are gone');
    expect(find.text('To contact'), findsOneWidget);
    expect(find.text('Overdue'), findsNothing, reason: 'the old hero stats are gone');
    expect(find.text('Follow-ups'), findsOneWidget, reason: "today's tasks: the count's name, once");
    expect(find.textContaining('Phase 1 of 8'), findsNothing, reason: 'no per-target cards: status and progress are viewed in the assistant');
    expect(find.textContaining('10 students at 16'), findsNothing);
    expect(find.text("You haven't set your FOLK-residents target"), findsOneWidget, reason: 'chanting and books are set; the third is asked for');
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
      expect(count(tester, 'followups'), '2');
      expect(count(tester, 'targets'), '1');
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
      expect(count(tester, 'targets'), '2');
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
      expect(find.textContaining('Hare Krishna Gopal!'), findsOneWidget, reason: 'the This week tab is showing');
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
          testWidgets('${wide ? 'website 1280' : 'phone 360'}, ${dark ? 'dark' : 'light'}, text scale $scale: compact, nothing overflows, each count is a 48 dp target', (tester) async {
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
            if (wide) expect(today.width, lessThan(700), reason: 'a compact column on a wide screen');
            for (final k in ['followups', 'targets', 'other']) {
              final r = tester.getRect(find.byKey(ValueKey('home-today-$k')));
              expect(r.height, greaterThanOrEqualTo(48), reason: k);
              expect(today.contains(r.topLeft) && today.contains(r.bottomRight), isTrue, reason: '$k inside the card');
            }
            if (scale == 1.0 && !wide) expect(today.height, lessThan(130), reason: 'compact on a phone');
          });
        }
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

  group('the ONE compact targets card (three targets; a Female Enabler has two)', () {
    Future<void> shell(WidgetTester tester, List<CompoundTarget> targets, {double scale = 1.0, bool dark = false, AdminProfile? me}) async {
      phone(tester, scale);
      await pumpShell(tester, data: FakeHomeData(targetList: targets), me: me);
      if (dark) {
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pump();
      }
    }

    final chant = target('chanting', 10, 16, 1, 8);
    final books = target('books', 10, 5, 2, 8);
    final folk = target('folk', 6, 1, 1, 4);

    testWidgets('none set: all three are named, with a Set a target button', (tester) async {
      await shell(tester, const []);
      expect(find.byKey(const ValueKey('home-targets-card')), findsOneWidget);
      expect(find.text("You haven't set your chanting, book-reading and FOLK-residents targets"), findsOneWidget);
      expect(find.byKey(const ValueKey('home-set-target')), findsOneWidget);
      expect(find.text('Set a target'), findsOneWidget);
    });

    testWidgets('chanting and books set: the FOLK-residents target is missing', (tester) async {
      await shell(tester, [chant, books]);
      expect(find.text("You haven't set your FOLK-residents target"), findsOneWidget);
      expect(find.text('Set a target'), findsOneWidget);
    });

    testWidgets('only chanting set: the other two are missing', (tester) async {
      await shell(tester, [chant]);
      expect(find.text("You haven't set your book-reading and FOLK-residents targets"), findsOneWidget);
    });

    testWidgets('only the FOLK-residents target set: chanting and book-reading are missing', (tester) async {
      await shell(tester, [folk]);
      expect(find.text("You haven't set your chanting and book-reading targets"), findsOneWidget);
    });

    testWidgets('all three set: "All your targets are set" and no button', (tester) async {
      await shell(tester, [chant, books, folk]);
      expect(find.text('All your targets are set'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-set-target')), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsWidgets);
    });

    testWidgets('a Female Enabler has two targets: the FOLK-residents one is boys only and never asked for', (tester) async {
      final fe = profile('F', 'FEMALE_ENABLER');
      await shell(tester, const [], me: fe);
      expect(find.text("You haven't set your chanting and book-reading targets"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await shell(tester, [chant, books], me: fe);
      expect(find.text('Both your targets are set'), findsOneWidget);
      expect(find.textContaining('FOLK-residents'), findsNothing);
      expect(find.byKey(const ValueKey('home-set-target')), findsNothing);
    });

    testWidgets('a finished or abandoned target does not count as set', (tester) async {
      final done = CompoundTarget.from('G', 'old', {'metric': 'chanting', 'status': 'completed', 'currentPhase': 1, 'totalPhases': 1});
      await shell(tester, [done]);
      expect(find.text("You haven't set your chanting, book-reading and FOLK-residents targets"), findsOneWidget);
    });

    testWidgets('Set a target opens the create flow, on the missing metric when exactly one is missing', (tester) async {
      await shell(tester, [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)]);
      await tester.tap(find.byKey(const ValueKey('home-set-target')));
      await tester.pumpAndSettle();
      expect(find.byType(CompoundGoalSetupPage), findsOneWidget);
      expect(tester.widget<CompoundGoalSetupPage>(find.byType(CompoundGoalSetupPage)).initialMetric, 'folk', reason: 'the one missing target is preselected');
    });

    testWidgets('no per-target cards, no Targets section any more', (tester) async {
      await shell(tester, [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)]);
      expect(find.textContaining('Phase '), findsNothing);
      expect(find.textContaining('students at'), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: the card fits, the button stays a target', (tester) async {
          await shell(tester, const [], scale: scale, dark: dark);
          expect(tester.takeException(), isNull);
          final card = tester.getRect(find.byKey(const ValueKey('home-targets-card')));
          expect(card.width, lessThanOrEqualTo(360));
          final button = tester.getRect(find.byKey(const ValueKey('home-set-target')));
          expect(button.height, greaterThanOrEqualTo(42));
          expect(button.right, lessThanOrEqualTo(card.right));
        });
      }
    }
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
