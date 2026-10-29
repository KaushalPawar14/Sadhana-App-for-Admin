/// Compound guide targets — "N students at value V" — schema and every
/// Firestore operation (Guide Target Planning continuation, built
/// 2026-08-28).
///
/// ---------------------------------------------------------------------------
/// Why a NEW, separate collection path rather than extending `GoalQueries.dart`
/// ---------------------------------------------------------------------------
/// `GoalQueries.dart`'s `guideTargets/{guideId}` models a target's number as a
/// RAW AGGREGATE across the guide's whole group (e.g. "15 total confirmed
/// meetings", "40 books finished total"). A compound target's number means
/// something categorically different — "N individual students each at/above
/// value V" — which does not fit that shape at all: `perMetricTargets` has no
/// concept of a student COUNT, only a metric SUM. Bolting a student-count
/// field onto the old per-metric-sum model would silently redefine what an
/// existing guide's live goal number means.
///
/// So: a genuinely new, additive subcollection —
/// `guideTargets/{guideId}/targets/{targetId}` — living BESIDE the old
/// top-level `guideTargets/{guideId}` document, never inside it. The old
/// document, its own `phases` subcollection, `GoalQueries.dart`,
/// `GoalSetup.dart`'s existing classes, `PhasePlanService.dart` and
/// `GoalProgressBar.dart` are untouched by this file — confirmed by grep, not
/// merely by intent (see the verification report this file's task produced).
///
/// ⚠️ Restricted to `chanting` and `books` ONLY (enforced in [validMetric]).
/// Association/expeditions are per-event group actions with no per-student
/// daily/lifetime value to threshold against — the compound shape does not
/// apply to them, per the product owner's confirmed scope.
///
/// ---------------------------------------------------------------------------
/// Firestore
/// ---------------------------------------------------------------------------
///   guideTargets/{guideId}/targets/{targetId}
///     metric              String    "chanting" | "books"
///     studentCountGoal    int
///     perStudentValueGoal int       rounds/day for chanting, book count for books
///     endDate             Timestamp
///     status              String    "active" | "completed" | "abandoned"
///     currentPhase        int
///     totalPhases         int
///     createdAt           Timestamp
///     pendingProposal     Map?      {proposedBy, proposedPhases, proposedAt, note}
///                                   — null when nothing is pending.
///
///   guideTargets/{guideId}/targets/{targetId}/phases/{n}
///     phaseNumber              int
///     tasks                    List<Map>  see [CompoundTask] — TASK-LIST model
///                              (fixed round-ladder task-list task, replaces
///                              the old flat studentCountSubGoal/
///                              perStudentValueSubGoal-per-phase design).
///                              Each entry is either:
///                                {type:"roster", fromCount, toCount}
///                                  — at most one per phase.
///                                {type:"value", fromLevel, toLevel,
///                                 studentUids: [...]}
///                                  — zero or more per phase, each against a
///                                  group SNAPSHOTTED at generation time.
///     status                   String  "pending" | "active" | "achieved" | "failed"
///     startedAt                Timestamp?
///     weeklyHistory            List<Map>  {weekOf, result, actuals}
///                              `actuals.taskResults` is a per-task array of
///                              {complete, actual} in the SAME order as
///                              `tasks` — see [CompoundWeeklyResult].
///
/// ⚠️ **INDEPENDENT phase timeline per target** (an explicit, flagged
/// assumption): a guide's chanting track and books track each carry their own
/// `currentPhase`/`totalPhases`/`phases` — they do not share one clock, unlike
/// the old system's `selectedMetrics` bundle. The product owner's description
/// never explicitly resolved this either way; independent pacing was chosen
/// because a compound target's whole premise (roster growth vs. value
/// escalation) is metric-specific reasoning that a shared clock would force
/// into lockstep for no stated reason.
///
/// ---------------------------------------------------------------------------
/// WRITE SURFACE
/// ---------------------------------------------------------------------------
/// This file writes ONLY `guideTargets/*/targets/**`. Never the old top-level
/// `guideTargets/{guideId}` document's own fields, never its `phases`
/// subcollection. Never `users`, `sadhana-reports`, `hostel-sadhana`,
/// `booksRead` — every metric source is read with `.get()` only, exactly the
/// discipline `GoalQueries.dart` already established.
///
/// ⚠️ **HOD vs. guide, the one write-path distinction that matters most**:
/// [directlyEditPhaseTasks] (guide-only, manual editor AND the AI's own
/// [callRegenerateCompoundPlan] path) is the ONLY way anything reaches
/// `phases/**` directly. [proposeManualPhaseEdit] (HOD, manual editor) and
/// `functions/goals.js`'s `suggestCompoundPlan` (HOD, AI note) are the ONLY
/// two ways `pendingProposal` gets written — both structurally incapable of
/// touching `phases/**`. [approveProposal]/[rejectProposal] (guide-only)
/// are what actually turns a proposal, from either source, into live tasks.
///
/// Two genuinely separate, EQUALLY available paths per role (restored
/// manual-editing task, this continuation) — a value task's real content is
/// a specific, real student-uid group, so the manual editor
/// (`CompoundTaskEditorPage.dart`) includes its own student picker rather
/// than a plain number field; the AI note-driven regenerate/suggest flow
/// (`CompoundGoalRoadmapPage.dart`) sits alongside it unchanged. Neither
/// replaces the other.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'GoalMetrics.dart';
import 'AdminProfile.dart';
import 'StudentScope.dart';
import 'GuideDb.dart';

/// Same region every callable in this project's functions uses.
const String kFunctionsRegion = 'asia-south1';

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------

const String kGuideTargetsCollection = 'guideTargets';
const String kCompoundTargetsSubcollection = 'targets';
const String kCompoundPhasesSubcollection = 'phases';

const String kCompoundStatusActive = 'active';
const String kCompoundStatusCompleted = 'completed';
const String kCompoundStatusAbandoned = 'abandoned';

const String kCompoundPhasePending = 'pending';
const String kCompoundPhaseActive = 'active';
const String kCompoundPhaseAchieved = 'achieved';
const String kCompoundPhaseFailed = 'failed';

/// The only two metrics a compound target may carry — reuses the existing ids
/// from `GoalMetrics.dart` (Rule 1: never invent a parallel metric-id space).
const List<String> kCompoundMetrics = [kMetricChanting, kMetricBooks, kMetricFolk];

