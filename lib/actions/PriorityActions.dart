import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../Services/MissingReportNotification.dart';
import '../utils/AbcdeActivity.dart'
    show sadhanaDateKey, latestDayWithPossibleData;
import '../utils/AdminProfile.dart';
import '../utils/GuideDb.dart';
import '../utils/PlanningQueries.dart';
import '../utils/PriorityReasons.dart';
import '../utils/SadhanaReportSource.dart' show fetchDateReports;
import '../utils/StudentScope.dart';

/// The priority list, as shared logic with no screen in it: the Priority Students
/// screen and the AI agent both build the list, remove students from it and put
/// them back through these.
///
/// Every read goes through [StudentScope] / the scoped queries, so it is the
/// signed-in admin's own scope and nothing wider.

/// How loudly a concern is drawn. The screen turns it into a colour; the agent
/// ignores it.
enum PriorityTone { danger, warning, brass, brown }

/// One named concern. Deliberately carries no weight or number — a flag is either
/// present or it is not, and the guide reads the words.
///
/// `kind` names the TYPE of concern (never its wording or its day count, which
/// change daily): it is what "Remove from priority list" remembers, so a removed
/// student comes back only when a NEW kind of concern appears.
typedef PriorityFlag = ({String kind, String label, PriorityTone tone});

/// A student with at least one concern, and the concerns themselves.
typedef PriorityStudent = ({String uid, String name, List<PriorityFlag> flags});

/// What the priority list came to for the signed-in admin.
class PriorityList {
  const PriorityList({
    this.students = const [],
    this.inScope = 0,
    this.hiddenCount = 0,
    this.dismissed = const {},
    this.rosterFailed = false,
  });

  /// Students with a concern this admin has not removed, most concerns first.
  final List<PriorityStudent> students;

  /// Students this admin may see at all.
  final int inScope;

  /// Students with concerns that this admin removed and that have nothing new.
  final int hiddenCount;

  /// This admin's removals: student uid -> the concern kinds they had then.
  final Map<String, Set<String>> dismissed;

  /// The roster could not be read: nothing is shown rather than a guess.
  final bool rosterFailed;
}

/// A relationship is considered stale after three weeks without contact.
const int kStaleAfterDays = 21;

/// A LIT axis at or below this is worth the guide's attention.
const int kLowLitAxis = 2;

/// A commitment field as a whole number; anything else is 0, which the reason
/// rules read as "not set" (chanting then falls back to the standard 16, reading
/// skips its reason entirely).
int commitmentAsInt(Object? v) => v is num && v.isFinite && v > 0 ? v.toInt() : 0;

/// The 30 calendar days the reasons look at, most recent first.
///
/// The window ENDS AT YESTERDAY (`latestDayWithPossibleData`), not today: a
/// student who simply has not filed yet this morning is not three days behind. The
/// server's nightly check uses the same end day, so the app and the notification
/// never disagree by a day.
List<ReportDay> priorityWindowFor(Map<String, Map<String, dynamic>> reports) {
  final last = latestDayWithPossibleData(DateTime.now());
  return [
    for (var i = 0; i < 30; i++)
      () {
        final day = last.subtract(Duration(days: i));
        return ReportDay(day, reports[sadhanaDateKey(day)]);
      }(),
  ];
}

