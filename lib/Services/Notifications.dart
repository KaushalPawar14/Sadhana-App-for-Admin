import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'AccessToken.dart';

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
    );
  }

  // Handle notification clicks
  void handleMessageClick(RemoteMessage? message) {
    if (message != null) {
      print("Notification clicked: ${message.notification?.title}");
      // Navigate to a specific screen or perform an action
    }
  }

  // Send token notification to the admin (from the user app)
  Future<void> sendTokenNotification(String token, String title, String message) async {
    try {
      final body = {
        'message': {
          'token': token,
          'notification': {
            'body': message,
            'title': title,
          },
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
