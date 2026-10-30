import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/PlanBlocks.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// THIS WEEK, in the same visual language as Today: the totals line, then three BLOCKS separated by dividers (Interactions day by day with the names, their
/// small % and the done ones ticked; Target tasks with each student's step and the roster tasks; Other tasks with their dates). No advice text. A tap on a
/// name goes to that student's card in Today.

class _FakePlanData extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PendingChanges> pending(String adminId) => const Stream.empty();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => DateTime.utc(2026, 10, 30, 4, 30);
}

PlanItem _person(String uid, String name, String day, {bool done = false, int? percent}) =>
    PlanItem(id: 'interaction:$uid:$day', kind: 'interaction', title: 'Interaction with $name', studentName: name, studentUid: uid, scheduledFor: day, percent: percent, done: done);

PlanDoc _doc({required List<PlanItem> today}) => PlanDoc(
      todayDate: '2026-10-30',
      todayItems: today,
      weekOf: '2026-10-27',
      intro: '',
      sections: [
        PlanSection(id: 'interactions', title: 'Interactions', items: [
          _person('u1', 'Ravi', '2026-10-30', percent: 42, done: true),
          _person('u2', 'Amit', '2026-10-30', percent: 18),
          _person('u3', 'Mohit', '2026-10-31', percent: 60),
        ]),
        const PlanSection(id: 'targettasks', title: 'Target tasks', items: [
          PlanItem(id: 'weektarget:t1', kind: 'weekTask', title: 'Chanting 16 by 30 Nov', steps: [PlanStep(name: 'Testing', from: 12, to: 16), PlanStep(name: 'Amit', from: 8, to: 12, done: true)]),
          PlanItem(id: 'target_task:G:roster', kind: 'weekTask', title: 'Bring students 2 → 5'),
        ]),
        const PlanSection(id: 'othertasks', title: 'Other tasks', items: [
          PlanItem(id: 'weekmeet:a1', kind: 'weekOther', title: 'Meeting: Harsh', scheduledFor: '2026-10-31'),
          PlanItem(id: 'weekev:e1', kind: 'weekOther', title: 'Trip: Dwarka', scheduledFor: '2026-11-01'),
        ]),
      ],
      generatedAt: DateTime.utc(2026, 10, 30, 4, 10),
      status: 'upToDate',
      changedAt: DateTime.utc(2026, 10, 30, 4, 10),
      progress: const PlanProgress(needed: 3, done: 1, left: 2, summary: '', bySource: []),
    );

Future<_FakePlanData> _open(WidgetTester tester, PlanDoc doc, {double scale = 1.0, bool dark = false, Size size = const Size(360, 3000)}) async {
  AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []}));
  final data = _FakePlanData();
  PlanData.instance = data;
  await pumpScreen(tester, const PlanPage(initialWeek: true), scale: scale, dark: dark, size: size);
  data.controller.add(doc);
  await tester.pump();
  await tester.pump();
  return data;
}

