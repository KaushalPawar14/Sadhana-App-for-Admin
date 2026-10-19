/// The app's real, weighted competition score — `competition/{name}`, in one
/// place. Extracted this task (FOLK Boys board, drag-to-delete + scores)
/// specifically so `Pages/StudentProfilePage.dart` reads the same figure
/// every other score screen (`Scores/WeeklyResults.dart`,
/// `Scores/MonthlyResults.dart`, `Scores/TopWeekResults.dart`,
/// `Scores/TopMonthResults.dart`) already reads inline, rather than adding a
/// SEVENTH copy of the same two-field read. Matches
/// `utils/ScorecardPoints.dart`'s own precedent: one small file per data
/// source, not a shared "scores" grab-bag.
///
/// ⚠️ **Computed SERVER-SIDE, from the student's reports** (the new point
/// system, `functions/scoring.js`): every filed report re-scores the student's
/// current week and month, and the totals are SET from the reports (never
/// incremented), so they always match what was filed. Weekly (Sunday-Saturday)
/// and monthly figures are zeroed at the end of their period by the server.
/// The apps only read this document.
///
/// ⚠️ **The field names are literal strings containing dots, NOT a nested
/// map** — true for `monthly.*` exactly as it is for `weekly.*`.
/// The server writes via `.set({'weekly.total_score': ...,
/// 'monthly.total_score': ...}, {merge: true})` — `set()` (unlike
/// `update()`) does not interpret a dotted key as a field path, so Firestore
/// stores flat top-level fields literally named `weekly.total_score` and
/// `monthly.total_score`. Confirmed against a live document dump this task
/// (service account, read-only, student "Atharva Pagare"): real fields
/// include `"monthly.total_score": 455.1` and `"monthly.days_count": 25`
/// alongside the weekly ones — never a nested `monthly: {total_score: ...}`
/// map. The correct read is `data['monthly.total_score']`, exactly as
/// `data['weekly.total_score']` already is.
///
/// ⚠️ **Keyed by student NAME, not uid** — same collision risk
/// `utils/ScorecardPoints.dart` already documents for `scorecard`. A caller
/// holding only a uid must resolve the name first, and "no document" must be
/// treated as *unknown*, never as a score of zero.
///
/// ⚠️ **READ-ONLY.** Nothing in the Guide app writes to `competition`.
library;

/// The real, weighted figures a guide should treat as "the score" — weekly
/// and monthly `total_score`, plus how many days fed into each, so a guide
/// can see at a glance whether a low score means "quiet period" or "no
/// reports yet". Both come off the SAME `competition/{name}` document, so
/// one model reads both rather than two separate reads of the same doc.
class CompetitionTotals {
  final double weeklyTotalScore;
  final int weeklyDaysCount;
  final double monthlyTotalScore;
  final int monthlyDaysCount;

  /// The same period's points per item and multipliers, for the breakdown.
  final PeriodBreakdown weekly;
  final PeriodBreakdown monthly;

  /// Hostel & Localite students are scored on wake-up (not temple entry) and
  /// have no daily services or extra lecture.
  final bool hostelLocalite;

  const CompetitionTotals({
    required this.weeklyTotalScore,
    required this.weeklyDaysCount,
    required this.monthlyTotalScore,
    required this.monthlyDaysCount,
    this.weekly = const PeriodBreakdown(),
    this.monthly = const PeriodBreakdown(),
    this.hostelLocalite = false,
  });

  factory CompetitionTotals.fromData(Map<String, dynamic> data) {
    final rawWeeklyScore = data['weekly.total_score'];
    final rawWeeklyDays = data['weekly.days_count'];
    final rawMonthlyScore = data['monthly.total_score'];
    final rawMonthlyDays = data['monthly.days_count'];
    return CompetitionTotals(
      weeklyTotalScore: rawWeeklyScore is num ? rawWeeklyScore.toDouble() : 0,
      weeklyDaysCount: rawWeeklyDays is num ? rawWeeklyDays.toInt() : 0,
      monthlyTotalScore:
          rawMonthlyScore is num ? rawMonthlyScore.toDouble() : 0,
      monthlyDaysCount: rawMonthlyDays is num ? rawMonthlyDays.toInt() : 0,
      weekly: PeriodBreakdown.fromData(data, 'weekly'),
      monthly: PeriodBreakdown.fromData(data, 'monthly'),
      hostelLocalite: data['category'] == 'hostel_localite',
    );
  }

  /// Null when there is no `competition` document at all — kept distinct
  /// from a real score of 0, same rule `ScorecardTotals.fromSnapshotData`
  /// uses for `scorecard`.
  static CompetitionTotals? fromSnapshotData(Map<String, dynamic>? data) {
    if (data == null) return null;
    return CompetitionTotals.fromData(data);
  }
}

/// One period's points per item (each already multiplied by that day's
/// multipliers, so the items add up to the total) and its multipliers. The
/// multipliers are stored as per-day SUMS; [average] turns one into the figure
/// shown (sum / days, 1.00 with no days).
class PeriodBreakdown {
  final double total;
  final int days;
  final double sbClass;
  final double service;
  final double chanting;
  final double reading;
  final double extraLecture;
  final double templeSum;
  final double wakeupSum;
  final double japaSum;
  final double sleepSum;

  const PeriodBreakdown({
    this.total = 0,
    this.days = 0,
    this.sbClass = 0,
    this.service = 0,
    this.chanting = 0,
    this.reading = 0,
    this.extraLecture = 0,
    this.templeSum = 0,
    this.wakeupSum = 0,
    this.japaSum = 0,
    this.sleepSum = 0,
  });

  factory PeriodBreakdown.fromData(Map<String, dynamic> data, String prefix) {
    double n(String k) {
      final v = data['$prefix.$k'];
      return v is num ? v.toDouble() : 0;
    }

    return PeriodBreakdown(
      total: n('total_score'),
      days: n('days_count').toInt(),
      sbClass: n('bhagavatam_class'),
      service: n('daily_service'),
      chanting: n('chanting_rounds'),
      reading: n('book_reading'),
      extraLecture: n('extra_lecture'),
      templeSum: n('temple_multiplier'),
      wakeupSum: n('wakeup_multiplier'),
      japaSum: n('japa_multiplier'),
      sleepSum: n('sleeping_multiplier'),
    );
  }

  String average(double sum) => days <= 0 ? '1.00' : (sum / days).toStringAsFixed(2);

  /// "label: points" for each item the student's form has, in the form's order.
  List<({String label, String value})> itemLines({required bool hostelLocalite}) => [
        (label: 'SB class', value: sbClass.toStringAsFixed(1)),
        if (!hostelLocalite) (label: 'Services', value: service.toStringAsFixed(1)),
        (label: 'Chanting', value: chanting.toStringAsFixed(1)),
        (label: 'Reading', value: reading.toStringAsFixed(1)),
        if (!hostelLocalite) (label: 'Extra lecture', value: extraLecture.toStringAsFixed(1)),
      ];

  /// Average multipliers: temple (FOLK) or wake-up (Hostel & Localite), japa, sleep.
  List<({String label, String value})> multiplierLines({required bool hostelLocalite}) => [
        if (hostelLocalite)
          (label: 'Wake-up', value: average(wakeupSum))
        else
          (label: 'Temple', value: average(templeSum)),
        (label: 'Japa', value: average(japaSum)),
        (label: 'Sleep', value: average(sleepSum)),
      ];
}
