import '../theme/GuideColors.dart';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/NotificationRouter.dart';

// Handle background notifications. Called by Firebase Messaging from native code, in
// its own isolate, so it must be a TOP-LEVEL function (it was an instance method,
// which Firebase cannot call) carrying this pragma (a release/AOT build removes
// anything unannotated). Same body as before.
@pragma('vm:entry-point')
Future<void> handleBG(RemoteMessage message) async {
  print("Received background message: ${message.notification?.title}");
  if (message.notification != null) {
    await FirebaseCM().showLocalNotification(message);
  }
}

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
        android: AndroidInitializationSettings('@drawable/ic_stat_notification'),
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
          // The small icon is a white glyph on transparent (Android draws it as a
          // silhouette); the full-colour logo is the large icon.
          icon: 'ic_stat_notification',
          color: GuideColors.notificationAccent, // brass
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
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

}
