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

import 'package:cloud_firestore/cloud_firestore.dart';

/// Trims leading/trailing whitespace and collapses internal runs of
/// whitespace to a single space. This is the value written to
/// `users.name` everywhere in this app now — see this file's own header
/// for why the stored value and the comparison key must never diverge.
String normalizeStudentName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Part 2 item 1 — case-insensitive, whitespace-normalized duplicate
/// check. "Ayush", "Ayush ", " ayush" and "Ayush  Kumar" vs "Ayush Kumar"
/// are all detected as the relevant kind of match.
///
/// Reads the whole `users` collection rather than a single `where`
/// equality query — Firestore has no case-insensitive query operator, so
/// an exact-match query on the stored (real-cased) name cannot catch a
/// same-name-different-case collision. This project already does
/// full-collection `users` reads elsewhere for admin operations (e.g.
/// `Pages/BoysDetails.dart`'s guide-picker); the roster is small and
/// account creation is a rare event, so this stays cheap without needing a
/// second normalized-key field purely to make an indexed query possible
/// (Rule 12 — a schema addition was considered and rejected here as
/// unnecessary for the collection's real size).
///
/// Part 2 item 4 / Part 1 item 4 — a manual entry (`isManualEntry ==
/// true`, `Pages/BoysDetails.dart`) is excluded: the real student behind
/// that name must still be able to register under their own name;
/// `functions/manualStudents.js`'s merge reconciles the two by mobile
/// number immediately afterward. This exclusion is unaffected by
/// normalization — it was never about how names compare, only about which
/// documents count as "taken" at all.
Future<bool> isStudentNameTaken(String candidateRaw) async {
  final candidate = normalizeStudentName(candidateRaw).toLowerCase();
  if (candidate.isEmpty) return false;

  final snap = await FirebaseFirestore.instance.collection('users').get();
  for (final doc in snap.docs) {
    final data = doc.data();
    if (data['isManualEntry'] == true) continue;
    final existing =
        normalizeStudentName((data['name'] ?? '').toString()).toLowerCase();
    if (existing == candidate) return true;
  }
  return false;
}

/// Part 2 item 3 — a message a real person understands, not a technical
/// error.
const String kNameTakenMessage =
    "That name is already registered by another student. Please add your "
    "surname or a middle name so we can tell you apart.";
