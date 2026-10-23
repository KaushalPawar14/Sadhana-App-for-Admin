import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Pages/GuideSignIn.dart';
import 'GuideAuthGate.dart';
import '../widgets/GuideDialog.dart';

/// Signs this admin out of the phone: Google and Firebase together (`GuideAuthGate.signOut`), then the
/// cached guide name goes. The screen's confirm dialog and the AI agent's confirmation card both end here;
/// what to show next (the sign-in screen) is the caller's.
Future<void> signOutThisPhone() async {
  await GuideAuthGate.signOut();
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('selected_guide');
}

/// Asks "Are you sure you want to logout?" and, on yes, signs the admin out and
/// returns to the sign-in screen. (Moved unchanged from the old bottom bar so the
/// Home screen's logout button does exactly what the old FOLK Boys tab's did.)
Future<void> confirmAndLogout(BuildContext context) async {
  final bool? confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => GuideDialog(
      title: const Text("Confirm Logout"),
      content: const Text("Are you sure you want to logout?"),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel")),
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Logout")),
      ],
    ),
  );

  if (confirm ?? false) {
    await signOutThisPhone();

    if (context.mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const GuideSignInPage()));
    }
  }
}
