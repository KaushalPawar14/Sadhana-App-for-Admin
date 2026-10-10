/// Permanent, full-footprint deletion of a student — drag-to-delete's
/// backing logic (`Home/FolkBoysWorkspace.dart`'s trash target).
///
/// ---------------------------------------------------------------------------
/// Real-data discovery this task, before any code below was written
/// ---------------------------------------------------------------------------
/// The old `Home/Dashboard.dart._deleteSelectedUsers` deleted exactly six
/// documents: `users/{uid}`, `scorecard/{name}`, `sadhana-reports/{name}`,
/// `notification/{name}`, `competition/{name}`, `hostel-sadhana/{name}`. Five
/// of six are keyed by student **name**, not uid, and it left every
/// subcollection (`dates`, `studentComments/messages`, etc.) orphaned. A
/// live-data probe this task (`users` collection, 17 real docs) confirmed
/// every name is currently unique — no collision exists TODAY — but the risk
/// is structural, not hypothetical: nothing prevents two students from
/// sharing a name, and five collections have no other way to address a
/// specific student's row.
///
/// A full grep-and-probe sweep across both apps and `functions/` this task
/// found substantially more per-student data than those six documents. What
/// follows is deleted; what is deliberately NOT deleted is documented at the
/// bottom of this file, with the reason.
///
/// ---------------------------------------------------------------------------
/// DELETED — direct documents, keyed by uid, deleted with their subcollections
/// ---------------------------------------------------------------------------
///   users/{uid}                     + dailyReading/**, questions/**
///   holisticSuggestions/{uid}
///   studentServices/{uid}
///   studentComments/{uid}           + messages/**
///   studentChats/{uid}              + messages/**
///   friends/{uid}                   + list/**
///   friendGroups/{uid}              + groups/**
///
/// ---------------------------------------------------------------------------
/// DELETED — direct documents, keyed by student NAME (the name-collision risk)
/// ---------------------------------------------------------------------------
///   scorecard/{name}
///   sadhana-reports/{name}          + dates/**
///   hostel-sadhana/{name}           + dates/**
///   notification/{name}
///   competition/{name}
///
/// ⚠️ **[checkNameCollision] runs before any of the above, and refuses the
/// ENTIRE deletion — not just the name-keyed part — if it finds another
/// student with the exact same name.** A partial delete (uid-keyed rows gone,
/// name-keyed rows left behind because they might belong to someone else)
/// would leave the student in a confusing half-deleted state and is not
/// obviously safer than refusing outright, so the whole operation is refused
/// and the caller is told exactly why.
///
/// ---------------------------------------------------------------------------
/// DELETED — queried by a `uid`/`studentUid` field, every match deleted
/// ---------------------------------------------------------------------------
///   booksRead              where uid ==
///   bookmarks               where uid ==
///   rduaProgress             where uid ==
///   interactionLogs         where studentUid ==
///   litAssessments          where studentUid ==
///   flaggedChatMessages     where studentUid ==
///   associations             where studentUid ==
///   expeditionRegistrations where studentUid ==
///   chantingChallengeContributions where studentUid ==
///   studentKeyAliases       where studentUid ==
///   friendRequests          where fromUid == , then where toUid == (two
///                            queries — Firestore cannot OR two different
///                            fields in one query without risking the same
///                            `FAILED_PRECONDITION` class of error this
///                            codebase has hit before with compound queries)
///   voiceRooms              where createdBy == (rooms this student
///                            started — see the scope note below for rooms
///                            they only joined)
///
/// ---------------------------------------------------------------------------
/// boards/*/placements/{uid} — every board, iterated
/// ---------------------------------------------------------------------------
/// There is no reverse index from a student to the boards they have a
/// placement on, so every board in `boards` is listed and its
/// `placements/{uid}` doc is deleted if present. Deleting `users/{uid}` alone
/// already removes the student from the board visually — `BoardQueries.dart`
/// derives Board C's column membership from `users.guideId`, never from a
/// placement — so this step is pure hygiene against an orphaned document, not
/// something the board's own rendering depends on.
///
/// ---------------------------------------------------------------------------
/// ⚠️ DELIBERATELY NOT DELETED — cross-document array references
/// ---------------------------------------------------------------------------
/// A second class of "per-student data" found this task is not a document
/// this student owns, but a REFERENCE to them embedded inside some OTHER
/// party's document:
///  * `competition-results/{weekly|monthly}/weeks|months/{id}` — a
///    `topUsers` array embedding this student's NAME inside a leaderboard
///    snapshot owned by the whole competition, not this student.
///  * `guideTargets/{guideId}/targets/{id}/phases/{n}.tasks[].studentUids` —
///    this student's uid inside a GUIDE's own compound-goal task array.
///  * `notificationThrottle/{name}__{type}` — a composite key mixing guide
///    and student names for throttle bookkeeping, not a record this student
///    owns.
///  * `voiceRooms/{roomId}.participantUids` — this student's uid inside a
///    room started by a DIFFERENT student.
///  * `friends/{otherUid}/list/{thisUid}` and
///    `friendGroups/{otherUid}/groups/{id}.memberUids` — the REVERSE side of
///    a friendship/group membership, sitting under another student's own
///    subcollection.
///
/// None of these are touched. Scrubbing them would mean scanning and
/// mutating an unbounded number of OTHER guides'/students' documents from a
/// single client-triggered delete, with no batching guarantee across that
/// unknown set and no way to verify correctness without a real device/data
/// test this task explicitly must not perform (Rule 7). This is a real,
/// reported limitation, not a silent gap — see [StudentDeletionResult]'s
/// `notFullyScrubbed` list, always populated with this same explanation.
///
/// ---------------------------------------------------------------------------
/// Firebase Authentication — now deleted too (Master Task, 2026-09-14)
/// ---------------------------------------------------------------------------
/// No client SDK can delete another user's Auth account — only the Admin SDK
/// can, so this calls the `deleteStudentAuthAccount` Cloud Function
/// (`functions/studentDeletion.js`) FIRST, before any of the Firestore
/// deletion below. That order is deliberate: the function re-verifies the
/// CALLER's own (server-derived, since Master Task 2026-09-14's identity
/// locking — no client-supplied `guideId`/`isHod` is trusted any more)
/// guideId against this student's OWN `users/{uid}.guideId`, which only
/// still exists at this point — see that file's own header for its full
/// permission model and failure handling.
///
/// A `permission-denied`/`unauthenticated` result from that function is a
/// hard refusal: this whole deletion aborts and NONE of the Firestore steps
/// below run. Any other failure (network, an Admin SDK hiccup, or the
/// student simply having no Auth account at all — a manual entry, or an
/// already-deleted account) is recorded in [StudentDeletionResult.authResult]
/// and the Firestore deletion proceeds regardless — a surviving Auth account
/// with no Firestore data behind it is harmless (Master Task, 2026-09-14,
/// Part 3: signing in again with it is indistinguishable from a fresh
/// registration).
///
/// ---------------------------------------------------------------------------
/// Role-based hierarchy (Guide app conversion)
/// ---------------------------------------------------------------------------
/// Only a student the signed-in admin can manage may be deleted
/// ([StudentScope.canManage] on the student's own `users` doc; a HOD may delete
/// anyone). The Firestore steps below only run what that admin's rules allow:
/// every query that lists documents to delete carries the scope filter
/// ([StudentScope.constrainForStudent]) so the security rules can prove it, and
/// `users/{uid}` is deleted LAST because the uid-path collections' rules read
/// it (`canManageStudent`). Collections with no scope stamp (friends,
/// friendGroups, friendRequests, studentKeyAliases, voiceRooms, boards) are
/// attempted as before; where the rules refuse them (HOD-only) the step is
/// reported as failed in [StudentDeletionResult.steps], not swallowed.
///
/// ---------------------------------------------------------------------------
/// "Batched/transactional" — what this actually does, and why not a real
/// Firestore transaction
/// ---------------------------------------------------------------------------
/// A single Firestore `Transaction` cannot span this many collections and
/// queries (transactions require every read before any write, and are meant
/// for a small, tightly-coupled set of documents, not a multi-collection
/// purge across an unbounded number of query results). Each STEP below
/// batches its own document deletes in chunks of 400 (Firestore's own limit
/// is 500 writes per batch) via [_batchDelete]. Each step also runs inside
/// its own try/catch, so one failing step does not abort the rest — the
/// result records exactly which steps succeeded, which found nothing, and
/// which failed, so a partial failure is REPORTED, not swallowed. There is no
/// automatic rollback: if this genuinely fails partway, the student is left
/// partially deleted, and the caller is told precisely which collections
/// still have data so a retry (safe — every step here is idempotent, deleting
/// something already gone is a no-op) or manual cleanup is possible.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'StudentScope.dart';

