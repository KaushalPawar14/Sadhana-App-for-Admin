import 'package:googleapis_auth/auth_io.dart';

class AccessTokenFirebase {
  // first add endpoint url
  static String firebaseMessagingScope =
      "https://www.googleapis.com/auth/firebase.messaging";

  Future<String> getAccessToken() async {
    final client = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(
          {
            
          },
        ), [firebaseMessagingScope]
    );
    final accessToken = client.credentials.accessToken.data;

    client.close(); // ✅ VERY IMPORTANT

    return accessToken;
  }
}
