import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/Leaderboard.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/LeaderboardData.dart';

import 'support/guide_test_support.dart';

// The Leaderboard says WHY it is empty. In production today: the 24 Hostel & Localite boys have not filed a
// report since scoring began (0 `competition` documents for them), and FOLK has no girls. The query and the
// rules are right; the screen used to show one generic line.

AdminProfile profileOf(String id, String role, {String team = ''}) => AdminProfile.fromMap({
      'id': id,
      'displayName': id,
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

Map<String, dynamic> comp(String name, String category, String gender, double weekly, double monthly, {String guide = 'F1', String team = ''}) => {
      'Name': name,
      'category': category,
      'gender': gender,
      'scopeGender': gender,
      'scopeGuide': guide,
      'scopeTeam': team,
      'weekly.total_score': weekly,
      'weekly.days_count': weekly > 0 ? 3 : 0,
      'monthly.total_score': monthly,
      'monthly.days_count': monthly > 0 ? 5 : 0,
    };

// What production holds: H&L girls with scores, FOLK boys with scores, NO H&L boys, NO FOLK girls.
Future<FakeFirebaseFirestore> production() async {
  final db = FakeFirebaseFirestore();
  for (final d in [
    comp('Gopi', 'hostel_localite', 'female', 55, 155),
    comp('Gita', 'hostel_localite', 'female', 0, 65),
    comp('Arjun', 'folk', 'male', 50, 300, guide: 'G', team: 'G'),
  ]) {
    await db.collection('competition').doc(d['Name'] as String).set(d);
  }
  return db;
}

Future<void> open(WidgetTester tester, AdminProfile p, {double scale = 1.0, bool dark = false}) async {
  phone(tester, scale);
  AdminProfileProvider.instance.debugSet(p);
  GuideDb.useForTests(await production());
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

  group('the words', () {
    test('every group names itself; FOLK girls say there are no students', () {
      String m(String c, String g, LeaderboardPeriod p) => leaderboardEmptyMessage(category: c, gender: g, period: p);
      expect(m('hostel_localite', 'male', LeaderboardPeriod.weekly), 'No scores yet for Hostel & Localite boys this week.');
      expect(m('hostel_localite', 'male', LeaderboardPeriod.monthly), 'No scores yet for Hostel & Localite boys this month.');
      expect(m('hostel_localite', 'female', LeaderboardPeriod.weekly), 'No scores yet for Hostel & Localite girls this week.');
      expect(m('folk', 'male', LeaderboardPeriod.weekly), 'No scores yet for FOLK boys this week.');
      expect(m('folk', 'female', LeaderboardPeriod.weekly), 'No students in this group yet.');
      expect(m('folk', 'female', LeaderboardPeriod.monthly), 'No students in this group yet.');
    });
  });

  group('on today\'s production data', () {
    testWidgets('HOD, Hostel & Localite / Boys: a clear empty state, not a blank screen', (tester) async {
      await open(tester, profileOf('H', 'HOD'));
      await tester.tap(find.text('Hostel & Localite'));
      await tester.pumpAndSettle();
      expect(find.text('No scores yet for Hostel & Localite boys this week.'), findsOneWidget);
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('No scores yet for Hostel & Localite boys this month.'), findsOneWidget);
    });

    testWidgets('HOD, FOLK / Girls: "No students in this group yet."', (tester) async {
      await open(tester, profileOf('H', 'HOD'));
      await tester.tap(find.text('Girls'));
      await tester.pumpAndSettle();
      expect(find.text('No students in this group yet.'), findsOneWidget);
    });

    testWidgets('HOD, Hostel & Localite / Girls: the real ranking (Gopi above Gita this month)', (tester) async {
      await open(tester, profileOf('H', 'HOD'));
      await tester.tap(find.text('Hostel & Localite'));
      await tester.tap(find.text('Girls'));
      await tester.pumpAndSettle();
      expect(find.text('Gopi'), findsOneWidget);
      expect(find.textContaining('No scores yet'), findsNothing);
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Gopi')).dy, lessThan(tester.getTopLeft(find.text('Gita')).dy));
    });

    testWidgets('a Guide (boys only), Hostel & Localite: the same clear line', (tester) async {
      await open(tester, profileOf('G', 'GUIDE'));
      await tester.tap(find.text('Hostel & Localite'));
      await tester.pumpAndSettle();
      expect(find.text('No scores yet for Hostel & Localite boys this week.'), findsOneWidget);
    });

    testWidgets('a Female Enabler, FOLK: no students in the group; Hostel & Localite: her girls', (tester) async {
      await open(tester, profileOf('F1', 'FEMALE_ENABLER'));
      expect(find.text('No students in this group yet.'), findsOneWidget);
      await tester.tap(find.text('Hostel & Localite'));
      await tester.pumpAndSettle();
      expect(find.text('Gopi'), findsOneWidget);
    });
  });

  for (final scale in kScales) {
    for (final dark in [false, true]) {
      testWidgets('the empty states at text scale $scale, ${dark ? 'dark' : 'light'}', (tester) async {
        await open(tester, profileOf('H', 'HOD'), scale: scale, dark: dark);
        await tester.tap(find.text('Hostel & Localite'));
        await tester.pumpAndSettle();
        expect(find.text('No scores yet for Hostel & Localite boys this week.'), findsOneWidget);
        expectNoOverflow(tester);
        await tester.tap(find.text('Girls'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('FOLK'));
        await tester.pumpAndSettle();
        expect(find.text('No students in this group yet.'), findsOneWidget);
        expectNoOverflow(tester);
      });
    }
  }
}