/// Own local copy — matches `GoalCompoundQueries.dart`'s own
/// `kFunctionsRegion` constant, not shared, per this project's established
/// per-file convention for small constants like this one
/// (`CalendarQueries.dart`'s `kCalendarFunctionsRegion` is the precedent).
const String kDeletionFunctionsRegion = 'asia-south1';

/// Outcome of trying to delete the student's Firebase Auth account via the
/// `deleteStudentAuthAccount` Cloud Function. Always populated — never
/// silently skipped — so the guide sees a real result for this half of the
/// deletion too (Master Task, 2026-09-14, Part 2.4).
class AuthDeletionResult {
  /// True only when the Cloud Function actually deleted an Auth account.
  final bool deleted;

  /// True when there was simply no Auth account to delete — a manual entry
  /// (no account ever existed) or one already removed. Not an error.
  final bool hadNoAuthAccount;

  /// True when the server refused outright (not a registered admin at all,
  /// or this student isn't assigned to the caller's own, server-resolved
  /// guideId) — the caller of [deleteStudentEverywhere] treats this as a
  /// hard abort.
  final bool refusedByServer;

  /// Populated for both a hard refusal and a soft (non-blocking) failure;
  /// `null` on a clean success (deleted, or correctly had nothing to delete).
  final String? error;

