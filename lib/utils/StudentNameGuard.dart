// Unique, normalized, immutable student names — the ONE shared
// implementation every registration write path in this app uses (Rule 1),
// so there is exactly one place that decides what "the same name" means.
//
// Copied verbatim from the Student app's own `utils/StudentNameGuard.dart`
// (same treatment as `BookDeadlines.dart`/`ServiceBankContent.dart`) — keep
// the two in sync if either ever changes.
//
// ---------------------------------------------------------------------------
// Why `sadhana-reports`/`hostel-sadhana`/`scorecard`/`competition`/
// `notification` being name-keyed makes this load-bearing
// ---------------------------------------------------------------------------
// The product owner's own decision (this task's context): keep those five
// collections keyed by student NAME rather than migrate to uid-keying, and
// instead guarantee names are unique and stable. If two students ever end
// up with the same normalized name, every one of those five collections
// silently collides — one student's sadhana reports, scores and
// notifications become indistinguishable from (or overwrite) the other's.
// This file is the entire guarantee that failure mode never happens.
//
// ---------------------------------------------------------------------------
// Storage vs. comparison — Part 2 item 2
// ---------------------------------------------------------------------------
// normalizeStudentName() is applied to what gets STORED in `users.name` —
// trimmed, internal whitespace collapsed to one space — so the stored
// name and the key later used to look up `sadhana-reports/{name}` etc. can
// never diverge (both are always this same normalized string). Original
// capitalization is preserved in storage — a real name's casing is not
// noise to discard, and every existing name-keyed collection already
// expects real casing. Casing is folded ONLY inside isStudentNameTaken()'s
// own comparison, never applied to what's written.

import 'package:cloud_functions/cloud_functions.dart';

/// Trims leading/trailing whitespace and collapses internal runs of
/// whitespace to a single space. This is the value written to
/// `users.name` everywhere in this app now — see this file's own header
/// for why the stored value and the comparison key must never diverge.
String normalizeStudentName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Part 2 item 1 — case-insensitive, whitespace-normalized duplicate
/// check. "Ayush", "Ayush ", " ayush" and "Ayush  Kumar" vs "Ayush Kumar"
/// are all detected as the relevant kind of match.
///
/// Hierarchy conversion — a non-HOD admin can no longer read the whole
/// `users` collection, so the check now runs on the server: the callable
/// `checkNameAvailable` (region asia-south1) compares the name
/// case-insensitively and whitespace-normalized over every `users` document
/// and answers `{available: bool}`. The manual-entry rule below is the
/// server's to apply now.
///
/// A failed call is rethrown (never treated as "free"): the caller's existing
/// error path then reports "could not verify" instead of risking a duplicate.
///
/// Part 2 item 4 / Part 1 item 4 — a manual entry (`isManualEntry ==
/// true`, `Pages/BoysDetails.dart`) is excluded: the real student behind
/// that name must still be able to register under their own name;
/// `functions/manualStudents.js`'s merge reconciles the two by mobile
/// number immediately afterward. This exclusion is unaffected by
/// normalization — it was never about how names compare, only about which
/// documents count as "taken" at all.
Future<bool> isStudentNameTaken(String candidateRaw) async {
  final candidate = normalizeStudentName(candidateRaw);
  if (candidate.isEmpty) return false;

  final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
      .httpsCallable('checkNameAvailable')
      .call<dynamic>({'name': candidate});
  final data = result.data;
  final available = data is Map ? data['available'] : null;
  if (available is! bool) {
    throw StateError('Could not verify the name.');
  }
  return !available;
}

/// Part 2 item 3 — a message a real person understands, not a technical
/// error.
const String kNameTakenMessage =
    "That name is already registered by another student. Please add your "
    "surname or a middle name so we can tell you apart.";
