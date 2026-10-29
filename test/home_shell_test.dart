import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysEntry.dart';
import 'package:folk_guide_app/Pages/GoalSetup.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:folk_guide_app/theme/ThemeModeController.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BottomNavBar.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/HomeData.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/WeekSummary.dart';
import 'package:folk_guide_app/widgets/GuideNav.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/guide_test_support.dart';

/// Plain values instead of Firestore.
class FakeHomeData implements HomeData {
  FakeHomeData({
    this.targetList = const [],
    this.followUpList = const [],
    this.overdueList = const [],
    this.students = 20,
    this.eventList = const [],
  });

  final List<CompoundTarget> targetList;
  final List<FollowUpItem> followUpList;
  final List<OverdueItem> overdueList;
  final int students;
  final List<CalendarEvent> eventList;

  @override
  Stream<List<CompoundTarget>> targets(String guide) => Stream.value(targetList);
  @override
  Stream<List<FollowUpItem>> followUps(({DateTime start, DateTime end}) week) =>
      Stream.value(followUpList);
  @override
  Stream<List<OverdueItem>> overdue() => Stream.value(overdueList);
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

Future<ThemeModeController> pumpShell(WidgetTester tester, {HomeData? data, AdminProfile? me}) async {
  SharedPreferences.setMockInitialValues({'selected_guide': 'G'});
  final controller = await ThemeModeController.load();
  AdminProfileProvider.instance.debugSet(me ?? profile('G', 'GUIDE'));
  HomeData.instance = data ??
      FakeHomeData(
        targetList: [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)],
        followUpList: [(student: 'A', when: DateTime.now(), action: 'x')],
        overdueList: [(student: 'B', days: 3), (student: 'C', days: 1)],
      );
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
    AdminProfileProvider.instance.debugSet(null);
  });

  testWidgets('Home shows the real numbers: hero, target cards, board and calendar tiles', (tester) async {
    phone(tester, 1.0);
    await pumpShell(tester);
    expect(find.text('G Prabhu'), findsOneWidget, reason: 'the guide name, not a mockup name');
    expect(find.text('Hare Krishna,'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    // Targets 2, Follow-ups 1, Overdue 2
    final hero = find.byType(GuideHeroCard);
    expect(find.descendant(of: hero, matching: find.text('2')), findsNWidgets(2), reason: 'targets and overdue');
    expect(find.descendant(of: hero, matching: find.text('1')), findsOneWidget);
    expect(find.text('Targets'), findsOneWidget, reason: 'the hero stat; the target cards are gone');
    expect(find.text('Follow-ups'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
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
    for (final label in ['ABCDE', 'Priority students', 'Leaderboard']) {
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