  const AuthDeletionResult({
    required this.deleted,
    required this.hadNoAuthAccount,
    required this.refusedByServer,
    this.error,
  });

  bool get failed => error != null;
}

/// Calls `deleteStudentAuthAccount` (`functions/studentDeletion.js`) — see
/// that function's own header for its permission model. Exposed separately
/// from [deleteStudentEverywhere] so callers that need only this half
/// (there are none today, but this mirrors how every other step in this
/// file is independently testable) can use it directly.
///
/// Only `studentUid` is sent — as of Master Task 2026-09-14, the function
/// derives the caller's OWN guideId/HOD status itself (from their locked,
/// email-resolved identity), so there is nothing left for the client to
/// claim about who is calling.
Future<AuthDeletionResult> deleteStudentAuthAccount({required String uid}) async {
  try {
    final result = await FirebaseFunctions.instanceFor(
            region: kDeletionFunctionsRegion)
        .httpsCallable('deleteStudentAuthAccount')
        .call<Map<String, dynamic>>({'studentUid': uid});

    final data = result.data;
    final deleted = data['deleted'] == true;
    final reason = data['reason'] as String?;

    return AuthDeletionResult(
      deleted: deleted,
      hadNoAuthAccount: !deleted && reason == 'no-auth-account',
      refusedByServer: false,
    );
  } on FirebaseFunctionsException catch (e) {
    final hardRefusal = e.code == 'permission-denied' || e.code == 'unauthenticated';
    return AuthDeletionResult(
      deleted: false,
      hadNoAuthAccount: false,
      refusedByServer: hardRefusal,
      error: e.message ?? e.code,
    );
  } catch (e) {
    return AuthDeletionResult(
      deleted: false,
      hadNoAuthAccount: false,
      refusedByServer: false,
      error: e.toString(),
    );
  }
}

