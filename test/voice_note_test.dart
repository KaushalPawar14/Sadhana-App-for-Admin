import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AssociationManager.dart';
import 'package:folk_guide_app/Pages/InteractionLogger.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/Services/VoiceRecorder.dart';
import 'package:folk_guide_app/utils/VoiceNote.dart';
import 'package:folk_guide_app/widgets/VoiceNoteButton.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// Master Part 3 — speak a note, get clean English text.
///
/// The server does the language work (`functions/voiceNote.js`, tested there
/// with the real prompt rules). This is the Guide app's half: recording with a
/// clear state and a timer, the three-minute stop, kind handling of a refused
/// microphone, friendly errors with Retry, and where the text lands — appended,
/// editable, and not saved until the guide saves.

/// A microphone that does what the test tells it to.
class FakeRecorder implements VoiceRecorder {
  bool allowed = true;
  bool startThrows = false;
  VoiceClip? next = VoiceClip(
    bytes: Uint8List.fromList(const [1, 2, 3, 4, 5]),
    mimeType: 'audio/mp4',
    seconds: 12,
  );

  int permissionAsks = 0;
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  bool recording = false;

  @override
  Future<bool> ensurePermission() async {
    permissionAsks++;
    return allowed;
  }

  @override
  Future<void> start() async {
    if (startThrows) throw StateError('mic busy');
    starts++;
    recording = true;
  }

