import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/agent/AgentWrites.dart';
import 'package:folk_guide_app/agent/AgentWrites2.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';

import 'support/app_harness.dart';

/// THE ASSISTANT JUST DOES IT: no confirmation card except for a deletion; every other change runs at once and shows "Done: …" with an UNDO (for a few
/// minutes); what the server ran by itself is shown the same way; the new tools (batch size, doubt answered with AI) behave.

AdminProfile _me() => AdminProfile.fromMap({
      'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [],
      'admins': [
        {'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': ''}
      ],
    });

Map<String, dynamic> _action(String callId, String tool, Map<String, dynamic> args, {String title = 'Remember about a student', bool dbl = false}) =>
    {'callId': callId, 'tool': tool, 'args': args, 'title': title, 'lines': <Map<String, dynamic>>[], 'notifies': <String>[], 'double': dbl};

Map<String, dynamic> _proposal(List<Map<String, dynamic>> actions, {bool auto = true, bool tainted = false}) => {
      'sessionId': 'sess12345', 'status': 'confirm',
      'proposal': {'id': 'p1', 'tainted': tainted, 'headsUp': <String>[], 'auto': auto, 'actions': actions},
    };

Map<String, dynamic> _message(String text, {Map<String, dynamic>? executed}) => {'sessionId': 'sess12345', 'status': 'message', 'text': text, 'links': <Object>[], if (executed != null) 'executed': executed};

