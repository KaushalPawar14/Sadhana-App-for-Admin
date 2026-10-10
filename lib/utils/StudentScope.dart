import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'AdminProfile.dart';

/// Which students an admin may see, expressed as Firestore queries the
/// security rules (Master 3) can PROVE — never an unfiltered list for a
/// non-HOD.
///
///   HOD              everything (one unfiltered query)
///   Guide G          `teamGuide == G`  (his own + his Male Enablers')
///                    + unassigned males (`guideId == ""` and `gender == male`)
///   Male Enabler E   `guideId == E` + unassigned males
///   Female Enabler F `guideId == F` + unassigned females
///
/// Student documents use `guideId` / `teamGuide` / `gender`. History and
/// name-keyed documents (associations, interaction logs, reports...) carry the
/// server-stamped `scopeGuide` / `scopeTeam` / `scopeGender` instead (the old
/// `guideId` on them is the historic stamp and is NOT used for visibility).
///
/// Only equality filters are used, so no new composite index is needed; sort in
/// memory.
class StudentScope {
  StudentScope(this.profile);

  /// The scope of the signed-in admin.
  factory StudentScope.current() =>
      StudentScope(AdminProfileProvider.require());

  final AdminProfile profile;

  static final _db = FirebaseFirestore.instance;

  // -------------------------------------------------------------------------
  // students (`users`)
  // -------------------------------------------------------------------------

  /// The queries whose union is every student this admin may see.
  List<Query<Map<String, dynamic>>> studentQueries(
      [Query<Map<String, dynamic>>? base]) {
    final users = base ?? _db.collection('users');
    if (profile.isHod) return [users];
    final g = profile.gender;
    return [
      if (profile.isGuide)
        users.where('teamGuide', isEqualTo: profile.id)
      else
        users.where('guideId', isEqualTo: profile.id),
      users.where('guideId', isEqualTo: '').where('gender', isEqualTo: g),
    ];
  }

  /// Live list of the students this admin may see (merged, de-duplicated).
  Stream<QuerySnapshot<Map<String, dynamic>>> studentsStream() =>
      mergedStream(studentQueries());

  Future<QuerySnapshot<Map<String, dynamic>>> studentsGet() =>
      mergedGet(studentQueries());

  /// Only this admin's OWN students (`guideId == me`) — for "My students".
  Query<Map<String, dynamic>> ownStudentsQuery() =>
      _db.collection('users').where('guideId', isEqualTo: profile.id);

  /// The unassigned students this admin may see (their gender, or both for a HOD).
  Query<Map<String, dynamic>> unassignedStudentsQuery() {
    final q = _db.collection('users').where('guideId', isEqualTo: '');
    return profile.isHod ? q : q.where('gender', isEqualTo: profile.gender);
  }

  // -------------------------------------------------------------------------
  // history / name-keyed documents (scope fields)
  // -------------------------------------------------------------------------

  /// The queries whose union is every document of [collection] about a student
  /// this admin may see. [extraEquals] are extra equality filters (e.g.
  /// `{'status': 'pending'}`), applied to each query.
  List<Query<Map<String, dynamic>>> historyQueries(
    String collection, {
    Map<String, Object?> extraEquals = const {},
  }) {
    Query<Map<String, dynamic>> q = _db.collection(collection);
    extraEquals.forEach((k, v) => q = q.where(k, isEqualTo: v));
    return historyQueriesOn(q);
  }

