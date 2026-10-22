import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PriorityStudents.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// Priority students: long-press to select, remove from MY priority list. It writes one small record per student
// (priorityDismissals/{adminId}__{studentUid}) and never touches the student or anything about them.

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

// uid -> name, in the seeded world (app_harness): s1/s2/s6 on G's team, s3 is M1's (team G), s4 unassigned boy, s5 F1's girl
const names = {
  's1': 'Arjun Kumar',
  's2': 'Bhima Sen',
  's3': 'Chaitanya Das',
  's4': 'Dhruva Nair',
  's5': 'Gauri Devi',
};

Future<FakeFirebaseFirestore> open(WidgetTester tester, String who, {double scale = 1.0, bool dark = false, Future<void> Function(FakeFirebaseFirestore db)? seed}) async {
  final db = await prepareApp(tester);
  if (seed != null) await seed(db);
  AdminProfileProvider.instance.debugSet(profileOf(who));
  await pumpScreen(tester, const PriorityStudentsPage(), scale: scale, dark: dark);
  await settleLoad(tester);
  return db;
}

// The screen reads merged (Guide / Enabler) streams with `.first`; those only complete in real time, so give them
// a moment of it, then let the frames through.
Future<void> settleLoad(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await letDataArrive(tester, frames: 6);
  }
}

Future<void> hold(WidgetTester tester, String uid) async {
  final f = find.byKey(ValueKey('priority-$uid'));
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.pump();
  await tester.longPress(f);
  await letDataArrive(tester);
}

Future<void> tapCard(WidgetTester tester, String uid) async {
  final f = find.byKey(ValueKey('priority-$uid'));
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.pump();
  await tester.tap(f);
  await letDataArrive(tester);
}

/// Everything in the database except the removal records, as plain data, to prove nothing else is touched.
Future<Map<String, Object?>> everythingElse(FakeFirebaseFirestore db) async {
  final out = <String, Object?>{};
  for (final c in ['users', 'associations', 'interactionLogs', 'adminUsers', 'expeditions', 'litAssessments']) {
    final snap = await db.collection(c).get();
    out[c] = {for (final d in snap.docs) d.id: d.data().toString()};
  }
  return out;
}

Future<List<String>> dismissalIds(FakeFirebaseFirestore db) async =>
    ((await db.collection('priorityDismissals').get()).docs.map((d) => d.id).toList()..sort());

Future<void> top(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
  await settleLoad(tester);
}

