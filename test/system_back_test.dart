import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysEntry.dart';
import 'package:folk_guide_app/Home/FolkBoysWorkspace.dart';
import 'package:folk_guide_app/Pages/AgentLogPage.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/Pages/Leaderboard.dart';
import 'package:folk_guide_app/Pages/MusicCurriculumPage.dart';
import 'package:folk_guide_app/Pages/StudentDoubtsPage.dart';
import 'package:folk_guide_app/Pages/StudentMusicPage.dart';
import 'package:folk_guide_app/Pages/StudentNotificationSettings.dart';
import 'package:folk_guide_app/Pages/StudentProfilePage.dart';
import 'package:folk_guide_app/Pages/WeeklyPlanning.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:folk_guide_app/theme/ThemeModeController.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/data_range_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'all_dialogs_test.dart' show cases;
import 'all_screens_test.dart' show screens;
import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// THE PHONE'S BACK BUTTON, ON EVERY SCREEN.
///
/// Bug: opening Interactions and pressing the PHONE's back button (not the app bar arrow) showed a full red error
/// screen. The sheet that logs an interaction owned its text controller in the screen that opened it and disposed it
/// the moment the sheet's future completed — which is when the pop STARTS, while the sheet is still sliding away and
/// still painting the field ("A TextEditingController was used after being disposed").
///
/// This file presses system back — and Android's predictive back gesture, the one that scales the outgoing page — on
/// every screen the app has, from the place it is opened, and on every dialog and sheet reachable with one tap,
/// light and dark, at text scale 1.0, 1.3 and 1.6. No exception (an overflow is one), the screen underneath comes
/// back, nothing is left on screen.
///
/// Anything that disposes something its own exit animation still uses fails here.

/// A screen that is not in the all-screens sweep, and the constructor it needs.
final Map<String, Widget Function()> extraScreens = {
  'agent_page': () => const AgentPage(),
  'agent_log': () => const AgentLogPage(),
  'folk_boys_entry': () => const FolkBoysEntryScreen(selectedGuide: 'H'),
  'folk_boys_board': () => const FolkBoysWorkspace(selectedGuide: 'H'),
  'goal_home': () => const GoalHomePage(guideId: 'G'),
  'leaderboard': () => const LeaderboardPage(),
  'weekly_planning': () => const WeeklyPlanningPage(),
  'student_doubts': () => const StudentDoubtsPage(),
  'music_curriculum': () => const MusicCurriculumPage(),
  'student_music': () => const StudentMusicPage(studentUid: 's1', studentName: 'Arjun Kumar'),
  'student_notification_settings': () => StudentNotificationSettingsPage(studentUid: 's1', studentName: 'Arjun Kumar', canEdit: true, firestore: GuideDb.instance),
  'student_profile_at_suggestions': () => const StudentProfilePage(studentUid: 's1', focusSuggestions: true),
};

/// Screens whose own job is to refuse back (a forced update, the "install from Play" wall).
const refusesBack = {'force_update', 'non_play_install'};

const _openKey = ValueKey('open-the-screen');

/// The app's providers around a MaterialApp whose theme uses Android's PREDICTIVE back transition — the
/// outgoing page is scaled and moved while the gesture is held, the layout case that broke the board.
Future<void> pumpHost(WidgetTester tester, Widget Function() screen, {double scale = 1.0, bool dark = false}) async {
  phone(tester, scale);
  SharedPreferences.setMockInitialValues({'selected_guide': 'H', ThemeModeController.prefsKey: dark ? 'dark' : 'light'});
  final theme = await ThemeModeController.load();
  const predictive = PageTransitionsTheme(builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()});
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeModeController>.value(value: theme),
      ChangeNotifierProvider<ColorProvider>(create: (_) => ColorProvider(controller: theme)),
      ChangeNotifierProvider<AdminProfileProvider>.value(value: AdminProfileProvider.instance),
      ChangeNotifierProvider<DateRangeProvider>(create: (_) => DateRangeProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: GuideTheme.light.copyWith(pageTransitionsTheme: predictive),
      darkTheme: GuideTheme.dark.copyWith(pageTransitionsTheme: predictive),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: _openKey,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen())),
              child: const Text('Open the screen'),
            ),
          ),
        ),
      ),
    ),
  ));
}

