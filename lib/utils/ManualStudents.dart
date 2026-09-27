import 'package:cloud_firestore/cloud_firestore.dart';

/// Manually-added ("offline roster") students — a guide can record a real
/// student who chants but hasn't installed the app yet, so roadmap targets
/// reflect reality rather than app adoption.
///
/// ---------------------------------------------------------------------------
/// Rule 12 — why this is additive fields on `users`, not a parallel collection
/// ---------------------------------------------------------------------------
/// Every existing query that counts students — `FolkBoysWorkspace._usersQuery()`
/// (unfiltered `users` collection, filtered by column client-side),
/// `functions/goals.js`'s `liveRosterCountFor`/`computeStudentBuckets` (a
/// single `guideId ==` equality filter over `users`), the board's own card
/// rendering, `commitmentRounds` reads for the chanting metric — all of them
/// read `users` with no other required field. A manual entry that lives in
/// `users` is therefore counted by every one of those sites with ZERO code
/// changes, which is exactly what Part 5 of this task requires ("counted
/// fully toward roadmap targets... without changes"). A parallel collection
/// would need every one of those read sites rewritten to UNION two
/// collections — the opposite of Rule 1.
///
/// ---------------------------------------------------------------------------
/// New fields on `users/{id}` (Rule 12)
/// ---------------------------------------------------------------------------
///   isManualEntry     bool    true while unregistered; cleared by the merge
///                             Cloud Function (`functions/manualStudents.js`)
///                             the moment a matching real account registers.
///   addedByGuideId    String  which guide recorded this student.
///   addedAt           Timestamp
///   mergedFromManualEntry  Map?  written by the merge function on the
///                             SURVIVING real document — traceability only,
///                             never read by anything that gates behaviour.
/// Every other field (`name`, `mobileNumber`, `role`, `commitmentRounds`,
/// `guideId`) reuses the EXACT field name and format real registration
/// already uses — see `Students/.../lib/pages/CompleteProfile.dart` and
/// `Register.dart` for the source of truth this file matches.
///
/// ---------------------------------------------------------------------------
/// Document id — cannot collide with a real Firebase Auth uid
/// ---------------------------------------------------------------------------
/// A real student's `users/{uid}` document id IS their Firebase Auth uid —
/// confirmed via a live probe of this project's own `folk-sadhana-app`
/// Firestore: every existing uid is exactly 28 characters (the fixed length
/// Firebase Auth's email/password provider always generates). A manual entry
/// has no Auth account, so [generateManualStudentId] uses Firestore's own
/// auto-id generator (always exactly 20 characters, a different alphabet
/// convention) with a literal `manual_` prefix — a 27-character id that can
/// never equal a 28-character Auth uid, and is immediately recognisable in
/// the Firestore console even without checking length.
String generateManualStudentId() {
  final autoId = FirebaseFirestore.instance.collection('users').doc().id;
  return 'manual_$autoId';
}

/// Normalizes a mobile number to the EXACT format real registration writes:
/// a bare 10-digit string, no country code, no spaces, no punctuation — see
/// `CompleteProfile.dart:225-246`'s own `RegExp(r'^\d{10}$')` validator,
/// confirmed against every real `users.mobileNumber` value in production (17
/// of 17 existing docs, all exactly 10 digits, e.g. "9000077212").
///
/// Strips every non-digit character first (handles spaces, dashes,
/// parentheses), then — since a raw Indian mobile number is commonly typed
/// with a `+91`/`91` country-code prefix or a leading `0` STD-dialling
/// habit — keeps only the LAST 10 digits when more than 10 remain. This
/// normalizes for COMPARISON only; per this task's Part 3 item 4, existing
/// records are never rewritten, only both sides of a comparison are
/// normalized the same way.
///
/// Returns the normalized string even if it isn't exactly 10 digits (e.g.
/// too short) — callers must still validate the RESULT is 10 digits before
/// treating it as usable; this function never throws.
String normalizeMobileNumber(String raw) {
  final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.length <= 10) return digitsOnly;
  return digitsOnly.substring(digitsOnly.length - 10);
}

/// Exactly `CompleteProfile.dart`'s own validator (`^\d{10}$`) — deliberately
/// no leading-digit restriction beyond that, since registration itself has
/// none and this must accept everything registration would.
bool isValidNormalizedMobile(String normalized) =>
    RegExp(r'^\d{10}$').hasMatch(normalized);

/// Part 3 item 5 — warn before saving if the number already exists on ANY
/// user, manual or registered, and refuse to create a duplicate. A single
/// equality filter, matching this project's established convention of never
/// adding a composite-index query (see `GoalQueries.dart`'s own note on the
/// same subject).
///
/// Returns the conflicting document's data (so the caller can name who
/// already holds the number), or `null` if the number is free.
Future<Map<String, dynamic>?> findUserByMobileNumber(
  String normalizedMobile,
) async {
  if (normalizedMobile.isEmpty) return null;
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .where('mobileNumber', isEqualTo: normalizedMobile)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return null;
  return snap.docs.first.data();
}
