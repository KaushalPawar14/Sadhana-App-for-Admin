import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Pages/InteractionLogger.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// The buttons a guide now has on an interaction (Delete interaction, Remove follow-up — each asks first), and the assistant's
/// question card ("which of these two?") with choices to tap, side by side. Text size 1.0 / 1.3 / 1.6, light and dark.

Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await letDataArrive(tester, frames: 6);
  }
}

/// Lets snackbars and dialog timers run out, so the test ends cleanly.
Future<void> drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  // ------------------------------------------------------------------------------------------ the buttons
  group('interaction buttons', () {
    Future<(FakeFirebaseFirestore, String)> openList(WidgetTester tester, {double scale = 1.0, bool dark = false}) async {
      final db = await prepareApp(tester);
      final logs = await db.collection('interactionLogs').where('studentUid', isEqualTo: 's1').get();
      final id = logs.docs.firstWhere((d) => (d.data()['approvedSummary'] as Map?)?['followUpDate'] != null).id;
      await pumpScreen(tester, const InteractionLoggerPage(studentUid: 's1', studentName: 'Arjun Kumar'), scale: scale, dark: dark);
      await settle(tester);
      await letDataArrive(tester, frames: 12);
      return (db, id);
    }

    testWidgets('"Remove follow-up" asks first; Keep it changes nothing; Remove clears only the follow-up date', (tester) async {
      final (db, id) = await openList(tester);
      expect(find.byKey(ValueKey('follow-up-remove-$id')), findsOneWidget);
      expect(find.textContaining('Follow-up '), findsWidgets);
      await tester.tap(find.byKey(ValueKey('follow-up-remove-$id')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Remove this follow-up?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('follow-up-keep')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(((await db.collection('interactionLogs').doc(id).get()).data()!['approvedSummary'] as Map)['followUpDate'], isNotNull);

      await tester.tap(find.byKey(ValueKey('follow-up-remove-$id')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('follow-up-remove-yes')));
      await tester.pump();
      await settle(tester, rounds: 2);
      await tester.pump(const Duration(milliseconds: 400));
      final after = (await db.collection('interactionLogs').doc(id).get()).data()!;
      expect((after['approvedSummary'] as Map).containsKey('followUpDate'), isFalse);
      expect((after['approvedSummary'] as Map)['recommendedNextAction'], 'Call about the retreat', reason: 'the interaction stays');
      expect(find.byKey(ValueKey('follow-up-remove-$id')), findsNothing, reason: 'its row is gone');
      await drain(tester);
    });

    testWidgets('"Delete interaction" asks first; Cancel keeps it; Delete removes it', (tester) async {
      final (db, id) = await openList(tester);
      await tester.tap(find.byKey(ValueKey('interaction-delete-$id')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Delete 1 interaction log?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect((await db.collection('interactionLogs').doc(id).get()).exists, isTrue);

      await tester.tap(find.byKey(ValueKey('interaction-delete-$id')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await settle(tester, rounds: 3);
      expect((await db.collection('interactionLogs').doc(id).get()).exists, isFalse);
      await drain(tester);
    });

    testWidgets('the detail page has Delete interaction too, which asks and then leaves the page', (tester) async {
      final db = await prepareApp(tester);
      final id = (await db.collection('interactionLogs').where('studentUid', isEqualTo: 's1').get()).docs.first.id;
      await pumpScreen(tester, InteractionDetailPage(docId: id, studentName: 'Arjun Kumar'));
      await settle(tester);
      await letDataArrive(tester, frames: 12);
      await tester.ensureVisible(find.byKey(const ValueKey('interaction-detail-delete')));
      await tester.tap(find.byKey(const ValueKey('interaction-detail-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Delete 1 interaction log?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await settle(tester, rounds: 3);
      expect((await db.collection('interactionLogs').doc(id).get()).exists, isFalse);
      await drain(tester);
    });

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('the card with its follow-up row and buttons fits at text ${scale}x, ${dark ? 'dark' : 'light'}', (tester) async {
          await openList(tester, scale: scale, dark: dark);
          expect(find.text('Delete interaction'), findsWidgets);
          expect(find.text('Remove follow-up'), findsWidgets);
          expectNoOverflow(tester);
        });
      }
    }
  });

  // ------------------------------------------------------------------------------------------ the question card
  group('the assistant asks which one', () {
    late FakeFirebaseFirestore db;
    late List<Map<String, dynamic>> replies;
    late List<Map<String, dynamic>> requests;

    Future<AgentController> wire(WidgetTester tester) async {
      db = await prepareApp(tester);
      replies = [];
      requests = [];
      HierarchyApi.useForTests((name, args) async {
        requests.add(args);
        return replies.removeAt(0);
      });
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)));
      AgentSession.useForTests(c);
      addTearDown(() => AgentSession.useForTests(null));
      return c;
    }

    Map<String, dynamic> question([List<Map<String, dynamic>>? choices]) => {
          'sessionId': 'sess12345', 'status': 'question', 'questionsLeft': 18, 'questionLimit': 20, 'text': 'Bhima Sen has two follow-ups for 3 Nov that look the same.',
          'question': 'Which one should I remove?',
          'choices': choices ??
              [
                {'label': '20 Oct, 6:00 pm — **Call** about his Gita reading', 'detail': 'Follow-up 3 Nov\nNotes: We spoke about his japa', 'reply': 'Remove the follow-up on the 6:00 pm interaction (i_f1)'},
                {'label': '20 Oct, 6:30 pm — Call about Gita reading', 'detail': 'Follow-up 3 Nov', 'reply': 'Remove the follow-up on the 6:30 pm interaction (i_f2)'},
              ],
        };

    Future<void> say(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const ValueKey('agent-input')), text);
      await tester.tap(find.byKey(const ValueKey('agent-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    testWidgets('the card shows the question and both records side by side; tapping one sends its words and marks it', (tester) async {
      final c = await wire(tester);
      await pumpScreen(tester, AgentPage(controller: c));
      await tester.pump(const Duration(milliseconds: 100));
      replies.add(question());
      await say(tester, 'delete the duplicate follow-up for Bhima');
      expect(find.text('Which one should I remove?'), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-choice-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-choice-1')), findsOneWidget);
      final a = tester.getRect(find.byKey(const ValueKey('agent-choice-0')));
      final b = tester.getRect(find.byKey(const ValueKey('agent-choice-1')));
      expect((a.top - b.top).abs() < 1 && a.right <= b.left, isTrue, reason: 'side by side, to compare');
      expect((a.height - b.height).abs() < 1, isTrue, reason: 'the same height');
      expect(find.textContaining('**'), findsNothing, reason: 'no Markdown symbols');
      expectNoOverflow(tester);

      replies.add({'sessionId': 'sess12345', 'status': 'confirm', 'questionsLeft': 17, 'questionLimit': 20, 'proposal': {
        'id': 'p1', 'tainted': false, 'headsUp': <String>[],
        'actions': [{'callId': 'c1', 'tool': 'interaction_followup_remove', 'args': <String, dynamic>{}, 'title': 'Remove a follow-up', 'lines': [], 'notifies': <String>[], 'double': true}],
      }});
      await tester.tap(find.byKey(const ValueKey('agent-choice-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(requests.last['text'], 'Remove the follow-up on the 6:30 pm interaction (i_f2)', reason: 'the tap is the guide\'s next message');
      expect(requests.last['sessionId'], 'sess12345');
      final entry = c.entries.whereType<QuestionEntry>().single;
      expect(entry.chosen, 1);
      expect(find.byKey(const ValueKey('agent-confirm')), findsOneWidget, reason: 'the assistant went on to propose the removal, to be confirmed');
      // answered: the other choice can no longer be tapped
      await tester.tap(find.byKey(const ValueKey('agent-choice-0')), warnIfMissed: false);
      await tester.pump();
      expect(requests.length, 2);
    });

    testWidgets('three or more choices stack; at text 1.6 two choices stack too', (tester) async {
      final c = await wire(tester);
      await pumpScreen(tester, AgentPage(controller: c), scale: 1.6);
      await tester.pump(const Duration(milliseconds: 100));
      replies.add(question());
      await say(tester, 'which?');
      final a = tester.getRect(find.byKey(const ValueKey('agent-choice-0')));
      final b = tester.getRect(find.byKey(const ValueKey('agent-choice-1')));
      expect(b.top >= a.bottom - 1, isTrue, reason: 'stacked when the text is large');
      expectNoOverflow(tester);
    });

    testWidgets('a question in a saved chat comes back as the card: answered ones read-only, the last one still open', (tester) async {
      final c = await wire(tester);
      const choices = [
        {'label': 'First', 'detail': 'd1', 'reply': 'the first'},
        {'label': 'Second', 'detail': 'd2', 'reply': 'the second'},
      ];
      await db.collection('agentChats').doc('qchat').set({'adminId': 'H', 'title': 'Q', 'questions': 2, 'questionLimit': 20, 'tasks': 0, 'successful': 0, 'failed': 0, 'updatedMs': 1, 'createdMs': 1});
      final lines = db.collection('agentChats').doc('qchat').collection('entries');
      await lines.doc('000000').set({'seq': 0, 'kind': 'question', 'question': 'Older question?', 'choices': choices});
      await lines.doc('000001').set({'seq': 1, 'kind': 'user', 'text': 'the first'});
      await lines.doc('000002').set({'seq': 2, 'kind': 'question', 'question': 'Latest question?', 'choices': choices});
      await pumpScreen(tester, AgentPage(controller: c));
      tester.view.physicalSize = const Size(360, 2600);
      await c.openChat('qchat');
      await tester.pump();
      final questions = c.entries.whereType<QuestionEntry>().toList();
      expect(questions.length, 2);
      expect(questions[0].answered, isTrue, reason: 'something came after it');
      expect(questions[1].answered, isFalse, reason: 'nothing came after it: still open');
      expect(find.text('Older question?'), findsOneWidget);
      expect(find.text('Latest question?'), findsOneWidget);
    });

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('the question card fits at text ${scale}x, ${dark ? 'dark' : 'light'}', (tester) async {
          final c = await wire(tester);
          await pumpScreen(tester, AgentPage(controller: c), scale: scale, dark: dark);
          await tester.pump(const Duration(milliseconds: 100));
          replies.add(question([
            {'label': 'A very long first choice label that goes on to describe a record in some detail for comparing', 'detail': 'Follow-up 3 Nov 2026 · Notes: a long note about the conversation and what was agreed, with several words', 'reply': 'one'},
            {'label': 'Second', 'detail': 'Short', 'reply': 'two'},
            {'label': 'Third', 'reply': 'three'},
          ]));
          await say(tester, 'which?');
          expect(find.byKey(const ValueKey('agent-choice-2')), findsOneWidget);
          expectNoOverflow(tester);
        });
      }
    }
  });
}
