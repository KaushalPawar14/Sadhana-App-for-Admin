import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'GuideDb.dart';

/// The Today / This week plans, as the server wrote them (`guidePlans/{adminId}`, worked out by `functions/guidePlans.js`; the app only
/// reads it). Read-only everywhere: a plan changes when its data changes (a tick, a finished item, a new doubt: free and automatic), through the
/// assistant, or when the guide taps Refresh (the AI writes the questions again; also every morning at 6 AM and on Monday morning).

/// One topic of an interaction: the reason it was triggered, and the questions to ask and suggestions to make around it (written by the
/// AI, or the plain version when it could not be reached).
class PlanTopic {
  const PlanTopic({required this.key, required this.label, required this.reason, required this.questions, required this.suggestions, this.conclusions = const [], this.meaning = ''});

  final String key;
  final String label;
  final String reason;
  final List<String> questions;
  final List<String> suggestions;
  final List<String> conclusions;
  final String meaning;

  static List<String> _strings(Object? v) => [
        if (v is List)
          for (final e in v)
            if (e.toString().trim().isNotEmpty) e.toString().trim(),
      ];

  static PlanTopic? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final questions = _strings(raw['questions']);
    if (questions.isEmpty) return null;
    return PlanTopic(
      key: (raw['key'] ?? '').toString(),
      label: (raw['label'] ?? 'Topic').toString(),
      reason: (raw['reason'] ?? '').toString(),
      questions: questions,
      suggestions: _strings(raw['suggestions']),
      conclusions: _strings(raw['conclusions']),
      meaning: (raw['meaning'] ?? '').toString(),
    );
  }
}

/// One topic on a student's ONE card, as a one-line point ("He has asked to meet: answer him"). [group] is the section it belongs to.
class PlanPoint {
  const PlanPoint({required this.text, required this.group, this.kind = '', this.id = '', this.title = '', this.done = false});

  /// This topic is done (the guide reported it to the assistant, or the data finished it): it stays on the card with a line through it.
  final bool done;

  /// "Worry", "Chanting target", "Surrender 40%": the short title; [text] is its ONE line.
  final String title;
  final String text;
  final PlanGroup group;
  final String kind;
  final String id;

  static PlanPoint? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final text = (raw['text'] ?? '').toString();
    if (text.isEmpty) return null;
    return PlanPoint(text: text, group: PlanGroup.parse(raw['group']) ?? PlanGroup.followUp, done: raw['done'] == true, kind: (raw['kind'] ?? '').toString(), id: (raw['id'] ?? '').toString(), title: (raw['title'] ?? '').toString());
  }
}

/// One student's step in a target ("Testing 12 → 16").
class PlanStep {
  const PlanStep({required this.name, required this.from, required this.to, this.done = false});
  final String name;
  final int from;
  final int to;
  final bool done;
}

class PlanItem {
  const PlanItem({
    required this.id,
    required this.kind,
    required this.title,
    this.detail = '',
    this.studentName = '',
    this.forYou = false,
    this.checkWithHim = false,
    this.scheduledFor = '',
    this.done = false,
    this.topics = const [],
    this.percent,
    this.level = '',
    this.briefSource = '',
    this.how = '',
    this.encourage = const [],
    this.reportBack = '',
    this.carriedOver = false,
    this.gender = '',
    this.reasonSources = const [],
    this.batchPosition,
    this.batchRound,
    this.inToday = false,
    this.topicLabels = const [],
    this.studentUid = '',
    this.mode = '',
    this.points = const [],
    this.cardGroups = const [],
    this.steps = const [],
    this.also = '',
  });

  /// "Also: no report since 20 Oct": extra information on his card (a missing report is never an item of its own).
  final String also;

  /// The student this item is about (an interaction, or his one card), and how to meet him (`call` / `inperson`).
  final String studentUid;
  final String mode;

  /// ONE CARD PER STUDENT: every topic about him (a worry, a doubt, his sadhana, a target task, a meeting, a book due ...) as a one-line point,
  /// and the sections ([cardGroups], the most important first) those points belong to.
  final List<PlanPoint> points;
  final List<PlanGroup> cardGroups;

  /// This week's target line: each student's step ("Testing 12 → 16", "Amit 8 → 12"), the done ones ticked.
  final List<PlanStep> steps;

  final String id;
  final String kind;
  final String title;
  final String detail;
  final String studentName;

  /// Only the guide can do it, in person.
  final bool forYou;