List<String> listed() => [for (final n in names.values) if (find.text(n).evaluate().isNotEmpty) n];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  group('selecting', () {
    testWidgets('long-press starts selection; tap adds and removes; the cross cancels', (tester) async {
      await open(tester, 'H');
      expect(find.text('Priority Students'), findsOneWidget);
      expect(find.text('Press and hold a student to select, then remove from your list.'), findsOneWidget);
      await hold(tester, 's2');
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('remove-from-priority')), findsOneWidget);
      expect(find.text('Remove from priority list'), findsOneWidget);
      expect(find.text('Open profile'), findsNothing, reason: 'while selecting, a card is for selecting');
      await tapCard(tester, 's3');
      expect(find.text('2 selected'), findsOneWidget);
      await tapCard(tester, 's3');
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-selection')));
      await letDataArrive(tester);
      expect(find.text('Priority Students'), findsOneWidget);
      expect(find.byKey(const ValueKey('remove-from-priority')), findsNothing);
    });

    testWidgets('un-selecting the last student leaves selection mode only via the cross (the bar stays until then)', (tester) async {
      await open(tester, 'H');
      await hold(tester, 's2');
      await tapCard(tester, 's2');
      expect(find.byKey(const ValueKey('remove-from-priority')), findsNothing, reason: 'nothing selected: the bar is gone');
      expect(find.text('Priority Students'), findsOneWidget);
    });
  });

  group('removing', () {
    testWidgets('the confirmation shows the count; Cancel writes nothing', (tester) async {
      final db = await open(tester, 'H');
      await hold(tester, 's2');
      await tapCard(tester, 's3');
      await tester.tap(find.byKey(const ValueKey('remove-from-priority')));
      await letDataArrive(tester);
      expect(find.text('Remove 2 students from your priority list?'), findsOneWidget);
      expect(find.textContaining('NOT deleted or changed'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await letDataArrive(tester);
      expect(await dismissalIds(db), isEmpty);
      expect(find.text('2 selected'), findsOneWidget, reason: 'the selection is kept');
    });

    testWidgets('one student: the singular wording', (tester) async {
      await open(tester, 'H');
      await hold(tester, 's2');
      await tester.tap(find.byKey(const ValueKey('remove-from-priority')));
      await letDataArrive(tester);
      expect(find.text('Remove 1 student from your priority list?'), findsOneWidget);
    });

    testWidgets('Remove writes exactly one small record per student and NOTHING else changes', (tester) async {
      final db = await open(tester, 'H');
      final before = await everythingElse(db);
      await hold(tester, 's2');
      await tapCard(tester, 's3');
      await tester.tap(find.byKey(const ValueKey('remove-from-priority')));
      await letDataArrive(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-remove-priority')));
      await letDataArrive(tester, frames: 25);

      expect(await dismissalIds(db), ['H__s2', 'H__s3']);
      final doc = (await db.collection('priorityDismissals').doc('H__s2').get()).data()!;
      expect(doc.keys.toSet(), {'adminId', 'studentUid', 'kinds', 'dismissedAt'});
      expect(doc['adminId'], 'H');
      expect(doc['studentUid'], 's2');
      expect(doc['kinds'], isA<List>());
      expect((doc['kinds'] as List), isNotEmpty);
      // the students and everything about them: untouched
      expect(await everythingElse(db), before);
      expect((await db.collection('users').get()).docs.length, 6, reason: 'no student was deleted');

      // gone from this list, the others stay
      expect(find.text('Bhima Sen'), findsNothing);
      expect(find.text('Chaitanya Das'), findsNothing);
      expect(find.text('Arjun Kumar'), findsOneWidget);
      await top(tester);
      expect(find.text('2 removed by you.'), findsOneWidget);
      expect(find.text('2 students removed from your priority list'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Restore puts them back (deletes only the small records)', (tester) async {
      final db = await open(tester, 'H');
      await hold(tester, 's2');
      await tester.tap(find.byKey(const ValueKey('remove-from-priority')));
      await letDataArrive(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-remove-priority')));
      await settleLoad(tester);
      expect(find.text('Bhima Sen'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await top(tester);
      // Cards now carry the automatic sadhana reasons too, so they are taller
      // and the restore line can sit below the fold: bring it into view rather
      // than tapping where it used to be.
      await tester.ensureVisible(find.byKey(const ValueKey('restore-removed')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('restore-removed')));
      await settleLoad(tester);
      expect(await dismissalIds(db), isEmpty);
      expect(find.text('Bhima Sen'), findsOneWidget);
      expect((await db.collection('users').get()).docs.length, 6);
    });

    testWidgets('a student returns when a NEW kind of concern appears; stays away while nothing new', (tester) async {
      await open(tester, 'H', seed: (db) async {
        // s4 was removed when their only concern was "never logged"; s5 was removed with a different concern.
        // `no_report` is in s4's list because the seeded roster files no reports at all, so every student now
        // carries that automatic reason — s4 must still count as "nothing NEW since I removed them".
        await db.collection('priorityDismissals').doc('H__s4').set({'adminId': 'H', 'studentUid': 's4', 'kinds': ['never_logged', 'stale_contact', 'missing_report', 'no_report'], 'dismissedAt': Timestamp.now()});
        await db.collection('priorityDismissals').doc('H__s5').set({'adminId': 'H', 'studentUid': 's5', 'kinds': ['missing_report'], 'dismissedAt': Timestamp.now()});
      });
      expect(find.text('1 removed by you.'), findsOneWidget);
      expect(find.text('6 need attention'), findsNothing);
      expect(find.text('5 need attention'), findsOneWidget, reason: 'six flagged, one stays removed');
      expect(find.byKey(const ValueKey('priority-s4')), findsNothing, reason: 'same kind of concern as when removed');
      await tester.scrollUntilVisible(find.text('Gauri Devi'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Gauri Devi'), findsOneWidget, reason: 'a kind of concern they did not have then');
    });

    testWidgets("one admin's removal never hides the student from another admin", (tester) async {
      await open(tester, 'H', seed: (db) async {
        await db.collection('priorityDismissals').doc('G__s2').set({'adminId': 'G', 'studentUid': 's2', 'kinds': ['never_logged'], 'dismissedAt': Timestamp.now()});
      });
      expect(find.text('Bhima Sen'), findsOneWidget);
      expect(find.textContaining('removed by you'), findsNothing);
    });
  });

  group('every role removes only from their OWN list', () {
    for (final c in [
      ('H', 's2', 'Bhima Sen'),
      ('G', 's2', 'Bhima Sen'),
      ('M1', 's3', 'Chaitanya Das'),
      ('F1', 's5', 'Gauri Devi'),
    ]) {
      testWidgets('${c.$1} removes ${c.$3}: record ${c.$1}__${c.$2}', (tester) async {
        final db = await open(tester, c.$1);
        expect(find.text(c.$3), findsOneWidget);
        final before = await everythingElse(db);
        await hold(tester, c.$2);
        await tester.tap(find.byKey(const ValueKey('remove-from-priority')));
        await letDataArrive(tester);
        await tester.tap(find.byKey(const ValueKey('confirm-remove-priority')));
        await settleLoad(tester);
        expect(await dismissalIds(db), ['${c.$1}__${c.$2}']);
        expect(await everythingElse(db), before);
        expect(find.text(c.$3), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('who is on each list is unchanged (scope): Guide sees his team and the unassigned boy, never the girl', (tester) async {
      await open(tester, 'G');
      expect(find.text('5 need attention'), findsOneWidget, reason: 'Arjun, Bhima, Chaitanya, the long-named student and the unassigned boy Dhruva');
      expect(find.text('out of 5 students'), findsOneWidget);
      expect(find.text('Gauri Devi'), findsNothing);
    });

    testWidgets('Female Enabler sees only her girl', (tester) async {
      await open(tester, 'F1');
      expect(find.text('1 need attention'), findsOneWidget);
      expect(listed(), ['Gauri Devi']);
    });

    testWidgets('Male Enabler sees his own student (and the unassigned boy), not the girl', (tester) async {
      await open(tester, 'M1');
      expect(find.text('2 need attention'), findsOneWidget);
      expect(listed(), containsAll(['Chaitanya Das', 'Dhruva Nair']));
      expect(find.text('Gauri Devi'), findsNothing);
      expect(find.text('Arjun Kumar'), findsNothing);
    });
  });

  for (final scale in kScales) {
    for (final dark in [false, true]) {
      testWidgets('selecting and confirming at text scale $scale, ${dark ? 'dark' : 'light'}', (tester) async {
        await open(tester, 'H', scale: scale, dark: dark);
        expectNoOverflow(tester, reason: 'the list');
        await hold(tester, 's2');
        await tapCard(tester, 's3');
        expect(find.text('2 selected'), findsOneWidget);
        expectNoOverflow(tester, reason: 'selecting');
        await tester.tap(find.byKey(const ValueKey('remove-from-priority')));
        await letDataArrive(tester);
        expect(find.text('Remove 2 students from your priority list?'), findsOneWidget);
        expectNoOverflow(tester, reason: 'the confirmation');
      });
    }
  }
}
