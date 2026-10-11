import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/GuideTheme.dart';
import 'widgets/GuideSurface.dart';
import 'theme/GuideTokens.dart';
import 'theme/ThemeModeController.dart';
import 'package:folk_guide_app/utils/BottomNavBar.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/data_range_provider.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';
import 'utils/AdminProfile.dart';
import 'utils/InstallSource.dart';
import 'Pages/NonPlayInstallScreen.dart';
import 'Services/Notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/GuideGhost.dart';
import 'dart:async';

import 'Pages/ForceUpdateScreen.dart';
import 'Pages/GuideSignIn.dart';
import 'Services/UpdateToken.dart';
import 'Services/UpdateFCM.dart' show UpdateTokenService;
import 'utils/ForceUpdateCheck.dart';
import 'utils/GuideAuthGate.dart';
import 'utils/NotificationRouter.dart';
import 'utils/StartupGate.dart';
import 'utils/StartupTrace.dart';

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
  StartupTrace.start();
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only (the manifest locks it too, so there is no rotation flash
  // before Flutter starts).
  await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  String? savedGuide = prefs.getString('selected_guide');
  StartupTrace.mark('SharedPreferences read');

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
  // Firebase and the saved Light / Dark / Auto choice do not depend on each other: together.
  final initialised = await Future.wait<Object?>([
    Firebase.initializeApp(),
    ThemeModeController.load(),
  ]);
  final themeController = initialised[1] as ThemeModeController;
  StartupTrace.mark('Firebase.initializeApp + theme done');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeModeController>.value(
            value: themeController),
        // Mirrors the Light / Dark / Auto setting for the screens that still
        // read ColorProvider.
        ChangeNotifierProvider(
            create: (_) => ColorProvider(controller: themeController)),
        ChangeNotifierProvider<AdminProfileProvider>.value(
            value: AdminProfileProvider.instance),
        ChangeNotifierProvider(create: (_) => DateRangeProvider()),
      ],
      child: MyApp(savedGuide: savedGuide),
    ),
  );

  StartupTrace.mark('runApp called');

  // Everything below only needs Firebase to already exist (guaranteed now) and has no
  // bearing on the first screen, so it starts AFTER the first frame is drawn (it used to be
  // a microtask, which runs before it): the permission dialog, the notification channel and
  // the token-refresh listener. Registering the FCM token itself is done by the app shell
  // (`FolkBoysEntryScreen`, after its first frame) and by `GuideSignInPage` — never from here.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    StartupTrace.mark('first frame drawn');
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    await _requestNotificationPermissions();

    FirebaseCM firebaseCM = FirebaseCM();
    await firebaseCM.initNotifications();

    listenForAdminFcmTokenRefresh();
    StartupTrace.mark('notification setup done (background)');
  });
}