  @override
  Future<VoiceClip?> stop() async {
    stops++;
    recording = false;
    return next;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    recording = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  // -------------------------------------------------------------------------
  // the logic
  // -------------------------------------------------------------------------
  group('the clock', () {
    test('minutes and seconds', () {
      expect(formatElapsed(0), '0:00');
      expect(formatElapsed(7), '0:07');
      expect(formatElapsed(65), '1:05');
      expect(formatElapsed(180), '3:00');
    });

    test('a negative value never shows a minus', () {
      expect(formatElapsed(-4), '0:00');
    });

    test('the limit is three minutes', () => expect(kMaxVoiceSeconds, 180));
  });

  group('putting text in a field', () {
    test('into an empty field it is just the text', () {
      expect(appendNote('', 'He chants 8 rounds.'), 'He chants 8 rounds.');
      expect(appendNote('   \n', 'He chants 8 rounds.'), 'He chants 8 rounds.');
    });

    test('after what is there, on a new paragraph — never replacing it', () {
      expect(appendNote('Met after class.', 'He chants 8 rounds.'),
          'Met after class.\n\nHe chants 8 rounds.');
    });

    test('trailing spaces and newlines do not pile up', () {
      expect(appendNote('Met after class.\n\n  ', 'Next.'), 'Met after class.\n\nNext.');
    });

    test('nothing to add changes nothing', () {
      expect(appendNote('Keep me', ''), 'Keep me');
      expect(appendNote('Keep me', '   '), 'Keep me');
    });
  });

  group('what a guide is told when something goes wrong', () {
    test('a refused microphone says how to turn it back on, and that typing works', () {
      final m = voiceFailureMessage(const MicPermissionDenied());
      expect(m, contains('Settings'));
      expect(m, contains('Microphone'));
      expect(m, contains('type the note'));
    });

    test("the server's own sentence is shown as written", () {
      expect(voiceFailureMessage(HierarchyException('failed-precondition', "I couldn't make that out.")),
          "I couldn't make that out.");
      expect(voiceFailureMessage(HierarchyException('resource-exhausted', 'Please type this one.')),
          'Please type this one.');
    });

    test('a lapsed sign-in says so', () {
      expect(voiceFailureMessage(HierarchyException('unauthenticated', 'x')),
          contains('sign in again'));
    });

    test('a connection problem says so, in words', () {
      for (final code in ['unavailable', 'deadline-exceeded', 'internal']) {
        expect(voiceFailureMessage(HierarchyException(code, 'INTERNAL')),
            contains('Check your connection'), reason: code);
      }
    });

    test('nothing ever reaches the guide as a bare code or a stack trace', () {
      for (final e in <Object>[
        HierarchyException('weird-code', ''),
        StateError('boom'),
        'a string',
      ]) {
        final m = voiceFailureMessage(e);
        expect(m, isNotEmpty);
        expect(m, isNot(contains('StateError')));
        expect(m, isNot(contains('weird-code')));
      }
    });

    test('only a connection failure is worth sending the same recording again', () {
      expect(canRetrySameClip(HierarchyException('unavailable', '')), isTrue);
      expect(canRetrySameClip(HierarchyException('deadline-exceeded', '')), isTrue);
      expect(canRetrySameClip(HierarchyException('failed-precondition', '')), isFalse,
          reason: "a recording that could not be made out will not be better the second time");
      expect(canRetrySameClip(const MicPermissionDenied()), isFalse);
      expect(canRetrySameClip(StateError('x')), isFalse);
    });

    test('the two purposes the server knows', () {
      expect(VoicePurpose.interaction.wire, 'interaction');
      expect(VoicePurpose.associationNote.wire, 'association_note');
    });
  });

  // -------------------------------------------------------------------------
  // the button
  // -------------------------------------------------------------------------
  late FakeRecorder mic;
  late List<Map<String, dynamic>> calls;
  late Object? Function(Map<String, dynamic> args) answer;

  Future<void> pumpButton(
    WidgetTester tester, {
    required List<String> received,
    String existing = '',
    double scale = 1.0,
    bool dark = false,
    bool enabled = true,
  }) async {
    await prepareApp(tester);
    mic = FakeRecorder();
    VoiceRecorder.useForTests(mic);
    addTearDown(() => VoiceRecorder.useForTests(null));
    calls = [];
    answer = (_) => {'text': 'Arjun is keeping 8 rounds daily.'};
    HierarchyApi.useForTests((name, args) async {
      calls.add({'name': name, 'args': args});
      final r = answer(args);
      if (r is Exception) throw r;
      return r as Map<String, dynamic>;
    });

    await pumpScreen(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: VoiceNoteButton(
            purpose: VoicePurpose.interaction,
            studentName: 'Arjun Kumar',
            existingText: () => existing,
            enabled: enabled,
            onText: received.add,
          ),
        ),
      ),
      scale: scale,
      dark: dark,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('idle: just a Speak button — nothing is recorded or asked yet',
      (tester) async {
    await pumpButton(tester, received: []);
    expect(find.byKey(const ValueKey('voice-speak')), findsOneWidget);
    expect(mic.permissionAsks, 0, reason: 'the mic is not asked for until the guide taps');
    expect(mic.starts, 0);
  });

  testWidgets('tapping it records, with a clear state and a running timer',
      (tester) async {
    await pumpButton(tester, received: []);
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump();

    expect(mic.permissionAsks, 1);
    expect(mic.starts, 1);
    expect(find.byKey(const ValueKey('voice-recording')), findsOneWidget);
    expect(find.text('Recording 0:00 / 3:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Recording 0:07 / 3:00'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-cancel')), findsOneWidget);
  });

  testWidgets('Done sends the recording once and hands back the clean text',
      (tester) async {
    final got = <String>[];
    await pumpButton(tester, received: got, existing: 'Met after class.');
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();

    expect(got, ['Arjun is keeping 8 rounds daily.']);
    expect(calls.length, 1);
    final args = calls.single['args'] as Map<String, dynamic>;
    expect(calls.single['name'], 'voiceToEnglishText');
    expect(base64Decode(args['audioBase64'] as String), [1, 2, 3, 4, 5]);
    expect(args['mimeType'], 'audio/mp4');
    expect(args['durationSeconds'], 12);
    expect(args['purpose'], 'interaction');
    expect(args['studentName'], 'Arjun Kumar');
    expect(args['existingText'], 'Met after class.');
    expect(find.byKey(const ValueKey('voice-speak')), findsOneWidget,
        reason: 'back to idle, ready for another');
  });

  testWidgets('no existing text means none is sent', (tester) async {
    await pumpButton(tester, received: []);
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();
    expect((calls.single['args'] as Map).containsKey('existingText'), isFalse);
  });

  testWidgets('while it is being turned into text, the state says so',
      (tester) async {
    await pumpButton(tester, received: []);
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump();
    // hold the answer back
    HierarchyApi.useForTests((name, args) => Future<Map<String, dynamic>>.delayed(
        const Duration(seconds: 3), () => {'text': 'done'}));
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('voice-processing')), findsOneWidget);
    expect(find.text('Turning your voice into text…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('voice-speak')), findsOneWidget);
  });

  testWidgets('Cancel throws the recording away and sends nothing', (tester) async {
    final got = <String>[];
    await pumpButton(tester, received: got);
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const ValueKey('voice-cancel')));
    await tester.pumpAndSettle();

    expect(mic.cancels, 1);
    expect(mic.stops, 0, reason: 'cancelled, not finished');
    expect(calls, isEmpty);
    expect(got, isEmpty);
    expect(find.byKey(const ValueKey('voice-speak')), findsOneWidget);
  });

  testWidgets('it stops by itself at three minutes', (tester) async {
    final got = <String>[];
    await pumpButton(tester, received: got);
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 179));
    expect(find.byKey(const ValueKey('voice-recording')), findsOneWidget);
    expect(mic.stops, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(mic.stops, 1, reason: 'stopped at 3:00 without a tap');
    expect(got, ['Arjun is keeping 8 rounds daily.']);
  });

