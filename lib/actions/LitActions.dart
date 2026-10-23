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
