import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentLogPage.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Pages/HolisticSuggestion.dart';
import 'package:folk_guide_app/Pages/InteractionLogger.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/Services/VoiceRecorder.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/utils/AiMarkdown.dart';
import 'package:folk_guide_app/widgets/AiText.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// AI text is shown as real formatting, never as Markdown symbols - in every place the Guide app shows it:
/// the assistant (chat, confirmation card, log), the student's suggestions, an interaction's analysis (the card
/// and the editor's fields), a voice note in its box, and the other screens that carry AI words.
/// At text size 1.0 / 1.3 / 1.6, light and dark.

/// What the AI really writes.
const answer = 'Here is the plan for **Arjun Kumar**:\n\n'
    '## This week\n'
    '1. **Call** him on *Sunday*\n'
    '2. Share the `new book`\n\n'
    '- Ask about sleep\n'
    '- Mention the [roadmap](https://example.com/x)\n\n'
    'Keep it **kind**.';

/// Every piece of text a screen is showing: ordinary and rich text, and text in fields.
List<String> shownText(WidgetTester tester) => [
      for (final w in tester.widgetList<RichText>(find.byType(RichText))) w.text.toPlainText(),
      for (final w in tester.widgetList<EditableText>(find.byType(EditableText))) w.controller.text,
    ];

final RegExp marks = RegExp(r'\*|`|(^|\n)\s{0,3}#{1,6}\s|\]\(|<\/?[a-z]');

void expectNoMarks(WidgetTester tester, {String? where}) {
  for (final t in shownText(tester)) {
    expect(marks.hasMatch(t), isFalse, reason: '${where ?? 'screen'} shows Markdown symbols in: "$t"');
  }
}

/// Is [word] drawn bold somewhere on screen?
bool drawnBold(WidgetTester tester, String word) {
  bool walk(InlineSpan span, FontWeight? inherited) {
    if (span is! TextSpan) return false;
    final weight = span.style?.fontWeight ?? inherited;
    if (span.text != null && span.text!.contains(word) && weight != null && weight.index >= FontWeight.w600.index) return true;
    return (span.children ?? const []).any((c) => walk(c, weight));
  }

  return tester.widgetList<RichText>(find.byType(RichText)).any((w) => walk(w.text, w.text.style?.fontWeight));
}

