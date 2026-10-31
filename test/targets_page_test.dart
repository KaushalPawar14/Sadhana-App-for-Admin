import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/CompoundGoalProgressPage.dart';
import 'package:folk_guide_app/Pages/GoalSetup.dart';
import 'package:folk_guide_app/Pages/TargetsPage.dart';
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/GoalMetrics.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/HomeData.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// THE TARGETS PAGE: big calm cards (CHANTING gold, READING sky blue, FOLK purple; FOLK not for a Female Enabler), each about half the screen tall, saying the goal and its end date (or "Not set"
// with "Set target"), how far it is, the phase, the students whose turn is next, and the state (Active / Ended — choose / Achieved 🎉); a tap opens the target or the create flow; one under another
// on a phone, side by side on the website; light and dark, text scale 1.0 / 1.3 / 1.6.

class _Home implements HomeData {
  _Home(this.list);
  final List<CompoundTarget> list;
  @override
  Stream<List<CompoundTarget>> targets(String guide) => Stream.value(list);
  @override
  Stream<int> studentCount() => Stream.value(0);
  @override
  Future<List<CalendarEvent>> events(String guide) async => const [];
  @override
  Widget calendarBadge({required Widget child}) => child;
}

class _Plan extends PlanData {
  _Plan(this.doc);
  final PlanDoc? doc;
  @override
  Stream<PlanDoc?> plan(String adminId) => Stream.value(doc);
}

CompoundTarget tg(String metric, {int students = 5, int value = 16, int phase = 2, int total = 4, String status = 'active', DateTime? end}) => CompoundTarget.from('G', 't$metric', {
      'metric': metric,
      'studentCountGoal': students,
      'perStudentValueGoal': value,
      'status': status,
      'currentPhase': phase,
      'totalPhases': total,
      'endDate': Timestamp.fromDate(end ?? DateTime(2026, 12, 31)),
    });

PlanDoc planWith(String title, List<String> labels) => PlanDoc(
      todayDate: '2026-10-30',
      todayItems: const [],
      weekOf: '2026-10-26',
      intro: '',
      sections: [
        PlanSection(id: 'targettasks', title: 'Target tasks', items: [
          PlanItem(id: 'weekjourney', kind: 'weekTask', title: title, steps: [for (final l in labels) PlanStep(name: l.split(' — ').first, from: 0, to: 0, label: l)]),
        ]),
      ],
      generatedAt: DateTime.utc(2026, 10, 30, 4),
      status: 'upToDate',
      changedAt: DateTime.utc(2026, 10, 30, 4),
    );

AdminProfile prof(String role) => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': role, 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

final _journey = planWith('Chanting 3 of 5 · Reading 2 of 4 · FOLK 1 of 3', [
  'Amit — 12 → 16 · invite to FOLK (direct)',
  'Bala — 📖 Gita (1 → 2) on track, due Mon 30 Nov',
  'Chet — 8 → 12',
  'Dev — invite to FOLK (gentle)',
]);

