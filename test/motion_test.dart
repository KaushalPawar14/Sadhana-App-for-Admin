import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/theme/GuideTokens.dart';
import 'package:folk_guide_app/widgets/GuideEntry.dart';
import 'package:folk_guide_app/widgets/GuideGhost.dart';
import 'package:folk_guide_app/widgets/GuideStates.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';

import 'support/guide_test_support.dart';

Widget sized(double h, {Key? key}) => SizedBox(key: key, height: h, width: double.infinity);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  group('ghost clock', () {
    testWidgets('one shared clock: all ghosts breathe 0.5-1.0 over 1.8 s, ticker only while ghosts are shown', (tester) async {
      phone(tester, 1.0);
      expect(GhostClock.instance.running, isFalse);
      await tester.pumpWidget(guideHost(
        const Scaffold(
          body: Column(children: [
            GuideGhostList(rows: 2),
            GuideGhostList(rows: 2),
          ]),
        ),
        reduce: false,
      ));
      expect(GhostClock.instance.users, 2);
      expect(GhostClock.instance.running, isTrue);
      final values = <double>[];
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 90));
        values.add(GhostClock.instance.pulse.value);
      }
      expect(values.reduce((a, b) => a < b ? a : b), closeTo(0.5, 0.05));
      expect(values.reduce((a, b) => a > b ? a : b), closeTo(1.0, 0.05));
      // Back to the start of the cycle after 1.8 s.
      await tester.pump(const Duration(milliseconds: 1800 - 20 * 90));
      expect(GhostClock.instance.pulse.value, closeTo(0.5, 0.06));

      await tester.pumpWidget(guideHost(const Scaffold(body: SizedBox()), reduce: false));
      expect(GhostClock.instance.users, 0);
      expect(GhostClock.instance.running, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduce motion: ghosts are drawn at rest and hold no ticker', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(const Scaffold(body: GuideGhostList(rows: 3))));
      expect(GhostClock.instance.running, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('background: the ticker is muted while the app is paused', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(const Scaffold(body: GuideGhostList(rows: 1)), reduce: false));
      expect(GhostClock.instance.running, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 300));
      final frozen = GhostClock.instance.pulse.value;
      await tester.pump(const Duration(milliseconds: 400));
      expect(GhostClock.instance.pulse.value, frozen);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      expect(GhostClock.instance.running, isFalse);
    });

    testWidgets('ghost rows have the real row height and gap', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(const Scaffold(body: GuideGhostList(rows: 3, rowHeight: 72, gap: 10))));
      final rows = find.byType(GuideGhostRow);
      expect(rows, findsNWidgets(3));
      expect(tester.getSize(rows.first).height, 72);
      expect(tester.getRect(rows.at(1)).top - tester.getRect(rows.at(0)).bottom, 10);
    });
  });

  group('state view', () {
    Widget view(GuideLoad s, {VoidCallback? retry, GuideEmptyAction? action}) => guideHost(
          Scaffold(
            body: GuideStateView(
              state: s,
              ghost: sized(300),
              content: sized(300, key: const ValueKey('real')),
              emptyMessage: 'No boards yet. Create your first board.',
              emptyAction: action,
              onRetry: retry,
            ),
          ),
          reduce: false,
        );

    testWidgets('loading -> content cross-fades in 250 ms with no layout jump', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(view(GuideLoad.loading));
      final before = tester.getSize(find.byType(GuideStateView));
      expect(before.height, 300);
      await tester.pumpWidget(view(GuideLoad.content));
      final heights = <double>[];
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        heights.add(tester.getSize(find.byType(GuideStateView)).height);
      }
      expect(heights.every((h) => h == 300), isTrue, reason: '$heights');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('real')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(GhostClock.instance.running, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('empty: a still ghost, one friendly line and the action', (tester) async {
      phone(tester, 1.0);
      var tapped = 0;
      await tester.pumpWidget(view(GuideLoad.empty, action: GuideEmptyAction('Create board', () => tapped++)));
      await tester.pumpAndSettle();
      expect(find.text('No boards yet. Create your first board.'), findsOneWidget);
      expect(GhostClock.instance.running, isFalse, reason: 'a still ghost holds no ticker');
      await tester.tap(find.text('Create board'));
      expect(tapped, 1);
    });

    testWidgets('error: frozen ghost, a short message and Retry; no spinner', (tester) async {
      phone(tester, 1.0);
      var retried = 0;
      await tester.pumpWidget(view(GuideLoad.error, retry: () => retried++));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(GhostClock.instance.running, isFalse);
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });
  });

  group('entry and count-up', () {
    testWidgets('entry: fades in and rises, staggered, plays once and leaves no ticker', (tester) async {
      phone(tester, 1.0);
      Widget page(String t) => guideHost(
            Scaffold(
              body: Column(children: [
                GuideEntry(index: 0, child: Text('a$t')),
                GuideEntry(index: 3, child: Text('b$t')),
              ]),
            ),
            reduce: false,
          );
      await tester.pumpWidget(page('1'));
      final y0 = tester.getTopLeft(find.text('a1')).dy; // starts 14 dp low
      final yb = tester.getTopLeft(find.text('b1')).dy;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.text('a1')).dy, lessThan(y0), reason: 'rising');
      // b waits 150 ms: after 100 ms it has not started to move.
      expect(tester.getTopLeft(find.text('b1')).dy, closeTo(yb, 0.5));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.getTopLeft(find.text('a1')).dy, closeTo(y0 - GuideMotion.entryOffset, 0.5));
      expect(tester.getTopLeft(find.text('b1')).dy, lessThan(yb));
      // New data does not replay it.
      await tester.pumpWidget(page('2'));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduce motion: entry is the plain child', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(const Scaffold(body: GuideEntry(child: Text('x')))));
      expect(find.descendant(of: find.byType(GuideEntry), matching: find.byType(FadeTransition)), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('count-up: 0 -> N in ~600 ms the first time; a live update does not animate', (tester) async {
      phone(tester, 1.0);
      Widget page(String v) => guideHost(Scaffold(body: Center(child: GuideCountUp(v))), reduce: false);
      await tester.pumpWidget(page('24'));
      await tester.pump(const Duration(milliseconds: 100));
      final mid = int.parse(RegExp(r'\d+').firstMatch(
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data!).firstWhere((d) => d != '24'))!.group(0)!);
      expect(mid, inInclusiveRange(1, 23));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('24'), findsOneWidget);
      await tester.pumpWidget(page('31'));
      expect(find.text('31'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('count-up keeps a suffix and the box never changes size', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(
          const Scaffold(body: Center(child: GuideCountUp('12/30', style: TextStyle(fontSize: 24)))),
          reduce: false));
      final w0 = tester.getSize(find.byType(GuideCountUp)).width;
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(find.byType(GuideCountUp)).width, w0);
      await tester.pumpAndSettle();
      expect(find.text('12/30'), findsOneWidget);
    });
  });

  testWidgets('the hero card counts its numbers up on first appearance', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(guideHost(
        const Scaffold(
          body: GuideHeroCard(label: 'THIS WEEK', stats: [
            GuideHeroStat('8', 'Targets'),
            GuideHeroStat('12', 'Follow-ups'),
            GuideHeroStat('3', 'Overdue'),
          ]),
        ),
        reduce: false));
    await tester.pump(const Duration(milliseconds: 100));
    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data!)
        .where((d) => RegExp(r'^\d+$').hasMatch(d))
        .map(int.parse)
        .toList();
    expect(shown.any((n) => n > 0 && n < 12), isTrue, reason: 'still counting: $shown');
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
