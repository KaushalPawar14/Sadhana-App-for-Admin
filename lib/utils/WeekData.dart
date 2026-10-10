import 'package:cloud_firestore/cloud_firestore.dart';

import 'CalendarQueries.dart';
import 'GoalCompoundQueries.dart';
import 'PlanningQueries.dart';

/// Everything the This Week screen reads, behind one interface: the app uses the
/// Firestore-backed one (a pass-through to the existing query functions, unchanged);
/// a widget test hands in plain values.
abstract class WeekData {
  static WeekData instance = const FirestoreWeekData();

  /// `interactionLogs` scoped to the signed-in admin (follow-ups).
  Stream<QuerySnapshot> interactionLogs();

  /// `associations` scoped to the signed-in admin (overdue meetings).
  Stream<QuerySnapshot> associations();

  /// This guide's compound targets.
  Stream<List<CompoundTarget>> targets(String guideId);

  /// One target's phases.
  Stream<List<CompoundPhase>> phases(String guideId, String targetId);

  /// The calendar events this guide may see.
  Future<List<CalendarEvent>> events(String guideId);

  /// Live progress of each task of a phase.
  Future<List<TaskProgress>> phaseProgress({
    required List<CompoundTask> tasks,
    required String guideId,
    required String metric,
  });

  /// uid -> name for the students a phase's tasks name.
  Future<Map<String, String>> studentNames(Set<String> uids);
}

class FirestoreWeekData implements WeekData {
  const FirestoreWeekData();

  @override
  Stream<QuerySnapshot> interactionLogs() => scopedInteractionLogsStream();

  @override
  Stream<QuerySnapshot> associations() => scopedAssociationsStream();

  @override
  Stream<List<CompoundTarget>> targets(String guideId) => compoundTargetsStream(guideId);

  @override
  Stream<List<CompoundPhase>> phases(String guideId, String targetId) =>
      compoundPhasesStream(guideId, targetId);

  @override
  Future<List<CalendarEvent>> events(String guideId) => visibleEventsFor(guideId);

  @override
  Future<List<TaskProgress>> phaseProgress({
    required List<CompoundTask> tasks,
    required String guideId,
    required String metric,
  }) =>
      livePhaseProgress(tasks: tasks, guideId: guideId, metric: metric);

  @override
  Future<Map<String, String>> studentNames(Set<String> uids) => resolveStudentNames(uids);
}
