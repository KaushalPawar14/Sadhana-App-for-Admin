import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/SurrenderData.dart';

import 'board_test.dart' show FakeBoardData, openBoard, roster;
import 'support/guide_test_support.dart';

// The Surrender % breakdown (tap the bar in a board card's drop-down) must open FULLY on every phone: scrollable when long, with its Close button reachable, light and dark,
// text scale 1.0 / 1.3 / 1.6, and the same on a computer.

SurrenderInfo info({bool long = false, String? cap}) => SurrenderInfo(
      percent: 42,
      trend: 6,
      cap: cap,
      complete: false,
      residence: 'hostel',
      gender: 'male',
      name: 'Arjun Kumar',
      parts: [
        SurrenderPart(key: 'commitment', label: 'Commitment', weight: 10, score: 0.6, points: 6, reason: long ? 'Committed to 12 rounds and 30 min of reading a day. ' * 6 : 'Committed to 12 rounds and 30 min of reading a day.'),
        SurrenderPart(
          key: 'sadhana',
          label: 'Sadhana actually done',
          weight: 40,
          score: 0.1,
          points: 4,
          reason: long ? 'Last 30 days: rounds 70% of 16, reading 20 minutes on average, early rising 12 of 30 days. ' * 6 : 'Reported 3 of 30 days (10%) × (chanting 15 + reading 15 + timings 10 = 40) → 4 of 40. From the daily report forms, the last 30 days.',
          sub: const [
            SurrenderPart(key: 'sadhana_regularity', label: 'Reporting regularity (multiplies the three below)', weight: 1, score: 0.1, points: 0.1, multiplier: true, reason: 'Reported 3 of 30 days (10%)'),
            SurrenderPart(key: 'sadhana_chanting', label: 'Chanting', weight: 15, score: 1, points: 15, reason: 'Averaging 16 of 16 rounds on the days reported → 15 of 15'),
            SurrenderPart(key: 'sadhana_reading', label: 'Reading', weight: 15, score: 1, points: 15, reason: 'Averaging 60 of 60 min of reading on the days reported → 15 of 15'),
            SurrenderPart(key: 'sadhana_timings', label: 'Timings', weight: 10, score: 1, points: 10, reason: 'Timings on the days reported: 100% of the best (wake-up, sleep, japa finish) → 10 of 10'),
          ],
        ),
        SurrenderPart(key: 'attitude', label: 'Association — attitude & willingness', weight: 20, score: 0.8, points: 16, reason: "His guide's latest report: willing; 2 interactions or meetings with his guide in the last 30 days."),
        SurrenderPart(key: 'lit', label: 'LIT', weight: 20, score: 0, points: 0, missing: true, reason: 'No LIT yet → 0 of 20'),
        SurrenderPart(
          key: 'bonus',
          label: 'Bonus',
          weight: 10,
          score: 0.25,
          points: 2.5,
          reason: 'Bonus: 1 of 4 pieces earned (2.5 of 10).',
          sub: const [
            SurrenderPart(key: 'bonus_chanting', label: 'Extraordinary chanting', weight: 2.5, score: 1, points: 2.5, reason: 'Bonus: 52 rounds on 12 Oct → +2.5'),
            SurrenderPart(key: 'bonus_reading', label: 'Extraordinary reading', weight: 2.5, score: 0, points: 0, reason: 'No day with 180+ minutes of reading in the last 30 days → 0 of 2.5'),
            SurrenderPart(key: 'bonus_chanting_commitment', label: 'Chanting above his commitment', weight: 2.5, score: 0, points: 0, reason: 'No chanting commitment recorded → 0 of 2.5'),
            SurrenderPart(key: 'bonus_reading_commitment', label: 'Reading above his commitment', weight: 2.5, score: 0, points: 0, reason: 'Averaging 30 minutes of reading on the days reported, not above his commitment of 60 → 0 of 2.5'),
          ],
        ),
      ],
    );

