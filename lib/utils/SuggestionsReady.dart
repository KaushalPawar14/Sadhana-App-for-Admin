import 'package:cloud_firestore/cloud_firestore.dart';

import 'GuideDb.dart';
import 'SeenMarkers.dart';

/// "NEW SUGGESTIONS READY" — the orange dot trail for the suggestions the server makes by itself.
///
/// After every interaction a guide saves, the server analyses it and writes new suggestions for that
/// student to `holisticSuggestions/{studentUid}` with `generatedBy: 'auto'`, and tells the student's
/// guide ("New suggestions ready for <student>"). The trail follows the suggestions themselves, never
/// the push: they are "unseen" while they were made by the server and this admin has not OPENED them
/// since (`seenMarkers/{adminId}.suggestionsReady.{studentUid}` older than `generatedAt`). Swiping the
/// notification away changes nothing; reading the suggestions — or tapping the label under the
/// student's picture on their profile — clears it, and a newer batch lights it again.
///
/// Where it shows, from the outside in: the Home tab of the bottom bar → the FOLK Boys board entry → the
/// profile (person) icon on that student's card → the label under the picture on the student's profile.
/// A refresh the guide asks for by hand (`generatedBy` is their own id) never lights it: they are looking.
class SuggestionsReady {
  /// `seenMarkers/{adminId}.suggestionsReady.{studentUid}`.
  static const String featureKey = 'suggestionsReady';

  /// What the label says, wherever it appears.
  static const String label = 'New suggestions ready';

  /// The notification's `dest`.
  static const String dest = 'guide_suggestions';

  /// Whether a `holisticSuggestions` document is unseen for an admin whose marker for that student is [seenAt].
  static bool isUnseen(Map<String, dynamic>? data, Timestamp? seenAt) {
    if (data == null || data['generatedBy'] != 'auto') return false;
    final at = data['generatedAt'];
    if (at is! Timestamp) return false;
    return seenAt == null || at.compareTo(seenAt) > 0;
  }

  /// Live: does [studentUid]'s suggestions card carry the label for [guide]. Hoist the stream (build it once).
  static Stream<bool> unseenFor(String guide, String studentUid) {
    if (guide.isEmpty || studentUid.isEmpty) return Stream.value(false);
    final latest = GuideDb.instance
        .collection('holisticSuggestions')
        .doc(studentUid)
        .snapshots()
        .map((doc) {
      final d = doc.data();
      final at = d?['generatedAt'];
      return d != null && d['generatedBy'] == 'auto' && at is Timestamp ? at : null;
    });
    return SeenMarkers.unseenFrom(latest, SeenMarkers.seenAtSub(guide, featureKey, studentUid));
  }

  /// The guide opened these suggestions: the dot trail for this student clears (a newer batch shows again).
  static Future<void> markOpened(String guide, String studentUid) =>
      SeenMarkers.markSeenSub(guide, featureKey, studentUid);
}
