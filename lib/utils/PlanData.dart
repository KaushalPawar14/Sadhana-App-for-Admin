import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'GuideDb.dart';
import 'SeenMarkers.dart';

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

/// One line inside a topic: a point the AI prepared to discuss ([kind] `point`) or a data gap to fill ([kind] `gap_lit` | `gap_interaction` | `gap_attitude` |
/// `gap_reports`; [done] when the data is there now). Only the Surrender check has them.
class PlanSub {
  const PlanSub({required this.id, required this.kind, required this.text, this.done = false});

  final String id;
  final String kind;
  final String text;
  final bool done;

  bool get isGap => kind.startsWith('gap_');

  static PlanSub? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final text = (raw['text'] ?? '').toString();
    if (text.isEmpty) return null;
    return PlanSub(id: (raw['id'] ?? '').toString(), kind: (raw['kind'] ?? 'point').toString(), text: text, done: raw['done'] == true);
  }
}

/// One topic on a student's ONE card, as a one-line point ("He has asked to meet: answer him"). [group] is the section it belongs to.
class PlanPoint {
  const PlanPoint({
    required this.text,
    required this.group,
    this.kind = '',
    this.id = '',
    this.title = '',
    this.done = false,
    this.bookId = '',
    this.assocId = '',
    this.doubtId = '',
    this.metric = '',
    this.sub = const [],
    this.since = '',
    this.carriedOver = false,
    this.late = false,
    this.to,
    this.targetEnd = '',
    this.bookTitle = '',
    this.laterNote = '',
  });

  /// What LATER needs to know about a topic: its step (`to`, "raise to 12 rounds"), the day its target ends (the panel warns when the chosen date is after it), the book's title,
  /// and the note the guide left when he postponed it (shown on the topic when it returns).
  final int? to;
  final String targetEnd;
  final String bookTitle;
  final String laterNote;

  /// A confirmed meeting whose day has PASSED without "Completed" or "Cancelled": it stays in Today every day, with a Completed and a Cancelled button.
  final bool late;

  /// The Surrender check's lines (what to discuss, the gaps to fill), the day it first appeared and whether it has been carried over from an earlier day.
  final List<PlanSub> sub;
  final String since;
  final bool carriedOver;

  /// What the Today button of this topic opens: the book (a book due), the meeting (an association) or the doubt, and a target task's metric
  /// (`chanting` | `books` | `folk`).
  final String bookId;
  final String assocId;
  final String doubtId;
  final String metric;

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
    return PlanPoint(text: text, group: PlanGroup.parse(raw['group']) ?? PlanGroup.followUp, done: raw['done'] == true, kind: (raw['kind'] ?? '').toString(), id: (raw['id'] ?? '').toString(), title: (raw['title'] ?? '').toString(), bookId: (raw['bookId'] ?? '').toString(), assocId: (raw['assocId'] ?? '').toString(), doubtId: (raw['doubtId'] ?? '').toString(), metric: (raw['metric'] ?? '').toString(), since: (raw['since'] ?? '').toString(), carriedOver: raw['carriedOver'] == true, late: raw['late'] == true, to: raw['to'] is num ? (raw['to'] as num).round() : null, targetEnd: (raw['targetEnd'] ?? '').toString(), bookTitle: (raw['bookTitle'] ?? '').toString(), laterNote: (raw['laterNote'] ?? '').toString(), sub: [for (final x in (raw['sub'] as List? ?? const [])) if (PlanSub.fromMap(x) case final y?) y]);
  }
}

/// One student's step in a target ("Testing 12 → 16").
class PlanStep {
  const PlanStep({required this.name, required this.from, required this.to, this.done = false, this.book = '', this.due = '', this.label = ''});

  /// The words the server wrote for a COMBINED step ("Amit — 12 → 16 · invite to FOLK (direct)"); empty for a step of one target.
  final String label;

  /// A book target's step also names the book he is reading ("Testing — 📖 Bhagavad-gita"), the same words as his topic in Today.
  final String book;

  /// The finish-by date of that book (yyyy-MM-dd) while it is still ahead: the student is ON TRACK until then, not someone to contact.
  final String due;

  /// He is reading a book that is due later: on track, nothing to do until the date.
  bool get onTrack => !done && due.isNotEmpty;

