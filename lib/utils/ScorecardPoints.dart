/// The scorecard "Total Points" figure, in one place.
///
/// **Extracted 2026-08-21 from `Home/Calendar.dart`'s per-student Points tab**
/// (previously inline at `Calendar.dart:567-573`), which is where this
/// computation originated and which now delegates here. The arithmetic is
/// byte-for-byte unchanged — `chant + book + sbClass + service`, each coerced
/// through the same `is num ? toInt() : 0` guard the original used.
///
/// Extracted rather than re-implemented because the Guide Assignment board's
/// card face needs the same figure, and two copies of a scoring formula are
/// free to drift apart. There is exactly one implementation, here.
///
/// ⚠️ **READ-ONLY.** Nothing in this file, and nothing in the board feature,
/// writes to `scorecard`. That collection is SYSTEM-DERIVED from submitted
/// sadhana reports and has never been written by the Guide app.
///
/// ⚠️ `scorecard` is keyed by student **name**, not uid, and several live
/// names carry trailing spaces. A caller holding only a uid must look the name
/// up first, and must treat "no document" as *unknown*, not as zero — see
/// [ScorecardTotals.fromSnapshotData].
library;

/// The defensive numeric coercion the original inline code used.
int scorecardCount(Object? value) => value is num ? value.toInt() : 0;

/// The four lifetime component totals on `scorecard/{name}`, plus their sum.
class ScorecardTotals {
  final int chant;
  final int book;
  final int sbClass;
  final int service;

  const ScorecardTotals({
    required this.chant,
    required this.book,
    required this.sbClass,
    required this.service,
  });

  /// The figure the Guide app labels "Total Points".
  int get total => chant + book + sbClass + service;

  factory ScorecardTotals.fromData(Map<String, dynamic> data) {
    return ScorecardTotals(
      chant: scorecardCount(data['totalChantRounds']),
      book: scorecardCount(data['totalBookRead']),
      sbClass: scorecardCount(data['totalSBClass']),
      service: scorecardCount(data['totalServiceDone']),
    );
  }

  /// Null when there is no scorecard document at all.
  ///
  /// Kept deliberately distinct from a document whose fields are all zero: a
  /// student with no scorecard has an **unknown** total, not a total of 0, and
  /// the board renders those two states differently ("—" vs "0").
  static ScorecardTotals? fromSnapshotData(Map<String, dynamic>? data) {
    if (data == null) return null;
    return ScorecardTotals.fromData(data);
  }
}
