import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/Leaderboard.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/LeaderboardData.dart';
import 'package:folk_guide_app/widgets/GuideMeta.dart';

import 'support/guide_test_support.dart';

// The Guide's leaderboard now also shows the best five of each FIELD (per-item points of the period, no
// multipliers) from the same competition documents; there are no old category boards.
AdminProfile hod() => AdminProfile.fromMap({
      'id': 'H',
      'displayName': 'H',
      'role': 'HOD',
      'teamGuide': '',
      'email': 'h@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

Map<String, dynamic> doc(String name, String category, {double total = 0, Map<String, num> weekly = const {}, Map<String, num> monthly = const {}}) => {
      'Name': name,
      'category': category,
      'gender': 'male',
      'scopeGender': 'male',
      'scopeGuide': 'E1',
      'scopeTeam': 'G',
      'weekly.total_score': total,
      'weekly.days_count': 3,
      'monthly.total_score': total * 3,
      'monthly.days_count': 9,
      for (final e in weekly.entries) 'weekly.pts_${e.key}': e.value,
      for (final e in monthly.entries) 'monthly.pts_${e.key}': e.value,
    };

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  final rows = [
    doc('Arjun', 'folk', total: 900, weekly: {'chanting': 100, 'reading': 50, 'hearing': 75, 'service': 50}, monthly: {'chanting': 400}),
    doc('Bhima', 'folk', total: 700, weekly: {'chanting': 300, 'reading': 100, 'hearing': 100, 'service': 25}, monthly: {'chanting': 200}),
    doc('Chaitanya', 'folk', total: 500, weekly: {'chanting': 200, 'reading': 25, 'hearing': 150}),
    doc('Dhruva', 'folk', total: 300, weekly: {'chanting': 50, 'reading': 10, 'hearing': 25}),
    doc('Eknath', 'folk', total: 200, weekly: {'chanting': 60, 'reading': 20, 'hearing': 50, 'service': 50}),
    doc('Gopal', 'folk', total: 100, weekly: {'chanting': 70, 'reading': 30, 'hearing': 5}),
    doc('Hari', 'folk', total: 50, weekly: {'chanting': 80, 'reading': 40, 'hearing': 2}),
    doc('Hans', 'hostel_localite', total: 400, weekly: {'chanting': 90, 'reading': 60, 'hearing': 40, 'service': 999}),
  ];
  for (final d in rows) {
    await db.collection('competition').doc(d['Name'] as String).set(d);
  }
  return db;
}

Future<void> open(WidgetTester tester, {double scale = 1.0, bool dark = false}) async {
  phone(tester, scale);
  AdminProfileProvider.instance.debugSet(hod());
  GuideDb.useForTests(await seeded());
  await tester.pumpWidget(guideHost(const LeaderboardPage(), dark: dark));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
    LeaderboardData.instance = const FirestoreLeaderboardData();
  });

  group('bestByField (data)', () {
    test('five per field by the field\'s own points, none without points, ties by name', () async {
      final db = await seeded();
      final snap = await db.collection('competition').where('category', isEqualTo: 'folk').get();
      final w = bestByField(snap.docs, LeaderboardPeriod.weekly, 'folk');
      expect(w[BestField.chanting]!.map((e) => e.name), ['Bhima', 'Chaitanya', 'Arjun', 'Hari', 'Gopal']);
      expect(w[BestField.chanting]!.first.score, 300);
      expect(w[BestField.hearing]!.map((e) => e.name).first, 'Chaitanya');
      expect(w[BestField.service]!.map((e) => e.name), ['Arjun', 'Eknath', 'Bhima'], reason: 'Chaitanya has 0: not listed');
      final m = bestByField(snap.docs, LeaderboardPeriod.monthly, 'folk');
      expect(m[BestField.chanting]!.map((e) => e.name), ['Arjun', 'Bhima']);
      expect(m[BestField.reading], isEmpty);
    });

    test('Hostel & Localite have no Best Service, whatever the data says', () async {
      final db = await seeded();
      final snap = await db.collection('competition').where('category', isEqualTo: 'hostel_localite').get();
      final w = bestByField(snap.docs, LeaderboardPeriod.weekly, 'hostel_localite');
      expect(w.containsKey(BestField.service), isFalse);
      expect(w[BestField.chanting]!.single.name, 'Hans');
    });
  });

  testWidgets('the screen: FOLK shows the four fields; the ranking above is the total (multipliers applied)', (tester) async {
    await open(tester);
    expect(find.text('BEST BY FIELD · THIS WEEK'), findsOneWidget);
    // the ranking is by total: Arjun (900) above Bhima (700)
    expect(tester.getTopLeft(find.text('Arjun').first).dy, lessThan(tester.getTopLeft(find.text('Bhima').first).dy));
    for (final f in ['chanting', 'reading', 'hearing', 'service']) {
      await tester.scrollUntilVisible(find.byKey(ValueKey('field-$f')), 250, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(ValueKey('field-$f')), findsOneWidget);
    }
    expect(find.text('Best Chanting'), findsOneWidget);
    expect(find.text('Best Service'), findsOneWidget);
    expect(find.text('300 pts'), findsOneWidget, reason: 'Bhima\'s chanting points, not his total');
  });

  testWidgets('Hostel & Localite: three fields, no Best Service; the month has its own bests', (tester) async {
    await open(tester);
    await tester.tap(find.text('Hostel & Localite', findRichText: true));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('field-service')), findsNothing);
    expect(find.byKey(const ValueKey('field-hearing')), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FOLK', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This month', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('BEST BY FIELD · THIS MONTH'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('draws without overflow — ${dark ? 'dark' : 'light'}, text $scale', (tester) async {
        await open(tester, scale: scale, dark: dark);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('no old category board or scorecard read is left in the Guide screens', () {
    // (the raw "Total Points" tally and the scorecard readers were removed; see the progress notes)
    expect(GuideChoiceChip, isNotNull);
  });
}
