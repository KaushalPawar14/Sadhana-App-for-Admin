import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PriorityStudents.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// UNASSIGNED students' tasks are the owning HOD's alone: their interactions needed are not in a Guide's or an Enabler's list. They still see him on the board
// (and may claim him); the moment he is claimed his needs are in that guide's list.

const _admins = [
  {'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': ''},
  {'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': ''},
  {'id': 'M1', 'displayName': 'Madhava Das', 'role': 'MALE_ENABLER', 'teamGuide': 'G'},
  {'id': 'F1', 'displayName': 'Radha Devi', 'role': 'FEMALE_ENABLER', 'teamGuide': ''},
];

AdminProfile profileOf(String id) {
  final a = _admins.firstWhere((x) => x['id'] == id);
  return AdminProfile.fromMap({
    'id': id,
    'displayName': a['displayName'],
    'role': a['role'],
    'teamGuide': a['teamGuide'],
    'email': '${id.toLowerCase()}@x.org',
    'notificationPrefs': {},
    'notificationTypes': [],
    'admins': _admins,
  });
}

Future<void> needs(FakeFirebaseFirestore db, String uid) async {
  final u = (await db.collection('users').doc(uid).get()).data()!;
  await db.collection('interactionNeeds').doc(uid).set({
    'studentUid': uid,
    'studentName': u['name'],
    'guideId': u['guideId'],
    'scopeGuide': u['guideId'],
    'scopeTeam': u['teamGuide'],
    'scopeGender': u['gender'],
    'needs': [
      {'key': 'sadhana_slip', 'source': 'sadhana', 'topic': 'sadhana_slip', 'text': 'Not fulfilling his commitments for 3 days', 'urgency': 'today', 'since': 1}
    ],
    'updatedAt': Timestamp.now(),
    'changedAt': Timestamp.now(),
  });
}

Future<FakeFirebaseFirestore> open(WidgetTester tester, String who, {Future<void> Function(FakeFirebaseFirestore db)? seed}) async {
  final db = await prepareApp(tester);
  for (final uid in ['s1', 's2', 's3', 's4', 's5', 's6']) {
    await needs(db, uid);
  }
  if (seed != null) await seed(db);
  AdminProfileProvider.instance.debugSet(profileOf(who));
  await pumpScreen(tester, const PriorityStudentsPage());
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await letDataArrive(tester, frames: 6);
  }
  return db;
}

// s4 = Dhruva Nair, the unassigned boy of the seeded world (app_harness); s1 / s2 are on G's team
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => loadGuideFonts());
  tearDown(() => AdminProfileProvider.instance.debugSet(null));

  testWidgets('a Guide does not have the unassigned boy in his Interactions needed (his own students are there)', (tester) async {
    await open(tester, 'G');
    expect(find.byKey(const ValueKey('priority-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('priority-s4')), findsNothing);
  });

  testWidgets('a Male Enabler does not have him either', (tester) async {
    await open(tester, 'M1');
    expect(find.byKey(const ValueKey('priority-s4')), findsNothing);
  });

  testWidgets('the HOD has him in the list', (tester) async {
    await open(tester, 'H');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('priority-s4')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('priority-s4')), findsOneWidget);
  });

  testWidgets('once a Guide has claimed him (the need document carries his new guide) he is in that Guide\'s list', (tester) async {
    await open(tester, 'G', seed: (db) async {
      await db.collection('users').doc('s4').update({'guideId': 'G', 'teamGuide': 'G'});
      await needs(db, 's4');
    });
    await tester.scrollUntilVisible(find.byKey(const ValueKey('priority-s4')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('priority-s4')), findsOneWidget);
  });
}
