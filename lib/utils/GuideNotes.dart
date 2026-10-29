import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'AdminProfile.dart';
import 'GuideDb.dart';
import 'StudentScope.dart';

/// THE GUIDE'S NOTES ON A MEETING ARE GUIDE-ONLY. They used to sit on the association (`associations/{id}.guideNotes`), which the STUDENT
/// reads; they now live in `associationGuideNotes/{associationId}` — readable only by the admins who may see the student (rules), never
/// by a student. The student's own words (`studentNotes`) stay on the association.
const String kGuideNotesCollection = 'associationGuideNotes';

DocumentReference<Map<String, dynamic>> _ref(String associationId) => GuideDb.instance.collection(kGuideNotesCollection).doc(associationId);

/// The guide's note on one meeting ('' when none).
Future<String> guideNoteOf(String associationId) async {
  try {
    return (((await _ref(associationId).get()).data() ?? const {})['notes'] ?? '').toString();
  } catch (_) {
    return '';
  }
}

/// The notes of several meetings: `{associationId: notes}` (only those that have one).
Future<Map<String, String>> guideNotesOf(Iterable<String> associationIds) async {
  final out = <String, String>{};
  await Future.wait(associationIds.toSet().map((id) async {
    final n = await guideNoteOf(id);
    if (n.trim().isNotEmpty) out[id] = n;
  }));
  return out;
}

/// Live: every meeting note this admin may read, `{associationId: notes}` (the same scope the meetings use).
Stream<Map<String, String>> guideNotesStream() => StudentScope.current().historyStream(kGuideNotesCollection).map((snap) => {
      for (final d in snap.docs)
        if (((d.data()['notes'] ?? '').toString()).trim().isNotEmpty) d.id: (d.data()['notes'] ?? '').toString(),
    });

/// Saves the guide's note on a meeting (an empty note removes it). The association itself is not touched: nothing the student can read changes.
Future<void> saveGuideNote(String associationId, String notes) async {
  final text = notes.trim();
  if (text.isEmpty) {
    try {
      await _ref(associationId).delete();
    } catch (_) {/* nothing to delete */}
    return;
  }
  final a = (await GuideDb.instance.collection('associations').doc(associationId).get()).data() ?? const {};
  final me = AdminProfileProvider.current?.id ?? (a['guideId'] ?? '').toString();
  await _ref(associationId).set({
    'associationId': associationId,
    'studentUid': (a['studentUid'] ?? '').toString(),
    'studentName': (a['studentName'] ?? '').toString(),
    'notes': text,
    'updatedBy': me,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
