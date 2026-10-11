import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/BoardQueries.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
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
}
