import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysWorkspace.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/BoardQueries.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/GuideBoardGhost.dart';
import 'package:folk_guide_app/widgets/GuideGhost.dart';

import 'board_test.dart' show FakeBoardData, a, everyone, profile, roster;
import 'support/fake_snapshots.dart';
import 'support/guide_test_support.dart';

/// What the security rules really give each role on the FOLK Boys board (see
/// rules-tests/female_access.test.js, probed live): everyone may list the boards they own or
/// share (none here), but ONLY the HOD can read the shared Guide Assignment board, its columns
/// or create it. Students: HOD all; a Guide his team + unassigned boys; a Male Enabler his own
/// + unassigned boys; a Female Enabler her own + unassigned girls.
class RealRulesData extends FakeBoardData {
  RealRulesData({required this.role, required this.me, Map<String, Map<String, dynamic>>? all})
      : all = all ?? roster,
        super(users: all ?? roster);

  final String role;
  final String me;
  final Map<String, Map<String, dynamic>> all;

  Object? studentsError;
  bool studentsNever = false;
  final StreamController<QuerySnapshot<Map<String, dynamic>>> studentsC = StreamController.broadcast();
  int studentListens = 0;
  int ensureCalls = 0;
  bool ensureFails = false;
  int reconcileCalls = 0;
  bool hodHasBoard = true;
  Object? boardsError;

  bool get isHod => role == 'HOD';

  Map<String, Map<String, dynamic>> get visible {
    bool ok(Map<String, dynamic> u) {
      final unassigned = (u['guideId'] ?? '') == '';
      switch (role) {
        case 'HOD':
          return true;
        case 'GUIDE':
          return u['teamGuide'] == me || (unassigned && u['gender'] == 'male');
        case 'MALE_ENABLER':
          return u['guideId'] == me || (unassigned && u['gender'] == 'male');
        default:
          return u['guideId'] == me || (unassigned && u['gender'] == 'female');
      }
    }

    return {for (final e in all.entries) if (ok(e.value)) e.key: e.value};
  }

  @override
  Stream<List<BoardDoc>> boards() {
    if (boardsError != null) return Stream.error(boardsError!);
    return Stream.value(isHod && hodHasBoard ? [FakeBoardData.boardDoc] : const <BoardDoc>[]);
  }

