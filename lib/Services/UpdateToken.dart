import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Add 'adminId' as a parameter so the function knows who is opening the app
Future<void> updateAdminFcmToken(String adminId) async {
  try {
    // Get the FCM token for this specific device
    String? fcmToken = await FirebaseMessaging.instance.getToken();

    if (fcmToken != null) {
      // Store the FCM token in Firestore under that specific admin's document
      await FirebaseFirestore.instance
          .collection('adminUsers')
          .doc(adminId) // Uses 'SBSD' or 'AMHD' dynamically
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