/// The concerns one student has, from the data already read for them.
List<PriorityFlag> priorityFlagsFor({
  required ({String uid, String name}) student,
  required List<Map<String, dynamic>> logs,
  required List<Map<String, dynamic>> associations,
  required List<Map<String, dynamic>> lit,
  required Set<String> missing,
  required List<PriorityReason> reasons,
}) {
  final flags = <PriorityFlag>[];

  // --- The automatic sadhana reasons -----------------------------------------
  //
  // Each is three days in a row of the same thing going wrong, read from the
  // student's OWN category's reports and their own commitments
  // (`utils/PriorityReasons.dart`). They carry their own stable `kind`, so
  // "Remove from priority list" treats a NEW kind of slip as new — and a reason
  // simply stops being produced the moment it stops being true, which is what
  // makes the card clear itself.
  for (final r in reasons) {
    flags.add((
      kind: r.key,
      label: r.text,
      tone: r.kind == PriorityReasonKind.noReport
          ? PriorityTone.danger
          : PriorityTone.warning,
    ));
  }

  // --- A. Contact staleness ----------------------------------------------------
  //
  // Any status, not approved-only: an unapproved draft still means the guide met
  // the student. `interactionDate` survives approval either way.
  final dated = logs
      .map((l) => l['interactionDate'])
      .whereType<Timestamp>()
      .map((t) => t.toDate())
      .toList()
    ..sort((a, b) => b.compareTo(a));

  if (dated.isEmpty) {
    // Distinct from a lapse — this student has never been engaged at all, which
    // may simply mean they were added recently.
    flags.add((
      kind: 'never_logged',
      label: "Never logged an interaction",
      tone: PriorityTone.brass,
    ));
  } else {
    final days = daysOverdue(dated.first);
    if (days >= kStaleAfterDays) {
      flags.add((
        kind: 'stale_contact',
        label: "No interaction in $days days",
        tone: PriorityTone.warning,
      ));
    }
  }

  // --- B. Today's sadhana report -------------------------------------------------
  if (missing.contains(student.name)) {
    flags.add((
      kind: 'missing_report',
      label: "Has not submitted today's sadhana report",
      tone: PriorityTone.warning,
    ));
  }

  // --- C. Overdue association -----------------------------------------------------
  DateTime? worstOverdue;
  for (final data in associations) {
    final since = associationOverdueSince(data);
    if (since == null) continue;
    if (worstOverdue == null || since.isBefore(worstOverdue)) {
      worstOverdue = since;
    }
  }
  if (worstOverdue != null) {
    flags.add((
      kind: 'overdue_meeting',
      label: "Meeting overdue by ${daysOverdue(worstOverdue)} days",
      tone: PriorityTone.danger,
    ));
  }

  // --- D. Low LIT axes ---------------------------------------------------------------
  //
  // Each axis is judged on its own and reported on its own. No sum, no average, no
  // combined figure anywhere (Section 8).
  final sortedLit = lit.toList()
    ..sort((a, b) {
      final da = a['assessedAt'];
      final db = b['assessedAt'];
      if (da is! Timestamp) return 1;
      if (db is! Timestamp) return -1;
      return db.compareTo(da);
    });

  if (sortedLit.isNotEmpty) {
    final latest = sortedLit.first;

    void checkAxis(String key, String meaning) {
      final raw = latest[key];
      if (raw is! num) return;
      final value = raw.toInt();
      if (value > kLowLitAxis) return;
      flags.add((
        kind: 'lit_$key',
        label: "$meaning ($key: $value of 5)",
        tone: PriorityTone.brass,
      ));
    }

    checkAxis('L', 'Low receptivity');
    checkAxis('I', 'Low interest');
    checkAxis('T', 'Little available time');
  }

  // --- E. Follow-up date passed with no contact since ----------------------------------
  //
  // Approved-only, because `followUpDate` lives in `approvedSummary`.
  DateTime? dueSince;
  for (final log in logs) {
    if (log['status'] != 'approved') continue;
    final summary = log['approvedSummary'];
    if (summary is! Map<String, dynamic>) continue;

    final raw = summary['followUpDate'];
    if (raw is! Timestamp) continue;

    final due = raw.toDate();
    if (!due.isBefore(DateTime.now())) continue;

    if (dueSince == null || due.isBefore(dueSince)) dueSince = due;
  }

  if (dueSince != null) {
    // Only still outstanding if nothing has been logged since it came due.
    final contactedSince = dated.any((d) => d.isAfter(dueSince!));
    if (!contactedSince) {
      flags.add((
        kind: 'follow_up_due',
        label: "Follow-up was due "
            "${DateFormat('dd MMM').format(dueSince)}, no contact since",
        tone: PriorityTone.brown,
      ));
    }
  }

  return flags;
}

