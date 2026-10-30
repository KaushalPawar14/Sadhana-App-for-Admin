import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:folk_guide_app/Pages/ForceUpdateScreen.dart';
import 'package:folk_guide_app/Pages/GuideSignIn.dart';
import 'package:folk_guide_app/Pages/LaunchSplash.dart';
import 'package:folk_guide_app/Pages/NonPlayInstallScreen.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/StartupGate.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// THE ASSISTANT'S BUTTON SHOWS ONLY ONCE THE MAIN SHELL (Home and the other main tabs) IS ON SCREEN: never on the splash, the sign-in, a loading
/// screen, "update required" or any other screen before Home, even though the admin's profile is already there (it is, right after sign-in). It
/// fades in when Home appears.

AdminProfile _me() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

Future<void> _pump(WidgetTester tester, Widget home, {Size size = const Size(360, 800), bool signedIn = true}) async {
  // the app as it is right after sign-in: the profile, the database fakes
  await prepareApp(tester);
  if (!signedIn) AdminProfileProvider.instance.debugSet(null);
  phone(tester, 1.0, size: size);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(MaterialApp(
    theme: GuideTheme.light,
    builder: (context, child) => AgentOverlay(child: child!),
    home: home,
  ));
  await tester.pump();
  await tester.pump(); // the saved spot of the button is read
  await tester.pump();
}