/// One deletion step's outcome — how many documents were actually removed
/// (0 is a valid, normal result: the collection simply had nothing for this
/// student), or the error if the step itself failed.
class DeletionStepResult {
  final String label;
  final int? removedCount;
  final String? error;

  const DeletionStepResult({required this.label, this.removedCount, this.error});

  bool get failed => error != null;
}

class StudentDeletionResult {
  /// True when the whole operation was refused before anything was deleted
  /// (name collision) — [steps] is empty in that case.
  final bool refused;
  final String? refusalReason;

  final List<DeletionStepResult> steps;

  /// Always populated (even on full success) with the cross-document
  /// references this deletion never attempts to scrub — see this file's own
  /// header for why.
  final List<String> notFullyScrubbed;

  /// `null` only when [refused] is true and the refusal happened before the
  /// Auth-deletion step ran at all (the name-collision check) — otherwise
  /// always populated (Master Task, 2026-09-14, Part 2.4), including when
  /// the Auth call itself is what caused [refused].
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

/// Checks whether any OTHER student (different uid) currently has the exact
/// same `name`. Five collections below can only be addressed by name, so a
/// collision means this deletion cannot safely proceed at all.
///
/// A non-HOD can only list the students they may see (scoped queries), so the
/// check covers those; names are unique by registration (`checkNameAvailable`).
Future<String?> checkStudentNameCollision({
  required String uid,
  required String name,
}) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;

  final base = FirebaseFirestore.instance
      .collection('users')
      .where('name', isEqualTo: trimmed);
  final snap =
      await StudentScope.mergedGet(StudentScope.current().studentQueries(base));

  final others = snap.docs.where((d) => d.id != uid).toList();
  if (others.isEmpty) return null;

  return 'Another student ("${others.first.id}") has the exact same name '
      '"$trimmed". Several of this student\'s records are stored by name '
      'only, and deleting them could destroy the other student\'s data '
      'instead. Rename one of the two students first, then try again.';
}

Future<void> _batchDelete(List<DocumentReference> refs) async {
  for (var i = 0; i < refs.length; i += 400) {
    final chunk = refs.skip(i).take(400).toList();
    final batch = FirebaseFirestore.instance.batch();
    for (final ref in chunk) {
      batch.delete(ref);
    }
    await batch.commit();
  }
}

/// [scope] narrows the listing so the rules can prove it (name-keyed history
/// sub-collections such as `dates`); null = a uid-path sub-collection.
Future<int> _deleteSubcollection(
  DocumentReference<Map<String, dynamic>> parent,
  String name, {
  Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>>)? scope,
}) async {
  Query<Map<String, dynamic>> q = parent.collection(name);
  if (scope != null) q = scope(q);
  final snap = await q.get();
  if (snap.docs.isEmpty) return 0;
  await _batchDelete(snap.docs.map((d) => d.reference).toList());
  return snap.docs.length;
}

/// Deletes [ref] itself plus every doc in each named subcollection. Returns
/// the total document count removed (subcollection docs + the doc itself, if
/// it existed).
Future<int> _deleteDocDeep(
  DocumentReference<Map<String, dynamic>> ref, {
  List<String> subcollections = const [],
  Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>>)? scope,
}) async {
  var count = 0;
  for (final sub in subcollections) {
    count += await _deleteSubcollection(ref, sub, scope: scope);
  }
  // A scoped rule may refuse to read a document that does not exist; the
  // delete below is what matters, so an unreadable doc is counted as present.
  var existed = true;
  try {
    existed = (await ref.get()).exists;
  } catch (_) {}
  await ref.delete();
  if (existed) count += 1;
  return count;
}

Future<int> _deleteWhereEquals(
  String collection,
  String field,
  String value, {
  StudentRef? scopeTo,
}) async {
  if (value.isEmpty) return 0;
  Query<Map<String, dynamic>> q = FirebaseFirestore.instance
      .collection(collection)
      .where(field, isEqualTo: value);
  if (scopeTo != null) {
    q = StudentScope.current().constrainForStudent(q, scopeTo);
  }
  final snap = await q.get();
  if (snap.docs.isEmpty) return 0;
  await _batchDelete(snap.docs.map((d) => d.reference).toList());
  return snap.docs.length;
}

