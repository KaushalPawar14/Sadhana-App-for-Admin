import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void updateAdminFcmToken() async {
  try {
    // Get the FCM token for the admin device
    String? adminToken = await FirebaseMessaging.instance.getToken();

    if (adminToken != null) {
      // Store the FCM token in Firestore under the 'admin' document
      await FirebaseFirestore.instance.collection('adminUsers').doc('SBSD').set({
        'fcmToken': adminToken
      });
      print('Admin FCM token updated successfully: $adminToken');
    } else {
      print('Failed to retrieve FCM token.');
    }
  } catch (e) {
    print('Error updating FCM token: $e');
  }
}
