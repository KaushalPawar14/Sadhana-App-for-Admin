import 'HierarchyApi.dart';

/// A Gemini failure with a message that is safe to show the guide verbatim.
class GeminiException implements Exception {
  final String message;

  const GeminiException(this.message);

  @override
  String toString() => message;
}

/// Structured extraction of a guide's interaction notes, and the next-action
/// suggestion.
///
/// Gemini runs on the SERVER now (Cloud Functions `geminiExtractInteraction` /
/// `geminiSuggestNextAction`, functions/gemini.js): the API key used to be
/// bundled in this app's package and lives only in the functions' own
/// credentials. The prompts, generation settings and the normalisation of the
/// draft are unchanged (ported line for line).
///
/// This service only ever *extracts*. It does not decide anything and never
/// produces L/I/T scores. Nothing it returns is persisted as final: everything
/// lands in `extractedDraft` and waits for the guide to approve it.
class GeminiService {
  GeminiService({HierarchyApi? api}) : _api = api;

  final HierarchyApi? _api;
  HierarchyApi get _client => _api ?? HierarchyApi.instance;

  /// The keys the draft contains, and the ones the UI reads back.
  static const List<String> draftFields = [
    'interactionType',
    'interactionDateTime',
    'durationMinutes',
    'themes',
    'studentConcerns',
    'personalRevelation',
    'commitmentsMade',
    'followUpDate',
    'abcdeEvidence',
    'possibleLitEvidence',
    'temporaryCircumstances',
    'recommendedNextAction',
    'recommendedReasoning',
    'extractionConfidence',
  ];

  /// Sends [rawText] to Gemini (via the server) and returns the draft map.
  ///
  /// Throws [GeminiException] with a guide-readable message on any failure. The
  /// caller has already persisted [rawText] — this never writes to Firestore, so
  /// a failure cannot lose notes.
  Future<Map<String, dynamic>> extractInteraction({
    required String rawText,
    required String studentName,
  }) async {
    if (rawText.trim().isEmpty) {
      throw const GeminiException("Nothing to extract — the notes are empty.");
    }
    try {
      return await _client.geminiExtractInteraction(
          rawText: rawText, studentName: studentName);
    } on HierarchyException catch (e) {
      throw GeminiException(e.message);
    } catch (e) {
      throw GeminiException("Could not reach Gemini: $e");
    }
  }

  /// ONE current suggested next action, given a student's history
  /// ([contextText] is assembled by the caller and already free of raw
  /// dictation and of any combined LIT figure).
  Future<Map<String, dynamic>> suggestNextAction({
    required String contextText,
    required String studentName,
  }) async {
    try {
      return await _client.geminiSuggestNextAction(
          contextText: contextText, studentName: studentName);
    } on HierarchyException catch (e) {
      throw GeminiException(e.message);
    } catch (e) {
      throw GeminiException("Could not reach Gemini: $e");
    }
  }
}
