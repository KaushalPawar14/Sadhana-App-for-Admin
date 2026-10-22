import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/BookProgressData.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

import 'board_test.dart' show openBoard;
import 'support/guide_test_support.dart';

/// Feature 2 — the checkpoint circle in every level's book list marks a book
/// completed, and un-marks it again, through the SAME `booksRead` write path
/// the old in-dialog button used.

/// A student with one finished book, one being read and one never started.
const _books = {
  'sg1': {
    'level-1_book_1': {'endDate': '2026-01-01', 'endedBy': 'guide'},
    'level-1_book_2': {'startDate': '2026-03-01', 'isCurrentBook': true},
  },
};

const _docId = 'sg1_level-1_book_1';

Future<FakeFirebaseFirestore> openWithDb(WidgetTester tester,
    {double scale = 1.0, bool dark = false}) async {
  final db = FakeFirebaseFirestore();
  GuideDb.useForTests(db);
  await openBoard(tester,
      books: _books, scale: scale, dark: dark, size: const Size(420, 900));
  await tester.tap(find.text('Arjun Kumar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Level 1'));
  await tester.pumpAndSettle();
  return db;
}

/// The circle of one book row.
Finder circleOf(String title, IconData icon) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
      matching: find.byIcon(icon),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() => SeenMarkers.debugDisable = false);
  tearDown(() {
    GuideDb.useForTests(null);
    HierarchyApi.useForTests(null);
    BoardData.instance = const FirestoreBoardData();
    AdminProfileProvider.instance.debugSet(null);
  });

  // -------------------------------------------------------------------------
  // the old button is gone
  // -------------------------------------------------------------------------
  testWidgets('the assign dialog no longer offers "Mark as completed"',
      (tester) async {
    await openWithDb(tester);
    // tapping the TITLE of an unfinished book still opens the assign dialog
    await tester.tap(find.text('Book 3 of level one'));
    await tester.pumpAndSettle();
    expect(find.text('Assign this book'), findsOneWidget);
    expect(find.text('Mark as completed'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // marking completed
  // -------------------------------------------------------------------------
  testWidgets('tapping an unfinished circle asks, then writes the completion',
      (tester) async {
    final db = await openWithDb(tester);

    await tester.tap(
        circleOf('Book 3 of level one', Icons.radio_button_unchecked_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Mark this book finished?'), findsOneWidget);

    await tester.tap(find.text('Mark finished'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    final d = (await db.collection('booksRead').doc('sg1_level-1_book_3').get())
        .data()!;
    expect(d['isCurrentBook'], isFalse);
    expect(d['endedBy'], 'guide');
    expect((d['endDate'] as String).isNotEmpty, isTrue);
    // a book that was never started gets a real start date too
    expect(d['startDate'], d['endDate']);
    // and it reads as finished everywhere
    expect(statusForBookEntry(d), BookStatus.finished);
  });

  testWidgets('cancelling the confirmation writes nothing', (tester) async {
    final db = await openWithDb(tester);
    await tester.tap(
        circleOf('Book 3 of level one', Icons.radio_button_unchecked_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final snap =
        await db.collection('booksRead').doc('sg1_level-1_book_3').get();
    expect(snap.exists, isFalse);
  });

  testWidgets('the current book can be completed from its circle too',
      (tester) async {
    final db = await openWithDb(tester);
    await tester.tap(circleOf('Book 2 of level one', Icons.timelapse_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark finished'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    final d = (await db.collection('booksRead').doc('sg1_level-1_book_2').get())
        .data()!;
    // finished is never current
    expect(d['isCurrentBook'], isFalse);
    expect(statusForBookEntry(d), BookStatus.finished);
  });

  // -------------------------------------------------------------------------
  // un-marking
  // -------------------------------------------------------------------------
  testWidgets('tapping a completed circle asks, then reverts safely',
      (tester) async {
    final db = await openWithDb(tester);

    await tester.tap(circleOf('Book 1 of level one', Icons.check_circle_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Mark as not completed?'), findsOneWidget);

    await tester.tap(find.text('Mark not completed'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    final d = (await db.collection('booksRead').doc(_docId).get()).data()!;
    // the end date and who ended it are GONE, not blanked
    expect(d.containsKey('endDate'), isFalse);
    expect(d.containsKey('endedBy'), isFalse);
    // and it is NOT silently promoted to the current book
    expect(d['isCurrentBook'], isFalse);
    expect(statusForBookEntry(d), BookStatus.notStarted);
  });

  testWidgets('cancelling the revert leaves the book completed', (tester) async {
    final db = await openWithDb(tester);
    await tester.tap(circleOf('Book 1 of level one', Icons.check_circle_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final snap = await db.collection('booksRead').doc(_docId).get();
    // nothing was written at all
    expect(snap.exists, isFalse);
  });

  testWidgets('a finished row is still not tappable as a row — only its circle',
      (tester) async {
    await openWithDb(tester);
    await tester.tap(find.text('Book 1 of level one'));
    await tester.pumpAndSettle();
    expect(find.text('Assign this book'), findsNothing);
    expect(find.text('Mark as not completed?'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // the invariant, stated directly
  // -------------------------------------------------------------------------
  test('a reverted book is notStarted, never readingNow', () {
    expect(
        statusForBookEntry({'uid': 'sg1', 'isCurrentBook': false}),
        BookStatus.notStarted);
    // and an empty end date is not a completion
    expect(
        statusForBookEntry({'uid': 'sg1', 'endDate': '', 'isCurrentBook': false}),
        BookStatus.notStarted);
  });

  // -------------------------------------------------------------------------
  // both themes, every text scale
  // -------------------------------------------------------------------------
  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('the circles work at text $scale, ${dark ? 'dark' : 'light'}',
          (tester) async {
        final db = await openWithDb(tester, scale: scale, dark: dark);
        expect(tester.takeException(), isNull);
        await tester.tap(
            circleOf('Book 1 of level one', Icons.check_circle_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Mark as not completed?'), findsOneWidget);
        await tester.tap(find.text('Mark not completed'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 4));
        expect(tester.takeException(), isNull);
        final d = (await db.collection('booksRead').doc(_docId).get()).data()!;
        expect(d.containsKey('endDate'), isFalse);
      });
    }
  }
}
