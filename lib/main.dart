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

import 'Services/UpdateToken.dart';
import 'Services/FolkIdentityService.dart';
import 'config/AppConfiguration.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  String? savedGuide = prefs.getString('selected_guide');
  await FolkIdentityService.initialize();

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

    if (savedGuide != null) {
      await updateAdminFcmToken(savedGuide);
    }

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
            home: AppConfiguration.canUsePrivatePreview
                ? const CurvedNavBar('Subala Sundar Das')
                : AppConfiguration.googleOnlyAuthEnabled
                    ? GuideIdentityGate(savedGuide: savedGuide)
                    : SplashScreen(savedGuide: savedGuide),
          ),
        );
      },
    );
  }
}

class GuideIdentityGate extends StatefulWidget {
  final String? savedGuide;
  const GuideIdentityGate({super.key, this.savedGuide});

  @override
  State<GuideIdentityGate> createState() => _GuideIdentityGateState();
}

class _GuideIdentityGateState extends State<GuideIdentityGate> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    final user = FolkIdentityService.currentUser;
    if (user == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.supervisor_account, size: 72),
                const SizedBox(height: 20),
                const Text(
                  'FOLK Guide',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sign in with the Google account authorized by the FOLK HOD.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          try {
                            await FolkIdentityService.signInWithGoogle();
                          } finally {
                            if (mounted) setState(() => isLoading = false);
                          }
                        },
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Continue with Google'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: FolkIdentityService.loadCurrentProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final role = snapshot.data?['role'];
        if (role != 'guide' && role != 'hod') {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This Google account has not been assigned as a FOLK guide.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return SplashScreen(savedGuide: widget.savedGuide);
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
                    fontFamily: 'PlayfairDisplay', // elegant serif font
                    color: Colors.white,
                    fontSize: 20, // slightly larger
                    fontWeight: FontWeight.w700, // bold for emphasis
                    letterSpacing: 1.2, // spacing between letters
                    height: 1.3, // line height
                    shadows: [
                      Shadow(
                        offset: Offset(2, 2),
                        blurRadius: 4,
                        color: Colors.black26, // subtle shadow
                      ),
                    ],
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
