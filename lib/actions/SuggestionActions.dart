import '../Services/GuideAi.dart';
import '../utils/GuideDb.dart';

/// AI suggestions for a student, as shared logic with no screen in it: the profile
/// page's "Generate suggestions" button and the AI agent both go through
/// [generateStudentSuggestions].
///
/// The SERVER (OpenAI, `functions/interactionAI.js`) gathers the evidence about the student —
/// sadhana points, books, meetings, expeditions and what they wrote about them, the latest
/// interactions, the latest LIT reading as three separate lines, and the guide's own active
/// targets — asks the model, and stores the result in `holisticSuggestions/{studentUid}`.
/// It is never shown to a student.
///
/// New suggestions are also made BY THEMSELVES after every saved interaction; this is the
/// manual refresh. The server checks that the signed-in admin may manage the student.

/// Makes new suggestions for [studentUid] now. Returns how many were saved.
///
/// Throws [AiException] with a message the guide can read when the model cannot answer
/// (credit, outage) or the student is not theirs to see.
Future<int> generateStudentSuggestions({
  required String studentUid,
  GuideAi? ai,
}) =>
    (ai ?? GuideAi()).generateSuggestions(studentUid);

/// Deletes the AI suggestions made for a student (the document is keyed by the student). New ones can be generated again.
Future<void> deleteStudentSuggestions(String studentUid) async {
  await GuideDb.instance.collection('holisticSuggestions').doc(studentUid).delete();
}