  /// A suggestion to make only after asking the student (a Localite).
  final bool checkWithHim;

  /// `yyyy-MM-dd` the week plan set it for, or ''.
  final String scheduledFor;

  /// An interaction the guide has reported back: ticked (it stays in Today for the rest of the day).
  final bool done;

  /// An interaction's topics, each with its questions and suggestions (empty for every other kind of item).
  final List<PlanTopic> topics;

  /// The student's Surrender % and stage, when this is an interaction (the guide's eyes only; the plan is readable by that guide and a HOD).
  final int? percent;
  final String level;

  /// 'ai' (the questions were written by the AI) or 'fallback' (the plain version).
  final String briefSource;

  /// An interaction in today's batch: where and how to meet him, what to encourage, the report-back line, whether it was carried over from an
  /// earlier day, and its place (1, 2 ...) and round in the day's batch.
  final String how;
  final List<String> encourage;
  final String reportBack;
  final bool carriedOver;

  /// The student's gender ("male" / "female", or "" when not recorded): the words about him or her use the right pronouns.
  final String gender;

  /// An interaction's reasons by source (`target`, `sadhana`, `doubts`, `concern`, `surrender` ...): what decides its group on Home.
  final List<String> reasonSources;
  final int? batchPosition;
  final int? batchRound;

  /// In the week's list: this student is in today's batch. [topicLabels] are his topics' names (the questions are in Today).
  final bool inToday;
  final List<String> topicLabels;

  bool get isInteraction => kind == 'interaction';

  /// A student's small card (he has no interaction today, but a meeting, a book due or a doubt): kind `student`.
  bool get isStudentCard => kind == 'student';

  /// Either kind of student card: the interaction (his batch card) and the small one.
  bool get isCard => isInteraction || isStudentCard;

  /// A HOD's summary line for one guide (what is due, who needs attention); it sits BELOW the HOD's own tasks and is never counted as one of them.
  bool get isGuideSummary => kind == 'guideSummary';

  /// Which of Today's three groups this is in: a follow-up (an interaction a student needs), a target task (made by the guide's own targets:
  /// an interaction there only because of a target, or a phase / deadline of one), or any other task. Each item is in exactly one.
  PlanGroup get group => inGroups.first;

  /// Every section this item has something in, the most important first (Worries > Target tasks > Follow-ups > Other). A student's card sits in the
  /// first and is counted in each of them, without being repeated.
  List<PlanGroup> get inGroups {
    if (cardGroups.isNotEmpty) return cardGroups;
    if (kind == 'targetDeadline' || kind == 'phaseTask' || kind == 'targetTask') return const [PlanGroup.target];
    if (isInteraction) {
      final set = <PlanGroup>{
        for (final s in reasonSources) s == 'concern' ? PlanGroup.worry : (s == 'target' ? PlanGroup.target : PlanGroup.followUp),
      };
      if (set.isEmpty) set.add(PlanGroup.followUp);
      return [for (final g in PlanGroup.values) if (set.contains(g)) g];
    }
    return const [PlanGroup.other];
  }

