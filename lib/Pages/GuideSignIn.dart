import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../Services/HierarchyApi.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../Services/UpdateToken.dart';
import '../utils/BottomNavBar.dart';
import '../utils/GuideAuthGate.dart';
import '../utils/NotificationRouter.dart';
import '../utils/Snackbar.dart';
import '../widgets/GuideGate.dart';

/// The Guide app's entire "login" (Master Task, 2026-09-14 — "Replace the
/// Guide app's name picker with Google Sign-In, and add admin management").
///
/// No name list, no text field — one Google Sign-In button. Identity is
/// resolved by matching the signed-in email against `adminUsers.email`
/// ([GuideAuthGate.resolveAndPersistIdentity]), which becomes this session's
/// LOCKED guide identity: nothing in this app lets a signed-in person pick a
/// different one afterward. Same Google Sign-In package/approach as the
/// Student app's `pages/Welcome.dart` and this app's own prior version of
/// this screen (2026-09-12) — only the post-sign-in identity step changed.
class GuideSignInPage extends StatefulWidget {
  /// Shown once, immediately, if this screen was reached because a
  /// previously-valid session just failed re-resolution (removed from
  /// `adminUsers`, or their email changed) — rather than a plain first-time
  /// sign-in, which has nothing to report yet.
  final String? initialError;

  const GuideSignInPage({super.key, this.initialError});

  @override
  State<GuideSignInPage> createState() => _GuideSignInPageState();
}

class _GuideSignInPageState extends State<GuideSignInPage> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSnackbar(context, widget.initialError!, Colors.red, Icons.error);
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // Cancelled the account picker.
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final email = userCredential.user?.email;

      // Identity resolution + locking (Part 2.2/2.4) — the ONE place a
      // signed-in Google account becomes (or fails to become) a guide
      // identity. Persists to the SAME `selected_guide` pref every other
      // screen in this app already reads, so nothing downstream needed to
      // change (see `GuideAuthGate.resolveAndPersistIdentity`'s own doc
      // comment).
      String? resolvedGuide;
      try {
        resolvedGuide = await GuideAuthGate.resolveAndPersistIdentity(email);
      } on HierarchyException {
        if (!mounted) return;
        setState(() => _isLoading = false);
        showSnackbar(
          context,
          'Could not reach the server. Check your connection and try again.',
          Colors.red,
          Icons.error,
        );
        return;
      }

      if (resolvedGuide == null) {
        await GuideAuthGate.signOut();
        if (!mounted) return;
        setState(() => _isLoading = false);
        showSnackbar(
          context,
          'This account is not registered as a FOLK guide. Contact your HOD.',
          Colors.red,
          Icons.error,
        );
        return;
      }

      // FCM token registration (Part 2.7) — unchanged mechanism, now fed
      // the resolved identity instead of a picked one.
      await updateAdminFcmToken(resolvedGuide);

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CurvedNavBar(resolvedGuide!)),
      );
      // Same one-time call SplashScreen itself makes right after its own
      // navigation (main.dart) — this screen is the OTHER place that
      // performs the "enter the app" navigation, so it needs the same call
      // to flush a notification route queued during the sign-in wait.
      markAppReady();
    } on FirebaseAuthException catch (_) {
      await GuideAuthGate.signOut();
      if (!mounted) return;
      setState(() => _isLoading = false);
      showSnackbar(context, 'Sign-in failed. Please try again.', Colors.red,
          Icons.error);
    } catch (_) {
      await GuideAuthGate.signOut();
      if (!mounted) return;
      setState(() => _isLoading = false);
      showSnackbar(context, 'Sign-in failed. Please try again.', Colors.red,
          Icons.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GuideGate(
      icon: Icons.self_improvement_outlined,
      title: 'FOLK Guides',
      message: 'Sign in with your registered Google account to continue.',
      action: GuideGoogleButton(
        onPressed: _signInWithGoogle,
        loading: _isLoading,
      ),
    );
  }
}
