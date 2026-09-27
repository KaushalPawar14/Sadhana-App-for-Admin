import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AccessTokenFirebase {
  // first add endpoint url
  static String firebaseMessagingScope =
      "https://www.googleapis.com/auth/firebase.messaging";

  Future<String> getAccessToken() async {
    final String serviceAccountJsonString =
    await rootBundle.loadString('credentials/service-account.json');
    final Map<String, dynamic> serviceAccountJson =
    jsonDecode(serviceAccountJsonString);

    final client = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(
          serviceAccountJson,
        ), [firebaseMessagingScope]
    );
    final accessToken = client.credentials.accessToken.data;

    client.close(); // ✅ MUST ADD THIS

    return accessToken;
  }
}
