/// `serviceAssignments/{autoId}` — Part 3, Rule 12 justified below.
///
/// ---------------------------------------------------------------------------
/// Why a new collection, not the old `studentServices`
/// ---------------------------------------------------------------------------
/// The old `studentServices/{uid}` was one document per STUDENT, holding a
/// single `assignedServices` array of ids with zero status of any kind (Part
/// 1's own discovery confirmed this — assignment only, "completion is not
/// tracked anywhere in this system," per `AbcdeActivityCard.dart`'s own
/// comment). This task needs one row PER (student, service) PAIR, each with
/// its own status lifecycle and an independent, guide-only competence
/// assessment — a shape an array-of-ids field cannot hold without turning
/// every status/competence update into a read-modify-write of one shared
/// array (a real risk of two guides' near-simultaneous updates clobbering
/// each other). A new collection, one doc per assignment, makes every update
/// a single-document write with no such race, and lets the same data be
/// queried two ways — by student (`studentUid ==`) and by service
/// (`serviceNumber ==`) — with a single equality filter each time, matching
/// this project's established no-composite-index convention.
///
/// ---------------------------------------------------------------------------
/// Fields
/// ---------------------------------------------------------------------------
///   serviceNumber      int          1-19, matches `ServiceBankContent.dart`
///   studentUid         String
///   assignedByGuideId  String
///   assignedAt         Timestamp
///   status             String       see [kAssignmentStatuses]
///   statusUpdatedAt    Timestamp
///   statusUpdatedBy    String       whoever changed it last — a guide id or
///                                   the student's own uid; either app can
///                                   write these two fields (Part 5 item 3)
///   competence         Map?         see [CompetenceLevel] below. ABSENT
///                                   until a guide assesses it — never a
///                                   default/placeholder value, so "not yet
///                                   assessed" and "assessed as not yet
///                                   competent" are never confused.
///
/// ---------------------------------------------------------------------------
/// Competence shape — binary, not a scale (Part 3, justified)
/// ---------------------------------------------------------------------------
/// Every one of the 19 services' assessment questions in the source content
/// is phrased as a yes/no question ("Does his kīrtana make…", "Can he
/// independently…", "Would we confidently…") — none imply a graded scale.
/// Inventing a 1-5 scale the source material doesn't ask for would invite
/// guides to argue about what a "3" means for a question that was written
/// to be answered directly. `competence.level` is therefore exactly two
/// values: [kCompetenceNotYet] / [kCompetenceYes].
///
/// Competence is guide-only by CONSTRUCTION, not by a runtime permission
/// check the student app could bypass: [setCompetence] lives in this file,
/// imported only by Guide-app screens — the Student app's own copy of the
/// service-bank feature (Part 5) has no equivalent function and never
/// imports this file at all, so there is no code path in that app's source
/// that could write a `competence` field, regardless of what a modified
/// client might attempt against the open Firestore document (this project
/// has no security rules in source, exactly as `utils/GuideRoster.dart`'s
/// own header already states about every other permission in this app).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'StudentScope.dart';

const String kStatusAssigned = 'assigned';
const String kStatusInProgress = 'inProgress';
const String kStatusCompleted = 'completed';

/// The guide removed this assignment. The document is kept, never deleted —
/// Part 4 item 6's own reasoning: a completed service with a competence
/// assessment is real training history worth keeping, and even an
/// unassigned-before-completion record is a real fact about what was once
/// assigned, not something to erase.
const String kStatusWithdrawn = 'withdrawn';

const List<String> kAssignmentStatuses = [
  kStatusAssigned,
  kStatusInProgress,
  kStatusCompleted,
];

const String kCompetenceNotYet = 'notYet';
const String kCompetenceYes = 'yes';

String statusLabel(String status) {
  switch (status) {
    case kStatusAssigned:
      return 'Assigned';
    case kStatusInProgress:
      return 'In progress';
    case kStatusCompleted:
      return 'Completed';
    case kStatusWithdrawn:
      return 'Withdrawn';
    default:
      return status;
  }
}

class ServiceCompetence {
  final String level; // kCompetenceNotYet | kCompetenceYes
  final String assessedBy;
  final DateTime? assessedAt;
  final String? note;

  const ServiceCompetence({
    required this.level,
    required this.assessedBy,
    this.assessedAt,
    this.note,
  });

  factory ServiceCompetence.fromMap(Map<String, dynamic> map) {
    final ts = map['assessedAt'];
    return ServiceCompetence(
      level: (map['level'] ?? kCompetenceNotYet).toString(),
      assessedBy: (map['assessedBy'] ?? '').toString(),
      assessedAt: ts is Timestamp ? ts.toDate() : null,
      note: (map['note'] as String?)?.trim().isEmpty == true
          ? null
          : map['note'] as String?,
    );
  }
}

class ServiceAssignment {
  final String id;
  final int serviceNumber;
  final String studentUid;
  final String assignedByGuideId;
  final DateTime? assignedAt;
  final String status;
  final DateTime? statusUpdatedAt;
  final String statusUpdatedBy;
  final ServiceCompetence? competence;

  const ServiceAssignment({
    required this.id,
    required this.serviceNumber,
    required this.studentUid,
    required this.assignedByGuideId,
    this.assignedAt,
    required this.status,
    this.statusUpdatedAt,
    required this.statusUpdatedBy,
    this.competence,
  });

  factory ServiceAssignment.fromDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    final assignedAtTs = data['assignedAt'];
    final statusUpdatedAtTs = data['statusUpdatedAt'];
    final competenceMap = data['competence'];

