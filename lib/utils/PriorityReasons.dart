/// Why a student is on the Priority list, worked out from their own reports.
///
/// ---------------------------------------------------------------------------
/// The rules, in one place
/// ---------------------------------------------------------------------------
/// Each reason needs THREE CONSECUTIVE DAYS, and every one is read from the
/// student's OWN CATEGORY only (`sadhana-reports` for FOLK, `hostel-sadhana` for
/// Hostel & Localite — `SadhanaReportSource` already decides which) using only
/// what the FORM recorded. Nothing here re-scores a day; the server owns the
/// points. This only asks "has the same thing gone wrong three days running?".
///
///   no report            three calendar days in a row with no report at all
///   chanting below       three REPORTED days in a row under the commitment
///   reading below        the same for reading, skipped when the reading
///                        commitment is 0 (then any reading is already full marks)
///   morning late         three reported days in a row below the ×1.15 tier on
///                        temple entry (FOLK) or wake-up (Hostel & Localite)
///   sleep late           three reported days in a row below the ×1.15 tier
///
/// "Three REPORTED days in a row" means three consecutive entries in the list of
/// days the student actually filed — a day they did not file is not a day they
/// chanted too little, and it is already covered by the no-report reason.
///
/// ---------------------------------------------------------------------------
/// Shared with the server
/// ---------------------------------------------------------------------------
/// `functions/priorityReasons.js` computes the SAME reasons with the same keys,
/// for the nightly notification. This file and that one are checked against the
/// same cases, and the tier judgements both make come from the shared vectors
/// (`SadhanaTiers`, pinned by `test/sadhana_tiers_test.dart`).
library;

import 'SadhanaTiers.dart';

/// How many days in a row a thing must go wrong.
const int kPriorityRunLength = 3;

/// The stable key of each reason. Stored on the server document and used to
/// decide whether a reason is NEW, so these strings must not change casually.
enum PriorityReasonKind { noReport, chanting, reading, morning, sleep }

extension PriorityReasonKindX on PriorityReasonKind {
  String get key => switch (this) {
        PriorityReasonKind.noReport => 'no_report',
        PriorityReasonKind.chanting => 'chanting_below',
        PriorityReasonKind.reading => 'reading_below',
        PriorityReasonKind.morning => 'morning_late',
        PriorityReasonKind.sleep => 'sleep_late',
      };

  static PriorityReasonKind? fromKey(String key) {
    for (final k in PriorityReasonKind.values) {
      if (k.key == key) return k;
    }
    return null;
  }
}

/// One reason, with the short sentence a guide reads.
class PriorityReason {
  const PriorityReason(this.kind, this.text);
  final PriorityReasonKind kind;

  /// e.g. "No report since 20 Oct", "Chanting under 16 rounds on 3 days".
  final String text;

  String get key => kind.key;

  @override
  bool operator ==(Object other) =>
      other is PriorityReason && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.key}: $text';
}

/// One day of the window: the calendar date, and the report filed for it (null
/// when the student filed nothing that day).
class ReportDay {
  const ReportDay(this.date, this.report);
  final DateTime date;
  final Map<String, dynamic>? report;
  bool get filed => report != null;
}

/// Is this student on the Hostel & Localite form? (Their residence `role`.)
bool isHostelForm(String? role) {
  final r = (role ?? '').trim();
  return r == 'Stay at Hostel' || r == 'Stay at Localite';
}

num? _num(Object? v) => v is num && v.isFinite ? v : null;

String _shortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// The reasons that are true RIGHT NOW.
///
/// [days] is the window, MOST RECENT FIRST, one entry per calendar day with no
/// gaps. [chantCommitment] of 0 or less means the standard 16 (the server's own
/// rule); [readingCommitment] of 0 means the reading reason does not apply.
List<PriorityReason> priorityReasonsFor({
  required List<ReportDay> days,
  required String? role,
  required int chantCommitment,
  required int readingCommitment,
}) {
  final out = <PriorityReason>[];
  if (days.isEmpty) return out;

  final hostel = isHostelForm(role);
  final chantTarget =
      chantCommitment > 0 ? chantCommitment : kDefaultChantCommitment;

  // ---- no report: the most recent days, in a row, with nothing filed --------
  var missing = 0;
  for (final d in days) {
    if (d.filed) break;
    missing++;
  }
  if (missing >= kPriorityRunLength) {
    final lastFiled = days.where((d) => d.filed).firstOrNull;
    out.add(PriorityReason(
      PriorityReasonKind.noReport,
      lastFiled == null
          ? 'No report in the last ${days.length} days'
          : 'No report since ${_shortDate(lastFiled.date)}',
    ));
  }

  // ---- the rest look only at days that WERE filed ---------------------------
  final filed = days.where((d) => d.filed).toList();
  if (filed.length < kPriorityRunLength) return out;
  final run = filed.take(kPriorityRunLength).toList();

  bool allOf(bool Function(Map<String, dynamic>) test) =>
      run.every((d) => test(d.report!));

  // chanting under the commitment
  if (allOf((r) {
    final rounds = _num(r['chantRounds']);
    return rounds != null && rounds < chantTarget;
  })) {
    out.add(PriorityReason(
      PriorityReasonKind.chanting,
      'Chanting under $chantTarget rounds on $kPriorityRunLength days',
    ));
  }

  // reading under the commitment — only when there is one
  if (readingCommitment > 0 &&
      allOf((r) {
        final mins = _num(r['bookReading']);
        return mins != null && mins < readingCommitment;
      })) {
    out.add(PriorityReason(
      PriorityReasonKind.reading,
      'Reading under $readingCommitment min on $kPriorityRunLength days',
    ));
  }

  // the morning: temple entry (FOLK) or wake-up (Hostel & Localite)
  if (allOf((r) => (hostel
          ? wakeupMultiplier(r['wakeUpTime'])
          : templeMultiplier(r['templeEntry'])) <
      kMinimumGoodTier)) {
    out.add(PriorityReason(
      PriorityReasonKind.morning,
      hostel
          ? 'Waking up late on $kPriorityRunLength days'
          : 'Reaching the temple late on $kPriorityRunLength days',
    ));
  }

  // sleep
  if (allOf((r) => (hostel
          ? hostelSleepMultiplier(r['sleepTiming'])
          : folkSleepMultiplier(r['sleepTiming'])) <
      kMinimumGoodTier)) {
    out.add(PriorityReason(
      PriorityReasonKind.sleep,
      'Sleeping late on $kPriorityRunLength days',
    ));
  }

  return out;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