  static PlanItem fromMap(Map<String, dynamic> m) => PlanItem(
        id: (m['id'] ?? '').toString(),
        kind: (m['kind'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        detail: (m['detail'] ?? '').toString(),
        studentName: (m['studentName'] ?? '').toString(),
        forYou: m['forYou'] == true,
        checkWithHim: m['checkWithHim'] == true,
        scheduledFor: (m['scheduledFor'] ?? '').toString(),
        done: m['done'] == true,
        topics: [
          if (m['topics'] is List)
            for (final e in (m['topics'] as List))
              if (PlanTopic.fromMap(e) case final t?) t,
        ],
        percent: m['percent'] is num ? (m['percent'] as num).round() : null,
        level: (m['level'] ?? '').toString(),
        briefSource: (m['briefSource'] ?? '').toString(),
        how: (m['how'] ?? '').toString(),
        encourage: PlanTopic._strings(m['encourage']),
        reportBack: (m['reportBack'] ?? '').toString(),
        carriedOver: m['carriedOver'] == true,
        gender: (m['gender'] ?? '').toString(),
        reasonSources: [
          if (m['reasons'] is List)
            for (final r in (m['reasons'] as List))
              if (r is Map && (r['source'] ?? '').toString().isNotEmpty) r['source'].toString(),
        ],
        batchPosition: m['batch'] is Map && (m['batch'] as Map)['position'] is num ? ((m['batch'] as Map)['position'] as num).round() : null,
        batchRound: m['batch'] is Map && (m['batch'] as Map)['round'] is num ? ((m['batch'] as Map)['round'] as num).round() : null,
        inToday: m['inToday'] == true,
        topicLabels: PlanTopic._strings(m['topicLabels']),
        studentUid: (m['studentUid'] ?? '').toString(),
        mode: (m['mode'] ?? '').toString(),
        points: [
          if (m['points'] is List)
            for (final p in (m['points'] as List))
              if (PlanPoint.fromMap(p) case final x?) x,
        ],
        also: (m['also'] ?? '').toString(),
        steps: [
          if (m['steps'] is List)
            for (final e in (m['steps'] as List))
              if (e is Map) PlanStep(name: (e['name'] ?? '').toString(), from: e['from'] is num ? (e['from'] as num).round() : 0, to: e['to'] is num ? (e['to'] as num).round() : 0, done: e['done'] == true),
        ],
        cardGroups: [
          if (m['groups'] is List)
            for (final g in (m['groups'] as List))
              if (PlanGroup.parse(g) case final x?) x,
        ],
      );
}

/// The three groups of Today's tasks (the Home widget's three counts, and the sections of the Plan page's Today tab).
enum PlanGroup {
  worry,
  target,
  followUp,
  other;

  static PlanGroup? parse(Object? v) => switch (v?.toString()) {
        'worry' => PlanGroup.worry,
        'target' => PlanGroup.target,
        'followUp' => PlanGroup.followUp,
        'other' => PlanGroup.other,
        _ => null,
      };
}

/// How many of Today's tasks are still to do in each group. Done ones (ticked) are not counted: the number goes down as the guide works.
class PlanCounts {
  const PlanCounts({required this.followUps, required this.targets, required this.others, this.worries = 0, this.students = 0, this.cards = 0, this.tasks = 0, this.followUpsAndWorries = 0});

  /// Cards and tasks with a worry OR a follow-up in them: Home's one "Follow-ups" count (a worry is the most urgent follow-up).
  final int followUpsAndWorries;

  /// Cards (students) and tasks with something in each section. A student with topics in several sections is counted in each of them, once.
  /// [followUps] on Home also holds the worries (they are follow-ups with the most urgent first).
  final int worries;
  final int followUps;
  final int targets;
  final int others;

  /// How many students have a card today (topics are counted inside the card, not as more cards).
  final int students;

  /// How many things are to do: students with a card, and tasks that are not about one student.
  int get total => cards + tasks;
  final int cards;
  final int tasks;

  static PlanCounts of(PlanDoc? plan) {
    var w = 0, f = 0, t = 0, o = 0, s = 0, cards = 0, tasks = 0, fw = 0;
    for (final it in plan?.todayItems ?? const <PlanItem>[]) {
      if (it.done || it.isGuideSummary) continue;
      final groups = it.inGroups;
      if (it.isCard) {
        s++;
        cards++;
      } else {
        tasks++;
      }
      if (groups.contains(PlanGroup.worry)) w++;
      if (groups.contains(PlanGroup.target)) t++;
      if (groups.contains(PlanGroup.followUp)) f++;
      if (groups.contains(PlanGroup.other)) o++;
      if (groups.contains(PlanGroup.worry) || groups.contains(PlanGroup.followUp)) fw++;
    }
    return PlanCounts(worries: w, followUps: f, targets: t, others: o, students: s, cards: cards, tasks: tasks, followUpsAndWorries: fw);
  }
}

/// Today's batch of students: the guide's number a day, which round of the day it is, how many are done and left. [nextReady]: a refill just
/// added the next batch ("Next 4 ready").
class PlanBatch {
  const PlanBatch({required this.size, required this.round, required this.members, required this.carried, required this.nextReady, required this.done, required this.left});

  final int size;
  final int round;
  final int members;
  final int carried;
  final bool nextReady;
  final int done;
  final int left;

  static int _n(Object? v) => v is num ? v.round() : 0;

  static PlanBatch? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return PlanBatch(size: _n(raw['size']) == 0 ? 4 : _n(raw['size']), round: _n(raw['round']) == 0 ? 1 : _n(raw['round']), members: _n(raw['members']), carried: _n(raw['carried']), nextReady: raw['nextReady'] == true, done: _n(raw['done']), left: _n(raw['left']));
  }
}

/// One source of interactions in the week's picture (targets, sadhana, doubts and concerns, surrender steps).
class PlanSourceProgress {
  const PlanSourceProgress({required this.id, required this.label, required this.needed, required this.done, required this.left});
  final String id;
  final String label;
  final int needed;
  final int done;
  final int left;
}

/// "Interactions needed: 20 · done 4 · left 16", with the same per source.
class PlanProgress {
  const PlanProgress({required this.needed, required this.done, required this.left, required this.summary, required this.bySource});

