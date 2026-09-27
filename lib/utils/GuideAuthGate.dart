import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Services/UpdateFCM.dart';
import 'GuideRoster.dart';

/// Real authentication for the Guide app.
///
/// Master Task, 2026-09-12: added real Google Sign-In in front of the old
/// name picker, gated by an email allowlist (`guideEmails`).
///
/// Master Task, 2026-09-14 ("Replace the Guide app's name picker with
/// Google Sign-In, and add admin management") — REBUILT: the picker is
/// gone. A guide's identity is no longer self-selected at all; it is
/// resolved by matching the signed-in email against `adminUsers.email`
/// ([GuideRoster.resolveGuideIdentity]), and LOCKED for that session — there
/// is no code path anywhere in this app that lets a signed-in person become
/// a DIFFERENT guide than the one their email resolves to (see
/// `Guides/CLAUDE_PROGRESS.md` for the grep confirming this).
///
/// `guideEmails/{email}` still exists, but its role changed: it is no
/// longer a manually-curated allowlist — it's an auto-maintained MIRROR of
/// `adminUsers.email`, written only by [GuideRoster.addGuide]/
/// [GuideRoster.updateAdminEmail], read only by `firestore.rules`' own
/// `isLikelyGuide()` (which cannot query `adminUsers` directly — see that
/// file's header). Nothing in this class touches it.
class GuideAuthGate {
  GuideAuthGate._();

  /// Resolves [email] to its `adminUsers` document id (the locked guide
  /// identity) AND persists it to `SharedPreferences['selected_guide']` via
  /// [UpdateTokenService.saveSelectedGuide] — the SAME pref key every other
  /// screen in this app already reads via
  /// `UpdateTokenService().getSavedGuide()`. This is deliberate: it means
  /// none of the 18+ screens that independently call `getSavedGuide()`
  /// needed to change for this task — they simply always receive the
  /// correct, locked identity now, resolved once here rather than picked by
  /// the user.
  ///
  /// Returns the resolved name, or `null` if this email is not a registered
  /// admin — the caller must sign out and refuse entry in that case (see
  /// `Pages/GuideSignIn.dart`/`main.dart`'s `SplashScreen`).
  static Future<String?> resolveAndPersistIdentity(String? email) async {
    final resolved = await resolveGuideIdentity(email);
    if (resolved != null) {
      await UpdateTokenService().saveSelectedGuide(resolved);
    }
    return resolved;
  }

  /// Signs out of both Google and Firebase, and clears the resolved-
  /// identity pref. All three are cleared together deliberately — leaving a
  /// cached Google session behind would let `GoogleSignIn().signIn()`
  /// silently reuse it on the next attempt instead of showing the account
  /// picker (which matters most right after an unregistered-email
  /// rejection, so the person can pick a *different* Google account); a
  /// stale `selected_guide` pref left behind would be harmless in practice
  /// (nothing reads it until the NEXT successful resolve), but there is no
  /// reason to leave it dangling either.
  static Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_guide');
  }
}
