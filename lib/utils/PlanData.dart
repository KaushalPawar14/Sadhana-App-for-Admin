import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'GuideDb.dart';

/// The Today / This week plans, as the server wrote them (`guidePlans/{adminId}`, worked out by `functions/guidePlans.js`; the app only
/// reads it). Read-only everywhere: a plan changes only through the assistant, or when its data changes.

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

  static PlanItem fromMap(Map<String, dynamic> m) => PlanItem(
        id: (m['id'] ?? '').toString(),
        kind: (m['kind'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        detail: (m['detail'] ?? '').toString(),
        studentName: (m['studentName'] ?? '').toString(),
        forYou: m['forYou'] == true,
        checkWithHim: m['checkWithHim'] == true,
        scheduledFor: (m['scheduledFor'] ?? '').toString(),
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
