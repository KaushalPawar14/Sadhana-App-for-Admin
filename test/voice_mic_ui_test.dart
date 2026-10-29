import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/Services/VoiceRecorder.dart';
import 'package:folk_guide_app/utils/VoiceNote.dart';
import 'package:folk_guide_app/widgets/ThinkingDots.dart';
import 'package:folk_guide_app/widgets/VoiceNoteButton.dart';
import 'package:folk_guide_app/widgets/VoiceWaveform.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// The mic: fast and smooth. A head start to the server the moment recording begins, a live waveform while it records, a
/// processing animation, and the words appearing smoothly in the box. Text size 1.0 / 1.3 / 1.6, light and dark.

/// A microphone that also reports how loud the voice is.
class _Mic implements VoiceRecorder, VoiceLevels {
  final StreamController<double> loud = StreamController<double>.broadcast();
  int starts = 0;

  @override
  Stream<double> get levels => loud.stream;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<VoiceClip?> stop() async => VoiceClip(bytes: Uint8List.fromList([1, 2, 3, 4]), mimeType: 'audio/mp4', seconds: 5);
  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  late _Mic mic;
  late List<Map<String, dynamic>> warms;
  late List<Map<String, dynamic>> recordings;
  Completer<Map<String, dynamic>>? holdAnswer;
  late TextEditingController box;

