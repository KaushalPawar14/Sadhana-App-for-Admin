import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/GoalSetup.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/GoalMetrics.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:provider/provider.dart';

import 'support/guide_test_support.dart';

/// THE THIRD TARGET: how many of a guide's BOYS live in FOLK by a chosen end date. Counted automatically from each boy's residence (the
/// server: `functions/goals.js`, tested there); a Female Enabler does not get it; one active per type, deletable like the others.

AdminProfile _me(String id, String role) => AdminProfile.fromMap({
      'id': id, 'displayName': '$id Das', 'role': role, 'teamGuide': '', 'email': '$id@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': [],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  group('the metrics', () {
    test('three kinds of target, FOLK residents among them', () {
      expect(kCompoundMetrics, [kMetricChanting, kMetricBooks, kMetricFolk]);
      expect(validCompoundMetric('folk'), isTrue);
      expect(validCompoundMetric('services'), isFalse);
      final m = goalMetricById(kMetricFolk)!;
      expect(m.label, 'FOLK residents');
      expect(m.unit, 'boys living in FOLK');
      expect(m.isLive, isTrue, reason: 'counted live from each boy\'s residence');
    });

    test('a Female Enabler does not get the FOLK-residents target; everyone else does', () {
      expect(compoundMetricsFor(_me('F', 'FEMALE_ENABLER')), [kMetricChanting, kMetricBooks]);
      for (final role in ['GUIDE', 'MALE_ENABLER', 'HOD']) {
        expect(compoundMetricsFor(_me('X', role)), [kMetricChanting, kMetricBooks, kMetricFolk], reason: role);
      }
    });

    test('the limit message for a second FOLK-residents target', () {
      expect(targetLimitMessage('folk'), 'Delete your current FOLK-residents target first');
      expect(targetLimitMessage('books'), 'Delete your current book reading target first');
      expect(targetLimitMessage('chanting'), 'Delete your current chanting target first');
    });
  });

  group('the target document', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      db = FakeFirebaseFirestore();
      GuideDb.useForTests(db);
    });

    test('created with the number of boys as its goal, no per-student value (1), the end date, a DRAFT until its AI plan is written, no phases yet', () async {
      final id = await createCompoundTargetShell(guideId: 'G', metric: 'folk', studentCountGoal: 8, perStudentValueGoal: 1, endDate: DateTime(2026, 12, 20));
      final d = (await db.collection('guideTargets').doc('G').collection('targets').doc(id).get()).data()!;
      expect(d['metric'], 'folk');
      expect(d['studentCountGoal'], 8);
      expect(d['perStudentValueGoal'], 1);
      expect(d['status'], 'draft');
      expect(d['totalPhases'], 0);
      expect((d['endDate'] as Timestamp).toDate(), DateTime(2026, 12, 20));
    });

    test('one active target per type: a second FOLK-residents target is refused with its own words; the other types are unaffected', () async {
      final first = await createCompoundTargetShell(guideId: 'G', metric: 'folk', studentCountGoal: 8, perStudentValueGoal: 1, endDate: DateTime(2026, 12, 20));
      await db.collection('guideTargets').doc('G').collection('targets').doc(first).update({'status': 'active'}); // its plan was written
      await expectLater(
        createCompoundTargetShell(guideId: 'G', metric: 'folk', studentCountGoal: 3, perStudentValueGoal: 1, endDate: DateTime(2027, 1, 20)),
        throwsA(isA<CompoundTargetLimitException>()
            .having((e) => e.message, 'message', 'You already have a FOLK-residents target (8 boys living in FOLK, ends 20 Dec 2026). Open it or delete it first.')
            .having((e) => e.targetId, 'the target in the way', first)),
      );
      expect(await createCompoundTargetShell(guideId: 'G', metric: 'chanting', studentCountGoal: 5, perStudentValueGoal: 16, endDate: DateTime(2026, 12, 20)), isNotEmpty);
      expect(await createCompoundTargetShell(guideId: 'G', metric: 'books', studentCountGoal: 5, perStudentValueGoal: 2, endDate: DateTime(2026, 12, 20)), isNotEmpty);
    });

    test('after it is abandoned (deleted), a new one may be set', () async {
      final id = await createCompoundTargetShell(guideId: 'G', metric: 'folk', studentCountGoal: 8, perStudentValueGoal: 1, endDate: DateTime(2026, 12, 20));
      await abandonCompoundTarget('G', id);
      expect(await createCompoundTargetShell(guideId: 'G', metric: 'folk', studentCountGoal: 5, perStudentValueGoal: 1, endDate: DateTime(2027, 1, 20)), isNotEmpty);
    });

    test('an unknown metric is refused', () async {
      await expectLater(createCompoundTargetShell(guideId: 'G', metric: 'services', studentCountGoal: 1, perStudentValueGoal: 1, endDate: DateTime(2027, 1, 1)), throwsArgumentError);
    });
  });

  group('the tasks of a FOLK-residents plan', () {
    test('a roster-style task marked folk reads as "the boys living in FOLK", never "roster students"', () {
      final t = CompoundTask.from({'type': 'roster', 'folk': true, 'fromCount': 2, 'toCount': 4})!;
      expect(t.isFolk, isTrue);
      expect(t.describe('boys living in FOLK'), 'Bring the boys living in FOLK from 2 to 4');
      expect(t.toMap(), {'type': 'roster', 'fromCount': 2, 'toCount': 4, 'folk': true});
      final ordinary = CompoundTask.from({'type': 'roster', 'fromCount': 2, 'toCount': 4})!;
      expect(ordinary.isFolk, isFalse);
      expect(ordinary.describe('rounds'), 'Bring roster from 2 to 4 students');
    });
  });

  group('the create flow', () {
    Future<void> open(WidgetTester tester, AdminProfile me, {double scale = 1.0, bool dark = false, String? initial}) async {
      GuideDb.useForTests(FakeFirebaseFirestore());
      phone(tester, scale);
      AdminProfileProvider.instance.debugSet(me);
      await tester.pumpWidget(ChangeNotifierProvider<ColorProvider>(
        create: (_) => ColorProvider(),
        child: guideHost(CompoundGoalSetupPage(guideId: me.id, initialMetric: initial), dark: dark),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a Guide chooses between three metrics; a Female Enabler between two', (tester) async {
      await open(tester, _me('G', 'GUIDE'));
      expect(find.text('Chanting rounds'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      expect(find.text('FOLK residents'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open(tester, _me('F', 'FEMALE_ENABLER'));
      expect(find.text('FOLK residents'), findsNothing);
      expect(find.text('Chanting rounds'), findsOneWidget);
    });

    testWidgets('choosing FOLK residents asks only how many of the boys and by when; the per-student value is gone', (tester) async {
      await open(tester, _me('G', 'GUIDE'));
      expect(find.text('At what value, each'), findsOneWidget);
      await tester.tap(find.text('FOLK residents'));
      await tester.pump();
      expect(find.text('How many of your boys live in FOLK'), findsOneWidget);
      expect(find.text('At what value, each'), findsNothing);
      expect(find.textContaining('Counted automatically from each boy'), findsOneWidget);
      await tester.tap(find.text('Chanting rounds'));
      await tester.pump();
      expect(find.text('At what value, each'), findsOneWidget, reason: 'the other types keep it');
    });

    testWidgets('it can open already on FOLK residents (the Home card does that when it is the one missing)', (tester) async {
      await open(tester, _me('G', 'GUIDE'), initial: 'folk');
      expect(find.text('How many of your boys live in FOLK'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: the FOLK form fits', (tester) async {
          await open(tester, _me('G', 'GUIDE'), scale: scale, dark: dark, initial: 'folk');
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(find.text('Generate phase plan'), 200, scrollable: find.byType(Scrollable).first);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