/// Frames across an exit animation, a little at a time (so every intermediate layout is built).
Future<void> pumpThrough(WidgetTester tester, {int frames = 14, int ms = 40}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

Future<void> openIt(WidgetTester tester) async {
  await tester.tap(find.byKey(_openKey));
  await tester.pump();
  await letDataArrive(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

/// The phone's back button. With [keyboardUp] the keyboard was open on the sheet and goes away as it leaves — which
/// rebuilds whatever is still on screen while the exit animation runs (the moment the old bug needed).
Future<void> systemBack(WidgetTester tester, {bool keyboardUp = false}) async {
  await tester.binding.handlePopRoute();
  await tester.pump(const Duration(milliseconds: 16));
  if (keyboardUp) {
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump(const Duration(milliseconds: 16));
  }
  await pumpThrough(tester);
}

/// The soft keyboard comes up (the field is focused and the screen is 300 dp shorter).
Future<void> keyboardUp(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  addTearDown(tester.view.resetViewInsets);
  await tester.pump(const Duration(milliseconds: 100));
}

/// One message on the engine's back-gesture channel, exactly as Android's predictive back sends it.
Future<void> _gesture(WidgetTester tester, String method, [Map<String, Object?>? args]) async {
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    codec.encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
}

/// Android's predictive back gesture, dragged to [progress] and either let go (commit) or taken back (cancel).
Future<void> predictiveBack(WidgetTester tester, {bool commit = true, double progress = 0.6}) async {
  Map<String, Object?> at(double p) => {
        'touchOffset': <double>[8 + 200 * p, 400],
        'progress': p,
        'swipeEdge': 0, // from the left edge
      };
  await _gesture(tester, 'startBackGesture', at(0));
  await tester.pump(const Duration(milliseconds: 16));
  for (final p in [0.1, 0.25, progress]) {
    await _gesture(tester, 'updateBackGestureProgress', at(p));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull, reason: 'mid-gesture at ${(p * 100).round()}%');
  }
  await _gesture(tester, commit ? 'commitBackGesture' : 'cancelBackGesture');
  await pumpThrough(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  final every = {...screens, ...extraScreens};

  for (final e in every.entries) {
    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${e.key} · ${dark ? 'dark' : 'light'} · ×$scale · phone back', (tester) async {
          await prepareApp(tester);
          await pumpHost(tester, e.value, scale: scale, dark: dark);

          // 1. the phone's back button
          await openIt(tester);
          expect(tester.takeException(), isNull, reason: 'opening');
          await systemBack(tester);
          expect(tester.takeException(), isNull, reason: 'after system back');
          if (refusesBack.contains(e.key)) {
            expect(find.byKey(_openKey), findsNothing, reason: 'this screen refuses back');
            return;
          }
          expect(find.byKey(_openKey), findsOneWidget, reason: 'the screen underneath is back');

          // 2. the predictive back gesture, let go
          await openIt(tester);
          await predictiveBack(tester);
          expect(tester.takeException(), isNull, reason: 'after predictive back');
          expect(find.byKey(_openKey), findsOneWidget, reason: 'the screen underneath is back (gesture)');

          // 3. the gesture taken back: the screen stays, whole
          await openIt(tester);
          await predictiveBack(tester, commit: false);
          expect(tester.takeException(), isNull, reason: 'after a cancelled gesture');
          expect(find.byKey(_openKey), findsNothing, reason: 'still on the screen');
          await systemBack(tester);
          expect(tester.takeException(), isNull, reason: 'back again');
          expect(find.byKey(_openKey), findsOneWidget);

          // leave: let any polling timer of the screen run out
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
        });
      }
    }
  }

  // ----------------------------------------------------------------------------- dialogs and sheets
  for (final c in cases) {
    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${c.name} (dialog / sheet) · ${dark ? 'dark' : 'light'} · ×$scale · phone back', (tester) async {
          await prepareApp(tester);
          await pumpHost(tester, c.screen, scale: scale, dark: dark);
          await openIt(tester);
          final target = c.tap != null ? find.text(c.tap!).first : find.byIcon(c.byIcon!).first;
          await tester.ensureVisible(target);
          await tester.tap(target, warnIfMissed: false);
          await tester.pump();
          await letDataArrive(tester, frames: 8);
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: 'opening');

          // back closes the dialog / sheet, and only it
          await systemBack(tester);
          expect(tester.takeException(), isNull, reason: 'after system back on the dialog / sheet');
          expect(find.byKey(_openKey), findsNothing, reason: 'the screen that opened it is still there');
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.byType(Dialog), findsNothing);

          // back again leaves the screen
          await systemBack(tester);
          expect(tester.takeException(), isNull, reason: 'after system back on the screen');
          expect(find.byKey(_openKey), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
        });
      }
    }
  }

  // ----------------------------------------------------------------------------- the interactions bug itself
  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('interactions: open "New", type, phone back mid-note, then leave · ${dark ? 'dark' : 'light'} · ×$scale', (tester) async {
        await prepareApp(tester);
        await pumpHost(tester, screens['interaction_logger']!, scale: scale, dark: dark);
        await openIt(tester);
        await tester.tap(find.text('New'));
        await tester.pump();
        await letDataArrive(tester, frames: 10);
        await tester.enterText(find.byType(TextField).first, 'Half a note');
        await tester.pump();
        await keyboardUp(tester);
        // the phone's back button, with the keyboard up and the field still holding text
        await systemBack(tester, keyboardUp: true);
        expect(tester.takeException(), isNull, reason: 'sheet closed with the phone back button');
        expect(find.text('Half a note'), findsNothing);
        // and again, with the sheet swiped by the predictive gesture
        await tester.tap(find.text('New'));
        await tester.pump();
        await letDataArrive(tester, frames: 10);
        await predictiveBack(tester);
        expect(tester.takeException(), isNull, reason: 'sheet closed with the predictive gesture');
        await systemBack(tester);
        expect(tester.takeException(), isNull, reason: 'left the screen');
        expect(find.byKey(_openKey), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
