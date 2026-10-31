import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/PlanToday.dart';
import 'package:folk_guide_app/utils/PlanTopicActions.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

// A TARGET'S END DATE HAS BEEN REACHED: Today shows "Target ended" (or "Target achieved 🎉") in Target tasks, with how it ended and two buttons: Delete target (after a confirmation) and
// Extend end date (a new end date; the target continues and a new plan is made at once). The server side is functions/test/targetEnded.test.js.

PlanItem ended({bool achieved = false, bool done = false}) => PlanItem(
      id: 'target_ended:G:tg1',
      kind: 'targetEnded',
      title: achieved ? 'Target achieved 🎉' : 'Target ended: your chanting target',
      detail: achieved
          ? 'Reached 5 of 5 boys at 16 rounds. Congratulations! It ended on Mon 19 Oct: delete it, or extend its end date to keep going.'
          : 'Reached 3 of 5 boys at 16 rounds. It ended on Mon 19 Oct: delete it, or extend its end date to keep going.',
      targetId: 'tg1',
      achieved: achieved,
      result: achieved ? 'Reached 5 of 5 boys at 16 rounds' : 'Reached 3 of 5 boys at 16 rounds',
      done: done,
    );

class _Fake extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
}

AdminProfile _me() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

Future<void> _open(WidgetTester tester, PlanItem item) async {
  AdminProfileProvider.instance.debugSet(_me());
  final data = _Fake();
  PlanData.instance = data;
  await pumpScreen(tester, const PlanPage(), size: const Size(360, 4000));
  data.controller.add(planDoc(today: [item], left: 0));
  await tester.pump();
  await tester.pump();
  await tester.tap(find.byKey(ValueKey('plan-row-${item.id}')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final deleted = <List<String>>[];
  final extended = <List<Object>>[];
  var failDelete = false;
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  setUp(() {
    deleted.clear();
    extended.clear();
    failDelete = false;
    laterClock = () => DateTime(2026, 10, 30, 10);
    TargetEndActions.instance = TargetEndActions(
      delete: (g, t) async {
        if (failDelete) throw StateError('down');
        deleted.add([g, t]);
      },
      extend: (g, t, d, note) async => extended.add([g, t, d, note]),
    );
  });
  tearDown(() {
    debugEndDatePicker = null;
  });
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  test('it is a task in TARGET TASKS, counted like the others, and not a student card', () {
    final plan = planDoc(today: [ended()], left: 0);
    final v = TodayView.of(plan);
    expect(v.section(kSectionTargets).tasks.map((t) => t.id), ['target_ended:G:tg1']);
    expect(v.total, 1);
    expect(ended().isCard, isFalse);
    expect(isEndedTarget(ended()), isTrue);
    expect(isEndedTarget(ended(done: true)), isFalse);
  });

  testWidgets('THE TOPIC: its title, how it ended, and the two buttons (48 dp): Delete target and Extend end date', (tester) async {
    await prepareApp(tester);
    await _open(tester, ended());
    expect(find.text('Target ended: your chanting target'), findsOneWidget);
    expect(find.textContaining('Reached 3 of 5 boys at 16 rounds'), findsOneWidget);
    for (final k in ['delete', 'extend']) {
      expect(find.byKey(ValueKey('plan-target-$k-target_ended:G:tg1')), findsOneWidget, reason: k);
      expect(tester.getSize(find.byKey(ValueKey('plan-target-$k-target_ended:G:tg1'))).height, greaterThanOrEqualTo(48));
    }
    expect(find.text('Delete target'), findsOneWidget);
    expect(find.text('Extend end date'), findsOneWidget);
  });

  testWidgets('THE GOAL WAS REACHED: "Target achieved 🎉" with the same two buttons', (tester) async {
    await prepareApp(tester);
    await _open(tester, ended(achieved: true));
    expect(find.text('Target achieved 🎉'), findsOneWidget);
    expect(find.textContaining('Congratulations!'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-target-delete-target_ended:G:tg1')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-target-extend-target_ended:G:tg1')), findsOneWidget);
  });

  testWidgets('DELETE TARGET asks first: Keep it deletes nothing; Delete target deletes THIS target of THIS guide', (tester) async {
    await prepareApp(tester);
    await _open(tester, ended());
    await tester.tap(find.byKey(const ValueKey('plan-target-delete-target_ended:G:tg1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('target-delete-title')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('target-delete-no')));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty, reason: 'Keep it');
    await tester.tap(find.byKey(const ValueKey('plan-target-delete-target_ended:G:tg1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('target-delete-yes')));
    await tester.pumpAndSettle();
    expect(deleted, [
      ['G', 'tg1']
    ]);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('A FAILED DELETE says so and throws nothing', (tester) async {
    await prepareApp(tester);
    failDelete = true;
    await _open(tester, ended());
    await tester.tap(find.byKey(const ValueKey('plan-target-delete-target_ended:G:tg1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('target-delete-yes')));
    await tester.pumpAndSettle();
    expect(find.text('Could not delete the target'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('EXTEND END DATE: the chosen date goes with the target; the new plan is asked for in the same step; no date, nothing happens', (tester) async {
    await prepareApp(tester);
    await _open(tester, ended());
    DateTime? firstOffered;
    debugEndDatePicker = (context, first) async {
      firstOffered = first;
      return null;
    };
    await tester.tap(find.byKey(const ValueKey('plan-target-extend-target_ended:G:tg1')));
    await tester.pumpAndSettle();
    expect(firstOffered, DateTime(2026, 10, 31), reason: 'only a day after today can be chosen');
    expect(extended, isEmpty, reason: 'cancelled');
    debugEndDatePicker = (context, first) async => DateTime(2026, 11, 30);
    await tester.tap(find.byKey(const ValueKey('plan-target-extend-target_ended:G:tg1')));
    await tester.pumpAndSettle();
    expect(extended, hasLength(1));
    expect(extended.single.sublist(0, 3), ['G', 'tg1', DateTime(2026, 11, 30)]);
    expect(extended.single[3].toString(), contains('30 Nov 2026'), reason: 'the plan note says what changed');
    expect(find.textContaining('Target extended to 30 Nov 2026'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('text $scale on a 360 dp phone: the topic and its buttons fit', (tester) async {
      await prepareApp(tester);
      phone(tester, scale);
      await _open(tester, ended(achieved: true));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('plan-target-extend-target_ended:G:tg1')), findsOneWidget);
    });
  }
}
