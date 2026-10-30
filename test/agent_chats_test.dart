import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentChatsPage.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/widgets/GuideSurface.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// The assistant's CHAT SESSIONS: a New chat only by its button, a saved chat per session (title, counts), the history
/// list, opening and continuing an old chat, 20 questions per session, the daily cap, and each admin's own chats only.
/// At text size 1.0 / 1.3 / 1.6, light and dark.

Map<String, dynamic> _reply(String status, [Map<String, dynamic> more = const {}]) => {'sessionId': 'sess12345', 'status': status, 'questionsLeft': 19, 'questionLimit': 20, ...more};

Map<String, dynamic> _proposal() => {
      'id': 'p1',
      'tainted': false,
      'headsUp': ['This notifies 1 student.'],
      'actions': [
        {
          'callId': 'c1', 'tool': 'meeting_request', 'args': {'studentUid': 's1'}, 'title': 'Request a meeting with a student',
          'lines': [{'label': 'Student', 'value': 'Arjun Kumar', 'items': <String>[]}], 'notifies': <String>[], 'double': false,
        },
      ],
    };

final DateTime _now = DateTime(2026, 10, 23, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  late FakeFirebaseFirestore db;
  late List<Map<String, dynamic>> replies;
  late List<Map<String, dynamic>> requests;

  Future<AgentController> wire(WidgetTester tester, {Who who = Who.hod}) async {
    db = await prepareApp(tester, who: who);
    replies = [];
    requests = [];
    HierarchyApi.useForTests((name, args) async {
      if (name == 'guideAgentTurn') {
        requests.add(args);
        return replies.removeAt(0);
      }
      return <String, dynamic>{};
    });
    final c = AgentController(env: AgentEnv(profile: adminProfile(who), db: db, clock: () => _now));
    AgentSession.useForTests(c);
    addTearDown(() => AgentSession.useForTests(null));
    return c;
  }

  Future<void> open(WidgetTester tester, AgentController c, {double scale = 1.0, bool dark = false}) async {
    await pumpScreen(tester, AgentPage(controller: c), scale: scale, dark: dark);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('agent-input')), text);
    await tester.tap(find.byKey(const ValueKey('agent-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  /// A saved chat, as the server writes it.
  Future<void> saveChat(
    String id, {
    String adminId = 'H',
    String title = 'Meet Arjun on Monday',
    int questions = 3,
    int tasks = 0,
    int successful = 0,
    int failed = 0,
    int? updatedMs,
    int limit = 20,
    List<Map<String, dynamic>> entries = const [],
  }) async {
    await db.collection('agentChats').doc(id).set({
      'adminId': adminId, 'title': title, 'questions': questions, 'questionLimit': limit,
      'tasks': tasks, 'successful': successful, 'failed': failed,
      'createdMs': updatedMs ?? _now.millisecondsSinceEpoch, 'updatedMs': updatedMs ?? _now.millisecondsSinceEpoch,
    });
    for (var i = 0; i < entries.length; i++) {
      await db.collection('agentChats').doc(id).collection('entries').doc(i.toString().padLeft(6, '0')).set({'seq': i, 'atMs': _now.millisecondsSinceEpoch, ...entries[i]});
    }
  }

  Future<void> openHistory(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('agent-chats')));
    await tester.pump();
    await letDataArrive(tester);
  }

  /// Level 1: opens a session's card.
  Future<void> expandChat(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('agent-chat-title-$id')));
    await tester.pump();
    await letDataArrive(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// "Open chat" inside an opened session.
  Future<void> openChatFromHistory(WidgetTester tester, String id) async {
    await expandChat(tester, id);
    await tester.ensureVisible(find.byKey(ValueKey('agent-chat-open-$id')));
    await tester.tap(find.byKey(ValueKey('agent-chat-open-$id')));
    await tester.pump();
    await letDataArrive(tester);
    await tester.pump(const Duration(milliseconds: 500));
  }

  bool inputEnabled(WidgetTester tester) => tester.widget<TextField>(find.byKey(const ValueKey('agent-input'))).enabled ?? true;
  bool sendEnabled(WidgetTester tester) =>
      tester.widget<InkWell>(find.descendant(of: find.byKey(const ValueKey('agent-send')), matching: find.byType(InkWell))).onTap != null;

  // ------------------------------------------------------------------------------------------ a new chat only by the button
  group('a New chat starts only when the guide presses the button', () {
    testWidgets('questions keep going into the same session; nothing resets by itself', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('message', {'text': 'First answer.', 'questionsLeft': 19}));
      await say(tester, 'first');
      replies.add(_reply('message', {'text': 'Second answer.', 'questionsLeft': 18}));
      await say(tester, 'second');
      expect(requests[0].containsKey('sessionId'), isFalse, reason: 'the first question opens the session');
      expect(requests[1]['sessionId'], 'sess12345', reason: 'the second continues it');
      expect(c.entries.whereType<ProgressEntry>().length, 2, reason: 'each request has its progress card');
      expect(c.entries.where((e) => e is! ProgressEntry).length, 4);
      expect(find.text('Second answer.'), findsOneWidget);
      expect(find.text('First answer.'), findsOneWidget);
    });

    testWidgets('when the server says the conversation has gone, the chat stays on screen and the guide is told to start a New chat', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('message', {'text': 'Hello.', 'questionsLeft': 19}));
      await say(tester, 'hello');
      replies.add({'sessionId': null, 'status': 'message', 'text': 'That conversation has ended. Please start again.', 'ended': true});
      await say(tester, 'again');
      expect(find.text('Hello.'), findsOneWidget, reason: 'nothing was cleared');
      expect(find.byKey(const ValueKey('agent-session-gone')), findsOneWidget);
      expect(inputEnabled(tester), isFalse);
      expect(sendEnabled(tester), isFalse);
      expect(c.entries.isNotEmpty, isTrue);
      final before = requests.length;
      await tester.tap(find.byKey(const ValueKey('agent-send')), warnIfMissed: false);
      await tester.pump();
      expect(requests.length, before, reason: 'nothing is sent, and no new session is started');
      // only the button starts one
      await tester.tap(find.byKey(const ValueKey('agent-new-chat')));
      await tester.pump();
      expect(c.entries, isEmpty);
      expect(inputEnabled(tester), isTrue);
      replies.add(_reply('message', {'text': 'New start.', 'sessionId': 'sess99999', 'questionsLeft': 19}));
      await say(tester, 'fresh');
      expect(requests.last.containsKey('sessionId'), isFalse, reason: 'a new session, with no old id');
    });

    testWidgets('New chat starts at 20 questions left', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('message', {'text': 'ok', 'questionsLeft': 3}));
      await say(tester, 'q');
      expect(find.text('3 questions left in this session'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agent-new-chat')));
      await tester.pump();
      expect(find.text('20 questions left in this session'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------ the question count and its limit
  group('20 questions per session', () {
    testWidgets('"N questions left in this session" goes down with each answer, and says "1 question" at one', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      expect(find.byKey(const ValueKey('agent-questions-left')), findsOneWidget);
      expect(find.text('20 questions left in this session'), findsOneWidget);
      replies.add(_reply('message', {'text': 'a', 'questionsLeft': 19}));
      await say(tester, 'one');
      expect(find.text('19 questions left in this session'), findsOneWidget);
      replies.add(_reply('message', {'text': 'b', 'questionsLeft': 1}));
      await say(tester, 'two');
      expect(find.text('1 question left in this session'), findsOneWidget);
    });

    testWidgets('at 0 the box is closed with "This session is full — start a New chat", and nothing can be sent', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('message', {'text': 'Last one.', 'questionsLeft': 0}));
      await say(tester, 'the 20th');
      expect(find.byKey(const ValueKey('agent-session-full')), findsOneWidget);
      expect(find.text('This session is full — start a New chat'), findsWidgets, reason: 'in the notice and the box');
      expect(inputEnabled(tester), isFalse);
      expect(sendEnabled(tester), isFalse);
      expect(find.byKey(const ValueKey('agent-questions-left')), findsNothing);
      final before = requests.length;
      await c.send('sneak one in');
      expect(requests.length, before, reason: 'the controller refuses it too');
      // a New chat opens it again
      await tester.tap(find.byKey(const ValueKey('agent-new-chat')));
      await tester.pump();
      expect(inputEnabled(tester), isTrue);
    });

    testWidgets('a card already shown can still be confirmed in a full session, and answering it is not a question', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('confirm', {'text': 'I can do that.', 'proposal': _proposal(), 'questionsLeft': 0}));
      await say(tester, 'meet Arjun');
      expect(find.byKey(const ValueKey('agent-session-full')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-confirm')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('agent-confirm'))).onPressed, isNotNull);
      replies.add(_reply('message', {'text': 'Done.', 'questionsLeft': 0}));
      await tester.tap(find.byKey(const ValueKey('agent-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(requests.last['outcome'], 'executed');
      expect(find.byKey(const ValueKey('agent-session-full')), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------ the daily cap
  group('the daily cap', () {
    Map<String, dynamic> limit() => _reply('limit', {'why': 'day', 'text': 'Daily limit reached — try again tomorrow. Everything in the app still works by hand.', 'questionsLeft': 19});

    testWidgets('is shown when reached, closes the box, and a New chat does not lift it', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(limit());
      await say(tester, 'hello');
      expect(find.textContaining('Daily limit reached — try again tomorrow'), findsWidgets);
      expect(find.byKey(const ValueKey('agent-daily-limit')), findsOneWidget);
      expect(inputEnabled(tester), isFalse);
      expect(sendEnabled(tester), isFalse);
      await tester.tap(find.byKey(const ValueKey('agent-new-chat')));
      await tester.pump();
      expect(find.byKey(const ValueKey('agent-daily-limit')), findsOneWidget, reason: 'still today');
      expect(inputEnabled(tester), isFalse);
    });

    testWidgets('a card proposed earlier can still be confirmed or cancelled', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('confirm', {'text': 'I can do that.', 'proposal': _proposal()}));
      await say(tester, 'meet Arjun');
      replies.add(limit());
      await say(tester, 'and one more thing');
      expect(find.byKey(const ValueKey('agent-daily-limit')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('agent-confirm'))).onPressed, isNotNull, reason: 'Confirm still works');
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('agent-cancel'))).onPressed, isNotNull, reason: 'and so does Cancel');
      replies.add(_reply('message', {'text': 'Done.'}));
      await tester.tap(find.byKey(const ValueKey('agent-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(requests.last['outcome'], 'executed');
      expect(requests.last['proposalId'], 'p1');
      expect(find.textContaining('Done'), findsWidgets);
    });

    testWidgets('lifts by itself the next day', (tester) async {
      var clock = _now;
      db = await prepareApp(tester);
      replies = [];
      requests = [];
      HierarchyApi.useForTests((name, args) async {
        requests.add(args);
        return replies.removeAt(0);
      });
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => clock));
      AgentSession.useForTests(c);
      addTearDown(() => AgentSession.useForTests(null));
      await open(tester, c);
      replies.add(limit());
      await say(tester, 'hello');
      expect(c.dailyLimit, isTrue);
      clock = _now.add(const Duration(days: 1));
      expect(c.dailyLimit, isFalse);
    });

    testWidgets('the hour limit only says so; the box stays open', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('limit', {'why': 'hour', 'text': "You've asked me a lot this hour, so I'm pausing for a little.", 'questionsLeft': 19}));
      await say(tester, 'hello');
      expect(find.textContaining('this hour'), findsWidgets);
      expect(find.byKey(const ValueKey('agent-daily-limit')), findsNothing);
      expect(inputEnabled(tester), isTrue);
    });
  });

  // ------------------------------------------------------------------------------------------ the history
  group('the history', () {
    testWidgets('one card per session, newest first: date and time, the title, "N tasks · X successful · Y failed"', (tester) async {
      final c = await wire(tester);
      await saveChat('old', title: 'Plan the Sunday programme', tasks: 3, successful: 2, failed: 1, updatedMs: DateTime(2026, 10, 20, 9, 5).millisecondsSinceEpoch);
      await saveChat('mid', title: 'Meet Arjun on Monday', tasks: 1, successful: 1, failed: 0, updatedMs: DateTime(2026, 10, 22, 17, 40).millisecondsSinceEpoch);
      await saveChat('new', title: 'Who needs attention?', tasks: 0, updatedMs: DateTime(2026, 10, 23, 8, 15).millisecondsSinceEpoch);
      await open(tester, c);
      await openHistory(tester);
      expect(find.text('Chat history'), findsOneWidget);
      expect(find.text('Plan the Sunday programme'), findsOneWidget);
      expect(find.text('3 tasks · 2 successful · 1 failed'), findsOneWidget);
      expect(find.text('1 task · 1 successful · 0 failed'), findsOneWidget);
      expect(find.text('0 tasks · 0 successful · 0 failed'), findsOneWidget);
      expect(find.text('20 Oct 2026, 9:05 AM'), findsOneWidget);
      expect(find.text('22 Oct 2026, 5:40 PM'), findsOneWidget);
      expect(find.text('23 Oct 2026, 8:15 AM'), findsOneWidget);
      final y = [for (final id in ['new', 'mid', 'old']) tester.getTopLeft(find.byKey(ValueKey('agent-chat-$id'))).dy];
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: 'newest first');
      expectNoOverflow(tester);
    });

    testWidgets('an admin sees only their OWN chats', (tester) async {
      final c = await wire(tester);
      await saveChat('mine', title: 'My own chat');
      await saveChat('theirs', adminId: 'G', title: "Somebody else's chat");
      await saveChat('hers', adminId: 'F1', title: "Another admin's chat");
      await open(tester, c);
      await openHistory(tester);
      expect(find.text('My own chat'), findsOneWidget);
      expect(find.text("Somebody else's chat"), findsNothing);
      expect(find.text("Another admin's chat"), findsNothing);
    });

    testWidgets("another admin's chat cannot be opened, even by its id", (tester) async {
      final c = await wire(tester);
      await saveChat('theirs', adminId: 'G', title: "Somebody else's chat", entries: [
        {'kind': 'user', 'text': 'private words'},
      ]);
      await open(tester, c);
      await expectLater(c.openChat('theirs'), throwsA(isA<AgentFailure>()));
      await expectLater(c.openChat('does-not-exist'), throwsA(isA<AgentFailure>()));
      expect(c.entries, isEmpty);
      expect(find.text('private words'), findsNothing);
    });

    testWidgets('no chats yet says so', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      await openHistory(tester);
      expect(find.byKey(const ValueKey('agent-chats-empty')), findsOneWidget);
    });

    testWidgets('the button is there for every role, not only the HOD', (tester) async {
      final c = await wire(tester, who: Who.guide);
      await open(tester, c);
      expect(find.byKey(const ValueKey('agent-chats')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-log')), findsNothing, reason: "the HOD's log stays the HOD's");
    });

    testWidgets("a guide's own chats show for a guide, and a HOD's do not leak to them", (tester) async {
      final c = await wire(tester, who: Who.guide);
      await saveChat('g', adminId: 'G', title: "Gopal's chat");
      await saveChat('h', adminId: 'H', title: "Harinam's chat");
      await open(tester, c);
      await openHistory(tester);
      expect(find.text("Gopal's chat"), findsOneWidget);
      expect(find.text("Harinam's chat"), findsNothing);
    });
  });

  // ------------------------------------------------------------------------------------------ opening and continuing
  group('opening an old chat', () {
    Future<void> seedFull() => saveChat(
          'chat1',
          title: 'Meet Arjun on Monday',
          questions: 4,
          tasks: 2,
          successful: 1,
          failed: 1,
          entries: [
            {'kind': 'user', 'text': 'Set up a meeting with Arjun'},
            {'kind': 'assistant', 'text': 'I can do that:\n- **Meet** Arjun', 'links': [{'route': 'trips'}]},
            {
              'kind': 'proposal', 'proposalId': 'p1', 'state': 'done', 'advice': ['This notifies 1 student.', 'Arjun has a clash.'],
              'proposal': _proposal(), 'results': {'c1': {'ok': true, 'text': 'Meeting requested.'}},
            },
            {'kind': 'user', 'text': 'and another'},
            {
              'kind': 'proposal', 'proposalId': 'p2', 'state': 'done', 'advice': <String>[],
              'proposal': {..._proposal(), 'id': 'p2'}, 'results': {'c1': {'ok': false, 'text': 'Arjun is not in your team.'}},
            },
            {
              'kind': 'proposal', 'proposalId': 'p3', 'state': 'cancelled', 'advice': <String>[],
              'proposal': {..._proposal(), 'id': 'p3'}, 'results': <String, dynamic>{},
            },
          ],
        );

    testWidgets("Open chat shows that chat as it looked: the messages, the cards, what came of each", (tester) async {
      final c = await wire(tester);
      await seedFull();
      await open(tester, c);
      tester.view.physicalSize = const Size(360, 2600); // tall, so every line is built and can be read
      await openHistory(tester);
      await openChatFromHistory(tester, 'chat1');
      expect(find.byType(AgentPage), findsOneWidget);
      expect(find.byType(AgentChatsPage), findsNothing, reason: 'back on the chat');
      expect(c.entries.length, 6);
      expect(find.text('Set up a meeting with Arjun'), findsOneWidget);
      expect(find.text('and another'), findsOneWidget);
      expect(c.entries[1], isA<AssistantEntry>());
      final p1 = c.entries[2] as ProposalEntry;
      expect(p1.state, ProposalState.done);
      expect(p1.results['c1'], (true, 'Meeting requested.'));
      expect((c.entries[4] as ProposalEntry).results['c1'], (false, 'Arjun is not in your team.'));
      expect((c.entries[5] as ProposalEntry).state, ProposalState.cancelled);
      expect(c.sessionId, 'chat1');
      expect(find.text('16 questions left in this session'), findsOneWidget, reason: '20 - 4');
      expectNoOverflow(tester);
    });

    testWidgets('the guide can CONTINUE it: the next question goes into the same session', (tester) async {
      final c = await wire(tester);
      await seedFull();
      await open(tester, c);
      tester.view.physicalSize = const Size(360, 2600); // tall, so every line is built and can be read
      await openHistory(tester);
      await openChatFromHistory(tester, 'chat1');
      replies.add(_reply('message', {'sessionId': 'chat1', 'text': 'Sure, I remember.', 'questionsLeft': 15}));
      await say(tester, 'what did we do?');
      expect(requests.single['sessionId'], 'chat1', reason: 'the saved session is its context');
      expect(find.text('Sure, I remember.'), findsOneWidget);
      expect(find.text('Set up a meeting with Arjun'), findsOneWidget, reason: 'the old lines stay above');
      expect(find.text('15 questions left in this session'), findsOneWidget);
    });

    testWidgets('a chat whose 20 questions are used up opens read-only: "This session is full"', (tester) async {
      final c = await wire(tester);
      await saveChat('fullchat', title: 'A long one', questions: 20, entries: [
        {'kind': 'user', 'text': 'the 20th question'},
        {'kind': 'assistant', 'text': 'the last answer'},
      ]);
      await open(tester, c);
      await openHistory(tester);
      await expandChat(tester, 'fullchat');
      expect(find.text('Full — start a New chat to ask more'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agent-chat-open-fullchat')));
      await tester.pump();
      await letDataArrive(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('the last answer'), findsOneWidget, reason: 'still readable');
      expect(find.byKey(const ValueKey('agent-session-full')), findsOneWidget);
      expect(inputEnabled(tester), isFalse);
      expect(sendEnabled(tester), isFalse);
    });

    testWidgets('a card still waiting can be confirmed from the old chat; confirming sends what the guide saw', (tester) async {
      final c = await wire(tester);
      await saveChat('waiting', title: 'Pending one', entries: [
        {'kind': 'user', 'text': 'meet Arjun'},
        {'kind': 'proposal', 'proposalId': 'p1', 'state': 'waiting', 'advice': ['This notifies 1 student.'], 'proposal': _proposal(), 'results': <String, dynamic>{}, 'atMs': _now.millisecondsSinceEpoch - 3600000},
      ]);
      await open(tester, c);
      await openHistory(tester);
      await openChatFromHistory(tester, 'waiting');
      expect(find.byKey(const ValueKey('agent-confirm')), findsOneWidget);
      replies.add(_reply('message', {'sessionId': 'waiting', 'text': 'Done.'}));
      await tester.tap(find.byKey(const ValueKey('agent-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final sent = requests.single;
      expect(sent['sessionId'], 'waiting');
      expect(sent['proposalId'], 'p1');
      expect(sent['advice'], ['This notifies 1 student.']);
      expect((sent['shown'] as List).single['callId'], 'c1');
      expect((sent['shown'] as List).single['ok'], isA<bool>());
      expect((sent['shown'] as List).single['text'], isNotEmpty);
    });

    testWidgets('a card left waiting for hours is shown as not confirmed, with no buttons', (tester) async {
      final c = await wire(tester);
      await saveChat('stale', title: 'Stale one', entries: [
        {'kind': 'user', 'text': 'meet Arjun'},
        {'kind': 'proposal', 'proposalId': 'p1', 'state': 'waiting', 'advice': <String>[], 'proposal': _proposal(), 'results': <String, dynamic>{}, 'atMs': _now.millisecondsSinceEpoch - 7 * 3600000},
        {'kind': 'proposal', 'proposalId': 'p2', 'state': 'expired', 'advice': <String>[], 'proposal': {..._proposal(), 'id': 'p2'}, 'results': <String, dynamic>{}},
      ]);
      await open(tester, c);
      await openHistory(tester);
      await openChatFromHistory(tester, 'stale');
      expect(find.text('Not confirmed — nothing was changed'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('agent-confirm')), findsNothing);
    });

    testWidgets('opening another chat replaces what is on screen, and New chat still clears it', (tester) async {
      final c = await wire(tester);
      await saveChat('a', title: 'Chat A', entries: [{'kind': 'user', 'text': 'words of A'}]);
      await saveChat('b', title: 'Chat B', entries: [{'kind': 'user', 'text': 'words of B'}]);
      await open(tester, c);
      await c.openChat('a');
      await tester.pump();
      expect(find.text('words of A'), findsOneWidget);
      await c.openChat('b');
      await tester.pump();
      expect(find.text('words of B'), findsOneWidget);
      expect(find.text('words of A'), findsNothing);
      expect(c.sessionId, 'b');
      await tester.tap(find.byKey(const ValueKey('agent-new-chat')));
      await tester.pump();
      expect(c.entries, isEmpty);
      expect(c.sessionId, isNull);
    });
  });

  // ------------------------------------------------------------------------------------------ the two drop-down levels
  group('the history drop-downs', () {
    Map<String, dynamic> card(String proposalId, String state, Map<String, dynamic> results, {String title = 'Request a meeting with a student', List<Map<String, dynamic>>? lines, List<String> notifies = const <String>[]}) => {
          'kind': 'proposal', 'proposalId': proposalId, 'state': state, 'advice': <String>[], 'results': results, 'atMs': _now.millisecondsSinceEpoch - 600000,
          'proposal': {
            'id': proposalId, 'tainted': false, 'headsUp': <String>[],
            'actions': [
              {
                'callId': 'c1', 'tool': 'meeting_request', 'args': <String, dynamic>{}, 'title': title,
                'lines': lines ?? [{'label': 'Student', 'value': 'Ravi Kumar', 'items': <String>[]}, {'label': 'When', 'value': 'Fri 5 PM', 'items': <String>[]}],
                'notifies': notifies, 'double': false,
              },
            ],
          },
        };

    Future<void> seedTasks() => saveChat('s1', title: 'Associations for Ravi', questions: 6, tasks: 2, successful: 1, failed: 1, entries: [
          {'kind': 'user', 'text': 'set up a meeting with Ravi'},
          card('p1', 'done', {'c1': {'ok': true, 'text': 'Meeting requested for Fri 5 PM.'}}, notifies: ["the student: 'Meeting Scheduled'"]),
          {'kind': 'user', 'text': 'and one with Mohan'},
          card('p2', 'done', {'c1': {'ok': false, 'text': 'Mohan is not in your team.'}}, lines: [{'label': 'Student', 'value': 'Mohan Das', 'items': <String>[]}]),
          {'kind': 'user', 'text': 'and one more'},
          card('p3', 'cancelled', <String, dynamic>{}),
          {'kind': 'user', 'text': 'and another'},
          card('p4', 'waiting', <String, dynamic>{}),
        ]);

    testWidgets('level 1 is collapsed: only date, title and counts; no tasks and no Open chat until a card is opened', (tester) async {
      final c = await wire(tester);
      await seedTasks();
      await open(tester, c);
      await openHistory(tester);
      expect(find.byKey(const ValueKey('agent-chat-title-s1')), findsOneWidget);
      expect(find.text('2 tasks · 1 successful · 1 failed'), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-chat-open-s1')), findsNothing, reason: 'nothing in full until opened');
      expect(find.textContaining('Request a meeting with a student'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('opening a session lists its TASKS (not the cancelled or unanswered cards), each collapsed, with a tick or a cross', (tester) async {
      final c = await wire(tester);
      await seedTasks();
      await open(tester, c);
      await openHistory(tester);
      await expandChat(tester, 's1');
      expect(find.byKey(const ValueKey('agent-chat-open-s1')), findsOneWidget);
      expect(find.text('Request a meeting with a student — Ravi Kumar, Fri 5 PM'), findsOneWidget);
      expect(find.text('Request a meeting with a student — Mohan Das'), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-task-status-ok')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-task-status-failed')), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-task-s1-1-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-task-s1-3-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-task-s1-5-c1')), findsNothing, reason: 'cancelled is not a task');
      expect(find.byKey(const ValueKey('agent-task-s1-7-c1')), findsNothing, reason: 'unanswered is not a task');
      // level 2 is collapsed: no details yet
      expect(find.text('What was changed'), findsNothing);
      expect(find.text('Meeting requested for Fri 5 PM.'), findsNothing);
      expect(find.text("Mohan is not in your team."), findsNothing);
    });

    testWidgets('opening a task shows the whole action: what was changed, who was told, the result — or the error; opening it again closes it', (tester) async {
      final c = await wire(tester);
      await seedTasks();
      await open(tester, c);
      await openHistory(tester);
      await expandChat(tester, 's1');

      await tester.tap(find.text('Request a meeting with a student — Ravi Kumar, Fri 5 PM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('What was changed'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('When'), findsOneWidget);
      expect(find.text('Who was told'), findsOneWidget);
      expect(find.text("the student: 'Meeting Scheduled'"), findsOneWidget);
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('Meeting requested for Fri 5 PM.'), findsOneWidget);

      await tester.tap(find.text('Request a meeting with a student — Mohan Das'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Mohan is not in your team.'), findsOneWidget);

      // closing: the details go
      await tester.tap(find.text('Request a meeting with a student — Ravi Kumar, Fri 5 PM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Meeting requested for Fri 5 PM.'), findsNothing);
      expect(find.text('Who was told'), findsNothing);
      expect(find.text('Mohan is not in your team.'), findsOneWidget, reason: 'the other task stays open');
    });

    testWidgets('a session opens and closes with an animation (no jump), and its card goes back to collapsed', (tester) async {
      final c = await wire(tester);
      await seedTasks();
      await open(tester, c);
      await openHistory(tester);
      expect(find.byType(GuideAnimatedSize), findsWidgets, reason: 'the card animates its height');
      await expandChat(tester, 's1');
      expect(find.byKey(const ValueKey('agent-chat-open-s1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agent-chat-title-s1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('agent-chat-open-s1')), findsNothing);
    });

    testWidgets('a session with no confirmed task says so, and still offers Open chat', (tester) async {
      final c = await wire(tester);
      await saveChat('talk', title: 'Just questions', entries: [
        {'kind': 'user', 'text': 'where do I add a trip?'},
        {'kind': 'assistant', 'text': 'Open Analysis.'},
      ]);
      await open(tester, c);
      await openHistory(tester);
      await expandChat(tester, 'talk');
      expect(find.byKey(const ValueKey('agent-chat-no-tasks-talk')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-chat-open-talk')), findsOneWidget);
    });

    testWidgets('only one session needs to be read when opened: the others stay collapsed', (tester) async {
      final c = await wire(tester);
      await seedTasks();
      await saveChat('other', title: 'Another', tasks: 1, successful: 1, entries: [card('p9', 'done', {'c1': {'ok': true, 'text': 'Done.'}})]);
      await open(tester, c);
      await openHistory(tester);
      await expandChat(tester, 's1');
      expect(find.byKey(const ValueKey('agent-chat-open-s1')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-chat-open-other')), findsNothing);
    });

    testWidgets('Open chat from the history continues in the same session', (tester) async {
      final c = await wire(tester);
      await seedTasks();
      await open(tester, c);
      await openHistory(tester);
      await openChatFromHistory(tester, 's1');
      expect(c.sessionId, 's1');
      expect(find.byType(AgentChatsPage), findsNothing);
      replies.add(_reply('message', {'sessionId': 's1', 'text': 'Yes.', 'questionsLeft': 13}));
      await say(tester, 'continue');
      expect(requests.single['sessionId'], 's1');
    });

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('long titles, details and errors wrap neatly in both levels at text ${scale}x, ${dark ? 'dark' : 'light'}', (tester) async {
          final c = await wire(tester);
          const long = 'Assign the book "Bhagavad-gita As It Is" to Ravi Kumar, Mohan Das and eleven other students of the Sunday group by Friday evening';
          await saveChat('long', title: 'A very long chat title about assigning several books to a large group of students this week', tasks: 1, failed: 1, successful: 0, entries: [
            card('p1', 'done', {'c1': {'ok': false, 'text': 'Not saved: the book is not in the list your team can assign, and two of the students are in another guide\'s team. $long'}},
                title: long, lines: [{'label': 'Students', 'value': long, 'items': <String>[]}], notifies: ['the students: "A new book was assigned to you, please collect it from the library on Friday"']),
          ]);
          await open(tester, c, scale: scale, dark: dark);
          await openHistory(tester);
          await expandChat(tester, 'long');
          expectNoOverflow(tester, reason: 'level 1 opened');
          await tester.tap(find.textContaining('Assign the book').first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.ensureVisible(find.text('Error'));
          expect(find.text('Error'), findsOneWidget);
          expectNoOverflow(tester, reason: 'level 2 opened');
        });
      }
    }

    test('task titles are short: the action and its first short details', () {
      final lines = [
        {
          'kind': 'proposal', 'state': 'done', 'seq': 3, 'results': {'c1': {'ok': true, 'text': 'x'}},
          'proposal': {
            'id': 'p', 'actions': [
              {'callId': 'c1', 'tool': 't', 'args': <String, dynamic>{}, 'title': 'Set an association', 'lines': [
                {'label': 'Student', 'value': 'Ravi', 'items': <String>[]},
                {'label': 'Note', 'value': 'A very long note that goes on and on and certainly is longer than thirty six characters', 'items': <String>[]},
                {'label': 'When', 'value': 'Fri 5 PM', 'items': <String>[]},
                {'label': 'Extra', 'value': 'ignored third', 'items': <String>[]},
              ], 'notifies': <String>[], 'double': false},
            ],
          },
        },
      ];
      final tasks = chatTasksOf(lines);
      expect(tasks.single.shortTitle, 'Set an association — Ravi, Fri 5 PM');
      expect(tasks.single.ok, isTrue);
      expect(tasks.single.key, '3-c1');
    });
  });

  // ------------------------------------------------------------------------------------------ looks
  for (final scale in kScales) {
    for (final dark in [false, true]) {
      final label = 'text ${scale}x, ${dark ? 'dark' : 'light'}';

      testWidgets('the history list and the closed boxes fit at $label', (tester) async {
        final c = await wire(tester);
        await saveChat('a', title: 'A rather long title about setting up several meetings with many students this week', tasks: 12, successful: 10, failed: 2);
        await saveChat('b', title: 'Short', questions: 20, updatedMs: _now.millisecondsSinceEpoch - 86400000);
        await open(tester, c, scale: scale, dark: dark);
        expectNoOverflow(tester, reason: 'questions left');
        await openHistory(tester);
        expect(find.text('12 tasks · 10 successful · 2 failed'), findsOneWidget);
        expectNoOverflow(tester, reason: 'history');
        await tester.pageBack();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        replies.add(_reply('message', {'text': 'Last one.', 'questionsLeft': 0}));
        await say(tester, 'q');
        expect(find.byKey(const ValueKey('agent-session-full')), findsOneWidget);
        expectNoOverflow(tester, reason: 'full');
        await tester.tap(find.byKey(const ValueKey('agent-new-chat')));
        await tester.pump();
        replies.add(_reply('limit', {'why': 'day', 'text': 'Daily limit reached — try again tomorrow.'}));
        await say(tester, 'q');
        expect(find.byKey(const ValueKey('agent-daily-limit')), findsOneWidget);
        expectNoOverflow(tester, reason: 'daily limit');
      });
    }
  }

  test('counts read naturally', () {
    expect(chatCountsText({'tasks': 1, 'successful': 1, 'failed': 0}), '1 task · 1 successful · 0 failed');
    expect(chatCountsText({'tasks': 0}), '0 tasks · 0 successful · 0 failed');
    expect(chatCountsText({'tasks': 5, 'successful': 4, 'failed': 1}), '5 tasks · 4 successful · 1 failed');
  });
}
