import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/BoardQueries.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenDot.dart';
import 'package:folk_guide_app/widgets/GuideBoard.dart';
import 'package:folk_guide_app/widgets/GuideBoardGhost.dart';
import 'package:folk_guide_app/widgets/GuideBoardMotion.dart';
import 'package:folk_guide_app/widgets/GuideGhost.dart';

import 'board_test.dart' show FakeBoardData, openBoard, roster;
import 'support/guide_test_support.dart';

/// Boards that the test releases by hand.
class SlowBoardData extends FakeBoardData {
  SlowBoardData() : super(users: roster);

  final boardsC = StreamController<List<BoardDoc>>.broadcast();
  int boardListens = 0;

  @override
  Stream<List<BoardDoc>> boards() {
    boardListens++;
    return boardsC.stream;
  }
}

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

  testWidgets('loading: two ghost columns, no spinner; the real board fades in over them without moving', (tester) async {
    final slow = SlowBoardData();
    await openBoard(tester, data: slow, reduce: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(GuideBoardGhost), findsOneWidget);
    expect(GhostClock.instance.running, isTrue);
    final ghostColumn = tester.getRect(find
        .descendant(of: find.byType(GuideBoardGhost), matching: find.byType(ListView))
        .first);

    slow.boardsC.add([FakeBoardData.boardDoc, FakeBoardData.customBoard]);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // The column header, real, is at the ghost's left edge.
    final header = tester.getRect(find.byType(GuideBoardColumnHeader).first);
    expect(header.left, greaterThanOrEqualTo(ghostColumn.left));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('G Das'), findsOneWidget);
    expect(find.byType(GuideBoardGhost), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(GhostClock.instance.running, isFalse);
  });

  testWidgets('a failed load: a frozen ghost, a short message and Retry that listens again', (tester) async {
    final slow = SlowBoardData();
    await openBoard(tester, data: slow, reduce: false);
    slow.boardsC.addError('permission-denied');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Could not load the board'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final before = slow.boardListens;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(slow.boardListens, greaterThan(before));
    slow.boardsC.add([FakeBoardData.boardDoc]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('G Das'), findsOneWidget);
  });

  testWidgets('dragging a card over a column opens a gap there; dropping it settles', (tester) async {
    await openBoard(tester, size: const Size(1400, 900), reduce: false);
    await tester.pumpAndSettle();
    final card = find.text('Dhruva Nair').first;
    final from = tester.getCenter(card);
    final to = tester.getCenter(find.text('G Das').first) + const Offset(0, 120);
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(from + const Offset(10, 10));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final gaps = tester.widgetList<GuideDropGap>(find.byType(GuideDropGap)).where((g) => g.open).toList();
    expect(gaps, hasLength(1), reason: 'only the column under the finger opens a gap');
    final open = tester.getSize(find.byWidgetPredicate((w) => w is GuideDropGap && w.open));
    expect(open.height, greaterThan(50));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // the claim confirmation (a dialog) appears; cancel it
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.widgetList<GuideDropGap>(find.byType(GuideDropGap)).where((g) => g.open), isEmpty);
  });

  testWidgets('every other column keeps zero height gaps (a column is unchanged at rest)', (tester) async {
    await openBoard(tester, size: const Size(1400, 900));
    for (final gap in tester.widgetList<GuideDropGap>(find.byType(GuideDropGap))) {
      expect(gap.open, isFalse);
    }
    expect(tester.getSize(find.byType(GuideDropGap).first).height, 0);
  });

  testWidgets('column headers drift a few dp while the row scrolls; none with reduced motion', (tester) async {
    Future<List<double>> shifts(bool reduce) async {
      await openBoard(tester, reduce: reduce, me: null);
      await tester.pumpAndSettle();
      final out = <double>[];
      for (final p in tester.widgetList<GuideHeaderParallax>(find.byType(GuideHeaderParallax))) {
        final t = find.descendant(of: find.byWidget(p), matching: find.byType(Transform));
        if (t.evaluate().isEmpty) {
          out.add(0);
        } else {
          out.add(tester.widget<Transform>(t.first).transform.getTranslation().x);
        }
      }
      return out;
    }

    final moving = await shifts(false);
    expect(moving, isNotEmpty);
    for (final s in moving) {
      expect(s.abs(), lessThanOrEqualTo(GuideHeaderParallax.maxShift + 0.01));
    }
    final still = await shifts(true);
    expect(still.every((s) => s == 0), isTrue);
  });

  testWidgets('an expanded card fades its details in and leaves no ticker', (tester) async {
    await openBoard(tester, reduce: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arjun Kumar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FadeTransition), findsWidgets);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a card whose book commitment is unseen shows a dot; expanding it does not clear it (the book does)', (tester) async {
    final data = FakeBoardData(users: roster)..unseenCommitmentUids = {'sg1'};
    await openBoard(tester, data: data);
    await tester.pumpAndSettle();
    Finder dotOn(String name) => find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(GuideBoardCardFrame)),
        matching: find.byType(UnseenDot));
    expect(dotOn('Arjun Kumar'), findsOneWidget);
    expect(dotOn('Bhima Sen'), findsNothing, reason: 'only the unseen student');
    await tester.tap(find.text('Arjun Kumar'));
    await tester.pumpAndSettle();
    expect(dotOn('Arjun Kumar'), findsWidgets, reason: 'opening the card is not seeing the book');
  });

  // ------------------------------------------------ the dot on the exact book
  group('unseen book commitments: card -> level -> book', () {
    Finder dotIn(Finder inside) => find.descendant(of: inside, matching: find.byType(UnseenDot));
    Finder row(String text) => find.ancestor(of: find.text(text), matching: find.byType(GestureDetector)).first;
    Finder cardOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(GuideBoardCardFrame));

    FakeBoardData world() => FakeBoardData(users: roster)
      ..unseenBooks = {
        'sg1': {'sg1_level-1_book_3', 'sg1_level-2_book_1'},
      };

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 1.6]) {
        testWidgets('dot on the right level and book, clearing book -> level -> card (${dark ? 'dark' : 'light'}, text scale $scale)', (tester) async {
          final data = world();
          await openBoard(tester, data: data, dark: dark, scale: scale);
          await tester.pumpAndSettle();
          // the card
          final dotsOnRow2 = dotIn(find.descendant(of: cardOf('Arjun Kumar'), matching: find.byType(Row)).first);
          expect(dotsOnRow2, findsWidgets);
          expect(dotIn(cardOf('Bhima Sen')), findsNothing, reason: 'only the student with an unseen book');
          await tester.tap(find.text('Arjun Kumar'));
          await tester.pumpAndSettle();
          // the levels: 1 and 2 have an unseen book (even closed), 3 has none
          expect(dotIn(row('Level 1')), findsOneWidget);
          expect(dotIn(row('Level 2')), findsOneWidget);
          expect(dotIn(row('Level 3')), findsNothing);
          expect(tester.takeException(), isNull);

          // open level 1: book 3 has the dot, book 1 does not
          await tester.tap(find.text('Level 1'));
          await tester.pumpAndSettle();
          expect(dotIn(row('Book 3 of level one')), findsOneWidget);
          expect(dotIn(row('Book 1 of level one')), findsNothing);
          expect(data.seenBooks, isEmpty, reason: 'seen only once the row has been on screen a moment');
          expect(tester.takeException(), isNull);

          // a moment later the book is seen: its dot and the level's dot clear; level 2 and the card stay
          await tester.pump(const Duration(milliseconds: 1700));
          await tester.pumpAndSettle();
          expect(data.seenBooks, ['sg1_level-1_book_3']);
          expect(dotIn(row('Book 3 of level one')), findsNothing);
          expect(dotIn(row('Level 1')), findsNothing, reason: 'all of level 1 is seen');
          expect(dotIn(row('Level 2')), findsOneWidget);
          expect(dotIn(cardOf('Arjun Kumar')), findsWidgets, reason: 'the card still has an unseen book');

          // level 2: its book is tapped -> seen at once, then the card clears
          await tester.tap(find.text('Level 1')); // close level 1 so level 2 is within reach
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Level 2'));
          await tester.tap(find.text('Level 2'));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.ensureVisible(find.text('Level two book'));
          await tester.pump();
          expect(dotIn(row('Level two book')), findsOneWidget);
          await tester.tap(find.text('Level two book'));
          await tester.pump();
          expect(data.seenBooks, ['sg1_level-1_book_3', 'sg1_level-2_book_1']);
          await tester.pumpAndSettle();
          expect(dotIn(row('Level 2')), findsNothing);
          expect(data.unseenBooks, isEmpty);
          expect(find.byType(UnseenDot), findsNothing, reason: 'nothing unseen left on this card');
          await tester.pump(const Duration(seconds: 4));
        });
      }
    }

    testWidgets('a book that is hidden under "Show more" gets the level dot but not a row dot until shown', (tester) async {
      final data = FakeBoardData(users: roster)..unseenBooks = {'sg1': {'sg1_level-1_book_8'}};
      await openBoard(tester, data: data);
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      expect(dotIn(row('Level 1')), findsOneWidget);
      await tester.tap(find.text('Level 1'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1700));
      expect(data.seenBooks, isEmpty, reason: 'book 8 is not on screen yet');
      expect(dotIn(row('Level 1')), findsOneWidget);
      await tester.tap(find.text('Show 3 more'));
      await tester.pumpAndSettle();
      expect(dotIn(row('Book 8 of level one')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pumpAndSettle();
      expect(data.seenBooks, ['sg1_level-1_book_8']);
      expect(find.byType(UnseenDot), findsNothing);
    });

    testWidgets('collapsing the card or the level before the moment is up does not mark the book seen', (tester) async {
      final data = world();
      await openBoard(tester, data: data);
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Level 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Level 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(data.seenBooks, isEmpty);
    });
  });
}