  testWidgets('leaving the screen mid-recording closes the microphone',
      (tester) async {
    await pumpButton(tester, received: []);
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump(const Duration(seconds: 2));
    expect(mic.recording, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(mic.cancels, 1);
    expect(mic.recording, isFalse);
  });

  testWidgets('a refused microphone is explained kindly, with no Retry that could not help',
      (tester) async {
    await pumpButton(tester, received: []);
    mic.allowed = false;
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-failed')), findsOneWidget);
    expect(find.textContaining('Settings'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-retry')), findsNothing);
    expect(mic.starts, 0);

    await tester.tap(find.byKey(const ValueKey('voice-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-speak')), findsOneWidget);
  });

  testWidgets('a microphone that will not open says so instead of crashing',
      (tester) async {
    await pumpButton(tester, received: []);
    mic.startThrows = true;
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-failed')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recording of nothing is a friendly message, not an empty note',
      (tester) async {
    final got = <String>[];
    await pumpButton(tester, received: got);
    mic.next = null;
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();

    expect(find.textContaining("couldn't make that out"), findsOneWidget);
    expect(got, isEmpty);
    expect(calls, isEmpty, reason: 'nothing worth sending');
  });

  testWidgets("when the server can't make it out, Retry starts a fresh recording",
      (tester) async {
    final got = <String>[];
    await pumpButton(tester, received: got);
    answer = (_) => HierarchyException('failed-precondition', "I couldn't make that out. Try again.");

    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();

    expect(find.text("I couldn't make that out. Try again."), findsOneWidget);
    expect(got, isEmpty);

    answer = (_) => {'text': 'Second time lucky.'};
    await tester.tap(find.byKey(const ValueKey('voice-retry')));
    await tester.pump();
    expect(mic.starts, 2, reason: 'the same recording would fail the same way');
    expect(find.byKey(const ValueKey('voice-recording')), findsOneWidget);
  });

  testWidgets('after a connection failure, Retry sends the SAME recording again',
      (tester) async {
    final got = <String>[];
    await pumpButton(tester, received: got);
    var attempt = 0;
    answer = (_) {
      attempt++;
      return attempt == 1
          ? HierarchyException('unavailable', 'x')
          : {'text': 'It got through.'};
    };

    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-retry')));
    await tester.pumpAndSettle();

    expect(got, ['It got through.']);
    expect(mic.starts, 1, reason: 'he did not have to say it all again');
    expect(calls.length, 2);
    expect(calls[1]['args']['audioBase64'], calls[0]['args']['audioBase64']);
  });

  testWidgets('a success is delivered once, and the recording is not kept',
      (tester) async {
    final got = <String>[];
    await pumpButton(tester, received: got);
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();
    expect(got.length, 1);
    // Nothing left to resend, and no Retry on offer.
    expect(find.byKey(const ValueKey('voice-retry')), findsNothing);
    expect(calls.length, 1);
  });

  testWidgets('disabled while the form is saving', (tester) async {
    await pumpButton(tester, received: [], enabled: false);
    await tester.tap(find.byKey(const ValueKey('voice-speak')), warnIfMissed: false);
    await tester.pump();
    expect(mic.starts, 0);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      final s = '${dark ? 'dark' : 'light'}, text $scale';

      testWidgets('every state fits ($s)', (tester) async {
        await pumpButton(tester, received: [], scale: scale, dark: dark);
        expect(tester.takeException(), isNull, reason: 'idle, $s');

        await tester.tap(find.byKey(const ValueKey('voice-speak')));
        await tester.pump(const Duration(seconds: 65));
        expect(find.byKey(const ValueKey('voice-recording')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'recording, $s');

        answer = (_) => HierarchyException('failed-precondition',
            "I couldn't make that out. Please try again, a little closer to the phone and somewhere quieter.");
        await tester.tap(find.byKey(const ValueKey('voice-done')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('voice-failed')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'failed, $s');
      });
    }
  }

  // -------------------------------------------------------------------------
  // in the two fields
  // -------------------------------------------------------------------------
  testWidgets('Associations → add interaction: the mic fills the interaction text, editable',
      (tester) async {
    await prepareApp(tester);
    mic = FakeRecorder();
    VoiceRecorder.useForTests(mic);
    addTearDown(() => VoiceRecorder.useForTests(null));
    final sent = <Map<String, dynamic>>[];
    HierarchyApi.useForTests((name, args) async {
      sent.add({'name': name, 'args': args});
      if (name == 'voiceToEnglishText') {
        return {'text': 'Ravi said he will chant 12 rounds from Monday.'};
      }
      return <String, dynamic>{};
    });

    await pumpScreen(tester,
        const InteractionLoggerPage(studentUid: 's1', studentName: 'Arjun Kumar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).last;
    await tester.enterText(field, 'Met after the evening program.');
    await tester.pump();

    await tester.ensureVisible(find.byKey(const ValueKey('voice-speak')));
    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();

    final text = tester.widget<TextField>(field).controller!.text;
    expect(text,
        'Met after the evening program.\n\nRavi said he will chant 12 rounds from Monday.',
        reason: 'appended after what was there, not replacing it');

    // It went to the server with this student's name and the existing text for context,
    // and it is NOT saved: the guide has not pressed Save.
    final voice = sent.singleWhere((c) => c['name'] == 'voiceToEnglishText');
    expect(voice['args']['studentName'], 'Arjun Kumar');
    expect(voice['args']['existingText'], 'Met after the evening program.');
    expect(voice['args']['purpose'], 'interaction');
    expect(sent.where((c) => c['name'] != 'voiceToEnglishText'), isEmpty,
        reason: 'speaking a note saves nothing and notifies nobody');

    // still editable
    await tester.enterText(field, '$text Edited by hand.');
    expect(tester.widget<TextField>(field).controller!.text, endsWith('Edited by hand.'));
  });

  testWidgets('Associations → complete a meeting: the mic fills the notes', (tester) async {
    final db = await prepareApp(tester);
    mic = FakeRecorder();
    VoiceRecorder.useForTests(mic);
    addTearDown(() => VoiceRecorder.useForTests(null));
    HierarchyApi.useForTests((name, args) async {
      if (name == 'voiceToEnglishText') {
        return {'text': 'We discussed his exam week and agreed a smaller target.'};
      }
      return <String, dynamic>{};
    });

    await pumpScreen(tester, const AssociationManagerPage());
    await tester.pumpAndSettle();
    // Confirmed meetings, the ones that can be completed, are on the second tab.
    await tester.tap(find.text('Upcoming & History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark Complete').first);
    await tester.pumpAndSettle();

    expect(find.text('Notes from the meeting'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-speak')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-speak')));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();

    expect(find.text('We discussed his exam week and agreed a smaller target.'),
        findsOneWidget);

    // Saving still works exactly as before, and writes what is in the box.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    final meetings = await db.collection('associations').get();
    expect(
        meetings.docs.any((d) =>
            (d.data()['guideNotes'] ?? '') ==
            'We discussed his exam week and agreed a smaller target.'),
        isTrue);
  });

  for (final scale in kScales) {
    for (final dark in [false, true]) {
      testWidgets('the meeting-notes dialog with the mic fits at text $scale, '
          '${dark ? 'dark' : 'light'}', (tester) async {
        await prepareApp(tester);
        VoiceRecorder.useForTests(FakeRecorder());
        addTearDown(() => VoiceRecorder.useForTests(null));
        await pumpScreen(tester, const AssociationManagerPage(), scale: scale, dark: dark);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Upcoming & History'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark Complete').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('voice-speak')));
        await tester.pump(const Duration(seconds: 70));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('voice-recording')), findsOneWidget);
      });
    }
  }
}
