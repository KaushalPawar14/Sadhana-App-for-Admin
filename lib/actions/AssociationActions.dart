import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../Services/HierarchyApi.dart';
import '../utils/GuideDb.dart';

/// Meetings with students (Associations): the writes, with no screen in them.
///
/// Each of these used to live inside `AssociationManager`'s State, tangled up
/// with date pickers and snackbars. They moved here, unchanged, so that the
/// screen and the AI agent make the SAME write — one implementation, not a
/// screen's and a copy of it — and the security rules and the student
/// notification rules apply to both alike.
///
/// A failure is thrown, not swallowed: the caller decides how to tell the guide
/// (the screen with a snackbar, the agent in its reply). The one exception is the
/// notification, which — as it always did — never rolls back the change it is
/// about.

final DateFormat _when = DateFormat('dd MMM yyyy, hh:mm a');

/// The student hears about a meeting through the server, which applies their
/// own `associationUpdates` preference and owns the FCM token.
Future<void> notifyStudentAboutMeeting(
  String studentUid,
  String title,
  String body,
) async {
  if (studentUid.isEmpty) return;
  try {
    await HierarchyApi.instance.sendStudentNotification({
      'kind': 'association_update',
      'studentUid': studentUid,
      'title': title,
      'body': body,
    });
  } catch (_) {
    // A failed notification must not roll back the status change.
  }
}

/// "Request a Meeting": the guide asks a student for a time. It starts Pending
/// (`requestedBy: guide`) until the student confirms.
///
/// @return the new association's id
Future<String> requestMeeting({
  required String guideId,
  required String studentUid,
  required String studentName,
  required DateTime preferred,
  String message = '',
}) async {
  final ref = await GuideDb.instance.collection('associations').add({
    'studentUid': studentUid,
    'studentName': studentName,
    'guideId': guideId,
    'requestedBy': 'guide',
    'preferredDate': Timestamp.fromDate(preferred),
    'confirmedDate': null,
    'status': 'pending',
    'studentNotes': message.trim(),
    'guideNotes': '',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  await notifyStudentAboutMeeting(
    studentUid,
    'Meeting Scheduled',
    'Your guide has requested a meeting on ${_when.format(preferred)}',
  );
  return ref.id;
}

/// "Confirm" / "Set My Own Date": fixes the time of a student's request.
Future<void> confirmMeeting(
  String associationId, {
  required String studentUid,
  required DateTime when,
}) async {
  await GuideDb.instance.collection('associations').doc(associationId).update({
    'confirmedDate': Timestamp.fromDate(when),
    'status': 'confirmed',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  await notifyStudentAboutMeeting(
    studentUid,
    'Meeting Confirmed',
    'Your meeting is confirmed for ${_when.format(when)}',
  );
}

/// "Accept Student's Date": takes the student's counter-proposal as it stands.
Future<void> acceptStudentProposal(
  String associationId, {
  required String studentUid,
  required Timestamp proposed,
}) async {
  await GuideDb.instance.collection('associations').doc(associationId).update({
    'confirmedDate': proposed,
    'status': 'confirmed',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  await notifyStudentAboutMeeting(
    studentUid,
    'Meeting Confirmed',
    'Your meeting is confirmed for ${_when.format(proposed.toDate())}',
  );
}

/// "Mark Complete": the meeting happened; these are the notes.
Future<void> completeMeeting(
  String associationId, {
  required String notes,
}) async {
  await GuideDb.instance.collection('associations').doc(associationId).update({
    'status': 'completed',
    'guideNotes': notes.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

/// Cancel a request or a meeting.
Future<void> cancelMeeting(
  String associationId, {
  required String studentUid,
}) async {
  await GuideDb.instance.collection('associations').doc(associationId).update({
    'status': 'cancelled',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  await notifyStudentAboutMeeting(
    studentUid,
    'Meeting Cancelled',
    'Your meeting request was cancelled',
  );
}

/// Move an already confirmed meeting to another time, and tell the student.
///
/// New with the agent: the app could confirm a request and cancel a meeting, but
/// not move one, and the agent may only do what a guide can do by hand — so the
/// Upcoming card gained a Reschedule button that calls this, and so does the agent.
Future<void> rescheduleMeeting(
  String associationId, {
  required String studentUid,
  required DateTime when,
}) async {
  await GuideDb.instance.collection('associations').doc(associationId).update({
    'confirmedDate': Timestamp.fromDate(when),
    'status': 'confirmed',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  await notifyStudentAboutMeeting(
    studentUid,
    'Meeting Rescheduled',
    'Your meeting has been moved to ${_when.format(when)}',
  );
}

/// Changes the guide's notes on a COMPLETED meeting (the assistant's edit of what "Mark Complete" saved).
Future<void> editMeetingNotes(
  String associationId, {
  required String notes,
}) async {
  await GuideDb.instance.collection('associations').doc(associationId).update({
    'guideNotes': notes.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
