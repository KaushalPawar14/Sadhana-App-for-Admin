import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AssociationManager.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// THE ASSOCIATIONS PAGE: ONE page, three collapsible sections in order (Pending, Confirmed, Completed), each header with its count; no tabs.
/// Pending: Confirm / Cancel (confirmed first). Confirmed: Completed (asks for notes; saves the meeting + the interaction record) / Cancelled (deletes it,
/// after a confirmation, and tells the student). Completed: the guide's notes, read-only.

Timestamp _ts(int d, int h) => Timestamp.fromDate(DateTime(2026, 11, d, h));

Future<FakeFirebaseFirestore> _world(WidgetTester tester) async {
  final db = await prepareApp(tester, who: Who.guide, seeded: false);
  await db.collection('users').doc('s1').set({'name': 'Arjun Kumar', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at Hostel'});
  Map<String, dynamic> base(String name, String status, {Timestamp? preferred, Timestamp? confirmed, String note = ''}) =>
      {'studentUid': 's1', 'studentName': name, 'guideId': 'G', 'status': status, 'preferredDate': preferred ?? _ts(1, 10), 'confirmedDate': confirmed, 'studentNotes': note, 'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male', 'requestedBy': 'student'};
  await db.collection('associations').doc('p1').set(base('Pending Pia', 'pending', preferred: _ts(5, 17), note: 'Can we meet about my japa?'));
  await db.collection('associations').doc('p2').set(base('Pending Pat', 'pending', preferred: _ts(6, 11)));
  await db.collection('associations').doc('c1').set(base('Confirmed Late', 'confirmed', confirmed: _ts(9, 10)));
  await db.collection('associations').doc('c2').set(base('Confirmed Soon', 'confirmed', confirmed: _ts(3, 9)));
  await db.collection('associations').doc('d1').set(base('Done Old', 'completed', confirmed: _ts(1, 9)));
  await db.collection('associations').doc('d2').set(base('Done New', 'completed', confirmed: _ts(2, 9)));
  await db.collection('associations').doc('x1').set(base('Cancelled Carl', 'cancelled'));
  await db.collection('associationGuideNotes').doc('d2').set({'notes': 'He is keen on kirtan.', 'studentUid': 's1', 'studentName': 'Done New', 'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'});
  return db;
}

Future<void> _open(WidgetTester tester, {double scale = 1.0, bool dark = false, Size size = const Size(360, 1600)}) async {
  await pumpScreen(tester, const AssociationManagerPage(), scale: scale, dark: dark, size: size);
  await tester.pumpAndSettle();
}

double _y(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() {
    AdminProfileProvider.instance.debugSet(null);
    HierarchyApi.useForTests(null);
  });

  testWidgets('ONE page: Pending, Confirmed, Completed in that order, each header with its count; the old tabs are gone', (tester) async {
    await _world(tester);
    await _open(tester);
    expect(find.text('Upcoming & History'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    final ys = ['pending', 'confirmed', 'completed'].map((id) => _y(tester, find.byKey(ValueKey('plan-section-assoc-$id')))).toList();
    expect(ys, [...ys]..sort(), reason: 'Pending on top, Confirmed in the middle, Completed at the bottom');
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-section-count-assoc-pending'))).data, '2');
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-section-count-assoc-confirmed'))).data, '2');
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-section-count-assoc-completed'))).data, '2', reason: 'a cancelled record is not listed');
    expect(find.text('Cancelled Carl'), findsNothing);
    // each section collapses and opens again
    await tester.tap(find.byKey(const ValueKey('plan-section-assoc-confirmed')));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed Soon'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('plan-section-assoc-confirmed')));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed Soon'), findsOneWidget);
  });

  testWidgets('PENDING: the student, the requested date and his note, with Confirm and Cancel; CONFIRMED soonest first; COMPLETED newest first', (tester) async {
    await _world(tester);
    await _open(tester);
    expect(find.text('Pending Pia'), findsOneWidget);
    expect(find.textContaining('Requested: 05 Nov 2026, 05:00 PM'), findsOneWidget);
    expect(find.text('Can we meet about my japa?'), findsOneWidget);
    for (final id in ['p1', 'p2']) {
      expect(find.byKey(ValueKey('assoc-confirm-$id')), findsOneWidget);
      expect(find.byKey(ValueKey('assoc-cancel-$id')), findsOneWidget);
    }
    expect(_y(tester, find.text('Confirmed Soon')), lessThan(_y(tester, find.text('Confirmed Late'))), reason: 'soonest first');
    expect(find.byKey(const ValueKey('assoc-when-c2')), findsOneWidget);
    for (final id in ['c1', 'c2']) {
      expect(find.byKey(ValueKey('assoc-completed-$id')), findsOneWidget);
      expect(find.byKey(ValueKey('assoc-cancelled-$id')), findsOneWidget);
    }
    expect(_y(tester, find.text('Done New')), lessThan(_y(tester, find.text('Done Old'))), reason: 'newest first');
    expect(find.text('He is keen on kirtan.'), findsOneWidget, reason: "the guide's notes, read-only");
    expect(find.byKey(const ValueKey('assoc-completed-d2')), findsNothing, reason: 'a finished meeting has no buttons');
  });

  testWidgets('PENDING Cancel asks first; confirming cancels it and tells the student; "Keep it" changes nothing', (tester) async {
    final db = await _world(tester);
    final pushes = <Map<String, dynamic>>[];
    HierarchyApi.useForTests((name, args) async {
      if (name == 'sendStudentNotification') pushes.add(args);
      return <String, dynamic>{};
    });
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('assoc-cancel-p1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assoc-sure-title')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assoc-sure-no')));
    await tester.pumpAndSettle();
    expect((await db.collection('associations').doc('p1').get()).data()!['status'], 'pending');
    await tester.tap(find.byKey(const ValueKey('assoc-cancel-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assoc-sure-yes')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect((await db.collection('associations').doc('p1').get()).data()!['status'], 'cancelled', reason: 'as before: kept, cancelled');
    expect(pushes.single['title'], 'Meeting Cancelled');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PENDING Confirm opens the date and time pickers (the existing flow) and confirms the meeting', (tester) async {
    final db = await _world(tester);
    final pushes = <Map<String, dynamic>>[];
    HierarchyApi.useForTests((name, args) async {
      if (name == 'sendStudentNotification') pushes.add(args);
      return <String, dynamic>{};
    });
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('assoc-confirm-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    final d = (await db.collection('associations').doc('p1').get()).data()!;
    expect(d['status'], 'confirmed');
    expect(d['confirmedDate'], isA<Timestamp>());
    expect(pushes.single['title'], 'Meeting Confirmed');
  });

  testWidgets('CONFIRMED "Completed" asks for notes (typed, with the mic there), then saves the meeting completed, the guide-only notes and the interaction; the card moves to Completed', (tester) async {
    final db = await _world(tester);
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('assoc-completed-c2')));
    await tester.pumpAndSettle();
    expect(find.text('Meeting completed'), findsOneWidget);
    expect(find.text('Confirmed Soon'), findsNWidgets(2), reason: 'the dialog names the student');
    await tester.enterText(find.widgetWithText(TextFormField, 'Notes from the meeting'), 'Agreed on 8 rounds.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect((await db.collection('associations').doc('c2').get()).data()!['status'], 'completed');
    expect((await db.collection('associationGuideNotes').doc('c2').get()).data()!['notes'], 'Agreed on 8 rounds.');
    final logs = (await db.collection('interactionLogs').where('source', isEqualTo: 'meeting').get()).docs;
    expect(logs.length, 1, reason: 'a held meeting counts as an interaction (history, Surrender %, Today ticks, by the server)');
    expect([logs.single.data()['studentUid'], logs.single.data()['rawDictation'], logs.single.data()['analysis']], ['s1', 'Agreed on 8 rounds.', 'done']);
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-section-count-assoc-confirmed'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-section-count-assoc-completed'))).data, '3');
    // (the server stamps the scope fields on a guide note, which is what makes it show in Completed; the in-memory database has no server)
  });

  testWidgets('CONFIRMED "Cancelled" asks first, then DELETES the association completely and tells the student; "Keep it" deletes nothing', (tester) async {
    final db = await _world(tester);
    final pushes = <Map<String, dynamic>>[];
    HierarchyApi.useForTests((name, args) async {
      if (name == 'sendStudentNotification') pushes.add(args);
      return <String, dynamic>{};
    });
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('assoc-cancelled-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assoc-sure-no')));
    await tester.pumpAndSettle();
    expect((await db.collection('associations').doc('c1').get()).exists, isTrue);
    await tester.tap(find.byKey(const ValueKey('assoc-cancelled-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assoc-sure-yes')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect((await db.collection('associations').doc('c1').get()).exists, isFalse, reason: 'deleted completely');
    expect(find.text('Confirmed Late'), findsNothing);
    expect(pushes.single['title'], 'Meeting Cancelled');
    for (final id in ['p1', 'p2', 'c2', 'd1', 'd2', 'x1']) {
      expect((await db.collection('associations').doc(id).get()).exists, isTrue, reason: '$id: nothing else is deleted');
    }
  });

  testWidgets('a way to create a new meeting stays on the page', (tester) async {
    await _world(tester);
    await _open(tester);
    expect(find.text('New Meeting'), findsOneWidget);
  });

  testWidgets('a link from a notification or a button opens the record\'s section and outlines its card', (tester) async {
    await _world(tester);
    await pumpScreen(tester, const AssociationManagerPage(highlightAssociationId: 'd2'), size: const Size(360, 1600));
    await tester.pumpAndSettle();
    final box = tester.widget<Container>(find.byKey(const ValueKey('assoc-card-d2')));
    expect((box.decoration as BoxDecoration).border, isNotNull);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on a phone and on a website width: no overflow, headers 48 dp', (tester) async {
        await _world(tester);
        for (final size in [const Size(360, 2200), const Size(1100, 1200)]) {
          await _open(tester, scale: scale, dark: dark, size: size);
          expect(tester.takeException(), isNull, reason: '$size');
          for (final id in ['pending', 'confirmed', 'completed']) {
            expect(tester.getSize(find.byKey(ValueKey('plan-section-assoc-$id'))).height, greaterThanOrEqualTo(48), reason: id);
          }
          expect(tester.getRect(find.byKey(const ValueKey('assoc-card-p1'))).right, lessThanOrEqualTo(size.width + .5));
        }
      });
    }
  }
}
