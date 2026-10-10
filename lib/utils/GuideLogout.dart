import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Pages/GuideSignIn.dart';
import 'GuideAuthGate.dart';

/// Asks "Are you sure you want to logout?" and, on yes, signs the admin out and
/// returns to the sign-in screen. (Moved unchanged from the old bottom bar so the
/// Home screen's logout button does exactly what the old FOLK Boys tab's did.)
Future<void> confirmAndLogout(BuildContext context) async {
  final bool? confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
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
    // Google + Firebase sign-out together (`GuideAuthGate.signOut`), then the
    // cached guide name goes, and the sign-in screen replaces everything.
    await GuideAuthGate.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_guide');

    if (context.mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const GuideSignInPage()));
    }
  }
}