  /// "30 Nov" of a yyyy-MM-dd.
  String get dueShort {
    final d = DateTime.tryParse(due);
    if (d == null) return due;
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  /// The words of the step in This week and the calendar: "Testing 12 → 16", and for a book "Testing — 📖 Bhagavad-gita (1 → 2)", with "on track — due 30 Nov" while his book is not due yet.
  String get words => label.isNotEmpty ? label : (book.isEmpty ? '$name $from → $to' : '$name — 📖 $book ($from → $to)') + (onTrack ? ' · on track — due $dueShort' : '');
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
    this.inCombined = false,
    this.also = '',
    this.calNote = '',
    this.targetId = '',
    this.achieved = false,
    this.result = '',
  });

  /// A target whose END DATE has been reached (kind `targetEnded`): which target, whether its goal was reached ("Target achieved"), and how it ended ("Reached 3 of 5 boys at 16 rounds").
  /// It stays in Today until the guide deletes the target or extends its end date.
  final String targetId;
  final bool achieved;
  final String result;

  /// The calendar event that shapes this interaction ("Exams 31 Dec–17 Jan"): shown as a small note on the item.
  final String calNote;

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

  /// A target's own line in This week that the one combined "Chanting 3 of 5 · Reading 2 of 4 · FOLK 1 of 3" line already says (the calendar still draws its band).
  final bool inCombined;

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
        calNote: (m['calNote'] ?? '').toString(),
        targetId: (m['targetId'] ?? '').toString(),
        achieved: m['achieved'] == true,
        result: (m['result'] ?? '').toString(),
        inCombined: m['inCombined'] == true,
        steps: [
          if (m['steps'] is List)
            for (final e in (m['steps'] as List))
              if (e is Map) PlanStep(name: (e['name'] ?? '').toString(), from: e['from'] is num ? (e['from'] as num).round() : 0, to: e['to'] is num ? (e['to'] as num).round() : 0, done: e['done'] == true, book: (e['book'] ?? '').toString(), due: (e['due'] ?? '').toString(), label: (e['label'] ?? '').toString()),
          // the ONE combined This-week line: each student's combined next step (older plans drew them as steps; an older app shows the title only)
          if (m['combined'] is List)
            for (final e in (m['combined'] as List))
              if (e is Map) PlanStep(name: (e['name'] ?? '').toString(), from: 0, to: 0, done: e['done'] == true, label: (e['label'] ?? '').toString()),
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

/// The `seenMarkers` key: the moment the admin last left the Plan page.
const String kPlanNewKey = 'planNew';

/// One NEW change in an admin's plan area ("New doubt: Testing", "Book finished: Ayush", "New task: Surrender check — Ravi").
class PendingChange {
  const PendingChange({required this.type, required this.text, this.at, this.studentUid = ''});

  final String type;
  final String text;
  final DateTime? at;

  /// The student it is about (empty for a target, a calendar event ...): his rows in Today / This week carry the "New" tag.
  final String studentUid;
}

/// What changed in an admin's plan area (`planChanges/{adminId}/items`, written by the server for THAT admin's own scope, kept 14 days). The plans update
/// by themselves; the badge counts the changes NEWER than the moment the admin last left the Plan page ([NewChanges]).
class PendingChanges {
  const PendingChanges(this.items);

  static const PendingChanges none = PendingChanges([]);

  final List<PendingChange> items;
  int get count => items.length;

  static PendingChanges fromDocs(Iterable<Map<String, dynamic>> docs) {
    final list = [
      for (final d in docs)
        if ((d['text'] ?? '').toString().isNotEmpty)
          PendingChange(
            type: (d['type'] ?? '').toString(),
            text: (d['text'] ?? '').toString(),
            studentUid: (d['studentUid'] ?? '').toString(),
            at: d['at'] is Timestamp ? (d['at'] as Timestamp).toDate() : null,
          ),
    ]..sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
    return PendingChanges(list);
  }
}

/// THE NEW, NOT SEEN YET changes of one admin: those newer than the moment he last LEFT the Plan page (his first time: the last 24 hours). The badge on the Home
/// plan widgets and on the Plan page shows [count]; a tap lists [items]; the rows in Today / This week they concern carry a small "New" tag ([isNewFor]).
class NewChanges {
  const NewChanges(this.items);

  static const NewChanges none = NewChanges([]);

  /// The changes newer than [seen] (null: the last 24 hours before [now]), newest first.
  factory NewChanges.of(PendingChanges all, DateTime? seen, DateTime now) {
    final since = seen ?? now.subtract(const Duration(days: 1));
    return NewChanges([for (final c in all.items) if (c.at != null && c.at!.isAfter(since)) c]..sort((a, b) => b.at!.compareTo(a.at!)));
  }

  final List<PendingChange> items;
  int get count => items.length;

  /// The students a new change is about.
  Set<String> get studentUids => {for (final c in items) if (c.studentUid.isNotEmpty) c.studentUid};
  bool get hasTarget => items.any((c) => c.type == 'target');

  /// Whether an item of the plan (a student's card or row, a target task) has something new.
  bool isNewFor({String studentUid = '', bool isTarget = false}) => (studentUid.isNotEmpty && studentUids.contains(studentUid)) || (isTarget && hasTarget);
}

/// What this app run knows of the admin's looks at the new changes (see [PlanData.looked]); one per [PlanData] instance.
class _Looks {
  /// Per admin: the newest change (by the SERVER's own stamp, so no clock difference counts) he had on screen when he looked: nothing up to it is new any more.
  final Map<String, DateTime> viewedUpTo = {};

  /// Per admin: the newest change stamp of the pending list as last heard.
  final Map<String, DateTime> latestAt = {};

  /// Per admin: the "seen" cursor as it was BEFORE the first look since the Plan page was last left (the "New" tags keep it, so a look at the list on Home does not
  /// strip the tags off the rows).
  final Map<String, DateTime?> tagBase = {};

  /// The last "seen" cursor heard from the server, per admin.
  final Map<String, DateTime?> heardSeen = {};
  final StreamController<String> looked = StreamController<String>.broadcast(sync: true);
}

/// What the Plan page and the dots read, behind one interface (tests hand in a fake).
abstract class PlanData {
  const PlanData();

  static PlanData instance = const FirestorePlanData();

  /// The admin's plan, live; null until the server has written one.
  Stream<PlanDoc?> plan(String adminId);

  /// What changed in the admin's plan area in the last 14 days, live (no AI cost: recorded by the server as it happens).
  Stream<PendingChanges> pending(String adminId) => Stream.value(PendingChanges.none);

  /// The moment the admin last LEFT the Plan page (null: never).
  Stream<DateTime?> seenAt(String adminId) => Stream.value(null);

  /// Saves "seen" on the server (the screens call [looked] / [leftPlan], which clear everything on screen at once first).
  Future<void> markPlanSeen(String adminId) async {}

  // ---- what the admin has just LOOKED at (kept in this app run, so the badge and the dot clear at once, whatever the network does) -----------------------------

  static final Expando<_Looks> _looks = Expando<_Looks>('planLooks');
  _Looks get _l => _looks[this] ??= _Looks();

  /// The admin LOOKS at the new changes (the list, or the Plan page): the badge and the dots clear AT ONCE, here, before the server has answered. A failed or slow save
  /// changes nothing on screen; a change that arrives after this look is new again. [save]: also write "seen" to the server now (the list does; the Plan page does it when
  /// the admin leaves it, so the page's own "New" tags keep the server's cursor while he is on it).
  void looked(String adminId, {bool save = true}) {
    if (adminId.isEmpty) return;
    final l = _l;
    if (!l.tagBase.containsKey(adminId) && l.heardSeen.containsKey(adminId)) l.tagBase[adminId] = l.heardSeen[adminId];
    final latest = l.latestAt[adminId];
    if (latest != null) l.viewedUpTo[adminId] = latest;
    l.looked.add(adminId);
    if (save) markPlanSeen(adminId).catchError((_) {});
  }

  /// The admin LEFT the Plan page: what arrived while he was on it is looked at too, "seen" is saved, and the "New" tags are over.
  void leftPlan(String adminId) {
    if (adminId.isEmpty) return;
    looked(adminId);
    _l.tagBase.remove(adminId);
  }

  /// The NEW changes of one admin, live: [pending] newer than [seenAt] and than what he has just looked at. Nothing is emitted until BOTH are known (never a stale first
  /// frame). [forPage]: the Plan page's own view - its "New" tags and bar keep the server's cursor from before the first look, so they stay while he is on the page.
  /// (One subscription of each; cancelled with this one.)
  Stream<NewChanges> newChanges(String adminId, {bool forPage = false}) {
    final l = _l;
    late final StreamController<NewChanges> c;
    StreamSubscription<PendingChanges>? a;
    StreamSubscription<DateTime?>? b;
    StreamSubscription<String>? lk;
    PendingChanges? items;
    DateTime? seen;
    DateTime? frozen;
    var frozenKnown = false;
    var seenKnown = false;
    void emit() {
      if (items == null || !seenKnown || c.isClosed) return;
      DateTime? cursor;
      if (forPage) {
        if (!frozenKnown) {
          frozen = l.tagBase.containsKey(adminId) ? l.tagBase[adminId] : seen;
          frozenKnown = true;
        }
        cursor = frozen;
      } else {
        cursor = seen;
        final v = l.viewedUpTo[adminId];
        if (v != null && (cursor == null || v.isAfter(cursor))) cursor = v;
      }
      c.add(NewChanges.of(items!, cursor, now()));
    }

    c = StreamController<NewChanges>(
      onListen: () {
        a = pending(adminId).listen((v) {
          items = v;
          DateTime? newest;
          for (final x in v.items) {
            if (x.at != null && (newest == null || x.at!.isAfter(newest))) newest = x.at;
          }
          if (newest != null) l.latestAt[adminId] = newest;
          emit();
        }, onError: c.addError);
        b = seenAt(adminId).listen((v) {
          seen = v;
          l.heardSeen[adminId] = v;
          seenKnown = true;
          emit();
        }, onError: c.addError);
        lk = l.looked.stream.where((id) => id == adminId).listen((_) => emit());
      },
      onCancel: () async {
        await a?.cancel();
        await b?.cancel();
        await lk?.cancel();
      },
    );
    return c.stream;
  }

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
  Stream<DateTime?> seenAt(String adminId) => SeenMarkers.seenAt(adminId, kPlanNewKey).map((t) => t?.toDate());

  @override
  Future<void> markPlanSeen(String adminId) => SeenMarkers.markSeen(adminId, kPlanNewKey);

  @override
  Stream<PendingChanges> pending(String adminId) => GuideDb.instance
      .collection('planChanges')
      .doc(adminId)
      .collection('items')
      .snapshots()
      .map((s) => PendingChanges.fromDocs(s.docs.map((d) => d.data())));
}
