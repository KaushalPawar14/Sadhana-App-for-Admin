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
/// ⚠️ **Computed CLIENT-SIDE, not server-side** — confirmed this task by
/// reading `Students/.../lib/services/CompetitionService.dart`. A student's
/// own device calls `CompetitionService.updateScores()` on every sadhana
/// report submission, which `FieldValue.increment()`s these fields directly.
/// There is no Cloud Function anywhere in `functions/` that touches
/// `competition`.
///
/// ⚠️ **Both "weekly" and "monthly" reset, but not on a fixed schedule.**
/// Confirmed this task (adding monthly) by reading
/// `Students/.../lib/models/CompetitionResults.dart` in full: monthly has its
/// OWN, separate lazy trigger — `checkAndRunMonthlyLazyTrigger`, called
/// alongside `checkAndRunWeeklyLazyTrigger` from `Students/.../lib/main.dart`
/// on every app start. It tracks the last-finalised month as a `"YYYY-MM"`
/// string on `competition-results/monthly_meta.last_month_finalized`, and
/// once ANY student's device is first to open the app after the month
/// number changes, it zeroes every `monthly.*` field across the whole
/// `competition` collection via its own `_resetMonthlyFields()` — the exact
/// same lazy, client-triggered, no-fixed-schedule mechanism `_resetWeeklyFields()`
/// already used for the weekly figures, just on a monthly cadence and a
/// separate meta-doc. If no student opens the app promptly after a month
/// turns over, the reset is simply late for everyone, same as weekly.
///
/// ⚠️ **The field names are literal strings containing dots, NOT a nested
/// map** — true for `monthly.*` exactly as it is for `weekly.*`.
/// `CompetitionService.dart` writes via `.set({'weekly.total_score': ...,
/// 'monthly.total_score': ...}, SetOptions(merge: true))` — `set()` (unlike
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

  const CompetitionTotals({
    required this.weeklyTotalScore,
    required this.weeklyDaysCount,
    required this.monthlyTotalScore,
    required this.monthlyDaysCount,
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
