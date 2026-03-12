import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/Pages/FolkGuideSelect.dart';
import 'package:folk_guide_app/utils/BottomNavBar.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/data_range_provider.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';
import 'Services/MissingReportNotification.dart';
import 'Services/Notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  String? savedGuide = prefs.getString('selected_guide');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ColorProvider()),
        ChangeNotifierProvider(create: (_) => DateRangeProvider()),
      ],
      child: MyApp(savedGuide: savedGuide),
    ),
  );

  Future.microtask(() async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    await _requestNotificationPermissions();

    FirebaseCM firebaseCM = FirebaseCM();
    await firebaseCM.initNotifications();

    await NotificationManager().prepareMissingReports();
    await _prepareNotifications();
  });
}

class MyApp extends StatelessWidget {
  final String? savedGuide;
  const MyApp({super.key, this.savedGuide});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, deviceType) {
        final colorProvider = Provider.of<ColorProvider>(context);

        return AnimatedTheme(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          data: ThemeData(
            useMaterial3: true,
            fontFamily: 'Satoshi',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFFFD180),
              brightness: colorProvider.color == Colors.white
                  ? Brightness.light
                  : Brightness.dark,
            ),
            scaffoldBackgroundColor: colorProvider.color == Colors.white
                ? const Color(0xFFFFF8E1)
                : const Color(0xFF121212),
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Folk Sadhana',
            home: SplashScreen(savedGuide: savedGuide),
          ),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  final String? savedGuide;

  const SplashScreen({super.key, this.savedGuide});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Fade controller: 2 seconds for fade in/out
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Fade animation from 0 (invisible) to 1 (visible)
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeInOut,
      ),
    );

    // Repeat the fade-in/out animation forever
    _fadeController.repeat(reverse: true);

    // Navigate after 3 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => widget.savedGuide != null
              ? CurvedNavBar(widget.savedGuide!)
              : FolkGuideSelectionPage(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.blue.shade400],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _fadeAnimation,
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Lottie.asset(
                    'assets/emoji/splash_screen.json',
                    repeat: true,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FadeTransition(
                opacity: _fadeAnimation,
                child: const Text(
                  "Now it's easy to check Sadhana daily",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _requestNotificationPermissions() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('User granted notification permissions!');
  } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
    print('User granted provisional notification permissions.');
  } else {
    print('User denied notification permissions.');
  }
}

Future<void> _prepareNotifications() async {

  final manager = NotificationManager();

  await manager.prepareMissingReports();

  print("===== MISSING REPORT USERS =====");

  for (var user in manager.missingUsernames) {
    print(user);
  }

  print("Total Missing: ${manager.missingCount}");
}
