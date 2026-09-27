/// Resolution layer bridging the **name-keyed** sadhana collections to the
/// **uid-keyed** `users` collection (Stage 3 item 4, built 2026-08-23).
///
/// ---------------------------------------------------------------------------
/// ⚠️ NOTHING HERE RENAMES OR RE-KEYS ANY EXISTING DOCUMENT (Rule 3 / Rule 4)
/// ---------------------------------------------------------------------------
/// `sadhana-reports/{studentName}` and `hostel-sadhana/{studentName}` keep the
/// exact document ids they have today, whitespace and all. This is a
/// **comparison and lookup layer only**. [normalizeStudentKey] is never used to
/// build a document id, and this file performs **zero writes**.
///
/// ---------------------------------------------------------------------------
/// ⚠️⚠️ WHY THIS GENERATES CANDIDATE KEYS INSTEAD OF LISTING REAL ONES
/// ---------------------------------------------------------------------------
/// Measured on the real database: **all 29 sadhana-report parent documents are
/// phantom.** `sadhana-reports/{name}` and `hostel-sadhana/{name}` hold no
/// fields at all — they exist only as parents of a `dates` subcollection:
///
///     sadhana-reports   listDocuments() [admin] = 25   .get() [client] = 0
///     hostel-sadhana    listDocuments() [admin] =  4   .get() [client] = 0
///
/// `listDocuments()` is an **admin-SDK-only** method. The Flutter client's
/// `.get()` returns only documents that really exist, so from inside the app
/// **the parent list is invisible — it reads as an empty collection.**
///
/// Therefore a client cannot enumerate report keys at all. It can only
/// *construct* the keys a given student's history might live under and read
/// those paths directly; a path that does not exist simply yields an empty
/// snapshot, which is harmless.
///
/// The consequence worth stating plainly: **the authoritative seam audit — which
/// keys resolve to nobody — cannot be computed in the app.** It requires
/// `listDocuments()`, so it belongs to the Cloud Function in Stage 9, which
/// runs on the admin SDK. See `functions/goals.js`.
library;