    return ServiceAssignment(
      id: id,
      serviceNumber: (data['serviceNumber'] as num?)?.toInt() ?? 0,
      studentUid: (data['studentUid'] ?? '').toString(),
      assignedByGuideId: (data['assignedByGuideId'] ?? '').toString(),
      assignedAt: assignedAtTs is Timestamp ? assignedAtTs.toDate() : null,
      status: (data['status'] ?? kStatusAssigned).toString(),
      statusUpdatedAt:
          statusUpdatedAtTs is Timestamp ? statusUpdatedAtTs.toDate() : null,
      statusUpdatedBy: (data['statusUpdatedBy'] ?? '').toString(),
      competence: competenceMap is Map<String, dynamic>
          ? ServiceCompetence.fromMap(competenceMap)
          : null,
    );
  }

  bool get isWithdrawn => status == kStatusWithdrawn;
}

CollectionReference<Map<String, dynamic>> _col() =>
    FirebaseFirestore.instance.collection('serviceAssignments');

/// Hierarchy: `serviceAssignments` carry the server-stamped scope fields, so
/// every read below goes through [StudentScope]'s history helpers (HOD: all;
/// others: only their visible students' assignments). Only equality filters, so
/// no composite index; callers sort in memory.
List<ServiceAssignment> _toAssignments(QuerySnapshot<Map<String, dynamic>> snap) =>
    snap.docs.map((d) => ServiceAssignment.fromDoc(d.id, d.data())).toList();

/// Every assignment for one student — "by student" (Part 4 item 4), a
/// single `studentUid ==` equality filter. Includes withdrawn ones; callers
/// filter those out for an "active" view where that distinction matters.
Stream<List<ServiceAssignment>> assignmentsForStudentStream(String studentUid) {
  return StudentScope.current()
      .historyStream('serviceAssignments',
          extraEquals: {'studentUid': studentUid})
      .map(_toAssignments);
}

/// Every assignment of one service — "by service" (Part 4 item 4), a single
/// `serviceNumber ==` equality filter.
Stream<List<ServiceAssignment>> assignmentsForServiceStream(int serviceNumber) {
  return StudentScope.current()
      .historyStream('serviceAssignments',
          extraEquals: {'serviceNumber': serviceNumber})
      .map(_toAssignments);
}

/// Every assignment this viewer may see — the Guide app's "Assigned" tab
/// streams this once and groups/filters client-side (by student, by service).
Stream<List<ServiceAssignment>> allAssignmentsStream() {
  return StudentScope.current()
      .historyStream('serviceAssignments')
      .map(_toAssignments);
}

/// Assigns [serviceNumber] to [studentUid]. Guards against a duplicate
/// ACTIVE assignment (Part 3 — not explicitly asked for, but the natural
/// reading of "assign" as a real action rather than a button that can spam
/// identical rows every tap): if a non-withdrawn assignment of the same
/// service already exists for this student, this is a silent no-op and
/// returns that existing assignment's id; a WITHDRAWN one does not block a
/// fresh assignment (Part 4 item 6's own reasoning — withdrawing and later
/// reassigning the same service is a real, expected flow).
Future<String> assignService({
  required int serviceNumber,
  required String studentUid,
  required String assignedByGuideId,
}) async {
  final existing = await StudentScope.current().historyGet(
    'serviceAssignments',
    extraEquals: {'studentUid': studentUid, 'serviceNumber': serviceNumber},
  );

  for (final doc in existing.docs) {
    if (doc.data()['status'] != kStatusWithdrawn) return doc.id;
  }

  final ref = await _col().add({
    'serviceNumber': serviceNumber,
    'studentUid': studentUid,
    'assignedByGuideId': assignedByGuideId,
    'assignedAt': FieldValue.serverTimestamp(),
    'status': kStatusAssigned,
    'statusUpdatedAt': FieldValue.serverTimestamp(),
    'statusUpdatedBy': assignedByGuideId,
  });
  return ref.id;
}

/// Part 4 item 5 / Part 5 item 3 — either app calls this. `updatedBy` is
/// whichever identity the caller has: a guide id from the Guide app, or the
/// student's own uid from the Student app. Never touches `competence`.
Future<void> updateAssignmentStatus({
  required String assignmentId,
  required String newStatus,
  required String updatedBy,
}) async {
  await _col().doc(assignmentId).set({
    'status': newStatus,
    'statusUpdatedAt': FieldValue.serverTimestamp(),
    'statusUpdatedBy': updatedBy,
  }, SetOptions(merge: true));
}

/// Guide-only by construction — see this file's header. Never called from
/// anywhere the Student app can reach.
Future<void> setCompetence({
  required String assignmentId,
  required String level,
  required String assessedByGuideId,
  String? note,
}) async {
  await _col().doc(assignmentId).set({
    'competence': {
      'level': level,
      'assessedBy': assessedByGuideId,
      'assessedAt': FieldValue.serverTimestamp(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    },
  }, SetOptions(merge: true));
}

/// Part 4 item 6 — withdraw, never delete. Keeps `competence` if any was
/// already recorded; only `status` (and its own stamp fields) change.
Future<void> withdrawAssignment({
  required String assignmentId,
  required String withdrawnBy,
}) async {
  await updateAssignmentStatus(
    assignmentId: assignmentId,
    newStatus: kStatusWithdrawn,
    updatedBy: withdrawnBy,
  );
}
