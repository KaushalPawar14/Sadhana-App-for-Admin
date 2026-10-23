import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Master 2 A — a chanting competition runs over a span of days.
///
/// A single-day competition is simply a span whose start and end are the same
/// day, and a competition created before ranges existed has no start/end at
/// all — only `targetDateKey`. Every one of them answers [ChallengeSpan.of]
/// the same way, so nothing that shows one needs to know which kind it has.
///
/// Mirrors `spanOf` / `dateKeyOrder` in `functions/challenges.js`, which is
/// what decides which days actually count.

/// The longest a competition may run. A month is already generous for a
/// collective chant; beyond it the day-wise table stops being something a
/// phone can show.
const int kMaxChallengeDays = 31;

/// `dd-MM-yyyy` — the key the server matches on.
String challengeDayKey(DateTime d) => DateFormat('dd-MM-yyyy').format(d);

/// A `dd-MM-yyyy` key as a date, or null if it is not one.
///
/// Range-checked, not just split: `2026-10-15` also has three numeric parts
/// and must not pass for a day.
DateTime? parseChallengeDayKey(String? key) {
  final parts = (key ?? '').trim().split('-');
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  if (day < 1 || day > 31 || month < 1 || month > 12) return null;
  if (year < 1000 || year > 9999) return null;
  final d = DateTime(year, month, day);
  // DateTime rolls 31 Feb over into March — reject rather than accept it.
  if (d.day != day || d.month != month) return null;
  return d;
}

class ChallengeSpan {
  final DateTime start;
  final DateTime end;

  const ChallengeSpan(this.start, this.end);

  bool get isRange => !_sameDay(start, end);

  /// Calendar days covered, ends included.
  int get dayCount => DateTime.utc(end.year, end.month, end.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays +
      1;

  /// "1 day" / "6 days" — the helper line under the end-date picker.
  String get dayLabel => dayCount == 1 ? "1 day" : "$dayCount days";

  /// Every day of the span, in order, as `dd-MM-yyyy` keys.
  List<String> get dayKeys => [
        for (var i = 0; i < dayCount; i++)
          challengeDayKey(DateTime(start.year, start.month, start.day + i)),
      ];

  /// "20 Oct 2026" for one day, "15 Oct – 20 Oct 2026" for a span.
  String get label {
    final f = DateFormat('dd MMM yyyy');
    if (!isRange) return f.format(end);
    if (start.year == end.year) {
      return '${DateFormat('dd MMM').format(start)} – ${f.format(end)}';
    }
    return '${f.format(start)} – ${f.format(end)}';
  }

  /// The span of a `chantingChallenges` document, old or new.
  ///
  /// Falls back through the shapes in the order they were introduced:
  /// explicit start/end, then the single `targetDateKey`, then the
  /// `targetDate` timestamp. Null only when the document has no usable date
  /// at all.
  static ChallengeSpan? of(Map<String, dynamic> data) {
    DateTime? fromKey(String field) =>
        parseChallengeDayKey((data[field] ?? '').toString());

    final target = fromKey('targetDateKey') ??
        (data['targetDate'] is Timestamp
            ? (data['targetDate'] as Timestamp).toDate()
            : null);
    final start = fromKey('startDateKey') ?? target;
    final end = fromKey('endDateKey') ?? target;
    if (start == null || end == null) return null;
    // A hand-edited document with the two the wrong way round still reads as
    // a sensible span rather than a negative one.
    if (end.isBefore(start)) return ChallengeSpan(end, start);
    return ChallengeSpan(
      DateTime(start.year, start.month, start.day),
      DateTime(end.year, end.month, end.day),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// One student's rounds on one day.
class DayContribution {
  final String name;
  final int rounds;
  const DayContribution(this.name, this.rounds);
}

/// One row of the day-wise table.
class ChallengeDay {
  final String dayKey;
  final DateTime date;

  /// Students who filed rounds that day.
  final int studentCount;

  /// Rounds filed that day, all students together.
  final int rounds;

  /// Who contributed how many, most rounds first.
  final List<DayContribution> contributors;

  const ChallengeDay({
    required this.dayKey,
    required this.date,
    required this.studentCount,
    required this.rounds,
    required this.contributors,
  });
}

int _asInt(Object? v) => v is num ? v.toInt() : 0;

/// The day-wise table for [span] from the contribution rows of a competition.
///
/// Every day of the span gets a row, including days nobody chanted on — a
/// gap in the middle of a week is exactly what a guide wants to see, and
/// leaving it out would make the table look shorter than the competition.
///
/// A row with no `byDay` is one written before ranges existed; its challenge
/// was a single day, so its rounds belong to the span's last day. Days that
/// fall outside the span are ignored rather than shown, so a hand-edited row
/// cannot add a day the competition never had.
List<ChallengeDay> buildDayTable(
  ChallengeSpan span,
  Iterable<Map<String, dynamic>> contributions,
) {
  final keys = span.dayKeys;
  final perDay = {for (final k in keys) k: <DayContribution>[]};
  final lastKey = keys.last;

  for (final row in contributions) {
    final name = (row['studentName'] ?? '').toString();
    final byDay = row['byDay'];
    if (byDay is Map) {
      byDay.forEach((k, v) {
        final rounds = _asInt(v);
        if (rounds <= 0) return;
        perDay[k.toString()]?.add(DayContribution(name, rounds));
      });
    } else {
      final rounds = _asInt(row['rounds']);
      if (rounds > 0) perDay[lastKey]!.add(DayContribution(name, rounds));
    }
  }

  return [
    for (final k in keys)
      () {
        final people = perDay[k]!
          ..sort((a, b) => b.rounds.compareTo(a.rounds));
        return ChallengeDay(
          dayKey: k,
          date: parseChallengeDayKey(k)!,
          studentCount: people.length,
          rounds: people.fold(0, (acc, p) => acc + p.rounds),
          contributors: people,
        );
      }(),
  ];
}

/// Why a span cannot be created, or null if it is fine.
String? challengeSpanProblem(DateTime? start, DateTime? end) {
  if (end == null) return 'Choose an end date';
  if (start == null) return 'Choose a start date';
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  if (e.isBefore(s)) return 'The end date cannot be before the start date';
  final days = DateTime.utc(e.year, e.month, e.day)
          .difference(DateTime.utc(s.year, s.month, s.day))
          .inDays +
      1;
  if (days > kMaxChallengeDays) {
    return 'A competition can run for at most $kMaxChallengeDays days';
  }
  return null;
}
