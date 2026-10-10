import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'CalendarQueries.dart' show kScopeMandatory;
import 'GoalCompoundQueries.dart' show kGuideTargetsCollection;
import 'SeenMarkers.dart';
import 'StudentScope.dart';

/// Shared, reusable "is this feature unseen for this guide" streams —
/// Follow-up task, 2026-09-10, Part 2. Every one of these is used at
/// (at least) two places: the nav bar's own tab dot, and the intermediate
/// hub-tile dot that sits between the tab and the final content screen —
/// factored here rather than re-querying the same collections separately
/// in `BottomNavBar.dart`/`Competition.dart`/`PriorityHub.dart`/
/// `FolkBoysEntry.dart` so all of them read from exactly one source of
/// truth (Rule 1 — reuse the existing `SeenMarkers`/`UnseenFeatureBadge`
/// mechanism, not a second one).
///
/// ⚠️ Every function here returns an already-hoistable `Stream` — callers
/// must still build it exactly once (`initState()`, or its async
/// completion) and store the result in a field, never call these fresh
/// inside `build()`.
class UnseenAggregates {
  /// Tests only: every aggregate is simply "nothing unseen" (no Firestore).
  @visibleForTesting
  static bool debugDisable = false;

  static Stream<Timestamp?> _maxTimestamp(
      Stream<QuerySnapshot<Map<String, dynamic>>> query, String field) {
    return query.map((snap) {
      Timestamp? max;
      for (final doc in snap.docs) {
        final ts = doc.data()[field];
        if (ts is Timestamp && (max == null || ts.compareTo(max) > 0)) {
          max = ts;
        }
      }
      return max;
    });
  }

  /// ORs any number of already-hoisted boolean streams together.
  static Stream<bool> anyOf(List<Stream<bool>> sources) {
    if (sources.isEmpty) return Stream.value(false);
    late StreamController<bool> controller;
    final latest = List<bool?>.filled(sources.length, null);
    final subs = <StreamSubscription>[];

    void emit() {
      if (latest.any((v) => v == null)) return;
      controller.add(latest.any((v) => v == true));
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        for (var i = 0; i < sources.length; i++) {
          subs.add(sources[i].listen((v) {
            latest[i] = v;
            emit();
          }));
        }
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );
    return controller.stream;
  }

  // Hierarchy: every roster-wide stream below is scoped through
  // [StudentScope] (HOD all; Guide his team + unassigned males; Enablers their
  // own + unassigned of their gender). The `isHod` parameter is kept only so
  // existing callers compile — the scope comes from the loaded admin profile.
  static StudentScope get _scope => StudentScope.current();

  static Stream<bool> associationsUnseen(String guide, bool isHod) {
    if (debugDisable) return Stream.value(false);
    return SeenMarkers.unseenFrom(
      _maxTimestamp(_scope.historyStream('associations'), 'updatedAt'),
      SeenMarkers.seenAt(guide, 'associations'),
    );
  }

  static Stream<bool> expeditionReflectionsUnseen(String guide, bool isHod) {
    if (debugDisable) return Stream.value(false);
    return SeenMarkers.unseenFrom(
      _maxTimestamp(_scope.historyStream('expeditionRegistrations'),
          'reflectionSubmittedAt'),
      SeenMarkers.seenAt(guide, 'expeditionReflections'),
    );
  }

  static Stream<bool> serviceAssignmentsUnseen(String guide, bool isHod) {
    if (debugDisable) return Stream.value(false);
    return SeenMarkers.unseenFrom(
      _maxTimestamp(
          _scope.historyStream('serviceAssignments'), 'statusUpdatedAt'),
      SeenMarkers.seenAt(guide, 'serviceAssignments'),
    );
  }

  static Stream<bool> flaggedMessagesUnseen(String guide, bool isHod) {
    if (debugDisable) return Stream.value(false);
    return SeenMarkers.unseenFrom(
      _maxTimestamp(_scope.historyStream('flaggedChatMessages'), 'createdAt'),
      SeenMarkers.seenAt(guide, 'flaggedMessages'),
    );
  }

  static Stream<bool> calendarEventsUnseen(String guide) {
    if (debugDisable) return Stream.value(false);
    return SeenMarkers.unseenFrom(
      _maxTimestamp(
          FirebaseFirestore.instance
              .collection('calendarEvents')
              .where('scope', isEqualTo: kScopeMandatory)
              .snapshots(),
          'createdAt'),
      SeenMarkers.seenAt(guide, 'calendarEvents'),
    );
  }

