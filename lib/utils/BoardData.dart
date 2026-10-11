import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'BoardQueries.dart';
import 'BoardQueries.dart' as bq;
import 'BookProgressData.dart';
import 'BookProgressData.dart' as bp;
import 'StudentScope.dart';
import 'UnseenFeatureBadge.dart';
import 'GuideDb.dart';

/// Everything the FOLK Boys board reads or writes, behind one interface. The app
/// always uses [FirestoreBoardData] (a thin pass-through to the functions in
/// `BoardQueries.dart`, `BookProgressData.dart` and `StudentScope.dart`, unchanged);
/// a widget test hands in plain values instead of Firestore. The reassignment
/// itself is NOT here: it goes through `HierarchyApi.assignStudent`, which a test
/// replaces with `HierarchyApi.useForTests`.
abstract class BoardData {
  static BoardData instance = const FirestoreBoardData();

  /// Every board this admin may open (`allBoardsStream`).
  Stream<List<BoardDoc>> boards();

  /// A board's columns, in order.
  Stream<List<BoardColumn>> columns(String boardId);

  /// A custom board's placements (`boards/{id}/placements`).
  Stream<QuerySnapshot<Map<String, dynamic>>> placements(String boardId);

  /// The students the signed-in admin may see (role-scoped).
  Stream<QuerySnapshot<Map<String, dynamic>>> students();

  /// Creates the one shared Guide Assignment board if it does not exist.
  Future<void> ensureGuideBoard({required List<BoardDoc> all, required String hodGuide});

  /// One column per visible admin (never deletes).
  Future<void> reconcileColumns({
    required String boardId,
    required List<String> roster,
    required List<BoardColumn> existing,
  });

  /// Moves a card on a custom board.
  Future<void> movePlacement({
    required String boardId,
    required String studentUid,
    required String columnId,
    required int order,
    required String movedBy,
  });

  /// `books/level-1..3` and the link availability.
  Future<BooksConfig> booksConfig();

  /// A student's chanting commitment (rounds a day), or null.
  Future<int?> chantingCommitment(String uid);

  /// One student's `booksRead` documents (scoped for the rules).
  Stream<QuerySnapshot<Map<String, dynamic>>> booksRead(StudentRef student);

  /// Wraps a card's Comments icon with its per-student unseen dot.
  Widget commentsBadge({required String studentUid, required Widget child});
}

class FirestoreBoardData implements BoardData {
  const FirestoreBoardData();

  @override
  Stream<List<BoardDoc>> boards() => bq.allBoardsStream();

  @override
  Stream<List<BoardColumn>> columns(String boardId) => bq.columnsStream(boardId);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> placements(String boardId) =>
      bq.placementsStream(boardId);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> students() =>
      StudentScope.current().studentsStream();

  @override
  Future<void> ensureGuideBoard({required List<BoardDoc> all, required String hodGuide}) =>
      bq.ensureGuideAssignmentBoard(all: all, hodGuide: hodGuide);

  @override
  Future<void> reconcileColumns({
    required String boardId,
    required List<String> roster,
    required List<BoardColumn> existing,
  }) =>
      bq.reconcileGuideColumns(boardId: boardId, roster: roster, existing: existing);

  @override
  Future<void> movePlacement({
    required String boardId,
    required String studentUid,
    required String columnId,
    required int order,
    required String movedBy,
  }) =>
      bq.movePlacement(
        boardId: boardId,
        studentUid: studentUid,
        columnId: columnId,
        order: order,
        movedBy: movedBy,
      );

  @override
  Future<BooksConfig> booksConfig() => bp.loadBooksConfig();

  @override
  Future<int?> chantingCommitment(String uid) => bp.loadChantingCommitment(uid);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> booksRead(StudentRef student) =>
      StudentScope.current()
          .constrainForStudent(
            GuideDb.instance
                .collection('booksRead')
                .where('uid', isEqualTo: student.uid),
            student,
          )
          .snapshots();

  @override
  Widget commentsBadge({required String studentUid, required Widget child}) =>
      UnseenFeatureBadge(
        featureKey: 'studentComments',
        subKey: studentUid,
        timestampField: 'createdAt',
        dotOffset: const Offset(10, 10),
        latestQuery: (_) => GuideDb.instance
            .collection('studentComments')
            .doc(studentUid)
            .collection('messages')
            .snapshots(),
        child: child,
      );
}
