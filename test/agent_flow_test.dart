import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentReads.dart';
import 'package:folk_guide_app/agent/AgentTypes.dart';
import 'package:folk_guide_app/agent/AgentWrites.dart';
import 'package:folk_guide_app/agent/AgentWrites2.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';

/// The phone's half of the agent, end to end, against a scripted server.
///
/// The server (functions/guideAgent.js, tested there) decides what comes next; these tests pin what
/// the phone does with it: answers reads in scope, shows a proposal before anything happens, runs
/// only what is confirmed through the shared functions, refuses a deletion without both
/// confirmations, tells the server exactly what happened — and, for EVERY change that names a
/// student or a record, refuses an out-of-scope one without writing a thing.

const kNotYours = "I can't find that student among your students.";

AdminProfile _profile(String id) {
  final role = {'H': 'HOD', 'G': 'GUIDE', 'G2': 'GUIDE', 'M1': 'MALE_ENABLER', 'F1': 'FEMALE_ENABLER'}[id]!;
  return AdminProfile.fromMap({
    'id': id, 'displayName': 'Admin $id', 'role': role, 'teamGuide': id == 'M1' ? 'G' : '', 'email': '$id@x.org',
    'notificationPrefs': {}, 'notificationTypes': [],
    'admins': [
      {'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': ''},
      {'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': ''},
      {'id': 'G2', 'displayName': 'Govinda Das', 'role': 'GUIDE', 'teamGuide': ''},
      {'id': 'M1', 'displayName': 'Madhava Das', 'role': 'MALE_ENABLER', 'teamGuide': 'G'},
      {'id': 'F1', 'displayName': 'Radha Devi', 'role': 'FEMALE_ENABLER', 'teamGuide': ''},
    ],
  });
}

class _S {
  const _S(this.uid, this.name, this.gender, this.guide, this.team);
  final String uid, name, gender, guide, team;
}

const _students = [
  _S('u_arjun', 'Arjun Kumar', 'male', 'G', 'G'),
  _S('u_bhima', 'Bhima Sen', 'male', 'M1', 'G'),
  _S('u_ravi', 'Ravi Other', 'male', 'G2', 'G2'), // another team: outside G's scope
  _S('u_gauri', 'Gauri Devi', 'female', 'F1', ''), // a girl: outside G's scope
];

Future<void> _seed(FakeFirebaseFirestore db) async {
  final when = Timestamp.fromDate(DateTime(2026, 11, 2, 18));
  for (final s in _students) {
    final stamp = {'scopeGuide': s.guide, 'scopeTeam': s.team, 'scopeGender': s.gender};
    await db.collection('users').doc(s.uid).set({
      'name': s.name, 'gender': s.gender, 'guideId': s.guide, 'teamGuide': s.team, 'role': 'Stay at FOLK',
      'commitmentRounds': 16, 'readingCommitmentMinutes': 30,
    });
    await db.collection('associations').doc('a_${s.uid}').set({
      'studentUid': s.uid, 'studentName': s.name, 'status': 'pending', 'requestedBy': 'student', 'preferredDate': when,
      'counterProposalDate': when, ...stamp,
    });
    await db.collection('interactionLogs').doc('i_${s.uid}').set({
      'studentUid': s.uid, 'studentName': s.name, 'status': 'approved', 'interactionDate': when, 'rawDictation': 'Spoke with ${s.name}',
      'approvedSummary': {'interactionType': 'Call', 'themes': ['x'], 'studentConcerns': 'none'}, ...stamp,
    });
    await db.collection('flaggedChatMessages').doc('f_${s.uid}').set({
      'studentUid': s.uid, 'studentName': s.name, 'text': 'hello', 'reviewed': false, 'createdAt': when, ...stamp,
    });
    await db.collection('bookDoubts').doc('d_${s.uid}').set({
      'uid': s.uid, 'studentName': s.name, 'mode': 'guide', 'question': 'why?', 'status': 'open', 'askedAt': when, ...stamp,
    });
    await db.collection('expeditionRegistrations').doc('t1_${s.uid}').set({
      'tripId': 't1', 'studentUid': s.uid, 'studentName': s.name, 'attendance': 'pending', ...stamp,
    });
    await db.collection('serviceAssignments').doc('sv_${s.uid}').set({
      'studentUid': s.uid, 'serviceNumber': 1, 'assignedByGuideId': 'G', 'status': 'assigned', ...stamp,
    });
  }
  await db.collection('expeditions').doc('t1').set({'title': 'Trip', 'tripDate': when, 'endDate': when, 'status': 'upcoming', 'createdBy': 'G', 'targetGender': 'male', 'archived': false});
  await db.collection('books').doc('level-1').set({'book_1': 'Bhagavad-gita As It Is', 'book_2': 'Nectar of Devotion'});
  await db.collection('chantingChallenges').doc('c1').set({'name': 'Old', 'guideId': 'G', 'status': 'active'});
  await db.collection('boards').doc('b1').set({'kind': 'custom', 'ownerGuideId': 'G', 'title': 'My board', 'sharedWith': <String>[]});
  await db.collection('boards').doc('b1').collection('columns').doc('c1').set({'title': 'To meet', 'order': 0, 'colorValue': 1, 'kind': 'normal'});
  await db.collection('musicCurriculum').doc('m1').set({'name': 'Mridanga', 'order': 0, 'checkpoints': [{'id': 'cp1', 'title': 'Tala'}]});
}