  Future<void> open(WidgetTester tester, {double scale = 1.0, bool dark = false, bool reduce = true}) async {
    await prepareApp(tester);
    mic = _Mic();
    VoiceRecorder.useForTests(mic);
    addTearDown(() {
      VoiceRecorder.useForTests(null);
      mic.loud.close();
    });
    warms = [];
    recordings = [];
    holdAnswer = null;
    box = TextEditingController(text: 'Met after the program.');
    HierarchyApi.useForTests((name, args) async {
      if (args['warm'] == true) {
        warms.add(args);
        return {'text': '', 'warmed': true};
      }
      recordings.add(args);
      if (holdAnswer != null) return holdAnswer!.future;
      return {'text': 'Ravi will chant twelve rounds from Monday.'};
    });
    await pumpScreen(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(key: const ValueKey('box'), controller: box, maxLines: null),
              VoiceNoteButton(
                purpose: VoicePurpose.interaction,
                studentName: 'Ravi',
                existingText: () => box.text,
                onText: (clean) => revealAppend(box, clean, animate: !reduce),
              ),
            ],
          ),
        ),
      ),
      scale: scale,
      dark: dark,
      reduce: reduce,
    );
  }

  group('a head start', () {
    testWidgets('the moment recording begins, the server is told to warm up; it is told once, not at Done and not on Retry', (tester) async {
      await open(tester);
      expect(warms, isEmpty);
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(warms.length, 1);
      expect(warms.single, {'warm': true}, reason: 'no audio, no text, nothing about the student');
      expect(recordings, isEmpty, reason: 'it is not a recording');
      await tester.tap(find.byKey(const ValueKey('voice-done')));
      await tester.pumpAndSettle();
      expect(warms.length, 1);
      expect(recordings.length, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a warm-up that fails changes nothing for the guide', (tester) async {
      await open(tester);
      HierarchyApi.useForTests((name, args) async {
        if (args['warm'] == true) throw HierarchyException('unavailable', 'DOWN');
        return {'text': 'Fine.'};
      });
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('voice-recording')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-failed')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('voice-cancel')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the live waveform', () {
    testWidgets('while recording, the bars follow how loud the voice is; when quiet they fall back', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      final wave = find.byKey(const ValueKey('voice-waveform'));
      expect(wave, findsOneWidget);
      VoiceLevelTrail trail() => tester.widget<VoiceWaveform>(wave).trail;
      expect(trail().peak, 0.0, reason: 'silence until the voice is heard');
      for (final v in [.2, .5, .9, .7, .3]) {
        mic.loud.add(v);
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(trail().peak, closeTo(.9, 1e-9));
      expect(trail().levels.last, closeTo(.3, 1e-9), reason: 'the newest reading is on the right');
      for (var i = 0; i < 40; i++) {
        mic.loud.add(0);
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(trail().peak, 0.0, reason: 'the old bars have slid off to the left');
      await tester.tap(find.byKey(const ValueKey('voice-cancel')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('paused, the waveform rests at a flat line and stops listening; resuming brings it back', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      mic.loud.add(.8);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const ValueKey('voice-pause')));
      await tester.pump();
      await tester.pump();
      final wave = find.byKey(const ValueKey('voice-waveform'));
      expect(tester.widget<VoiceWaveform>(wave).paused, isTrue);
      mic.loud.add(.9);
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<VoiceWaveform>(wave).trail.peak, 0.0, reason: 'not listening while paused');
      await tester.tap(find.byKey(const ValueKey('voice-resume')));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<VoiceWaveform>(wave).paused, isFalse);
      mic.loud.add(.6);
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<VoiceWaveform>(wave).trail.peak, closeTo(.6, 1e-9));
      await tester.tap(find.byKey(const ValueKey('voice-cancel')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });

    test('the trail keeps a fixed number of bars and never holds a level outside 0..1', () {
      final t = VoiceLevelTrail(bars: 8);
      for (var i = 0; i < 20; i++) {
        t.add(i / 10);
      }
      expect(t.levels.length, 8);
      expect(t.levels.every((l) => l >= 0 && l <= 1), isTrue);
      expect(t.levels.last, 1.0);
      t.clear();
      expect(t.peak, 0.0);
    });

    testWidgets('a recorder that cannot report loudness still records: the waveform just stays flat', (tester) async {
      await prepareApp(tester);
      final plain = _PlainMic();
      VoiceRecorder.useForTests(plain);
      addTearDown(() => VoiceRecorder.useForTests(null));
      HierarchyApi.useForTests((name, args) async => {'text': 'ok'});
      await pumpScreen(tester, Scaffold(body: VoiceNoteButton(purpose: VoicePurpose.assistant, onText: (_) {})));
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      expect(find.byKey(const ValueKey('voice-recording')), findsOneWidget);
      expect(tester.widget<VoiceWaveform>(find.byKey(const ValueKey('voice-waveform'))).trail.peak, 0.0);
      await tester.tap(find.byKey(const ValueKey('voice-cancel')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('processing and the words appearing', () {
    testWidgets('while the text is being made, a thinking animation shows; the guide cannot start a second recording', (tester) async {
      await open(tester, reduce: false);
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      holdAnswer = Completer<Map<String, dynamic>>();
      await tester.tap(find.byKey(const ValueKey('voice-done')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('voice-processing')), findsOneWidget);
      expect(find.text('Turning your voice into text…'), findsOneWidget);
      expect(tester.state<ThinkingDotsState>(find.byKey(const ValueKey('voice-dots'))).moving, isTrue);
      expect(find.byKey(const ValueKey('voice-speak')), findsNothing);
      holdAnswer!.complete({'text': 'Done now.'});
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the words appear a few at a time, never replacing what was there, and end exactly as the clean text', (tester) async {
      await open(tester, reduce: false);
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-done')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final seen = <String>[];
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(box.text);
      }
      const full = 'Met after the program.\n\nRavi will chant twelve rounds from Monday.';
      expect(box.text, full);
      final partial = seen.where((t) => t != 'Met after the program.' && t != full).toList();
      expect(partial, isNotEmpty, reason: 'it did not all appear at once');
      expect(partial.every((t) => full.startsWith(t) && t.startsWith('Met after the program.')), isTrue, reason: 'each step is a prefix of the final text: $partial');
      // growing, never shrinking
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i].length, greaterThanOrEqualTo(seen[i - 1].length));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('with reduce-motion the words are simply there', (tester) async {
      await open(tester, reduce: true);
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-done')));
      await tester.pumpAndSettle();
      expect(box.text, 'Met after the program.\n\nRavi will chant twelve rounds from Monday.');
    });

    test('revealAppend: immediate when asked, ends with the cursor at the end, and says when it is done', () async {
      final c = TextEditingController(text: 'One.');
      var done = 0;
      revealAppend(c, 'Two three four.', animate: false, done: () => done++);
      expect(c.text, 'One.\n\nTwo three four.');
      expect(c.selection.baseOffset, c.text.length);
      expect(done, 1);
      final empty = TextEditingController();
      revealAppend(empty, 'Hello there friend.', animate: false);
      expect(empty.text, 'Hello there friend.');
      final noop = TextEditingController(text: 'Same');
      revealAppend(noop, '   ', animate: true);
      expect(noop.text, 'Same');
    });
  });

  for (final scale in kScales) {
    for (final dark in [false, true]) {
      testWidgets('the recording panel with its waveform, and the processing line, fit at text ${scale}x, ${dark ? 'dark' : 'light'}', (tester) async {
        await open(tester, scale: scale, dark: dark);
        await tester.tap(find.byKey(const ValueKey('voice-speak')));
        await tester.pump();
        for (final v in [.2, .9, .5, .7]) {
          mic.loud.add(v);
          await tester.pump(const Duration(milliseconds: 80));
        }
        expectNoOverflow(tester);
        holdAnswer = Completer<Map<String, dynamic>>();
        await tester.tap(find.byKey(const ValueKey('voice-done')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expectNoOverflow(tester);
        holdAnswer!.complete({'text': 'x y z'});
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}

class _PlainMic implements VoiceRecorder {
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<VoiceClip?> stop() async => VoiceClip(bytes: Uint8List.fromList([1]), mimeType: 'audio/mp4', seconds: 1);
  @override
  Future<void> cancel() async {}
}
