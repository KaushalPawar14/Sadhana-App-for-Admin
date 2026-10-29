import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PriorityStudents.dart';
import 'package:folk_guide_app/actions/PriorityActions.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// THE ORDER of the Interactions needed list: SURRENDER %, HIGHEST FIRST, the % beside each name; a worrying message from the AI chat stays at the
/// very top whatever the %; equal % -> the more urgent reasons first, then more reasons, then the name. (The server's plans use the same order:
/// functions/test/dailyBatch.test.js.)

PriorityFlag flag(String key) => (kind: key, label: key, tone: PriorityTone.warning);
PriorityStudent student(String name, int? percent, {List<String> keys = const ['sadhana_slip'], bool distress = false, bool acute = false}) =>
    (uid: name, name: name, flags: [for (final k in keys) flag(k)], percent: percent, distress: distress, acute: acute);
List<String> order(List<PriorityStudent> list) => ([...list]..sort(comparePriority)).map((s) => s.name).toList();

Map<String, dynamic> need(String source, String key, {Map<String, dynamic>? facts}) =>
    {'key': key, 'source': source, 'topic': key, 'text': 'Reason $key', 'urgency': 'today', 'since': 1, if (facts != null) 'facts': facts};

Future<void> needsDoc(FakeFirebaseFirestore db, String uid, int? percent, List<Map<String, dynamic>> list) async {
  final u = (await db.collection('users').doc(uid).get()).data()!;
  await db.collection('interactionNeeds').doc(uid).set({
    'studentUid': uid, 'studentName': u['name'], 'guideId': u['guideId'], 'scopeGuide': u['guideId'], 'scopeTeam': u['teamGuide'], 'scopeGender': u['gender'],
    'needs': list, if (percent != null) 'percent': percent, 'updatedAt': Timestamp.now(), 'changedAt': Timestamp.now(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() => AdminProfileProvider.instance.debugSet(null));

  group('the comparator', () {
    test('highest % first; no % yet is last', () {
      expect(order([student('A', 20), student('B', 85), student('C', null), student('D', 55)]), ['B', 'D', 'A', 'C']);
    });
    test('DISTRESS EXCEPTION: a worrying message stays at the very top whatever the %; an acute one above a pastoral one', () {
      expect(order([student('High', 95), student('Worried', 4, distress: true), student('Mid', 50)]), ['Worried', 'High', 'Mid']);
      expect(order([student('PastoralHigh', 90, distress: true), student('AcuteLow', 3, distress: true, acute: true), student('High', 99)]), ['AcuteLow', 'PastoralHigh', 'High']);
    });
    test('TIES: equal % -> the more urgent reasons first (doubt, slip, surrender step, target), then more reasons, then the name', () {
      expect(order([student('Zed', 40, keys: ['target_chanting_t']), student('Amy', 40), student('Bob', 40, keys: ['doubt_d1'])]), ['Bob', 'Amy', 'Zed']);
      expect(order([student('Zed', 40, keys: ['sadhana_slip', 'doubt_d1']), student('Amy', 40, keys: ['sadhana_slip'])]), ['Zed', 'Amy'], reason: 'doubt outranks slip');
      expect(order([student('Zed', 40, keys: ['sadhana_slip', 'surrender_x']), student('Amy', 40, keys: ['sadhana_slip'])]), ['Zed', 'Amy'], reason: 'more reasons');
      expect(order([student('Zed', 40), student('Amy', 40), student('Bob', 40)]), ['Amy', 'Bob', 'Zed'], reason: 'then by name');
    });
    test('the tiers mirror the server', () {
      expect([priorityTierOf('concern_c1'), priorityTierOf('doubt_d'), priorityTierOf('sadhana_slip'), priorityTierOf('reporting_habit'), priorityTierOf('surrender_thr_1'), priorityTierOf('target_books_t'), priorityTierOf('good_sadhana')],
          [0, 0.5, 2, 2, 3, 4, 5]);
    });
  });

  group('the Interactions needed screen', () {
    Future<FakeFirebaseFirestore> open(WidgetTester tester, Future<void> Function(FakeFirebaseFirestore) seed) async {
      final db = await prepareApp(tester);
      await seed(db);
      AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({
        'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': '', 'email': 'h@x.org', 'notificationPrefs': {}, 'notificationTypes': [],
        'admins': [{'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': ''}],
      }));
      await pumpScreen(tester, const PriorityStudentsPage(), size: const Size(360, 3000));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await letDataArrive(tester, frames: 6);
      }
      return db;
    }

    double top(WidgetTester tester, String uid) => tester.getTopLeft(find.byKey(ValueKey('priority-$uid'))).dy;

    testWidgets('sorted by Surrender %, the % beside every name, a worry on top, ties by urgency then name', (tester) async {
      await open(tester, (db) async {
        // s1 Arjun 30%, s2 Bhima 80%, s3 Chaitanya 55% with a worrying message, s4 Dhruva no % yet, s5 Gauri 55%, s6 (long name) 55% with a doubt
        await needsDoc(db, 's1', 30, [need('sadhana', 'sadhana_slip')]);
        await needsDoc(db, 's2', 80, [need('sadhana', 'sadhana_slip')]);
        await needsDoc(db, 's3', 55, [need('concern', 'concern_c1', facts: {'kind': 'pastoral'}), need('sadhana', 'sadhana_slip')]);
        await needsDoc(db, 's4', null, [need('sadhana', 'sadhana_slip')]);
        await needsDoc(db, 's6', 55, [need('doubt', 'doubt_d1')]);
      });
      // every card shows its % beside the name
      expect(tester.widget<Text>(find.byKey(const ValueKey('priority-name-s2'))).data, 'Bhima Sen · 80%');
      expect(tester.widget<Text>(find.byKey(const ValueKey('priority-name-s1'))).data, 'Arjun Kumar · 30%');
      expect(tester.widget<Text>(find.byKey(const ValueKey('priority-name-s4'))).data, 'Dhruva Nair', reason: 'no % yet: just the name');
      // the order: the worry (Chaitanya, 55%) on top; then 80, then 55 (a doubt), then 30; no % last
      final tops = {for (final u in ['s1', 's2', 's3', 's4', 's6']) u: top(tester, u)};
      final sorted = tops.keys.toList()..sort((a, b) => tops[a]!.compareTo(tops[b]!));
      expect(sorted, ['s3', 's2', 's6', 's1', 's4']);
    });

    testWidgets('an acute worry is above a pastoral one, both above a higher %', (tester) async {
      await open(tester, (db) async {
        await needsDoc(db, 's1', 99, [need('sadhana', 'sadhana_slip')]);
        await needsDoc(db, 's2', 40, [need('concern', 'concern_c1', facts: {'acute': false})]);
        await needsDoc(db, 's3', 2, [need('concern', 'concern_c2', facts: {'acute': true})]);
      });
      expect(top(tester, 's3'), lessThan(top(tester, 's2')));
      expect(top(tester, 's2'), lessThan(top(tester, 's1')));
    });
  });
}
