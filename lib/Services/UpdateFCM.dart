import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

class UpdateTokenService {

  Future<String?> getFCMToken() async {
    if (kIsWeb) return null; // no push notifications in the browser
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
}