void main() {
  late FakeFirebaseFirestore db;
  late List<Map<String, dynamic>> requests;
  late List<Map<String, dynamic>> replies;
  late List<(String, Map<String, dynamic>)> calls;

  setUp(() async {
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    await db.collection('users').doc('u1').set({'name': 'Arjun', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at FOLK', 'commitmentRounds': 12, 'readingCommitmentMinutes': 30});
    await db.collection('adminUsers').doc('G').set({'role': 'GUIDE', 'displayName': 'Gopal Das', 'planSettings': {'dailyBatch': 6}});
    await db.collection('bookDoubts').doc('d1').set({'uid': 'u1', 'studentName': 'Arjun', 'mode': 'guide', 'question': 'why?', 'status': 'pending', 'bookTitle': 'Gita', 'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'});
    requests = [];
    replies = [];
    calls = [];
    HierarchyApi.useForTests((name, args) async {
      if (name == 'guideAgentTurn') {
        requests.add(args);
        return replies.removeAt(0);
      }
      calls.add((name, args));
      return {'ok': true, 'message': 'Noted.', if (name == 'savePlanSettings') 'previous': 6};
    });
    AdminProfileProvider.instance.debugSet(_me());
  });
  tearDown(() {
    GuideDb.useForTests(null);
    HierarchyApi.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  AgentController controller() => AgentController(env: AgentEnv(profile: _me(), db: db, clock: () => DateTime(2026, 10, 30, 12)));
  ProposalEntry lastCard(AgentController c) => c.entries.whereType<ProposalEntry>().last;

  test('NO CONFIRMATION: an "auto" proposal runs the moment it arrives: the server is told it was done (one confirmation), a "Done" card with an Undo is shown, no card waits', () async {
    replies
      ..add(_proposal([_action('c1', 'student_note_add', {'studentUid': 'u1', 'text': 'keen on service'})]))
      ..add(_message('Noted: Arjun is keen on service.'));
    final c = controller();
    await c.send('Arjun is keen on service');
    final card = lastCard(c);
    expect(card.state, ProposalState.done, reason: 'it ran without anyone pressing Confirm');
    expect(card.results['c1']!.$1, isTrue);
    expect(requests[1]['outcome'], 'executed');
    expect(requests[1]['confirmations'], 1);
    expect(calls.where((x) => x.$1 == 'studentGuideNote').single.$2, {'studentUid': 'u1', 'kind': 'note', 'text': 'keen on service'});
    expect(card.canUndo, isTrue);
    expect((c.entries.last as AssistantEntry).text, contains('keen on service'));
  });

  test('A DELETION KEEPS ITS CARD (double confirmation), and so does anything not "auto" (e.g. prepared after reading a student\'s words)', () async {
    replies.add(_proposal([_action('c1', 'meeting_delete', {'ids': ['x']}, title: 'Delete meetings', dbl: true)]));
    final c = controller();
    await c.send('delete that meeting');
    expect(lastCard(c).state, ProposalState.waiting, reason: 'a deletion waits for the guide');
    expect(requests.length, 1);
    // auto false: waits too
    replies.add(_proposal([_action('c1', 'student_note_add', {'studentUid': 'u1', 'text': 'x'})], auto: false, tainted: true));
    await controller().send('note it');
    expect(calls.where((x) => x.$1 == 'studentGuideNote'), isEmpty, reason: 'nothing ran');
  });

  test('"auto" with a double action in it still waits (the phone never runs a deletion without both confirmations)', () async {
    replies.add(_proposal([_action('c1', 'student_note_add', {'studentUid': 'u1', 'text': 'x'}), _action('c2', 'meeting_delete', {'ids': ['x']}, dbl: true)]));
    final c = controller();
    await c.send('do both');
    expect(lastCard(c).state, ProposalState.waiting);
    expect(calls, isEmpty);
  });

  test('UNDO takes it back through the same server call, once; the chat says so; it cannot be undone twice', () async {
    replies
      ..add(_proposal([_action('c1', 'student_advice_set', {'studentUid': 'u1', 'setting': 'stop_chanting_push'})]))
      ..add(_message('Done.'));
    final c = controller();
    await c.send('stop suggesting more chanting for Arjun');
    final card = lastCard(c);
    expect(card.canUndo, isTrue);
    await c.undo(card);
    expect(calls.where((x) => x.$1 == 'studentGuideNote').map((x) => x.$2['kind']), ['stop_chanting_push', 'resume_chanting_push']);
    expect(card.undone, isTrue);
    expect(card.canUndo, isFalse);
    expect((c.entries.last as AssistantEntry).text, startsWith('Undone'));
    final n = calls.length;
    await c.undo(card);
    expect(calls.length, n, reason: 'nothing happens the second time');
  });

  test('UNDO IS FOR A FEW MINUTES: after that the button is gone and nothing runs', () async {
    replies
      ..add(_proposal([_action('c1', 'student_note_add', {'studentUid': 'u1', 'text': 'x'})]))
      ..add(_message('Done.'));
    final c = controller();
    await c.send('note');
    final card = lastCard(c);
    card.undoUntil = DateTime.now().subtract(const Duration(seconds: 1));
    expect(card.canUndo, isFalse);
    final n = calls.length;
    await c.undo(card);
    expect(calls.length, n);
  });

  test('UNDO OF A COMMITMENT CHANGE puts back what he had (rounds and reading), not what the assistant guessed', () async {
    replies
      ..add(_proposal([_action('c1', 'student_commitments_set', {'studentUid': 'u1', 'rounds': 16})], ))
      ..add(_message('Done.'));
    final c = controller();
    await c.send('Arjun will chant 16 rounds');
    var u = (await db.collection('users').doc('u1').get()).data()!;
    expect([u['commitmentRounds'], u['readingCommitmentMinutes']], [16, 30]);
    await c.undo(lastCard(c));
    u = (await db.collection('users').doc('u1').get()).data()!;
    expect([u['commitmentRounds'], u['readingCommitmentMinutes']], [12, 30]);
  });

  test('WHAT THE SERVER RAN BY ITSELF (it finishes even if the app is closed) is shown as a done card with its Undo, before the assistant\'s words', () async {
    replies.add(_message('Noted for Arjun.', executed: {
      'proposal': {'id': 'p9', 'tainted': false, 'headsUp': <String>[], 'auto': true, 'actions': [_action('c1', 'student_note_add', {'studentUid': 'u1', 'text': 'keen'}, title: 'Remember about a student')]},
      'results': [
        {'callId': 'c1', 'ok': true, 'text': 'Noted. It will shape his plan.'}
      ],
      'undo': [
        {'name': 'studentGuideNote', 'data': {'studentUid': 'u1', 'kind': 'note_undo'}}
      ],
    }));
    final c = controller();
    await c.send('Arjun is keen');
    final cards = c.entries.whereType<ProposalEntry>().toList();
    expect(cards.single.state, ProposalState.done);
    expect(cards.single.results['c1'], (true, 'Noted. It will shape his plan.'));
    expect(c.entries.indexOf(cards.single), lessThan(c.entries.indexOf(c.entries.last)), reason: 'the card comes first, the words after');
    expect(requests.length, 1, reason: 'the phone did not have to report back: the server already did the work');
    expect(calls, isEmpty, reason: 'and the phone did nothing itself');
    await c.undo(cards.single);
    expect(calls.single.$1, 'studentGuideNote');
    expect(calls.single.$2, {'studentUid': 'u1', 'kind': 'note_undo'});
  });

  test('BATCH SIZE only through the assistant: it saves the number (1 to 12) and Undo puts back the old one; 0 and 13 are refused', () async {
    final env = AgentEnv(profile: _me(), db: db, clock: () => DateTime(2026, 10, 30, 12));
    final r = await kAgentWritesB['plan_batch_size_set']!({'size': 8}, env);
    expect(r.ok, isTrue);
    expect(calls.single.$1, 'savePlanSettings');
    expect(calls.single.$2, {'dailyBatch': 8});
    await r.undo!();
    expect(calls.last.$2, {'dailyBatch': 6}, reason: 'the number he had (the server says)');
    await expectLater(kAgentWritesB['plan_batch_size_set']!({'size': 13}, env), throwsA(anything));
    await expectLater(kAgentWritesB['plan_batch_size_set']!({'size': 0}, env), throwsA(anything));
  });

  test('A DOUBT ANSWERED WITH AI says so to the student; one answered from the guide\'s own words does not', () async {
    final env = AgentEnv(profile: _me(), db: db, clock: () => DateTime(2026, 10, 30, 12));
    final ai = await kAgentWritesA['doubt_answer']!({'doubtId': 'd1', 'text': 'Chanting purifies the heart.', 'byAi': true}, env);
    expect(ai.ok, isTrue);
    var d = (await db.collection('bookDoubts').doc('d1').get()).data()!;
    expect('${d['answer']}', contains('Chanting purifies the heart.'));
    expect('${d['answer']}', contains('Prepared with AI'));
    expect('${d['answer']}', contains('Gopal Das'), reason: 'sent as the guide\'s answer');
    await db.collection('bookDoubts').doc('d1').set({'uid': 'u1', 'studentName': 'Arjun', 'mode': 'guide', 'question': 'why?', 'status': 'pending', 'bookTitle': 'Gita', 'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'});
    final own = await kAgentWritesA['doubt_answer']!({'doubtId': 'd1', 'text': 'Because it is the yuga dharma.'}, env);
    expect(own.ok, isTrue);
    d = (await db.collection('bookDoubts').doc('d1').get()).data()!;
    expect('${d['answer']}', 'Because it is the yuga dharma.');
  });

  testWidgets('THE CARD SAYS "Done: …" with an Undo button while it can be undone; "Undone" after; and a deletion\'s card still has its buttons', (tester) async {
    final planDb = await prepareApp(tester);
    HierarchyApi.useForTests((name, args) async {
      if (name == 'guideAgentTurn') return replies.removeAt(0);
      calls.add((name, args));
      return {'ok': true, 'message': 'Noted.'};
    });
    await planDb.collection('users').doc('u1').set({'name': 'Arjun', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at FOLK'});
    replies
      ..add(_proposal([_action('c1', 'student_note_add', {'studentUid': 'u1', 'text': 'keen'})]))
      ..add(_message('Done.'));
    final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: planDb, clock: () => DateTime(2026, 10, 30, 12)));
    AgentSession.useForTests(c);
    addTearDown(() => AgentSession.useForTests(null));
    await pumpScreen(tester, AgentPage(controller: c));
    await tester.enterText(find.byKey(const ValueKey('agent-input')), 'Arjun is keen');
    await tester.tap(find.byKey(const ValueKey('agent-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('agent-confirm')), findsNothing, reason: 'no confirmation');
    expect(find.textContaining('Done: Remember about a student'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-undo')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-undo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('agent-undo')), findsNothing);
    expect(find.textContaining('Undone'), findsWidgets);
    await tester.pump(const Duration(minutes: 6)); // the undo window ends, the snackbar goes
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