/// The metrics this admin may set: the FOLK-residents target is for boys only, so a Female Enabler does not get it.
List<String> compoundMetricsFor(AdminProfile me) => [
      for (final m in kCompoundMetrics)
        if (m != kMetricFolk || me.role != AdminRole.femaleEnabler) m,
    ];

bool validCompoundMetric(String metric) => kCompoundMetrics.contains(metric);

/// The fixed round-ladder every value task's `fromLevel`/`toLevel` is drawn
/// from — mirrors `functions/goals.js`'s own `ROUND_LADDER` byte-for-byte
/// (Rule 1: one definition of "the ladder", not two that could drift).
const List<int> kRoundLadder = [1, 2, 4, 8, 12, 16];

/// This target's effective ladder: every fixed rung below the real goal,
/// plus the goal itself appended (e.g. goal=10 -> [1,2,4,8,10]). Mirrors
/// `functions/goals.js`'s `effectiveLadder`.
List<int> effectiveLadder(int goal) =>
    kRoundLadder.where((v) => v < goal).followedBy([goal]).toList();

/// This student's tier: the highest ladder rung at/below [value], or `0`
/// ("not yet started") if below the lowest rung. Mirrors
/// `functions/goals.js`'s `tierFor` byte-for-byte — used by the manual task
/// editor to pre-fill a value task's student picker with whoever is
/// currently AT that task's `fromLevel`.
int tierFor(int value, List<int> ladder) {
  var tier = 0;
  for (final rung in ladder) {
    if (value >= rung) {
      tier = rung;
    } else {
      break;
    }
  }
  return tier;
}

/// What one student should do about a book during a books task, worked out
/// on the server from their real `booksRead` docs (goals.js
/// `bookPlansForUids`): either a book is already open and wants finishing,
/// or there is none and the next one needs assigning.
///
/// A books task on its own says "move these three from 1 book to 2", which
/// is true but not something a guide can act on. These are the three things
/// he actually has to go and do.
class BookAction {
  /// Finish the book already open.
  static const String finish = 'finish';

  /// No book open — assign the next one.
  static const String start = 'start';

  final String uid;
  final String action;
  final String? bookTitle;

  const BookAction({required this.uid, required this.action, this.bookTitle});

  static BookAction? from(Object? raw) {
    if (raw is! Map) return null;
    final uid = (raw['uid'] ?? '').toString();
    final action = (raw['action'] ?? '').toString();
    if (uid.isEmpty || (action != finish && action != start)) return null;
    final title = raw['bookTitle'];
    return BookAction(
      uid: uid,
      action: action,
      bookTitle: title == null || title.toString().trim().isEmpty
          ? null
          : title.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'action': action,
        'bookTitle': bookTitle,
      };

  /// The line the guide reads: "Ravi: finish Bhagavad Gita by Sunday", or
  /// "Assign the next book to Amit".
  ///
  /// [byDay] is passed only for the phase the guide is on NOW — a deadline
  /// on a phase that has not started yet would be a date nobody agreed to.
  /// It is computed where it is shown rather than stored, because a stored
  /// one goes stale the moment the phase moves.
  String describe(String? name, {String? byDay}) {
    final who = (name == null || name.trim().isEmpty) ? 'A student' : name;
    if (action == start) return 'Assign the next book to $who';
    final title = bookTitle ?? 'their current book';
    return byDay == null
        ? '$who: finish $title'
        : '$who: finish $title by $byDay';
  }
}

/// The day the guide should have the phase he is on now finished by.
///
/// Monday morning's sweep is what judges a phase, so the real deadline is
/// the Sunday before it. Said plainly on the two days where "Sunday" would
/// be a confusing way to describe it.
String phaseDueDayLabel([DateTime? now]) {
  switch ((now ?? DateTime.now()).weekday) {
    case DateTime.sunday:
      return 'today';
    case DateTime.saturday:
      return 'tomorrow';
    default:
      return 'Sunday';
  }
}

/// Task-list model task types — see [CompoundTask].
const String kTaskTypeRoster = 'roster';
const String kTaskTypeValue = 'value';

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

/// One task within a phase — the task-list model's core unit. A roster task
/// grows the group ({fromCount, toCount}); a value task moves ONE real tier
/// of students up ({fromLevel, toLevel, studentUids} — the group is
/// SNAPSHOTTED at generation time, never a live-updating reference).
class CompoundTask {
  final String type; // kTaskTypeRoster | kTaskTypeValue
  final int? fromCount;
  final int? toCount;
  final int? fromLevel;
  final int? toLevel;
  final List<String> studentUids;

  /// True on the tasks of a FOLK-residents target (`folk: true`).
  final bool folk;

  /// Books targets only, and only on plans generated after this existed —
  /// an older plan simply has none and renders exactly as it used to.
  final List<BookAction> bookActions;

  const CompoundTask({
    required this.type,
    this.fromCount,
    this.toCount,
    this.fromLevel,
    this.toLevel,
    this.studentUids = const [],
    this.bookActions = const [],
    this.folk = false,
  });

  bool get isRoster => type == kTaskTypeRoster;

  /// A FOLK-residents task: a roster-style count of boys living in FOLK.
  bool get isFolk => folk;