  final int needed;
  final int done;
  final int left;
  final String summary;
  final List<PlanSourceProgress> bySource;

  /// The four sources of an interaction, all zero: what This week shows while the server has written no counts yet.
  static const List<PlanSourceProgress> emptySources = [
    PlanSourceProgress(id: 'target', label: 'Targets', needed: 0, done: 0, left: 0),
    PlanSourceProgress(id: 'sadhana', label: 'Sadhana', needed: 0, done: 0, left: 0),
    PlanSourceProgress(id: 'doubts', label: 'Doubts and concerns', needed: 0, done: 0, left: 0),
    PlanSourceProgress(id: 'surrender', label: 'Surrender steps', needed: 0, done: 0, left: 0),
  ];

  static const PlanProgress empty = PlanProgress(needed: 0, done: 0, left: 0, summary: 'Interactions needed: 0 · done 0 · left 0', bySource: emptySources);

  static int _n(Object? v) => v is num ? v.round() : 0;

  static PlanProgress? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return PlanProgress(
      needed: _n(raw['needed']),
      done: _n(raw['done']),
      left: _n(raw['left']),
      summary: (raw['summary'] ?? '').toString(),
      bySource: [
        if (raw['bySource'] is List)
          for (final s in raw['bySource'] as List)
            if (s is Map) PlanSourceProgress(id: (s['id'] ?? '').toString(), label: (s['label'] ?? '').toString(), needed: _n(s['needed']), done: _n(s['done']), left: _n(s['left'])),
      ],
    );
  }
}

class PlanSection {
  const PlanSection({required this.id, required this.title, required this.items});
  final String id;
  final String title;
  final List<PlanItem> items;
}

/// Where the plan stands: `upToDate`, or `updating` (an AI run is writing it: the guide's Refresh, the 6 AM run). [refreshedAt] / [refreshedBy]
/// say when and by what the AI last rewrote it (`refresh`, `daily`, `weekly`); the free updates in between do not change them.
/// One student in the Plan's MISSING REPORTS tab: no daily report for 5 or more days (or never). Not an interaction.
class MissingReport {
  const MissingReport({required this.studentUid, required this.studentName, required this.label, this.days, this.reason = '', this.gender = ''});

  final String studentUid;
  final String studentName;

  /// "No report for 8 days" / "Never reported".
  final String label;
  final int? days;

  /// What he told the guide (as the guide told the assistant); '' when nothing was said.
  final String reason;
  final String gender;

  static MissingReport? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final uid = (raw['studentUid'] ?? '').toString();
    if (uid.isEmpty) return null;
    return MissingReport(
      studentUid: uid,
      studentName: (raw['studentName'] ?? '').toString(),
      label: (raw['label'] ?? '').toString(),
      days: raw['days'] is num ? (raw['days'] as num).round() : null,
      reason: (raw['reason'] ?? '').toString(),
      gender: (raw['gender'] ?? '').toString(),
    );
  }
}

class PlanDoc {
  const PlanDoc({
    required this.todayDate,
    required this.todayItems,
    required this.weekOf,
    required this.intro,
    required this.sections,
    required this.generatedAt,
    required this.status,
    required this.changedAt,
    this.refreshedAt,
    this.refreshedBy = '',
    this.batch,
    this.progress,
    this.missingReports = const [],
  });

  final String todayDate;
  final List<PlanItem> todayItems;
  final String weekOf;
  final String intro;
  final List<PlanSection> sections;
  final DateTime? generatedAt;
  final String status;
  final DateTime? changedAt;
  final DateTime? refreshedAt;
  final String refreshedBy;

  /// Today's batch (null for a HOD's plan, which has none) and the week's progress.
  final PlanBatch? batch;
  final PlanProgress? progress;

  /// The students in the Missing reports tab (the server works them out; the ones the guide ignores are not in it).
  final List<MissingReport> missingReports;

  static DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;

  static List<PlanItem> _items(Object? raw) => [
        if (raw is List)
          for (final e in raw)
            if (e is Map) PlanItem.fromMap(Map<String, dynamic>.from(e)),
      ];

