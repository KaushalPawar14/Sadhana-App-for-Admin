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
    Future<FakeBoardData> pump(WidgetTester tester, {double scale = 1.0, bool dark = false, List<HistoryLine>? lines, Size size = const Size(360, 800)}) async {
      phone(tester, scale, size: size);
      final data = FakeBoardData(users: const {})..histories['u1'] = lines ?? manyHistoryLines();
      BoardData.instance = data;
      addTearDown(() => BoardData.instance = const FirestoreBoardData());
      await tester.pumpWidget(guideHost(Scaffold(body: SingleChildScrollView(child: StudentHistoryList(studentUid: 'u1'))), dark: dark));
      await tester.pump();
      await tester.pump();
      return data;
    }

    testWidgets('one line each; the lines never wrap; the first section (it has lines) is open, the rest closed', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('history-list')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && (w.maxLines == 1) && (w.data ?? '').startsWith('Line ')), findsWidgets);
      expect(find.byKey(const ValueKey('history-cat-lines-interactions')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-cat-lines-sadhana')), findsNothing, reason: 'closed until tapped');
      expect(find.byKey(const ValueKey('history-line-h29')), findsNothing, reason: 'the 30th line is in Sadhana, closed');
      await openAllHistorySections(tester);
      expect(find.byKey(const ValueKey('history-line-h29')), findsOneWidget, reason: 'the 30th');
    });

    testWidgets('SEVEN SECTIONS in the order of the card, each with its count and the date of its latest line', (tester) async {
      await pump(tester, lines: [
        HistoryLine(id: 'interaction_1', kind: kHistoryInteraction, title: 'Talked', detail: 'd', at: DateTime(2026, 10, 29, 10)),
        HistoryLine(id: 'assoc_1_confirmed', kind: kHistoryDealing, title: 'Meeting confirmed', detail: 'd', at: DateTime(2026, 10, 25)),
        HistoryLine(id: 'cross_x', kind: kHistorySurrender, title: 'Surrender crossed 40%', detail: 'd', at: DateTime(2026, 10, 28)),
        HistoryLine(id: 'chantavg_w', kind: kHistorySadhana, title: 'Chanting up', detail: 'd', at: DateTime(2026, 10, 27)),
        HistoryLine(id: 'chantavg_w2', kind: kHistorySadhana, title: 'Chanting up again', detail: 'd', at: DateTime(2026, 10, 20)),
        HistoryLine(id: 'book_b1_finished', kind: kHistoryDealing, title: 'Finished Gita', detail: 'd', at: DateTime(2026, 10, 10)),
        HistoryLine(id: 'trip_r1', kind: kHistoryDealing, title: 'Registered for Mayapur', detail: 'd', at: DateTime(2026, 9, 30)),
        HistoryLine(id: 'concern_open_f', kind: kHistoryDealing, title: 'Worrying message', detail: 'd', at: DateTime(2026, 10, 22)),
        HistoryLine(id: 'doubt_open_d_1', kind: kHistoryDealing, title: 'Doubt asked', detail: 'd', at: DateTime(2026, 10, 21)),
      ]);
      final order = ['interactions', 'surrender', 'sadhana', 'books', 'trips', 'worries', 'doubts'];
      final labels = ['Interactions & meetings', 'Surrender & targets', 'Sadhana', 'Books', 'Trips & services', 'Worries', 'Doubts'];
      final ys = [for (final k in order) tester.getTopLeft(find.byKey(ValueKey('history-cat-header-$k'))).dy];
      expect(ys, [...ys]..sort(), reason: 'in the order of the card');
      for (var i = 0; i < 7; i++) {
        expect(find.descendant(of: find.byKey(ValueKey('history-cat-header-${order[i]}')), matching: find.text(labels[i])), findsOneWidget, reason: labels[i]);
      }
      String count(String k) => tester.widget<Text>(find.byKey(ValueKey('history-cat-count-$k'))).data!;
      String latest(String k) => tester.widget<Text>(find.byKey(ValueKey('history-cat-latest-$k'))).data!;
      expect([for (final k in order) count(k)], ['2', '1', '2', '1', '1', '1', '1']);
      expect(latest('interactions'), '29 Oct', reason: 'the newest line of the section');
      expect(latest('sadhana'), '27 Oct');
      expect(latest('trips'), '30 Sep');
    });

    testWidgets('a section opens and closes with a tap on its header; its lines are newest first; a line opens the details', (tester) async {
      await pump(tester, lines: [
        HistoryLine(id: 'book_old', kind: kHistoryDealing, title: 'Book: older', detail: 'The older book.', at: DateTime(2026, 9, 1)),
        HistoryLine(id: 'book_new', kind: kHistoryDealing, title: 'Finished Gita', detail: 'He finished the Gita.', at: DateTime(2026, 10, 10)),
      ]);
      expect(find.byKey(const ValueKey('history-cat-lines-books')), findsNothing, reason: 'closed by default (the first section has nothing)');
      expect(find.byKey(const ValueKey('history-cat-lines-interactions')), findsNothing, reason: 'the first section is empty: nothing opens by itself');
      await tester.tap(find.byKey(const ValueKey('history-cat-header-books')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-cat-lines-books')), findsOneWidget);
      expect(tester.getTopLeft(find.text('Finished Gita')).dy, lessThan(tester.getTopLeft(find.text('Book: older')).dy), reason: 'newest first');
      await tester.tap(find.text('Finished Gita'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-dialog-title')), findsOneWidget);
      expect(find.text('He finished the Gita.'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-cat-header-books')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-cat-lines-books')), findsNothing, reason: 'closed again');
      // an empty section does not open
      await tester.tap(find.byKey(const ValueKey('history-cat-header-doubts')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-cat-lines-doubts')), findsNothing);
    });

    testWidgets('30 PER CATEGORY: a category shows its 30 newest; the other categories are not cut by it (the old overall limit is gone)', (tester) async {
      await pump(tester, lines: [
        for (var i = 0; i < 40; i++) HistoryLine(id: 'interaction_$i', kind: kHistoryInteraction, title: 'Talk $i', detail: 'd', at: DateTime(2026, 8, 1).add(Duration(days: i))),
        for (var i = 0; i < 12; i++) HistoryLine(id: 'doubt_open_${i}_1', kind: kHistoryDealing, title: 'Doubt $i', detail: 'd', at: DateTime(2026, 7, 1).add(Duration(days: i))),
      ].toList());
      // (the widget shows what the stream gives: the server and HistoryLine.fromDoc trim; the fake stream gives the lines as they are)
      expect(tester.widget<Text>(find.byKey(const ValueKey('history-cat-count-doubts'))).data, '12');
      final fromDoc = HistoryLine.fromDoc({
        'items': [
          for (var i = 0; i < 40; i++) _line('interaction_$i', 'interaction', 'Talk $i', DateTime(2026, 8, 1).add(Duration(days: i))),
          for (var i = 0; i < 12; i++) _line('doubt_open_${i}_1', 'dealing', 'Doubt $i', DateTime(2026, 7, 1).add(Duration(days: i))),
        ],
      });
      expect(fromDoc.where((l) => l.category == 'interactions').length, 30);
      expect(fromDoc.where((l) => l.category == 'doubts').length, 12, reason: 'untouched');
      expect(fromDoc.where((l) => l.category == 'interactions').first.id, 'interaction_39');
      expect(fromDoc.where((l) => l.category == 'interactions').last.id, 'interaction_10', reason: 'the 10 oldest are gone');
    });

    test('a line carries the category the server wrote; an old line without one gets it from its kind and id', () {
      final lines = HistoryLine.fromDoc({
        'items': [
          {..._line('x1', 'dealing', 'Server says books', DateTime(2026, 10, 3)), 'category': 'books'},
          _line('book_b', 'dealing', 'Old book line', DateTime(2026, 10, 2)),
          {..._line('y', 'dealing', 'Bogus category', DateTime(2026, 10, 1)), 'category': 'nonsense'},
          _line('doubt_closed_d', 'dealing', 'Doubt answered', DateTime(2026, 9, 30)),
          _line('concern_open_c', 'dealing', 'Worry', DateTime(2026, 9, 29)),
          _line('trip_t', 'dealing', 'Trip', DateTime(2026, 9, 28)),
          _line('cross_a', 'surrender', 'Crossed', DateTime(2026, 9, 27)),
          _line('commit_12', 'sadhana', 'Commit', DateTime(2026, 9, 26)),
        ],
      });
      expect({for (final l in lines) l.id: l.category}, {
        'x1': 'books', 'book_b': 'books', 'y': 'interactions', 'doubt_closed_d': 'doubts', 'concern_open_c': 'worries', 'trip_t': 'trips', 'cross_a': 'surrender', 'commit_12': 'sadhana',
      });
      expect(kHistoryCategories.map((c) => c.label), ['Interactions & meetings', 'Surrender & targets', 'Sadhana', 'Books', 'Trips & services', 'Worries', 'Doubts']);
    });

    for (final size in const {'360': Size(360, 800), '393': Size(393, 851), '412': Size(412, 915), 'website': Size(1400, 900)}.entries) {
      for (final dark in [false, true]) {
        for (final scale in kScales) {
          testWidgets('${size.key} · ${dark ? 'dark' : 'light'} · ×$scale: seven headers, each a 48 dp target, no overflow; every section opens; a line\'s details dialog fits', (tester) async {
            await pump(tester, scale: scale, dark: dark, size: size.value, lines: [
              HistoryLine(id: 'interaction_1', kind: kHistoryInteraction, title: 'Interaction (Call): a rather long line about what was discussed with him this week', detail: 'Full details of the talk. ' * 8, at: DateTime(2026, 10, 29)),
              HistoryLine(id: 'cross_x', kind: kHistorySurrender, title: 'Surrender 40% → 50%', detail: 'd', at: DateTime(2026, 10, 28)),
              HistoryLine(id: 'chantavg_w', kind: kHistorySadhana, title: 'Chanting up 4 rounds a day (8 → 12)', detail: 'd', at: DateTime(2026, 10, 27)),
              HistoryLine(id: 'book_b', kind: kHistoryDealing, title: 'Finished Gita', detail: 'd', at: DateTime(2026, 10, 10)),
              HistoryLine(id: 'trip_t', kind: kHistoryDealing, title: 'Registered for Mayapur', detail: 'd', at: DateTime(2026, 9, 30)),
              HistoryLine(id: 'concern_c', kind: kHistoryDealing, title: 'Worrying message in his AI chat', detail: 'd', at: DateTime(2026, 10, 22)),
              HistoryLine(id: 'doubt_open_d_1', kind: kHistoryDealing, title: 'Doubt asked (Gita)', detail: 'd', at: DateTime(2026, 10, 21)),
            ]);
            expect(tester.takeException(), isNull);
            for (final k in ['interactions', 'surrender', 'sadhana', 'books', 'trips', 'worries', 'doubts']) {
              final r = tester.getRect(find.byKey(ValueKey('history-cat-header-$k')));
              expect(r.height, greaterThanOrEqualTo(48), reason: k);
              expect(r.right, lessThanOrEqualTo(size.value.width), reason: k);
            }
            await openAllHistorySections(tester);
            expect(tester.takeException(), isNull);
            for (final id in ['interaction_1', 'cross_x', 'chantavg_w', 'book_b', 'trip_t', 'concern_c', 'doubt_open_d_1']) {
              expect(find.byKey(ValueKey('history-line-$id')), findsOneWidget, reason: id);
            }
            await tester.ensureVisible(find.byKey(const ValueKey('history-line-doubt_open_d_1')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('history-line-doubt_open_d_1')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byKey(const ValueKey('history-dialog-detail')), findsOneWidget);
          });
        }
      }
    }

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
