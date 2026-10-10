/// The metrics a guide may put in a compound target, and — just as
/// importantly — what each one is honestly capable of (originally Stage 4,
/// built 2026-08-23; trimmed to chanting/books only when the old
/// association/expeditions aggregate-target system was retired entirely —
/// see `GoalCompoundQueries.dart`'s own header, and the task that removed
/// it, for why).
///
/// Every entry here was decided by reading real data, not by assumption. The
/// `capability` field is not decoration: `CompoundGoalProgressPage.dart` and
/// `functions/goals.js`'s evaluator both branch on it, so a metric cannot
/// accidentally be presented as live when its data cannot support that.
///
/// ⚠️ **Association and expeditions are gone, full stop** — not hidden, not
/// deprecated-but-selectable. They modelled a per-event GROUP action (a
/// meeting, a registration), which has no per-student daily/lifetime value to
/// threshold against — the compound "N students at value V" shape this app
/// now exclusively offers does not apply to them at all. Their real Firestore
/// data (the old `guideTargets/{guideId}` top-level documents and `phases`
/// subcollections that used them) was deleted, not merely orphaned.
///
/// ---------------------------------------------------------------------------
/// Why each remaining metric is where it is
/// ---------------------------------------------------------------------------
///  * **Books** — `booksRead/{uid}_{level}_{bookKey}` is uid-keyed (no name
///    seam), so a per-guide total is cheap and live. But its dates are
///    `yyyy-MM-dd` **strings**, and a `uid` equality plus a date range is a
///    compound query needing a composite index this project has never used.
///    So: **lifetime total only**. The UI says "books finished", never "this
///    week".
///
///  * **Chanting** — for the COMPOUND system, this is now a self-set
///    COMMITMENT (`users/{uid}.commitmentRounds`), never the name-keyed
///    `sadhana-reports`/`hostel-sadhana` weekly-report aggregation the
///    original (now-retired) goal system used. A student sets it once from
///    `CompleteProfile.dart`'s registration continuation, or any time after
///    from `Profile.dart` — a real write path exists in the Student app now,
///    reversing the earlier explicit decision not to add one. Checking a
///    guide's students against a threshold is a plain uid-scoped field
///    comparison — as cheap as Books below, not the expensive name-key
///    resolution + full `dates`-subcollection scan the old aggregation
///    needed. **Genuinely LIVE**, not weekly-only — see
///    `functions/goals.js`'s `chantingStudentsAtOrAboveThreshold` and
///    `Guides/.../GoalCompoundQueries.dart`'s `liveBooksThresholdCount`
///    sibling for the matching chanting version.
///
///  * **Service** — **EXCLUDED, and not offered.** Completion is not recorded
///    anywhere; `Guides/.../AbcdeActivityCard.dart:293` and `:632` both say so
///    outright. `dailyServices` is a 0/1/2 enum written by FOLK residents only
///    (hostel reports lack the field entirely), and `scorecard.totalServiceDone`
///    is lifetime-cumulative with no week attribution. A weekly service target
///    would be invented, not measured.
library;

import 'package:flutter/material.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideColors.dart';

/// How trustworthy a metric's figure is at the moment it is displayed.
enum MetricCapability {
  /// Recomputed from source data on every read.
  live,

  /// A true total with no time window. Correct, but not "this week".
  lifetimeTotal,

  /// Only refreshed by the Monday Cloud Function. Stale between runs, by
  /// design, and must be labelled with the date it was computed.
  weeklyOnly,
}

class GoalMetric {
  /// Stored as `guideTargets/{guideId}/targets/{targetId}.metric`.
  /// ⚠️ Never rename — this string persists in Firestore.
  final String id;

  final String label;

  /// Plural noun for the target value, e.g. "5 meetings".
  final String unit;

  final MetricCapability capability;

  /// Shown under the metric wherever it appears. Empty when there is nothing
  /// the guide needs warning about.
  final String caveat;

  const GoalMetric({
    required this.id,
    required this.label,
    required this.unit,
    required this.capability,
    this.caveat = '',
  });

  bool get isLive => capability == MetricCapability.live;
  bool get isWeeklyOnly => capability == MetricCapability.weeklyOnly;
  bool get isLifetime => capability == MetricCapability.lifetimeTotal;
}

const String kMetricBooks = 'books';
const String kMetricChanting = 'chanting';

/// The selectable list. Service is absent by design — see the library
/// comment. Association/expeditions are absent because they were retired
/// entirely, not because of a capability limitation.
const List<GoalMetric> kGoalMetrics = [
  GoalMetric(
    id: kMetricBooks,
    label: 'Books',
    unit: 'books finished',
    capability: MetricCapability.lifetimeTotal,
    caveat: 'Lifetime total across your students, not a weekly count — the '
        'reading data cannot be split by week.',
  ),
  GoalMetric(
    id: kMetricChanting,
    label: 'Chanting rounds',
    unit: 'rounds',
    // LIVE, not weekly-only — this checks each student's own self-set
    // `commitmentRounds`, a plain field, not a scan of their submitted
    // reports. See this file's own library comment for the full history.
    capability: MetricCapability.live,
    caveat: 'This counts students who have COMMITTED to this many rounds a '
        'day, not who actually chanted that much this week — a student sets '
        'their own commitment from their profile.',
  ),
];

GoalMetric? goalMetricById(String id) {
  for (final m in kGoalMetrics) {
    if (m.id == id) return m;
  }
  return null;
}

/// The colour and wording for a capability badge.
///
/// ⚠️ **Defined once, here.** Every screen that shows a metric's figure
/// (`CompoundGoalProgressPage.dart`, `GoalWeeklyPhasePage.dart`) uses this —
/// if they worded a capability differently the guide would learn two
/// meanings for one thing. Keeping it beside the capability it describes is
/// why this file imports material.
(Color, String) capabilityBadge(MetricCapability c, GuideColors g) {
  switch (c) {
    case MetricCapability.live:
      return (g.success, 'Live');
    case MetricCapability.lifetimeTotal:
      return (g.brass, 'Lifetime total');
    case MetricCapability.weeklyOnly:
      return (g.warning, 'Weekly — updates Mondays');
  }
}