  static CompoundTask? from(Object? raw) {
    if (raw is! Map) return null;
    final type = (raw['type'] ?? '').toString();
    if (type != kTaskTypeRoster && type != kTaskTypeValue) return null;
    final uidsRaw = raw['studentUids'];
    final actionsRaw = raw['bookActions'];
    return CompoundTask(
      type: type,
      fromCount: (raw['fromCount'] as num?)?.toInt(),
      toCount: (raw['toCount'] as num?)?.toInt(),
      fromLevel: (raw['fromLevel'] as num?)?.toInt(),
      toLevel: (raw['toLevel'] as num?)?.toInt(),
      studentUids: uidsRaw is List
          ? uidsRaw.map((e) => e.toString()).toList()
          : const [],
      bookActions: actionsRaw is List
          ? actionsRaw.map(BookAction.from).whereType<BookAction>().toList()
          : const [],
      folk: raw['folk'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        if (fromCount != null) 'fromCount': fromCount,
        if (toCount != null) 'toCount': toCount,
        if (fromLevel != null) 'fromLevel': fromLevel,
        if (toLevel != null) 'toLevel': toLevel,
        if (folk) 'folk': true,
        if (type == kTaskTypeValue) 'studentUids': studentUids,
        if (bookActions.isNotEmpty)
          'bookActions': bookActions.map((a) => a.toMap()).toList(),
      };

  /// One human-readable checklist line, e.g. "Bring roster from 6 to 8
  /// students" or, for a value task, the real students it applies to by
  /// name — e.g. "Move Ravi and Om from 2 to 4 rounds".
  ///
  /// [uidToName] is a batched uid -> name lookup the caller resolves ONCE
  /// per screen render via [resolveStudentNames] — never queried per task
  /// or per call here, since this method stays synchronous and pure.
  /// Omitting it (or an empty [studentUids]) falls back to the original
  /// bare-count wording, so any call site that hasn't been updated yet
  /// keeps working exactly as before (Rule 3).
  ///
  /// A uid missing from [uidToName] — a deleted account, or a user doc
  /// with no `name` — becomes "a student" for that one entry rather than
  /// being silently dropped: the number of students the task actually
  /// applies to must never look smaller than it really is just because a
  /// name couldn't be found.
  ///
  /// A roster task never reaches the name-list branch at all — it has no
  /// `studentUids` (those students don't exist yet, see [isRoster]) — so
  /// it stays exactly as generic as before, unaffected by this change.
  String describe(String unit, [Map<String, String>? uidToName]) {
    if (isRoster && isFolk) {
      return 'Bring the boys living in FOLK from ${fromCount ?? 0} to ${toCount ?? 0}';
    }
    if (isRoster) {
      return 'Bring roster from ${fromCount ?? 0} to ${toCount ?? 0} students';
    }
    if (uidToName == null || studentUids.isEmpty) {
      return 'Move ${studentUids.length} student(s) from ${fromLevel ?? 0} '
          'to ${toLevel ?? 0} $unit';
    }

    final names = studentUids.map((uid) => uidToName[uid] ?? 'a student').toList();
    return 'Move ${_joinNamesCapped(names)} from ${fromLevel ?? 0} '
        'to ${toLevel ?? 0} $unit';
  }

  /// Joins names for a checklist line, capped so a task with many students
  /// never produces an unreadable wall of names on a cramped board card —
  /// at most [_maxNamesShown] spelled out, then "and N more".
  static const int _maxNamesShown = 3;

  static String _joinNamesCapped(List<String> names) {
    if (names.isEmpty) return 'no students';
    if (names.length <= _maxNamesShown) return _joinNames(names);
    final shown = names.take(_maxNamesShown).toList();
    final remaining = names.length - _maxNamesShown;
    return '${_joinNames(shown)} and $remaining more';
  }

  static String _joinNames(List<String> names) {
    if (names.length == 1) return names[0];
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    return '${names.sublist(0, names.length - 1).join(", ")} and ${names.last}';
  }
}

/// Every studentUid referenced by any VALUE task in [tasks] — a roster
/// task contributes none (see [CompoundTask.isRoster]). Used to batch-
/// resolve names ONCE per screen render (one phase's tasks, or an entire
/// plan's, depending on the caller) rather than once per task.
Set<String> collectStudentUids(Iterable<CompoundTask> tasks) {
  final uids = <String>{};
  for (final t in tasks) {
    if (!t.isRoster) uids.addAll(t.studentUids);
  }
  return uids;
}

/// Batched uid -> name lookup (Rule 1 — one shared resolver for every
/// screen that renders a value task's real students, not a query per task
/// or per screen). Mirrors `goals.js`'s own `realValuesForUids` — one
/// parallel `.get()` per uid, no `whereIn` chunking needed at this
/// project's real roster scale.
///
/// A uid with no `users` doc, or a doc with an empty `name` (a deleted
/// account), is simply absent from the returned map — [CompoundTask.describe]
/// falls back to "a student" for it, never crashes, and never silently
/// shrinks the displayed count.
Future<Map<String, String>> resolveStudentNames(Set<String> uids) async {
  if (uids.isEmpty) return {};

  final snaps = await Future.wait(
    uids.map((uid) => GuideDb.instance.collection('users').doc(uid).get()),
  );

  final map = <String, String>{};
  for (final snap in snaps) {
    final name = (snap.data()?['name'] ?? '').toString().trim();
    if (name.isNotEmpty) map[snap.id] = name;
  }
  return map;
}

class CompoundProposal {
  final String proposedBy;

  /// Each entry: {tasks: [...]} — see [CompoundTask].
  final List<Map<String, dynamic>> proposedPhases;
  final DateTime? proposedAt;
  final String note;

  const CompoundProposal({
    required this.proposedBy,
    required this.proposedPhases,
    required this.proposedAt,
    required this.note,
  });

  static CompoundProposal? from(Object? raw) {
    if (raw is! Map) return null;
    final phasesRaw = raw['proposedPhases'];
    final at = raw['proposedAt'];
    return CompoundProposal(
      proposedBy: (raw['proposedBy'] ?? '').toString(),
      proposedPhases: phasesRaw is List
          ? phasesRaw
              .whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList()
          : const [],
      proposedAt: at is Timestamp ? at.toDate() : null,
      note: (raw['note'] ?? '').toString(),
    );
  }

  /// Parsed tasks for proposed phase index [i] (0-based) — used by the
  /// pending-proposal banner's preview.
  List<CompoundTask> tasksFor(int i) {
    if (i < 0 || i >= proposedPhases.length) return const [];
    final tasksRaw = proposedPhases[i]['tasks'];
    return tasksRaw is List
        ? tasksRaw.map(CompoundTask.from).whereType<CompoundTask>().toList()
        : const [];
  }
}

class CompoundTarget {
  final String guideId;
  final String targetId;
  final String metric;
  final int studentCountGoal;
  final int perStudentValueGoal;
  final DateTime? endDate;
  final String status;
  final int currentPhase;
  final int totalPhases;
  final DateTime? createdAt;
  final CompoundProposal? pendingProposal;

  const CompoundTarget({
    required this.guideId,
    required this.targetId,
    required this.metric,
    required this.studentCountGoal,
    required this.perStudentValueGoal,
    required this.endDate,
    required this.status,
    required this.currentPhase,
    required this.totalPhases,
    required this.createdAt,
    required this.pendingProposal,
  });

  static CompoundTarget from(
      String guideId, String targetId, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    final end = d['endDate'];
    final created = d['createdAt'];
    return CompoundTarget(
      guideId: guideId,
      targetId: targetId,
      metric: (d['metric'] ?? '').toString(),
      studentCountGoal: (d['studentCountGoal'] as num?)?.toInt() ?? 0,
      perStudentValueGoal: (d['perStudentValueGoal'] as num?)?.toInt() ?? 0,
      endDate: end is Timestamp ? end.toDate() : null,
      status: (d['status'] ?? '').toString(),
      currentPhase: (d['currentPhase'] as num?)?.toInt() ?? 1,
      totalPhases: (d['totalPhases'] as num?)?.toInt() ?? 0,
      createdAt: created is Timestamp ? created.toDate() : null,
      pendingProposal: CompoundProposal.from(d['pendingProposal']),
    );
  }

  bool get isActive => status == kCompoundStatusActive;
  GoalMetric? get metricInfo => goalMetricById(metric);
}

/// One task's outcome within a `weeklyHistory` entry — same order as the
/// phase's own `tasks` at the time of that evaluation.
class TaskResult {
  final bool complete;
  final int actual;

  const TaskResult({required this.complete, required this.actual});

  static TaskResult from(Map<String, dynamic> m) => TaskResult(
        complete: m['complete'] == true,
        actual: (m['actual'] as num?)?.toInt() ?? 0,
      );
}

class CompoundWeeklyResult {
  final DateTime? weekOf;
  final bool passed;
  final List<TaskResult> taskResults;
  final bool aheadOfSchedule;

  const CompoundWeeklyResult({
    required this.weekOf,
    required this.passed,
    required this.taskResults,
    required this.aheadOfSchedule,
  });

  static CompoundWeeklyResult from(Map<String, dynamic> m) {
    final w = m['weekOf'];
    final a = m['actuals'];
    final resultsRaw = a is Map ? a['taskResults'] : null;
    return CompoundWeeklyResult(
      weekOf: w is Timestamp ? w.toDate() : null,
      passed: m['result'] == true || m['result'] == 'pass',
      taskResults: resultsRaw is List
          ? resultsRaw
              .whereType<Map>()
              .map((m2) => TaskResult.from(m2.cast<String, dynamic>()))
              .toList()
          : const [],
      aheadOfSchedule: a is Map && a['aheadOfSchedule'] == true,
    );
  }
}

class CompoundPhase {
  final int phaseNumber;
  final List<CompoundTask> tasks;
  final String status;
  final DateTime? startedAt;
  final List<CompoundWeeklyResult> weeklyHistory;

  const CompoundPhase({
    required this.phaseNumber,
    required this.tasks,
    required this.status,
    required this.startedAt,
    required this.weeklyHistory,
  });

  static CompoundPhase from(String id, Map<String, dynamic> data) {
    final hist = data['weeklyHistory'];
    final started = data['startedAt'];
    final tasksRaw = data['tasks'];
    return CompoundPhase(
      phaseNumber: (data['phaseNumber'] as num?)?.toInt() ?? int.tryParse(id) ?? 0,
      tasks: tasksRaw is List
          ? tasksRaw.map(CompoundTask.from).whereType<CompoundTask>().toList()
          : const [],
      status: (data['status'] ?? kCompoundPhasePending).toString(),
      startedAt: started is Timestamp ? started.toDate() : null,
      weeklyHistory: hist is List
          ? hist
              .whereType<Map>()
              .map((m) => CompoundWeeklyResult.from(m.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }

  /// The most recent weekly result, or null if never evaluated — rendered as
  /// "awaiting Monday's check", never as 0 (same discipline as the old
  /// system's `GoalPhase.latestWeek`).
  CompoundWeeklyResult? get latestWeek {
    if (weeklyHistory.isEmpty) return null;
    final sorted = List<CompoundWeeklyResult>.from(weeklyHistory)
      ..sort((a, b) {
        if (a.weekOf == null) return 1;
        if (b.weekOf == null) return -1;
        return a.weekOf!.compareTo(b.weekOf!);
      });
    return sorted.last;
  }
}

// -----------------------------------------------------------------------------
// References and reads
// -----------------------------------------------------------------------------

CollectionReference<Map<String, dynamic>> compoundTargetsRef(String guideId) =>
    GuideDb.instance
        .collection(kGuideTargetsCollection)
        .doc(guideId)
        .collection(kCompoundTargetsSubcollection);

DocumentReference<Map<String, dynamic>> compoundTargetRef(
        String guideId, String targetId) =>
    compoundTargetsRef(guideId).doc(targetId);

CollectionReference<Map<String, dynamic>> compoundPhasesRef(
        String guideId, String targetId) =>
    compoundTargetRef(guideId, targetId).collection(kCompoundPhasesSubcollection);

Stream<List<CompoundTarget>> compoundTargetsStream(String guideId) =>
    compoundTargetsRef(guideId).snapshots().map((snap) => snap.docs
        .map((d) => CompoundTarget.from(guideId, d.id, d.data()))
        .toList());

Stream<CompoundTarget?> compoundTargetStream(String guideId, String targetId) =>
    compoundTargetRef(guideId, targetId)
        .snapshots()
        .map((s) => s.exists ? CompoundTarget.from(guideId, targetId, s.data()) : null);

Stream<List<CompoundPhase>> compoundPhasesStream(String guideId, String targetId) =>
    compoundPhasesRef(guideId, targetId).snapshots().map((snap) {
      final list =
          snap.docs.map((d) => CompoundPhase.from(d.id, d.data())).toList();
      list.sort((a, b) => a.phaseNumber.compareTo(b.phaseNumber));
      return list;
    });

/// Whole weeks from now until [endDate], floored at 1 — byte-for-byte the same
/// rule as `GoalQueries.dart`'s `weeksRemaining`, duplicated rather than
/// imported cross-file since the two systems are deliberately independent
/// (Rule 3: the old file is untouched, including not adding a new export to
/// it for this file to consume).
int compoundWeeksRemaining(DateTime endDate, {DateTime? from}) {
  final start = from ?? DateTime.now();
  final days = endDate.difference(start).inDays;
  if (days <= 0) return 1;
  final weeks = (days / 7).floor();
  return weeks < 1 ? 1 : weeks;
}

// -----------------------------------------------------------------------------
// Writes — target lifecycle
// -----------------------------------------------------------------------------

/// Creates the SHELL of a new compound target — its four goal fields only,
/// zero phases yet. `currentPhase`/`totalPhases` are both `0`, a sentinel
/// the UI reads as "plan not generated yet" (distinct from a real 1-phase
/// plan, which is `currentPhase: 1`).
///
/// ---------------------------------------------------------------------------
/// RULE 12 JUSTIFICATION — `guideTargets/{guideId}/targets` (first write site)
/// ---------------------------------------------------------------------------
/// A new subcollection, not a new top-level collection: it lives beside the
/// existing per-guide `guideTargets/{guideId}` document deliberately, so both
/// systems remain discoverable under the same guide-scoped root while never
/// sharing a single field or subcollection. See this file's own header for
/// why the OLD document's `perMetricTargets`-sum shape cannot represent a
/// compound "N students at value V" target at all.
///
/// The caller (`CompoundGoalSetup.dart`) calls
/// [callGenerateCompoundPlan] with the returned `targetId` immediately after
/// this — the actual phase plan is generated AND written server-side (the
/// only place the real per-student standing data and the OpenAI call belong;
/// see `functions/goals.js`'s `generateCompoundPlan`).
/// A guide already has an active target of this metric.
///
/// Thrown rather than returned so no caller can create a second one by
/// ignoring a boolean. [message] is written for the guide and shown as it is.
class CompoundTargetLimitException implements Exception {
  const CompoundTargetLimitException(this.metric, this.message);
  final String metric;
  final String message;
  @override
  String toString() => message;
}

/// The guide's ACTIVE target of [metric], if they have one.
///
/// "Active" is the only status that blocks a new target: a completed or
/// abandoned one is history, and a guide must be able to start again.
Future<CompoundTarget?> activeTargetOfMetric(
    String guideId, String metric) async {
  final snap = await compoundTargetsRef(guideId)
      .where('metric', isEqualTo: metric)
      .where('status', isEqualTo: kCompoundStatusActive)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return null;
  final doc = snap.docs.first;
  return CompoundTarget.from(guideId, doc.id, doc.data());
}

/// The sentence a guide sees when they already have one.
String targetLimitMessage(String metric) => switch (metric) {
      'books' => 'Delete your current book reading target first',
      'folk' => 'Delete your current FOLK-residents target first',
      _ => 'Delete your current chanting target first',
    };

Future<String> createCompoundTargetShell({
  required String guideId,
  required String metric,
  required int studentCountGoal,
  required int perStudentValueGoal,
  required DateTime endDate,
}) async {
  if (!validCompoundMetric(metric)) {
    throw ArgumentError('Compound targets support only chanting, books or FOLK residents.');
  }

  // ONE active target per metric (Master 1, A1). Checked here rather than
  // only in the screen, so every path to a new target goes past it — the
  // setup page, a retry after a failed plan, or anything added later.
  final existing = await activeTargetOfMetric(guideId, metric);
  if (existing != null) {
    throw CompoundTargetLimitException(metric, targetLimitMessage(metric));
  }

  final targetDoc = compoundTargetsRef(guideId).doc();
  await targetDoc.set({
    'metric': metric,
    'studentCountGoal': studentCountGoal,
    'perStudentValueGoal': perStudentValueGoal,
    'endDate': Timestamp.fromDate(endDate),
    'status': kCompoundStatusActive,
    'currentPhase': 0,
    'totalPhases': 0,
    'createdAt': FieldValue.serverTimestamp(),
    'pendingProposal': null,
  });
  return targetDoc.id;
}

Future<void> abandonCompoundTarget(String guideId, String targetId) =>
    compoundTargetRef(guideId, targetId).update({'status': kCompoundStatusAbandoned});

/// Why a delete (or an abandon) failed, in words a guide can act on — and
/// never a generic "could not do that just now".
///
/// A generic line is worse than useless here: it reads as "the delete is
/// broken" when the usual cause is the callable being unreachable, which is a
/// different problem with a different fix. So the code is always shown, with a
/// plain sentence for the ones that mean something specific:
///
///   unavailable / internal / deadline-exceeded  the function did not answer
///   unauthenticated                             the sign-in lapsed
///   permission-denied                           not ours, or the door is shut
///   not-found                                   already gone
String deleteFailureMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    final plain = switch (error.code) {
      'unavailable' || 'internal' || 'deadline-exceeded' =>
        'The server did not answer',
      'unauthenticated' => 'Your sign-in has lapsed — sign in again',
      'permission-denied' =>
        'Refused — either the target is not yours, or the app is shut out '
            'of this function',
      'not-found' => 'That target no longer exists',
      _ => null,
    };
    final detail = (error.message ?? '').trim();
    return plain != null
        ? '$plain (${error.code})'
        : 'Delete failed: ${error.code}'
            '${detail.isEmpty ? '' : ' — $detail'}';
  }
  if (error is FirebaseException) {
    final detail = (error.message ?? '').trim();
    return 'Delete failed: ${error.code}'
        '${detail.isEmpty ? '' : ' — $detail'}';
  }
  return 'Delete failed: $error';
}

/// Deletes a target and its phases for good, through
/// `functions/goals.js`'s `deleteCompoundTarget`.
///
/// A callable rather than a client delete because the phases are a
/// subcollection — deleting the target document alone would leave them
/// orphaned — and because who may delete one is the server's decision
/// (`requireGoalAccess`: the target's own guide, or a HOD).
///
/// Returns how many phase documents went with it, for the confirmation.
Future<int> callDeleteCompoundTarget({
  required String guideId,
  required String targetId,
}) async {
  final result = await FirebaseFunctions.instanceFor(region: kFunctionsRegion)
      .httpsCallable('deleteCompoundTarget')
      .call<Map<String, dynamic>>({'guideId': guideId, 'targetId': targetId});
  final n = result.data['phasesDeleted'];
  return n is num ? n.toInt() : 0;
}

/// Calls `functions/goals.js`'s `generateCompoundPlan` callable — the ONLY
/// place the real AI call happens (server-side, per `PhasePlanService.dart`'s
/// own stated preference: a client-side key ships inside the APK, and the
/// evaluator is server-side anyway). Reads the target's already-stored
/// fields, computes real roster/standing data, generates and WRITES the
/// phases subcollection, and bumps `currentPhase`/`totalPhases` off their
/// `0` "not generated yet" sentinel — all inside the one function call.
///
/// Throws `FirebaseFunctionsException` on failure (bad OpenAI response after
/// retries, missing target, etc.) — the caller shows this verbatim, matching
/// how `RduaFriendsScreen.dart` already surfaces callable errors.
Future<int> callGenerateCompoundPlan({
  required String guideId,
  required String targetId,
}) async {
  final result = await FirebaseFunctions.instanceFor(region: kFunctionsRegion)
      .httpsCallable('generateCompoundPlan')
      .call<Map<String, dynamic>>({'guideId': guideId, 'targetId': targetId});
  final phaseCount = result.data['phaseCount'];
  return phaseCount is num ? phaseCount.toInt() : 0;
}

/// GUIDE-triggered regeneration — calls `functions/goals.js`'s
/// `regenerateCompoundPlan`, which writes DIRECTLY to the live `phases`
/// from the CURRENT phase forward, preserving every already-achieved phase
/// untouched (see that function's own header). No approval step — this IS
/// the guide's own direct-edit path under the task-list model. Used by both
/// the roadmap view's free-text suggestion box and the automatic
/// regeneration that follows an end-date change.
///
/// [note] is optional — an empty/omitted note still regenerates from
/// today's real numbers, just without extra human guidance for the model.
Future<int> callRegenerateCompoundPlan({
  required String guideId,
  required String targetId,
  String? note,
}) async {
  final result = await FirebaseFunctions.instanceFor(region: kFunctionsRegion)
      .httpsCallable('regenerateCompoundPlan')
      .call<Map<String, dynamic>>({
    'guideId': guideId,
    'targetId': targetId,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
  });
  final phaseCount = result.data['phaseCount'];
  return phaseCount is num ? phaseCount.toInt() : 0;
}

/// HOD-triggered regeneration — calls `functions/goals.js`'s
/// `suggestCompoundPlan`, which writes the AI's output into
/// `pendingProposal` (never `phases/**` directly — see that function's own
/// header for the exact contract it preserves with [approveProposal]). One
/// of TWO ways `pendingProposal` gets written — [proposeManualPhaseEdit]
/// below is the other, hand-typed one; both are equally available to the
/// HOD (restored manual-editing task). `functions/goals.js`'s
/// `onCompoundProposalWritten` trigger fires on either write to notify the
/// guide.
Future<void> callSuggestCompoundPlan({
  required String guideId,
  required String targetId,
  required String hodUid,
  String? note,
}) async {
  await FirebaseFunctions.instanceFor(region: kFunctionsRegion)
      .httpsCallable('suggestCompoundPlan')
      .call<Map<String, dynamic>>({
    'guideId': guideId,
    'targetId': targetId,
    'hodUid': hodUid,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
  });
}

/// The guide's own direct edit of the target's end date (Part 4). Writes
/// ONLY `endDate`; the caller is responsible for following this with
/// [callRegenerateCompoundPlan] so the plan actually reflects the new
/// timeframe — this function alone does not trigger regeneration, so the
/// two stay independently callable/testable.
Future<void> updateTargetEndDate({
  required String guideId,
  required String targetId,
  required DateTime endDate,
}) =>
    compoundTargetRef(guideId, targetId)
        .update({'endDate': Timestamp.fromDate(endDate)});

/// Guide-only manual edit — writes the FULL new tasks array straight to the
/// live CURRENT phase (restored manual-editing task, Part 2 item 3). No
/// approval needed — matches the guide's existing no-approval precedent for
/// direct edits (same role [directlyEditPhase] used to have; this is its
/// task-list-shaped replacement, coexisting with — not replacing —
/// [callRegenerateCompoundPlan]'s AI note-driven path).
///
/// ⚠️ CURRENT phase only, by design (Part 2's explicit restriction): editing
/// a future not-yet-active phase would be pointless under this feature's
/// live-rebucketing model — that phase gets re-bucketed from real, current
/// data the moment it actually activates (see `advanceCompoundTarget` in
/// `functions/goals.js`), so any manually-typed `studentUids` snapshot for
/// it would already be stale by the time it mattered.
Future<void> directlyEditPhaseTasks({
  required String guideId,
  required String targetId,
  required int phaseNumber,
  required List<CompoundTask> tasks,
}) =>
    compoundPhasesRef(guideId, targetId).doc('$phaseNumber').update({
      'tasks': tasks.map((t) => t.toMap()).toList(),
    });

/// HOD-only manual edit — proposes a change to ONLY the CURRENT phase's
/// tasks (same Part 2 restriction as [directlyEditPhaseTasks] above). Writes
/// the FULL `1..totalPhases` `proposedPhases` sequence into
/// `pendingProposal` — the contract [approveProposal] already assumes
/// (`proposedPhases[0]` == phase 1) — by reading every OTHER phase's
/// CURRENT tasks fresh and carrying them through byte-for-byte unchanged.
/// This mirrors the exact "achieved phases prepended unchanged" pattern
/// `functions/goals.js`'s `suggestCompoundPlan` already uses server-side,
/// now applied to a hand-typed edit instead of an AI-generated one. Never
/// touches `phases/**` directly — only reads it, to build the unchanged
/// slots — same write-surface rule every other HOD-facing write in this
/// file follows.
Future<void> proposeManualPhaseEdit({
  required String guideId,
  required String targetId,
  required String hodUid,
  required int currentPhaseNumber,
  required int totalPhases,
  required List<CompoundTask> editedTasks,
  required String note,
}) async {
  final phasesRef = compoundPhasesRef(guideId, targetId);
  final proposedPhases = <Map<String, dynamic>>[];

  for (var n = 1; n <= totalPhases; n++) {
    if (n == currentPhaseNumber) {
      proposedPhases.add({'tasks': editedTasks.map((t) => t.toMap()).toList()});
      continue;
    }
    final snap = await phasesRef.doc('$n').get();
    final tasksRaw = snap.data()?['tasks'];
    proposedPhases.add({'tasks': tasksRaw is List ? tasksRaw : const []});
  }

  await compoundTargetRef(guideId, targetId).update({
    'pendingProposal': {
      'proposedBy': hodUid,
      'proposedPhases': proposedPhases,
      'proposedAt': FieldValue.serverTimestamp(),
      'note': note,
    },
  });
}

// -----------------------------------------------------------------------------
// Writes — HOD propose / guide approve
// -----------------------------------------------------------------------------

/// Guide-only. Replaces each phase's `tasks` with the proposal's —
/// deliberately preserving each phase's own `status`/`startedAt`/
/// `weeklyHistory` (a proposal revises tasks on an ongoing plan; it is not
/// "start the plan over", which would discard real elapsed history). Extra
/// trailing phases beyond the proposal's length are removed only if they were
/// never started (`pending`) — a phase already active/achieved/failed is
/// never deleted, since that would erase real history regardless of what the
/// proposal's length implies.
Future<void> approveProposal({
  required String guideId,
  required String targetId,
}) async {
  final db = GuideDb.instance;
  final targetRef = compoundTargetRef(guideId, targetId);
  final phasesRef = compoundPhasesRef(guideId, targetId);

  await db.runTransaction((tx) async {
    final snap = await tx.get(targetRef);
    if (!snap.exists) return;
    final proposal = CompoundProposal.from(snap.data()?['pendingProposal']);
    if (proposal == null) return;

    final existing = await phasesRef.get();
    final existingByNumber = <int, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in existing.docs) {
      final n = int.tryParse(d.id);
      if (n != null) existingByNumber[n] = d;
    }

    for (var i = 0; i < proposal.proposedPhases.length; i++) {
      final n = i + 1;
      final tasks = proposal.proposedPhases[i]['tasks'] ?? const [];
      final doc = phasesRef.doc('$n');
      if (existingByNumber.containsKey(n)) {
        tx.update(doc, {'tasks': tasks});
      } else {
        tx.set(doc, {
          'phaseNumber': n,
          'tasks': tasks,
          'status': kCompoundPhasePending,
          'startedAt': null,
          'weeklyHistory': <Map<String, dynamic>>[],
        });
      }
    }

    // Trailing phases beyond the new length: remove only if never started.
    for (final entry in existingByNumber.entries) {
      if (entry.key <= proposal.proposedPhases.length) continue;
      final status = (entry.value.data()['status'] ?? '').toString();
      if (status == kCompoundPhasePending) {
        tx.delete(entry.value.reference);
      }
    }

    tx.update(targetRef, {
      'pendingProposal': null,
      'totalPhases': proposal.proposedPhases.length,
    });
  });
}

/// Guide-only. Rejects the proposal — the live plan is untouched.
Future<void> rejectProposal({
  required String guideId,
  required String targetId,
}) =>
    compoundTargetRef(guideId, targetId).update({'pendingProposal': null});

// -----------------------------------------------------------------------------
// Live actuals (Part 7 — progress page)
// -----------------------------------------------------------------------------

/// The students OWNED by [guideId] (`users.guideId == guideId`) — the same
/// roster the server-side goal evaluation uses. Hierarchy: read through the
/// admin's scoped student query ([StudentScope.studentsGet] — never a bare
/// `users` query the security rules cannot prove), then narrowed to the
/// owner's own students in memory. A HOD sees every student, so he can still
/// review any admin's target; everyone else's scope always contains their own
/// students.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _ownedStudents(
    String guideId) async {
  final owners = rosterOwnerIds(guideId);
  final snap = await StudentScope.current().studentsGet();
  return snap.docs
      .where((d) => owners.contains((d.data()['guideId'] ?? '').toString().trim()))
      .toList();
}

/// The admin ids whose students make up [guideId]'s goal roster: a GUIDE's own
/// students PLUS his Male Enablers' students (his team); anyone else has just
/// their own. Mirrors `rosterOwnerIds` in functions/goals.js, which counts the
/// same roster on the server.
Set<String> rosterOwnerIds(String guideId, {AdminProfile? profile}) {
  final p = profile ?? AdminProfileProvider.current;
  final owners = <String>{guideId};
  if (p == null) return owners;
  final owner = p.adminById(guideId);
  if (owner == null || owner.role != AdminRole.guide) return owners;
  for (final a in p.admins) {
    if (a.role == AdminRole.maleEnabler && a.teamGuide == guideId) owners.add(a.id);
  }
  return owners;
}

/// Live roster count — the students this target's owner (and, for a Guide,
/// his Male Enablers) own, read through the scoped student helper (see [_ownedStudents]).
Future<int> liveRosterCount(String guideId) async {
  return (await _ownedStudents(guideId)).length;
}

/// `booksRead` documents of ONE student, constrained so the security rules can
/// prove the read (`constrainForStudent` adds the scope filter from the
/// student's current assignment).
Future<QuerySnapshot<Map<String, dynamic>>> _booksReadFor(
    String uid, StudentRef ref) {
  final q = GuideDb.instance
      .collection('booksRead')
      .where('uid', isEqualTo: uid);
  return StudentScope.current().constrainForStudent(q, ref).get();
}

/// How many of this guide's students have a LIFETIME `booksRead` count
/// (real uid-keyed path only — `booksRead/{uid}_{level}_{bookKey}`, never the
/// legacy `booksRead/{username}/{level}/{autoId}` shape `BooksDetails.dart`
/// still writes) at or above [perStudentValueGoal]. Computed live — books has
/// no time-window concern (it is a lifetime total, exactly like the old
/// system's books metric), so unlike chanting this does not need to wait for
/// Monday's check.
Future<int> liveBooksThresholdCount({
  required String guideId,
  required int perStudentValueGoal,
}) async {
  final users = await _ownedStudents(guideId);

  var qualifying = 0;
  for (final u in users) {
    final br = await _booksReadFor(u.id, StudentRef.fromDoc(u));
    final finished = br.docs.where((d) {
      final end = d.data()['endDate'];
      return end != null && end.toString().trim().isNotEmpty;
    }).length;
    if (finished >= perStudentValueGoal) qualifying++;
  }
  return qualifying;
}

/// How many of this guide's students have SELF-SET a chanting COMMITMENT
/// (`users/{uid}.commitmentRounds`) at or above [perStudentValueGoal].
///
/// ⚠️ Computed live — a real, direct field comparison, not a scan of
/// submitted reports. This replaces the original weekly-only design: the
/// original chanting metric needed the Monday Cloud Function because
/// checking actual reported behaviour meant resolving name-keyed report
/// documents and scanning whole `dates` subcollections (see
/// `GoalMetrics.dart`'s own history note). A commitment is a plain field on
/// `users/{uid}` — exactly as cheap to check live as [liveBooksThresholdCount]
/// above, which is why the two are now symmetric.
Future<int> liveChantingThresholdCount({
  required String guideId,
  required int perStudentValueGoal,
}) async {
  final users = await _ownedStudents(guideId);

  var qualifying = 0;
  for (final u in users) {
    final commitment = u.data()['commitmentRounds'];
    if (commitment is num && commitment > 0 && commitment >= perStudentValueGoal) {
      qualifying++;
    }
  }
  return qualifying;
}

/// Fraction complete, clamped to 1.0. Null when unknown — never rendered as 0
/// (same discipline as `GoalQueries.dart`'s `metricFraction`).
double? compoundFraction({required int? actual, required int target}) {
  if (actual == null) return null;
  if (target <= 0) return null;
  return (actual / target).clamp(0.0, 1.0);
}

// -----------------------------------------------------------------------------
// Per-task live progress (task-list phase model task, Part 6)
// -----------------------------------------------------------------------------

/// Real current value for ONE student — mirrors `functions/goals.js`'s
/// `realValuesForUids`, one uid at a time (a task's own snapshotted group is
/// realistically small, same cost profile as [liveBooksThresholdCount]'s own
/// per-student loop above).
///
/// Hierarchy: [studentDoc] (the student's `users` document, when the caller
/// already holds it) saves a read; either way the `booksRead` query is
/// constrained to the student's scope so the security rules can prove it.
Future<int> liveValueForStudent({
  required String uid,
  required String metric,
  DocumentSnapshot<Map<String, dynamic>>? studentDoc,
}) async {
  final db = GuideDb.instance;
  final snap = studentDoc ?? await db.collection('users').doc(uid).get();
  if (metric == kMetricChanting) {
    final v = snap.data()?['commitmentRounds'];
    return v is num ? v.toInt() : 0;
  }
  final br = await _booksReadFor(uid, StudentRef.fromDoc(snap));
  return br.docs.where((d) {
    final end = d.data()['endDate'];
    return end != null && end.toString().trim().isNotEmpty;
  }).length;
}

/// One roster entry for the manual task editor's student picker: real uid,
/// display name, and real current value for [metric].
class StudentValue {
  final String uid;
  final String name;
  final int value;

