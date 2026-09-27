/// Shared planning predicates.
///
/// These live here rather than inside a single dashboard's State class so the
/// weekly planning overview and the full dashboards agree by construction. If
/// "overdue" ever needs redefining, it changes in one place.
///
/// Every date comparison uses the device clock. There is no `timezone`
/// package in this app, so "today" and "this week" are device-local — Asia/
/// Kolkata in practice, but not pinned. Same assumption `getTodayDateId()`
/// already makes.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'GuideRoster.dart';

/// Monday 00:00 of the current week, and the Monday after it.
///
/// End is **exclusive**, so a Sunday-evening follow-up is inside the week and
/// next Monday's is not. `DateTime.weekday` is 1 = Monday … 7 = Sunday.
({DateTime start, DateTime end}) currentWeekRange([DateTime? now]) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final monday = startOfToday.subtract(Duration(days: today.weekday - 1));

  return (start: monday, end: monday.add(const Duration(days: 7)));
}

/// True when [value] is a Timestamp inside [start, end).
bool fallsInRange(Object? value, DateTime start, DateTime end) {
  if (value is! Timestamp) return false;
  final date = value.toDate();
  return !date.isBefore(start) && date.isBefore(end);
}

/// The date that makes an association overdue, or null when it is not.
///
/// Overdue means a `pending` record whose `preferredDate` has passed, or a
/// `confirmed` one whose `confirmedDate` has passed — a meeting that should
/// have happened and was never marked complete.
///
/// Compared against the start of today, so a meeting earlier *today* is not
/// yet overdue: the guide may still be about to hold it.
DateTime? associationOverdueSince(Map<String, dynamic> data, [DateTime? now]) {
  final status = (data['status'] ?? '').toString();

  final Object? raw;
  if (status == 'pending') {
    raw = data['preferredDate'];
  } else if (status == 'confirmed') {
    raw = data['confirmedDate'] ?? data['preferredDate'];
  } else {
    return null;
  }

  if (raw is! Timestamp) return null;

  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final date = raw.toDate();

  return date.isBefore(startOfToday) ? date : null;
}

/// Whole days between [since] and today, both truncated to midnight.
int daysOverdue(DateTime since, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final startOfThen = DateTime(since.year, since.month, since.day);
  return startOfToday.difference(startOfThen).inDays;
}

/// `associations` scoped to the viewer: everything for the HOD, one guide's
/// records for anyone else.
///
/// A single equality filter only — status and dates are matched in Dart so no
/// composite index is required, matching every other screen in this app.
Stream<QuerySnapshot> scopedAssociationsStream(String guide) {
  final collection = FirebaseFirestore.instance.collection('associations');

  return guide == kHodGuideId
      ? collection.snapshots()
      : collection.where('guideId', isEqualTo: guide).snapshots();
}

/// `interactionLogs` scoped the same way.
Stream<QuerySnapshot> scopedInteractionLogsStream(String guide) {
  final collection = FirebaseFirestore.instance.collection('interactionLogs');

  return guide == kHodGuideId
      ? collection.snapshots()
      : collection.where('guideId', isEqualTo: guide).snapshots();
}

/// Firestore rejects a `whereIn` with more than this many values.
const int _whereInLimit = 30;

/// `litAssessments` for the students on [studentUids], which the caller has
/// already scoped to the viewer's own roster.
///
/// Scoped **by student, not by assessing guide**. A student reassigned from
/// one guide to another keeps their history, so their new guide sees the
/// earlier assessments; scoping on the assessment's own `guideId` would hide
/// them and silently under-report.
///
/// This still never widens LIT across guides: the server only returns rows
/// for uids the caller already has on their roster. LIT is the most sensitive
/// data in the system, so the alternative — reading the whole collection and
/// filtering client-side — was rejected: it would put every student's
/// assessment on every guide's phone.
///
/// A roster larger than [_whereInLimit] is fetched in concurrent chunks,
/// because Firestore caps the number of values in a single `whereIn`.
Future<List<QueryDocumentSnapshot>> litAssessmentsForRoster(
  String guide,
  List<String> studentUids,
) async {
  final collection = FirebaseFirestore.instance.collection('litAssessments');

  if (guide == kHodGuideId) {
    return (await collection.get()).docs;
  }

  if (studentUids.isEmpty) return const [];

  final chunks = <List<String>>[];
  for (var i = 0; i < studentUids.length; i += _whereInLimit) {
    final end = (i + _whereInLimit).clamp(0, studentUids.length);
    chunks.add(studentUids.sublist(i, end));
  }

  final snapshots = await Future.wait(
    chunks.map((chunk) => collection.where('studentUid', whereIn: chunk).get()),
  );

  return snapshots.expand((snap) => snap.docs).toList();
}

/// Students visible to [guide] — all of them for the HOD.
///
/// Returns uid and name together, because `users` is uid-keyed while
/// `sadhana-reports`, `notification` and `scorecard` are all name-keyed, so
/// joining across them needs both.
///
/// Returns null when the roster could not be read, so a caller can tell "no
/// students" apart from "lookup failed" and fail closed rather than showing
/// another guide's students.
Future<List<({String uid, String name})>?> scopedStudents(String guide) async {
  try {
    final snap = guide == kHodGuideId
        ? await FirebaseFirestore.instance.collection('users').get()
        : await FirebaseFirestore.instance
            .collection('users')
            .where('guideId', isEqualTo: guide)
            .get();

    final students = <({String uid, String name})>[];
    for (final doc in snap.docs) {
      final name = (doc.data()['name'] ?? '').toString();
      if (name.isNotEmpty) students.add((uid: doc.id, name: name));
    }
    return students;
  } catch (_) {
    return null;
  }
}

/// Student display names visible to [guide]. Thin wrapper over
/// [scopedStudents] so both share one query and one scoping rule.
Future<Set<String>?> scopedStudentNames(String guide) async {
  final students = await scopedStudents(guide);
  return students?.map((s) => s.name).toSet();
}
