import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/GuideRoster.dart';

// The guide the CURRENT Firebase session really belongs to: the signed-in
// account's email resolved against `adminUsers.email`. Null when nobody is
// signed in or the email is not a registered guide. Never read from the cached
// `selected_guide` pref, which is only a copy of an earlier resolution.
Future<String?> _signedInGuideId() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return resolveGuideIdentity(user.email);
}

// Writes this device's FCM token to the guide's own `adminUsers` document, but
// only when that guide is genuinely signed in on this device. The last device a
// guide signs in or launches on holds the token and receives notifications.
Future<void> updateAdminFcmToken(String adminId) async {
  try {
    final signedIn = await _signedInGuideId();
    if (signedIn == null || signedIn != adminId) return;

    // Get the FCM token for this specific device
    String? fcmToken = await FirebaseMessaging.instance.getToken();

    if (fcmToken != null) {
      // Store the FCM token in Firestore under that specific admin's document
      await FirebaseFirestore.instance
          .collection('adminUsers')
          .doc(adminId)
          .set(
        {'fcmToken': fcmToken},
        SetOptions(merge: true), // Ensures you don't delete their other data
      );

      print('FCM token updated successfully for $adminId');
    } else {
      print('Failed to retrieve FCM token.');
    }
  } catch (e) {
    print('Error updating FCM token for $adminId: $e');
  }
}

StreamSubscription<String>? _tokenRefreshSub;

// FCM rotates tokens on its own (reinstall, restored data, expiry). Keep the
// signed-in guide's stored token current; does nothing while nobody is signed
// in, since the next sign-in writes the token anyway. Safe to call repeatedly.
void listenForAdminFcmTokenRefresh() {
  _tokenRefreshSub ??=
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    try {
      final guideId = await _signedInGuideId();
      if (guideId == null) return;
      await FirebaseFirestore.instance
          .collection('adminUsers')
          .doc(guideId)
          .set({'fcmToken': token}, SetOptions(merge: true));
    } catch (e) {
      print('Error refreshing FCM token: $e');
    }
  });
}

// On sign-out: remove the signed-in guide's stored token, but only if it is
// still THIS device's token, so signing out here never silences a device the
// guide signed in on later. Never blocks or fails the sign-out itself.
Future<void> clearAdminFcmTokenIfOurs() async {
  try {
    final guideId = await _signedInGuideId();
    if (guideId == null) return;

    final ownToken = await FirebaseMessaging.instance.getToken();
    if (ownToken == null) return;

    final ref =
        FirebaseFirestore.instance.collection('adminUsers').doc(guideId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.data()?['fcmToken'] == ownToken) {
        tx.update(ref, {'fcmToken': FieldValue.delete()});
      }
    }).timeout(const Duration(seconds: 5));
  } catch (e) {
    print('Could not clear FCM token on sign-out: $e');
  }
}