/// Whether the button is there for a person: in the tree, fully opaque, and not ignoring touches.
bool _visible(WidgetTester tester) {
  final fade = find.byKey(const ValueKey('agent-button-fade'));
  if (fade.evaluate().isEmpty) return false;
  final opacity = tester.widget<AnimatedOpacity>(fade).opacity;
  final ignoring = tester.widgetList<IgnorePointer>(find.ancestor(of: fade, matching: find.byType(IgnorePointer))).any((i) => i.ignoring);
  return opacity == 1 && !ignoring;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => loadGuideFonts());
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // the worst case: the profile is already there (right after sign-in), the shell is not
    AdminProfileProvider.instance.debugSet(_me());
    AgentShell.ready.value = false;
  });
  tearDown(() {
    AgentShell.ready.value = false;
    AdminProfileProvider.instance.debugSet(null);
  });

  final preHome = <String, Widget Function()>{
    'the launch splash': () => LaunchSplash(start: () => Completer<StartupOutcome>().future, pageFor: (_) => const SizedBox()),
    'the update-required screen': () => const ForceUpdateScreen(),
    'the non-Play install screen': () => const NonPlayInstallScreen(),
    'the sign-in page': () => const GuideSignInPage(),
    'a loading screen': () => const Scaffold(body: Center(child: CircularProgressIndicator())),
  };

  for (final e in preHome.entries) {
    testWidgets('NO BUTTON on ${e.key}, though the admin is already known', (tester) async {
      await _pump(tester, e.value());
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('agent-button-fade')), findsOneWidget, reason: 'the overlay is there: the button is kept out, not absent by accident');
      expect(_visible(tester), isFalse);
      // and a tap where it would be reaches nothing
      final fade = find.byKey(const ValueKey('agent-button-fade'));
      if (fade.evaluate().isNotEmpty) expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
      expect(find.byKey(const ValueKey('agent-fab')).hitTestable(), findsNothing);
      await tester.pump(const Duration(seconds: 5)); // the splash's minimum time
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the button appears when the main shell says it is on screen, fading in smoothly (not at once), and goes when the shell goes', (tester) async {
    await _pump(tester, const Scaffold(body: Center(child: Text('Home'))));
    expect(_visible(tester), isFalse);
    AgentShell.ready.value = true;
    await tester.pump();
    final fade = find.byKey(const ValueKey('agent-button-fade'));
    // fading: the first frame has not finished the fade
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.widget<AnimatedOpacity>(fade).opacity;
    expect(mid, 1, reason: 'the target opacity is 1 ...');
    expect(tester.widget<AnimatedOpacity>(fade).duration, greaterThanOrEqualTo(const Duration(milliseconds: 300)), reason: '... reached over a smooth fade, not a jump');
    await tester.pump(const Duration(milliseconds: 600));
    expect(_visible(tester), isTrue);
    expect(find.byKey(const ValueKey('agent-fab')).hitTestable(), findsOneWidget);
    AgentShell.ready.value = false;
    await tester.pump(const Duration(milliseconds: 600));
    expect(_visible(tester), isFalse);
  });

  testWidgets('nobody signed in: no button at all, shell or not', (tester) async {
    AgentShell.ready.value = true;
    await _pump(tester, const Scaffold(body: SizedBox.expand()), signedIn: false);
    expect(find.byKey(const ValueKey('agent-button-fade')), findsNothing);
  });

  testWidgets('the same on a phone and on the website (a narrow browser window): hidden before the shell, shown after', (tester) async {
    for (final size in [const Size(360, 800), const Size(700, 900)]) {
      AgentShell.ready.value = false;
      await _pump(tester, const Scaffold(body: SizedBox.expand()), size: size);
      expect(_visible(tester), isFalse, reason: '$size before');
      AgentShell.ready.value = true;
      await tester.pump(const Duration(milliseconds: 600));
      expect(_visible(tester), isTrue, reason: '$size after');
      await tester.pumpWidget(const SizedBox());
    }
  });

  // ---------------------------------------------------------------- THE BUTTON NEVER DISAPPEARS (root causes)

  testWidgets('A SHELL REPLACED BY ANOTHER IN THE SAME FRAME keeps the button: the old one going after the new one coming used to clear the flag for good', (tester) async {
    await _pump(tester, const Scaffold(body: SizedBox.expand()));
    final a = Object();
    final b = Object();
    AgentShell.attach(a);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_visible(tester), isTrue);
    // the new shell comes and the old one goes in the same frame, in the worst order
    AgentShell.attach(b);
    AgentShell.detach(a);
    await tester.pump(const Duration(milliseconds: 600));
    expect(AgentShell.ready.value, isTrue, reason: 'one shell is still there');
    expect(_visible(tester), isTrue);
    // and the other order
    AgentShell.detach(b);
    AgentShell.attach(a);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_visible(tester), isTrue);
    // only when the last one goes does it go
    AgentShell.detach(a);
    await tester.pump(const Duration(milliseconds: 600));
    expect(AgentShell.ready.value, isFalse);
    expect(_visible(tester), isFalse);
    AgentShell.reset();
  });

  testWidgets('THE BUTTON IS THERE FROM THE FIRST FRAME (it does not wait for the saved spot to be read) and a garbage saved spot never loses it', (tester) async {
    for (final saved in <Map<String, Object>>[
      {},
      {'agent_button_dx_fraction': double.nan, 'agent_button_dy_fraction': 5.0},
      {'agent_button_dx_fraction': -3.0, 'agent_button_dy_fraction': 12.0},
      {'agent_button_dx_fraction': 0.5, 'agent_button_dy_fraction': 0.5},
    ]) {
      SharedPreferences.setMockInitialValues(saved);
      AgentShell.ready.value = true;
      await prepareApp(tester);
      phone(tester, 1.0, size: const Size(360, 800));
      await tester.pumpWidget(MaterialApp(theme: GuideTheme.light, builder: (context, child) => AgentOverlay(child: child!), home: const Scaffold(body: SizedBox.expand())));
      await tester.pump(); // ONE frame: no waiting for the saved spot
      expect(find.byKey(const ValueKey('agent-fab')), findsOneWidget, reason: '$saved');
      await tester.pump(const Duration(milliseconds: 600));
      final r = tester.getRect(find.byKey(const ValueKey('agent-fab')));
      expect(r.left, greaterThanOrEqualTo(0), reason: '$saved');
      expect(r.right, lessThanOrEqualTo(360), reason: '$saved');
      expect(r.top, greaterThanOrEqualTo(0), reason: '$saved');
      expect(r.bottom, lessThanOrEqualTo(800), reason: '$saved');
      expect(_visible(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('THE KEYBOARD NEVER HIDES THE BUTTON: with the keyboard open it sits above it', (tester) async {
    AgentShell.ready.value = true;
    await prepareApp(tester);
    phone(tester, 1.0, size: const Size(360, 800));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(() => tester.view.resetViewInsets());
    await tester.pumpWidget(MaterialApp(theme: GuideTheme.light, builder: (context, child) => AgentOverlay(child: child!), home: const Scaffold(body: SizedBox.expand())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final r = tester.getRect(find.byKey(const ValueKey('agent-fab')));
    expect(r.bottom, lessThanOrEqualTo(800 - 300), reason: 'above the keyboard');
    expect(_visible(tester), isTrue);
  });
}
