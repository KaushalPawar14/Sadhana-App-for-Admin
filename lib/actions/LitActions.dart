import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/GuideDb.dart';

/// A LIT reading of a student, as one shared write: the LIT screen and the AI
/// agent both save through [saveLitAssessment].
///
/// L, I and T are three INDEPENDENT readings, each 1 to 5. They are stored as
/// three fields and never added, averaged or combined into a level — nothing
/// here computes a total, and nothing should.

const List<String> kLitConfidences = ['low', 'medium', 'high'];

/// Why a reading cannot be saved, or null if it can.
///
/// Checked here as well as on the screen, because the screen is not the only
/// way in any more.
String? litProblem({
  required Map<String, int?> scores,
  required String evidence,
  required String confidence,
}) {
  final unset = ['L', 'I', 'T'].where((k) => scores[k] == null).toList();
  if (unset.isNotEmpty) {
    return 'Rate all three axes (${unset.join(', ')} still unset)';
  }
  for (final k in ['L', 'I', 'T']) {
    final v = scores[k]!;
    if (v < 1 || v > 5) return '$k must be between 1 and 5';
  }
  if (evidence.trim().isEmpty) {
    return 'Evidence is required — what did you observe?';
  }
  if (!kLitConfidences.contains(confidence)) {
    return 'Confidence must be low, medium or high';
  }
  return null;
}

/// Saves a reading. A reassessment is a NEW document beside the old one, never a
/// replacement (`add`, never `set`).
///
/// @return the new document's id
Future<String> saveLitAssessment({
  required String studentUid,
  required String studentName,
  required String guideId,
  required Map<String, int?> scores,
  required String evidence,
  required String confidence,
  String? sourceInteractionId,
}) async {
  final problem =
      litProblem(scores: scores, evidence: evidence, confidence: confidence);
  if (problem != null) throw ArgumentError(problem);

  final ref = await GuideDb.instance.collection('litAssessments').add({
    'studentUid': studentUid,
    'studentName': studentName,
    'guideId': guideId,
    'L': scores['L'],
    'I': scores['I'],
    'T': scores['T'],
    'evidence': evidence.trim(),
    'confidence': confidence,
    'sourceInteractionId': sourceInteractionId,
    'assessedAt': FieldValue.serverTimestamp(),
  });
  return ref.id;
}

/// Corrects a saved LIT assessment: any of the three readings, the evidence or the confidence. The readings stay three
/// separate numbers; the whole result is checked again exactly as a new reading is.
Future<void> editLitAssessment(
  String id, {
  Map<String, int?> scores = const {},
  String? evidence,
  String? confidence,
}) async {
  final ref = GuideDb.instance.collection('litAssessments').doc(id);
  final snap = await ref.get();
  final data = snap.data();
  if (data == null) throw StateError('That assessment no longer exists.');
  final merged = <String, int?>{
    'L': scores['L'] ?? (data['L'] as num?)?.toInt(),
    'I': scores['I'] ?? (data['I'] as num?)?.toInt(),
    'T': scores['T'] ?? (data['T'] as num?)?.toInt(),
  };
  final newEvidence = (evidence ?? (data['evidence'] ?? '').toString()).trim();
  final newConfidence = confidence ?? (data['confidence'] ?? '').toString();
  final problem = litProblem(scores: merged, evidence: newEvidence, confidence: newConfidence);
  if (problem != null) throw ArgumentError(problem);
  await ref.update({
    'L': merged['L'],
    'I': merged['I'],
    'T': merged['T'],
    'evidence': newEvidence,
    'confidence': newConfidence,
    'editedAt': FieldValue.serverTimestamp(),
  });
}

/// Deletes a saved LIT assessment (double-confirmed in the assistant).
Future<void> deleteLitAssessment(String id) async {
  await GuideDb.instance.collection('litAssessments').doc(id).delete();
}
