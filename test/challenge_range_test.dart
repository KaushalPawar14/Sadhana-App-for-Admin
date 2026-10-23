import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/ChantingChallengeManager.dart';
import 'package:folk_guide_app/utils/ChallengeRange.dart';
import 'package:intl/intl.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// Master 2 A — a chanting competition over a span of days.
///
/// The server decides which days count (`functions/challenges.js`); this is
/// the Guide app's half: choosing the span, showing it, and showing who
/// chanted how much on which day. A single day, and a competition made before
/// ranges existed, must keep looking and working exactly as they did.

Map<String, dynamic> range() => {
      'startDateKey': '15-10-2026',
      'endDateKey': '20-10-2026',
      'targetDateKey': '20-10-2026',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  // -------------------------------------------------------------------------
  // reading a span
  // -------------------------------------------------------------------------
  group('the span of a competition', () {
    test('an old single-day competition is a one-day span', () {
      final s = ChallengeSpan.of({'targetDateKey': '12-08-2026'})!;
      expect(s.isRange, isFalse);
      expect(s.dayCount, 1);
      expect(s.label, '12 Aug 2026');
    });

    test('a range reads its own start and end', () {
      final s = ChallengeSpan.of(range())!;
      expect(s.isRange, isTrue);
      expect(s.dayCount, 6);
      expect(s.label, '15 Oct – 20 Oct 2026');
      expect(s.dayLabel, '6 days');
    });

    test('start == end is a single day', () {
      final s = ChallengeSpan.of({
        'startDateKey': '20-10-2026',
        'endDateKey': '20-10-2026',
        'targetDateKey': '20-10-2026',
      })!;
      expect(s.isRange, isFalse);
      expect(s.dayLabel, '1 day');
    });

    test('a range that crosses a year says both years', () {
      final s = ChallengeSpan.of({
        'startDateKey': '29-12-2026',
        'endDateKey': '02-01-2027',
        'targetDateKey': '02-01-2027',
      })!;
      expect(s.label, '29 Dec 2026 – 02 Jan 2027');
      expect(s.dayCount, 5);
    });

    test('with only the timestamp it still finds the day', () {
      final s = ChallengeSpan.of({
        'targetDate': Timestamp.fromDate(DateTime(2026, 8, 12)),
      })!;
      expect(s.label, '12 Aug 2026');
    });

    test('a document with no usable date has no span', () {
      expect(ChallengeSpan.of({}), isNull);
      expect(ChallengeSpan.of({'targetDateKey': 'garbage'}), isNull);
    });

    test('start and end the wrong way round still read sensibly', () {
      final s = ChallengeSpan.of({
        'startDateKey': '20-10-2026',
        'endDateKey': '15-10-2026',
      })!;
      expect(s.start.day, 15);
      expect(s.end.day, 20);
    });

    test('the day keys run in order and cross a month end', () {
      final s = ChallengeSpan.of({
        'startDateKey': '30-10-2026',
        'endDateKey': '02-11-2026',
      })!;
      expect(s.dayKeys, ['30-10-2026', '31-10-2026', '01-11-2026', '02-11-2026']);
    });
  });

  group('reading a day key', () {
    test('a real date parses', () {
      expect(parseChallengeDayKey('05-03-2026'), DateTime(2026, 3, 5));
    });

    test('anything else does not', () {
      for (final bad in [
        '', 'x', '2026-10-15', '32-01-2026', '10-13-2026', '31-02-2026', null,
      ]) {
        expect(parseChallengeDayKey(bad), isNull, reason: '$bad');
      }
    });
  });

  // -------------------------------------------------------------------------
  // choosing one
  // -------------------------------------------------------------------------
  group('what may be created', () {
    final d = DateTime(2026, 10, 15);

    test('one day is allowed', () {
      expect(challengeSpanProblem(d, d), isNull);
    });

    test('a week is allowed', () {
      expect(challengeSpanProblem(d, DateTime(2026, 10, 21)), isNull);
    });

    test('no end date, or no start, says so', () {
      expect(challengeSpanProblem(d, null), 'Choose an end date');
      expect(challengeSpanProblem(null, d), 'Choose a start date');
    });

    test('an end before the start is refused', () {
      expect(challengeSpanProblem(DateTime(2026, 10, 20), d),
          'The end date cannot be before the start date');
    });

    test('exactly the longest allowed is fine, one more is not', () {
      expect(challengeSpanProblem(d, d.add(const Duration(days: 30))), isNull);
      expect(challengeSpanProblem(d, d.add(const Duration(days: 31))),
          'A competition can run for at most $kMaxChallengeDays days');
    });
  });

  // -------------------------------------------------------------------------
  // the day-wise table
  // -------------------------------------------------------------------------
  group('the day-wise table', () {
    final span = ChallengeSpan.of(range())!;

    Map<String, dynamic> row(String name, Map<String, int> byDay) => {
          'studentName': name,
          'rounds': byDay.values.fold(0, (a, b) => a + b),
          'byDay': byDay,
        };

    test('every day of the span gets a row, in order', () {
      final table = buildDayTable(span, [
        row('Ravi', {'15-10-2026': 16}),
      ]);
      expect(table.map((d) => d.dayKey), span.dayKeys);
      expect(table.length, 6);
    });

    test('who chanted how many on which day, and how many students', () {
      final table = buildDayTable(span, [
        row('Ravi', {'15-10-2026': 16, '16-10-2026': 8}),
        row('Om', {'15-10-2026': 4}),
        row('Amit', {'16-10-2026': 12}),
      ]);
      final first = table[0];
      expect(first.studentCount, 2);
      expect(first.rounds, 20);
      expect(first.contributors.map((c) => '${c.name}:${c.rounds}'),
          ['Ravi:16', 'Om:4'], reason: 'most rounds first');

      final second = table[1];
      expect(second.studentCount, 2);
      expect(second.rounds, 20);
      expect(second.contributors.first.name, 'Amit');
    });

    test('a day nobody chanted on is still shown, as empty', () {
      final table = buildDayTable(span, [
        row('Ravi', {'15-10-2026': 16, '18-10-2026': 8}),
      ]);
      final gap = table.firstWhere((d) => d.dayKey == '16-10-2026');
      expect(gap.studentCount, 0);
      expect(gap.rounds, 0);
      expect(gap.contributors, isEmpty);
    });

    test('the days add up to the competition total', () {
      final table = buildDayTable(span, [
        row('Ravi', {'15-10-2026': 16, '16-10-2026': 8}),
        row('Om', {'17-10-2026': 4}),
      ]);
      expect(table.fold(0, (a, d) => a + d.rounds), 28);
    });

    test('a day outside the span is ignored, not added as a column', () {
      final table = buildDayTable(span, [
        row('Ravi', {'15-10-2026': 16, '01-01-2030': 99}),
      ]);
      expect(table.length, 6);
      expect(table.fold(0, (a, d) => a + d.rounds), 16);
    });

    test('a row with no byDay belongs to the last day', () {
      // Written before ranges: its competition was a single day.
      final table = buildDayTable(span, [
        {'studentName': 'Old', 'rounds': 12},
      ]);
      expect(table.last.dayKey, '20-10-2026');
      expect(table.last.rounds, 12);
      expect(table.first.rounds, 0);
    });

    test('zero and junk rounds are not counted as a contribution', () {
      final table = buildDayTable(span, [
        row('Ravi', {'15-10-2026': 0}),
        {'studentName': 'X', 'byDay': {'15-10-2026': 'many'}},
      ]);
      expect(table.first.studentCount, 0);
    });
  });

  // -------------------------------------------------------------------------
  // the screens
  // -------------------------------------------------------------------------
  Future<void> seed(dynamic db, {bool withRows = true}) async {
    await db.collection('chantingChallenges').doc('c-range').set({
      'name': 'Kartik Week',
      'targetRounds': 500,
      'currentTotal': 44,
      'status': 'active',
      'guideId': 'H',
      'createdBy': 'H',
      ...range(),
      'startDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
      'targetDate': Timestamp.fromDate(DateTime(2026, 10, 20)),
    });
    await db.collection('chantingChallenges').doc('c-old').set({
      'name': 'Ekadashi',
      'targetRounds': 300,
      'currentTotal': 12,
      'status': 'active',
      'guideId': 'H',
      'createdBy': 'H',
      'targetDateKey': '12-08-2026',
      'targetDate': Timestamp.fromDate(DateTime(2026, 8, 12)),
    });
    if (!withRows) return;
    Future<void> r(String id, String uid, String name, Map<String, int> byDay) =>
        db.collection('chantingChallengeContributions').doc('${id}_$uid').set({
          'challengeId': id,
          'studentUid': uid,
          'studentName': name,
          'guideId': 'G',
          'rounds': byDay.values.fold(0, (a, b) => a + b),
          'byDay': byDay,
        });
    await r('c-range', 's1', 'Arjun Kumar', {'15-10-2026': 16, '16-10-2026': 8});
    await r('c-range', 's2', 'Bhima Sen', {'15-10-2026': 4, '17-10-2026': 16});
    await db.collection('chantingChallengeContributions').doc('c-old_s1').set({
      'challengeId': 'c-old',
      'studentUid': 's1',
      'studentName': 'Arjun Kumar',
      'guideId': 'G',
      'rounds': 12,
    });
  }

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      final mode = '${dark ? 'dark' : 'light'}, text $scale';

      testWidgets('the list shows a range and a single day ($mode)', (tester) async {
        final db = await prepareApp(tester);
        await seed(db);
        await pumpScreen(tester, const ChantingChallengeManagerPage(),
            scale: scale, dark: dark);
        await tester.pumpAndSettle();

        expect(find.text('15 Oct – 20 Oct 2026'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('12 Aug 2026'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('12 Aug 2026'), findsOneWidget,
            reason: 'a competition made before ranges looks as it did');
        expect(tester.takeException(), isNull);
      });

      testWidgets('the results show the ranking AND the day-wise table ($mode)',
          (tester) async {
        final db = await prepareApp(tester);
        await seed(db);
        await pumpScreen(
            tester,
            ChallengeContributionsPage(
              challengeId: 'c-range',
              challengeName: 'Kartik Week',
              target: 500,
              total: 44,
              span: ChallengeSpan.of(range()),
            ),
            scale: scale,
            dark: dark);
        await tester.pumpAndSettle();

        expect(find.text('Day by day'), findsOneWidget);
        // The ranking sits below six day rows, so at large text it is past the
        // fold; scroll to it the way a guide would.
        await tester.scrollUntilVisible(find.text('Total ranking'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Total ranking'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Bhima Sen'), 200,
            scrollable: find.byType(Scrollable).first);
        // both students are in the ranking, with their TOTALS
        expect(find.text('Arjun Kumar'), findsOneWidget);
        expect(find.text('Bhima Sen'), findsOneWidget);
        expect(find.text('24', skipOffstage: false), findsWidgets,
            reason: 'Arjun: 16 + 8');
        expect(find.text('20', skipOffstage: false), findsWidgets,
            reason: 'Bhima: 4 + 16');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a day opens to show who chanted how many', (tester) async {
    final db = await prepareApp(tester);
    await seed(db);
    await pumpScreen(
        tester,
        ChallengeContributionsPage(
          challengeId: 'c-range',
          challengeName: 'Kartik Week',
          target: 500,
          total: 44,
          span: ChallengeSpan.of(range()),
        ));
    await tester.pumpAndSettle();

    final firstDay = find.byKey(const ValueKey('day-15-10-2026'));
    expect(firstDay, findsOneWidget);
    await tester.ensureVisible(firstDay);
    await tester.tap(firstDay);
    await tester.pumpAndSettle();

    expect(find.text('2 students'), findsWidgets);
    // 15 Oct: Arjun 16, Bhima 4 — total 20
    expect(find.text('16'), findsWidgets);
    expect(find.text('4'), findsWidgets);
  });

  testWidgets('a single-day competition has no day-wise table', (tester) async {
    final db = await prepareApp(tester);
    await seed(db);
    await pumpScreen(
        tester,
        ChallengeContributionsPage(
          challengeId: 'c-old',
          challengeName: 'Ekadashi',
          target: 300,
          total: 12,
          span: ChallengeSpan.of({'targetDateKey': '12-08-2026'}),
        ));
    await tester.pumpAndSettle();

    expect(find.text('Day by day'), findsNothing,
        reason: 'one day IS the ranking; a one-row table would say nothing');
    expect(find.text('Arjun Kumar'), findsOneWidget);
    expect(find.text('12'), findsWidgets);
  });

  testWidgets('a competition with no contributions says so, with no table',
      (tester) async {
    final db = await prepareApp(tester);
    await seed(db, withRows: false);
    await pumpScreen(
        tester,
        ChallengeContributionsPage(
          challengeId: 'c-range',
          challengeName: 'Kartik Week',
          target: 500,
          total: 0,
          span: ChallengeSpan.of(range()),
        ));
    await tester.pumpAndSettle();
    expect(find.text('No contributions yet.'), findsOneWidget);
    expect(find.text('Day by day'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // creating one
  // -------------------------------------------------------------------------
  Future<void> openCreate(WidgetTester tester, {double scale = 1.0, bool dark = false}) async {
    await pumpScreen(tester, const ChantingChallengeManagerPage(),
        scale: scale, dark: dark);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Challenge'));
    await tester.pumpAndSettle();
  }

  testWidgets('the dialog asks for a start AND an end date', (tester) async {
    await prepareApp(tester);
    await openCreate(tester);
    expect(find.byKey(const ValueKey('challenge-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('challenge-end')), findsOneWidget);
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('End date'), findsOneWidget);
  });

  for (final scale in kScales) {
    testWidgets('the create dialog fits at text $scale, light and dark',
        (tester) async {
      for (final dark in [false, true]) {
        await prepareApp(tester);
        await openCreate(tester, scale: scale, dark: dark);
        expect(find.text('Start date'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'dark=$dark');
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('creating without dates is refused with a reason', (tester) async {
    final db = await prepareApp(tester);
    await openCreate(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Challenge name'), 'Test');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Target rounds (whole roster)'), '100');
    final before = (await db.collection('chantingChallenges').get()).docs.length;
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Choose an end date'), findsOneWidget);
    final after = (await db.collection('chantingChallenges').get()).docs.length;
    expect(after, before, reason: 'nothing written for a refused create');
  });

  testWidgets('one tap on the start fills the end — a single day is one choice',
      (tester) async {
    final db = await prepareApp(tester);
    await openCreate(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Challenge name'), 'Today only');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Target rounds (whole roster)'), '100');

    await tester.tap(find.byKey(const ValueKey('challenge-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('1 day'), findsOneWidget, reason: 'end followed the start');

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    final docs = (await db.collection('chantingChallenges').get())
        .docs.where((d) => d.data()['name'] == 'Today only').toList();
    expect(docs.length, 1);
    final data = docs.single.data();
    final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
    expect(data['startDateKey'], today);
    expect(data['endDateKey'], today);
    expect(data['targetDateKey'], today,
        reason: 'the key every older reader still matches on');
    expect(data['targetDate'], isA<Timestamp>());
    expect(data['currentTotal'], 0);
    expect(data['status'], 'active');
  });

  testWidgets('a real range is stored with its end as the target day',
      (tester) async {
    final db = await prepareApp(tester);
    await openCreate(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Challenge name'), 'This month');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Target rounds (whole roster)'), '900');

    // End = today.
    await tester.tap(find.byKey(const ValueKey('challenge-end')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Start = the 1st of this month (never more than 30 days back, so always
    // selectable and always inside the 31-day limit).
    final now = DateTime.now();
    if (now.day > 1) {
      await tester.tap(find.byKey(const ValueKey('challenge-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    final data = (await db.collection('chantingChallenges').get())
        .docs.singleWhere((d) => d.data()['name'] == 'This month').data();
    final first = DateTime(now.year, now.month, 1);
    expect(data['startDateKey'], DateFormat('dd-MM-yyyy').format(first));
    expect(data['endDateKey'], DateFormat('dd-MM-yyyy').format(now));
    expect(data['targetDateKey'], data['endDateKey'],
        reason: 'the last day is what the sweep and old readers use');
    expect((data['targetDate'] as Timestamp).toDate().day, now.day);
  });
}
