import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> initializeNotifications() async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

Future<void> showNotification() async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  const AndroidNotificationDetails androidPlatformChannelSpecifics =
  AndroidNotificationDetails(
    'Data_submission_channel', // Channel ID
    'Data Submission Notifications', // Channel Name
    channelDescription: 'Notifications related to data submissions',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'ticker',
  );

  const NotificationDetails platformChannelSpecifics =
  NotificationDetails(android: androidPlatformChannelSpecifics);

  // final currentUser = FirebaseAuth.instance.currentUser;
  // final userDoc = await FirebaseFirestore.instance
  //     .collection('users')
  //     .doc(currentUser?.uid)
  //     .get();
  //
  // String userName = userDoc.data()?['name'] ?? 'Unknown User';

  await flutterLocalNotificationsPlugin.show(
    0, // Notification ID
    'Hare Krishna Prabhu 🙏', // Notification Title
    "Fill up your today's Sadhana report 📝", // Notification Content (entered data)
    platformChannelSpecifics,
    payload: 'item x',
  );
}