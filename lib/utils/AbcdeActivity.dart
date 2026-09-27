/// ABCDE activity maths — pure Dart, deliberately no Flutter imports.
///
/// Kept separate from the card widget so the bracket boundaries and the
/// day-offset handling can be executed and checked directly with `dart run`,
/// rather than only eyeballed inside a widget tree. Every number this file
/// produces is shown to a guide beside the raw figure it came from.
///
/// ⚠️ **This file must never import or reference `litAssessments`, L, I or T.**
/// ABCDE and LIT are separate systems (Rule 10). This is activity data only.
library;

// ---------------------------------------------------------------------------
// Date keys
// ---------------------------------------------------------------------------

/// Sadhana date documents are keyed `dd-MM-yyyy`.
///
/// ⚠️ That format **does not sort chronologically** as a string, which is why
/// no range query is possible over these ids and the whole subcollection must
/// be read and indexed by real date. The same constraint is documented in the
/// Student app at `ChantingScreen.dart:173-174`.
String sadhanaDateKey(DateTime date) =>
    "${date.day.toString().padLeft(2, '0')}-"
    "${date.month.toString().padLeft(2, '0')}-"
    "${date.year}";

/// Parses a `dd-MM-yyyy` document id, or null if the id is not a date key.
///
/// Hand-rolled rather than `DateFormat.parseStrict` so this file stays
/// dependency-free and runnable outside Flutter. Rolled-over dates such as
/// `31-02-2026` are rejected rather than silently becoming 3 March, which
/// `DateTime(y, m, d)` would otherwise do.
DateTime? parseSadhanaDateKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  if (parts[0].length != 2 || parts[1].length != 2 || parts[2].length != 4) {
    return null;
  }

  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;

  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// The most recent day that can possibly have data.
///
/// A report submitted on day N records day **N−1**'s practice, so today's
/// practice will not exist until tomorrow's submission. The trailing window
/// therefore ends **yesterday**, not today.
///
/// This is a deliberate difference from `ChantingScreen`'s heatmap, which ends
/// on today because a calendar strip should show today's square. Here, a
/// guaranteed-empty final day would drag the recent average down and could
/// invent a "declining" reading out of nothing.
DateTime latestDayWithPossibleData(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(const Duration(days: 1));
}

/// Builds a chronological daily series of length [days] ending at
/// [latestDayWithPossibleData].
///
/// [valueByDocId] maps a raw `dd-MM-yyyy` document id to that document's value
/// for one field. **The −1 day shift is applied here**: a document keyed day N
/// contributes to day N−1. Getting this wrong shifts every trend by a day.
///
/// Days with no document yield 0 — absence of a report is genuinely zero
/// practice recorded, which is what a guide needs to see. Whether the student
/// has submitted *anything at all* is reported separately by [hasAnyReports].
List<int> dailySeries({
  required Map<String, int> valueByDocId,
  required DateTime now,
  int days = 30,
}) {
  final byActualDay = <String, int>{};

  for (final entry in valueByDocId.entries) {
    final keyDate = parseSadhanaDateKey(entry.key);
    if (keyDate == null) continue;

    // The practice happened the day BEFORE the document's key.
    final actualDay = keyDate.subtract(const Duration(days: 1));
    byActualDay[sadhanaDateKey(actualDay)] = entry.value;
  }

  final lastDay = latestDayWithPossibleData(now);

  final series = <int>[];
  for (int i = days - 1; i >= 0; i--) {
    final day = lastDay.subtract(Duration(days: i));
    series.add(byActualDay[sadhanaDateKey(day)] ?? 0);
  }
  return series;
}

/// True when the student has at least one parseable report document at all.
///
/// Distinguishes "submitted nothing ever" from "submitted, recorded zero" —
/// rendering those two identically would show a brand-new student as inactive.
bool hasAnyReports(Map<String, int> valueByDocId) =>
    valueByDocId.keys.any((k) => parseSadhanaDateKey(k) != null);

// ---------------------------------------------------------------------------
// C — chanting bracket
// ---------------------------------------------------------------------------

