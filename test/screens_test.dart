import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AbcdeHub.dart';
import 'package:folk_guide_app/Pages/BoysDetails.dart';
import 'package:folk_guide_app/Pages/Competition.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/Pages/WeeklyPlanning.dart';
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/GoalData.dart';
import 'package:folk_guide_app/utils/WeekData.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_snapshots.dart';
import 'support/guide_test_support.dart';

AdminProfile profile(String role, {String id = 'G'}) => AdminProfile.fromMap({
      'id': id,
      'displayName': 'Me',
      'role': role,
      'teamGuide': '',
      'email': 'm@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

CompoundTarget target(String metric, int students, int value, int phase, int total, {String id = 't'}) =>
    CompoundTarget.from('G', '$id$metric', {
      'metric': metric,
      'studentCountGoal': students,
      'perStudentValueGoal': value,
      'status': 'active',
      'currentPhase': phase,
      'totalPhases': total,
    });

class FakeGoalData implements GoalData {
  FakeGoalData(this.list);
  final List<CompoundTarget> list;
  @override
  Stream<List<CompoundTarget>> targets(String guideId) => Stream.value(list);
}

class FakeWeekData implements WeekData {
  FakeWeekData({
    this.logs = const [],
    this.assocs = const [],
    this.targetList = const [],
    this.eventList = const [],
  });
  final List<Map<String, dynamic>> logs;
  final List<Map<String, dynamic>> assocs;
  final List<CompoundTarget> targetList;
  final List<CalendarEvent> eventList;

  @override
  Stream<QuerySnapshot> interactionLogs() =>
      Stream.value(FakeSnap([for (var i = 0; i < logs.length; i++) FakeDoc('l$i', logs[i])]));
  @override
  Stream<QuerySnapshot> associations() =>
      Stream.value(FakeSnap([for (var i = 0; i < assocs.length; i++) FakeDoc('a$i', assocs[i])]));
  @override
  Stream<List<CompoundTarget>> targets(String guideId) => Stream.value(targetList);
  @override
  Stream<List<CompoundPhase>> phases(String guideId, String targetId) => Stream.value([
        CompoundPhase.from('1', {
          'phaseNumber': 1,
          'tasks': [
            {'type': 'roster', 'fromCount': 6, 'toCount': 8},
            {'type': 'value', 'fromLevel': 2, 'toLevel': 4, 'studentUids': ['s1', 's2']},
          ],
        }),
      ]);
  @override
  Future<List<CalendarEvent>> events(String guideId) async => eventList;
  @override
  Future<List<TaskProgress>> phaseProgress({
    required List<CompoundTask> tasks,
    required String guideId,
    required String metric,
  }) async =>
      [
        const TaskProgress(actual: 8, target: 8, complete: true),
        const TaskProgress(actual: 1, target: 2, complete: false),
      ];
  @override
  Future<Map<String, String>> studentNames(Set<String> uids) async => {'s1': 'Ravi', 's2': 'Om'};
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    WeekData.instance = const FirestoreWeekData();
    GoalData.instance = const FirestoreGoalData();
    AdminProfileProvider.instance.debugSet(null);
  });

  // ------------------------------------------------------------------ ABCDE
  group('ABCDE', () {
    testWidgets('five pastel rows A-E with a serif letter, title, description and chevron', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(const AbcdeHubPage()));
      await settle(tester);
      final rows = find.byType(GuidePastelRow);
      expect(rows, findsNWidgets(5));
      for (final l in ['A', 'B', 'C', 'D', 'E']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(find.text('Association'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      expect(find.text('Chanting'), findsOneWidget);
      expect(find.text('Devotional service'), findsOneWidget);
      expect(find.text('Expeditions'), findsOneWidget);
      expect(find.textContaining('Meetings, requests and counter-proposals'), findsOneWidget);
      expect(find.textContaining('The five limbs of practice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rows use sand, slate, sage, clay, mauve; the dark theme uses the deeper ABCDE set', (tester) async {
      for (final dark in [false, true]) {
        phone(tester, 1.0);
        await tester.pumpWidget(guideHost(const AbcdeHubPage(), dark: dark));
        await settle(tester);
        final g = dark ? GuideColors.dark : GuideColors.light;
        final expected = [GuidePastel.sand, GuidePastel.slate, GuidePastel.sage, GuidePastel.clay, GuidePastel.mauve];
        final boxes = tester.widgetList<GuidePastelBox>(find.byType(GuidePastelBox)).toList();
        expect(boxes.map((b) => b.pastel), expected);
        for (final b in boxes) {
          expect(b.abcde, isTrue);
        }
        final first = tester.widget<Container>(find
            .descendant(of: find.byType(GuidePastelBox).first, matching: find.byType(Container))
            .first);
        final colours = ((first.decoration as BoxDecoration).gradient as LinearGradient).colors;
        expect(colours, g.pastel(GuidePastel.sand, abcde: true).colors);
        await tester.pumpWidget(const SizedBox());
      }
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: no overflow, rows are 48 dp or taller', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(guideHost(const AbcdeHubPage(), dark: dark));
          await settle(tester);
          expect(tester.takeException(), isNull);
          for (final r in tester.widgetList(find.byType(GuidePastelRow)).map((w) => tester.getRect(find.byWidget(w)))) {
            expect(r.height, greaterThanOrEqualTo(48));
            expect(r.right, lessThanOrEqualTo(360));
          }
        });
      }
    }
  });

  // ------------------------------------------------------------- Analysis tab
  testWidgets('Analysis: the four tiles, two per row, 150 dp or taller, each a pastel', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(guideHost(Scaffold(body: CompetitionPage())));
    await settle(tester);
    final tiles = find.byType(GuideGradientTile);
    expect(tiles, findsNWidgets(4));
    final rects = [for (var i = 0; i < 4; i++) tester.getRect(tiles.at(i))];
    expect(rects[0].top, rects[1].top);
    expect(rects[2].top, rects[3].top);
    expect(rects[2].top, greaterThan(rects[0].bottom));
    for (final r in rects) {
      expect(r.height, greaterThanOrEqualTo(160));
    }
    expect(find.text('INSIGHTS'), findsOneWidget);
    expect(find.text('Folk analysis'), findsOneWidget);
  });

  // ----------------------------------------------------------------- Tasks tab
  testWidgets('Tasks: Add student, Submissions, Add admin, Notifications (150 dp tiles)', (tester) async {
    phone(tester, 1.0);
    AdminProfileProvider.instance.debugSet(profile('GUIDE'));
    await tester.pumpWidget(guideHost(const Scaffold(body: AdminControlPage())));
    await settle(tester);
    expect(find.byType(GuideGradientTile), findsNWidgets(4));
    for (final l in ['Add student', 'Submissions', 'Add admin', 'Notifications']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.text('MANAGE'), findsOneWidget);
    expect(find.text('Other tasks'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(tester.getRect(find.byType(GuideGradientTile).at(i)).height, greaterThanOrEqualTo(150));
    }
  });

  // ---------------------------------------------------------------- This Week
  group('This Week', () {
    final today = DateTime.now();
    List<Map<String, dynamic>> logs() => [
          {
            'status': 'approved',
            'studentName': 'Arjun',
            'approvedSummary': {
              'followUpDate': Timestamp.fromDate(DateTime(today.year, today.month, today.day, 12)),
              'recommendedNextAction': 'Call about the retreat',
            },
          },
          {'status': 'pending', 'studentName': 'Ignored'},
        ];
    List<Map<String, dynamic>> assocs() => [
          {
            'status': 'pending',
            'studentName': 'Bhima',
            'preferredDate': Timestamp.fromDate(today.subtract(const Duration(days: 3))),
          },
          {
            'status': 'pending',
            'studentName': 'Chaitanya',
            'preferredDate': Timestamp.fromDate(today.subtract(const Duration(days: 1))),
          },
        ];

    Future<void> openWeek(WidgetTester tester, {FakeWeekData? data, String role = 'GUIDE', double scale = 1.0, bool dark = false}) async {
      phone(tester, scale);
      AdminProfileProvider.instance.debugSet(profile(role));
      WeekData.instance = data ??
          FakeWeekData(
            logs: logs(),
            assocs: assocs(),
            targetList: [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)],
            eventList: [
              CalendarEvent(
                id: 'e', eventDate: today, endDate: null, type: 'exam', title: 'Midterm',
                note: 'Bring ID', sourceTextBlockId: '', scope: 'mandatory', ownerGuideId: null, notifyOffsets: const [],
              ),
            ],
          );
      await tester.pumpWidget(guideHost(const WeeklyPlanningPage(), dark: dark));
      await settle(tester);
    }

    testWidgets('a navy hero with the week range, then four expandable cards with count badges', (tester) async {
      await openWeek(tester);
      expect(find.text('This Week'), findsOneWidget);
      expect(find.textContaining('Your students · G'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Your targets this week'), findsOneWidget);
      expect(find.text('Follow-ups due'), findsOneWidget);
      expect(find.text('Overdue meetings'), findsOneWidget);
      // counts: calendar 1, targets 2, follow-ups 1, overdue 2
      expect(find.text('2'), findsNWidgets(2));
      expect(find.text('1'), findsNWidgets(2));
      // the calendar card starts open, the others closed
      expect(find.text('Midterm'), findsOneWidget);
      expect(find.text('Call about the retreat'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a card opens it: follow-up, overdue list with days, and the hand-off button', (tester) async {
      await openWeek(tester);
      await tester.tap(find.text('Follow-ups due'));
      await tester.pumpAndSettle();
      expect(find.text('Arjun'), findsOneWidget);
      expect(find.text('Call about the retreat'), findsOneWidget);
      expect(find.text('Ignored'), findsNothing);
      await tester.tap(find.text('Overdue meetings'));
      await tester.pumpAndSettle();
      expect(find.text('Bhima'), findsOneWidget);
      expect(find.text('3 days'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
      expect(find.text('Open Overdue Associations'), findsOneWidget);
    });

    testWidgets('a target opens to its per-task checklist with live progress', (tester) async {
      await openWeek(tester);
      await tester.tap(find.text('Your targets this week'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Phase 1'), findsWidgets);
      await tester.tap(find.textContaining('Phase 1').first);
      await tester.pumpAndSettle();
      expect(find.text('Bring roster from 6 to 8 students'), findsWidgets);
      expect(find.text('Move Ravi and Om from 2 to 4 rounds'), findsWidgets);
      expect(find.text('8/8'), findsWidgets);
      expect(find.text('1/2'), findsWidgets);
      expect(find.text('Open full page'), findsWidgets);
    });

    testWidgets('empty cards say so: nothing scheduled / nothing overdue; no targets or events = no card', (tester) async {
      await openWeek(tester, data: FakeWeekData());
      expect(find.text('Your targets this week'), findsNothing);
      expect(find.text('Calendar'), findsNothing);
      await tester.tap(find.text('Follow-ups due'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing scheduled this week'), findsOneWidget);
      await tester.tap(find.text('Overdue meetings'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing overdue'), findsOneWidget);
    });

    testWidgets('the HOD sees "All guides (HOD view)"', (tester) async {
      await openWeek(tester, role: 'HOD');
      expect(find.text('All guides (HOD view)'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: no overflow with everything open', (tester) async {
          await openWeek(tester, scale: scale, dark: dark);
          expect(tester.getRect(find.byType(GuideHeroPanel)).right, lessThanOrEqualTo(360));
          for (final title in ['Follow-ups due', 'Overdue meetings', 'Your targets this week']) {
            await tester.ensureVisible(find.text(title));
            await tester.tap(find.text(title));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('screenshots: This Week light and dark (for looking at)', (tester) async {
      for (final dark in [false, true]) {
        phone(tester, 1.0, size: const Size(390, 844));
        AdminProfileProvider.instance.debugSet(profile('GUIDE'));
        WeekData.instance = FakeWeekData(
            logs: logs(),
            assocs: assocs(),
            targetList: [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)]);
        await tester.pumpWidget(guideHost(const WeeklyPlanningPage(), dark: dark));
        await settle(tester);
        await tester.tap(find.text('Your targets this week'));
        await tester.pumpAndSettle();
        await shot(tester, 'week_${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  // ------------------------------------------------------------------ Targets
  group('Your targets', () {
    Future<void> openTargets(WidgetTester tester, List<CompoundTarget> list, {String role = 'GUIDE', double scale = 1.0, bool dark = false}) async {
      phone(tester, scale);
      AdminProfileProvider.instance.debugSet(profile(role));
      GoalData.instance = FakeGoalData(list);
      await tester.pumpWidget(guideHost(const GoalHomePage(guideId: 'G'), dark: dark));
      await settle(tester);
    }

    testWidgets('a card per target: title, "N students at V", phase, percent, progress, two buttons; New target pinned', (tester) async {
      await openTargets(tester, [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)]);
      expect(find.text('Your targets'), findsOneWidget);
      expect(find.textContaining('10 students at 16'), findsOneWidget);
      expect(find.textContaining('10 students at 5'), findsOneWidget);
      expect(find.text('Phase 1 of 8'), findsOneWidget);
      expect(find.text('Phase 2 of 8'), findsOneWidget);
      expect(find.text('13%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('This week'), findsNWidgets(2));
      expect(find.text('Progress'), findsNWidgets(2));
      expect(find.text('New target'), findsOneWidget);
      // New target is pinned below the list, full width
      final button = tester.getRect(find.text('New target'));
      expect(button.bottom, greaterThan(700));
      expect(find.byTooltip("Review guides' targets"), findsNothing, reason: 'HOD only');
    });

    testWidgets('the HOD also gets the review button', (tester) async {
      await openTargets(tester, [target('chanting', 10, 16, 1, 8)], role: 'HOD');
      expect(find.byTooltip("Review guides' targets"), findsOneWidget);
    });

    testWidgets('no targets: the explanation; a plan that failed: retry', (tester) async {
      await openTargets(tester, const []);
      expect(find.textContaining('No active targets yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await openTargets(tester, [target('chanting', 10, 16, 0, 0)]);
      expect(find.textContaining("generation didn't complete"), findsOneWidget);
      expect(find.text('Retry plan generation'), findsOneWidget);
      expect(find.text('This week'), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: no overflow, buttons 42 dp or taller', (tester) async {
          await openTargets(tester, [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)], scale: scale, dark: dark);
          expect(tester.takeException(), isNull);
          for (final f in [find.text('This week'), find.text('Progress'), find.text('New target')]) {
            for (final e in f.evaluate()) {
              final r = tester.getRect(find.byWidget(e.widget));
              expect(r.right, lessThanOrEqualTo(360));
            }
          }
        });
      }
    }

    testWidgets('screenshots: targets light and dark (for looking at)', (tester) async {
      for (final dark in [false, true]) {
        phone(tester, 1.0, size: const Size(390, 844));
        AdminProfileProvider.instance.debugSet(profile('GUIDE'));
        GoalData.instance = FakeGoalData([target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)]);
        await tester.pumpWidget(guideHost(const GoalHomePage(guideId: 'G'), dark: dark));
        await settle(tester);
        await shot(tester, 'targets_${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