class _Mic implements VoiceRecorder {
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<VoiceClip?> stop() async => VoiceClip(bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'audio/mp4', seconds: 4);
  @override
  Future<void> cancel() async {}
}

Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await letDataArrive(tester, frames: 6);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  // ------------------------------------------------------------------------------------------ the shared widget
  group('AiText', () {
    for (final scale in kScales) {
      for (final dark in [false, true]) {
        final label = 'text ${scale}x, ${dark ? 'dark' : 'light'}';

        testWidgets('draws bold, italic, headings and lists as formatting, with no symbols, at $label', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(guideHost(const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: AiText(answer, selectable: true))), dark: dark));
          await tester.pump();
          expectNoMarks(tester);
          expect(drawnBold(tester, 'Arjun Kumar'), isTrue, reason: '**bold** is bold');
          expect(drawnBold(tester, 'This week'), isTrue, reason: 'a heading is bold');
          expect(find.textContaining('Sunday'), findsOneWidget);
          expect(find.text('1.'), findsOneWidget);
          expect(find.text('2.'), findsOneWidget);
          expect(find.text('•'), findsNWidgets(2), reason: 'two bullets');
          expect(find.textContaining('https'), findsNothing, reason: 'a link keeps its words, not its address');
          expect(find.byType(SelectionArea), findsOneWidget, reason: 'still selectable');
          expectNoOverflow(tester);
        });
      }
    }

    testWidgets('a plain sentence is drawn exactly as before (Text / SelectableText), nothing extra', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(const Scaffold(body: Column(children: [AiText('Just a sentence.'), AiText('Copy me.', selectable: true)]))));
      expect(find.text('Just a sentence.'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(SelectionArea), findsNothing);
    });

    testWidgets('with maxLines a list runs on as lines inside one text and is cut with an ellipsis', (tester) async {
      phone(tester, 1.3);
      await tester.pumpWidget(guideHost(const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: AiText('- **one** item\n- two item\n- three item\n- four item', maxLines: 2)))));
      final text = tester.widget<RichText>(find.byType(RichText).last);
      expect(text.maxLines, 2);
      expect(text.text.toPlainText().startsWith('• one item\n• two item'), isTrue);
      expectNoMarks(tester);
      expectNoOverflow(tester);
    });

    testWidgets('nothing in it can be tapped or opened', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(const Scaffold(body: AiText('[click](https://evil.example) <a href="javascript:x()">now</a> <script>bad()</script>'))));
      expect(find.byType(GestureDetector).evaluate().where((e) => e.widget is GestureDetector && (e.widget as GestureDetector).onTap != null), isEmpty);
      final plain = shownText(tester).join(' ');
      expect(plain.contains('evil'), isFalse);
      expect(plain.contains('javascript'), isFalse);
      expect(plain.contains('<'), isFalse);
      expect(plain.contains('click'), isTrue);
    });
  });

  // ------------------------------------------------------------------------------------------ the assistant
  group('the assistant', () {
    late List<Map<String, dynamic>> replies;
    String spoken = 'Who has **not** filed today:\n- Arjun\n- Bhima';

    Future<AgentController> wire(WidgetTester tester) async {
      final db = await prepareApp(tester);
      replies = [];
      HierarchyApi.useForTests((name, args) async {
        if (name == 'guideAgentTurn') return replies.removeAt(0);
        if (name == 'voiceToEnglishText') return {'text': spoken};
        return <String, dynamic>{};
      });
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)));
      AgentSession.useForTests(c);
      addTearDown(() => AgentSession.useForTests(null));
      return c;
    }

    Future<void> say(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const ValueKey('agent-input')), text);
      await tester.tap(find.byKey(const ValueKey('agent-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        final label = 'text ${scale}x, ${dark ? 'dark' : 'light'}';

        testWidgets('an answer is formatted and selectable, a confirmation card too, at $label', (tester) async {
          final c = await wire(tester);
          await pumpScreen(tester, AgentPage(controller: c), scale: scale, dark: dark);
          await tester.pump(const Duration(milliseconds: 100));

          replies.add({'sessionId': 'sess12345', 'status': 'message', 'text': answer, 'links': <Map<String, dynamic>>[]});
          await say(tester, 'plan for Arjun');
          expectNoMarks(tester, where: 'the answer');
          expect(drawnBold(tester, 'Arjun Kumar'), isTrue);
          expect(find.byType(SelectionArea), findsOneWidget, reason: 'the answer stays selectable');
          expectNoOverflow(tester, reason: 'answer');

          replies.add({
            'sessionId': 'sess12345',
            'status': 'confirm',
            'text': 'I can do that:\n- **Meet** Arjun',
            'proposal': {
              'id': 'p1',
              'tainted': false,
              'headsUp': ['Check the **date** first.'],
              'actions': [
                {
                  'callId': 'c1',
                  'tool': 'meeting_request',
                  'args': {'studentUid': 's1'},
                  'title': 'Meet **Arjun Kumar**',
                  'lines': [
                    {'label': 'Message to the student', 'value': 'Let us **catch up** about:\n- sleep\n- *japa*', 'items': <String>[]},
                  ],
                  'notifies': <String>[],
                  'double': false,
                },
              ],
            },
          });
          await say(tester, 'meet him');
          expect(find.byKey(const ValueKey('agent-confirm')), findsOneWidget);
          expectNoMarks(tester, where: 'the confirmation card');
          expect(drawnBold(tester, 'catch up'), isTrue);
          expectNoOverflow(tester, reason: 'card');
        });
      }
    }

    testWidgets('a voice note lands in the box as clean plain text (no symbols), editable, sent by nothing', (tester) async {
      final c = await wire(tester);
      VoiceRecorder.useForTests(_Mic());
      addTearDown(() => VoiceRecorder.useForTests(null));
      await pumpScreen(tester, AgentPage(controller: c));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-done')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const ValueKey('agent-input')));
      expect(field.controller!.text, 'Who has not filed today:\n• Arjun\n• Bhima');
      expect(marks.hasMatch(field.controller!.text), isFalse);
    });

    testWidgets("the HOD's log shows the assistant's titles, lines and notes formatted", (tester) async {
      final db = await prepareApp(tester);
      await db.collection('agentActions').add({
        'adminId': 'G', 'adminName': 'Gopal Das', 'role': 'GUIDE', 'createdMs': DateTime(2026, 10, 23, 16).millisecondsSinceEpoch,
        'request': 'meet Arjun', 'status': 'executed', 'confirmations': 1,
        'actions': [
          {'callId': 'c1', 'tool': 'meeting_request', 'title': 'Meet **Arjun Kumar**', 'lines': [{'label': 'Message', 'value': 'Let us **catch up**'}]},
        ],
        'results': [{'callId': 'c1', 'tool': 'meeting_request', 'ok': false, 'error': 'Could **not** save'}],
        'note': 'Prepared with *care*',
      });
      await pumpScreen(tester, const AgentLogPage());
      await letDataArrive(tester);
      expectNoMarks(tester, where: 'the log');
      expect(drawnBold(tester, 'Arjun Kumar'), isTrue);
      expectNoOverflow(tester);
    });
  });

  // ------------------------------------------------------------------------------------------ suggestions
  group("a student's AI suggestions", () {
    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('show bold and lists, never symbols, at text ${scale}x, ${dark ? 'dark' : 'light'}', (tester) async {
          final db = await prepareApp(tester);
          await db.collection('holisticSuggestions').doc('s1').set({
            'suggestions': [
              {'action': 'Invite him to the **Sunday** programme', 'why': 'He has *not* met anyone in **three weeks**:\n- no interactions\n- no meetings', 'next': 'Ask him on **Friday** for 5 pm'},
              {'action': '## Assign book 2', 'why': 'Book 1 was done in `May`', 'next': '1. Hand it over\n2. Note it down'},
            ],
          });
          await pumpScreen(
            tester,
            const Scaffold(body: SingleChildScrollView(child: HolisticSuggestionSection(studentUid: 's1', studentName: 'Arjun Kumar'))),
            scale: scale,
            dark: dark,
          );
          await letDataArrive(tester);
          expectNoMarks(tester, where: 'the suggestions');
          expect(drawnBold(tester, 'Sunday'), isTrue);
          expect(drawnBold(tester, 'three weeks'), isTrue);
          expect(find.textContaining('Assign book 2'), findsOneWidget);
          expectNoOverflow(tester);
        });
      }
    }
  });

  // ------------------------------------------------------------------------------------------ interactions
  group("an interaction's analysis", () {
    Future<String> seed(FakeFirebaseFirestore db) async {
      final ref = await db.collection('interactionLogs').add({
        'studentUid': 's1',
        'studentName': 'Arjun Kumar',
        'guideId': 'G',
        'status': 'approved',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
        'interactionDate': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
        'approvedSummary': {
          'interactionType': 'Phone call',
          'studentConcerns': 'Worried about **exams**:\n- maths\n- physics',
          'commitmentsMade': 'Will chant *16 rounds*',
          'recommendedNextAction': 'Call him on **Sunday**',
          'recommendedReasoning': 'He opened up about `exams`:\n- needs **support**',
        },
        'scopeGuide': 'G',
        'scopeTeam': 'G',
      });
      return ref.id;
    }

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('the card shows the suggested next action formatted, at text ${scale}x, ${dark ? 'dark' : 'light'}', (tester) async {
          final db = await prepareApp(tester);
          await seed(db);
          await pumpScreen(tester, const InteractionLoggerPage(studentUid: 's1', studentName: 'Arjun Kumar'), scale: scale, dark: dark);
          await settle(tester, rounds: 3);
          await letDataArrive(tester, frames: 12);
          expect(find.text('Suggested next action'), findsWidgets);
          expectNoMarks(tester, where: 'the interaction card');
          expect(drawnBold(tester, 'Sunday'), isTrue);
          expectNoOverflow(tester);
        });
      }
    }

    testWidgets('the editor fills its boxes with clean plain text, ready to edit', (tester) async {
      final db = await prepareApp(tester);
      final id = await seed(db);
      await pumpScreen(tester, InteractionDetailPage(docId: id, studentName: 'Arjun Kumar'));
      await settle(tester, rounds: 3);
      await letDataArrive(tester, frames: 12);
      final texts = shownText(tester);
      expect(texts.any((t) => t.contains('Worried about exams')), isTrue, reason: 'the words are there');
      expectNoMarks(tester, where: 'the interaction editor');
    });
  });

  // ------------------------------------------------------------------------------------------ every place uses the one widget
  group('every place that shows AI text uses the one shared widget', () {
    // file -> a line that must be drawn with AiText, so a screen cannot quietly go back to a raw Text
    const sites = <String, List<String>>{
      'lib/Pages/AgentPage.dart': ['AiText(e.text, selectable: true', 'AiText(l.value', 'AiText(a.title', 'AiText(line,', "AiText(result.\$2"],
      'lib/Pages/AgentLogPage.dart': ["AiText((a['title']", "AiText((d['note'])"],
      'lib/Pages/HolisticSuggestion.dart': ['AiText(\n                s.action', 'AiText(\n                  s.why', 'AiText(\n                      s.next'],
      'lib/Pages/InteractionLogger.dart': ['AiText(action', 'AiText(\n                        reasoning', 'plainAiText((value ?? \'\').toString())'],
      'lib/Pages/AssociationManager.dart': ['AiText(body, maxLines: 2'],
      'lib/Pages/WeeklyPlanning.dart': ['AiText(item.action'],
      'lib/Pages/PriorityStudents.dart': ['AiText(\n                      flag.label'],
      'lib/Pages/FlaggedMessages.dart': ['AiText(\n                  pastoralReason'],
      'lib/Pages/GoalWeeklyPhasePage.dart': ['AiText(pending.note'],
      'lib/widgets/VoiceNoteButton.dart': ['widget.onText(plainAiText(text))'],
    };
    sites.forEach((file, needles) {
      test(file, () {
        final src = File(file).readAsStringSync().replaceAll('\r\n', '\n');
        for (final n in needles) {
          expect(src.contains(n), isTrue, reason: '$file should contain: $n');
        }
      });
    });

    test('no AI text goes through a SelectableText / raw Text of its own any more', () {
      final src = File('lib/Pages/AgentPage.dart').readAsStringSync();
      expect(src.contains('SelectableText(e.text'), isFalse);
    });
  });
}