  /// Goal proposals — one target's own doc id is its sub-key
  /// (`GoalWeeklyPhasePage`'s own `markSeenSub` call uses the same key),
  /// so "any target unseen" ORs each target's own `pendingProposal.
  /// proposedAt` against ITS OWN cursor, not one flat cursor.
  static Stream<bool> goalProposalsUnseen(String guide) {
    if (debugDisable) return Stream.value(false);
    late StreamController<bool> controller;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
    Map<String, Timestamp>? cursors;
    final subs = <StreamSubscription>[];

    void emit() {
      if (docs == null || cursors == null) return;
      final anyUnseen = docs!.any((doc) {
        final proposal = doc.data()['pendingProposal'];
        if (proposal is! Map) return false;
        final ts = proposal['proposedAt'];
        if (ts is! Timestamp) return false;
        final cursor = cursors![doc.id];
        return cursor == null || ts.compareTo(cursor) > 0;
      });
      controller.add(anyUnseen);
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        subs.add(FirebaseFirestore.instance
            .collection(kGuideTargetsCollection)
            .doc(guide)
            .collection('targets')
            .snapshots()
            .listen((snap) {
          docs = snap.docs;
          emit();
        }));
        subs.add(SeenMarkers.subCursors(guide, 'goalProposals').listen((c) {
          cursors = c;
          emit();
        }));
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// Every student uid this admin's board shows a column for — mirrors
  /// `Home/FolkBoysWorkspace.dart`'s own `_visibleColumns` rule (HOD:
  /// everyone; Guide: his team + unassigned males; Enablers: their own +
  /// unassigned of their gender) without calling into that file at all — a
  /// separate, read-only scoped query against `users`
  /// ([StudentScope.studentsGet]), never touching `_usersQuery`/
  /// `_visibleColumns` themselves. One-time fetch, not a live stream: this
  /// app's own guide-identity resolution is already a one-time read, and a
  /// roster changing (a student re-assigned) is a rare admin action, not
  /// something this dot needs to reflect within the same session.
  static Future<List<String>> myRosterUids(String guide, bool isHod) async {
    final snap = await _scope.studentsGet();
    return snap.docs.map((d) => d.id).toList();
  }

  /// Roster-wide aggregate over `booksRead` — every student's own
  /// `commitmentSetAt` (only when `commitmentSetBy == 'guide'`, matching
  /// `_expandedDetail`'s own per-student check) compared against THAT
  /// student's own cursor. Hierarchy: read through the scoped history query
  /// (`scopeGuide`/`scopeTeam` stamps), which is provable by the rules and
  /// replaces the old chunked `uid whereIn` over the roster.
  static Stream<bool> bookCommitmentsRosterUnseen(
      String guide, bool isHod) {
    if (debugDisable) return Stream.value(false);
    late StreamController<bool> controller;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
    Map<String, Timestamp>? cursors;
    final subs = <StreamSubscription>[];

    void emit() {
      if (docs == null || cursors == null) return;
      final anyUnseen = docs!.any((doc) {
        if (doc.data()['commitmentSetBy'] != 'guide') return false;
        final ts = doc.data()['commitmentSetAt'];
        if (ts is! Timestamp) return false;
        final uid = (doc.data()['uid'] ?? '').toString();
        final cursor = cursors![uid];
        return cursor == null || ts.compareTo(cursor) > 0;
      });
      controller.add(anyUnseen);
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        subs.add(_scope.historyStream('booksRead').listen((snap) {
          docs = snap.docs;
          emit();
        }));
        subs.add(SeenMarkers.subCursors(guide, 'bookCommitments').listen((c) {
          cursors = c;
          emit();
        }));
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );

    return controller.stream;
  }

  /// Roster-wide aggregate over `studentComments/{uid}/messages` — one
  /// subcollection per student, with no `studentUid` field on the message
  /// docs themselves, so (unlike `booksRead`) there is no single batched
  /// query that can cover the whole roster at once; this opens one small
  /// listener per roster student instead. Safe at this app's real scale
  /// (~20 users total today, confirmed against live data) — a roster in
  /// the hundreds would need a different approach, but that is not this
  /// app's shape.
  static Stream<bool> studentCommentsRosterUnseen(
      String guide, bool isHod) async* {
    if (debugDisable) {
      yield false;
      return;
    }
    final uids = await myRosterUids(guide, isHod);
    if (uids.isEmpty) {
      yield false;
      return;
    }

    final perStudent = uids.map((uid) {
      final latest = _maxTimestamp(
          FirebaseFirestore.instance
              .collection('studentComments')
              .doc(uid)
              .collection('messages')
              .snapshots(),
          'createdAt');
      final seen = SeenMarkers.seenAtSub(guide, 'studentComments', uid);
      return SeenMarkers.unseenFrom(latest, seen);
    }).toList();

    yield* anyOf(perStudent);
  }
}
