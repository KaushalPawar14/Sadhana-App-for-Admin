import 'dart:async';

import 'package:folk_guide_app/utils/PlanData.dart';

/// A plan whose documents the test releases by hand (Home listens to the guide's plan for its two plan widgets).
class ManualPlanData extends PlanData {
  final c = StreamController<PlanDoc?>.broadcast();
  final pendingC = StreamController<PendingChanges>.broadcast();
  int listens = 0;

  @override
  Stream<PendingChanges> pending(String adminId) => pendingC.stream;

  @override
  Stream<PlanDoc?> plan(String adminId) {
    listens++;
    return c.stream;
  }

  @override
  DateTime now() => DateTime.utc(2026, 10, 30, 4, 30);
}

/// Wraps another [PlanData] and remembers whose plan was asked for.
class RecordingPlanData extends PlanData {
  RecordingPlanData(this.inner, this.asked);
  final PlanData inner;
  final List<String> asked;

  @override
  Stream<PlanDoc?> plan(String adminId) {
    asked.add(adminId);
    return inner.plan(adminId);
  }

  @override
  Stream<PendingChanges> pending(String adminId) => inner.pending(adminId);

  @override
  DateTime now() => inner.now();
}

/// A plan that is already there.
class FixedPlanData extends PlanData {
  FixedPlanData(this.doc, {this.changes = PendingChanges.none});
  final PlanDoc? doc;
  final PendingChanges changes;

  @override
  Stream<PendingChanges> pending(String adminId) => Stream.value(changes);

  @override
  Stream<PlanDoc?> plan(String adminId) => Stream.value(doc);

  @override
  DateTime now() => DateTime.utc(2026, 10, 30, 4, 30);
}

/// Pending changes as the server's records would give them (the newest is the LAST in [texts]).
PendingChanges pendingOf(List<String> texts) => PendingChanges([
      for (var i = 0; i < texts.length; i++) PendingChange(type: 'interaction', text: texts[i], at: DateTime(2026, 10, 30, 10, i)),
    ].reversed.toList());

/// One interaction in today's batch, [sources] being the sources of its reasons (`sadhana`, `doubts`, `target` ...).
PlanItem interactionItem(String uid, String name, List<String> sources, {bool done = false}) => PlanItem(
      id: 'interaction:$uid:2026-10-28',
      kind: 'interaction',
      title: 'Interaction with $name',
      studentName: name,
      forYou: true,
      done: done,
      reasonSources: sources,
      batchPosition: 1,
    );

/// A Today plan: [today] items, a week's progress (needed · done · left) when [left] is given.
PlanDoc planDoc({List<PlanItem>? today, int? left, int done = 0, String refreshedBy = '', DateTime? refreshedAt, String status = 'upToDate', List<MissingReport> missing = const []}) => PlanDoc(
      todayDate: '2026-10-30',
      todayItems: today ?? const [],
      weekOf: '2026-10-26',
      intro: 'Hare Krishna Gopal!',
      sections: const [],
      generatedAt: DateTime.utc(2026, 10, 30, 4, 10),
      status: status,
      changedAt: DateTime.utc(2026, 10, 30, 4, 10),
      refreshedAt: refreshedAt,
      refreshedBy: refreshedBy,
      batch: const PlanBatch(size: 4, round: 1, members: 4, carried: 0, nextReady: false, done: 0, left: 4),
      missingReports: missing,
      progress: left == null ? null : PlanProgress(needed: left + done, done: done, left: left, summary: 'Interactions needed: ${left + done} · done $done · left $left', bySource: const []),
    );
