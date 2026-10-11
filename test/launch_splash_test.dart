import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/LaunchSplash.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:folk_guide_app/utils/StartupGate.dart';
import 'package:lottie/lottie.dart';

import 'support/guide_test_support.dart';

// The launch splash: shown for a minimum of 2 s on every cold start, with the startup work running
// in parallel (it never adds waiting), the startup ghost if the decision is not ready after 2 s,
// a static splash under "reduce animations", and the routing exactly the decision's.

Widget app(Widget child, {bool dark = false, bool reduce = false}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: GuideTheme.light,
      darkTheme: GuideTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduce), child: c!),
      home: child,
    );

StartupOutcome shell([String id = 'G']) => StartupOutcome(StartupTarget.shell, guideId: id);

/// A splash whose startup work finishes after [work] (or at once), with the destination as a text.
class Rig {
  Rig({Duration work = Duration.zero, StartupOutcome? outcome, this.minDuration = const Duration(seconds: 2)}) {
    this.outcome = outcome ?? shell();
    this.work = work;
  }

  late final StartupOutcome outcome;
  late final Duration work;
  final Duration minDuration;
  int started = 0;
  final events = <String>[];

  Widget build({bool reduce = false, bool dark = false}) => app(
        LaunchSplash(
          minDuration: minDuration,
          start: () async {
            started++;
            events.add('start');
            await Future<void>.delayed(work);
            events.add('decided');
            return outcome;
          },
          pageFor: (o) => Scaffold(body: Text('PAGE:${o.target.name}:${o.guideId ?? ''}')),
          beforeNavigate: (o) async => events.add('before:${o.target.name}'),
          afterNavigate: (o) => events.add('after:${o.target.name}'),
        ),
        reduce: reduce,
        dark: dark,
      );
}

