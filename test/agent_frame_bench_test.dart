import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/agent/AgentTypes.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// FRAME COST of the assistant's screens: how long each frame's build + layout + paint takes on the dev PC, with the
/// assistant's animations running. It is a benchmark, not a pass/fail test: it prints numbers (and fails only if a frame is
/// absurdly slow), so the same file run before and after a change shows what the change cost.
///
///   AGENT_BENCH=1 flutter test test/agent_frame_bench_test.dart
///
/// What it can NOT show: raster (GPU) time and real-device jank. Those need a phone in profile mode
/// (`flutter run --profile` + DevTools "Performance"); no device is attached to the machine this was written on. What it does
/// show is the part the app controls - rebuilds and layout - which is where "unnecessary rebuilds" would appear.

final bool _on = Platform.environment['AGENT_BENCH'] == '1';

class _Stats {
  _Stats(this.name, List<double> ms)
      : mean = ms.reduce((a, b) => a + b) / ms.length,
        p95 = (List.of(ms)..sort())[(ms.length * .95).floor().clamp(0, ms.length - 1)],
        worst = ms.reduce((a, b) => a > b ? a : b),
        frames = ms.length;

  final String name;
  final double mean;
  final double p95;
  final double worst;
  final int frames;

  @override
  String toString() => '${name.padRight(34)} frames ${frames.toString().padLeft(4)}   mean ${mean.toStringAsFixed(2).padLeft(6)} ms   p95 ${p95.toStringAsFixed(2).padLeft(6)} ms   worst ${worst.toStringAsFixed(2).padLeft(6)} ms';
}

Future<_Stats> _measure(WidgetTester tester, String name, int frames, {void Function(int i)? each}) async {
  final times = <double>[];
  await tester.pump(const Duration(milliseconds: 100)); // settle
  for (var i = 0; i < frames; i++) {
    each?.call(i);
    final sw = Stopwatch()..start();
    await tester.pump(const Duration(milliseconds: 16));
    sw.stop();
    times.add(sw.elapsedMicroseconds / 1000);
  }
  return _Stats(name, times);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  testWidgets('assistant frame cost', skip: !_on, (tester) async {
    final out = <_Stats>[];
    final db = await prepareApp(tester);
    final stuck = Completer<Map<String, dynamic>>();
    HierarchyApi.useForTests((name, args) => stuck.future);
    final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)));
    AgentSession.useForTests(c);
    addTearDown(() => AgentSession.useForTests(null));

    // 1. the floating button on its own, idle, on a plain page
    tester.platformDispatcher.textScaleFactorTestValue = 1.0;
    await pumpScreen(tester, const AgentOverlay(child: Scaffold(body: SizedBox.expand()), signedIn: null), reduce: false);
    out.add(await _measure(tester, 'floating button, idle (240 frames)', 240));

    // 2. a long conversation on screen, with the assistant "thinking"
    for (var i = 0; i < 20; i++) {
      c.entries.add(UserEntry('Question number $i about the students and what to do this week'));
      c.entries.add(AssistantEntry('Answer $i with a **bold** point, a list:\n- first item\n- second item\n\nand a closing sentence that is long enough to wrap onto a second line.'));
    }
    await pumpScreen(tester, AgentPage(controller: c), reduce: false);
    unawaited(c.send('another question'));
    await tester.pump(const Duration(milliseconds: 100));
    out.add(await _measure(tester, 'chat, 41 messages, thinking (300)', 300));

    // 3. scrolling that conversation
    final scroll = find.byKey(const ValueKey('agent-conversation'));
    final state = tester.state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable)).first);
    out.add(await _measure(tester, 'chat, scrolling 40 px a frame (200)', 200, each: (i) {
      final p = state.position;
      p.jumpTo((p.pixels + (i.isEven ? 40 : -40)).clamp(0, p.maxScrollExtent));
    }));

    // 4. a card on screen: the question card
    c.entries.add(QuestionEntry('Which one should I remove?', const [
      AgentChoice(label: 'First record', detail: 'Follow-up 3 Nov', reply: 'a'),
      AgentChoice(label: 'Second record', detail: 'Follow-up 3 Nov', reply: 'b'),
    ]));
    c.notifyListeners();
    await tester.pump(const Duration(milliseconds: 400));
    out.add(await _measure(tester, 'chat with a question card (200)', 200));

    // ignore: avoid_print
    print('\nASSISTANT FRAME COST (dev PC, test binding: build + layout + paint, no raster)\n${out.join('\n')}\n');
    for (final s in out) {
      expect(s.worst, lessThan(250), reason: '${s.name}: a single frame took far too long');
    }
    SchedulerBinding.instance.ensureVisualUpdate();
  });
}
