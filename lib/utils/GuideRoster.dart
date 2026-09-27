/// Guide identity, in one place.
///
/// Two separate concerns live here and must not be confused:
///
///  * **Who the HOD is** — [kHodGuideId]. Exactly one guide, with app-wide
///    visibility across every other guide's students (FOLK_HANDOFF.md
///    Section 2).
///  * **Which guides exist** — the roster. Several guides, and it grows over
///    time.
///
/// REAL identity as of Master Task, 2026-09-14 ("Replace the Guide app's
/// name picker with Google Sign-In, and add admin management"): a guide's
/// identity is no longer self-selected. It is resolved exactly once, right
/// after Google Sign-In, by matching the signed-in email against
/// `adminUsers.email` (see [resolveGuideIdentity]) — LOCKED for that signed-
/// in session, with no in-app way to become a different guide. The picker
/// (`Pages/FolkGuideSelect.dart`) is confirmed dead as of this task — kept
/// per this project's convention (see that file's own header), not deleted,
/// but nothing live constructs it any more.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// The FOLK HOD. Sees all students, all associations, all submissions.
///
/// Compared against the SharedPreferences `selected_guide` value, so it must
/// match that guide's roster name exactly.
const String kHodGuideId = 'SBSD';

/// Live roster: every guide with a real `adminUsers` document, sorted.
///
/// `adminUsers` is reused as the source of truth (Rule 12) — its document ids
/// are guide names, and `Home/FolkBoysEntry.dart` already writes one there for
/// whichever guide is selected. A guide added through [addGuide] gets their
/// document up front so they appear here *before* they have ever opened the
/// app; the later `merge: true` FCM-token write then adds their `fcmToken`
/// without disturbing it.
///
/// ⚠️ **No hardcoded seed fallback.** A `kSeedGuideIds`-style constant used to
/// union three names in here regardless of whether they had a real
/// `adminUsers` document — removed entirely (board-column-scoping task):
/// every caller of this roster (the "Add Admin" duplicate check, HOD guide-
/// multiselects, and the mandatory board's own columns — NOT the picker any
/// more, confirmed dead as of Master Task 2026-09-14) now sees exactly the
/// real, current roster, nothing more. Real data checked before this removal:
/// `adminUsers` already held real documents for all three former seed names
/// (`AMHD`, `FOLK`, `SBSD`) — the fallback had already stopped changing
/// anything in practice, so this is a correctness cleanup, not a behaviour
/// change for today's data. If Firestore is ever briefly unreachable, or on
/// the very first frame before this stream emits, callers now see an empty
/// list rather than a fabricated one — each caller below chooses to fail
/// closed for that case, not to reintroduce a hardcoded name.
Stream<List<String>> guideRosterStream() {
  return FirebaseFirestore.instance
      .collection('adminUsers')
      .snapshots()
      .map((snap) {
    final names = <String>{};
    for (final doc in snap.docs) {
      if (doc.id.trim().isNotEmpty) names.add(doc.id.trim());
    }
    final sorted = names.toList()..sort();
    return sorted;
  });
}

/// Why a guide name was rejected, or null when it is acceptable.
///
/// Case-insensitive against [existing], because `adminUsers` is keyed by this
/// name and "amhd" and "AMHD" would otherwise become two separate guides
/// owning different students.
String? validateNewGuideName(String raw, List<String> existing) {
  final name = raw.trim();

  if (name.isEmpty) return "Enter a name";
  if (name.length > 24) return "Keep it under 24 characters";

  // Firestore document ids cannot contain these.
  if (name.contains('/') || name.contains('.')) {
    return "No slashes or dots";
  }

  final lower = name.toLowerCase();
  if (existing.any((e) => e.toLowerCase() == lower)) {
    return "$name already exists";
  }

  return null;
}

/// Creates the guide's `adminUsers` document so they appear in the roster —
/// with their email, since Master Task 2026-09-14: without one, this guide
/// could never sign in at all.
///
/// `merge: true` so this can never clobber an `fcmToken` that somehow
/// already exists for that name. Rule 3: `fcmToken` is never touched,
/// renamed, or removed by this function.
///
/// Does NOT touch `guideEmails` — that mirror is maintained entirely
/// server-side now, by a Cloud Function trigger on `adminUsers` writes
/// (`functions/guideEmailMirror.js`), deliberately: it needs to stay
/// correct even for an email set directly in the Firebase console (exactly
/// how the first admins' emails are seeded — see Part 5's deployment
/// ordering), which a client-side batch write here could never react to.
Future<void> addGuide(
  String name, {
  required String email,
  required String addedBy,
}) async {
  await FirebaseFirestore.instance
      .collection('adminUsers')
      .doc(name.trim())
      .set({
    'email': normalizeAdminEmail(email),
    'addedAt': FieldValue.serverTimestamp(),
    'addedBy': addedBy,
  }, SetOptions(merge: true));
}