  /// Same, on an existing query (a sub-collection, or one with filters already).
  List<Query<Map<String, dynamic>>> historyQueriesOn(
      Query<Map<String, dynamic>> q) {
    if (profile.isHod) return [q];
    return [
      if (profile.isGuide)
        q.where('scopeTeam', isEqualTo: profile.id)
      else
        q.where('scopeGuide', isEqualTo: profile.id),
      q
          .where('scopeGuide', isEqualTo: '')
          .where('scopeGender', isEqualTo: profile.gender),
    ];
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> historyStream(
    String collection, {
    Map<String, Object?> extraEquals = const {},
  }) =>
      mergedStream(historyQueries(collection, extraEquals: extraEquals));

  Future<QuerySnapshot<Map<String, dynamic>>> historyGet(
    String collection, {
    Map<String, Object?> extraEquals = const {},
  }) =>
      mergedGet(historyQueries(collection, extraEquals: extraEquals));

  /// Adds the filter that lets the rules prove this admin may read the documents
  /// of ONE student: used on queries like `booksRead where uid == X` or a
  /// student's `sadhana-reports/{name}/dates`. [s] is that student's current
  /// assignment (from their `users` document).
  ///
  /// For a student this admin may not see, the returned query is still one the
  /// rules accept but matches nothing.
  Query<Map<String, dynamic>> constrainForStudent(
      Query<Map<String, dynamic>> q, StudentRef s) {
    if (profile.isHod) return q;
    final unassignedOfMine = s.guideId.isEmpty && s.gender == profile.gender;
    if (profile.isGuide) {
      if (s.teamGuide == profile.id) return q.where('scopeTeam', isEqualTo: profile.id);
    } else if (s.guideId == profile.id) {
      return q.where('scopeGuide', isEqualTo: profile.id);
    }
    if (unassignedOfMine) {
      return q
          .where('scopeGuide', isEqualTo: '')
          .where('scopeGender', isEqualTo: profile.gender);
    }
    // Not a student this admin can see: still a query the rules accept (it asks
    // for this admin's own scope), and it simply returns nothing for this
    // student - never a permission error on screen.
    return profile.isGuide
        ? q.where('scopeTeam', isEqualTo: profile.id)
        : q.where('scopeGuide', isEqualTo: profile.id);
  }

  /// Whether this admin may see/manage the student (UI-side mirror of the
  /// server rule; the server enforces it again).
  bool canManage(StudentRef s) {
    if (profile.isHod) return true;
    final unassigned = s.guideId.isEmpty;
    if (profile.isGuide) {
      return s.gender == 'male' &&
          (s.guideId == profile.id || s.teamGuide == profile.id || unassigned);
    }
    if (s.gender != profile.gender) return false;
    return s.guideId == profile.id || unassigned;
  }

  // -------------------------------------------------------------------------
  // merging
  // -------------------------------------------------------------------------

  static Stream<QuerySnapshot<Map<String, dynamic>>> mergedStream(
      List<Query<Map<String, dynamic>>> queries) {
    if (queries.length == 1) return queries.first.snapshots();
    late StreamController<QuerySnapshot<Map<String, dynamic>>> controller;
    final subs = <StreamSubscription<dynamic>>[];
    final latest =
        List<QuerySnapshot<Map<String, dynamic>>?>.filled(queries.length, null);

    void emit() {
      if (latest.any((s) => s == null)) return;
      controller.add(MergedSnapshot.of(latest.cast()));
    }

    controller = StreamController<QuerySnapshot<Map<String, dynamic>>>(
      onListen: () {
        for (var i = 0; i < queries.length; i++) {
          subs.add(queries[i].snapshots().listen(
            (s) {
              latest[i] = s;
              emit();
            },
            onError: controller.addError,
          ));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> mergedGet(
      List<Query<Map<String, dynamic>>> queries) async {
    if (queries.length == 1) return queries.first.get();
    final snaps = await Future.wait(queries.map((q) => q.get()));
    return MergedSnapshot.of(snaps);
  }
}

/// A student's current assignment, as stored on their `users` document.
class StudentRef {
  const StudentRef({
    required this.uid,
    required this.guideId,
    required this.teamGuide,
    required this.gender,
  });

  final String uid;
  final String guideId;
  final String teamGuide;
  final String gender;

  factory StudentRef.fromUser(String uid, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    String s(Object? v) => (v ?? '').toString().trim();
    final g = s(d['gender']).toLowerCase();
    return StudentRef(
      uid: uid,
      guideId: s(d['guideId']),
      teamGuide: s(d['teamGuide']),
      gender: g == 'female' ? 'female' : (g == 'male' ? 'male' : ''),
    );
  }

  factory StudentRef.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      StudentRef.fromUser(doc.id, doc.data());
}

/// The merge of several query snapshots, de-duplicated by document id. It
/// IS-A `QuerySnapshot`, so every existing `StreamBuilder<QuerySnapshot<...>>`
/// and `snap.docs` call site keeps working unchanged. `docChanges` is empty.
class MergedSnapshot implements QuerySnapshot<Map<String, dynamic>> {
  MergedSnapshot._(this._docs, this._metadata);

  factory MergedSnapshot.of(List<QuerySnapshot<Map<String, dynamic>>> snaps) {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final s in snaps) {
      for (final d in s.docs) {
        byId.putIfAbsent(d.reference.path, () => d);
      }
    }
    return MergedSnapshot._(byId.values.toList(), snaps.first.metadata);
  }

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;
  final SnapshotMetadata _metadata;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;

  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges => const [];

  @override
  SnapshotMetadata get metadata => _metadata;

  @override
  int get size => _docs.length;
}