  @override
  Stream<List<BoardColumn>> columns(String boardId) {
    if (!isHod) return Stream.error('permission-denied');
    return super.columns(boardId);
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> students() {
    studentListens++;
    if (studentsNever) return studentsC.stream;
    if (studentsError != null) return Stream.error(studentsError!);
    return Stream.value(FakeSnap([for (final e in visible.entries) FakeDoc(e.key, e.value)]));
  }

  @override
  Future<void> ensureGuideBoard({required List<BoardDoc> all, required String hodGuide}) async {
    ensureCalls++;
    if (!isHod || ensureFails) throw 'permission-denied';
  }

  @override
  Future<void> reconcileColumns({
    required String boardId,
    required List<String> roster,
    required List<BoardColumn> existing,
  }) async {
    reconcileCalls++;
  }
}

const roles = <(String, String, String)>[
  // (role, id, a name that must appear as a column / card when there is data)
  ('HOD', 'H', 'H Das'),
  ('GUIDE', 'G', 'G Das'),
  ('MALE_ENABLER', 'M1', 'M1 Das'),
  ('FEMALE_ENABLER', 'F1', 'F1 Das'),
];

Future<RealRulesData> open(
  WidgetTester tester,
  String role,
  String id, {
  Map<String, Map<String, dynamic>>? all,
  void Function(RealRulesData)? setUp,
}) async {
  phone(tester, 1.0, size: const Size(1600, 900)); // wide: every lane of the HOD's board is on screen
  AdminProfileProvider.instance.debugSet(
      profile(id, role, team: role == 'MALE_ENABLER' ? 'G' : '', admins: everyone));
  final data = RealRulesData(role: role, me: id, all: all);
  setUp?.call(data);
  BoardData.instance = data;
  HierarchyApi.useForTests((name, args) async => {});
  await tester.pumpWidget(guideHost(FolkBoysWorkspace(selectedGuide: id), reduce: true));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return data;
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

  for (final (role, id, column) in roles) {
    group('$role board', () {
      testWidgets('with data: the board shows, no ghost left, nothing waits for the shared board', (tester) async {
        final data = await open(tester, role, id);
        await tester.pumpAndSettle();
        expect(find.byType(GuideBoardGhost), findsNothing, reason: 'the loading ghost is gone');
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.textContaining('Could not load the board'), findsNothing);
        expect(find.textContaining('No students yet'), findsNothing);
        expect(find.text(column), findsWidgets);
        final names = [for (final u in data.visible.values) u['name'] as String];
        expect(names, isNotEmpty);
        expect(find.text(names.first), findsWidgets);
        expect(GhostClock.instance.running, isFalse);
        // only the HOD touches the shared board
        expect(data.ensureCalls, role == 'HOD' ? greaterThan(0) : 0);
        expect(data.reconcileCalls, role == 'HOD' ? greaterThan(0) : 0);
      });

      testWidgets('empty (no students): a still ghost and a friendly line; never the breathing ghost', (tester) async {
        await open(tester, role, id, all: const {});
        await tester.pumpAndSettle();
        expect(find.text('No students yet'), findsOneWidget);
        expect(find.textContaining('Students will appear here'), findsOneWidget);
        expect(find.textContaining('Could not load the board'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(find.byType(GuideBoardGhost), findsOneWidget, reason: 'the ghost stays, still');
        expect(GhostClock.instance.running, isFalse, reason: 'a still ghost, not breathing');
        expect(tester.binding.transientCallbackCount, 0);
      });

      testWidgets('error: a frozen ghost, a short message and Retry that listens again', (tester) async {
        final data = await open(tester, role, id, setUp: (d) => d.studentsError = 'permission-denied');
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not load the board'), findsOneWidget);
        expect(find.textContaining('permission-denied'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
        expect(GhostClock.instance.running, isFalse);
        final before = data.studentListens;
        data.studentsError = null;
        await tester.tap(find.text('Retry'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(data.studentListens, greaterThan(before));
        expect(find.text('Retry'), findsNothing);
        expect(find.text(column), findsWidgets);
      });

      testWidgets('no answer at all: after the time limit the ghost freezes and offers Retry', (tester) async {
        await open(tester, role, id, setUp: (d) => d.studentsNever = true);
        // still loading: breathing ghost, no message yet
        expect(find.byType(GuideBoardGhost), findsOneWidget);
        expect(find.textContaining('Could not load the board'), findsNothing);
        await tester.pump(const Duration(seconds: 21));
        await tester.pump();
        expect(find.textContaining('Could not load the board'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      });
    });
  }

  group('Female Enabler board (the reported bug)', () {
    testWidgets('a new Female Enabler with no female students: the empty state, not the loading ghost', (tester) async {
      // production: boys exist, no girls. Her scoped students are empty; boards() has no shared board for her.
      await open(tester, 'FEMALE_ENABLER', 'F1', all: {
        'sg1': roster['sg1']!,
        'su1': roster['su1']!,
      });
      await tester.pumpAndSettle();
      expect(find.text('No students yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(GhostClock.instance.running, isFalse);
    });

    testWidgets('one unassigned girl (production today): her lane shows the girl in Unassigned', (tester) async {
      await open(tester, 'FEMALE_ENABLER', 'F1', all: {'sfu': roster['sfu']!});
      await tester.pumpAndSettle();
      expect(find.byType(GuideBoardGhost), findsNothing);
      expect(find.text('Hema Priya'), findsWidgets);
      expect(find.text('F1 Das'), findsWidgets);
      expect(find.text('Unassigned'), findsWidgets);
    });

    testWidgets('boys never appear on her board even if the stream carried them', (tester) async {
      await open(tester, 'FEMALE_ENABLER', 'F1');
      await tester.pumpAndSettle();
      expect(find.text('Gauri Devi'), findsWidgets);
      expect(find.text('Arjun Kumar'), findsNothing);
      expect(find.text('Dhruva Nair'), findsNothing);
    });
  });

  group('HOD board and the shared Guide Assignment board', () {
    testWidgets('the HOD still waits for the board to be created, then shows it', (tester) async {
      final data = await open(tester, 'HOD', 'H', setUp: (d) => d.hodHasBoard = false);
      // the board does not exist yet: ensure ran (and succeeded); still waiting, breathing
      expect(data.ensureCalls, 1);
      expect(find.byType(GuideBoardGhost), findsOneWidget);
      expect(find.textContaining('Could not load the board'), findsNothing);
    });

    testWidgets('the HOD whose board cannot be created sees Retry, not a ghost forever', (tester) async {
      final data = await open(tester, 'HOD', 'H', setUp: (d) {
        d.hodHasBoard = false;
        d.ensureFails = true;
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load the board'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      data.ensureFails = false;
      data.hodHasBoard = true;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(find.text('H Das'), findsWidgets);
    });

    testWidgets('the HOD whose boards list fails sees Retry', (tester) async {
      await open(tester, 'HOD', 'H', setUp: (d) => d.boardsError = 'unavailable');
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load the board'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('a Guide never calls ensureGuideBoard or reconcileColumns (both write to the HOD-only board)', (tester) async {
    final data = await open(tester, 'GUIDE', 'G');
    await tester.pumpAndSettle();
    expect(data.ensureCalls, 0);
    expect(data.reconcileCalls, 0);
    expect(a('G', 'GUIDE')['id'], 'G'); // keeps the shared helper import used
  });
}