  static PlanDoc fromMap(Map<String, dynamic> d) {
    final today = d['today'] is Map ? Map<String, dynamic>.from(d['today'] as Map) : const <String, dynamic>{};
    final week = d['week'] is Map ? Map<String, dynamic>.from(d['week'] as Map) : const <String, dynamic>{};
    return PlanDoc(
      todayDate: (today['date'] ?? '').toString(),
      todayItems: _items(today['items']),
      weekOf: (week['weekOf'] ?? '').toString(),
      intro: (week['intro'] ?? '').toString(),
      sections: [
        if (week['sections'] is List)
          for (final s in week['sections'] as List)
            if (s is Map) PlanSection(id: (s['id'] ?? '').toString(), title: (s['title'] ?? '').toString(), items: _items(s['items'])),
      ],
      generatedAt: _ts(d['generatedAt']),
      status: (d['status'] ?? 'upToDate').toString(),
      changedAt: _ts(d['changedAt']),
      refreshedAt: _ts(d['refreshedAt']),
      refreshedBy: (d['refreshedBy'] ?? '').toString(),
      batch: PlanBatch.fromMap(today['batch']),
      progress: PlanProgress.fromMap(week['progress']),
      missingReports: [
        if (d['missingReports'] is Map && (d['missingReports'] as Map)['items'] is List)
          for (final e in (d['missingReports'] as Map)['items'] as List)
            if (MissingReport.fromMap(e) != null) MissingReport.fromMap(e)!,
      ],
    );
  }
}

/// One change since the guide's last plan refresh that the AI has not considered yet ("interaction with Ravi").
class PendingChange {
  const PendingChange({required this.type, required this.text, this.at});

  final String type;
  final String text;
  final DateTime? at;
}

/// What is pending for one guide (`planChanges/{adminId}/items`, written by the server for THAT guide's own students, cleared when the AI
/// rewrites his plan): the number on the Refresh badge, and the list a tap shows.
class PendingChanges {
  const PendingChanges(this.items);

  static const PendingChanges none = PendingChanges([]);

  final List<PendingChange> items;
  int get count => items.length;

  /// "2 changes: interaction with Ravi; interaction with Amit" (the newest first).
  String get summary => count == 0 ? '' : '$count change${count == 1 ? '' : 's'}: ${items.map((c) => c.text).join('; ')}';

  static PendingChanges fromDocs(Iterable<Map<String, dynamic>> docs) {
    final list = [
      for (final d in docs)
        if ((d['text'] ?? '').toString().isNotEmpty) PendingChange(type: (d['type'] ?? '').toString(), text: (d['text'] ?? '').toString(), at: d['at'] is Timestamp ? (d['at'] as Timestamp).toDate() : null),
    ]..sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
    return PendingChanges(list);
  }
}

/// What the Plan page and the dots read, behind one interface (tests hand in a fake).
abstract class PlanData {
  const PlanData();

  static PlanData instance = const FirestorePlanData();

  /// The admin's plan, live; null until the server has written one.
  Stream<PlanDoc?> plan(String adminId);

  /// The changes since the admin's last plan refresh that the AI has not considered yet, live (no AI cost: counted by the server as they happen).
  Stream<PendingChanges> pending(String adminId) => Stream.value(PendingChanges.none);

  /// What is open about one student (the lines of his reasons): shown when a name in This week is tapped and he has no card in Today.
  Future<List<String>> needsOf(String studentUid) async => const [];

  /// The moment the admin last looked at the plan page.
  DateTime now() => DateTime.now();
}

class FirestorePlanData extends PlanData {
  const FirestorePlanData();

  @override
  Stream<PlanDoc?> plan(String adminId) => GuideDb.instance.collection('guidePlans').doc(adminId).snapshots().map((s) {
        final d = s.data();
        return s.exists && d != null ? PlanDoc.fromMap(d) : null;
      });

  @override
  Future<List<String>> needsOf(String studentUid) async {
    final snap = await GuideDb.instance.collection('interactionNeeds').doc(studentUid).get();
    final needs = snap.data()?['needs'];
    return [
      if (needs is List)
        for (final n in needs)
          if (n is Map && (n['text'] ?? '').toString().isNotEmpty) n['text'].toString(),
    ];
  }

  @override
  Stream<PendingChanges> pending(String adminId) => GuideDb.instance
      .collection('planChanges')
      .doc(adminId)
      .collection('items')
      .snapshots()
      .map((s) => PendingChanges.fromDocs(s.docs.map((d) => d.data())));
}
