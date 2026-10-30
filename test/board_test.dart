import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysWorkspace.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/StudentHistory.dart';
import 'package:folk_guide_app/utils/SurrenderData.dart';
import 'package:folk_guide_app/utils/BoardQueries.dart';
import 'package:folk_guide_app/utils/BookProgressData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/StudentScope.dart';
import 'package:folk_guide_app/widgets/GuideBoard.dart';
import 'package:folk_guide_app/widgets/BoardDraggable.dart';

import 'support/fake_snapshots.dart';
import 'support/guide_test_support.dart';

// ---------------------------------------------------------------- fake data
/// The fullest history a card can show: 30 lines of every kind, some long enough to need an ellipsis.
List<HistoryLine> manyHistoryLines([int n = 30]) => [
      for (var i = 0; i < n; i++)
        HistoryLine(
          id: 'h$i',
          kind: const ['advice', 'interaction', 'dealing', 'note', 'sadhana'][i % 5],
          title: i % 4 == 0 ? 'Plan advice: a rather long line about how to approach him this week and what to ask' : 'Line $i',
          detail: 'The full details of line $i.',
          at: DateTime(2026, 10, 29).subtract(Duration(days: i)),
        ),
    ];

class FakeBoardData implements BoardData {
  FakeBoardData({required this.users, this.books = const {}, Map<String, String>? placementList})
      : placementList = placementList ?? {};

  final Map<String, Map<String, dynamic>> users; // uid -> users doc
  final Map<String, Map<String, dynamic>> books; // `${uid}` -> {level_key: entry}
  final Map<String, String> placementList; // student uid -> column id (custom board)
  final List<String> moved = [];

  static final boardDoc = BoardDoc.from('board1', {
    'kind': 'guideAssignment',
    'ownerGuideId': '',
    'title': 'Guide Assignment',
  });
  static final customBoard = BoardDoc.from('custom1', {
    'kind': 'custom',
    'ownerGuideId': 'G',
    'title': 'Ekadashi outreach',
    'sharedWith': <String>[],
  });

  @override
  Stream<List<BoardDoc>> boards() => Stream.value([boardDoc, customBoard]);

  @override
  Stream<List<BoardColumn>> columns(String boardId) => Stream.value(boardId == 'board1'
      ? [
          BoardColumn.from('cu', {'title': 'Unassigned', 'order': 9999, 'colorValue': 0xFF757575, 'kind': 'unassigned'}),
        ]
      : [
          BoardColumn.from('c1', {'title': 'To call', 'order': 0, 'colorValue': 0xFF00695C, 'kind': 'normal'}),
          BoardColumn.from('c2', {'title': 'Called', 'order': 1, 'colorValue': 0xFF1565C0, 'kind': 'normal'}),
        ]);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> placements(String boardId) => Stream.value(
      FakeSnap([for (final e in placementList.entries) FakeDoc(e.key, {'columnId': e.value, 'studentUid': e.key})]));

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> students() =>
      Stream.value(FakeSnap([for (final e in users.entries) FakeDoc(e.key, e.value)]));

  @override
  Future<void> ensureGuideBoard({required List<BoardDoc> all, required String hodGuide}) async {}

  @override
  Future<void> reconcileColumns({
    required String boardId,
    required List<String> roster,
    required List<BoardColumn> existing,
  }) async {}

  @override
  Future<void> movePlacement({
    required String boardId,
    required String studentUid,
    required String columnId,
    required int order,
    required String movedBy,
  }) async {
    moved.add('$studentUid->$columnId');
  }

  @override
  Future<BooksConfig> booksConfig() async => BooksConfig({
        'level-1': [
          for (var i = 1; i <= 8; i++)
            BookConfigEntry(level: 'level-1', key: 'book_$i', title: 'Book $i of level one', hasLink: true),
        ],
        'level-2': [BookConfigEntry(level: 'level-2', key: 'book_1', title: 'Level two book', hasLink: true)],
        'level-3': const [],
      });