const sizes = {'360': Size(360, 640), '393': Size(393, 851), '412': Size(412, 915), 'desktop': Size(1400, 900)};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() => SeenMarkers.debugDisable = false);
  tearDown(() {
    HierarchyApi.useForTests(null);
    BoardData.instance = const FirestoreBoardData();
    AdminProfileProvider.instance.debugSet(null);
  });

  for (final s in sizes.entries) {
    for (final scale in kScales) {
      for (final dark in [false, true]) {
        for (final long in [false, true]) {
          testWidgets('${s.key} · ×$scale · ${dark ? 'dark' : 'light'}${long ? ' · long reasons' : ''}: the breakdown opens, shows its parts and can be closed', (tester) async {
            final data = FakeBoardData(users: roster)..surrenders['sg1'] = info(long: long, cap: long ? 'residence' : null);
            await openBoard(tester, data: data, size: s.value, scale: scale, dark: dark, reduce: false);
            await tester.tap(find.text('Arjun Kumar').first);
            await tester.pumpAndSettle();
            final bar = find.byKey(const ValueKey('surrender-bar'));
            await tester.ensureVisible(bar);
            await tester.pumpAndSettle();
            await tester.tap(bar);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'no exception while it builds');
            final title = find.byKey(const ValueKey('surrender-dialog-title'));
            expect(title, findsOneWidget, reason: 'the dialog is there, not only the dimmed screen');
            // really on screen: inside the window, with a size
            final screen = Offset.zero & s.value;
            final box = tester.getRect(title);
            expect(box.height, greaterThan(0));
            expect(screen.contains(box.topLeft) && screen.contains(box.bottomRight), isTrue, reason: 'the title is inside the window: $box');
            // the dialog's card is opaque (fully faded in) and its parts can be reached by scrolling
            final first = find.byKey(const ValueKey('surrender-part-commitment'));
            expect(first, findsOneWidget);
            // THE SADHANA PART: regularity (a multiplier shown as a percent) and its three pieces, each with its reason
            for (final k in ['regularity', 'chanting', 'reading', 'timings']) {
              expect(find.byKey(ValueKey('surrender-sub-sadhana_$k')), findsOneWidget, reason: k);
            }
            expect(find.byKey(const ValueKey('surrender-points-sadhana_regularity')), findsOneWidget);
            expect(tester.widget<Text>(find.byKey(const ValueKey('surrender-points-sadhana_regularity'))).data, '× 10%');
            expect(tester.widget<Text>(find.byKey(const ValueKey('surrender-points-sadhana_chanting'))).data, '15 of 15');
            expect(tester.widget<Text>(find.byKey(const ValueKey('surrender-points-sadhana_timings'))).data, '10 of 10');
            expect(find.text('Reported 3 of 30 days (10%)'), findsOneWidget);
            // THE BONUS: its four pieces of 2.5, each with its points and reason
            for (final k in ['chanting', 'reading', 'chanting_commitment', 'reading_commitment']) {
              expect(find.byKey(ValueKey('surrender-sub-bonus_$k')), findsOneWidget, reason: k);
            }
            expect(tester.widget<Text>(find.byKey(const ValueKey('surrender-points-bonus_chanting'))).data, '2.5 of 2.5');
            expect(tester.widget<Text>(find.byKey(const ValueKey('surrender-points-bonus'))).data, '2.5 of 10');
            expect(find.text('Bonus: 52 rounds on 12 Oct → +2.5'), findsOneWidget);
            expect(find.text('Association — attitude & willingness'), findsOneWidget);
            expect(tester.widget<Text>(find.byKey(const ValueKey('surrender-points-sadhana'))).data, '4 of 40');
            final opacity = tester.widgetList<FadeTransition>(find.ancestor(of: title, matching: find.byType(FadeTransition))).map((f) => f.opacity.value);
            expect(opacity.every((o) => o == 1.0), isTrue, reason: 'faded in all the way: $opacity');
            await tester.scrollUntilVisible(find.text('Close'), 200, scrollable: find.byType(Scrollable).last);
            await tester.pumpAndSettle();
            final close = tester.getRect(find.text('Close'));
            expect(screen.contains(close.center), isTrue, reason: 'Close is on screen: $close');
            await tester.tap(find.text('Close'));
            await tester.pumpAndSettle();
            expect(title, findsNothing);
            await tester.pump(const Duration(seconds: 4));
          });
        }
      }
    }
  }

  // ---- every OTHER dialog the board card opens, at phone widths (the same IntrinsicWidth path a phone's AlertDialog takes)
  for (final s in sizes.entries.where((e) => e.key != 'desktop')) {
    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('${s.key} · ×$scale · ${dark ? 'dark' : 'light'}: a history line opens its details; Close reaches', (tester) async {
          final data = FakeBoardData(users: roster)..surrenders['sg1'] = info();
          await openBoard(tester, data: data, size: s.value, scale: scale, dark: dark, reduce: false);
          await tester.tap(find.text('Arjun Kumar').first);
          await tester.pumpAndSettle();
          final line = find.textContaining('Plan advice: a rather long line').first;
          await tester.ensureVisible(line);
          await tester.pumpAndSettle();
          await tester.tap(line);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('history-dialog-title')), findsOneWidget);
          await tester.scrollUntilVisible(find.text('Close'), 200, scrollable: find.byType(Scrollable).last);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('history-dialog-title')), findsNothing);
          await tester.pump(const Duration(seconds: 4));
        });
      }
    }
  }

  for (final scale in kScales) {
    for (final dark in [false, true]) {
      testWidgets('599 · ×$scale · ${dark ? 'dark' : 'light'}: the drop dialog (reassign) opens and answers at the widest phone width', (tester) async {
        final api = <List<Object?>>[];
        await openBoard(tester, api: api, size: const Size(599, 900), scale: scale, dark: dark, reduce: false);
        final from = tester.getCenter(find.text('Arjun Kumar').first);
        final colX = tester.getCenter(find.text('M1 Das').first);
        final g = await tester.startGesture(from);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
        await g.moveTo(from + const Offset(10, 10));
        await tester.pump();
        await g.moveTo(Offset(colX.dx, colX.dy + 120));
        await tester.pump();
        await g.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'no exception');
        expect(find.text('Reassign this boy?'), findsOneWidget, reason: 'the confirmation is really there');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(api.where((c) => c[0] == 'assignStudent'), isEmpty);
        await tester.pump(const Duration(seconds: 4));
      });
    }
  }
}