class _Server {
  _Server(this.replies);
  final List<Map<String, dynamic>> replies;
  final List<Map<String, dynamic>> requests = [];
  final List<Map<String, dynamic>> pushes = [];
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async {
    if (name == 'guideAgentTurn') {
      requests.add(args);
      if (replies.isEmpty) throw StateError('the test scripted no more replies');
      return replies.removeAt(0);
    }
    if (name == 'sendStudentNotification') {
      pushes.add(args);
      return {'sent': 1, 'total': 1};
    }
    if (name == 'checkMobileTaken') return {'taken': false};
    return <String, dynamic>{};
  }
}

Map<String, dynamic> _message(String text, {List<Map<String, dynamic>> links = const []}) =>
    {'sessionId': 'sess12345', 'status': 'message', 'text': text, 'links': links};

Map<String, dynamic> _reads(List<Map<String, dynamic>> reads) => {'sessionId': 'sess12345', 'status': 'need_reads', 'reads': reads};

Map<String, dynamic> _confirm(String id, List<Map<String, dynamic>> actions, {List<String> headsUp = const []}) => {
      'sessionId': 'sess12345', 'status': 'confirm',
      'proposal': {'id': id, 'tainted': false, 'headsUp': headsUp, 'actions': actions},
    };

Map<String, dynamic> _action(String callId, String tool, Map<String, dynamic> args, {String title = 'Do it', bool dbl = false}) =>
    {'callId': callId, 'tool': tool, 'args': args, 'title': title, 'lines': <Map<String, dynamic>>[], 'notifies': <String>[], 'double': dbl};

