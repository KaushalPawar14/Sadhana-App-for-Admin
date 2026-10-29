import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'GuideDb.dart';

/// The Today / This week plans, as the server wrote them (`guidePlans/{adminId}`, worked out by `functions/guidePlans.js`; the app only
/// reads it). Read-only everywhere: a plan changes only through the assistant, or when its data changes.

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
  });

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

  bool get isInteraction => kind == 'interaction';

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
      );
}

class PlanSection {
  const PlanSection({required this.id, required this.title, required this.items});
  final String id;
  final String title;
  final List<PlanItem> items;
}

/// Where the plan stands: `upToDate`, `pending` (changes found, waiting for [PlanDoc.pendingRunAt]) or `updating`.
class PlanDoc {
  const PlanDoc({
    required this.todayDate,
    required this.todayItems,
    required this.weekOf,
    required this.intro,
    required this.sections,
    required this.generatedAt,
    required this.status,
    required this.pendingRunAt,
    required this.changedAt,
  });

  final String todayDate;
  final List<PlanItem> todayItems;
  final String weekOf;
  final String intro;
  final List<PlanSection> sections;
  final DateTime? generatedAt;
  final String status;
  final DateTime? pendingRunAt;
  final DateTime? changedAt;

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
      pendingRunAt: _ts(d['pendingRunAt']),
      changedAt: _ts(d['changedAt']),
    );
  }
}

/// What the Plan page and the dots read, behind one interface (tests hand in a fake).
abstract class PlanData {
  const PlanData();

  static PlanData instance = const FirestorePlanData();

  /// The admin's plan, live; null until the server has written one.
  Stream<PlanDoc?> plan(String adminId);

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
}
