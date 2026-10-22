/// The time-of-day multiplier tiers of the point system, in the Guide app.
///
/// ---------------------------------------------------------------------------
/// A PORT, not a second opinion
/// ---------------------------------------------------------------------------
/// These are the same tables as `functions/scoring.js` (`TIERS`) and the Student
/// app's `lib/utils/DayScore.dart`, ported line for line. The Guide app needs
/// them because Priority students decides whether a student reached at least the
/// ×1.15 tier on a day, and that judgement must be the same one the server makes
/// when it scores the day — otherwise a guide is told a student is slipping on
/// days the leaderboard says were fine.
///
/// `test/sadhana_tiers_test.dart` pins every function here to
/// `test/fixtures/scoring_vectors.json`, which is a byte-identical copy of
/// `functions/test/scoring_vectors.json` — the same file the server's own tests
/// and the Student app's tests read. A tier changed on the server and not here
/// fails that test, so the three cannot drift apart silently.
///
/// Only the TIER machinery is ported. The points themselves (chanting, reading,
/// graded items) are not computed in this app at all: the server owns them, and
/// Priority students compares a student's own reported numbers against their own
/// commitments rather than re-scoring anything.
library;

// minutes since midnight; a time of day is "by" a limit when it is at or before it
const List<List<num>> _japa = [
  [10 * 60, 1.5],
  [14 * 60, 1.25],
  [18 * 60, 1.15],
];
const List<List<num>> _sleepFolk = [
  [22 * 60, 1.5],
  [22 * 60 + 30, 1.25],
  [23 * 60, 1.15],
];
const List<List<num>> _temple = [
  [5 * 60 + 35, 1.5],
  [5 * 60 + 45, 1.25],
  [6 * 60, 1.15],
];
const List<List<num>> _wakeup = [
  [5 * 60 + 30, 1.5],
  [6 * 60, 1.25],
  [6 * 60 + 30, 1.15],
];
const List<List<num>> _sleepHostel = [
  [22 * 60 + 30, 1.5],
  [23 * 60, 1.25],
  [23 * 60 + 30, 1.15],
];

/// Which multiplier's tier table.
enum ScoreTier { japa, sleepFolk, temple, wakeup, sleepHostel }

/// The tiers of a multiplier: "by [limit] minutes after midnight" earns
/// [multiplier]; anything later, or a missing/unreadable time, is 1.0.
List<({int limit, double multiplier})> tierRows(ScoreTier tier) {
  final rows = switch (tier) {
    ScoreTier.japa => _japa,
    ScoreTier.sleepFolk => _sleepFolk,
    ScoreTier.temple => _temple,
    ScoreTier.wakeup => _wakeup,
    ScoreTier.sleepHostel => _sleepHostel,
  };
  return [for (final r in rows) (limit: r[0].toInt(), multiplier: r[1].toDouble())];
}

/// The tier a day must reach before Priority students stops counting it as a
/// slip. Below this and the day is "not reaching at least the 1.15 tier".
const double kMinimumGoodTier = 1.15;

/// Minutes since midnight as a clock time: 335 -> "5:35 AM", 1320 -> "10:00 PM".
String clockText(int minutes) {
  final h24 = minutes ~/ 60;
  final m = minutes % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
}

/// "HH:mm", "H:mm" or "h:mm a" -> minutes since midnight, or null.
int? minutesOf(Object? value) {
  final s = (value ?? '').toString().trim();
  var m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
  if (m != null) {
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    return h < 24 && mi < 60 ? h * 60 + mi : null;
  }
  m = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$').firstMatch(s);
  if (m != null) {
    var h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h < 1 || h > 12 || mi > 59) return null;
    h = h % 12 + (m.group(3)!.toLowerCase().startsWith('p') ? 12 : 0);
    return h * 60 + mi;
  }
  return null;
}

double _tier(int? minutes, List<List<num>> tiers) {
  if (minutes == null) return 1.0;
  for (final t in tiers) {
    if (minutes <= t[0]) return t[1].toDouble();
  }
  return 1.0;
}

/// A sleep time as the form saves it: anything before noon is "after midnight"
/// and counts as 11:59 PM.
int? sleepMinutes(Object? value) {
  final m = minutesOf(value);
  return m != null && m < 12 * 60 ? 23 * 60 + 59 : m;
}

double japaMultiplier(Object? v) => _tier(minutesOf(v), _japa);
double folkSleepMultiplier(Object? v) => _tier(sleepMinutes(v), _sleepFolk);
double templeMultiplier(Object? v) => _tier(minutesOf(v), _temple);
double wakeupMultiplier(Object? v) => _tier(minutesOf(v), _wakeup);
double hostelSleepMultiplier(Object? v) => _tier(sleepMinutes(v), _sleepHostel);

/// The standard daily chanting number when a student has none on file — the
/// server's own `DEFAULT_CHANT_COMMITMENT`.
const int kDefaultChantCommitment = 16;