void main() {
  late FakeFirebaseFirestore db;
  late _Server server;

  setUp(() async {
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    await _seed(db);
    server = _Server([]);
    HierarchyApi.useForTests(server.call);
  });
  tearDown(() {
    GuideDb.useForTests(null);
    HierarchyApi.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  AgentEnv envFor(String id) {
    final p = _profile(id);
    AdminProfileProvider.instance.debugSet(p);
    return AgentEnv(profile: p, db: db, clock: () => DateTime(2026, 10, 23, 12));
  }

  AgentController controller([String id = 'G']) => AgentController(env: envFor(id));

  // -------------------------------------------------------------------------
  group('the conversation', () {
    test('a plain answer is shown, with its buttons', () async {
      server.replies.add(_message('Open Analysis → ABCDE → Expeditions.', links: [{'route': 'trips'}]));
      final c = controller();
      await c.send('where do I add a trip?');
      expect(server.requests.single, {'text': 'where do I add a trip?'});
      final a = c.entries.last as AssistantEntry;
      expect(a.text, contains('Expeditions'));
      expect(a.links.single.route, 'trips');
      expect(c.busy, isFalse);
    });

    test('reads are answered on the phone, in scope, and the session carries on', () async {
      server
        ..replies.add(_reads([{'callId': 'c1', 'tool': 'find_students', 'args': {'query': 'a'}}]))
        ..replies.add(_message('I found Arjun.'));
      final c = controller();
      await c.send('find a');
      expect(server.requests[1]['sessionId'], 'sess12345');
      final result = (server.requests[1]['toolResults'] as List).single as Map;
      expect(result['callId'], 'c1');
      expect(result['ok'], isTrue);
      final names = [for (final s in (result['data'] as Map)['students'] as List) (s as Map)['name']];
      expect(names, ['Arjun Kumar', 'Bhima Sen'], reason: 'G sees his own and his team (Bhima is his Male Enabler); not Ravi (G2) or Gauri (a girl)');
      expect({for (final e in result['entities'] as List) (e as Map)['id']}, {'u_arjun', 'u_bhima'});
    });

    test('a read that fails goes back as an error with the reason, and the conversation survives', () async {
      server
        ..replies.add(_reads([{'callId': 'c1', 'tool': 'get_student', 'args': {'studentUid': 'u_ravi'}}]))
        ..replies.add(_message("I couldn't find that student."));
      final c = controller();
      await c.send('about Ravi');
      final result = (server.requests[1]['toolResults'] as List).single as Map;
      expect(result['ok'], isFalse);
      expect(result['error'], kNotYours);
      expect(c.entries.whereType<ErrorEntry>(), isEmpty);
    });

    test('an unknown tool is an error the model hears, never a crash', () async {
      server
        ..replies.add(_reads([{'callId': 'c1', 'tool': 'launch_missiles', 'args': {}}]))
        ..replies.add(_message('ok'));
      final c = controller();
      await c.send('x');
      expect(((server.requests[1]['toolResults'] as List).single as Map)['error'], contains("can't do that"));
    });

    test('a server failure is shown with its real reason', () async {
      HierarchyApi.useForTests((n, a) async => throw HierarchyException('not-found', 'NOT_FOUND'));
      final c = controller();
      await c.send('hello');
      final e = c.entries.last as ErrorEntry;
      expect(e.text, contains("isn't on the server yet"));
      expect(e.text, contains('not-found'));
      expect(c.busy, isFalse);
    });

    test('a runaway conversation is stopped', () async {
      server.replies.addAll(List.generate(20, (_) => _reads([{'callId': 'c', 'tool': 'list_priority', 'args': {}}])));
      final c = controller();
      await c.send('go');
      expect(c.entries.last, isA<ErrorEntry>());
      expect(server.requests.length, AgentController.maxRounds + 1);
    });

    test('while it is working, a second message is ignored', () async {
      server.replies.add(_message('hi'));
      final c = controller();
      final first = c.send('one');
      final second = c.send('two');
      await Future.wait([first, second]);
      expect(server.requests.length, 1);
    });
  });

  // -------------------------------------------------------------------------
  group('a change is shown first, run only when confirmed, and reported exactly', () {
    Future<(AgentController, ProposalEntry)> propose(String tool, Map<String, dynamic> args, {bool dbl = false, String as = 'G'}) async {
      server.replies.add(_confirm('p1', [_action('c1', tool, args, dbl: dbl)]));
      final c = controller(as);
      await c.send('do it');
      return (c, c.entries.last as ProposalEntry);
    }

    test('nothing is written while the card is on screen', () async {
      final (c, entry) = await propose('meeting_request', {'studentUid': 'u_arjun', 'date': '2026-10-26', 'time': '18:00'});
      expect(entry.state, ProposalState.waiting);
      expect((await db.collection('associations').get()).docs.length, 4, reason: 'only the seeded ones');
      expect(server.pushes, isEmpty);
      expect(c.busy, isFalse);
    });

    test('confirming runs the shared function: the meeting is requested and the student told', () async {
      final (c, entry) = await propose('meeting_request', {'studentUid': 'u_arjun', 'date': '2026-10-26', 'time': '18:00', 'message': 'Please come'});
      server.replies.add(_message('Done — Arjun has been asked.'));
      await c.confirm(entry, confirmations: 1);

      final docs = (await db.collection('associations').where('requestedBy', isEqualTo: 'guide').get()).docs;
      expect(docs.length, 1);
      final d = docs.single.data();
      expect(d['studentUid'], 'u_arjun');
      expect(d['studentName'], 'Arjun Kumar');
      expect(d['guideId'], 'G');
      expect(d['status'], 'pending');
      expect(d['studentNotes'], 'Please come');
      expect((d['preferredDate'] as Timestamp).toDate(), DateTime(2026, 10, 26, 18));
      expect(server.pushes.single['kind'], 'association_update');
      expect(server.pushes.single['studentUid'], 'u_arjun');

      final report = server.requests.last;
      expect(report['outcome'], 'executed');
      expect(report['proposalId'], 'p1');
      expect(report['confirmations'], 1);
      final r = (report['results'] as List).single as Map;
      expect(r['callId'], 'c1');
      expect(r['ok'], isTrue);
      expect(entry.state, ProposalState.done);
      expect(entry.results['c1']!.$1, isTrue);
      expect(entry.results['c1']!.$2, contains('Meeting requested with Arjun Kumar'));
      expect((c.entries.last as AssistantEntry).text, contains('Done'));
    });

    test('cancelling changes nothing and tells the server', () async {
      final (c, entry) = await propose('meeting_request', {'studentUid': 'u_arjun', 'date': '2026-10-26', 'time': '18:00'});
      server.replies.add(_message('Okay, nothing changed.'));
      await c.cancel(entry);
      expect(entry.state, ProposalState.cancelled);
      expect((await db.collection('associations').where('requestedBy', isEqualTo: 'guide').get()).docs, isEmpty);
      expect(server.pushes, isEmpty);
      expect(server.requests.last['outcome'], 'cancelled');
      // and it cannot be run afterwards
      await c.confirm(entry, confirmations: 1);
      expect((await db.collection('associations').where('requestedBy', isEqualTo: 'guide').get()).docs, isEmpty);
    });

    test('a deletion needs two confirmations — with one, it does not run at all', () async {
      final (c, entry) = await propose('flagged_delete', {'messageIds': ['f_u_arjun']}, dbl: true);
      expect(entry.proposal.needsSecondConfirmation, isTrue);
      await expectLater(c.confirm(entry, confirmations: 1), throwsStateError);
      expect((await db.collection('flaggedChatMessages').doc('f_u_arjun').get()).exists, isTrue);
      expect(entry.state, ProposalState.waiting, reason: 'still waiting for the guide');

      server.replies.add(_message('Deleted.'));
      await c.confirm(entry, confirmations: 2);
      expect((await db.collection('flaggedChatMessages').doc('f_u_arjun').get()).exists, isFalse);
      expect(server.requests.last['confirmations'], 2);
    });

    test('a change the guide may not make is refused and reported as failed, with nothing written', () async {
      final (c, entry) = await propose('meeting_request', {'studentUid': 'u_gauri', 'date': '2026-10-26', 'time': '18:00'});
      server.replies.add(_message("I couldn't do that."));
      await c.confirm(entry, confirmations: 1);
      expect((await db.collection('associations').where('requestedBy', isEqualTo: 'guide').get()).docs, isEmpty);
      final r = ((server.requests.last['results']) as List).single as Map;
      expect(r['ok'], isFalse);
      expect(r['error'], kNotYours);
      expect(entry.results['c1']!.$1, isFalse);
    });

    test('several changes run in order, and one failing does not stop the others', () async {
      server.replies.add(_confirm('p9', [
        _action('c1', 'student_comment_add', {'studentUid': 'u_arjun', 'text': 'First'}),
        _action('c2', 'student_comment_add', {'studentUid': 'u_ravi', 'text': 'Not mine'}),
        _action('c3', 'student_comment_add', {'studentUid': 'u_bhima', 'text': 'Third'}),
      ]));
      final c = controller();
      await c.send('comment on all');
      final entry = c.entries.last as ProposalEntry;
      server.replies.add(_message('Two of three done.'));
      await c.confirm(entry, confirmations: 1);
      final results = {for (final r in server.requests.last['results'] as List) (r as Map)['callId']: r['ok']};
      expect(results, {'c1': true, 'c2': false, 'c3': true});
      expect((await db.collection('studentComments').doc('u_arjun').collection('messages').get()).docs.length, 1);
      expect((await db.collection('studentComments').doc('u_ravi').collection('messages').get()).docs, isEmpty);
    });

    test('the roster is re-read after a change, so the next look sees it', () async {
      final env = envFor('G');
      final c = AgentController(env: env);
      server.replies.add(_confirm('p2', [_action('c1', 'student_commitments_set', {'studentUid': 'u_arjun', 'rounds': 25})]));
      await c.send('set his rounds');
      expect((await env.students())['u_arjun']!['commitmentRounds'], 16, reason: 'read once, kept');
      server.replies.add(_message('Done.'));
      await c.confirm(c.entries.last as ProposalEntry, confirmations: 1);
      expect((await env.students())['u_arjun']!['commitmentRounds'], 25, reason: 'read again after the change');
    });

    test('advice is worked out from the guide\'s own data and shown beside the card', () async {
      await db.collection('associations').doc('a_extra').set({
        'studentUid': 'u_arjun', 'studentName': 'Arjun Kumar', 'status': 'confirmed', 'confirmedDate': Timestamp.fromDate(DateTime(2026, 10, 27, 17)),
        'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male',
      });
      final (c, entry) = await propose('meeting_request', {'studentUid': 'u_arjun', 'date': '2026-10-26', 'time': '18:00'});
      expect(entry.advice.any((l) => l.contains('Arjun Kumar already has 1 meeting with you that week')), isTrue, reason: entry.advice.join('|'));
      c.reset();
    });

    test('a date that has passed is pointed out before confirming', () async {
      final (_, entry) = await propose('meeting_request', {'studentUid': 'u_arjun', 'date': '2026-10-01', 'time': '18:00'});
      expect(entry.advice.any((l) => l.contains('has already passed')), isTrue, reason: entry.advice.join('|'));
    });
  });

  // -------------------------------------------------------------------------
  group('every change that names a student or a record refuses one outside the scope — writing nothing', () {
    // A Guide G, whose scope excludes u_ravi (another team) and u_gauri (a girl).
    final studentTools = <String, Map<String, dynamic>>{
      'meeting_request': {'date': '2026-11-05', 'time': '18:00'},
      'interaction_add': {'notes': 'x', 'interactionType': 'Call', 'date': '2026-10-22'},
      'lit_record': {'L': 3, 'I': 3, 'T': 3, 'evidence': 'x', 'confidence': 'low'},
      'student_comment_add': {'text': 'x'},
      'book_assign': {'bookId': 'level-1/book_1', 'commitmentDate': '2026-12-01'},
      'book_finish': {'bookId': 'level-1/book_1'},
      'book_unfinish': {'bookId': 'level-1/book_1'},
      'student_commitments_set': {'rounds': 20},
      'student_notification_set': {'key': 'books', 'value': false},
      'student_residence_set': {'residence': 'Stay at Hostel'},
      'student_dob_set': {'dob': '2004-05-17'},
      'student_assign': {'toGuideId': 'G'},
      'student_delete': {},
      'suggestions_generate': {},
      'service_assign': {'serviceNumber': '1'},
      'music_tick_set': {'checkpointId': 'cp1', 'ticked': true},
      'board_card_move': {'boardId': 'b1', 'columnId': 'c1'},
      'board_card_remove': {'boardId': 'b1'},
    };
    final listTools = <String, Map<String, dynamic>>{'priority_remove': {}, 'priority_restore': {}, 'submission_remind': {}};
    final recordTools = <String, Map<String, dynamic>>{
      'meeting_confirm': {'associationId': 'a_u_ravi', 'date': '2026-11-05', 'time': '18:00'},
      'meeting_accept_student_date': {'associationId': 'a_u_ravi'},
      'meeting_complete': {'associationId': 'a_u_ravi', 'notes': 'x'},
      'meeting_cancel': {'associationId': 'a_u_ravi'},
      'meeting_reschedule': {'associationId': 'a_u_ravi', 'date': '2026-11-05', 'time': '18:00'},
      'meeting_delete': {'associationIds': ['a_u_ravi']},
      'interaction_edit': {'interactionId': 'i_u_ravi', 'concerns': 'x'},
      'interaction_reextract': {'interactionId': 'i_u_ravi'},
      'interaction_delete': {'interactionIds': ['i_u_ravi']},
      'flagged_mark_reviewed': {'messageId': 'f_u_ravi', 'reviewed': true},
      'flagged_delete': {'messageIds': ['f_u_ravi']},
      'doubt_answer': {'doubtId': 'd_u_ravi', 'text': 'x'},
      'trip_attendance_set': {'registrationId': 't1_u_ravi', 'attendance': 'full'},
      'service_set_status': {'assignmentId': 'sv_u_ravi', 'status': 'completed'},
      'service_set_competence': {'assignmentId': 'sv_u_ravi', 'level': 'yes'},
      'service_withdraw': {'assignmentId': 'sv_u_ravi'},
    };

    final all = {...kAgentWritesA, ...kAgentWritesB};

    for (final entry in studentTools.entries) {
      for (final outsider in ['u_ravi', 'u_gauri']) {
        test('${entry.key} for $outsider', () async {
          final env = envFor('G');
          final before = db.dump();
          final args = {'studentUid': outsider, ...entry.value};
          await expectLater(all[entry.key]!(args, env), throwsA(isA<AgentFailure>().having((f) => f.message, 'message', kNotYours)));
          expect(db.dump(), before, reason: 'nothing was written');
          expect(server.pushes, isEmpty, reason: 'and nobody was told');
        });
      }
    }

    for (final entry in listTools.entries) {
      test('${entry.key} with an outsider in the list', () async {
        final env = envFor('G');
        final before = db.dump();
        await expectLater(all[entry.key]!({'studentUids': ['u_arjun', 'u_gauri'], ...entry.value}, env), throwsA(isA<AgentFailure>().having((f) => f.message, 'message', kNotYours)));
        expect(db.dump(), before);
        expect(server.pushes, isEmpty);
      });
    }

    for (final entry in recordTools.entries) {
      test('${entry.key} on a record about an outsider', () async {
        final env = envFor('G');
        final before = db.dump();
        await expectLater(all[entry.key]!(entry.value, env), throwsA(isA<AgentFailure>().having((f) => f.message, 'message', kNotYours)));
        expect(db.dump(), before);
        expect(server.pushes, isEmpty);
      });
    }

    test('the same refusals hold for a Female Enabler asking about boys, and a Male Enabler about girls', () async {
      final before = db.dump();
      await expectLater(kAgentWritesA['student_comment_add']!({'studentUid': 'u_arjun', 'text': 'x'}, envFor('F1')), throwsA(isA<AgentFailure>()));
      await expectLater(kAgentWritesA['student_comment_add']!({'studentUid': 'u_gauri', 'text': 'x'}, envFor('M1')), throwsA(isA<AgentFailure>()));
      await expectLater(kAgentWritesA['meeting_confirm']!({'associationId': 'a_u_arjun', 'date': '2026-11-05', 'time': '18:00'}, envFor('F1')), throwsA(isA<AgentFailure>()));
      expect(db.dump(), before);
    });

    test('a HOD may do what they could do by hand: any student', () async {
      final r = await kAgentWritesA['student_comment_add']!({'studentUid': 'u_ravi', 'text': 'From the HOD'}, envFor('H'));
      expect(r.ok, isTrue);
      final c = (await db.collection('studentComments').doc('u_ravi').collection('messages').get()).docs.single.data();
      expect(c['authorRole'], 'HOD');
    });
  });

  // -------------------------------------------------------------------------
  group('what each change writes (the shared function ran)', () {
    test('LIT: three separate axes, never a sum', () async {
      await kAgentWritesA['lit_record']!({'studentUid': 'u_arjun', 'L': 4, 'I': 3, 'T': 2, 'evidence': 'Asked good questions', 'confidence': 'medium'}, envFor('G'));
      final d = (await db.collection('litAssessments').get()).docs.single.data();
      expect([d['L'], d['I'], d['T']], [4, 3, 2]);
      expect(d['guideId'], 'G');
      expect(d.containsKey('total'), isFalse);
    });

    test('books: assigned with a deadline and the student told; finished; un-finished', () async {
      final env = envFor('G');
      await kAgentWritesA['book_assign']!({'studentUid': 'u_arjun', 'bookId': 'level-1/book_1', 'commitmentDate': '2026-12-01'}, env);
      var d = (await db.collection('booksRead').doc('u_arjun_level-1_book_1').get()).data()!;
      expect(d['bookTitle'], 'Bhagavad-gita As It Is');
      expect(d['commitmentDate'], '2026-12-01');
      expect(server.pushes.single['kind'], 'book_assigned');
      await kAgentWritesA['book_finish']!({'studentUid': 'u_arjun', 'bookId': 'level-1/book_1'}, env);
      d = (await db.collection('booksRead').doc('u_arjun_level-1_book_1').get()).data()!;
      expect(d['endedBy'], 'guide');
      await expectLater(kAgentWritesA['book_assign']!({'studentUid': 'u_arjun', 'bookId': 'level-1/book_1', 'commitmentDate': '2026-12-01'}, env),
          throwsA(isA<AgentFailure>().having((f) => f.message, 'message', contains('already finished'))));
      await kAgentWritesA['book_unfinish']!({'studentUid': 'u_arjun', 'bookId': 'level-1/book_1'}, env);
      d = (await db.collection('booksRead').doc('u_arjun_level-1_book_1').get()).data()!;
      expect(d.containsKey('endDate'), isFalse);
    });

    test('commitments keep the field that was not mentioned', () async {
      await kAgentWritesA['student_commitments_set']!({'studentUid': 'u_arjun', 'rounds': 20}, envFor('G'));
      final d = (await db.collection('users').doc('u_arjun').get()).data()!;
      expect(d['commitmentRounds'], 20);
      expect(d['readingCommitmentMinutes'], 30, reason: 'unchanged');
    });

    test('priority: removal remembers the concerns shown, restore deletes only this admin\'s record', () async {
      final env = envFor('G');
      final list = await env.priority();
      expect(list.students.any((s) => s.uid == 'u_arjun'), isTrue, reason: 'never logged in the window: a concern exists');
      await kAgentWritesA['priority_remove']!({'studentUids': ['u_arjun']}, env);
      final d = (await db.collection('priorityDismissals').doc('G__u_arjun').get()).data()!;
      expect(d['adminId'], 'G');
      expect(d['kinds'], isNotEmpty);
      await kAgentWritesA['priority_restore']!({'studentUids': ['u_arjun']}, env);
      expect((await db.collection('priorityDismissals').doc('G__u_arjun').get()).exists, isFalse);
    });

    test('trips and competitions: created for the right audience; the students are told once', () async {
      final env = envFor('G');
      await kAgentWritesA['trip_create']!({'title': 'Govardhan', 'startDate': '2026-12-05', 'endDate': '2026-12-06', 'targetGender': 'male'}, env);
      final trip = (await db.collection('expeditions').where('title', isEqualTo: 'Govardhan').get()).docs.single.data();
      expect(trip['createdBy'], 'G');
      expect(trip['targetGender'], 'male');
      await kAgentWritesA['competition_create']!({'name': 'Diwali', 'targetRounds': 5000, 'startDate': '2026-11-01', 'endDate': '2026-11-05'}, env);
      final c = (await db.collection('chantingChallenges').where('name', isEqualTo: 'Diwali').get()).docs.single.data();
      expect(c['guideIds'], ['G', 'M1']);
      expect(server.pushes.where((p) => p['kind'] == 'chanting_challenge').length, 1);
    });

    test('meetings: confirm, reschedule, complete, cancel each do their one thing and tell the student', () async {
      final env = envFor('G');
      await kAgentWritesA['meeting_confirm']!({'associationId': 'a_u_arjun', 'date': '2026-11-05', 'time': '18:30'}, env);
      var d = (await db.collection('associations').doc('a_u_arjun').get()).data()!;
      expect(d['status'], 'confirmed');
      expect((d['confirmedDate'] as Timestamp).toDate(), DateTime(2026, 11, 5, 18, 30));
      await kAgentWritesA['meeting_reschedule']!({'associationId': 'a_u_arjun', 'date': '2026-11-06', 'time': '19:00'}, env);
      d = (await db.collection('associations').doc('a_u_arjun').get()).data()!;
      expect((d['confirmedDate'] as Timestamp).toDate(), DateTime(2026, 11, 6, 19));
      await kAgentWritesA['meeting_complete']!({'associationId': 'a_u_arjun', 'notes': 'Good talk'}, env);
      d = (await db.collection('associations').doc('a_u_arjun').get()).data()!;
      expect(d['status'], 'completed');
      expect(d['guideNotes'], 'Good talk');
      await kAgentWritesA['meeting_cancel']!({'associationId': 'a_u_bhima'}, env);
      expect((await db.collection('associations').doc('a_u_bhima').get()).data()!['status'], 'cancelled');
      expect(server.pushes.map((p) => p['title']), ['Meeting Confirmed', 'Meeting Rescheduled', 'Meeting Cancelled']);
    });

    test('interactions: edited fields merge into the summary; deleted ones are really gone', () async {
      final env = envFor('G');
      await kAgentWritesA['interaction_edit']!({'interactionId': 'i_u_arjun', 'concerns': 'Exams', 'themes': ['exams']}, env);
      final d = (await db.collection('interactionLogs').doc('i_u_arjun').get()).data()!;
      expect((d['approvedSummary'] as Map)['studentConcerns'], 'Exams');
      expect((d['approvedSummary'] as Map)['themes'], ['exams']);
      expect((d['approvedSummary'] as Map)['interactionType'], 'Call', reason: 'the rest of the summary is kept');
      await kAgentWritesA['interaction_delete']!({'interactionIds': ['i_u_arjun']}, env);
      expect((await db.collection('interactionLogs').doc('i_u_arjun').get()).exists, isFalse);
    });

    test('a delete of a record the rules would not let this guide delete is reported, not hidden', () async {
      // a legacy record, unstamped, with someone else's guideId
      await db.collection('flaggedChatMessages').doc('f_legacy').set({'studentUid': 'u_arjun', 'studentName': 'Arjun Kumar', 'guideId': 'G2', 'text': 'x'});
      final r = await kAgentWritesA['flagged_delete']!({'messageIds': ['f_legacy']}, envFor('G'));
      expect(r.ok, isFalse);
      expect(r.error, contains('not permitted'));
      expect((await db.collection('flaggedChatMessages').doc('f_legacy').get()).exists, isTrue);
    });

    test('boards: only your own boards; the Guide Assignment board is left to the app', () async {
      final env = envFor('G');
      await kAgentWritesB['board_column_add']!({'boardId': 'b1', 'title': 'Done'}, env);
      expect((await db.collection('boards').doc('b1').collection('columns').get()).docs.length, 2);
      await db.collection('boards').doc('ga').set({'kind': 'guideAssignment', 'ownerGuideId': 'H', 'title': 'Guides', 'sharedWith': <String>[]});
      await expectLater(kAgentWritesB['board_rename']!({'boardId': 'ga', 'title': 'x'}, env), throwsA(isA<AgentFailure>()));
    });

    test('music: a checkpoint is added to an instrument; ticking is per student', () async {
      final env = envFor('H');
      await kAgentWritesB['music_checkpoints_edit']!({'instrumentId': 'm1', 'action': 'add', 'title': 'Solo'}, env);
      final cps = ((await db.collection('musicCurriculum').doc('m1').get()).data()!['checkpoints'] as List);
      expect(cps.map((c) => (c as Map)['title']), ['Tala', 'Solo']);
      await kAgentWritesB['music_tick_set']!({'studentUid': 'u_arjun', 'checkpointId': 'cp1', 'ticked': true}, env);
      final progress = (await db.collection('musicProgress').doc('u_arjun').get()).data()!;
      expect(((progress['ticks'] as Map)['cp1'] as Map)['by'], 'H');
    });

    test('settings: appearance and sign out go only through what the app gave the agent', () async {
      await expectLater(kAgentWritesB['appearance_set']!({'mode': 'dark'}, envFor('G')), throwsA(isA<AgentFailure>()));
      var signedOut = false;
      final env = AgentEnv(profile: _profile('G'), db: db, signOut: () async => signedOut = true);
      final r = await kAgentWritesB['sign_out']!({}, env);
      expect(r.ok, isTrue);
      expect(signedOut, isTrue);
    });
  });
}