Future<void> open(WidgetTester tester, {List<CompoundTarget>? targets, PlanDoc? plan, String role = 'GUIDE', double scale = 1.0, bool dark = false, Size size = const Size(360, 800)}) async {
  AdminProfileProvider.instance.debugSet(prof(role));
  HomeData.instance = _Home(targets ?? [tg('chanting'), tg('books', value: 4), tg('folk', value: 0, total: 2)]);
  PlanData.instance = _Plan(plan ?? _journey);
  await pumpScreen(tester, const TargetsPage(guideId: 'G'), scale: scale, dark: dark, size: size);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    HomeData.instance = const FirestoreHomeData();
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  group('what a card says (from the target and the combined This-week line)', () {
    test('goal, progress, phase, next students and state', () {
      final cards = TargetCardData.allFrom([tg('chanting'), tg('books', value: 4), tg('folk', value: 0, total: 2)], _journey, const [kMetricChanting, kMetricBooks, kMetricFolk]);
      final c = cards[0];
      expect([c.goalWords, c.progressWords, c.phaseWords], ['16 rounds by 31 Dec', '3 of 5 boys at 16 rounds', 'Phase 2 of 4']);
      expect(c.next, ['Amit — 12 → 16 · invite to FOLK (direct)', 'Chet — 8 → 12'], reason: 'the chanting steps (not the book, not FOLK-only)');
      expect(cards[1].goalWords, '4 books by 31 Dec');
      expect(cards[1].progressWords, '2 of 4 students at 4 books');
      expect(cards[1].next, ['Bala — 📖 Gita (1 → 2) on track, due Mon 30 Nov']);
      expect(cards[2].goalWords, '5 FOLK residents by 31 Dec');
      expect(cards[2].progressWords, '1 of 3 boys living in FOLK');
      expect(cards[2].next, ['Amit — 12 → 16 · invite to FOLK (direct)', 'Dev — invite to FOLK (gentle)']);
      final today = DateTime(2026, 10, 30);
      expect(cards.map((x) => x.stateWords(today)), ['Active', 'Active', 'Active']);
    });

    test('states: not set, ended (choose), achieved', () {
      final today = DateTime(2026, 10, 30);
      final none = TargetCardData.allFrom(const [], null, const [kMetricChanting]).single;
      expect([none.isSet, none.stateWords(today), none.goalWords, none.progressWords], [false, 'Not set', null, null]);
      final ended = TargetCardData.allFrom([tg('chanting', end: DateTime(2026, 10, 30))], _journey, const [kMetricChanting]).single;
      expect(ended.stateWords(today), 'Ended — choose');
      expect(TargetCardData.allFrom([tg('chanting', end: DateTime(2026, 10, 31))], _journey, const [kMetricChanting]).single.stateWords(today), 'Active', reason: 'the end date has not been reached');
      final done = TargetCardData.allFrom([tg('chanting')], planWith('Chanting 5 of 5', const []), const [kMetricChanting]).single;
      expect(done.stateWords(today), 'Achieved 🎉');
      expect(TargetCardData.allFrom([tg('chanting', status: 'abandoned')], _journey, const [kMetricChanting]).single.isSet, isFalse, reason: 'an abandoned target does not count as set');
    });
  });

  testWidgets('the three cards, their colours, texts and the half-screen height (phone, light)', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('targets-list')), findsOneWidget);
    for (final m in [kMetricChanting, kMetricBooks, kMetricFolk]) {
      expect(find.byKey(ValueKey('target-card-$m')), findsOneWidget, reason: m);
    }
    expect([for (final m in [kMetricChanting, kMetricBooks, kMetricFolk]) tester.widget<Text>(find.byKey(ValueKey('target-title-$m'))).data], ['CHANTING', 'READING', 'FOLK']);
    expect(tester.widget<Text>(find.byKey(const ValueKey('target-goal-chanting'))).data, '16 rounds by 31 Dec');
    expect(tester.widget<Text>(find.byKey(const ValueKey('target-progress-chanting'))).data, '3 of 5 boys at 16 rounds');
    expect(tester.widget<Text>(find.byKey(const ValueKey('target-phase-chanting'))).data, 'Phase 2 of 4');
    expect(find.text('Amit — 12 → 16 · invite to FOLK (direct)'), findsNWidgets(2), reason: 'under chanting and under FOLK: the combined next step');
    expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('target-state-chanting')), matching: find.byType(Text))).data, 'Active');
    Gradient gradientOf(String m) => (tester.widget<Container>(find.descendant(of: find.byKey(ValueKey('target-card-$m')), matching: find.byType(Container)).first).decoration! as BoxDecoration).gradient!;
    expect((gradientOf('chanting') as LinearGradient).colors, GuideColors.targetGoldLight);
    expect((gradientOf('books') as LinearGradient).colors, GuideColors.targetSkyLight);
    expect((gradientOf('folk') as LinearGradient).colors, GuideColors.targetPurpleLight);
    // about half the screen tall, one under another, not full screen
    final sizes = [for (final m in [kMetricChanting, kMetricBooks, kMetricFolk]) tester.getSize(find.byKey(ValueKey('target-card-$m')))];
    for (final s in sizes) {
      expect(s.height, greaterThanOrEqualTo(400 - 1), reason: 'about half of an 800 dp screen');
      expect(s.height, lessThan(640), reason: 'not full screen');
      expect(s.width, closeTo(360 - 40, 1), reason: 'the width of the page');
    }
    final tops = [for (final m in [kMetricChanting, kMetricBooks, kMetricFolk]) tester.getTopLeft(find.byKey(ValueKey('target-card-$m'))).dy];
    expect(tops[0], lessThan(tops[1]));
    expect(tops[1], lessThan(tops[2]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme: the deep gradients with light text', (tester) async {
    await open(tester, dark: true);
    Gradient gradientOf(String m) => (tester.widget<Container>(find.descendant(of: find.byKey(ValueKey('target-card-$m')), matching: find.byType(Container)).first).decoration! as BoxDecoration).gradient!;
    expect((gradientOf('chanting') as LinearGradient).colors, GuideColors.targetGoldDark);
    expect((gradientOf('books') as LinearGradient).colors, GuideColors.targetSkyDark);
    expect((gradientOf('folk') as LinearGradient).colors, GuideColors.targetPurpleDark);
    expect(tester.widget<Text>(find.byKey(const ValueKey('target-goal-chanting'))).style!.color, GuideColors.targetCardTextDark);
  });

  testWidgets('a Female Enabler has no FOLK card', (tester) async {
    await open(tester, role: 'FEMALE_ENABLER', targets: [tg('chanting'), tg('books', value: 4)]);
    expect(find.byKey(const ValueKey('target-card-chanting')), findsOneWidget);
    expect(find.byKey(const ValueKey('target-card-books')), findsOneWidget);
    expect(find.byKey(const ValueKey('target-card-folk')), findsNothing);
  });

  testWidgets('NOT SET: "Not set" and Set target; ENDED: "Ended — choose"; ACHIEVED 🎉', (tester) async {
    await open(tester, targets: [tg('chanting', end: DateTime(2020, 1, 1)), tg('books', value: 4)], plan: planWith('Chanting 1 of 5 · Reading 4 of 4', const []));
    expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('target-state-chanting')), matching: find.byType(Text))).data, 'Ended — choose');
    expect(find.text('Choose: delete or extend'), findsOneWidget);
    expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('target-state-books')), matching: find.byType(Text))).data, 'Achieved 🎉');
    expect(tester.widget<Text>(find.byKey(const ValueKey('target-goal-folk'))).data, 'Not set');
    expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('target-state-folk')), matching: find.byType(Text))).data, 'Not set');
    expect(find.text('Set target'), findsOneWidget);
  });

  testWidgets('a tap opens the target when it is set, the create flow when it is not', (tester) async {
    GuideDb.useForTests(FakeFirebaseFirestore());
    addTearDown(() => GuideDb.useForTests(null));
    await open(tester, targets: [tg('chanting')]);
    await tester.ensureVisible(find.byKey(const ValueKey('target-card-folk')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('target-card-folk')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CompoundGoalSetupPage), findsOneWidget, reason: 'not set: the create flow (on FOLK)');
    expect(tester.widget<CompoundGoalSetupPage>(find.byType(CompoundGoalSetupPage)).initialMetric, kMetricFolk);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('target-card-chanting')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('target-card-chanting')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CompoundGoalProgressPage), findsOneWidget, reason: 'set: the target itself (where it is deleted or extended)');
  });

  testWidgets('THE WEBSITE: cards sit side by side in the content column, never wider than half of it', (tester) async {
    await open(tester, size: const Size(1280, 900));
    final a = tester.getRect(find.byKey(const ValueKey('target-card-chanting')));
    final b = tester.getRect(find.byKey(const ValueKey('target-card-books')));
    final c = tester.getRect(find.byKey(const ValueKey('target-card-folk')));
    expect(a.top, b.top, reason: 'two on a row');
    expect(c.top, greaterThan(a.top));
    expect(a.width, lessThanOrEqualTo((1080 - 12) / 2 + 1));
    expect(b.left - a.right, closeTo(12, 1), reason: 'the card gap');
    expect(a.height, greaterThanOrEqualTo(900 * .5 - 1));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      for (final wide in [false, true]) {
        testWidgets('${wide ? 'website 1280' : 'phone 360'}, ${dark ? 'dark' : 'light'}, text scale $scale: nothing overflows, the buttons are 48 dp targets', (tester) async {
          await open(tester, dark: dark, scale: scale, size: wide ? const Size(1280, 900) : const Size(360, 800));
          expect(tester.takeException(), isNull);
          for (final m in [kMetricChanting, kMetricBooks, kMetricFolk]) {
            await tester.ensureVisible(find.byKey(ValueKey('target-card-$m')));
            expect(tester.getSize(find.byKey(ValueKey('target-card-$m'))).height, greaterThanOrEqualTo(260));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('a failed load says so with Retry; the page is never blank', (tester) async {
    AdminProfileProvider.instance.debugSet(prof('GUIDE'));
    HomeData.instance = _Failing();
    PlanData.instance = _Plan(null);
    await pumpScreen(tester, const TargetsPage(guideId: 'G'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Could not load your targets'), findsOneWidget);
    expect(find.text('Retry'), findsWidgets);
  });
}

class _Failing extends _Home {
  _Failing() : super(const []);
  @override
  Stream<List<CompoundTarget>> targets(String guide) => Stream<List<CompoundTarget>>.error('boom');
}
