import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'HierarchyApi.dart';

// The admin FCM token now lives in `adminTokens/{id}`, written ONLY by the
// server (callables registerAdminToken / clearAdminToken), which works out who
// the caller is from their sign-in. The app no longer reads or writes
// `adminUsers` or any token document itself.

// Registers this device's FCM token for the signed-in admin. The last device an
// admin signs in or launches on holds the token and receives notifications.
Future<void> updateAdminFcmToken(String adminId) async {
  if (kIsWeb) return; // no push notifications in the browser
  try {
    if (FirebaseAuth.instance.currentUser == null) return;
    final String? fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken == null) {
      print('Failed to retrieve FCM token.');
      return;
    }
    await HierarchyApi.instance.registerAdminToken(fcmToken);
    print('FCM token registered for $adminId');
  } catch (e) {
    print('Error registering FCM token for $adminId: $e');
  }
}

StreamSubscription<String>? _tokenRefreshSub;

// FCM rotates tokens on its own (reinstall, restored data, expiry). Keep the
// signed-in admin's stored token current; does nothing while nobody is signed
// in, since the next sign-in registers the token anyway. Safe to call repeatedly.
void listenForAdminFcmTokenRefresh() {
  if (kIsWeb) return;
  _tokenRefreshSub ??=
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      await HierarchyApi.instance.registerAdminToken(token);
    } catch (e) {
      print('Error refreshing FCM token: $e');
    }
  });
}

// On sign-out: remove this admin's stored token, but only if it is still THIS
// device's token (the server compares), so signing out here never silences a
// device the admin signed in on later. Never blocks or fails the sign-out.
Future<void> clearAdminFcmTokenIfOurs() async {
  if (kIsWeb) return;
  try {
    if (FirebaseAuth.instance.currentUser == null) return;
    final ownToken = await FirebaseMessaging.instance.getToken();
    if (ownToken == null) return;
    await HierarchyApi.instance
        .clearAdminToken(ownToken)
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    print('Could not clear FCM token on sign-out: $e');
  }
}
