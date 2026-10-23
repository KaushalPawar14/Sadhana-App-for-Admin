import 'HierarchyApi.dart';

/// An AI failure with a message that is safe to show the guide verbatim.
class AiException implements Exception {
  final String message;

  const AiException(this.message);

  @override
  String toString() => message;
}

/// The two things the guide can still ask the AI for by hand. Both run on the SERVER (OpenAI,
/// `functions/interactionAI.js`); the app holds no AI key and no prompt.
///
/// Everything else the AI does for a guide happens without a screen: an interaction that is
/// saved is analysed in the background and new suggestions for that student follow by themselves.
class GuideAi {
  GuideAi({HierarchyApi? api}) : _api = api;

  final HierarchyApi? _api;
  HierarchyApi get _client => _api ?? HierarchyApi.instance;

  /// Makes new suggestions for [studentUid] now ("Generate / Refresh suggestions").
  /// The server stores them where the profile reads them; returns how many.
  Future<int> generateSuggestions(String studentUid) async {
    try {
      return await _client.generateStudentSuggestions(studentUid);
    } on HierarchyException catch (e) {
      throw AiException(e.message);
    } catch (e) {
      throw AiException('Could not reach the AI: $e');
    }
  }

  /// Runs the analysis again over an interaction whose original notes are still stored.
  /// The server saves the result; this only reports whether it worked.
  Future<void> reanalyse(String interactionId) async {
    try {
      await _client.analyseInteraction(interactionId);
    } on HierarchyException catch (e) {
      throw AiException(e.message);
    } catch (e) {
      throw AiException('Could not reach the AI: $e');
    }
  }
}