/// Changes an EXISTING admin's email — the one field this task's "Add
/// Admin" screen lets anyone fix after the fact (name/doc id stays
/// permanent, same rule as every other identity in this app). See
/// [addGuide]'s own comment: the `guideEmails` mirror updates itself via
/// the same Cloud Function trigger, not from here.
Future<void> updateAdminEmail(String name, {required String newEmail}) async {
  await FirebaseFirestore.instance.collection('adminUsers').doc(name).set(
    {'email': normalizeAdminEmail(newEmail)},
    SetOptions(merge: true),
  );
}

/// Lowercased, trimmed — `adminUsers.email` is queried by exact match
/// (`resolveGuideIdentity`, `isAdminEmailTaken`, and the
/// `deleteStudentAuthAccount` Cloud Function all compare this way), so every
/// write must normalize the same way or a real match could silently fail.
String normalizeAdminEmail(String email) => email.trim().toLowerCase();

/// Resolves a signed-in Google email to the `adminUsers` document id that
/// owns it — the LOCKED identity for that session (Master Task, 2026-09-14).
/// `null` if no admin holds this email at all. Mirrors exactly what
/// `functions/studentDeletion.js`'s `resolveCallerGuideIdentity` does
/// server-side; kept in sync by convention (documented in both places),
/// since Dart and JS can't literally share this one query.
///
/// `firestore.rules`' `isLikelyGuide()` gates `adminUsers` reads on the
/// caller ALREADY being a resolved admin — so this exact query, run for a
/// genuinely unregistered person, comes back as a Firestore
/// `permission-denied` exception, not an empty result. Caught here and
/// treated identically to "no match": either way, this person is not a
/// registered admin, and the caller (`GuideSignInPage`) shows the same
/// "not registered" message regardless of which of the two this was.
Future<String?> resolveGuideIdentity(String? email) async {
  if (email == null || email.trim().isEmpty) return null;
  final normalized = normalizeAdminEmail(email);

  final QuerySnapshot<Map<String, dynamic>> matches;
  try {
    matches = await FirebaseFirestore.instance
        .collection('adminUsers')
        .where('email', isEqualTo: normalized)
        .limit(1)
        .get();
  } catch (_) {
    return null;
  }

  if (matches.docs.isEmpty) return null;
  return matches.docs.first.id;
}

/// Whether [email] already belongs to a DIFFERENT admin than [excludingName]
/// — used by the "Add Admin" / "Edit email" forms so two admins can never
/// share one email (which `resolveGuideIdentity` could otherwise resolve
/// ambiguously — `.limit(1)` would just pick whichever Firestore returns
/// first).
Future<bool> isAdminEmailTaken(String email, {String? excludingName}) async {
  final normalized = normalizeAdminEmail(email);
  final matches = await FirebaseFirestore.instance
      .collection('adminUsers')
      .where('email', isEqualTo: normalized)
      .get();

  return matches.docs.any((d) => d.id != excludingName);
}

/// Same shape as the Student app's own registration email check
/// (`EmailSignIn.dart`) — kept as a local copy per this project's
/// established per-file convention for small validators like this one
/// (`CalendarQueries.dart`'s `kCalendarFunctionsRegion` is the precedent for
/// "own local copy, not a cross-file import," for the same reason).
final RegExp kAdminEmailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// The eligibility rule custom boards already use — HOD sees/manages every
/// student, a regular guide only their own. Extracted here (Service Bank
/// task) so a second consumer never has to write a second copy of this
/// rule: mirrors `Home/FolkBoysWorkspace.dart`'s own private
/// `_customBoardEligible` EXACTLY (same two lines), which is left
/// untouched and NOT repointed to call this — that file's custom-board
/// path is on this task's own "do not touch" list. This function is for
/// every consumer from here on; `_customBoardEligible` stays as the
/// board's own internal copy of the identical rule.
bool guideCanManageStudent({
  required String studentGuideId,
  required String viewerGuide,
  required bool viewerIsHod,
}) {
  if (viewerIsHod) return true;
  return studentGuideId == viewerGuide;
}
