import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/Calendar.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenDot.dart';
import 'package:folk_guide_app/widgets/StudentBooksPanel.dart';
import 'package:provider/provider.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';

import 'board_test.dart' show FakeBoardData, everyone, profile, roster;
import 'support/guide_test_support.dart';

/// The student page has three tabs: Calendar | Scores | Books. Badges are gone from the Guide app (students keep theirs in their own
/// app); the book list that used to be the board card's drop-down lives in Books. The suggestions section is gone from the student's
/// profile (the advice is in the plans).

Future<FakeBoardData> open(WidgetTester tester, {double scale = 1.0, bool dark = false, FakeBoardData? data}) async {
  final db = FakeFirebaseFirestore();
  GuideDb.useForTests(db);
  await db.collection('users').doc('sg1').set({'name': 'Arjun Kumar', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at FOLK'});
  phone(tester, scale);
  AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE', admins: everyone));
  final fake = data ??
      FakeBoardData(users: roster, books: const {
        'sg1': {
          'level-1_book_1': {'endDate': '2026-01-01'},
          'level-1_book_2': {'startDate': '2026-03-01', 'isCurrentBook': true, 'commitmentDate': '2026-12-01', 'commitmentSetBy': 'guide'},
        },
      });
  BoardData.instance = fake;
  await tester.pumpWidget(ChangeNotifierProvider<ColorProvider>(
    create: (_) => ColorProvider(),
    child: guideHost(CalendarPage(username: 'Arjun Kumar', role: 'Stay at FOLK', studentUid: 'sg1'), dark: dark),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  return fake;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() => SeenMarkers.debugDisable = false);
  tearDown(() {
    GuideDb.useForTests(null);
    BoardData.instance = const FirestoreBoardData();
    AdminProfileProvider.instance.debugSet(null);
  });

  testWidgets('the tabs are Calendar, Scores, Books — in that order — and there is no Badges tab', (tester) async {
    await open(tester);
    final labels = ['Calendar', 'Scores', 'Books'];
    for (final l in labels) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.text('Badges'), findsNothing);
    expect(find.byIcon(Icons.military_tech_outlined), findsNothing);
    final xs = [for (final l in labels) tester.getTopLeft(find.text(l)).dx];
    expect(xs, [...xs]..sort(), reason: 'left to right: Calendar, Scores, Books');
    expect(find.text('Weekly Wins'), findsNothing);
    expect(find.text('No badges won yet 🏅'), findsNothing);
  });

  testWidgets('Books shows the three levels with where the student is; opening one lists the books, finished first', (tester) async {
    await open(tester);
    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    expect(find.byType(StudentBooksPanel), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('Level 3'), findsOneWidget);
    expect(find.text('1 of 8 finished · 1 reading'), findsOneWidget);
    await tester.tap(find.text('Level 1'));
    await tester.pumpAndSettle();
    expect(find.text('Book 1 of level one'), findsOneWidget);
    expect(find.text('Due 2026-12-01 (set by guide)'), findsOneWidget);
    expect(find.text('Show 3 more'), findsOneWidget);
    await tester.tap(find.text('Show 3 more'));
    await tester.pumpAndSettle();
    expect(find.text('Book 8 of level one'), findsOneWidget);
  });

  testWidgets('Calendar is still the first tab, and switching back and forth works', (tester) async {
    await open(tester);
    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scores'));
    await tester.pumpAndSettle();
    expect(find.byType(StudentBooksPanel), findsNothing);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(StudentBooksPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a book commitment the guide has not seen: dots on the level and the book, marked seen a moment after the tab is open', (tester) async {
    final data = FakeBoardData(users: roster)..unseenBooks = {'sg1': {'sg1_level-1_book_3'}};
    await open(tester, data: data);
    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    Finder dotIn(Finder f) => find.descendant(of: f, matching: find.byType(UnseenDot));
    expect(dotIn(find.byKey(const ValueKey('books-level-level-1'))), findsOneWidget, reason: 'on the level (even closed)');
    expect(data.seenBooks, isEmpty);
    await tester.tap(find.text('Level 1'));
    await tester.pumpAndSettle();
    expect(dotIn(find.byKey(const ValueKey('book-row-level-1_book_3'))), findsOneWidget, reason: 'on the exact book');
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(data.seenBooks, ['sg1_level-1_book_3'], reason: 'seen once the tab has been open a moment');
    expect(find.byType(UnseenDot), findsNothing, reason: 'all clear: the trail ends here');
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: tabs and the Books tab fit', (tester) async {
        await open(tester, scale: scale, dark: dark);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Books'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Level 1'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final circle = tester.getRect(find.byKey(const ValueKey('book-circle-level-1_book_2')));
        expect(circle.height, greaterThanOrEqualTo(30));
      });
    }
  }

  group('the student profile has no AI suggestions section any more', () {
    test('the page no longer builds a "Suggested Next Action" section or the "New suggestions ready" label', () {
      final src = File('lib/Pages/StudentProfilePage.dart').readAsStringSync();
      expect(src.contains('Suggested Next Action'), isFalse);
      expect(src.contains('HolisticSuggestion'), isFalse);
      expect(src.contains('New suggestions ready'), isFalse);
      expect(File('lib/Pages/HolisticSuggestion.dart').existsSync(), isFalse);
      expect(File('lib/utils/SuggestionsReady.dart').existsSync(), isFalse);
    });

    test('the board no longer has the "New suggestions ready" dot trail (no stream, no aggregate, no card dot)', () {
      for (final f in ['lib/Home/FolkBoysWorkspace.dart', 'lib/Home/FolkBoysEntry.dart', 'lib/utils/BottomNavBar.dart', 'lib/utils/BoardData.dart', 'lib/utils/UnseenAggregates.dart']) {
        final src = File(f).readAsStringSync();
        expect(src.contains('suggestionsReady'), isFalse, reason: f);
        expect(src.contains('unseenSuggestions'), isFalse, reason: f);
        expect(src.contains('SuggestionsReady'), isFalse, reason: f);
      }
    });

    test('the assistant has no "generate / delete suggestions" executors; the Plan dot replaces the trail', () {
      final writes = File('lib/agent/AgentWrites.dart').readAsStringSync();
      expect(writes.contains('suggestionsGenerate'), isFalse);
      expect(writes.contains('suggestionsDelete'), isFalse);
      expect(File('lib/agent/AgentOverlay.dart').readAsStringSync().contains('planUnseen'), isTrue);
    });
  });
}