class MyApp extends StatelessWidget {
  final String? savedGuide;
  const MyApp({super.key, this.savedGuide});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, deviceType) {
        return MaterialApp(
          navigatorKey: guideNavigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'FOLK Guides',
          theme: GuideTheme.light,
          darkTheme: GuideTheme.dark,
          themeMode: context.watch<ThemeModeController>().themeMode,
          themeAnimationDuration: GuideMotion.of(context, GuideMotion.theme),
          home: SplashScreen(savedGuide: savedGuide),
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

/// The launch screen: a ghost of the app, shown AT ONCE (there is no fixed delay and no
/// animation to wait for), while [StartupGate] works out where to go. The decisions and their
/// order are what this screen always made (see `StartupGate`); the differences are that
/// nothing waits for a timer, the force-update read is capped at 1.5 s and runs alongside
/// everything else, the FCM token is no longer registered here (the shell does it after its
/// first frame), and a signed-in admin with a cached profile goes straight into the app while
/// the profile is re-checked in the background.
class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    StartupTrace.mark('splash initState (ghost shown)');
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  Future<void> _go() async {
    final outcome = await StartupGate.run(
      forceUpdate: ForceUpdateCheck.isUpdateRequired,
      currentEmail: () => FirebaseAuth.instance.currentUser?.email ??
          (FirebaseAuth.instance.currentUser == null ? null : ''),
      installedOutsidePlayStore: installedOutsidePlayStore,
      cachedProfile: (email) async {
        final cached = await AdminProfileProvider.instance.readCache(email);
        if (cached != null) {
          AdminProfileProvider.instance.restore(cached);
          // The pref every screen reads for the locked identity.
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getString('selected_guide') != cached.id) {
            await UpdateTokenService().saveSelectedGuide(cached.id);
          }
        }
        return cached;
      },
      resolveFresh: GuideAuthGate.resolveAndPersistIdentity,
      trace: StartupTrace.mark,
    );
    if (!mounted) return;

    switch (outcome.target) {
      case StartupTarget.forceUpdate:
        // `markAppReady()` is deliberately NOT called: a notification tapped while an update is
        // required stays queued and can never fire underneath this blocking screen.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ForceUpdateScreen()),
        );
      case StartupTarget.signIn:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GuideSignInPage()),
        );
      case StartupTarget.nonPlayInstall:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const NonPlayInstallScreen()),
        );
      case StartupTarget.offline:
        // A transient problem (no network, server busy): keep the session and ask them to try
        // again, rather than signing a real admin out.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const GuideSignInPage(initialError: kOfflineMessage),
          ),
        );
      case StartupTarget.notRegistered:
        await GuideAuthGate.signOut();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const GuideSignInPage(initialError: kNotRegisteredMessage),
          ),
        );
      case StartupTarget.shell:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => CurvedNavBar(outcome.guideId!)),
        );
        StartupTrace.mark('app shell pushed (first real screen)');
        // Splash-race fix (Master Task, 2026-09-10): called immediately AFTER the navigation
        // that reaches the real content, so a notification route queued during this window
        // lands on top of the shell instead of being evicted by it.
        markAppReady();
        if (outcome.fromCache) unawaited(_revalidateInBackground());
    }
  }

  @override
  Widget build(BuildContext context) {
    // A ghost of the app's own shape (page header, then rows), instantly; no animation to wait for.
    return GuideScaffold(
      body: SafeArea(
        child: GuideGhostArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 28, GuideSpace.pagePadding, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                GuideGhostBar(width: 90, height: 11),
                SizedBox(height: 10),
                GuideGhostBar(width: 220, height: 30),
                SizedBox(height: 26),
                GuideGhostBlock(height: 120),
                SizedBox(height: 14),
                GuideGhostRow(),
                SizedBox(height: 10),
                GuideGhostRow(),
                SizedBox(height: 10),
                GuideGhostRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// After the app opened from the cached profile: ask the server again. Removed -> sign out and
/// go to the sign-in screen with the explanation (exactly what a fresh resolve did before).
/// Role / team changed -> rebuild the shell from the new profile, so who sees what is correct
/// at once. Anything else is already applied by the provider. A server that cannot be reached
/// changes nothing.
Future<void> _revalidateInBackground() async {
  final result = await AdminProfileProvider.instance.revalidate();
  StartupTrace.mark('admin profile re-checked in background: ${result.name}');
  final nav = guideNavigatorKey.currentState;
  if (nav == null) return;
  switch (result) {
    case ProfileRefresh.removed:
      await GuideAuthGate.signOut();
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GuideSignInPage(initialError: kNotRegisteredMessage)),
        (_) => false,
      );
    case ProfileRefresh.restructured:
      final id = AdminProfileProvider.current?.id;
      if (id == null) return;
      await UpdateTokenService().saveSelectedGuide(id);
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => CurvedNavBar(id)), (_) => false);
    case ProfileRefresh.unchanged:
    case ProfileRefresh.updated:
    case ProfileRefresh.offline:
      break;
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
