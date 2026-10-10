import 'package:cloud_firestore/cloud_firestore.dart';

import 'PlanningQueries.dart';

/// The two lists behind "Follow-ups" and "Overdue" on the Home hero and on the
/// This Week screen. The rules are the ones This Week has always used (moved
/// here so both screens agree by construction); nothing is queried here.

/// A follow-up due in the current week.
typedef FollowUpItem = ({String student, DateTime when, String action});

/// An overdue meeting.
typedef OverdueItem = ({String student, int days});

/// `interactionLogs` whose approved summary has a follow-up date inside [week]
/// (status and the date range are matched in Dart, so no composite index is
/// needed), earliest first.
List<FollowUpItem> followUpsDue(
  Iterable<QueryDocumentSnapshot> docs,
  ({DateTime start, DateTime end}) week,
) {
  final due = <FollowUpItem>[];
  for (final doc in docs) {
    final data = doc.data() as Map<String, dynamic>;
    if (data['status'] != 'approved') continue;

    final summary = data['approvedSummary'];
    if (summary is! Map<String, dynamic>) continue;

    final raw = summary['followUpDate'];
    if (!fallsInRange(raw, week.start, week.end)) continue;

    due.add((
      student: (data['studentName'] ?? 'Unknown').toString(),
      when: (raw as Timestamp).toDate(),
      action: (summary['recommendedNextAction'] ?? '').toString(),
    ));
  }
  due.sort((a, b) => a.when.compareTo(b.when));
  return due;
}

/// `associations` that are overdue (see [associationOverdueSince]), most
/// overdue first.
List<OverdueItem> overdueAssociations(Iterable<QueryDocumentSnapshot> docs) {
  final overdue = <OverdueItem>[];
  for (final doc in docs) {
    final data = doc.data() as Map<String, dynamic>;
    final since = associationOverdueSince(data);
    if (since == null) continue;
    overdue.add((
      student: (data['studentName'] ?? 'Unknown').toString(),
      days: daysOverdue(since),
    ));
  }
  overdue.sort((a, b) => b.days.compareTo(a.days));
  return overdue;
}
