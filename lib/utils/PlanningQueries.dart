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

import 'StudentScope.dart';

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

/// `associations` scoped to the viewer: everything for a HOD, otherwise the
/// records about the students the signed-in admin may see (the server-stamped
/// scope fields — see `StudentScope`).
///
/// Equality filters only — status and dates are matched in Dart so no
/// composite index is required, matching every other screen in this app.
///
/// [guide] is ignored (kept so older call sites still compile): the scope is
/// always the signed-in admin's own.
Stream<QuerySnapshot> scopedAssociationsStream([String guide = '']) =>
    StudentScope.current().historyStream('associations');

/// `interactionLogs` scoped the same way.
Stream<QuerySnapshot> scopedInteractionLogsStream([String guide = '']) =>
    StudentScope.current().historyStream('interactionLogs');

/// `litAssessments` about the students the signed-in admin may see.
///
/// Scoped **by student, not by assessing guide**: a student reassigned from one
/// admin to another keeps their history, so the new owner sees the earlier
/// assessments; scoping on the assessment's own `guideId` would hide them and
/// silently under-report.
///
/// This never widens LIT: the scope fields restrict the read to the viewer's
/// own visible students (the rules enforce the same filters). LIT is the most
/// sensitive data in the system, so reading the whole collection and filtering
/// client-side is not an option.
Future<List<QueryDocumentSnapshot>> litAssessmentsForRoster() async =>
    (await StudentScope.current().historyGet('litAssessments')).docs;

/// Students visible to the signed-in admin — all of them for a HOD.
///
/// Returns uid and name together, because `users` is uid-keyed while
/// `sadhana-reports`, `notification` and `scorecard` are all name-keyed, so
/// joining across them needs both.
///
/// Returns null when the roster could not be read, so a caller can tell "no
/// students" apart from "lookup failed" and fail closed rather than showing
/// another admin's students. [guide] is ignored (kept for older call sites).
Future<List<({String uid, String name})>?> scopedStudents(
    [String guide = '']) async {
  try {
    final snap = await StudentScope.current().studentsGet();

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

/// Student display names visible to the signed-in admin. Thin wrapper over
/// [scopedStudents] so both share one query and one scoping rule.
Future<Set<String>?> scopedStudentNames([String guide = '']) async {
  final students = await scopedStudents();
  return students?.map((s) => s.name).toSet();
}
