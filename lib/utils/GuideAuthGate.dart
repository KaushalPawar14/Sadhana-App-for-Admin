import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Services/UpdateFCM.dart';
import '../Services/UpdateToken.dart';
import 'AdminProfile.dart';

/// Real authentication for the Guide app.
///
/// Master Task, 2026-09-12: added real Google Sign-In in front of the old
/// name picker, gated by an email allowlist (`guideEmails`).
///
/// Master Task, 2026-09-14 ("Replace the Guide app's name picker with
/// Google Sign-In, and add admin management") — REBUILT: the picker is
/// gone. A guide's identity is no longer self-selected at all; it is
/// resolved by matching the signed-in email against `adminUsers.email`
/// (the `getAdminProfile` callable), and LOCKED for that session — there
/// is no code path anywhere in this app that lets a signed-in person become
/// a DIFFERENT guide than the one their email resolves to (see
/// `Guides/CLAUDE_PROGRESS.md` for the grep confirming this).
///
/// `guideEmails/{email}` still exists, but its role changed: it is no
/// longer a manually-curated allowlist — it's an auto-maintained MIRROR of
/// `adminUsers.email`, written only by the `addAdmin` / `updateAdmin` callables, read only by `firestore.rules`' own
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
    if (email == null || email.trim().isEmpty) return null;
    // The server resolves who this is (from the sign-in itself) and returns the
    // profile: role, display name, team, preferences. A non-admin gets null; a
    // transient failure throws HierarchyException so the caller can keep the
    // session and retry instead of signing a real admin out.
    final profile = await AdminProfileProvider.instance.load();
    if (profile != null) {
      await UpdateTokenService().saveSelectedGuide(profile.id);
    }
    return profile?.id;
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
    // Before the session ends, so the signed-in guide can still be resolved.
    await clearAdminFcmTokenIfOurs();
    if (!kIsWeb) await GoogleSignIn().signOut(); // in a browser Firebase Auth's own sign-out is the whole of it
    await FirebaseAuth.instance.signOut();
    AdminProfileProvider.instance.clear();
    await AdminProfileProvider.instance.clearCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_guide');
  }
}
