import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'AccessToken.dart';
import '../utils/NotificationRouter.dart';

class FirebaseCM {
  final FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
  final AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'notification', // ID
    'notification', // Name
    importance: Importance.max,
    playSound: true,
    showBadge: true,
  );

  // Initialize notifications
  Future<void> initNotifications() async {
    // Request permission for notifications
    NotificationSettings settings = await firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      print('Permission denied');
    }

    // Initialize the notification plugin
    await localNotifications.initialize(
      InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      // Deep-link routing (Master Task, 2026-09-10 — Part 3) — the ONE
      // launch state `getInitialMessage()`/`onMessageOpenedApp` below
      // cannot cover: the app already in the FOREGROUND when a
      // notification arrives, which shows a LOCAL notification instead
      // (`showLocalNotification`) whose tap was previously never handled
      // at all. `payload` is `message.data` JSON-encoded (see
      // `showLocalNotification`'s own updated comment), decoded back into
      // a map here.
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload);
          if (data is Map) {
            routeNotification(Map<String, dynamic>.from(data));
          }
        } catch (_) {
          // Malformed payload — fails safe, same as an unrecognised `dest`.
        }
      },
    );

    // Listen for messages in the background
    FirebaseMessaging.onBackgroundMessage(handleBG); // Background handler
    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen(handleForegroundNotification); // Foreground handler
    FirebaseMessaging.onMessageOpenedApp.listen(handleMessageClick); // When the notification is clicked

    // Handle the initial message when the app is opened from a terminated state
    firebaseMessaging.getInitialMessage().then(handleMessageClick);
  }

  // Handle background notifications
  Future<void> handleBG(RemoteMessage message) async {
    print("Received background message: ${message.notification?.title}");
    if (message.notification != null) {
      await showLocalNotification(message);
    }
  }

  // Handle notifications in the foreground
  Future<void> handleForegroundNotification(RemoteMessage message) async {
    print("Received foreground message: ${message.notification?.title}");
    if (message.notification != null) {
      await showLocalNotification(message);
    }
  }

  // Show the notification locally using flutter_local_notifications
  Future<void> showLocalNotification(RemoteMessage message) async {
    await localNotifications.show(
      0, // Notification ID
      message.notification?.title, // Notification Title
      message.notification?.body, // Notification Body
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.high,
          showWhen: false,
        ),
      ),
      // Carries the SAME routing data this message arrived with (Master
      // Task, 2026-09-10 — Part 3), so a tap on this locally-shown
      // notification (the foreground case) routes exactly like a tap on
      // a real system notification does.
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
    );
  }

  // Handle notification clicks
  void handleMessageClick(RemoteMessage? message) {
    if (message != null) {
      print("Notification clicked: ${message.notification?.title}");
      routeNotification(message.data);
    }
  }

  // Send token notification to the admin (from the user app)
  //
  // [data] — deep-link routing payload (Master Task, 2026-09-10 — Part 3),
  // optional and additive: every existing call site that doesn't pass it
  // keeps sending exactly the notification it always did. FCM's REST `send`
  // API requires `data` values to be strings, same as the Cloud Functions
  // SDK's own `getMessaging().send({data})` — enforced here by the
  // parameter's own type rather than left to each caller to remember.
  Future<void> sendTokenNotification(
    String token,
    String title,
    String message, {
    Map<String, String>? data,
  }) async {
    try {
      final body = {
        'message': {
          'token': token,
          'notification': {
            'body': message,
            'title': title,
          },
          if (data != null) 'data': data,
        },
      };

      String url = 'https://fcm.googleapis.com/v1/projects/folk-sadhana-app/messages:send';
      String accessKey = await AccessTokenFirebase().getAccessToken();

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
    } catch (e) {
      print('Error sending notification: $e');
    }
  }
}