  const StudentValue({required this.uid, required this.name, required this.value});
}

/// This guide's REAL current roster, each with their name and real current
/// value for [metric] — used by the manual task editor's student picker
/// (restored manual-editing task, Part 1 item 2).
///
/// ⚠️ Deliberately NOT `PlanningQueries.dart`'s `scopedStudents` — that
/// function scopes by VIEWER identity (the HOD sees every student system-
/// wide). This always wants ONE SPECIFIC guide's roster regardless of who is
/// viewing — the HOD editing guide X's target needs guide X's students, not
/// everyone's — so it uses the same owner-narrowed scoped query
/// [liveRosterCount] uses ([_ownedStudents]), with no special-casing for the
/// HOD (his scope is simply every student).
Future<List<StudentValue>> liveRosterWithValues({
  required String guideId,
  required String metric,
}) async {
  final users = await _ownedStudents(guideId);

  if (metric == kMetricChanting) {
    return users.map((u) {
      final v = u.data()['commitmentRounds'];
      return StudentValue(
        uid: u.id,
        name: (u.data()['name'] ?? 'Unknown').toString(),
        value: v is num ? v.toInt() : 0,
      );
    }).toList();
  }

  final out = <StudentValue>[];
  for (final u in users) {
    final value =
        await liveValueForStudent(uid: u.id, metric: metric, studentDoc: u);
    out.add(StudentValue(
      uid: u.id,
      name: (u.data()['name'] ?? 'Unknown').toString(),
      value: value,
    ));
  }
  return out;
}

/// Live progress for ONE task — roster: real current roster count vs
/// `toCount`; value: how many of the task's OWN snapshotted `studentUids`
/// currently meet `toLevel`, out of that exact group's size. Mirrors
/// `functions/goals.js`'s `evaluatePhaseTasks` per-task logic.
class TaskProgress {
  final int actual;
  final int target;
  final bool complete;

