import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysWorkspace.dart';
import 'package:folk_guide_app/Pages/StudentProfilePage.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/BoardQueries.dart';
import 'package:folk_guide_app/widgets/GuideBoardGhost.dart';
import 'package:folk_guide_app/widgets/GuideReveal.dart';

import 'board_test.dart' show FakeBoardData, user;
import 'support/app_harness.dart';
import 'support/fake_snapshots.dart';
import 'support/guide_test_support.dart';

// Coming back to the FOLK Boys board from a page opened on it: no loading ghost, no new Firestore
// subscriptions, no entry animation again, and the columns and their lists exactly where they were.

Stream<T> counted<T>(Stream<T> source, void Function() hit) => Stream<T>.multi((c) {
      hit();
      source.listen(c.add, onError: c.addError, onDone: c.close);
    });

/// A board with many students in the HOD's column (so it scrolls), counting every subscription.
class CountingBoardData extends FakeBoardData {
  CountingBoardData({Map<String, Map<String, dynamic>>? users}) : super(users: users ?? _many());

  static Map<String, Map<String, dynamic>> _many() => {
        for (var i = 0; i < 40; i++) 'g$i': user('Student ${i.toString().padLeft(2, '0')}', guideId: 'H', team: 'H'),
        for (var i = 0; i < 6; i++) 'u$i': user('Unassigned ${i.toString().padLeft(2, '0')}'),
      };

  int boardsListens = 0;
  int columnsListens = 0;
  int studentsListens = 0;
  int placementsListens = 0;

  int get total => boardsListens + columnsListens + studentsListens + placementsListens;

  final StreamController<QuerySnapshot<Map<String, dynamic>>> studentsC = StreamController.broadcast();
  bool live = false;

  QuerySnapshot<Map<String, dynamic>> snapshot() => FakeSnap([for (final e in users.entries) FakeDoc(e.key, e.value)]);

  @override
  Stream<List<BoardDoc>> boards() => counted(super.boards(), () => boardsListens++);

  @override
  Stream<List<BoardColumn>> columns(String boardId) => counted(super.columns(boardId), () => columnsListens++);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> students() => counted(
      live
          ? (() async* {
              yield snapshot();
              yield* studentsC.stream;
            })()
          : super.students(),
      () => studentsListens++);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> placements(String boardId) => counted(super.placements(boardId), () => placementsListens++);
}

Future<void> openHod(WidgetTester tester, CountingBoardData data, {Size size = const Size(700, 900)}) async {
  await prepareApp(tester);
  BoardData.instance = data;
  await pumpScreen(tester, const FolkBoysWorkspace(selectedGuide: 'H'), reduce: false);
  tester.view.physicalSize = size;
  await letDataArrive(tester, frames: 30);
  await tester.pumpAndSettle();
}

/// The row of columns, and the first column's own list.
Finder horizontalList() => find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal);
Finder firstColumnList() => find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.vertical).first;

int ghostFrames(WidgetTester tester) => find.byType(GuideBoardGhost, skipOffstage: false).evaluate().length;

double offsetOf(WidgetTester tester, Finder list) =>
    tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position.pixels;

/// Pushes a page on top of the board and closes it again, counting the frames that show the ghost.
Future<int> pushAndPop(WidgetTester tester, {bool realProfile = false}) async {
  final nav = Navigator.of(tester.element(find.byType(FolkBoysWorkspace)));
  unawaited(nav.push(MaterialPageRoute<void>(
      builder: (_) => realProfile ? const StudentProfilePage(studentUid: 's1') : const Scaffold(body: Text('A PAGE')))));
  await tester.pumpAndSettle();
  await letDataArrive(tester, frames: 20);
  tester.state<NavigatorState>(find.byType(Navigator).last).pop();
  var ghosts = 0;
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    ghosts += ghostFrames(tester);
  }
  return ghosts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  testWidgets('a page pushed and popped: no ghost frame, no new subscription, no fade again', (tester) async {
    final data = CountingBoardData();
    await openHod(tester, data);
    expect(ghostFrames(tester), 0);
    final before = data.total;
    final ghosts = await pushAndPop(tester);
    expect(ghosts, 0, reason: 'the ghost appeared on return');
    expect(data.total, before, reason: 'the board listened again on return');
    expect(tester.binding.transientCallbackCount, 0, reason: 'something is still animating');
  });

  testWidgets('the real student page pushed and popped behaves the same', (tester) async {
    final data = CountingBoardData();
    await openHod(tester, data);
    final before = data.total;
    final ghosts = await pushAndPop(tester, realProfile: true);
    expect(ghosts, 0);
    expect(data.total, before);
  });

  testWidgets('the horizontal position of the columns and the open column list stay put', (tester) async {
    final data = CountingBoardData();
    await openHod(tester, data, size: const Size(500, 800));
    // the first column's own list, scrolled; then the row of columns, scrolled
    final listKey = firstColumnList().evaluate().first.widget.key!;
    final column = find.byKey(listKey);
    await tester.drag(column, const Offset(0, -300));
    await tester.pumpAndSettle();
    final vOffset = offsetOf(tester, column);
    expect(vOffset, greaterThan(0));
    await tester.drag(horizontalList(), const Offset(-120, 0), warnIfMissed: false);
    await tester.pumpAndSettle();
    final hOffset = offsetOf(tester, horizontalList());
    expect(hOffset, greaterThan(0));

    final ghosts = await pushAndPop(tester);
    expect(ghosts, 0);
    expect(offsetOf(tester, horizontalList()), hOffset, reason: 'the columns moved');
    expect(offsetOf(tester, find.byKey(listKey)), vOffset, reason: 'the column list moved');
  });

  testWidgets('a board built afresh (a new State) starts from the last data: no ghost, no fade, same position', (tester) async {
    final data = CountingBoardData();
    await openHod(tester, data, size: const Size(500, 800));
    await tester.drag(horizontalList(), const Offset(-200, 0));
    await tester.pumpAndSettle();
    final hOffset = offsetOf(tester, horizontalList());
    // the whole board is thrown away and built again, as if something above it had been rebuilt
    await tester.pumpWidget(const SizedBox());
    BoardData.instance = data;
    await pumpScreen(tester, const FolkBoysWorkspace(selectedGuide: 'H'), reduce: false, resetBoardMemory: false);
    tester.view.physicalSize = const Size(500, 800);
    var ghosts = 0;
    for (var i = 0; i < 60; i++) {
      ghosts += ghostFrames(tester);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ghosts, 0, reason: 'a ghost frame on a board that was already loaded once');
    expect(find.byType(GuideReveal), findsOneWidget);
    expect(find.text('Student 00'), findsOneWidget, reason: 'the cards are there from the first frame');
    expect(offsetOf(tester, horizontalList()), hOffset);
    await tester.pumpAndSettle();
  });

  testWidgets('a refresh updates the cards in place, without a ghost', (tester) async {
    final data = CountingBoardData()..live = true;
    await openHod(tester, data);
    expect(find.text('Student 00'), findsOneWidget);
    data.users['late'] = user('Zed Late', guideId: 'H', team: 'H');
    data.studentsC.add(data.snapshot());
    var ghosts = 0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      ghosts += ghostFrames(tester);
    }
    expect(ghosts, 0);
    expect(find.text('Student 00'), findsOneWidget, reason: 'the cards stayed while it refreshed');
  });
}
