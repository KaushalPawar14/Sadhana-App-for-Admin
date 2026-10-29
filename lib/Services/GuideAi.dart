import 'HierarchyApi.dart';

/// An AI failure with a message that is safe to show the guide verbatim.
class AiException implements Exception {
  final String message;

  const AiException(this.message);

  @override
  String toString() => message;
}

/// The thing the guide can still ask the AI for by hand (re-reading an interaction). Both run on the SERVER (OpenAI,
/// `functions/interactionAI.js`); the app holds no AI key and no prompt.
///
/// Everything else the AI does for a guide happens without a screen: an interaction that is
/// saved is analysed in the background, and the advice for each student is worked out inside the Today / This week plans.
class GuideAi {
  GuideAi({HierarchyApi? api}) : _api = api;

  final HierarchyApi? _api;
  HierarchyApi get _client => _api ?? HierarchyApi.instance;

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
