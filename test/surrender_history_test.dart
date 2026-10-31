import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/SurrenderData.dart';
import 'package:folk_guide_app/widgets/SurrenderBar.dart';

import 'support/guide_test_support.dart';

// THE SURRENDER HISTORY in the Guide app: the breakdown shows the % of each recent week joined ("52 → 61 → 70 → 80 → 70") and the 10% marks crossed (day, "80 → 70 ↓", cause).

Map<String, dynamic> doc({List<Map<String, dynamic>> weekly = const [], List<Map<String, dynamic>> events = const []}) => {
      'percent': 70,
      'trend': -5,
      'weekly': weekly,
      'events': events,
      'parts': const [],
      'complete': true,
      'residence': 'hostel',
    };

Map<String, dynamic> ev(String day, int from, int to, String dir, String cause) => {'day': day, 'from': from, 'to': to, 'dir': dir, 'fromLevel': from ~/ 10 * 10, 'toLevel': to ~/ 10 * 10, 'cause': cause};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  test('THE DATA: weekly % and events are read from the record; the timeline is the weeks joined, ending at where he is', () {
    final info = SurrenderInfo.fromDoc(doc(
      weekly: [
        {'week': '2026-W40', 'day': '2026-10-02', 'pct': 52},
        {'week': '2026-W41', 'day': '2026-10-09', 'pct': 61.2},
        {'week': '2026-W42', 'day': '2026-10-16', 'pct': 70},
        {'week': '2026-W43', 'day': '2026-10-23', 'pct': 80},
        {'week': '2026-W44', 'day': '2026-10-30', 'pct': 70},
      ],
      events: [ev('2026-10-30', 82, 72, 'down', 'formula')],
    ))!;
    expect(info.weekly, [52, 61, 70, 80, 70]);
    expect(info.weeklyLine(), '52 → 61 → 70 → 80 → 70');
    expect(info.weeklyLine(max: 3), '70 → 80 → 70');
    expect(info.events.single.label, '80 → 70 ↓');
    expect(info.events.single.causeWords, 'the formula changed');
    expect(info.events.single.up, isFalse);
  });

  test('NOTHING TO COMPARE: fewer than two weeks gives no line; an old record without history still reads', () {
    expect(SurrenderInfo.fromDoc(doc(weekly: [{'week': '2026-W44', 'day': '2026-10-30', 'pct': 70}]))!.weeklyLine(), isNull);
    final old = SurrenderInfo.fromDoc({'percent': 40, 'parts': const [], 'complete': true, 'residence': 'hostel'})!;
    expect([old.weekly, old.events, old.weeklyLine()], [isEmpty, isEmpty, isNull]);
    // a broken row is skipped, not a crash
    final odd = SurrenderInfo.fromDoc(doc(weekly: [{'pct': 'x'}, {'week': 'w', 'pct': 55}], events: [{'dir': 'up'}, ev('2026-10-30', 55, 61, 'up', 'lit')]))!;
    expect([odd.weekly, odd.events.length], [[55], 1]);
  });

  test('THE CAUSES are in plain words, an unknown one is shown as written; the day is "30 Oct"', () {
    String words(String c) => SurrenderEvent.fromMap(ev('2026-10-30', 60, 70, 'up', c))!.causeWords;
    expect([words('reports'), words('lit'), words('interaction'), words('meeting'), words('ignore'), words('earlier')], ['new daily reports', 'a new LIT assessment', 'an interaction', 'a meeting', 'ignoring his missing reports', 'earlier records']);
    expect(words('something'), 'something');
    expect([surrenderDayLabel('2026-10-30'), surrenderDayLabel('2026-01-05'), surrenderDayLabel('soon')], ['30 Oct', '5 Jan', 'soon']);
  });

  for (final dark in [false, true]) {
    testWidgets('THE BREAKDOWN shows "Over time": the weekly line and the newest crossings first, each with its cause (${dark ? 'dark' : 'light'})', (tester) async {
      phone(tester, 1.0);
      final info = SurrenderInfo.fromDoc(doc(
        weekly: [
          {'week': '2026-W42', 'day': '2026-10-16', 'pct': 61},
          {'week': '2026-W43', 'day': '2026-10-23', 'pct': 80},
          {'week': '2026-W44', 'day': '2026-10-30', 'pct': 70},
        ],
        events: [ev('2026-10-23', 72, 82, 'up', 'reports'), ev('2026-10-30', 82, 72, 'down', 'formula')],
      ))!;
      await tester.pumpWidget(guideHost(Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showSurrenderBreakdown(c, 'Testing', info), child: const Text('open'))))), dark: dark));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('surrender-weekly'))).data, '61 → 80 → 70');
      expect(find.text('Over time'), findsOneWidget);
      expect(find.text('30 Oct · 80 → 70 ↓ · the formula changed'), findsOneWidget);
      expect(find.text('23 Oct · 70 → 80 ↑ · new daily reports'), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const ValueKey('surrender-event-2026-10-30-82-72'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('surrender-event-2026-10-23-72-82'))).dy), reason: 'newest first');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('NO HISTORY YET: the breakdown has no "Over time" block', (tester) async {
    phone(tester, 1.0);
    final info = SurrenderInfo.fromDoc(doc())!;
    await tester.pumpWidget(guideHost(Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showSurrenderBreakdown(c, 'Testing', info), child: const Text('open'))))), dark: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Over time'), findsNothing);
    expect(find.byKey(const ValueKey('surrender-weekly')), findsNothing);
  });
}
