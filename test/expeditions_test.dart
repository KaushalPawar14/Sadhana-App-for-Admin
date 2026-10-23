import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/ExpeditionManager.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/ExpeditionModel.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// Expeditions: gender-targeted trips, attendance, History, delete. Roles: HOD, Guide, Male Enabler, Female Enabler.

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

Timestamp day(int y, int m, int d) => Timestamp.fromDate(DateTime(y, m, d));

Map<String, dynamic> trip(String title, String place, String by, String gender, {bool archived = false, Timestamp? date}) => {
      'title': title,
      'description': '',
      'location': place,
      'tripDate': date ?? Timestamp.fromDate(DateTime.now().add(const Duration(days: 10))),
      'createdBy': by,
      'createdAt': Timestamp.now(),
      'status': 'upcoming',
      'targetGender': gender,
      'archived': archived,
    };

Map<String, dynamic> reg(String tripId, String uid, String name, String guide, String team, String gender,
        {String? attendance, bool reflected = false}) =>
    {
      'expeditionId': tripId,
      'studentUid': uid,
      'studentName': name,
      'registeredAt': Timestamp.now(),
      'hasReflected': reflected,
      'reflectionText': reflected ? 'It was a wonderful, humbling day of walking and kirtan.' : '',
      'guideId': guide,
      'scopeGuide': guide,
      'scopeTeam': team,
      'scopeGender': gender,
      if (attendance != null) 'attendance': attendance,
    };

Future<FakeFirebaseFirestore> world(WidgetTester tester) async {
  final db = await prepareApp(tester);
  for (final d in (await db.collection('expeditions').get()).docs) {
    await d.reference.delete();
  }
  final t = db.collection('expeditions');
  await t.doc('tb').set(trip('Boys Vrindavan Yatra', 'Vrindavan', 'G', 'male'));
  await t.doc('tm').set(trip('Boys Mayapur Retreat', 'Mayapur', 'M1', 'male'));
  await t.doc('tg').set(trip('Girls Dwarka Yatra', 'Dwarka', 'F1', 'female'));
  await t.doc('tOld').set(trip('Old Boys Yatra', 'Govardhan', 'G', 'male', archived: true, date: day(2026, 8, 25)));
  await t.doc('tOld2').set(trip('Older Boys Yatra', 'Mayapur', 'G', 'male', archived: true, date: day(2026, 7, 10)));
  await t.doc('tOldG').set(trip('Old Girls Yatra', 'Dwarka', 'F1', 'female', archived: true, date: day(2026, 8, 2)));
  final r = db.collection('expeditionRegistrations');
  await r.doc('tb_s1').set(reg('tb', 's1', 'Arjun Kumar', 'G', 'G', 'male', reflected: true));
  await r.doc('tb_s2').set(reg('tb', 's2', 'Bhima Sen', 'G', 'G', 'male', attendance: 'partial'));
  await r.doc('tb_s3').set(reg('tb', 's3', 'Chaitanya Das', 'M1', 'G', 'male', attendance: 'full'));
  await r.doc('tg_s5').set(reg('tg', 's5', 'Gauri Devi', 'F1', '', 'female'));
  await r.doc('tOld_s1').set(reg('tOld', 's1', 'Arjun Kumar', 'G', 'G', 'male', attendance: 'full', reflected: true));
  await r.doc('tOld_s2').set(reg('tOld', 's2', 'Bhima Sen', 'G', 'G', 'male', attendance: 'partial'));
  await r.doc('tOld_s6').set(reg('tOld', 's6', 'Sixth Student', 'G', 'G', 'male'));
  await r.doc('tOldG_s5').set(reg('tOldG', 's5', 'Gauri Devi', 'F1', '', 'female', attendance: 'full'));
  return db;
}

Future<FakeFirebaseFirestore> openManager(WidgetTester tester, String who, {double scale = 1.0, bool dark = false}) async {
  final db = await world(tester);
  AdminProfileProvider.instance.debugSet(profileOf(who));
  await pumpScreen(tester, const ExpeditionManagerPage(), scale: scale, dark: dark);
  await letDataArrive(tester);
  return db;
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await letDataArrive(tester);
}

