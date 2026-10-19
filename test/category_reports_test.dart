import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/Calendar.dart';
import 'package:folk_guide_app/Pages/AbcdeActivityCard.dart';
import 'package:folk_guide_app/Services/MissingReportNotification.dart';
import 'package:folk_guide_app/utils/SadhanaReportSource.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:table_calendar/table_calendar.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// Reports are CATEGORY-SEPARATED: a student's data is read ONLY from the collection of his CURRENT category
// (FOLK -> sadhana-reports; Hostel / Localite -> hostel-sadhana). Nothing is deleted or moved; it is live.
String id(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
final now = DateTime.now();
final today = DateTime(now.year, now.month, now.day);
final firstOfMonth = DateTime(now.year, now.month, 1);

Future<FakeFirebaseFirestore> world(WidgetTester tester, {String role = 'Stay at FOLK'}) async {
  final db = await prepareApp(tester, seeded: false);
  await db.collection('users').doc('s1').set({'name': 'Asha', 'role': role, 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G'});
  return db;
}

Future<void> report(FakeFirebaseFirestore db, String collection, DateTime d, [Map<String, dynamic>? data]) =>
    db.collection(collection).doc('Asha').collection('dates').doc(id(d)).set(data ?? {'chantRounds': 16, 'bookReading': 30, 'classHearing': 2});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  test('which collection a role means', () {
    expect(reportCollectionForRole('Stay at FOLK'), kFolkReports);
    expect(reportCollectionForRole('Stay at Hostel'), kHostelReports);
    expect(reportCollectionForRole('Stay at Localite'), kHostelReports);
    expect(reportCollectionForRole(''), kFolkReports);
    expect(reportCollectionForRole(null), kFolkReports);
  });

  testWidgets('fetchDateReports / fetchDateReport read ONLY the current category', (tester) async {
    final db = await world(tester);
    await report(db, kFolkReports, today.subtract(const Duration(days: 1)));
    await report(db, kFolkReports, today.subtract(const Duration(days: 2)));
    await report(db, kHostelReports, today, {'wakeUpTime': '05:00', 'chantRounds': 16});
    final asFolk = await fetchDateReports('Asha', 'Stay at FOLK');
    expect(asFolk.keys.toSet(), {id(today.subtract(const Duration(days: 1))), id(today.subtract(const Duration(days: 2)))});
    final asHostel = await fetchDateReports('Asha', 'Stay at Hostel');
    expect(asHostel.keys.toSet(), {id(today)});
    expect(await fetchDateReport('Asha', id(today), 'Stay at FOLK'), isNull, reason: 'a Hostel report is not a FOLK student\'s report');
    expect((await fetchDateReport('Asha', id(today), 'Stay at Localite'))!['wakeUpTime'], '05:00');
    expect(await fetchDateReport('Asha', id(today.subtract(const Duration(days: 1))), 'Stay at Hostel'), isNull);
  });

  testWidgets('"left to submit" (the missing-report check) looks only at the current category', (tester) async {
    final db = await world(tester);
    await report(db, kHostelReports, today); // filed today, but under Hostel
    var missing = await MissingReportService().fetchMissingNames();
    expect(missing, ['Asha'], reason: 'a FOLK student with only a Hostel report today has not submitted');
    await db.collection('users').doc('s1').update({'role': 'Stay at Hostel'});
    missing = await MissingReportService().fetchMissingNames();
    expect(missing, isEmpty, reason: 'as a Hostel student that report counts');
    await db.collection('users').doc('s1').update({'role': 'Stay at FOLK'});
    await report(db, kFolkReports, today);
    expect(await MissingReportService().fetchMissingNames(), isEmpty);
  });

  test('availableDatesStream follows the student\'s profile live (FOLK -> Hostel -> FOLK)', () async {
    final folk = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
    final hostel = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
    final roles = StreamController<String?>.broadcast();
    addTearDown(() async {
      await folk.close();
      await hostel.close();
      await roles.close();
    });
    final events = <Set<String>>[];
    final sub = availableDatesStream('Asha',
            role: 'Stay at FOLK',
            snapshotsFor: (c) => (c == kFolkReports ? folk : hostel).stream,
            roleStream: roles.stream)
        .listen(events.add);
    final db = FakeFirebaseFirestore();
    var n = 0;
    Future<QuerySnapshot<Map<String, dynamic>>> snap(List<String> ids) async {
      final col = db.collection('t${n++}');
      for (final i in ids) {
        await col.doc(i).set({'x': 1});
      }
      return col.get();
    }

    folk.add(await snap(['01-10-2026', '02-10-2026']));
    await Future<void>.delayed(Duration.zero);
    expect(events.last, {'01-10-2026', '02-10-2026'});
    expect(hostel.hasListener, isFalse);

    roles.add('Stay at Hostel');
    await Future<void>.delayed(Duration.zero);
    expect(folk.hasListener, isFalse, reason: 'the FOLK collection is no longer read');
    hostel.add(await snap([]));
    await Future<void>.delayed(Duration.zero);
    expect(events.last, <String>{}, reason: 'every day red, zero submitted');
    hostel.add(await snap(['05-10-2026']));
    await Future<void>.delayed(Duration.zero);
    expect(events.last, {'05-10-2026'}, reason: 'a new report counts');

    roles.add('Stay at Localite');
    await Future<void>.delayed(Duration.zero);
    expect(hostel.hasListener, isTrue, reason: 'Hostel and Localite are one category');

    roles.add('Stay at FOLK');
    await Future<void>.delayed(Duration.zero);
    folk.add(await snap(['01-10-2026', '02-10-2026']));
    await Future<void>.delayed(Duration.zero);
    expect(events.last, {'01-10-2026', '02-10-2026'}, reason: 'switched back: the old FOLK days return');
    await sub.cancel();
  });

  testWidgets('the student\'s calendar recolours live when his category changes', (tester) async {
    final db = await world(tester);
    final first = firstOfMonth;
    await report(db, kFolkReports, first);
    await report(db, kHostelReports, first.add(const Duration(days: 1)), {'wakeUpTime': '05:00', 'chantRounds': 16});
    await pumpScreen(tester, CalendarPage(username: 'Asha', role: 'Stay at FOLK', studentUid: 's1'), reduce: true);
    await letDataArrive(tester, frames: 25);

    int green() {
      final ctx = tester.element(find.byType(TableCalendar<dynamic>));
      final success = ctx.g.success;
      return find
          .descendant(of: find.byType(TableCalendar<dynamic>), matching: find.byType(AnimatedContainer))
          .evaluate()
          .where((e) {
        final d = (e.widget as AnimatedContainer).decoration;
        return d is BoxDecoration && d.color == success;
      }).length;
    }

    final folkGreen = green();
    expect(folkGreen, 1, reason: 'one FOLK report, on the 1st');

    await db.collection('users').doc('s1').update({'role': 'Stay at Hostel'});
    await letDataArrive(tester, frames: 25);
    final expectedHostel = today.day >= 2 ? 1 : 0; // the 2nd is in the future on the 1st of a month
    expect(green(), expectedHostel, reason: 'now only his Hostel report counts; the FOLK day is red');

    await db.collection('users').doc('s1').update({'role': 'Stay at FOLK'});
    await letDataArrive(tester, frames: 25);
    expect(green(), 1, reason: 'back in FOLK: the saved FOLK day is green again');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the ABCDE activity card reads again when the category changes', (tester) async {
    final db = await world(tester);
    // FOLK: 4 reports with 20 rounds; Hostel: none
    for (var i = 1; i <= 4; i++) {
      await report(db, kFolkReports, today.subtract(Duration(days: i)), {'chantRounds': 20, 'bookReading': 10});
    }
    Widget card(String role) => AbcdeActivityCard(studentUid: 's1', studentName: 'Asha', role: role, lifetimeRounds: 0);
    await pumpScreen(tester, Scaffold(body: SingleChildScrollView(child: card('Stay at FOLK'))));
    await letDataArrive(tester, frames: 25);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, Scaffold(body: SingleChildScrollView(child: card('Stay at Hostel'))));
    await letDataArrive(tester, frames: 25);
    expect(tester.takeException(), isNull);
  });
}