Future<DeletionStepResult> _step(
    String label, Future<int> Function() action) async {
  try {
    final n = await action();
    return DeletionStepResult(label: label, removedCount: n);
  } catch (e) {
    return DeletionStepResult(label: label, error: e.toString());
  }
}

/// Permanently deletes every piece of this student's own data this task's
/// discovery pass found — see this file's header for the exact list and for
/// what is deliberately excluded — AND their Firebase Auth account (Master
/// Task, 2026-09-14, Part 2), via [deleteStudentAuthAccount], called first.
///
/// No `guideId`/`isHod` parameters here any more (Master Task, 2026-09-14):
/// `deleteStudentAuthAccount` derives the caller's own identity itself, from
/// their locked, email-resolved `adminUsers` record — there is nothing left
/// for this function or its caller to supply about who is calling.
/// `FolkBoysWorkspace._handleDeleteDrop`'s own client-side permission gate
/// (`_guide`/`_isHod`) still runs first, as a fast, friendly pre-check, but
/// the real enforcement is now entirely server-side.
///
/// The caller MUST have already shown a confirmation dialog naming the
/// student and stating the deletion is permanent — there is no confirmation
/// inside this function.
Future<StudentDeletionResult> deleteStudentEverywhere({
  required String uid,
  required String name,
}) async {
  final trimmedName = name.trim();
  final firestore = FirebaseFirestore.instance;
  final scope = StudentScope.current();

  // The student must be one this admin can manage (a HOD: any). Read the
  // student's own doc by id — that is also what scopes every query below.
  final userDoc = await firestore.collection('users').doc(uid).get();
  if (!userDoc.exists) {
    return const StudentDeletionResult(
      refused: true,
      refusalReason: 'This student record no longer exists, so it cannot be '
          'deleted from here. Ask the HOD to clear any leftovers.',
    );
  }
  final ref = StudentRef.fromDoc(userDoc);
  if (!scope.canManage(ref)) {
    return const StudentDeletionResult(
      refused: true,
      refusalReason: 'Not authorised to delete this student.',
    );
  }

  final collision = await checkStudentNameCollision(uid: uid, name: name);
  if (collision != null) {
    return StudentDeletionResult(refused: true, refusalReason: collision);
  }

  // Auth deletion FIRST — see this file's header for why the order matters
  // (the server-side guideId re-check needs `users/{uid}` to still exist).
  final authResult = await deleteStudentAuthAccount(uid: uid);
  if (authResult.refusedByServer) {
    return StudentDeletionResult(
      refused: true,
      refusalReason: authResult.error ??
          'Not authorised to delete this student.',
      authResult: authResult,
    );
  }

  final steps = <DeletionStepResult>[];
  Query<Map<String, dynamic>> scoped(Query<Map<String, dynamic>> q) =>
      scope.constrainForStudent(q, ref);

  // Name-keyed documents — safe now that the collision check above passed.
  if (trimmedName.isNotEmpty) {
    steps.add(await _step('scorecard',
        () => _deleteDocDeep(firestore.collection('scorecard').doc(trimmedName))));
    steps.add(await _step(
        'sadhana-reports (+ dates)',
        () => _deleteDocDeep(
            firestore.collection('sadhana-reports').doc(trimmedName),
            subcollections: ['dates'],
            scope: scoped)));
    steps.add(await _step(
        'hostel-sadhana (+ dates)',
        () => _deleteDocDeep(
            firestore.collection('hostel-sadhana').doc(trimmedName),
            subcollections: ['dates'],
            scope: scoped)));
    // The student's own token doc, deleted by name only — never read.
    steps.add(await _step('notification', () async {
      await firestore.collection('notification').doc(trimmedName).delete();
      return 0;
    }));
    steps.add(await _step('competition',
        () => _deleteDocDeep(firestore.collection('competition').doc(trimmedName))));
  }

  // uid-keyed direct documents (the uid is in the path; `users/{uid}` itself
  // goes last — these collections' rules read it).
  steps.add(await _step('holisticSuggestions',
      () => _deleteDocDeep(firestore.collection('holisticSuggestions').doc(uid))));
  steps.add(await _step('studentServices',
      () => _deleteDocDeep(firestore.collection('studentServices').doc(uid))));
  steps.add(await _step(
      'studentComments (+ messages)',
      () => _deleteDocDeep(firestore.collection('studentComments').doc(uid),
          subcollections: ['messages'])));
  steps.add(await _step(
      'studentChats (+ messages)',
      () => _deleteDocDeep(firestore.collection('studentChats').doc(uid),
          subcollections: ['messages'])));
  steps.add(await _step(
      'friends (+ list)',
      () => _deleteDocDeep(firestore.collection('friends').doc(uid),
          subcollections: ['list'])));
  steps.add(await _step(
      'friendGroups (+ groups)',
      () => _deleteDocDeep(firestore.collection('friendGroups').doc(uid),
          subcollections: ['groups'])));

  // Queried by a uid / studentUid field — scope-stamped collections carry the
  // single-student filter so the rules can prove the listing.
  steps.add(await _step('booksRead',
      () => _deleteWhereEquals('booksRead', 'uid', uid, scopeTo: ref)));
  steps.add(await _step('bookmarks',
      () => _deleteWhereEquals('bookmarks', 'uid', uid, scopeTo: ref)));
  steps.add(await _step('rduaProgress',
      () => _deleteWhereEquals('rduaProgress', 'uid', uid, scopeTo: ref)));
  steps.add(await _step('interactionLogs',
      () => _deleteWhereEquals('interactionLogs', 'studentUid', uid, scopeTo: ref)));
  steps.add(await _step('litAssessments',
      () => _deleteWhereEquals('litAssessments', 'studentUid', uid, scopeTo: ref)));
  steps.add(await _step('flaggedChatMessages',
      () => _deleteWhereEquals('flaggedChatMessages', 'studentUid', uid, scopeTo: ref)));
  steps.add(await _step('associations',
      () => _deleteWhereEquals('associations', 'studentUid', uid, scopeTo: ref)));
  steps.add(await _step(
      'expeditionRegistrations',
      () => _deleteWhereEquals('expeditionRegistrations', 'studentUid', uid,
          scopeTo: ref)));
  steps.add(await _step(
      'chantingChallengeContributions',
      () => _deleteWhereEquals(
          'chantingChallengeContributions', 'studentUid', uid,
          scopeTo: ref)));
  steps.add(await _step('studentKeyAliases',
      () => _deleteWhereEquals('studentKeyAliases', 'studentUid', uid)));
  steps.add(await _step('friendRequests', () async {
    final a = await _deleteWhereEquals('friendRequests', 'fromUid', uid);
    final b = await _deleteWhereEquals('friendRequests', 'toUid', uid);
    return a + b;
  }));
  steps.add(await _step(
      'voiceRooms (started by this student)',
      () => _deleteWhereEquals('voiceRooms', 'createdBy', uid)));

  // Board placements — every board, iterated (no reverse index exists).
  steps.add(await _step('board placements', () async {
    final boards = await firestore.collection('boards').get();
    var total = 0;
    for (final board in boards.docs) {
      final placement =
          board.reference.collection('placements').doc(uid);
      final existed = (await placement.get()).exists;
      if (existed) {
        await placement.delete();
        total += 1;
      }
    }
    return total;
  }));

  // The student's own document, last.
  steps.add(await _step(
      'users (+ dailyReading, questions)',
      () => _deleteDocDeep(firestore.collection('users').doc(uid),
          subcollections: ['dailyReading', 'questions'])));

  return StudentDeletionResult(
    steps: steps,
    notFullyScrubbed: kDeletionCrossReferenceCaveats,
    authResult: authResult,
  );
}
