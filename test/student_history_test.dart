import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/StudentHistory.dart';
import 'package:folk_guide_app/widgets/StudentHistoryList.dart';

import 'board_test.dart' show FakeBoardData, manyHistoryLines;
import 'support/guide_test_support.dart';

/// A student's HISTORY on the board card: one line each, newest first, the last 30, a tap for the full details. Written by the server
/// (`functions/studentHistory.js`, tested there: advice, interactions, dealings, notes, significant sadhana changes, the 30 limit);
/// the app reads and shows it.

Map<String, dynamic> _line(String id, String kind, String title, DateTime at, [String? detail]) =>
    {'id': id, 'kind': kind, 'title': title, 'detail': detail ?? 'Details of $title', 'at': Timestamp.fromDate(at)};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  group('the lines of a history document', () {
    test('newest first, whatever order they were stored in', () {
      final lines = HistoryLine.fromDoc({
        'items': [
          _line('old', 'note', 'Old', DateTime(2026, 10, 1)),
          _line('new', 'advice', 'New', DateTime(2026, 10, 29)),
          _line('mid', 'dealing', 'Mid', DateTime(2026, 10, 15)),
        ],
      });
      expect(lines.map((l) => l.id), ['new', 'mid', 'old']);
    });

    test('at most 30 are shown (the server keeps 30; the app never shows more)', () {
      final lines = HistoryLine.fromDoc({
        'items': [for (var i = 0; i < 45; i++) _line('l$i', 'dealing', 'Line $i', DateTime(2026, 9, 1).add(Duration(days: i)))],
      });
      expect(lines.length, kHistoryMax);
      expect(lines.first.id, 'l44', reason: 'the newest');
      expect(lines.last.id, 'l15');
    });

    test('a line without a title is dropped; without details it falls back to its title; unknown kinds read as a dealing', () {
      final lines = HistoryLine.fromDoc({
        'items': [
          {'id': 'x', 'kind': 'note', 'title': '', 'at': Timestamp.fromDate(DateTime(2026, 10, 1))},
          {'id': 'y', 'title': 'Just a title', 'at': Timestamp.fromDate(DateTime(2026, 10, 2))},
          'nonsense',
        ],
      });
      expect(lines.length, 1);
      expect(lines.single.detail, 'Just a title');
      expect(lines.single.kind, kHistoryDealing);
    });

    test('no document, no items: an empty history', () {
      expect(HistoryLine.fromDoc(null), isEmpty);
      expect(HistoryLine.fromDoc({'items': null}), isEmpty);
    });

    test('every kind has an icon and a label', () {
      for (final k in [kHistoryAdvice, kHistoryInteraction, kHistoryDealing, kHistoryNote, kHistorySadhana]) {
        expect(historyKindLabel(k), isNotEmpty);
        expect(historyIcon(k), isA<IconData>());
      }
      expect(historyDay(DateTime(2026, 10, 29), DateTime(2026, 11, 1)), '29 Oct');
      expect(historyDay(DateTime(2025, 12, 25), DateTime(2026, 11, 1)), '25 Dec 2025');
      expect(historyDayHeading(DateTime(2026, 11, 1, 9), DateTime(2026, 11, 1, 20)), 'Today');
      expect(historyDayHeading(DateTime(2026, 10, 31, 23), DateTime(2026, 11, 1, 1)), 'Yesterday');
      expect(historyDayHeading(DateTime(2026, 10, 29), DateTime(2026, 11, 1)), '29 Oct');
    });
  });

  group('the list on the card', () {
    Future<FakeBoardData> pump(WidgetTester tester, {double scale = 1.0, bool dark = false, List<HistoryLine>? lines, int firstShown = 8}) async {
      phone(tester, scale);
      final data = FakeBoardData(users: const {})..histories['u1'] = lines ?? manyHistoryLines();
      BoardData.instance = data;
      addTearDown(() => BoardData.instance = const FirestoreBoardData());
      await tester.pumpWidget(guideHost(Scaffold(body: SingleChildScrollView(child: StudentHistoryList(studentUid: 'u1', firstShown: firstShown))), dark: dark));
      await tester.pump();
      await tester.pump();
      return data;
    }

    testWidgets('one line each, 8 first and "Show 22 more" for the rest; the lines never wrap', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('history-list')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && (w.maxLines == 1) && (w.data ?? '').startsWith('Line ')), findsWidgets);
      expect(find.text('Show 22 more'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('history-more')));
      await tester.pump();
      expect(find.byKey(const ValueKey('history-more')), findsNothing);
      expect(find.byKey(const ValueKey('history-line-h29')), findsOneWidget, reason: 'the 30th');
    });

    testWidgets('GROUPED BY DAY: one small heading per day, newest first, and no date on the line itself', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      await pump(tester, lines: [
        HistoryLine(id: 'a', kind: kHistoryNote, title: 'Note A', detail: 'd', at: today),
        HistoryLine(id: 'b', kind: kHistoryInteraction, title: 'Interaction B', detail: 'd', at: today.subtract(const Duration(hours: 2))),
        HistoryLine(id: 'c', kind: kHistoryDealing, title: 'Dealing C', detail: 'd', at: today.subtract(const Duration(days: 1))),
        HistoryLine(id: 'd', kind: kHistoryDealing, title: 'Dealing D', detail: 'd', at: DateTime(2020, 3, 4, 9)),
      ]);
      expect(find.text('Today'), findsOneWidget, reason: 'two lines, one heading');
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('4 Mar 2020'), findsOneWidget);
      final y = ['Note A', 'Interaction B', 'Dealing C', 'Dealing D'].map((x) => tester.getTopLeft(find.text(x)).dy).toList();
      expect(y, [...y]..sort(), reason: 'newest first');
      expect(tester.getTopLeft(find.text('Today')).dy, lessThan(y[0]), reason: 'the heading sits above its lines');
    });

    testWidgets('a tap opens a dialog with the full details, the kind and the date', (tester) async {
      await pump(tester, lines: [HistoryLine(id: 'a', kind: kHistoryNote, title: 'Note: keen on service', detail: 'You told the assistant: keen on service, loves cooking.', at: DateTime(2026, 10, 29, 18, 30))]);
      await tester.tap(find.byKey(const ValueKey('history-line-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-dialog-title')), findsOneWidget);
      expect(find.text('You told the assistant: keen on service, loves cooking.'), findsOneWidget);
      expect(find.textContaining('Note · Thu 29 Oct 2026'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-dialog-title')), findsNothing);
    });

    testWidgets('empty: a friendly line; updates live when a line arrives', (tester) async {
      final data = await pump(tester, lines: []);
      expect(find.byKey(const ValueKey('history-empty')), findsOneWidget);
      data.histories['u1'] = [HistoryLine(id: 'n', kind: kHistoryAdvice, title: 'Plan advice: new', detail: 'd', at: DateTime(2026, 10, 29))];
      data.historyC.add(null);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('history-empty')), findsNothing);
      expect(find.text('Plan advice: new'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: no overflow, every line a 48 dp target; the dialog fits', (tester) async {
          await pump(tester, scale: scale, dark: dark);
          expect(tester.takeException(), isNull);
          final r = tester.getRect(find.byKey(const ValueKey('history-line-h1')));
          expect(r.height, greaterThanOrEqualTo(48));
          expect(r.right, lessThanOrEqualTo(360));
          await tester.tap(find.byKey(const ValueKey('history-line-h0')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('history-dialog-detail')), findsOneWidget);
        });
      }
    }
  });
}
