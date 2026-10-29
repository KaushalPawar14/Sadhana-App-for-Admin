import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/agent/AgentTypes.dart';
import 'package:folk_guide_app/theme/AgentLook.dart';
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:folk_guide_app/widgets/AgentFab.dart';
import 'package:folk_guide_app/widgets/ThinkingDots.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// The assistant's SAFFRON look: the colours and their contrast, the glossy 3D floating button and its shine (which pauses when it
/// should, and is static with reduce-motion), the typing indicator, and the cards that ease in. Text size 1.0 / 1.3 / 1.6, light
/// and dark.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  final light = GuideTheme.light.extension<GuideColors>()!;
  final dark = GuideTheme.dark.extension<GuideColors>()!;

  // ------------------------------------------------------------------------------------------ the colours
  group('the colours', () {
    test('the assistant is SAFFRON in both themes: a warm gradient from saffron to deep saffron, never fuchsia or pink', () {
      for (final g in [light, dark]) {
        for (final c in [g.agentTop, g.agentMid, g.agentBottom]) {
          expect((c.r * 255).round(), greaterThan(200), reason: 'a rich warm red');
          expect((c.g * 255).round(), allOf(greaterThan(70), lessThan(215)), reason: 'amber, not red-pink');
          expect((c.b * 255).round(), lessThan(100), reason: 'no blue, so no pink or purple');
        }
        // the gradient runs from the lighter warm saffron to the deeper one
        expect(g.agentTop.computeLuminance(), greaterThan(g.agentMid.computeLuminance()));
        expect(g.agentMid.computeLuminance(), greaterThan(g.agentBottom.computeLuminance()));
        for (final c in [g.agent]) {
          expect((c.r * 255).round(), greaterThan((c.b * 255).round() + 60), reason: 'orange, not fuchsia');
          expect((c.g * 255).round(), greaterThan((c.b * 255).round()));
        }
      }
      expect(light.agent, isNot(dark.agent), reason: 'the accent is tuned for each theme');
    });

    test('text and icons in the saffron colour read at 4.5:1 or better on the page and the cards, in light and dark', () {
      for (final (name, g) in [('light', light), ('dark', dark)]) {
        expect(contrastRatio(g.agent, g.surface), greaterThanOrEqualTo(4.5), reason: '$name: saffron text on a card');
        expect(contrastRatio(g.agent, g.pageBackground), greaterThanOrEqualTo(4.5), reason: '$name: saffron text on the page');
      }
    });

    test('text and icons ON the saffron fills (the guide\'s bubbles, the button, Confirm) read at 4.5:1 or better on every stop', () {
      for (final (name, g) in [('light', light), ('dark', dark)]) {
        for (final (stop, c) in [('top', g.agentTop), ('mid', g.agentMid), ('bottom', g.agentBottom)]) {
          expect(contrastRatio(g.onAgent, c), greaterThanOrEqualTo(4.5), reason: '$name: text on the $stop of the gradient');
        }
      }
    });

    test('no pink or fuchsia is left anywhere in the assistant\'s code', () {
      final files = [
        'lib/Pages/AgentPage.dart', 'lib/Pages/AgentChatsPage.dart', 'lib/Pages/AgentLogPage.dart', 'lib/agent/AgentOverlay.dart',
        'lib/widgets/AgentFab.dart', 'lib/widgets/TaskProgressCard.dart', 'lib/theme/AgentLook.dart', 'lib/theme/GuideColors.dart',
      ];
      for (final f in files) {
        final src = File(f).readAsStringSync();
        expect(src.contains('0xFFB0278F') || src.contains('0xFFE05CC0'), isFalse, reason: '$f still has the old fuchsia');
        expect(RegExp(r'fuchsia|Colors\.pink|Colors\.purple|Colors\.deepPurple|magenta', caseSensitive: false).hasMatch(src.replaceAll(RegExp(r'//.*'), '')), isFalse, reason: f);
      }
    });
  });

  // ------------------------------------------------------------------------------------------ the floating button
  group('the floating button', () {
    /// The overlay on a plain page, signed in. [reduce] is the phone's reduce-motion setting.
    Future<void> pumpOverlay(WidgetTester tester, {bool reduce = false, bool darkTheme = false}) async {
      await prepareApp(tester);
      phone(tester, 1.0);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(
        theme: GuideTheme.light,
        darkTheme: GuideTheme.dark,
        themeMode: darkTheme ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduce), child: AgentOverlay(child: child!)),
        home: const Scaffold(body: SizedBox.expand()),
      ));
      await tester.pump(const Duration(milliseconds: 100));
    }

    AgentFabState fab(WidgetTester tester) => tester.state<AgentFabState>(find.byType(AgentFab));

    testWidgets('a light shine sweeps across it every 5.5 seconds', (tester) async {
      await pumpOverlay(tester);
      expect(fab(tester).shining, isTrue);
      final starts = <double>[];
      var t = 0.0;
      var was = false;
      while (t < 14.0) {
        await tester.pump(const Duration(milliseconds: 50));
        t += .05;
        final now = fab(tester).sweeping;
        if (now && !was) starts.add(t);
        was = now;
      }
      expect(starts.length, greaterThanOrEqualTo(2), reason: 'sweeps at $starts');
      expect(starts[1] - starts[0], closeTo(5.5, .15), reason: 'between 5 and 6 seconds');
      expect(kAgentShineEvery.inMilliseconds, inInclusiveRange(5000, 6000));
      // and it is a sweep, not a constant glow: it rests between
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 200));
      expect(fab(tester).sweeping, isFalse, reason: 'resting between sweeps');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it pauses when the app is in the background, and carries on when it is back', (tester) async {
      await pumpOverlay(tester);
      expect(fab(tester).shining, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(fab(tester).shining, isFalse, reason: 'no battery spent while nobody can see it');
      expect(fab(tester).sweeping, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fab(tester).shining, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it pauses while the button is hidden (on the assistant page), and resumes when it shows again', (tester) async {
      await pumpOverlay(tester);
      expect(fab(tester).shining, isTrue);
      AgentRouteVisibility.instance.onAgent.value = true;
      await tester.pump();
      await tester.pump();
      expect(find.byType(AgentFab), findsNothing, reason: 'offstage');
      AgentRouteVisibility.instance.onAgent.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fab(tester).shining, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with reduce-motion it is static: no timer, no animation, no sweep', (tester) async {
      await pumpOverlay(tester, reduce: true);
      expect(fab(tester).shining, isFalse);
      await tester.pump(const Duration(seconds: 7));
      expect(fab(tester).sweeping, isFalse);
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byKey(const ValueKey('agent-fab')), findsOneWidget, reason: 'still there, just still');
    });

    testWidgets('pressing it makes it sink: smaller, lower, with a tighter shadow; letting go brings it back', (tester) async {
      await pumpOverlay(tester, reduce: true);
      Matrix4 m() => tester.widget<AnimatedContainer>(find.descendant(of: find.byType(AgentFab), matching: find.byType(AnimatedContainer)).first).transform!;
      double scale() => m().storage[0];
      double down() => m().storage[13];
      expect(scale(), 1.0);
      expect(down(), 0.0);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('agent-button'))));
      await tester.pump(const Duration(milliseconds: 150));
      expect(scale(), lessThan(1.0), reason: 'pressed down: smaller');
      expect(down(), greaterThan(0.0), reason: 'and lower');
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 150));
      expect(scale(), 1.0);
      expect(down(), 0.0);
    });

    for (final darkTheme in [false, true]) {
      testWidgets('it looks like a glossy 3D saffron ball: lit from the top, shaded below, saffron in the middle (${darkTheme ? 'dark' : 'light'})', (tester) async {
        await pumpOverlay(tester, reduce: true, darkTheme: darkTheme);
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.descendant(of: find.byType(AgentFab), matching: find.byType(RepaintBoundary)).first);
        late ByteData data;
        late int w;
        late int h;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          w = image.width;
          h = image.height;
          data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        });
        Color px(double fx, double fy) {
          final x = (w * fx).round().clamp(0, w - 1);
          final y = (h * fy).round().clamp(0, h - 1);
          final i = (y * w + x) * 4;
          return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
        }

        final topGloss = px(.5, .22); // inside the glossy highlight
        final middle = px(.2, .55); // the saffron body, clear of the icon and the gloss
        final bottom = px(.5, .93); // the shaded lower edge
        expect(topGloss.computeLuminance(), greaterThan(middle.computeLuminance()), reason: 'a highlight on top');
        expect(middle.computeLuminance(), greaterThan(bottom.computeLuminance()), reason: 'a shade below');
        expect((middle.r * 255).round(), greaterThan((middle.b * 255).round() + 80), reason: 'saffron in the middle, not pink');
        expect(find.descendant(of: find.byType(AgentFab), matching: find.byType(ClipOval)), findsOneWidget, reason: 'a round button');
      });
    }
  });

  // ------------------------------------------------------------------------------------------ the page
  group('the assistant page', () {
    late FakeFirebaseFirestore db;
    late List<Map<String, dynamic>> replies;
    Completer<Map<String, dynamic>>? hold;

    Future<AgentController> wire(WidgetTester tester) async {
      db = await prepareApp(tester);
      replies = [];
      hold = null;
      HierarchyApi.useForTests((name, args) async {
        if (hold != null) return hold!.future;
        return replies.removeAt(0);
      });
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)));
      AgentSession.useForTests(c);
      addTearDown(() => AgentSession.useForTests(null));
      return c;
    }

    double opacityOf(WidgetTester tester, Finder inside) {
      var o = 1.0;
      for (final e in tester.widgetList<Opacity>(find.ancestor(of: inside, matching: find.byType(Opacity)))) {
        o *= e.opacity;
      }
      return o;
    }

    Map<String, dynamic> question() => {
          'sessionId': 'sess12345', 'status': 'question', 'questionsLeft': 18, 'questionLimit': 20,
          'question': 'Which one should I remove?',
          'choices': [
            {'label': 'First', 'detail': 'd1', 'reply': 'one'},
            {'label': 'Second', 'detail': 'd2', 'reply': 'two'},
          ],
        };

    Map<String, dynamic> confirm() => {
          'sessionId': 'sess12345', 'status': 'confirm', 'questionsLeft': 18, 'questionLimit': 20,
          'proposal': {
            'id': 'p1', 'tainted': false, 'headsUp': <String>[],
            'actions': [{'callId': 'c1', 'tool': 'meeting_request', 'args': <String, dynamic>{}, 'title': 'Request a meeting', 'lines': <Map<String, dynamic>>[], 'notifies': <String>[], 'double': false}],
          },
        };

    Future<void> say(WidgetTester tester, String text, {int ms = 20}) async {
      await tester.enterText(find.byKey(const ValueKey('agent-input')), text);
      await tester.tap(find.byKey(const ValueKey('agent-send')));
      await tester.pump(Duration(milliseconds: ms));
    }

    testWidgets('a new question card eases in (fades up); with reduce-motion it is simply there', (tester) async {
      final c = await wire(tester);
      await pumpScreen(tester, AgentPage(controller: c), reduce: false);
      await tester.pump(const Duration(milliseconds: 100));
      replies.add(question());
      await say(tester, 'which?', ms: 60);
      final card = find.byKey(const ValueKey('agent-choice-0'));
      expect(card, findsOneWidget);
      expect(opacityOf(tester, card), lessThan(1.0), reason: 'part-way in');
      await tester.pump(const Duration(milliseconds: 600));
      expect(opacityOf(tester, card), 1.0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('with reduce-motion the question card is there at full strength at once', (tester) async {
      final c = await wire(tester);
      await pumpScreen(tester, AgentPage(controller: c), reduce: true);
      await tester.pump(const Duration(milliseconds: 100));
      replies.add(question());
      await say(tester, 'which?', ms: 60);
      expect(opacityOf(tester, find.byKey(const ValueKey('agent-choice-0'))), 1.0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a confirmation card eases in too, and results show a clear tick', (tester) async {
      final c = await wire(tester);
      await pumpScreen(tester, AgentPage(controller: c), reduce: false);
      await tester.pump(const Duration(milliseconds: 100));
      replies.add(confirm());
      await say(tester, 'meet', ms: 60);
      expect(find.byKey(const ValueKey('agent-confirm')), findsOneWidget);
      expect(opacityOf(tester, find.byKey(const ValueKey('agent-confirm'))), lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 700));
      expect(opacityOf(tester, find.byKey(const ValueKey('agent-confirm'))), 1.0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a finished card shows a clear tick; a failed action shows a cross', (tester) async {
      final c = await wire(tester);
      await pumpScreen(tester, AgentPage(controller: c), reduce: true);
      await tester.pump(const Duration(milliseconds: 100));
      replies.add(confirm());
      await say(tester, 'meet');
      await tester.pump(const Duration(milliseconds: 100));
      final entry = c.entries.whereType<ProposalEntry>().single;
      entry.state = ProposalState.done;
      entry.results['c1'] = (true, 'Meeting requested.');
      c.notifyListeners();
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsWidgets);
      entry.results['c1'] = (false, 'Not allowed.');
      c.notifyListeners();
      await tester.pump();
      expect(find.byIcon(Icons.cancel), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('while the assistant thinks, a typing indicator (three moving dots) shows; it goes when the answer comes', (tester) async {
      final c = await wire(tester);
      await pumpScreen(tester, AgentPage(controller: c), reduce: false);
      await tester.pump(const Duration(milliseconds: 100));
      hold = Completer<Map<String, dynamic>>();
      await say(tester, 'hello', ms: 80);
      expect(find.byKey(const ValueKey('agent-working')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-thinking-dots')), findsOneWidget);
      expect(tester.state<ThinkingDotsState>(find.byKey(const ValueKey('agent-thinking-dots'))).moving, isTrue);
      hold!.complete({'sessionId': 'sess12345', 'status': 'message', 'text': 'Hi there.', 'questionsLeft': 19, 'questionLimit': 20});
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('agent-working')), findsNothing);
      expect(find.text('Hi there.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('with reduce-motion the typing dots stand still', (tester) async {
      final c = await wire(tester);
      await pumpScreen(tester, AgentPage(controller: c), reduce: true);
      await tester.pump(const Duration(milliseconds: 100));
      hold = Completer<Map<String, dynamic>>();
      await say(tester, 'hello', ms: 80);
      expect(tester.state<ThinkingDotsState>(find.byKey(const ValueKey('agent-thinking-dots'))).moving, isFalse);
      hold!.complete({'sessionId': 'sess12345', 'status': 'message', 'text': 'Hi.', 'questionsLeft': 19, 'questionLimit': 20});
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    for (final scale in kScales) {
      for (final darkTheme in [false, true]) {
        testWidgets('the whole conversation - bubbles, progress, question, confirmation, typing - fits at text ${scale}x, ${darkTheme ? 'dark' : 'light'}', (tester) async {
          final c = await wire(tester);
          c.entries
            ..add(UserEntry('Set up a meeting with Arjun on Monday evening and tell him'))
            ..add(AssistantEntry('Here is the plan:\n- **Meet** Arjun on Monday at 6 pm\n- Tell him by message\n\nShall I go ahead?'))
            ..add(QuestionEntry('Which Arjun?', const [AgentChoice(label: 'Arjun Kumar', detail: 'Team Gopal', reply: 'a'), AgentChoice(label: 'Arjun Patel', detail: 'Team Madhava', reply: 'b')]));
          await pumpScreen(tester, AgentPage(controller: c), scale: scale, dark: darkTheme, reduce: true);
          tester.view.physicalSize = const Size(360, 2400);
          await tester.pump(const Duration(milliseconds: 100));
          hold = Completer<Map<String, dynamic>>();
          await say(tester, 'and then?', ms: 120);
          expectNoOverflow(tester);
          expect(find.byKey(const ValueKey('agent-working')), findsOneWidget);
          hold!.complete({'sessionId': 'sess12345', 'status': 'message', 'text': 'Done.', 'questionsLeft': 19, 'questionLimit': 20});
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 2));
        });
      }
    }
  });
}
