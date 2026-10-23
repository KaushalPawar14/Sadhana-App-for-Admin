import '../utils/GuideDb.dart';

/// Flagged student chat messages, as a shared write with no screen in it: the Flagged
/// Messages screen and the AI agent both mark a message reviewed through this.
///
/// Deleting flagged messages is `confirmAndDeleteSelected` (utils/SelectableDelete.dart).

/// Marks one flagged message reviewed (or, with [reviewed] false, unreviewed). It
/// changes that one field and nothing else; the student's message is never touched.
Future<void> markFlaggedReviewed(String messageId, bool reviewed) async {
  await GuideDb.instance
      .collection('flaggedChatMessages')
      .doc(messageId)
      .update({'reviewed': reviewed});
}