Finder get splash => find.text('FOLK Guides');
Finder get ghost => find.byType(StartupGhost);
Finder page(String s) => find.text('PAGE:$s');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  group('the splash is shown for at least 2 seconds', () {
    testWidgets('even when the startup decision is ready at once, the splash stays up for the full 2 s', (tester) async {
      phone(tester, 1.0);
      final rig = Rig();
      await tester.pumpWidget(rig.build());
      await tester.pump(); // the first frame, the work starts
      expect(splash, findsOneWidget);
      expect(find.byType(Lottie), findsOneWidget, reason: 'the animation is back');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(splash, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900)); // 1.9 s
      expect(splash, findsOneWidget);
      expect(page('shell:G'), findsNothing, reason: 'not before 2 s');
      expect(rig.events, ['start', 'decided']);
      await tester.pump(const Duration(milliseconds: 150)); // 2.05 s
      await tester.pumpAndSettle();
      expect(page('shell:G'), findsOneWidget);
      expect(splash, findsNothing);
      expect(rig.events, ['start', 'decided', 'before:shell', 'after:shell']);
    });

    testWidgets('the work runs IN PARALLEL: it starts with the splash, and a 1 s decision still leaves at 2 s (no waiting added)', (tester) async {
      phone(tester, 1.0);
      final rig = Rig(work: const Duration(seconds: 1));
      await tester.pumpWidget(rig.build());
      await tester.pump();
      expect(rig.started, 1, reason: 'started at the first frame, not after the splash');
      await tester.pump(const Duration(milliseconds: 1950));
      expect(page('shell:G'), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(page('shell:G'), findsOneWidget, reason: 'left at 2 s, not at 2 s + 1 s');
    });

    testWidgets('a decision that takes longer (3 s): the ghost from 2 s, then the screen the moment it is ready', (tester) async {
      phone(tester, 1.0);
      final rig = Rig(work: const Duration(seconds: 3));
      await tester.pumpWidget(rig.build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1900));
      expect(splash, findsOneWidget);
      expect(ghost, findsNothing);
      await tester.pump(const Duration(milliseconds: 200)); // 2.1 s
      await tester.pump(const Duration(milliseconds: 300)); // the cross-fade
      expect(ghost, findsOneWidget, reason: 'the startup ghost while it is not ready');
      expect(splash, findsNothing);
      expect(page('shell:G'), findsNothing);
      await tester.pump(const Duration(milliseconds: 800)); // 3.2 s
      await tester.pumpAndSettle();
      expect(page('shell:G'), findsOneWidget);
      expect(ghost, findsNothing);
    });

    testWidgets('the decision arriving exactly around 2 s goes straight on, with no ghost flash', (tester) async {
      phone(tester, 1.0);
      final rig = Rig(work: const Duration(milliseconds: 1999));
      await tester.pumpWidget(rig.build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2010));
      await tester.pumpAndSettle();
      expect(page('shell:G'), findsOneWidget);
    });
  });

  group('routing is exactly the decision\'s (every target)', () {
    for (final t in StartupTarget.values) {
      testWidgets('${t.name}: the page for that decision, after the hooks in order', (tester) async {
        phone(tester, 1.0);
        final rig = Rig(outcome: StartupOutcome(t, guideId: t == StartupTarget.shell ? 'E1' : null));
        await tester.pumpWidget(rig.build());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2, milliseconds: 100));
        await tester.pumpAndSettle();
        expect(page('${t.name}:${t == StartupTarget.shell ? 'E1' : ''}'), findsOneWidget);
        // before the navigation, then after it (sign-out / flushing a queued notification live there)
        expect(rig.events.where((e) => e.contains(':')).toList(), ['before:${t.name}', 'after:${t.name}']);
      });
    }

    testWidgets('a startup step that throws never leaves the splash stuck: the offline sign-in screen', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(app(LaunchSplash(
        start: () async => throw StateError('boom'),
        pageFor: (o) => Scaffold(body: Text('PAGE:${o.target.name}')),
      )));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('PAGE:offline'), findsOneWidget);
    });
  });

  group('reduce animations: a static splash, still for the full 2 s', () {
    testWidgets('no animation and no fade running; leaves at 2 s', (tester) async {
      phone(tester, 1.0);
      final rig = Rig();
      await tester.pumpWidget(rig.build(reduce: true));
      await tester.pump();
      expect(splash, findsOneWidget);
      expect(find.byType(FadeTransition).evaluate().where((e) => e.widget is FadeTransition && (e.widget as FadeTransition).opacity.value != 1).isEmpty, isTrue);
      final lottie = tester.widget<Lottie>(find.byType(Lottie));
      expect(lottie.animate, isFalse);
      expect(lottie.repeat, isFalse);
      await tester.pump(const Duration(milliseconds: 1900));
      expect(splash, findsOneWidget, reason: 'still 2 s');
      expect(tester.binding.transientCallbackCount, 0, reason: 'nothing animates');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(page('shell:G'), findsOneWidget);
    });

    testWidgets('with animations on, the logo breathes (a running animation) and the Lottie plays', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(Rig().build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final lottie = tester.widget<Lottie>(find.byType(Lottie));
      expect(lottie.animate, isTrue);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });
  });

  group('Ink & Brass, light and dark, any text size: no white flash, no overflow', () {
    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale, real fonts', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(Rig(work: const Duration(seconds: 3)).build(dark: dark));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expectNoOverflow(tester);
          // the page background is the theme's own (never a white default)
          final scaffold = tester.widget<Scaffold>(find.descendant(of: find.byType(LaunchSplash), matching: find.byType(Scaffold)).first);
          final bg = (dark ? GuideTheme.dark : GuideTheme.light).scaffoldBackgroundColor;
          expect(scaffold.backgroundColor ?? bg, isNot(const Color(0xFFFFFFFF)));
          expect(find.text("Now it's easy to check Sadhana daily"), findsOneWidget);
          // the ghost phase too
          await tester.pump(const Duration(milliseconds: 4000));
          await tester.pump(const Duration(milliseconds: 400));
          expect(ghost, findsOneWidget);
          expectNoOverflow(tester);
          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
        });
      }
    }

    test('the native launch window already shows the theme\'s page background (light #F6F4EF, dark #141519), so there is no white flash before Flutter draws', () {
      final light = File('android/app/src/main/res/values/colors.xml').readAsStringSync();
      final night = File('android/app/src/main/res/values-night/colors.xml').readAsStringSync();
      expect(light, contains('#F6F4EF'));
      expect(night, contains('#141519'));
      expect(File('android/app/src/main/res/drawable/launch_background.xml').readAsStringSync(), contains('@color/folk_page_background'));
    });
  });

  group('the splash wiring in main.dart', () {
    final main = File('lib/main.dart').readAsStringSync();
    test('the splash is the LaunchSplash with the 2 s minimum; the work is the same StartupGate', () {
      expect(main, contains('LaunchSplash('));
      expect(main, contains('StartupGate.run('));
      expect(File('lib/Pages/LaunchSplash.dart').readAsStringSync(), contains('Duration(seconds: 2)'));
    });

    test('routing in main.dart is unchanged: one page per decision', () {
      for (final page in ['ForceUpdateScreen()', 'GuideSignInPage()', 'NonPlayInstallScreen()', 'kOfflineMessage', 'kNotRegisteredMessage', 'CurvedNavBar(outcome.guideId!)']) {
        expect(main, contains(page), reason: page);
      }
      // markAppReady only on the shell; sign-out only for a no-longer-registered account
      expect(main, contains('markAppReady();'));
      expect(main, contains('if (outcome.target == StartupTarget.notRegistered) await GuideAuthGate.signOut();'));
    });
  });
}
