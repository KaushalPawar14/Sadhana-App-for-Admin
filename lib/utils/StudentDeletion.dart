/// Permanent, full-footprint deletion of a student — drag-to-delete's backing
/// logic (`Home/FolkBoysWorkspace.dart`'s trash target).
///
/// The whole deletion runs on the SERVER now: the Cloud Function `deleteStudent`
/// (functions/studentDeletion.js). A client batch cannot delete across ~20
/// collections once the strict security rules are live, and several of the
/// records (friends, friend groups, requests, voice rooms, board placements,
/// aliases, name-keyed documents) belong to no admin's scope.
///
/// What the function does, in order:
///  1. checks the caller is an admin who can manage this student (HOD: any;
///     Guide: his team + unassigned males; Male Enabler: own + unassigned males;
///     Female Enabler: own + unassigned females) — otherwise it refuses and
///     deletes nothing;
///  2. refuses if another student has the same (normalised) name — several
///     records are stored by name only;
///  3. deletes the student's Firebase Auth account;
///  4. deletes every Firestore record (uid-keyed documents with their
///     sub-collections, name-keyed documents matched by exact / normalised name
///     and `studentKeyAliases`, documents found by a `uid` / `studentUid` field,
///     friend requests in both directions, voice rooms the student started, board
///     placements) with `users/{uid}` last. Every step is independent and
///     idempotent; a failing step is reported, not swallowed, and the rest still
///     run. There is no rollback — a retry is safe.
///
/// Deliberately NOT scrubbed (always reported in
/// [StudentDeletionResult.notFullyScrubbed]): references to this student inside
/// OTHER parties' documents (leaderboard snapshots, a guide's goal task lists,
/// rooms they only joined, other students' friend lists).
///
/// The caller MUST have already shown a confirmation dialog naming the student
/// and stating the deletion is permanent — there is none in here.
library;

import 'package:cloud_functions/cloud_functions.dart';

/// Outcome of deleting the student's Firebase Auth account (always populated).
class AuthDeletionResult {
  /// True only when an Auth account was actually deleted.
  final bool deleted;

  /// True when there was simply no Auth account (a manual entry, or already gone).
  final bool hadNoAuthAccount;

  /// True when the server refused outright.
  final bool refusedByServer;

  /// Populated for a refusal or a soft failure; null on a clean success.
  final String? error;

  const AuthDeletionResult({
    required this.deleted,
    required this.hadNoAuthAccount,
    required this.refusedByServer,
    this.error,
  });

  bool get failed => error != null;
}

/// One deletion step's outcome: how many documents were removed (0 is normal),
/// or the error if the step itself failed.
class DeletionStepResult {
  final String label;
  final int? removedCount;
  final String? error;

  const DeletionStepResult({required this.label, this.removedCount, this.error});

  bool get failed => error != null;
}

class StudentDeletionResult {
  /// True when the whole operation was refused before anything was deleted.
  final bool refused;
  final String? refusalReason;

  final List<DeletionStepResult> steps;

  /// Always populated (even on full success): references this deletion never
  /// attempts to scrub.
  final List<String> notFullyScrubbed;

  final AuthDeletionResult? authResult;

  const StudentDeletionResult({
    this.refused = false,
    this.refusalReason,
    this.steps = const [],
    this.notFullyScrubbed = const [],
    this.authResult,
  });

  bool get anyStepFailed => steps.any((s) => s.failed);
}

const List<String> kDeletionCrossReferenceCaveats = [
  "Leaderboard snapshots (competition-results) may still show this student's name",
  "A guide's compound-goal task lists may still reference this student's uid",
  "Voice-chat rooms this student joined (but did not start) may still list them as a participant",
  "Other students' friend lists / friend groups may still reference this student",
];

typedef DeleteStudentInvoker = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> data);

Future<Map<String, dynamic>> _callDeleteStudent(Map<String, dynamic> data) async {
  final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
      .httpsCallable('deleteStudent', options: HttpsCallableOptions(timeout: const Duration(minutes: 5)))
      .call<dynamic>(data);
  final raw = result.data;
  return raw is Map ? _deep(raw) : <String, dynamic>{};
}

Map<String, dynamic> _deep(Map raw) => {
      for (final e in raw.entries) e.key.toString(): _deepValue(e.value),
    };

dynamic _deepValue(dynamic v) {
  if (v is Map) return _deep(v);
  if (v is List) return v.map(_deepValue).toList();
  return v;
}

/// Turns the server's answer into the result the UI already knows how to show.
StudentDeletionResult parseDeletionResult(Map<String, dynamic> data) {
  final auth = data['auth'];
  final authMap = auth is Map ? auth.cast<String, dynamic>() : null;
  final steps = <DeletionStepResult>[
    for (final s in (data['steps'] as List? ?? const []))
      if (s is Map)
        DeletionStepResult(
          label: (s['label'] ?? '').toString(),
          removedCount: (s['removedCount'] as num?)?.toInt(),
          error: s['error']?.toString(),
        ),
  ];
  return StudentDeletionResult(
    refused: data['refused'] == true,
    refusalReason: data['refusalReason']?.toString(),
    steps: steps,
    notFullyScrubbed: [
      for (final c in (data['notFullyScrubbed'] as List? ?? const [])) c.toString(),
    ],
    authResult: authMap == null
        ? null
        : AuthDeletionResult(
            deleted: authMap['deleted'] == true,
            hadNoAuthAccount: authMap['hadNoAuthAccount'] == true,
            refusedByServer: false,
            error: authMap['error']?.toString(),
          ),
  );
}

/// Permanently deletes the student (see this file's header). [name] is only
/// used for display by the caller; the server reads the student's real name.
Future<StudentDeletionResult> deleteStudentEverywhere({
  required String uid,
  required String name,
  DeleteStudentInvoker? invoke,
}) async {
  try {
    final data = await (invoke ?? _callDeleteStudent)({'studentUid': uid});
    return parseDeletionResult(data);
  } on FirebaseFunctionsException catch (e) {
    return StudentDeletionResult(
      refused: true,
      refusalReason: e.message ?? 'Could not delete this student (${e.code}).',
      authResult: AuthDeletionResult(
        deleted: false,
        hadNoAuthAccount: false,
        refusedByServer: e.code == 'permission-denied' || e.code == 'unauthenticated',
        error: e.message ?? e.code,
      ),
    );
  } catch (e) {
    return StudentDeletionResult(
      refused: true,
      refusalReason: 'Could not reach the server, so nothing was deleted. '
          'Check your connection and try again.',
    );
  }
}
