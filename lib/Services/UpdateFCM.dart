import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateTokenService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String?> getFCMToken() async {
    return await FirebaseMessaging.instance.getToken();
  }

  // Save selected guide locally
  Future<void> saveSelectedGuide(String guide) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_guide', guide);
  }

  // Get saved guide
  Future<String?> getSavedGuide() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_guide');
  }

  // Update FCM token for guide in Firestore
  Future<void> updateTokenForGuide(String guide) async {
    String? fcmToken = await FirebaseMessaging.instance.getToken();

    if (fcmToken == null) {
      print("⚠️ FCM token is null, trying again...");
      fcmToken = await FirebaseMessaging.instance.getToken(); // retry
      if (fcmToken == null) {
        print("❌ Still null. Cannot update Firestore.");
        return;
      }
    }

    try {
      await _firestore.collection('notification').doc(guide).set({
        'FCMToken': fcmToken,
      }, SetOptions(merge: true));

      print("✅ Token updated for $guide: $fcmToken");
    } catch (e) {
      print("❌ Failed to update token: $e");
    }
  }
}