/// The signed-in admin's priority list: every student in THEIR scope with at least
/// one concern, minus the ones they removed and that have nothing new.
///
/// A signal that cannot be read costs that signal, never the list; a roster that
/// cannot be read fails closed ([PriorityList.rosterFailed]).
Future<PriorityList> loadPriorityList() async {
  final profile = AdminProfileProvider.require();
  final students = await scopedStudents();

  if (students == null) {
    // Fail closed — show nothing rather than another guide's students.
    return const PriorityList(rosterFailed: true);
  }

  // Reused, not recomputed — the same singleton SubmissionStatusPage reads.
  final missing = <String>{...NotificationManager().missingUsernames};

  // One read per collection, independent of student count. `.first` on the shared
  // streams reuses their scoping rather than rebuilding the queries.
  List<QueryDocumentSnapshot> logs = [];
  List<QueryDocumentSnapshot> associations = [];
  List<QueryDocumentSnapshot> lit = [];

  try {
    logs = (await scopedInteractionLogsStream().first).docs;
  } catch (_) {/* a missing signal must not blank the list */}
  try {
    associations = (await scopedAssociationsStream().first).docs;
  } catch (_) {}
  try {
    // Scoped by the viewer's visible students, not by who wrote the assessment —
    // a reassigned student keeps their history.
    lit = await litAssessmentsForRoster();
  } catch (_) {}

  // Bucket by studentUid once, so the per-student pass is a map lookup rather than
  // a scan of every collection per student.
  Map<String, List<Map<String, dynamic>>> bucket(
      List<QueryDocumentSnapshot> docs) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = (data['studentUid'] ?? '').toString();
      if (uid.isEmpty) continue;
      out.putIfAbsent(uid, () => []).add(data);
    }
    return out;
  }

  final logsByStudent = bucket(logs);
  final assocByStudent = bucket(associations);
  final litByStudent = bucket(lit);

  // The full roster documents: the reasons need each student's residence (which
  // report collection is theirs) and their own commitments, which
  // `scopedStudents()` does not carry. Same scoped query, read once.
  final roster = <String, Map<String, dynamic>>{};
  try {
    final snap = await StudentScope.current().studentsGet();
    for (final d in snap.docs) {
      roster[d.id] = d.data();
    }
  } catch (_) {/* no reasons rather than no list */}

  // Each student's own category's reports. One read per student, in parallel —
  // there is no collection-group query over `dates` (the ids are `dd-MM-yyyy`,
  // which does not sort chronologically, and the rules can only prove a
  // per-student scoped read). Retention keeps about two months, so each read is
  // small. A failure for one student costs that student's reasons, never the list.
  final reasonsByStudent = <String, List<PriorityReason>>{};
  await Future.wait(students.map((student) async {
    final data = roster[student.uid];
    if (data == null) return;
    try {
      final reports =
          await fetchDateReports(student.name, (data['role'] ?? '').toString());
      final reasons = priorityReasonsFor(
        days: priorityWindowFor(reports),
        role: (data['role'] ?? '').toString(),
        chantCommitment: commitmentAsInt(data['commitmentRounds']),
        readingCommitment: commitmentAsInt(data['readingCommitmentMinutes']),
      );
      if (reasons.isNotEmpty) reasonsByStudent[student.uid] = reasons;
    } catch (_) {}
  }));

  // The students THIS admin already removed from their own priority list (a read
  // failure just shows everyone).
  final dismissed = await readPriorityDismissals(profile.id);

  final result = <PriorityStudent>[];
  var hidden = 0;

  for (final student in students) {
    final flags = priorityFlagsFor(
      student: student,
      logs: logsByStudent[student.uid] ?? const [],
      associations: assocByStudent[student.uid] ?? const [],
      lit: litByStudent[student.uid] ?? const [],
      missing: missing,
      reasons: reasonsByStudent[student.uid] ?? const [],
    );

    // No concerns means not a priority. Such a student is simply absent.
    if (flags.isEmpty) continue;

    // Removed by this admin, and nothing NEW has come up since: stays off their list.
    final removedKinds = dismissed[student.uid];
    if (removedKinds != null &&
        flags.every((f) => removedKinds.contains(f.kind))) {
      hidden++;
      continue;
    }

    result.add((uid: student.uid, name: student.name, flags: flags));
  }

  // Most concerns first; alphabetical within the same count so the order is stable
  // rather than arbitrary.
  result.sort((a, b) {
    final byCount = b.flags.length.compareTo(a.flags.length);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  });

  return PriorityList(
    students: result,
    inScope: students.length,
    hiddenCount: hidden,
    dismissed: dismissed,
  );
}

/// This admin's "removed from my priority list" records: student uid -> the concern
/// kinds they had then. A read failure is an empty map, so everyone shows.
Future<Map<String, Set<String>>> readPriorityDismissals(String adminId) async {
  try {
    final snap = await GuideDb.instance
        .collection('priorityDismissals')
        .where('adminId', isEqualTo: adminId)
        .get();
    return {
      for (final d in snap.docs)
        (d.data()['studentUid'] ?? '').toString(): {
          for (final k in (d.data()['kinds'] as List? ?? const [])) k.toString(),
        },
    }..remove('');
  } catch (_) {
    return {};
  }
}

/// Takes [chosen] off THIS admin's priority list. It writes one small record per
/// student (`priorityDismissals/{adminId}__{studentUid}`: adminId, studentUid,
/// kinds, dismissedAt) and nothing else: the student, their reports, chats,
/// meetings and assessments are never touched.
///
/// [chosen] carries each student's concerns AS SHOWN, because the removal
/// remembers their kinds — that is what lets a NEW kind of concern bring the
/// student back.
Future<void> removeFromPriority(List<PriorityStudent> chosen) async {
  if (chosen.isEmpty) return;
  final profile = AdminProfileProvider.require();
  final db = GuideDb.instance;
  final batch = db.batch();
  for (final p in chosen) {
    batch.set(db.collection('priorityDismissals').doc('${profile.id}__${p.uid}'), {
      'adminId': profile.id,
      'studentUid': p.uid,
      'kinds': [for (final f in p.flags) f.kind],
      'dismissedAt': FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

/// Puts the students [uids] this admin removed back on their list (deletes only
/// those small records).
Future<void> restoreToPriority(Iterable<String> uids) async {
  final profile = AdminProfileProvider.require();
  final db = GuideDb.instance;
  final batch = db.batch();
  for (final uid in uids) {
    batch.delete(db.collection('priorityDismissals').doc('${profile.id}__$uid'));
  }
  await batch.commit();
}
