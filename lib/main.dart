import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/utils/BottomNavBar.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/data_range_provider.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';
import 'utils/AdminProfile.dart';
import 'utils/InstallSource.dart';
import 'Pages/NonPlayInstallScreen.dart';
import 'Services/HierarchyApi.dart';
import 'Services/Notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';

import 'Pages/ForceUpdateScreen.dart';
import 'Pages/GuideSignIn.dart';
import 'Services/UpdateToken.dart';
import 'utils/ForceUpdateCheck.dart';
import 'utils/GuideAuthGate.dart';
import 'utils/NotificationRouter.dart';

/// Deep-link routing (Master Task, 2026-09-10 — Part 3). Unlike the
/// Student app, this app has exactly one `MaterialApp` (below) and its
/// `SplashScreen` pushes onto that SAME Navigator via a plain
/// `pushReplacement` — no nested inner `MaterialApp` to worry about.
/// `utils/NotificationRouter.dart` uses this same key rather than
/// declaring its own.
final GlobalKey<NavigatorState> guideNavigatorKey = GlobalKey<NavigatorState>();

// Called by Firebase Messaging from native code (see `handleBG` in
// Services/Notifications.dart): top-level, and annotated so a release (AOT) build
// keeps it.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  String? savedGuide = prefs.getString('selected_guide');

  // Force-update bug fix, 2026-09-16 — moved out of the post-runApp()
  // microtask below and awaited HERE instead. `SplashScreen.initState()`
  // (built synchronously as part of `runApp()`, right below) calls
  // `ForceUpdateCheck.isUpdateRequired()`, which touches
  // `FirebaseFirestore.instance` immediately. With `Firebase.initializeApp()`
  // deferred to a microtask that hadn't even been scheduled yet at that
  // point, that call threw every launch (`Firebase.app()` "throws if the
  // app does not exist" — firebase_core's own contract), and
  // `ForceUpdateCheck`'s own fail-open catch silently swallowed it — see
  // that file's header. Matches the Student app's `main.dart`, which
  // already awaits this before `runApp()`.
  await Firebase.initializeApp();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ColorProvider()),
        ChangeNotifierProvider<AdminProfileProvider>.value(
            value: AdminProfileProvider.instance),
        ChangeNotifierProvider(create: (_) => DateRangeProvider()),
      ],
      child: MyApp(savedGuide: savedGuide),
    ),
  );

  // Everything below only needs Firebase to already exist (guaranteed now)
  // and has no bearing on the first frame or the force-update check, so it
  // stays deferred exactly as before — permission dialogs, FCM token
  // registration and missing-report computation still don't block first
  // paint.
  Future.microtask(() async {
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    await _requestNotificationPermissions();

    FirebaseCM firebaseCM = FirebaseCM();
    await firebaseCM.initNotifications();

    // The token itself is written only after a real sign-in (SplashScreen /
    // GuideSignInPage), never from the cached `selected_guide`.
    listenForAdminFcmTokenRefresh();

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
            navigatorKey: guideNavigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'FOLK Guides',
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

  /// Follow-up task, 2026-09-10 — kicked off HERE, concurrently with the
  /// splash's own timer below, so it costs no extra visible delay in the
  /// common case: a Firestore round trip comfortably finishes inside the
  /// existing 4-second window, and a slow/failed one still resolves
  /// (fails open) via its own timeout by the time that timer fires.
  late final Future<bool> _forceUpdateCheck;

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

    _forceUpdateCheck = ForceUpdateCheck.isUpdateRequired();

    // Navigate after 3 seconds
    Future.delayed(const Duration(seconds: 4), () async {
      if (!mounted) return;

      // Decided at the SAME point splash already decides where to go, so
      // the update screen wins outright — whichever branch below fires is
      // the ONLY navigation this splash screen ever performs.
      // `markAppReady()` (the one thing that can flush a queued
      // notification route — see `utils/NotificationRouter.dart`) is
      // called ONLY on the normal branch below. Skipping it in the
      // force-update branch means a notification tapped while an update
      // is required simply stays queued — it can never fire underneath or
      // after this blocking screen, because nothing ever unblocks it.
      final mustUpdate = await _forceUpdateCheck;
      if (!mounted) return;

      if (mustUpdate) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ForceUpdateScreen()),
        );
        return;
      }

      // Real-auth gate, REBUILT — Master Task, 2026-09-14 ("Replace the
      // Guide app's name picker with Google Sign-In, and add admin
      // management"). The picker (`FolkGuideSelectionPage`) is gone from
      // this decision entirely; identity is resolved fresh from
      // `adminUsers` every launch, never taken on trust from the cached
      // `selected_guide` pref. Three cases:
      //  1. Nobody signed in yet (fresh install, or after a real logout) —
      //     go to the sign-in screen; no error, this is the normal
      //     first-launch state.
      //  2. Signed in, but their email no longer resolves to any
      //     `adminUsers` document (removed, or their email changed since
      //     last launch) — force a sign-out so no stale session lingers,
      //     then go to the sign-in screen WITH an explanation.
      //  3. Signed in AND resolved — proceeds straight to that guide's
      //     shell. Firebase Auth sessions persist across launches on their
      //     own, so an already-registered guide is never asked to sign in
      //     again here; only the (cheap, one-query) identity RESOLUTION
      //     re-runs every launch, not the sign-in itself.
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GuideSignInPage()),
        );
        return;
      }

      // Blocking screen for a copy installed outside the Play Store (release
      // builds only; a positive "not from the Play Store" answer is required).
      if (await installedOutsidePlayStore()) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const NonPlayInstallScreen()),
        );
        return;
      }

      String? resolvedGuide;
      try {
        resolvedGuide = await GuideAuthGate.resolveAndPersistIdentity(
            currentUser.email);
      } on HierarchyException {
        // A transient problem (no network, server busy): keep the session and
        // ask them to try again, rather than signing a real admin out.
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const GuideSignInPage(
              initialError:
                  'Could not reach the server. Check your connection and try again.',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;

      if (resolvedGuide == null) {
        await GuideAuthGate.signOut();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const GuideSignInPage(
              initialError:
                  'This account is not registered as a FOLK guide. Contact your HOD.',
            ),
          ),
        );
        return;
      }

      // FCM token registration (Part 2.7) — same mechanism as before,
      // re-run here too since this is the one place a resolution happens
      // without going through `GuideSignInPage`'s own sign-in flow (an
      // already-signed-in relaunch).
      await updateAdminFcmToken(resolvedGuide);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CurvedNavBar(resolvedGuide!)),
      );
      // Splash-race fix (Master Task, 2026-09-10 — Part 2) — called
      // immediately AFTER `pushReplacement`, the exact moment nothing
      // further from this splash screen will ever navigate again. Any
      // notification route that arrived during this splash window was
      // queued rather than applied (see `markAppReady()`'s own doc
      // comment in `utils/NotificationRouter.dart`) — applying it now
      // means it lands ON TOP of what `pushReplacement` just navigated
      // to, instead of being evicted by it a moment later.
      //
      // Deliberately NOT called on the two auth-gate branches above: this
      // must fire only the moment the app actually reaches its real
      // content, exactly as before — routing a queued notification onto
      // the sign-in screen would make no sense. `GuideSignInPage` makes
      // this same call itself, from the same position relative to its own
      // "enter the app" navigation, once sign-in succeeds.
      markAppReady();
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
