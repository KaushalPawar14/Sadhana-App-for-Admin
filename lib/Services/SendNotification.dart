import 'dart:convert';
import 'package:http/http.dart' as http;

import 'AccessToken.dart';

class SendNotificationService {

  Future<void> sendTokenNotification(List<String> tokens, String title, String message) async {
    try {
      String url = 'https://fcm.googleapis.com/v1/projects/folk-sadhana-app/messages:send';
      String accessKey = await AccessTokenFirebase().getAccessToken();

      for (String token in tokens) {
        final body = {
          'message': {
            'token': token,
            'notification': {
              'body': message,
              'title': title,
            },
          },
        };

        await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessKey',
          },
          body: jsonEncode(body),
        ).then((value) {
          print('Status code ${value.statusCode}');
        });
      }
    } catch (e) {
      print(e);
    }
  }
}
