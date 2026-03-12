import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:folk_guide_app/Services/AccessToken.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

class MissingReportService {

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  String getTodayDateId() {
    return DateFormat('dd-MM-yyyy').format(DateTime.now());
  }

  Future<List<String>> fetchMissingTokens() async {

    final today = getTodayDateId();

    final notificationSnapshot =
    await firestore.collection('notification').get();

    NotificationManager().missingUsernames.clear(); // <-- clear first

    List<Future<String?>> futures = [];

    for (final doc in notificationSnapshot.docs) {

      Future<String?> task() async {

        final username = doc.id;

        final dateRef = firestore
            .collection('sadhana-reports')
            .doc(username)
            .collection('dates')
            .doc(today);

        final reportDoc = await dateRef.get();

        if (!reportDoc.exists) {

          final token = doc.data()['FCMToken'];

          if (token != null && token.toString().isNotEmpty) {

            NotificationManager().missingUsernames.add(username);

            return token;
          }
        }

        return null;
      }

      futures.add(task());
    }

    final results = await Future.wait(futures);

    return results.whereType<String>().toList();
  }

}

class NotificationSenderService {

  Future<void> sendNotification(
      List<String> tokens,
      String title,
      String body,
      ) async {

    final accessToken = await AccessTokenFirebase().getAccessToken();

    const projectId = "folk-sadhana-app";

    List<Future> requests = [];

    for (String token in tokens) {

      final url = Uri.parse(
          "https://fcm.googleapis.com/v1/projects/$projectId/messages:send");

      final payload = {
        "message": {
          "token": token,
          "notification": {
            "title": title,
            "body": body
          }
        }
      };

      requests.add(
        http.post(
          url,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $accessToken",
          },
          body: jsonEncode(payload),
        ),
      );
    }

    await Future.wait(requests);
  }
}

class NotificationManager {

  static final NotificationManager _instance =
  NotificationManager._internal();

  factory NotificationManager() => _instance;

  NotificationManager._internal();

  List<String> _cachedTokens = [];
  List<String> missingUsernames = [];
  bool _isPrepared = false;

  Future<void> prepareMissingReports() async {

    _cachedTokens =
    await MissingReportService().fetchMissingTokens();
    _isPrepared = true;
  }

  Future<void> sendReminder(String title, String message) async {

    if (!_isPrepared) {
      await prepareMissingReports();
    }

    if (_cachedTokens.isEmpty) {
      return;
    }

    // _cachedTokens = ['cWY8ArNLQYeoMwjMDYzxaL:APA91bGgpkujolJKt45FkENG-PhsrmdMSWcHirSj4MX9YeeDmFlVrOzZYo9YziiRxdWZasW8C9KNxGiDcmhphE3MRKLH0tGJ4dd4KacTL4_kTqMrG73y3KI'];

    await NotificationSenderService()
        .sendNotification(_cachedTokens, title, message);
  }

  int get missingCount => _cachedTokens.length;

}