double _y(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  testWidgets('THE TOP: "Interactions this week: N · Done D · Left L", then three blocks in order with dividers and their counts', (tester) async {
    await _open(tester, _doc(today: const []));
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-progress-summary'))).data, 'Interactions this week: 3 · Done 1 · Left 2');
    final ys = ['week-interactions', 'week-targettasks', 'week-othertasks'].map((id) => _y(tester, find.byKey(ValueKey('plan-section-$id')))).toList();
    expect(ys, [...ys]..sort());
    expect(find.byType(PlanBlockDivider), findsNWidgets(2));
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-section-count-week-interactions'))).data, '1/3');
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-section-count-week-targettasks'))).data, '0/2');
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-section-count-week-othertasks'))).data, '2');
    expect(find.text('Interactions'), findsOneWidget);
    expect(find.text('Target tasks'), findsOneWidget);
    expect(find.text('Other tasks'), findsOneWidget);
  });

  testWidgets('INTERACTIONS day by day: "Thu 30 Oct" then "Fri 31 Oct", the names with their small %, the done ones ticked and struck through', (tester) async {
    await _open(tester, _doc(today: const []));
    expect(find.text('Fri 30 Oct'), findsOneWidget);
    expect(find.text('Sat 31 Oct'), findsWidgets);
    expect(_y(tester, find.text('Fri 30 Oct')), lessThan(_y(tester, find.text('Sat 31 Oct').first)));
    for (final n in ['Ravi', 'Amit', 'Mohit']) {
      expect(find.byKey(ValueKey('plan-week-name-${{'Ravi': 'u1', 'Amit': 'u2', 'Mohit': 'u3'}[n]}')), findsOneWidget, reason: n);
    }
    expect(find.text('42%'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-week-tick-u1')), findsOneWidget, reason: 'Ravi is done');
    expect(find.byKey(const ValueKey('plan-week-tick-u2')), findsNothing);
    expect(tester.widget<Text>(find.text('Ravi')).style!.decoration, TextDecoration.lineThrough);
  });

  testWidgets('TARGET TASKS: each target with its students\' steps (done ones ticked) and the roster task live here', (tester) async {
    await _open(tester, _doc(today: const []));
    expect(find.text('Chanting 16 by 30 Nov'), findsOneWidget);
    expect(find.text('Testing 12 → 16'), findsOneWidget);
    expect(find.text('Amit 8 → 12'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Amit 8 → 12')).style!.decoration, TextDecoration.lineThrough, reason: 'the done step');
    expect(find.text('Bring students 2 → 5'), findsOneWidget, reason: 'roster / recruiting tasks are This week only');
    expect(find.descendant(of: find.byKey(const ValueKey('plan-section-body-week-targettasks')), matching: find.text('Bring students 2 → 5')), findsOneWidget);
  });

  testWidgets('OTHER TASKS: meetings, trips, competitions, book deadlines, each with its date; no advice text anywhere', (tester) async {
    await _open(tester, _doc(today: const []));
    expect(find.text('Meeting: Harsh'), findsOneWidget);
    expect(find.text('Trip: Dwarka'), findsOneWidget);
    expect(find.text('Sat 31 Oct'), findsWidgets);
    expect(find.text('Sun 1 Nov'), findsOneWidget);
    for (final advice in ['Advice', 'Suggestion', 'Why:', 'Encourage', 'Questions and suggestions']) {
      expect(find.textContaining(advice), findsNothing, reason: advice);
    }
  });

  testWidgets('A TAP ON A NAME goes to that student\'s card in Today, open', (tester) async {
    final card = PlanItem(
      id: 'interaction:u2:2026-10-30',
      kind: 'interaction',
      title: 'Interaction with Amit',
      studentName: 'Amit',
      studentUid: 'u2',
      percent: 18,
      points: const [PlanPoint(kind: 'concern', title: 'Worry', text: 'Sounded discouraged', group: PlanGroup.worry)],
      cardGroups: const [PlanGroup.worry],
    );
    await _open(tester, _doc(today: [card]));
    await tester.tap(find.byKey(const ValueKey('plan-week-name-u2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-summary')), findsOneWidget, reason: 'Today is showing');
    expect(find.byKey(const ValueKey('plan-row-body-interaction:u2:2026-10-30')), findsOneWidget, reason: 'his row is open');
    expect(find.byKey(const ValueKey('plan-point-interaction:u2:2026-10-30-0')), findsOneWidget);
  });

  testWidgets('BLOCKS COLLAPSE AND OPEN with a tap on the header; an empty block says "Nothing here this week"', (tester) async {
    await _open(tester, _doc(today: const []).copyEmptyTargets());
    expect(find.byKey(const ValueKey('plan-section-empty-week-targettasks')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-section-empty-week-targettasks'))).data, 'Nothing here this week');
    await tester.tap(find.byKey(const ValueKey('plan-section-week-interactions')));
    await tester.pumpAndSettle();
    expect(find.text('Amit'), findsNothing, reason: 'collapsed');
    await tester.tap(find.byKey(const ValueKey('plan-section-week-interactions')));
    await tester.pumpAndSettle();
    expect(find.text('Amit'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on a phone and a website width: no overflow, headers 48 dp', (tester) async {
        for (final size in [const Size(360, 3600), const Size(1100, 2400)]) {
          await _open(tester, _doc(today: const []), scale: scale, dark: dark, size: size);
          expect(tester.takeException(), isNull, reason: '$size');
          for (final id in ['week-interactions', 'week-targettasks', 'week-othertasks']) {
            expect(tester.getSize(find.byKey(ValueKey('plan-section-$id'))).height, greaterThanOrEqualTo(48), reason: id);
            expect(tester.getRect(find.byKey(ValueKey('plan-section-$id'))).right, lessThanOrEqualTo(size.width + .5), reason: id);
          }
        }
      });
    }
  }
}

extension on PlanDoc {
  PlanDoc copyEmptyTargets() => PlanDoc(
        todayDate: todayDate,
        todayItems: todayItems,
        weekOf: weekOf,
        intro: intro,
        sections: [for (final s in sections) s.id == 'targettasks' ? PlanSection(id: s.id, title: s.title, items: const []) : s],
        generatedAt: generatedAt,
        status: status,
        changedAt: changedAt,
        progress: progress,
      );
}
