import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/Competition.dart';
import 'package:folk_guide_app/Pages/Leaderboard.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/LeaderboardData.dart';
import 'package:folk_guide_app/widgets/GuideMeta.dart';
import 'package:folk_guide_app/widgets/GuideStates.dart';

import 'support/guide_test_support.dart';

AdminProfile profile(String id, String role, {String team = ''}) => AdminProfile.fromMap({
      'id': id,
      'displayName': id,
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

Map<String, dynamic> comp(
  String name, {
  required String category,
  required String gender,
  double weekly = 0,
  double monthly = 0,
  int days = 0,
  String guide = 'E1',
  String team = 'G',
}) =>
    {
      'Name': name,
      'category': category,
      'gender': gender,
      'scopeGender': gender,
      'scopeGuide': guide,
      'scopeTeam': team,
      'weekly.total_score': weekly,
      'weekly.days_count': days,
      'monthly.total_score': monthly,
      'monthly.days_count': days,
    };

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  final docs = <Map<String, dynamic>>[
    // Guide G's team (boys)
    comp('Arjun', category: 'folk', gender: 'male', weekly: 50, monthly: 300, days: 4),
    comp('Bhima', category: 'folk', gender: 'male', weekly: 80, monthly: 200, days: 5),
    comp('Hari', category: 'hostel_localite', gender: 'male', weekly: 60, monthly: 250, days: 3),
    comp('Hans', category: 'hostel_localite', gender: 'male', weekly: 0, monthly: 0, days: 0),
    // unassigned boy
    comp('Hira', category: 'hostel_localite', gender: 'male', weekly: 30, monthly: 90, days: 2, guide: '', team: ''),
    // another guide's team
    comp('Dev', category: 'hostel_localite', gender: 'male', weekly: 99, monthly: 99, days: 6, guide: 'E9', team: 'G9'),
    // girls (Female Enabler F1)
    comp('Radha', category: 'folk', gender: 'female', weekly: 70, monthly: 70, days: 5, guide: 'F1', team: ''),
    comp('Gopi', category: 'hostel_localite', gender: 'female', weekly: 55, monthly: 155, days: 4, guide: 'F1', team: ''),
    comp('Gita', category: 'hostel_localite', gender: 'female', weekly: 65, monthly: 65, days: 4, guide: 'F1', team: ''),
  ];
  for (final d in docs) {
    await db.collection('competition').doc(d['Name'] as String).set(d);
  }
  // not yet stamped with a category: in no ranking
  await db.collection('competition').doc('Old').set({'Name': 'Old', 'gender': 'male', 'scopeGender': 'male', 'scopeGuide': 'E1', 'scopeTeam': 'G', 'weekly.total_score': 500, 'weekly.days_count': 1});
  return db;
}

Future<void> open(WidgetTester tester, AdminProfile p, {double scale = 1.0, bool dark = false}) async {
  phone(tester, scale);
  AdminProfileProvider.instance.debugSet(p);
  GuideDb.useForTests(await seeded());
  await tester.pumpWidget(guideHost(const LeaderboardPage(), dark: dark));
  await tester.pumpAndSettle();
}

Finder chip(String label) => find.text(label, findRichText: true);

List<String> names(WidgetTester tester, Iterable<String> all) =>
    [for (final n in all) if (find.text(n).evaluate().isNotEmpty) n];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
    LeaderboardData.instance = const FirestoreLeaderboardData();
  });

  const everyone = ['Arjun', 'Bhima', 'Hari', 'Hans', 'Hira', 'Dev', 'Radha', 'Gopi', 'Gita', 'Old'];

  group('ranking (data)', () {
    test('best first, quiet students are not ranked, ties by name', () async {
      final db = await seeded();
      final snap = await db.collection('competition').where('category', isEqualTo: 'folk').get();
      final w = rankCompetition(snap.docs, LeaderboardPeriod.weekly);
      expect(w.map((e) => e.name), ['Bhima', 'Radha', 'Arjun']);
      final m = rankCompetition(snap.docs, LeaderboardPeriod.monthly);
      expect(m.map((e) => e.name), ['Arjun', 'Bhima', 'Radha']);
      expect(rankCompetition((await db.collection('competition').where('category', isEqualTo: 'hostel_localite').get()).docs, LeaderboardPeriod.weekly).map((e) => e.name),
          isNot(contains('Hans')));
    });

    test('labels', () {
      expect(categoryLabel('folk'), 'FOLK');
      expect(categoryLabel('hostel_localite'), 'Hostel & Localite');
    });
  });

  group('a Guide: his team + unassigned boys, never girls or another team', () {
    testWidgets('FOLK first; the category selector switches to Hostel & Localite', (tester) async {
      await open(tester, profile('G', 'GUIDE'));
      expect(find.byType(GuideChoiceChip), findsNWidgets(4), reason: 'category x2 + period x2; no Boys/Girls for a guide');
      expect(chip('Boys'), findsNothing);
      expect(names(tester, everyone), ['Arjun', 'Bhima'], reason: 'FOLK boys of the team; the unstamped doc is in no ranking');
      // ranked best first: Bhima (80) above Arjun (50)
      expect(tester.getTopLeft(find.text('Bhima')).dy, lessThan(tester.getTopLeft(find.text('Arjun')).dy));

      await tester.tap(chip('Hostel & Localite'));
      await tester.pumpAndSettle();
      expect(names(tester, everyone), ['Hari', 'Hira'], reason: 'team + unassigned; not Dev (other team), not Hans (no score), not girls');
      expect(tester.getTopLeft(find.text('Hari')).dy, lessThan(tester.getTopLeft(find.text('Hira')).dy));

      await tester.tap(chip('FOLK'));
      await tester.pumpAndSettle();
      expect(names(tester, everyone), ['Arjun', 'Bhima']);
    });

    testWidgets('the period toggle re-ranks (monthly: Arjun 300 above Bhima 200)', (tester) async {
      await open(tester, profile('G', 'GUIDE'));
      await tester.tap(chip('This month'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Arjun')).dy, lessThan(tester.getTopLeft(find.text('Bhima')).dy));
    });
  });

  group('an Enabler', () {
    testWidgets('a Male Enabler sees his own students (+ unassigned boys) only', (tester) async {
      await open(tester, profile('E1', 'MALE_ENABLER', team: 'G'));
      await tester.tap(chip('Hostel & Localite'));
      await tester.pumpAndSettle();
      expect(names(tester, everyone), ['Hari', 'Hira']);
    });

    testWidgets('a Female Enabler is fixed to girls: Hostel & Localite shows Gita above Gopi; FOLK shows Radha', (tester) async {
      await open(tester, profile('F1', 'FEMALE_ENABLER'));
      expect(chip('Boys'), findsNothing);
      expect(names(tester, everyone), ['Radha']);
      await tester.tap(chip('Hostel & Localite'));
      await tester.pumpAndSettle();
      expect(names(tester, everyone), ['Gopi', 'Gita']);
      expect(tester.getTopLeft(find.text('Gita')).dy, lessThan(tester.getTopLeft(find.text('Gopi')).dy));
    });
  });

  group('a HOD', () {
    testWidgets('sees everyone, chooses Boys or Girls, and the four rankings stay apart', (tester) async {
      await open(tester, profile('H', 'HOD'));
      expect(tester.widgetList<GuideChoiceChip>(find.byType(GuideChoiceChip)).map((c) => c.label),
          ['FOLK', 'Hostel & Localite', 'Boys', 'Girls', 'This week', 'This month']);
      expect(names(tester, everyone), ['Arjun', 'Bhima']);
      await tester.tap(chip('Hostel & Localite'));
      await tester.pumpAndSettle();
      expect(names(tester, everyone), ['Hari', 'Hira', 'Dev'], reason: 'every H&L boy with a score, best first below');
      expect(tester.getTopLeft(find.text('Dev')).dy, lessThan(tester.getTopLeft(find.text('Hari')).dy));
      await tester.tap(chip('Girls'));
      await tester.pumpAndSettle();
      expect(names(tester, everyone), ['Gopi', 'Gita']);
      await tester.tap(chip('FOLK'));
      await tester.pumpAndSettle();
      expect(names(tester, everyone), ['Radha']);
    });
  });

  group('states', () {
    testWidgets('empty: a friendly line, no spinner', (tester) async {
      phone(tester, 1.0);
      AdminProfileProvider.instance.debugSet(profile('G2', 'GUIDE'));
      GuideDb.useForTests(await seeded());
      await tester.pumpWidget(guideHost(const LeaderboardPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('No scores yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('error: a message and Retry, which loads again', (tester) async {
      phone(tester, 1.0);
      AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE'));
      final fake = _FlakyData();
      LeaderboardData.instance = fake;
      await tester.pumpWidget(guideHost(const LeaderboardPage()));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Arjun'), findsOneWidget);
      expect(fake.calls, 2);
    });

    testWidgets('loading shows ghosts, not a spinner', (tester) async {
      phone(tester, 1.0);
      AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE'));
      final fake = _SlowData();
      LeaderboardData.instance = fake;
      await tester.pumpWidget(guideHost(const LeaderboardPage()));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(GuideStateView), findsOneWidget);
      fake.done.complete(const []);
      await tester.pumpAndSettle();
    });
  });

  group('layout: light and dark, text 1.0 / 1.3 / 1.6, no overflow', () {
    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'} text $scale (HOD, every selector)', (tester) async {
          await open(tester, profile('H', 'HOD'), scale: scale, dark: dark);
          expectNoOverflow(tester);
          for (final label in ['Hostel & Localite', 'Girls', 'This month', 'FOLK', 'Boys']) {
            await tester.tap(chip(label));
            await tester.pumpAndSettle();
            expectNoOverflow(tester, reason: '$label at $scale');
          }
        });
      }
    }
  });

  group('the Analysis tab', () {
    testWidgets('has a Leaderboard card that opens the page', (tester) async {
      phone(tester, 1.0);
      AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE'));
      GuideDb.useForTests(await seeded());
      await tester.pumpWidget(guideHost(Scaffold(body: CompetitionPage())));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.scrollUntilVisible(find.text('Leaderboard'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Leaderboard'));
      await tester.pumpAndSettle();
      expect(find.byType(LeaderboardPage), findsOneWidget);
    });
  });

  bestPerformerTests();
}


// ------------------------------------------------------------------ Best performer

Future<FakeFirebaseFirestore> withWinners({bool oldWeekToo = true}) async {
  final db = await seeded();
  Future<void> week(String id, String at, Map<String, Map<String, dynamic>> byRanking) async {
    final ref = db.collection('competition-results').doc('weekly').collection('weeks').doc(id);
    await ref.set({'generatedAt': at});
    for (final e in byRanking.entries) {
      await ref.collection('byCategory').doc(e.key).set(e.value);
    }
  }

  Map<String, dynamic> improved(String n, num inc, {String guide = 'E1', String team = 'G'}) =>
      {'name': n, 'increase': inc, 'reason': '+$inc points vs last week', 'scopeGuide': guide, 'scopeTeam': team};
  Map<String, dynamic> keeper(String n, int c, int d, {String guide = 'E1', String team = 'G'}) =>
      {'name': n, 'commitment': c, 'daysMet': d, 'reason': 'kept $c rounds on $d of 7 days', 'scopeGuide': guide, 'scopeTeam': team};
  if (oldWeekToo) {
    await week('2026-W41', '2026-10-11T00:05:00.000', {
      'folk_male': {'mostImproved': improved('Old Winner', 1), 'commitmentKeeper': null},
    });
  }
  await week('2026-W42', '2026-10-18T00:05:00.000', {
    'folk_male': {'mostImproved': improved('Arjun', 24), 'commitmentKeeper': keeper('Dev Far', 16, 6, guide: 'E9', team: 'G9')},
    'hostel_localite_male': {'mostImproved': null, 'commitmentKeeper': keeper('Hari', 16, 6)},
    'folk_female': {'mostImproved': improved('Radha', 7, guide: 'F1', team: ''), 'commitmentKeeper': null},
    'hostel_localite_female': {'mostImproved': null, 'commitmentKeeper': keeper('Gopi', 8, 5, guide: 'F1', team: '')},
  });
  return db;
}

Future<void> openWithWinners(WidgetTester tester, AdminProfile p, {double scale = 1.0, bool dark = false, bool winners = true}) async {
  phone(tester, scale);
  AdminProfileProvider.instance.debugSet(p);
  GuideDb.useForTests(winners ? await withWinners() : await seeded());
  await tester.pumpWidget(guideHost(const LeaderboardPage(), dark: dark));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
  await tester.pumpAndSettle();
}

void bestPerformerTests() {
  group('Best performer section', () {
    testWidgets('a Guide sees both winners of BOTH categories for boys, and who is in his group', (tester) async {
      await openWithWinners(tester, profile('G', 'GUIDE'));
      expect(find.text('BEST PERFORMER'), findsOneWidget);
      expect(find.text('Arjun'), findsWidgets);
      expect(find.text('+24 points vs last week'), findsOneWidget);
      expect(find.text('Dev Far'), findsOneWidget);
      expect(find.text('kept 16 rounds on 6 of 7 days'), findsNWidgets(2), reason: 'Dev Far (FOLK) and Hari (Hostel & Localite)');
      expect(find.text('Hari'), findsOneWidget);
      expect(find.text('No winner this week.'), findsOneWidget, reason: 'Hostel & Localite has no most-improved winner');
      // in his group: Arjun (team G) and Hari (team G); not Dev Far (another team)
      expect(find.text('In your group'), findsNWidgets(2));
      // never the girls, never an older week
      for (final n in ['Gopi', 'Old Winner']) {
        expect(find.text(n), findsNothing, reason: n);
      }
      expect(find.text('+7 points vs last week'), findsNothing, reason: 'the girls winner');
    });

    testWidgets('a Female Enabler sees the girls winners only', (tester) async {
      await openWithWinners(tester, profile('F1', 'FEMALE_ENABLER'));
      expect(find.text('+7 points vs last week'), findsOneWidget, reason: 'Radha, FOLK girls');
      expect(find.text('kept 8 rounds on 5 of 7 days'), findsOneWidget, reason: 'Gopi, Hostel & Localite girls');
      expect(find.text('Arjun'), findsNothing);
      expect(find.text('In your group'), findsNWidgets(2));
    });

    testWidgets('a HOD follows the Boys / Girls choice; everyone is in his scope', (tester) async {
      await openWithWinners(tester, profile('H', 'HOD'));
      expect(find.text('Dev Far'), findsOneWidget);
      expect(find.text('In your group'), findsNWidgets(3));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      await tester.tap(chip('Girls'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('+7 points vs last week'), findsOneWidget);
      expect(find.text('kept 8 rounds on 5 of 7 days'), findsOneWidget);
      expect(find.text('Arjun'), findsNothing);
    });

    testWidgets('no weekly results yet: a friendly line', (tester) async {
      await openWithWinners(tester, profile('G', 'GUIDE'), winners: false);
      expect(find.textContaining('No winners yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an error offers Retry', (tester) async {
      phone(tester, 1.0);
      AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE'));
      final data = _BestFlaky();
      LeaderboardData.instance = data;
      await tester.pumpWidget(guideHost(const LeaderboardPage()));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the winners just now."), findsOneWidget);
      await tester.tap(find.text('Retry').last);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('+3 points vs last week'), findsOneWidget);
      expect(data.calls, 2);
    });

    test('scope rule: HOD all; Guide his team and unassigned boys; Enabler their own and unassigned', () {
      final guide = profile('G', 'GUIDE');
      final enabler = profile('E1', 'MALE_ENABLER');
      final femaleEnabler = profile('F1', 'FEMALE_ENABLER');
      expect(winnerInScope(profile('H', 'HOD'), scopeGuide: 'x', scopeTeam: 'y', gender: 'female'), isTrue);
      expect(winnerInScope(guide, scopeGuide: 'E1', scopeTeam: 'G', gender: 'male'), isTrue);
      expect(winnerInScope(guide, scopeGuide: 'E9', scopeTeam: 'G9', gender: 'male'), isFalse);
      expect(winnerInScope(guide, scopeGuide: '', scopeTeam: '', gender: 'male'), isTrue);
      expect(winnerInScope(enabler, scopeGuide: 'E1', scopeTeam: 'G', gender: 'male'), isTrue);
      expect(winnerInScope(enabler, scopeGuide: 'E2', scopeTeam: 'G', gender: 'male'), isFalse);
      expect(winnerInScope(femaleEnabler, scopeGuide: '', scopeTeam: '', gender: 'female'), isTrue);
      expect(winnerInScope(femaleEnabler, scopeGuide: 'F2', scopeTeam: '', gender: 'female'), isFalse);
      expect(parseBestWinner(null, guide, 'male'), isNull);
      expect(parseBestWinner({'name': ' '}, guide, 'male'), isNull);
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'} text $scale: the winners section does not overflow (HOD, both genders)', (tester) async {
          await openWithWinners(tester, profile('H', 'HOD'), scale: scale, dark: dark);
          expectNoOverflow(tester);
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
          await tester.pumpAndSettle();
          await tester.tap(chip('Girls'));
          await tester.pumpAndSettle();
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
          await tester.pumpAndSettle();
          expectNoOverflow(tester);
        });
      }
    }
  });
}

class _BestFlaky implements LeaderboardData {
  int calls = 0;
  @override
  Future<Map<BestField, List<LeaderboardEntry>>> fieldBests({required String category, required String gender, required LeaderboardPeriod period}) async => {};

  @override
  Future<List<LeaderboardEntry>> ranking({required String category, required String gender, required LeaderboardPeriod period}) async =>
      const [LeaderboardEntry(name: 'Arjun', score: 5, days: 1)];

  @override
  Future<Map<String, BestPerformerSet>> bestPerformers({required String gender}) async {
    calls++;
    if (calls == 1) throw StateError('offline');
    return {
      'folk': const BestPerformerSet(
        mostImproved: BestWinnerInfo(name: 'Arjun', reason: '+3 points vs last week', inScope: true),
      ),
    };
  }
}

class _FlakyData implements LeaderboardData {
  int calls = 0;
  @override
  Future<Map<BestField, List<LeaderboardEntry>>> fieldBests({required String category, required String gender, required LeaderboardPeriod period}) async => {};

  @override
  Future<List<LeaderboardEntry>> ranking({required String category, required String gender, required LeaderboardPeriod period}) async {
    calls++;
    if (calls == 1) throw StateError('offline');
    return const [LeaderboardEntry(name: 'Arjun', score: 5, days: 1)];
  }

  @override
  Future<Map<String, BestPerformerSet>> bestPerformers({required String gender}) async => {};
}

class _SlowData implements LeaderboardData {
  final done = Completer<List<LeaderboardEntry>>();
  @override
  Future<Map<BestField, List<LeaderboardEntry>>> fieldBests({required String category, required String gender, required LeaderboardPeriod period}) async => {};

  @override
  Future<List<LeaderboardEntry>> ranking({required String category, required String gender, required LeaderboardPeriod period}) => done.future;

  @override
  Future<Map<String, BestPerformerSet>> bestPerformers({required String gender}) async => {};
}