/// Chanting bracket labels, reusing the podcast modules' five category names.
///
/// ⚠️ **Informational only.** This label does not gate anything. Podcast
/// modules are free-browse for every student regardless of this value, and
/// nothing outside this card reads it — there is deliberately no shared
/// constant linking the two, so a future edit here cannot silently change
/// podcast behaviour.
const List<String> kChantBracketLabels = [
  'Below F2',
  'F2',
  'F4',
  'F8',
  'F12',
  'F16',
];

/// Maps an average daily chanting-round count to a bracket label.
///
/// Boundaries exactly as specified — 1, 4, 8, 12, 16:
///   Below F2 : under 1 round/day
///   F2       : 1–3
///   F4       : 4–7
///   F8       : 8–11
///   F12      : 12–15
///   F16      : 16+
///
/// ⚠️ **Interpretation, stated openly:** the bands were specified as whole
/// numbers but an average is fractional, so the bands are treated as
/// contiguous half-open intervals — 3.5 rounds/day is F2, not "between F2 and
/// F4". No boundary value was invented; only the gaps between them were
/// closed, and closing them downward never flatters the student.
String chantingBracketFor(double avgRoundsPerDay) {
  if (avgRoundsPerDay < 1) return 'Below F2';
  if (avgRoundsPerDay < 4) return 'F2';
  if (avgRoundsPerDay < 8) return 'F4';
  if (avgRoundsPerDay < 12) return 'F8';
  if (avgRoundsPerDay < 16) return 'F12';
  return 'F16';
}

/// Mean of a daily series. Returns 0 for an empty series.
double averagePerDay(List<int> series) {
  if (series.isEmpty) return 0;
  final total = series.fold<int>(0, (sum, v) => sum + v);
  return total / series.length;
}

// ---------------------------------------------------------------------------
// Trend direction (C and B only)
// ---------------------------------------------------------------------------

/// A two-window comparison, carrying the numbers it was derived from so the UI
/// can always show them beside the word.
class TrendReading {
  /// Mean per day over the most recent 14 days of the series.
  final double recentAvg;

  /// Mean per day over the 14 days immediately before those.
  final double priorAvg;

  /// One of `improving`, `steady`, `declining`, or `not enough data`.
  final String direction;

  const TrendReading({
    required this.recentAvg,
    required this.priorAvg,
    required this.direction,
  });

  bool get isKnown => direction != 'not enough data';
}

/// Compares the last 14 days against the 14 before them.
///
/// On a 30-day series the two windows cover days 3–30, so the oldest 2 days sit
/// outside both windows by design — 14 + 14 does not divide 30, and stretching
/// a window to swallow them would make the two halves unequal and the
/// comparison meaningless.
///
/// ⚠️ The ±10% band and the 0.5/day absolute floor below are **chosen
/// defaults, not a stated policy.** They exist because a bare `>` comparison
/// would label 4.0 → 4.07 rounds/day "improving", which is noise, and because
/// a guide who is shown a direction word every time stops reading it. Both are
/// single-constant edits and worth revisiting once real guides use this.
TrendReading trendFromSeries(List<int> series, {int window = 14}) {
  if (series.length < window * 2) {
    return const TrendReading(
        recentAvg: 0, priorAvg: 0, direction: 'not enough data');
  }

  final recent = series.sublist(series.length - window);
  final prior = series.sublist(series.length - window * 2, series.length - window);

  final recentAvg = averagePerDay(recent);
  final priorAvg = averagePerDay(prior);

  // Nothing recorded in either window is not a trend, in either direction.
  if (recentAvg == 0 && priorAvg == 0) {
    return TrendReading(
        recentAvg: recentAvg, priorAvg: priorAvg, direction: 'steady');
  }

  final difference = recentAvg - priorAvg;
  final tolerance = (priorAvg * 0.10) < 0.5 ? 0.5 : (priorAvg * 0.10);

  if (difference.abs() <= tolerance) {
    return TrendReading(
        recentAvg: recentAvg, priorAvg: priorAvg, direction: 'steady');
  }

  return TrendReading(
    recentAvg: recentAvg,
    priorAvg: priorAvg,
    direction: difference > 0 ? 'improving' : 'declining',
  );
}

// ---------------------------------------------------------------------------
// A — association recency
// ---------------------------------------------------------------------------

/// Whole days between [from] and [to], comparing calendar days rather than
/// instants so "yesterday" is 1 regardless of the clock time on either side.
int wholeDaysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}