  @override
  Future<int?> chantingCommitment(String uid) async => uid == 'sg1' ? 16 : null;

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> booksRead(StudentRef student) => Stream.value(FakeSnap([
        for (final e in (books[student.uid] ?? const {}).entries)
          FakeDoc('${student.uid}_${e.key}', {
            'uid': student.uid,
            'level': e.key.split('_').first,
            'bookKey': e.key.substring(e.key.indexOf('_') + 1),
            ...e.value,
          }),
      ]));

  @override
  Widget commentsBadge({required String studentUid, required Widget child}) => child;

  /// Students whose book commitment is unseen (the cards show a dot for these).
  Set<String> unseenCommitmentUids = {};

  /// Per book: `{studentUid: {bookDocId}}`. [unseenCommitmentUids] (a whole student) is
  /// kept for the older card test: it means that student's first book.
  Map<String, Set<String>> unseenBooks = {};

  final StreamController<Map<String, Set<String>>> unseenC = StreamController.broadcast();
  final List<String> seenBooks = [];

  Map<String, Set<String>> get _allUnseen => {
        for (final u in unseenCommitmentUids) u: {'${u}_level-1_book_1'},
        for (final e in unseenBooks.entries) e.key: {...e.value},
      };

  @override
  Stream<Map<String, Set<String>>> unseenCommitments(String guide) async* {
    yield _allUnseen;
    yield* unseenC.stream;
  }

  /// The history lines of a student (set by a test; empty by default).
  final Map<String, List<HistoryLine>> histories = {};
  final StreamController<void> historyC = StreamController<void>.broadcast();

  @override
  Stream<List<HistoryLine>> history(String studentUid) async* {
    yield histories[studentUid] ?? manyHistoryLines();
    await for (final _ in historyC.stream) {
      yield histories[studentUid] ?? manyHistoryLines();
    }
  }

  /// The Surrender % of a student (set by a test; none by default: "not enough data yet").
  final Map<String, SurrenderInfo?> surrenders = {};
  final StreamController<void> surrenderC = StreamController<void>.broadcast();

  @override
  Stream<SurrenderInfo?> surrender(String studentUid) async* {
    yield surrenders[studentUid];
    await for (final _ in surrenderC.stream) {
      yield surrenders[studentUid];
    }
  }

  @override
  Future<void> markBooksSeen(String guide, String studentUid, Iterable<String> bookDocIds) async {
    seenBooks.addAll(bookDocIds);
    // what the cursor write does to the live stream
    unseenCommitmentUids.remove(studentUid);
    final left = unseenBooks[studentUid]?..removeAll(bookDocIds);
    if (left != null && left.isEmpty) unseenBooks.remove(studentUid);
    unseenC.add(_allUnseen);
  }
}

Map<String, dynamic> user(String name,
        {String role = 'Stay at FOLK', String gender = 'male', String guideId = '', String team = ''}) =>
    {'name': name, 'role': role, 'gender': gender, 'guideId': guideId, 'teamGuide': team};

AdminProfile profile(String id, String role, {String team = '', List<Map<String, dynamic>> admins = const []}) =>
    AdminProfile.fromMap({
      'id': id,
      'displayName': '$id Das',
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': admins,
    });

Map<String, dynamic> a(String id, String role, {String team = ''}) =>
    {'id': id, 'displayName': '$id Das', 'role': role, 'teamGuide': team};

final everyone = [
  a('H', 'HOD'),
  a('G', 'GUIDE'),
  a('M1', 'MALE_ENABLER', team: 'G'),
  a('G2', 'GUIDE'),
  a('F1', 'FEMALE_ENABLER'),
];

final roster = {
  'sg1': user('Arjun Kumar', guideId: 'G', team: 'G'),
  'sg2': user('Bhima Sen', role: 'Stay at Hostel', guideId: 'G', team: 'G'),
  'sm1': user('Chaitanya Das', role: 'Stay at Localite', guideId: 'M1', team: 'G'),
  'su1': user('Dhruva Nair'),
  'sg3': user('Eknath Rao', guideId: 'G2', team: 'G2'),
  'sf1': user('Gauri Devi', gender: 'female', role: 'Stay at Hostel', guideId: 'F1'),
  'sfu': user('Hema Priya', gender: 'female'),
};