const everyTitle = [
  'Boys Vrindavan Yatra',
  'Boys Mayapur Retreat',
  'Girls Dwarka Yatra',
];
List<String> shown(Iterable<String> all) => [for (final t in all) if (find.text(t).evaluate().isNotEmpty) t];

// Fills the "New Expedition" dialog: title, today as the trip start (the end follows it, so this is a one-day
// trip). (The dialog is already open.)
Future<void> fillTrip(WidgetTester tester, String title) async {
  await tester.enterText(find.byType(TextFormField).first, title);
  await tester.tap(find.text('Trip start date'));
  await letDataArrive(tester);
  await tester.tap(find.text('OK'));
  await letDataArrive(tester);
}

Future<Map<String, dynamic>?> createdTrip(FakeFirebaseFirestore db, String title) async {
  final snap = await db.collection('expeditions').where('title', isEqualTo: title).get();
  return snap.docs.isEmpty ? null : snap.docs.first.data();
}

// A test that lets the app's 3-second snackbar expire before it ends.
void tw(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pump(const Duration(seconds: 4));
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  group('the rules of a trip (model)', () {
    test('attendance: absent or unknown reads as pending; summary counts', () {
      expect(attendanceOf({}), 'pending');
      expect(attendanceOf({'attendance': 'bogus'}), 'pending');
      expect(attendanceOf({'attendance': 'partial'}), 'partial');
      expect(attendanceLabel('pending'), 'Pending');
      expect(attendanceLabel('partial'), 'Partially completed');
      expect(attendanceLabel('full'), 'Fully completed');
      final s = summariseAttendance([{}, {'attendance': 'partial'}, {'attendance': 'full'}, {'attendance': 'full'}, {'attendance': 'pending'}]);
      expect((s.pending, s.partial, s.full, s.total), (2, 1, 2, 5));
    });

    test('the gender of a trip follows the creator: Guide and Male Enabler boys, Female Enabler girls, HOD chooses', () {
      expect(tripTargetGenderFor(profileOf('G')), 'male');
      expect(tripTargetGenderFor(profileOf('M1')), 'male');
      expect(tripTargetGenderFor(profileOf('F1')), 'female');
      expect(tripTargetGenderFor(profileOf('H')), isNull);
      expect(targetGenderLabel('male'), 'Boys');
      expect(targetGenderLabel('female'), 'Girls');
      expect(targetGenderLabel(null), '');
    });

    test('History title: place and date; newest first', () {
      expect(historyTitle(trip('T', 'Vrindavan', 'G', 'male', date: day(2026, 8, 25))), 'Vrindavan · 25 Aug 2026');
      expect(historyTitle({'title': 'Only a title', 'tripDate': day(2026, 8, 25)}), 'Only a title · 25 Aug 2026');
      final list = [
        {'tripDate': day(2026, 7, 1)},
        {'tripDate': day(2026, 9, 1)},
        <String, dynamic>{},
        {'tripDate': day(2026, 8, 1)},
      ]..sort(newestFirst);
      expect([for (final t in list) t['tripDate'] is Timestamp ? (t['tripDate'] as Timestamp).toDate().month : 0], [9, 8, 7, 0]);
      expect(tripArchived({'archived': true}), isTrue);
      expect(tripArchived({}), isFalse);
    });
  });

  group('two tabs: Manage Trips and History (the Reflections tab is gone)', () {
    tw('tab labels', (tester) async {
      await openManager(tester, 'H');
      expect(find.text('Manage Trips'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Reflections'), findsNothing);
    });
  });

  group('who sees which trips (same scope in Manage and in History)', () {
    tw('HOD: every active trip, boys and girls; none of History here', (tester) async {
      await openManager(tester, 'H');
      expect(shown(everyTitle), everyTitle);
      expect(find.text('Old Boys Yatra'), findsNothing);
      expect(find.byKey(const ValueKey('trip-for-tb')), findsOneWidget);
      expect(find.text('For boys'), findsWidgets);
      expect(find.text('For girls'), findsWidgets);
    });

    tw('Guide: only the trips he created', (tester) async {
      await openManager(tester, 'G');
      expect(shown(everyTitle), ['Boys Vrindavan Yatra']);
    });

    tw('Male Enabler: only his own trips', (tester) async {
      await openManager(tester, 'M1');
      expect(shown(everyTitle), ['Boys Mayapur Retreat']);
    });

    tw('Female Enabler: only her (girls) trip', (tester) async {
      await openManager(tester, 'F1');
      expect(shown(everyTitle), ['Girls Dwarka Yatra']);
      expect(find.text('For girls'), findsOneWidget);
    });

    tw('History, HOD: every past trip, newest first, titled place + date', (tester) async {
      await openManager(tester, 'H');
      await openTab(tester, 'History');
      expect(find.text('Govardhan · 25 Aug 2026'), findsOneWidget);
      expect(find.text('Dwarka · 02 Aug 2026'), findsOneWidget);
      expect(find.text('Mayapur · 10 Jul 2026'), findsOneWidget);
      final y = [for (final t in ['Govardhan · 25 Aug 2026', 'Dwarka · 02 Aug 2026', 'Mayapur · 10 Jul 2026']) tester.getTopLeft(find.text(t)).dy];
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: 'newest trip date first');
      expect(find.text('Boys Vrindavan Yatra'), findsNothing, reason: 'active trips are not History');
    });

    tw('History, Guide: only his own past trips; Female Enabler: only hers', (tester) async {
      await openManager(tester, 'G');
      await openTab(tester, 'History');
      expect(find.text('Govardhan · 25 Aug 2026'), findsOneWidget);
      expect(find.text('Mayapur · 10 Jul 2026'), findsOneWidget);
      expect(find.text('Dwarka · 02 Aug 2026'), findsNothing);
    });

    tw('History, Female Enabler', (tester) async {
      await openManager(tester, 'F1');
      await openTab(tester, 'History');
      expect(find.text('Dwarka · 02 Aug 2026'), findsOneWidget);
      expect(find.text('Govardhan · 25 Aug 2026'), findsNothing);
    });

    tw('History: empty state', (tester) async {
      await openManager(tester, 'M1');
      await openTab(tester, 'History');
      expect(find.textContaining('No past trips yet'), findsOneWidget);
    });
  });

  group('creating a trip: the target gender', () {
    for (final c in [('G', 'male', 'boys'), ('M1', 'male', 'boys'), ('F1', 'female', 'girls')]) {
      tw('${c.$1}: the trip is for ${c.$3}, stored as targetGender "${c.$2}", active', (tester) async {
        final db = await openManager(tester, c.$1);
        await tester.tap(find.text('New Trip'));
        await letDataArrive(tester);
        expect(find.byKey(const ValueKey('trip-for-fixed')), findsOneWidget);
        expect(find.text('This trip is for ${c.$3}.'), findsOneWidget);
        expect(find.byKey(const ValueKey('trip-for-male')), findsNothing, reason: 'no choice for a non-HOD');
        await fillTrip(tester, 'Made by ${c.$1}');
        await tester.tap(find.text('Create'));
        await letDataArrive(tester);
        final made = await createdTrip(db, 'Made by ${c.$1}');
        expect(made, isNotNull);
        expect(made!['targetGender'], c.$2);
        expect(made['archived'], false);
        expect(made['createdBy'], c.$1);
        expect(made['status'], 'upcoming');
      });
    }

    tw('HOD chooses Girls', (tester) async {
      final db = await openManager(tester, 'H');
      await tester.tap(find.text('New Trip'));
      await letDataArrive(tester);
      expect(find.byKey(const ValueKey('trip-for-male')), findsOneWidget);
      expect(find.byKey(const ValueKey('trip-for-female')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trip-for-female')));
      await tester.pump();
      await fillTrip(tester, 'HOD girls trip');
      await tester.tap(find.text('Create'));
      await letDataArrive(tester);
      expect((await createdTrip(db, 'HOD girls trip'))!['targetGender'], 'female');
    });

    tw('HOD chooses Boys', (tester) async {
      final db = await openManager(tester, 'H');
      await tester.tap(find.text('New Trip'));
      await letDataArrive(tester);
      await tester.tap(find.byKey(const ValueKey('trip-for-male')));
      await tester.pump();
      await fillTrip(tester, 'HOD boys trip');
      await tester.tap(find.text('Create'));
      await letDataArrive(tester);
      expect((await createdTrip(db, 'HOD boys trip'))!['targetGender'], 'male');
    });

    tw('HOD who does not choose cannot create: nothing is written', (tester) async {
      final db = await openManager(tester, 'H');
      await tester.tap(find.text('New Trip'));
      await letDataArrive(tester);
      await fillTrip(tester, 'Undecided trip');
      await tester.tap(find.text('Create'));
      await letDataArrive(tester);
      expect(find.text('Choose Boys or Girls for this trip'), findsOneWidget);
      expect(await createdTrip(db, 'Undecided trip'), isNull);
    });
  });

  group('attendance (Manage Trips -> View Registrations)', () {
    Future<FakeFirebaseFirestore> openRegs(WidgetTester tester, String who, String tripId) async {
      final db = await openManager(tester, who);
      await tester.tap(find.byKey(ValueKey('registrations-$tripId')));
      await letDataArrive(tester);
      return db;
    }

    tw('the Guide sees his students with their status and a count summary; default is Pending', (tester) async {
      await openRegs(tester, 'G', 'tb');
      expect(find.text('Arjun Kumar'), findsOneWidget);
      expect(find.text('Bhima Sen'), findsOneWidget);
      expect(find.text('Chaitanya Das'), findsOneWidget);
      expect(find.text('Pending 1'), findsOneWidget);
      expect(find.text('Partially completed 1'), findsOneWidget);
      expect(find.text('Fully completed 1'), findsOneWidget);
      expect(find.text('3 registered'), findsOneWidget);
      // each row shows its own state
      expect(find.descendant(of: find.byKey(const ValueKey('attendance-tb_s1')), matching: find.text('Pending')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('attendance-tb_s2')), matching: find.text('Partially completed')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('attendance-tb_s3')), matching: find.text('Fully completed')), findsOneWidget);
    });

    tw('tapping a status changes it (saved), and the summary follows', (tester) async {
      final db = await openRegs(tester, 'G', 'tb');
      await tester.tap(find.byKey(const ValueKey('attendance-tb_s1')));
      await letDataArrive(tester);
      expect(find.text('Attendance'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('Fully completed')));
      await letDataArrive(tester);
      expect((await db.collection('expeditionRegistrations').doc('tb_s1').get()).data()!['attendance'], 'full');
      expect(find.text('Pending 0'), findsOneWidget);
      expect(find.text('Fully completed 2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('attendance-tb_s1')));
      await letDataArrive(tester);
      await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('Partially completed')));
      await letDataArrive(tester);
      expect((await db.collection('expeditionRegistrations').doc('tb_s1').get()).data()!['attendance'], 'partial');
      await tester.tap(find.byKey(const ValueKey('attendance-tb_s1')));
      await letDataArrive(tester);
      await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('Pending')));
      await letDataArrive(tester);
      expect((await db.collection('expeditionRegistrations').doc('tb_s1').get()).data()!['attendance'], 'pending');
    });

    tw('a reflection can be opened from the student row', (tester) async {
      await openRegs(tester, 'G', 'tb');
      expect(find.byKey(const ValueKey('reflection-tb_s1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reflection-tb_s2')), findsNothing, reason: 'only a student who wrote one');
      await tester.tap(find.byKey(const ValueKey('reflection-tb_s1')));
      await letDataArrive(tester);
      expect(find.textContaining('wonderful, humbling day'), findsOneWidget);
    });

    tw('a Guide sees only his own team in the list (the scope is unchanged)', (tester) async {
      final db = await openManager(tester, 'G');
      await db.collection('expeditionRegistrations').doc('tb_s4').set(reg('tb', 's4', 'Dhruva Nair', '', '', 'male'));
      await db.collection('expeditionRegistrations').doc('tb_other').set(reg('tb', 'sx', 'Other Team Boy', 'Z', 'Z', 'male'));
      await tester.tap(find.byKey(const ValueKey('registrations-tb')));
      await letDataArrive(tester);
      expect(find.text('Other Team Boy'), findsNothing);
      expect(find.text('Dhruva Nair'), findsOneWidget, reason: 'an unassigned boy is in a Guide\'s scope');
    });

    tw('the Female Enabler marks her girl', (tester) async {
      final db = await openRegs(tester, 'F1', 'tg');
      expect(find.text('Gauri Devi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('attendance-tg_s5')));
      await letDataArrive(tester);
      await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('Fully completed')));
      await letDataArrive(tester);
      expect((await db.collection('expeditionRegistrations').doc('tg_s5').get()).data()!['attendance'], 'full');
    });

    tw('the Male Enabler sees only his own student on his trip', (tester) async {
      final db = await openManager(tester, 'M1');
      await db.collection('expeditionRegistrations').doc('tm_s3').set(reg('tm', 's3', 'Chaitanya Das', 'M1', 'G', 'male'));
      await db.collection('expeditionRegistrations').doc('tm_s1').set(reg('tm', 's1', 'Arjun Kumar', 'G', 'G', 'male'));
      await tester.tap(find.byKey(const ValueKey('registrations-tm')));
      await letDataArrive(tester);
      expect(find.text('Chaitanya Das'), findsOneWidget);
      expect(find.text('Arjun Kumar'), findsNothing);
    });

    tw('the HOD sees every registration of a trip', (tester) async {
      await openRegs(tester, 'H', 'tb');
      expect(find.text('Arjun Kumar'), findsOneWidget);
      expect(find.text('Bhima Sen'), findsOneWidget);
      expect(find.text('Chaitanya Das'), findsOneWidget);
    });
  });

  group('History: locked, read only', () {
    tw('a card opens the student list with each FINAL status', (tester) async {
      final db = await openManager(tester, 'G');
      await openTab(tester, 'History');
      await tester.tap(find.byKey(const ValueKey('history-trip-tOld')));
      await letDataArrive(tester);
      expect(find.text('Arjun Kumar'), findsOneWidget);
      expect(find.text('Bhima Sen'), findsOneWidget);
      expect(find.text('Sixth Student'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('attendance-tOld_s1')), matching: find.text('Fully completed')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('attendance-tOld_s2')), matching: find.text('Partially completed')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('attendance-tOld_s6')), matching: find.text('Pending')), findsOneWidget);
      expect(find.text('Fully completed 1'), findsOneWidget);
      expect(find.text('A past trip: read only. Statuses are final.'), findsOneWidget);
      // read only: tapping a status opens nothing and changes nothing
      await tester.tap(find.byKey(const ValueKey('attendance-tOld_s6')));
      await letDataArrive(tester);
      expect(find.text('Attendance'), findsNothing);
      expect((await db.collection('expeditionRegistrations').doc('tOld_s6').get()).data()!.containsKey('attendance'), isFalse);
      // a reflection can still be read
      await tester.tap(find.byKey(const ValueKey('reflection-tOld_s1')));
      await letDataArrive(tester);
      expect(find.textContaining('wonderful, humbling day'), findsOneWidget);
    });

    tw('a History card shows how many students and how they ended', (tester) async {
      await openManager(tester, 'G');
      await openTab(tester, 'History');
      expect(find.text('3 students'), findsOneWidget);
      expect(find.text('1 fully, 1 partly'), findsOneWidget);
    });
  });

  group('delete (confirmation, then the server callable)', () {
    late List<List<dynamic>> calls;
    void spy([Future<Map<String, dynamic>> Function()? reply]) {
      calls = [];
      HierarchyApi.useForTests((name, data) async {
        calls.add([name, data]);
        return reply == null ? {'deleted': true, 'registrationsDeleted': 3} : reply();
      });
    }

    tw('an active trip: Cancel deletes nothing', (tester) async {
      await openManager(tester, 'G');
      spy();
      await tester.tap(find.byKey(const ValueKey('delete-trip-tb')));
      await letDataArrive(tester);
      expect(find.text('Delete this trip?'), findsOneWidget);
      expect(find.textContaining('every registration for it will be removed permanently'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await letDataArrive(tester);
      expect(calls, isEmpty);
    });

    tw('an active trip: Delete calls deleteExpedition with the trip id', (tester) async {
      await openManager(tester, 'G');
      spy();
      await tester.tap(find.byKey(const ValueKey('delete-trip-tb')));
      await letDataArrive(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-trip')));
      await letDataArrive(tester);
      expect(calls, [
        ['deleteExpedition', {'tripId': 'tb'}],
      ]);
      expect(find.text('Trip deleted'), findsOneWidget);
    });

    tw('a HOD can delete another admin\'s trip', (tester) async {
      await openManager(tester, 'H');
      spy();
      await tester.tap(find.byKey(const ValueKey('delete-trip-tg')));
      await letDataArrive(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-trip')));
      await letDataArrive(tester);
      expect(calls.single[1], {'tripId': 'tg'});
    });

    tw('a History card: confirmation, then delete', (tester) async {
      await openManager(tester, 'G');
      spy();
      await openTab(tester, 'History');
      await tester.tap(find.byKey(const ValueKey('delete-history-tOld')));
      await letDataArrive(tester);
      expect(find.text('Delete this History card?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await letDataArrive(tester);
      expect(calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('delete-history-tOld')));
      await letDataArrive(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-trip')));
      await letDataArrive(tester);
      expect(calls.single, ['deleteExpedition', {'tripId': 'tOld'}]);
    });

    tw('a refusal from the server is shown in its own words', (tester) async {
      await openManager(tester, 'G');
      spy(() async => throw HierarchyException('permission-denied', 'Only the person who created this trip, or a HOD, can delete it.'));
      await tester.tap(find.byKey(const ValueKey('delete-trip-tb')));
      await letDataArrive(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-trip')));
      await letDataArrive(tester);
      expect(find.text('Only the person who created this trip, or a HOD, can delete it.'), findsOneWidget);
    });
  });

  // Text size 1.0 / 1.3 / 1.6, light and dark, the app's real fonts.
  for (final scale in kScales) {
    for (final dark in [false, true]) {
      final s = 'text scale $scale, ${dark ? 'dark' : 'light'}';

      tw('Manage Trips, registrations sheet, History and a past trip — $s', (tester) async {
        await openManager(tester, 'H', scale: scale, dark: dark);
        expectNoOverflow(tester, reason: 'Manage Trips');
        await tester.tap(find.byKey(const ValueKey('registrations-tb')));
        await letDataArrive(tester);
        expect(find.text('Pending 1'), findsOneWidget);
        expectNoOverflow(tester, reason: 'registrations sheet');
        await tester.tapAt(const Offset(180, 30)); // the barrier above the sheet
        await letDataArrive(tester);
        await openTab(tester, 'History');
        expectNoOverflow(tester, reason: 'History');
        await tester.tap(find.byKey(const ValueKey('history-trip-tOld')));
        await letDataArrive(tester);
        expect(find.textContaining('Fully completed 1'), findsOneWidget);
        expectNoOverflow(tester, reason: 'a past trip');
      });

      tw('the New Expedition dialog (HOD, with the Boys/Girls choice) — $s', (tester) async {
        await openManager(tester, 'H', scale: scale, dark: dark);
        await tester.tap(find.text('New Trip'));
        await letDataArrive(tester);
        expect(find.byKey(const ValueKey('trip-for-female')), findsOneWidget);
        expectNoOverflow(tester);
      });
    }
  }
}
