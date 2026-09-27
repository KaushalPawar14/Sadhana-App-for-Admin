import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:folk_guide_app/Services/AccessToken.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../utils/SadhanaReportSource.dart';

class MissingReportService {

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  String getTodayDateId() {
    return DateFormat('dd-MM-yyyy').format(DateTime.now());
  }

  Future<List<String>> fetchMissingTokens() async {

    final today = getTodayDateId();

    final notificationSnapshot =
    await firestore.collection('notification').get();

    // Master Task 2026-09-11 — no longer needs a `users` roster read to
    // resolve each name's role: `fetchMergedDateReport` below checks both
    // sadhana collections directly instead of picking one by role, so the
    // per-name role lookup this used to feed is gone along with the read
    // that built it.
    NotificationManager().missingUsernames.clear(); // <-- clear first

    List<Future<String?>> futures = [];

    for (final doc in notificationSnapshot.docs) {

      Future<String?> task() async {

        final username = doc.id;

        // Master Task 2026-09-11 — checked against BOTH collections rather
        // than picking one by current role: a guide changing a student's
        // residence during the day must not make an already-submitted
        // report for today look "missing" just because it was filed under
        // the residence's collection from earlier that same day. See
        // utils/SadhanaReportSource.dart's own header.
        final report = await fetchMergedDateReport(username, today);

        if (report == null) {

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
          },
          'android': {
            'priority': 'HIGH'
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

    for (var request in requests) {
      final response = await request;

      print("Status: ${response.statusCode}");
      print("Body: ${response.body}");
    }
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

  /// ⚠️ **CURRENTLY UNREACHABLE — no caller anywhere (as of 2026-08-14).**
  ///
  /// Its only call site was the Admin Hub's "Send Notification" tile in
  /// `BoysDetails.dart`, which was **deliberately removed** — that tile fired
  /// a bulk push to every student missing today's report on a single tap, with
  /// no confirmation, and it duplicated the deployed `dailySadhanaReminder`
  /// Cloud Function that already sends the same message at 08:00 IST.
  ///
  /// **Kept on purpose, not overlooked**, in case a manual bulk send is wanted
  /// again. If it is ever re-wired, give it a confirmation dialog first — the
  /// per-student and "Remind All" buttons on `SubmissionStatusPage` are the
  /// supported manual path today, and the bulk one does confirm.
  ///
  /// ⚠️ Everything else in this file is **live and load-bearing**:
  /// `prepareMissingReports()`, `missingUsernames`, `missingCount` and
  /// `MissingReportService.fetchMissingTokens()` are used by `main.dart`,
  /// `SubmissionStatus.dart`, `WeeklyPlanning.dart` and `PriorityStudents.dart`.
  /// Do not delete this class or the service because this one method is idle.
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