/// Comparison-only normalisation. **Never** use this to build a document id.
///
/// Trim, collapse runs of internal whitespace to one space, lowercase. Chosen
/// as the minimum that fixes the observed data: all 13 whitespace-variant keys
/// resolve under it, and it cannot merge two genuinely different names.
String normalizeStudentKey(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Keys that are test, placeholder or developer artefacts.
///
/// **Excluded from aggregates, never deleted** — they hold 8 real date-docs
/// between them, and deleting student-submitted data is not this layer's job.
///
/// `"Unknown User"` is the literal `?? 'Unknown User'` fallback in
/// `Students/pages/Questions.dart` firing when a `users` doc had no `name`.
/// `"Kaushal Pawar"` matches the development machine's own OS account.
final Set<String> kTestStudentKeys = {
  normalizeStudentKey('Kaushal Pawar'),
  normalizeStudentKey('BISWA'),
  normalizeStudentKey('Newtest'),
  normalizeStudentKey('Unknown User'),
  normalizeStudentKey('Nimai Jivan Dasaaa'),
};

/// Keys deliberately left UNRESOLVED pending a human answer.
///
/// Stage 1's automated nearest-match produced false positives on these
/// (`"Ayush "` → `"Ganesh"` at edit distance 3 is not the same person), so they
/// are **not** aliased on a guess. `"Mitesh chavda "` may be the user
/// `"Chavda Mitesh j"` with the words reversed — plausible, unconfirmed.
/// Between them: 93 date-docs.
final Set<String> kPendingConfirmationKeys = {
  normalizeStudentKey('Ayush '),
  normalizeStudentKey('Utsav'),
  normalizeStudentKey('Mitesh chavda '),
};

/// ---------------------------------------------------------------------------
/// RULE 12 JUSTIFICATION — `studentKeyAliases`
/// ---------------------------------------------------------------------------
/// A new collection, because nothing existing maps a legacy sadhana report key
/// to a student uid, and every candidate fails:
///
///  * `users` is uid-keyed with one `name` per student — nowhere to record
///    "this student's history also lives under that other spelling", and adding
///    a list field there would mean writing to a student's own profile document
///    to fix a guide-side lookup problem.
///  * `sadhana-reports` / `hostel-sadhana` are the documents that must not be
///    renamed or re-keyed (Rule 3/4), so the mapping cannot live in them — and
///    their parents are phantom, so they cannot hold fields anyway.
///  * `notification`, `scorecard`, `competition` are also name-keyed and share
///    the identical seam — more of the problem, not a solution.
///
/// Document id is the **normalised report key**; the body points at a uid.
///
///   studentKeyAliases/{normalizedReportKey}
///     reportKey  String  the ORIGINAL key, whitespace preserved, for audit
///     studentUid String  the `users` document this key belongs to
///     note       String  why this alias exists
///     addedBy    String  guide who confirmed it
///
/// ⚠️ Read-only from the app. Seeding is a one-off administrative action.
const String kStudentKeyAliasesCollection = 'studentKeyAliases';

/// Every report key a student's sadhana history might live under.
///
/// Ordered most-likely first. Callers read each path in turn; a key with no
/// data yields an empty snapshot, so an extra candidate costs one cheap read
/// and never produces a wrong answer.
///
/// Covers the two variants actually observed in production — the exact name and
/// the trailing-space form (`"Om Patel"` / `"Om Patel "`, 23 and 59 date-docs
/// respectively, one student) — plus any explicit aliases the caller supplies
/// from [kStudentKeyAliasesCollection].
///
/// ⚠️ Returns the ORIGINAL-CASE keys, never the normalised form: these strings
/// are used as document ids, and the real ids carry their original casing.
List<String> candidateReportKeys(
  String studentName, {
  List<String> aliasKeys = const [],
}) {
  final out = <String>[];
  final seen = <String>{};

  void add(String k) {
    if (k.isEmpty) return;
    if (seen.add(k)) out.add(k);
  }

  final exact = studentName;
  final trimmed = studentName.trim();

  add(exact);
  add(trimmed);
  // The observed corruption is a single trailing space; it is cheap to try.
  add('$trimmed ');

  for (final a in aliasKeys) {
    add(a);
  }

  return out;
}

/// True when this key should be left out of any per-guide aggregate.
bool isExcludedStudentKey(String reportKey) =>
    kTestStudentKeys.contains(normalizeStudentKey(reportKey));

/// Whether a key is one of the three awaiting a human decision.
bool isPendingConfirmationKey(String reportKey) =>
    kPendingConfirmationKeys.contains(normalizeStudentKey(reportKey));

/// The seam summary, as computed **server-side** by the Monday Cloud Function
/// and stored for the app to read.
///
/// The app cannot compute this itself — see this library's header. Reading a
/// stored summary is the only honest way to show it in the UI, and a stale
/// summary is clearly better than silently under-reporting a total with no
/// indication that anything is missing.
class SeamSummary {
  final int totalReportKeys;
  final int resolvedKeys;
  final int testKeys;
  final int pendingConfirmation;
  final int unresolved;
  final DateTime? computedAt;

  const SeamSummary({
    required this.totalReportKeys,
    required this.resolvedKeys,
    required this.testKeys,
    required this.pendingConfirmation,
    required this.unresolved,
    required this.computedAt,
  });

  /// Real sadhana history attributable to nobody.
  int get unlinkedCount => pendingConfirmation + unresolved;

  /// Guide-facing sentence. Empty when there is nothing to disclose.
  String get disclosure {
    if (unlinkedCount == 0) return '';
    return "$unlinkedCount student${unlinkedCount == 1 ? '' : 's'}' "
        "historical data not linked";
  }

  static SeamSummary? from(Map<String, dynamic>? data) {
    if (data == null) return null;
    int n(String k) => data[k] is num ? (data[k] as num).toInt() : 0;
    final at = data['computedAt'];
    return SeamSummary(
      totalReportKeys: n('totalReportKeys'),
      resolvedKeys: n('resolvedKeys'),
      testKeys: n('testKeys'),
      pendingConfirmation: n('pendingConfirmation'),
      unresolved: n('unresolved'),
      computedAt: at is DateTime ? at : null,
    );
  }
}