  const TaskProgress({
    required this.actual,
    required this.target,
    required this.complete,
  });
}

Future<TaskProgress> liveTaskProgress({
  required CompoundTask task,
  required String guideId,
  required String metric,
}) async {
  if (task.isRoster) {
    final actual = await liveRosterCount(guideId);
    final target = task.toCount ?? 0;
    return TaskProgress(actual: actual, target: target, complete: actual >= target);
  }
  final uids = task.studentUids;
  if (uids.isEmpty) {
    return const TaskProgress(actual: 0, target: 0, complete: true);
  }
  var reached = 0;
  for (final uid in uids) {
    final v = await liveValueForStudent(uid: uid, metric: metric);
    if (v >= (task.toLevel ?? 0)) reached++;
  }
  return TaskProgress(actual: reached, target: uids.length, complete: reached >= uids.length);
}

/// Live progress for every task in a phase, in the SAME order as
/// `phase.tasks` — one round-trip helper so callers don't have to fan out
/// `liveTaskProgress` themselves.
Future<List<TaskProgress>> livePhaseProgress({
  required List<CompoundTask> tasks,
  required String guideId,
  required String metric,
}) async {
  final out = <TaskProgress>[];
  for (final task in tasks) {
    out.add(await liveTaskProgress(task: task, guideId: guideId, metric: metric));
  }
  return out;
}

/// Live, on-demand re-check of the CURRENT phase against real data right
/// now (Part 5 item 2) — calls `functions/goals.js`'s
/// `checkAndAdvanceIfAheadOfSchedule`. A guide who finishes every task in
/// the current phase early does not have to wait for Monday's sweep: this
/// advances immediately. A no-op (no writes at all) if the phase isn't
/// fully met yet — safe to call on every page load.
Future<bool> callCheckAndAdvanceIfAheadOfSchedule({
  required String guideId,
  required String targetId,
}) async {
  final result = await FirebaseFunctions.instanceFor(region: kFunctionsRegion)
      .httpsCallable('checkAndAdvanceIfAheadOfSchedule')
      .call<Map<String, dynamic>>({'guideId': guideId, 'targetId': targetId});
  return result.data['advanced'] == true;
}
