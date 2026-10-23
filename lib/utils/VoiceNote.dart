import '../Services/HierarchyApi.dart';

/// Speak a note, get clean English text (Master Part 3).
///
/// The logic of the mic button, with no widget and no microphone in it, so it
/// can be tested on its own. The button itself is `widgets/VoiceNoteButton`.

/// The longest a recording may run: three minutes. The server enforces the same
/// number with a little slack, because the server is the one that cannot be
/// talked out of it.
const int kMaxVoiceSeconds = 180;

/// What a recording is for. Passed to the server so the model writes the note
/// the right way; unknown values fall back there.
enum VoicePurpose {
  interaction('interaction'),
  associationNote('association_note');

  const VoicePurpose(this.wire);
  final String wire;
}

/// "0:07", "2:05", "3:00".
String formatElapsed(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

/// Puts [clean] into a field that may already hold something.
///
/// Appended after what is there, on a new paragraph, never replacing it: a
/// guide who typed two lines and then spoke a third wants all three. Into an
/// empty field it is just the text.
String appendNote(String existing, String clean) {
  final add = clean.trim();
  if (add.isEmpty) return existing;
  final base = existing.trimRight();
  if (base.isEmpty) return add;
  return '$base\n\n$add';
}

/// The microphone is not allowed. A separate type so the screen can explain how
/// to turn it back on instead of calling it an error.
class MicPermissionDenied implements Exception {
  const MicPermissionDenied();
  @override
  String toString() => 'The microphone is not allowed.';
}

/// What to tell the guide when the mic has been refused.
const String kMicDeniedMessage =
    "FOLK Guides can't use the microphone. To speak a note, allow it in your "
    "phone's Settings → Apps → FOLK Guides → Permissions → Microphone. "
    "You can still type the note.";

/// A message a guide can act on, for anything that goes wrong between tapping
/// the mic and getting text back. Never a stack trace and never a bare code.
String voiceFailureMessage(Object error) {
  if (error is MicPermissionDenied) return kMicDeniedMessage;

  if (error is HierarchyException) {
    switch (error.code) {
      // The server's own sentence is already written for this: "I couldn't make
      // that out…", "You've used a lot of voice notes this hour…".
      case 'failed-precondition':
      case 'resource-exhausted':
        return error.message;
      case 'unauthenticated':
      case 'permission-denied':
        return 'Your sign-in has lapsed — sign in again, then try the mic.';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
        return "Couldn't reach the server just now. Check your connection and "
            'try again.';
      default:
        return error.message.isEmpty
            ? "That didn't work. Please try again."
            : error.message;
    }
  }

  return "That didn't work. Please try again, or type the note.";
}

/// Whether a failure is worth a Retry that sends the SAME recording again.
///
/// A recording the model could not make out will not be better the second
/// time, and a refused mic has no recording at all — those need a fresh start.
/// A connection or server hiccup is exactly what a retry is for.
bool canRetrySameClip(Object error) {
  if (error is HierarchyException) {
    return const {'unavailable', 'deadline-exceeded', 'internal'}
        .contains(error.code);
  }
  return false;
}