Future<FakeBoardData> openBoard(
  WidgetTester tester, {
  AdminProfile? me,
  Map<String, Map<String, dynamic>>? students,
  Map<String, Map<String, dynamic>> books = const {},
  Size size = const Size(360, 800),
  double scale = 1.0,
  bool dark = false,
  bool reduce = true,
  FakeBoardData? data,
  List<List<Object?>>? api,
}) async {
  phone(tester, scale, size: size);
  AdminProfileProvider.instance.debugSet(me ?? profile('G', 'GUIDE', admins: everyone));
  final fake = data ?? FakeBoardData(users: students ?? roster, books: books);
  BoardData.instance = fake;
  HierarchyApi.useForTests((name, args) async {
    api?.add([name, args]);
    return {};
  });
  await tester.pumpWidget(guideHost(const FolkBoysWorkspace(selectedGuide: 'G'), dark: dark, reduce: reduce));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return fake;
}

/// A long-press drag of the card showing [name] onto the column titled [column].
Future<void> dragCard(WidgetTester tester, String name, String column) async {
  final card = find.text(name).first;
  final from = tester.getCenter(card);
  final to = tester.getCenter(find.text(column).first) + const Offset(0, 120);
  final gesture = await tester.startGesture(from);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.moveTo(from + const Offset(10, 10));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The website: a click-and-drag of the card showing [name] onto the column titled [column], with a mouse (or a trackpad), NO waiting before the move.
Future<void> dragCardWithMouse(WidgetTester tester, String name, String column, {PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
  final from = tester.getCenter(find.text(name).first);
  final to = tester.getCenter(find.text(column).first) + const Offset(0, 120);
  final gesture = await tester.startGesture(from, kind: kind);
  await gesture.moveTo(from + const Offset(12, 12));
  await tester.pump();
  await gesture.moveTo(from + (to - from) / 2);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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

  // ----------------------------------------------------- role-scoped columns
  group('columns follow the role', () {
    final wide = const Size(3200, 800); // wide enough that every column is built

    Future<List<String>> titles(WidgetTester tester) async {
      final out = <String>[];
      for (final e in tester.widgetList<GuideBoardColumnHeader>(find.byType(GuideBoardColumnHeader, skipOffstage: false))) {
        out.add(e.title);
      }
      return out;
    }

    testWidgets('HOD: every admin, two gender lanes, Unassigned for both genders', (tester) async {
      await openBoard(tester, me: profile('H', 'HOD', admins: everyone), size: wide);
      expect(await titles(tester), [
        'H Das', 'G Das', 'G2 Das', 'M1 Das', 'Unassigned (males)', // the males lane
        'F1 Das', 'Unassigned (females)', // the females lane
      ]);
      expect(find.text('MALES'), findsOneWidget);
      expect(find.text('FEMALES'), findsOneWidget);
    });

    testWidgets('Guide: his own column, his Male Enablers, Unassigned (males); no lane labels', (tester) async {
      await openBoard(tester, size: wide);
      expect(await titles(tester), ['G Das', 'M1 Das', 'Unassigned']);
      expect(find.text('MALES'), findsNothing);
    });

    testWidgets('Male Enabler: own column and Unassigned', (tester) async {
      await openBoard(tester, me: profile('M1', 'MALE_ENABLER', team: 'G', admins: everyone), size: wide);
      expect(await titles(tester), ['M1 Das', 'Unassigned']);
    });

    testWidgets('Female Enabler: own column and Unassigned (girls)', (tester) async {
      await openBoard(tester, me: profile('F1', 'FEMALE_ENABLER', admins: everyone), size: wide);
      expect(await titles(tester), ['F1 Das', 'Unassigned']);
      expect(find.text('Gauri Devi', skipOffstage: false), findsOneWidget);
      expect(find.text('Hema Priya', skipOffstage: false), findsOneWidget);
      expect(find.text('Arjun Kumar', skipOffstage: false), findsNothing);
    });
  });

  // ---------------------------------------------------------------- the cards
  testWidgets('a column shows its boys with avatar, group pill, count and the split line', (tester) async {
    await openBoard(tester);
    expect(find.text('G Das'), findsOneWidget);
    expect(find.textContaining('2 boys — 1 FOLK / 1 Hostel / 0 Localite'), findsOneWidget);
    expect(find.text('Arjun Kumar'), findsOneWidget);
    expect(find.text('Bhima Sen'), findsOneWidget);
    // the group pills and the legend
    expect(find.text('FOLK'), findsWidgets);
    expect(find.text('Hostel'), findsWidgets);
    expect(find.text('Localite'), findsWidgets, reason: 'the legend');
    expect(tester.takeException(), isNull);
  });

  testWidgets("tapping a card expands it inline: the student's one-line history, newest first, the last 30; a tap opens the details", (tester) async {
    final data = FakeBoardData(users: roster)
      ..histories['sg1'] = [
        HistoryLine(id: 'a', kind: 'advice', title: 'Plan advice: call him about japa', detail: 'Call him. He chants 9 rounds.', at: DateTime(2026, 10, 29)),
        HistoryLine(id: 'b', kind: 'interaction', title: 'Interaction (Call): ask about his Gita reading', detail: 'Themes: japa. Next: ask about his Gita reading.', at: DateTime(2026, 10, 27)),
        HistoryLine(id: 'c', kind: 'sadhana', title: 'Chanting up 4 rounds a day (8 → 12)', detail: 'His weekly average moved.', at: DateTime(2026, 10, 20)),
      ];
    await openBoard(tester, data: data);
    expect(find.byKey(const ValueKey('history-list')), findsNothing);
    await tester.tap(find.text('Arjun Kumar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-list')), findsOneWidget);
    // newest first, one line each
    final titles = tester.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('history-list')), matching: find.byType(Text))).map((t) => t.data).whereType<String>().toList();
    expect(titles.indexOf('Plan advice: call him about japa'), lessThan(titles.indexOf('Interaction (Call): ask about his Gita reading')));
    expect(titles.indexOf('Interaction (Call): ask about his Gita reading'), lessThan(titles.indexOf('Chanting up 4 rounds a day (8 → 12)')));
    expect(find.textContaining('20 Oct'), findsOneWidget, reason: 'one small heading per day (no date on the lines)');
    // the books are no longer in the card
    expect(find.text('Level 1'), findsNothing);
    expect(find.textContaining('Committed to'), findsNothing);
    // a tap: the full details
    await tester.tap(find.text('Interaction (Call): ask about his Gita reading'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-dialog-title')), findsOneWidget);
    expect(find.text('Themes: japa. Next: ask about his Gita reading.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    // collapsing the card again
    await tester.tap(find.text('Arjun Kumar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-list')), findsNothing);
  });

  testWidgets('a student with no history yet: a friendly line; a full history (30 lines) shows 8 and "Show 22 more"', (tester) async {
    final data = FakeBoardData(users: roster)..histories['sg1'] = [];
    await openBoard(tester, data: data);
    await tester.tap(find.text('Arjun Kumar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-empty')), findsOneWidget);
    data.histories['sg1'] = manyHistoryLines();
    data.historyC.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Show 22 more'), findsOneWidget, reason: '30 kept, 8 shown');
    await tester.ensureVisible(find.text('Show 22 more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 22 more'));
    await tester.pumpAndSettle();
    expect(find.text('Show 22 more'), findsNothing);
    expect(find.textContaining('Line 29'), findsOneWidget);
  });

  // ------------------------------------------------------------ drag and drop
  group('drag and drop goes through assignStudent', () {
    testWidgets('a Guide claims an unassigned boy: the confirmation, then the callable with the column', (tester) async {
      final api = <List<Object?>>[];
      await openBoard(tester, api: api, size: const Size(1400, 900));
      await dragCard(tester, 'Dhruva Nair', 'G Das');
      expect(find.text('Claim this boy?'), findsOneWidget);
      expect(find.text('Currently with'), findsOneWidget);
      await tester.tap(find.text('Claim'));
      await tester.pumpAndSettle();
      final calls = api.where((c) => c[0] == 'assignStudent').toList();
      expect(calls, hasLength(1));
      final args = calls.single[1] as Map;
      expect(args['studentId'], 'su1');
      expect(args['toGuideId'], 'G');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final api = <List<Object?>>[];
      await openBoard(tester, api: api, size: const Size(1400, 900));
      await dragCard(tester, 'Dhruva Nair', 'G Das');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.where((c) => c[0] == 'assignStudent'), isEmpty);
    });

    testWidgets('a Guide cannot take another guide student: blocked in the UI with the reason, nothing sent', (tester) async {
      final api = <List<Object?>>[];
      final students = {...roster};
      // Eknath belongs to G2: not visible to G, so use one of M1 (G's team) moving to Unassigned instead
      await openBoard(tester, api: api, students: students, size: const Size(1400, 900));
      // Chaitanya is M1's student: a Guide may not RELEASE a Male Enabler's boy
      await dragCard(tester, 'Chaitanya Das', 'Unassigned');
      expect(find.textContaining("only M1 Das or the HOD can release him"), findsOneWidget);
      expect(find.text('Release this boy?'), findsNothing);
      expect(api.where((c) => c[0] == 'assignStudent'), isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a Guide moves a boy within his team (to his Male Enabler)', (tester) async {
      final api = <List<Object?>>[];
      await openBoard(tester, api: api, size: const Size(1400, 900));
      await dragCard(tester, 'Arjun Kumar', 'M1 Das');
      expect(find.text('Reassign this boy?'), findsOneWidget);
      await tester.tap(find.text('Reassign'));
      await tester.pumpAndSettle();
      final args = api.firstWhere((c) => c[0] == 'assignStudent')[1] as Map;
      expect(args['studentId'], 'sg1');
      expect(args['toGuideId'], 'M1');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a girl dropped on a male column is blocked with the gender reason', (tester) async {
      final api = <List<Object?>>[];
      await openBoard(tester, me: profile('H', 'HOD', admins: everyone), api: api, size: const Size(3200, 900));
      await dragCard(tester, 'Hema Priya', 'G Das');
      expect(find.textContaining('female student'), findsOneWidget);
      expect(api.where((c) => c[0] == 'assignStudent'), isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('HOD reassigns anyone (a girl to a Female Enabler)', (tester) async {
      final api = <List<Object?>>[];
      await openBoard(tester, me: profile('H', 'HOD', admins: everyone), api: api, size: const Size(3200, 900));
      await dragCard(tester, 'Hema Priya', 'F1 Das');
      await tester.tap(find.text('Reassign'));
      await tester.pumpAndSettle();
      final args = api.firstWhere((c) => c[0] == 'assignStudent')[1] as Map;
      expect(args['studentId'], 'sfu');
      expect(args['toGuideId'], 'F1');
      await tester.pump(const Duration(seconds: 4));
    });

    group('the website: click and drag with a mouse or trackpad (no long press)', () {
      testWidgets('a mouse drags a card to another guide at once: the same confirmation and the same server call as the phone', (tester) async {
        final api = <List<Object?>>[];
        await openBoard(tester, api: api, size: const Size(1400, 900));
        await dragCardWithMouse(tester, 'Arjun Kumar', 'M1 Das');
        expect(find.text('Reassign this boy?'), findsOneWidget);
        await tester.tap(find.text('Reassign'));
        await tester.pumpAndSettle();
        final args = api.firstWhere((c) => c[0] == 'assignStudent')[1] as Map;
        expect(args['studentId'], 'sg1');
        expect(args['toGuideId'], 'M1');
        await tester.pump(const Duration(seconds: 4));
      });

      testWidgets('a mouse drags a student to Unassigned (the HOD): released through assignStudent with no guide', (tester) async {
        final api = <List<Object?>>[];
        await openBoard(tester, me: profile('H', 'HOD', admins: everyone), api: api, size: const Size(3200, 900));
        await dragCardWithMouse(tester, 'Arjun Kumar', 'Unassigned (males)');
        expect(find.text('Reassign this boy?'), findsOneWidget);
        expect(find.textContaining('no guide (Unassigned)'), findsWidgets);
        await tester.tap(find.text('Reassign'));
        await tester.pumpAndSettle();
        final args = api.firstWhere((c) => c[0] == 'assignStudent')[1] as Map;
        expect(args['studentId'], 'sg1');
        expect(args['toGuideId'], '');
        await tester.pump(const Duration(seconds: 4));
      });

      test('mouse and trackpad pick a card up at once; a finger, a stylus and anything else press and hold', () {
        expect(BoardDraggable.picksUpAtOnce(PointerDeviceKind.mouse), isTrue);
        expect(BoardDraggable.picksUpAtOnce(PointerDeviceKind.trackpad), isTrue);
        expect(BoardDraggable.picksUpAtOnce(PointerDeviceKind.touch), isFalse);
        expect(BoardDraggable.picksUpAtOnce(PointerDeviceKind.stylus), isFalse);
      });

      testWidgets('cancelling the confirmation after a mouse drag sends nothing', (tester) async {
        final api = <List<Object?>>[];
        await openBoard(tester, api: api, size: const Size(1400, 900));
        await dragCardWithMouse(tester, 'Arjun Kumar', 'M1 Das');
        expect(find.text('Reassign this boy?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(api.where((c) => c[0] == 'assignStudent'), isEmpty);
        await tester.pump(const Duration(seconds: 4));
      });

      testWidgets('the rules are the same: a Guide may not release a Male Enabler boy with the mouse either', (tester) async {
        final api = <List<Object?>>[];
        await openBoard(tester, api: api, size: const Size(1400, 900));
        await dragCardWithMouse(tester, 'Chaitanya Das', 'Unassigned');
        expect(find.textContaining('only M1 Das or the HOD can release him'), findsOneWidget);
        expect(api.where((c) => c[0] == 'assignStudent'), isEmpty);
        await tester.pump(const Duration(seconds: 4));
      });

      testWidgets('a mouse drag shows the lifted card and the delete target while it moves, and a plain click still expands the card', (tester) async {
        await openBoard(tester, size: const Size(1400, 900));
        final from = tester.getCenter(find.text('Arjun Kumar'));
        final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
        await g.moveTo(from + const Offset(20, 20));
        await tester.pump();
        expect(find.textContaining('Drop here to delete permanently'), findsOneWidget);
        await g.up();
        await tester.pumpAndSettle();
        expect(find.textContaining('Drop here to delete permanently'), findsNothing);
        // a click without moving is still the tap that expands the card (the details open with a second tap)
        await tester.tap(find.text('Arjun Kumar').first, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.byType(BoardDraggable<String>), findsWidgets);
      });
    });

    testWidgets('the phone is unchanged: a finger that swipes at once does not pick the card up (it scrolls), only press and hold does', (tester) async {
      final api = <List<Object?>>[];
      await openBoard(tester, api: api, size: const Size(1400, 900));
      final from = tester.getCenter(find.text('Arjun Kumar').first);
      final g = await tester.startGesture(from); // a finger
      await g.moveTo(from + const Offset(0, 120));
      await tester.pump();
      expect(find.textContaining('Drop here to delete permanently'), findsNothing);
      await g.up();
      await tester.pumpAndSettle();
      expect(api.where((c) => c[0] == 'assignStudent'), isEmpty);
    });

    testWidgets('the delete target appears only while a card is dragged', (tester) async {
      await openBoard(tester, size: const Size(1400, 900));
      expect(find.textContaining('Drop here to delete permanently'), findsNothing);
      final from = tester.getCenter(find.text('Arjun Kumar'));
      final g = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await g.moveTo(from + const Offset(20, 20));
      await tester.pump();
      expect(find.textContaining('Drop here to delete permanently'), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
      expect(find.textContaining('Drop here to delete permanently'), findsNothing);
    });
  });

  // ------------------------------------------------------------ custom boards
  testWidgets('a custom board: columns, adding a card by drag goes to placements, not to assignStudent', (tester) async {
    final api = <List<Object?>>[];
    final data = await openBoard(tester, api: api, size: const Size(1400, 900));
    data.placementList['sg1'] = 'c1';
    // open the board switcher and pick the custom board
    await tester.tap(find.byTooltip('Switch board'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ekadashi outreach'));
    await tester.pumpAndSettle();
    expect(find.text('To call'), findsOneWidget);
    expect(find.text('Called'), findsOneWidget);
    expect(find.text('Add a list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ------------------------------------------------------------- the top bar
  testWidgets('the top bar: back, title, switch board, new board', (tester) async {
    await openBoard(tester, size: const Size(1400, 800));
    expect(find.text('FOLK Boys'), findsOneWidget);
    expect(find.byTooltip('Switch board'), findsOneWidget);
    expect(find.byTooltip('New board'), findsOneWidget);
    expect(find.byTooltip('Board options'), findsNothing, reason: 'owner-only, custom boards');
    expect(find.text('New board'), findsOneWidget, reason: 'the dashed tile at the end');
  });

  // ------------------------------------------------------------ snap physics
  testWidgets('the row of columns snaps: a fling comes to rest on a column edge', (tester) async {
    await openBoard(tester, me: profile('H', 'HOD', admins: everyone), size: const Size(360, 800));
    final scroll = find.byType(Scrollable).first;
    final state = tester.state<ScrollableState>(scroll);
    final colW = GuideBoardTokensHelper.colW(360);
    final step = colW + 12;
    expect(state.position.pixels, 0);
    await tester.fling(scroll, const Offset(-250, 0), 900);
    await tester.pumpAndSettle();
    final p = state.position.pixels;
    expect(p, greaterThan(0), reason: 'it moved on');
    // rest = a multiple of (column + gap), allowing for the lane label (42) before the females lane
    // columns rest at 42 + k * step (the males-lane label comes first), the females
    // lane (its own label) after five columns
    final edges = <double>[
      for (var k = 0; k < 5; k++) 42 + k * step,
      for (var k = 5; k < 8; k++) 84 + k * step,
      state.position.maxScrollExtent,
    ];
    final onEdge = edges.any((e) => (e - p).abs() < 1.5);
    expect(onEdge, isTrue, reason: 'resting at $p (step $step)');
  });

  // -------------------------------------------------- layout at every size
  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: collapsed and expanded cards do not overflow', (tester) async {
        await openBoard(tester, scale: scale, dark: dark, books: {
          'sg1': {'level-1_book_1': {'endDate': '2026-01-01'}},
        });
        expect(tester.takeException(), isNull);
        // every card action is a 48 dp target
        for (final tip in ['Calendar', 'Comments', 'Profile']) {
          final r = tester.getRect(find.byTooltip(tip).first);
          expect(r.width, greaterThanOrEqualTo(48), reason: tip);
          expect(r.height, greaterThanOrEqualTo(48), reason: tip);
        }
        await tester.tap(find.text('Arjun Kumar'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('history-more')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // the column on screen stays inside it
        final col = tester.getRect(find.byType(GuideBoardColumnShell).first);
        expect(col.left, greaterThanOrEqualTo(0));
        expect(col.width, lessThanOrEqualTo(330));
        // the next column peeks in (the swipe hint) on a 360 dp phone
        expect(360 - col.right, greaterThan(0), reason: 'space for the peek');
      });
    }
  }

  testWidgets('screenshots: board light and dark, expanded (for looking at)', (tester) async {
    for (final dark in [false, true]) {
      await openBoard(tester, dark: dark, size: const Size(390, 844), books: {
        'sg1': {
          'level-1_book_1': {'endDate': '2026-01-01'},
          'level-1_book_2': {'startDate': '2026-03-01', 'isCurrentBook': true},
        },
      });
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-more')));
      await tester.pumpAndSettle();
      await shot(tester, 'board_${dark ? 'dark' : 'light'}');
      await tester.pumpWidget(const SizedBox());
    }
  });
}

class GuideBoardTokensHelper {
  static double colW(double screen) => (screen - 20 - 12 - 28).clamp(260.0, 330.0);
}
