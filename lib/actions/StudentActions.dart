import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/GuideDb.dart';
import '../utils/ManualStudents.dart';
import '../utils/StudentNameGuard.dart';

/// Changes to a student's own record, as shared writes with no screen in them.
/// The profile cards, the Tasks → Add student dialog and the AI agent all go
/// through these, so a student edited by the agent is edited exactly as one edited
/// by hand — same fields, same merge, same rules.
///
/// Every update here MERGES. A whole-document write would clobber anything a
/// newer Student app version added to the document.

/// The three residences a student can have, as stored in `users.role`.
const List<String> kResidences = [
  'Stay at FOLK',
  'Stay at Hostel',
  'Stay at Localite',
];

/// A day's worth of minutes — the ceiling the deployed Firestore rules enforce
/// on `readingCommitmentMinutes`.
const int kMaxReadingMinutes = 1440;

/// Why these commitments cannot be saved, or null if they can. Refuses the same
/// numbers the rules would, with a sentence that explains itself.
String? commitmentProblem({int? rounds, int? readingMinutes}) {
  if (rounds != null && rounds < 1) return 'Chanting must be at least 1 round a day';
  if (readingMinutes != null) {
    if (readingMinutes < 0) return 'Reading cannot be negative';
    if (readingMinutes > kMaxReadingMinutes) {
      return 'A day is $kMaxReadingMinutes minutes';
    }
  }
  return null;
}

/// Sets a student's daily chanting and reading commitments.
Future<void> setStudentCommitments(
  String studentUid, {
  required int? rounds,
  required int? readingMinutes,
  FirebaseFirestore? db,
}) async {
  final problem = commitmentProblem(rounds: rounds, readingMinutes: readingMinutes);
  if (problem != null) throw ArgumentError(problem);
  await (db ?? GuideDb.instance).collection('users').doc(studentUid).set({
    'commitmentRounds': rounds,
    'readingCommitmentMinutes': readingMinutes,
  }, SetOptions(merge: true));
}

/// Switches one notification on or off for a student. Stored at
/// `users/{uid}.notificationPrefs.<key>`, one key at a time, merged, so switching
/// one never disturbs the others.
Future<void> setStudentNotificationPref(
  String studentUid,
  String key,
  bool value, {
  FirebaseFirestore? db,
}) async {
  await (db ?? GuideDb.instance).collection('users').doc(studentUid).set({
    'notificationPrefs': {key: value},
  }, SetOptions(merge: true));
}

/// Changes a student's residence. Reports already filed stay filed under the old
/// category and come back if he is switched back; only new reports follow the
/// new one.
Future<void> setStudentResidence(
  String studentUid,
  String residence, {
  FirebaseFirestore? db,
}) async {
  if (!kResidences.contains(residence)) {
    throw ArgumentError('Residence must be one of: ${kResidences.join(', ')}');
  }
  await (db ?? GuideDb.instance)
      .collection('users')
      .doc(studentUid)
      .set({'role': residence}, SetOptions(merge: true));
}

/// Sets a student's date of birth. Only that field, merged.
Future<void> setStudentDob(
  String studentUid,
  DateTime dob, {
  FirebaseFirestore? db,
}) async {
  await (db ?? GuideDb.instance).collection('users').doc(studentUid).set(
    {'dob': Timestamp.fromDate(dob)},
    SetOptions(merge: true),
  );
}

/// Adding a student whose mobile number is already on another student.
class DuplicateMobileException implements Exception {
  DuplicateMobileException(this.existingName);
  final String existingName;

  @override
  String toString() => 'This mobile number already belongs to '
      '"$existingName" — cannot add a duplicate.';
}

/// Adds a student who has not signed up themselves ("manual entry").
///
/// Refuses a mobile number that already belongs to someone, rather than asking
/// the guide to confirm an override. [guideId] is whoever the student is
/// assigned to (null or empty = Unassigned); [addedBy] is the admin adding them.
///
/// @return the new student's id
Future<String> addManualStudent({
  required String name,
  required String mobile,
  required String residence,
  required String gender,
  required String addedBy,
  String? guideId,
  int? rounds,
}) async {
  final cleanName = normalizeStudentName(name);
  if (cleanName.isEmpty) throw ArgumentError("Enter the student's name");
  if (!kResidences.contains(residence)) {
    throw ArgumentError('Select FOLK, Hostel or Localite');
  }
  if (gender != 'male' && gender != 'female') {
    throw ArgumentError('Gender must be male or female');
  }
  final normalized = normalizeMobileNumber(mobile);
  if (!isValidNormalizedMobile(normalized)) {
    throw ArgumentError('Enter a valid 10-digit mobile number');
  }

  final existing = await findUserByMobileNumber(normalized);
  if (existing != null) {
    throw DuplicateMobileException((existing['name'] ?? 'another student').toString());
  }

  final id = generateManualStudentId();
  await GuideDb.instance.collection('users').doc(id).set({
    'name': cleanName,
    'mobileNumber': normalized,
    'role': residence,
    'gender': gender,
    if (guideId != null && guideId.isNotEmpty) 'guideId': guideId,
    if (rounds != null && rounds > 0) 'commitmentRounds': rounds,
    'isManualEntry': true,
    'addedByGuideId': addedBy,
    'addedAt': Timestamp.now(),
    'createdAt': Timestamp.now(),
  });
  return id;
}
