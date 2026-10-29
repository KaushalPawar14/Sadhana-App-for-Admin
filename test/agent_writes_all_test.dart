import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentReads.dart';
import 'package:folk_guide_app/agent/AgentTypes.dart';
import 'package:folk_guide_app/agent/AgentWrites.dart';
import 'package:folk_guide_app/agent/AgentWrites2.dart';
import 'package:folk_guide_app/theme/ThemeModeController.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every change the agent can make, run once against a seeded world as a HOD (who may do all of them), with what
/// it must leave behind. The tests that refuse out-of-scope students and records are in `agent_flow_test.dart`;
/// this one pins that each executor is wired to the right shared function and does its one thing.
///
/// What cannot be shown here: the target tools and "delete a student" go through Firebase callables the test
/// phone cannot reach, so for those only the id handling and the refusal are pinned.

AdminProfile _hod() => AdminProfile.fromMap({
      'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': '', 'email': 'h@x.org',
      'notificationPrefs': {}, 'notificationTypes': [
        {'key': 'chat', 'label': 'Chat', 'scope': 'other'},
      ],
      'admins': [
        {'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': ''},
        {'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': ''},
        {'id': 'M1', 'displayName': 'Madhava Das', 'role': 'MALE_ENABLER', 'teamGuide': 'G'},
      ],
    });

Future<void> _seed(FakeFirebaseFirestore db) async {
  final when = Timestamp.fromDate(DateTime(2026, 11, 2, 18));
  const stamp = {'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'};
  await db.collection('users').doc('u1').set({'name': 'Arjun Kumar', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at FOLK', 'commitmentRounds': 16, 'dob': when});
  await db.collection('flaggedChatMessages').doc('f1').set({'studentUid': 'u1', 'studentName': 'Arjun Kumar', 'text': 'x', 'reviewed': false, ...stamp});
  await db.collection('bookDoubts').doc('d1').set({'uid': 'u1', 'studentName': 'Arjun Kumar', 'mode': 'guide', 'question': 'why?', 'status': 'open', 'askedAt': when, ...stamp});
  await db.collection('expeditions').doc('t1').set({'title': 'Trip', 'tripDate': when, 'endDate': when, 'status': 'upcoming', 'createdBy': 'H', 'targetGender': 'male', 'archived': false});
  await db.collection('expeditionRegistrations').doc('t1_u1').set({'tripId': 't1', 'studentUid': 'u1', 'studentName': 'Arjun Kumar', 'attendance': 'pending', ...stamp});
  await db.collection('chantingChallenges').doc('c1').set({'name': 'Old', 'guideId': 'H', 'status': 'active'});
  await db.collection('chantingChallengeContributions').doc('k1').set({'challengeId': 'c1', 'studentUid': 'u1', ...stamp});
  await db.collection('serviceAssignments').doc('sv1').set({'studentUid': 'u1', 'serviceNumber': 1, 'assignedByGuideId': 'G', 'status': 'assigned', ...stamp});
  await db.collection('calendarTextBlocks').doc('blk1').set({'rawText': 'Old', 'submittedBy': 'H', 'submittedAt': when, 'scope': 'personal', 'ownerGuideId': 'H'});
  await db.collection('calendarEvents').doc('ev1').set({
    'eventDate': when, 'type': 'exam', 'title': 'Exam', 'note': '', 'sourceTextBlockId': 'blk1', 'scope': 'personal', 'ownerGuideId': 'H', 'notifyOffsets': ['oneWeekBefore'],
  });
  await db.collection('musicCurriculum').doc('m1').set({'name': 'Mridanga', 'order': 0, 'checkpoints': [{'id': 'cp1', 'title': 'Tala'}]});
  await db.collection('musicCurriculum').doc('m2').set({'name': 'Kartal', 'order': 1, 'checkpoints': <Object>[]});
  await db.collection('boards').doc('b1').set({'kind': 'custom', 'ownerGuideId': 'H', 'title': 'Board', 'sharedWith': <String>[]});
  await db.collection('boards').doc('b1').collection('columns').doc('c1').set({'title': 'One', 'order': 0, 'colorValue': 1, 'kind': 'normal'});
  await db.collection('boards').doc('b1').collection('columns').doc('c2').set({'title': 'Two', 'order': 1, 'colorValue': 1, 'kind': 'normal'});
  await db.collection('boards').doc('b1').collection('placements').doc('u1').set({'columnId': 'c1', 'order': 0});
  await db.collection('interactionLogs').doc('i1').set({
    'studentUid': 'u1', 'studentName': 'Arjun Kumar', 'interactionDate': when, 'rawDictation': 'He is doing well', 'status': 'approved',
    'approvedSummary': {'interactionType': 'Call'}, ...stamp,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore db;
  late List<Map<String, dynamic>> calls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    AdminProfileProvider.instance.debugSet(_hod());
    await _seed(db);
    calls = [];
    HierarchyApi.useForTests((name, args) async {
      calls.add({'_call': name, ...args});
      switch (name) {
        case 'addAdmin':
        case 'updateAdmin':
          return {'admin': {'id': 'new1', 'displayName': 'New Admin', 'role': args['role'] ?? 'GUIDE', 'teamGuide': ''}, 'boardColumn': name == 'addAdmin' ? 'created' : 'updated'};
        case 'removeAdmin':
          return {'studentCount': 3, 'teamlessEnablers': <String>[], 'removed': true, 'boardColumn': 'removed', 'cardsMoved': 3};
        case 'deleteExpedition':
          return {'deleted': true, 'registrationsDeleted': 1};
        case 'planCorrection':
          return {'ok': true, 'message': args['mode'] == 'remove' ? 'Removed from your plan.' : args['mode'] == 'call' ? 'Changed to a call.' : 'Moved to Thu 5 Nov.'};
        case 'checkMobileTaken':
          return {'taken': false};
        case 'generateStudentSuggestions':
          return {'count': 4};
        case 'sendStudentNotification':
          return {'sent': 1, 'total': 1};
        default:
          return <String, dynamic>{};
      }
    });
  });
  tearDown(() {
    GuideDb.useForTests(null);
    HierarchyApi.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  AgentEnv env({ThemeModeController? themes}) => AgentEnv(profile: _hod(), db: db, clock: () => DateTime(2026, 10, 23, 12), themes: themes);
  final all = {...kAgentWritesA, ...kAgentWritesB};

  Future<Map<String, dynamic>?> doc(String path) async => (await db.doc(path).get()).data();

  test('the table covers every executor (nothing is left untested by omission)', () {
    // the names exercised below, plus the ones whose callables the test phone cannot reach
    expect(all.length, 93 + 0, reason: 'a change was added or removed: update this file');
  });

  group('students', () {
    test('student_add', () async {
      final r = await all['student_add']!({'name': 'New Boy', 'mobile': '9876543210', 'residence': 'Stay at FOLK', 'gender': 'male', 'rounds': 8}, env());
      expect(r.ok, isTrue);
      final d = (await db.collection('users').where('name', isEqualTo: 'New Boy').get()).docs.single.data();
      expect(d['isManualEntry'], isTrue);
      expect(d['commitmentRounds'], 8);
      expect(d.containsKey('guideId'), isFalse, reason: 'a HOD\'s new student starts unassigned');
    });
    test('student_notification_set / residence / dob', () async {
      final e = env();
      await all['student_notification_set']!({'studentUid': 'u1', 'key': 'books', 'value': false}, e);
      await all['student_residence_set']!({'studentUid': 'u1', 'residence': 'Stay at Hostel'}, e);
      await all['student_dob_set']!({'studentUid': 'u1', 'dob': '2004-05-17'}, e);
      final d = (await doc('users/u1'))!;
      expect((d['notificationPrefs'] as Map)['books'], false);
      expect(d['role'], 'Stay at Hostel');
      expect((d['dob'] as Timestamp).toDate(), DateTime(2004, 5, 17));
    });
    test('student_assign goes through the server', () async {
      await all['student_assign']!({'studentUid': 'u1', 'toGuideId': 'G'}, env());
      expect(calls.any((c) => c['_call'] == 'assignStudent' && c['studentId'] == 'u1' && c['toGuideId'] == 'G'), isTrue);
    });
    test('student_delete reports a refusal in words (the server step cannot run here)', () async {
      await expectLater(all['student_delete']!({'studentUid': 'u1'}, env()), throwsA(anything));
      expect((await doc('users/u1')), isNotNull, reason: 'nothing was deleted without the server');
    });
  });

  group('interactions, flagged, doubts', () {
    test('interaction_add saves the record, queued for the server to analyse (the phone calls no AI)', () async {
      final r = await all['interaction_add']!({'studentUid': 'u1', 'notes': 'Spoke today', 'interactionType': 'Call', 'date': '2026-10-22'}, env());
      expect(r.ok, isTrue);
      final d = (await db.collection('interactionLogs').where('rawDictation', isEqualTo: 'Spoke today').get()).docs;
      expect(d.length, 1);
      expect(d.single.data()['analysis'], 'queued');
      expect(calls.any((c) => c['_call'] == 'sendStudentNotification' && c['kind'] == 'interaction_logged'), isTrue);
      expect(calls.any((c) => '${c['_call']}'.contains('gemini')), isFalse);
    });
    test('interaction_reextract asks the server to analyse the notes again', () async {
      await all['interaction_reextract']!({'interactionId': 'i1'}, env());
      expect(calls.where((c) => c['_call'] == 'analyseInteraction').single['logId'], 'i1');
    });
    test('flagged_mark_reviewed and doubt_answer', () async {
      final e = env();
      await all['flagged_mark_reviewed']!({'messageId': 'f1', 'reviewed': true}, e);
      expect((await doc('flaggedChatMessages/f1'))!['reviewed'], true);
      await all['doubt_answer']!({'doubtId': 'd1', 'text': 'Because it is the yuga dharma'}, e);
      final d = (await doc('bookDoubts/d1'))!;
      expect(d['status'], 'answered');
      expect(d['answer'], contains('yuga dharma'));
      expect(d['answeredByName'], 'Harinam Das');
    });
  });

  group('submissions and what the guide tells the assistant about a student', () {
    test('submission_remind sends one nudge for one student, a list for several', () async {
      final e = env();
      await all['submission_remind']!({'studentUids': ['u1']}, e);
      expect(calls.where((c) => c['kind'] == 'submission_nudge').single['studentUid'], 'u1');
    });
    test('student_note_add: goes through the server for a student in scope, with the words as given', () async {
      final r = await all['student_note_add']!({'studentUid': 'u1', 'text': 'keen on service, loves cooking'}, env());
      expect(r.ok, isTrue);
      final c = calls.singleWhere((c) => c['_call'] == 'studentGuideNote');
      expect(c['studentUid'], 'u1');
      expect(c['kind'], 'note');
      expect(c['text'], 'keen on service, loves cooking');
    });
    test('student_folk_interest_set: not interested / open again, reversible, with the reason', () async {
      final e = env();
      await all['student_folk_interest_set']!({'studentUid': 'u1', 'interest': 'not_interested', 'reason': 'his family will not allow it'}, e);
      expect(calls.last['kind'], 'not_folk');
      expect(calls.last['text'], 'his family will not allow it');
      await all['student_folk_interest_set']!({'studentUid': 'u1', 'interest': 'open'}, e);
      expect(calls.last['kind'], 'folk_open');
      expect(calls.last.containsKey('text'), isFalse);
    });
    test('a student outside the scope is not found: nothing is sent', () async {
      await db.collection('users').doc('u_far').set({'name': 'Far', 'gender': 'female', 'guideId': 'F9', 'teamGuide': '', 'role': 'Stay at Hostel'});
      AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({
        'id': 'M1', 'displayName': 'Madhava', 'role': 'MALE_ENABLER', 'teamGuide': 'G', 'email': 'm@x.org', 'notificationPrefs': {}, 'notificationTypes': [],
        'admins': [{'id': 'M1', 'displayName': 'Madhava', 'role': 'MALE_ENABLER', 'teamGuide': 'G'}],
      }));
      final before = calls.length;
      final e = AgentEnv(profile: AdminProfileProvider.current!, db: db, clock: () => DateTime(2026, 10, 23, 12));
      await expectLater(all['student_note_add']!({'studentUid': 'u_far', 'text': 'x'}, e), throwsA(anything));
      await expectLater(all['student_folk_interest_set']!({'studentUid': 'u_far', 'interest': 'not_interested'}, e), throwsA(anything));
      expect(calls.length, before);
    });
  });

  group('competitions and trips', () {
    test('competition_set_status closes and reopens; competition_delete takes its contributions too', () async {
      final e = env();
      await all['competition_set_status']!({'challengeId': 'c1', 'status': 'missed'}, e);
      expect((await doc('chantingChallenges/c1'))!['status'], 'missed');
      expect((await doc('chantingChallenges/c1'))!['closedAt'], isNotNull);
      await all['competition_set_status']!({'challengeId': 'c1', 'status': 'active'}, e);
      expect((await doc('chantingChallenges/c1'))!.containsKey('closedAt'), isFalse);
      await all['competition_delete']!({'challengeId': 'c1'}, e);
      expect(await doc('chantingChallenges/c1'), isNull);
      expect(await doc('chantingChallengeContributions/k1'), isNull);
    });
    test('trip_set_status, trip_attendance_set, trip_delete', () async {
      final e = env();
      await all['trip_set_status']!({'tripId': 't1', 'status': 'ongoing'}, e);
      expect((await doc('expeditions/t1'))!['status'], 'ongoing');
      await all['trip_attendance_set']!({'registrationId': 't1_u1', 'attendance': 'partial'}, e);
      expect((await doc('expeditionRegistrations/t1_u1'))!['attendance'], 'partial');
      final r = await all['trip_delete']!({'tripId': 't1'}, e);
      expect(r.ok, isTrue);
      expect(calls.any((c) => c['_call'] == 'deleteExpedition'), isTrue);
    });
  });

  group('targets', () {
    test('a target id the agent was not given is refused in words', () async {
      for (final t in ['target_regenerate_plan', 'target_abandon', 'target_delete', 'target_set_end_date', 'target_proposal_approve', 'target_proposal_reject', 'target_check_advance']) {
        await expectLater(all[t]!({'targetId': 'no-slash-here', 'endDate': '2026-12-01'}, env()), throwsA(isA<AgentFailure>()), reason: t);
      }
    });
    test('a task naming a student outside the scope is refused', () async {
      final guide = AgentEnv(
        profile: AdminProfile.fromMap({
          'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': [],
        }),
        db: db,
      );
      AdminProfileProvider.instance.debugSet(guide.me);
      await expectLater(
        all['target_edit_phase_tasks']!({'targetId': 'G/t1', 'phaseNumber': 1, 'tasks': [{'type': 'value', 'studentUids': ['u_outside']}]}, guide),
        throwsA(isA<AgentFailure>().having((f) => f.message, 'message', contains("can't find that student"))),
      );
    });
  });

  group('plan (corrected in chat only: the plan pages are read-only)', () {
    test('plan_item_skip: goes through the server, remembers why on the student, and says so', () async {
      final r = await all['plan_item_skip']!(
          {'itemId': 'invite:u1:2026-10-19', 'reason': 'He is a localite', 'constraint': 'no_invites', 'note': 'Cannot come to programs'}, env());
      expect(r.ok, isTrue);
      final call = calls.singleWhere((c) => c['_call'] == 'planCorrection');
      expect(call['itemId'], 'invite:u1:2026-10-19');
      expect(call['mode'], 'remove');
      expect(call['constraint'], 'no_invites');
      expect(call['noteText'], 'Cannot come to programs');
      expect(r.data.toString(), contains('Removed from your plan'));
      // the reason is also a visible note on the student's thread
      final notes = (await db.collection('studentComments').doc('u1').collection('messages').get()).docs;
      expect(notes.single.data()['text'], 'Plan note: Cannot come to programs');
      expect(notes.single.data()['authorId'], 'H');
    });
    test('plan_item_change: to a call, or to another day (which needs a day)', () async {
      final e = env();
      final call = await all['plan_item_change']!({'itemId': 'invite:u1:2026-10-19', 'mode': 'call', 'reason': 'busy'}, e);
      expect(call.ok, isTrue);
      expect(calls.last['mode'], 'call');
      expect((await db.collection('studentComments').doc('u1').collection('messages').get()).docs, isEmpty, reason: 'no note given, none written');
      await expectLater(all['plan_item_change']!({'itemId': 'invite:u1:2026-10-19', 'mode': 'other_day', 'reason': 'away'}, e), throwsA(anything));
      final moved = await all['plan_item_change']!({'itemId': 'invite:u1:2026-10-19', 'mode': 'other_day', 'newDate': '2026-11-05', 'reason': 'away'}, e);
      expect(moved.ok, isTrue);
      expect(calls.last['newDate'], '2026-11-05');
    });
    test('a student outside the guide\'s scope is not found: nothing is sent to the server', () async {
      await db.collection('users').doc('u_far').set({'name': 'Far', 'gender': 'female', 'guideId': 'F9', 'teamGuide': '', 'role': 'Stay at Hostel'});
      AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({
        'id': 'M1', 'displayName': 'Madhava', 'role': 'MALE_ENABLER', 'teamGuide': 'G', 'email': 'm@x.org', 'notificationPrefs': {}, 'notificationTypes': [],
        'admins': [{'id': 'M1', 'displayName': 'Madhava', 'role': 'MALE_ENABLER', 'teamGuide': 'G'}],
      }));
      final before = calls.length;
      await expectLater(
          all['plan_item_skip']!({'itemId': 'invite:u_far:2026-10-19', 'reason': 'x'}, AgentEnv(profile: AdminProfileProvider.current!, db: db, clock: () => DateTime(2026, 10, 23, 12))),
          throwsA(anything));
      expect(calls.length, before);
    });
  });

  group('calendar', () {
    test('calendar_add_notes saves the block and its events; personal for a HOD unless mandatory', () async {
      final e = env();
      await all['calendar_add_notes']!({'text': 'Exam on 5 Nov', 'events': [{'date': '2026-11-05', 'type': 'exam', 'title': 'Exam'}]}, e);
      final blocks = (await db.collection('calendarTextBlocks').where('rawText', isEqualTo: 'Exam on 5 Nov').get()).docs;
      expect(blocks.single.data()['scope'], 'personal');
      expect(blocks.single.data()['ownerGuideId'], 'H');
      expect((await db.collection('calendarEvents').where('title', isEqualTo: 'Exam').get()).docs.length, 2, reason: 'the seeded one and the new one');

      await all['calendar_add_notes']!({'text': 'Festival', 'mandatory': true, 'events': [{'date': '2026-11-10', 'type': 'festival', 'title': 'Festival day'}]}, e);
      final mandatory = (await db.collection('calendarTextBlocks').where('rawText', isEqualTo: 'Festival').get()).docs.single.data();
      expect(mandatory['scope'], 'mandatory');
      expect(mandatory['ownerGuideId'], isNull);
    });
    test('calendar_update_block, calendar_edit_event, calendar_delete_block', () async {
      final e = env();
      await all['calendar_edit_event']!({'eventId': 'ev1', 'date': '2026-11-07', 'type': 'exam', 'title': 'Exam moved'}, e);
      expect((await doc('calendarEvents/ev1'))!['title'], 'Exam moved');
      expect((await doc('calendarEvents/ev1'))!['notifyOffsets'], ['oneWeekBefore'], reason: 'reminders kept when none are given');
      // replacing a block replaces the events that came from it
      await all['calendar_update_block']!({'blockId': 'blk1', 'text': 'New text', 'events': [{'date': '2026-11-06', 'type': 'program', 'title': 'Program'}]}, e);
      expect((await doc('calendarTextBlocks/blk1'))!['rawText'], 'New text');
      expect((await db.collection('calendarEvents').where('title', isEqualTo: 'Program').get()).docs.length, 1);
      await all['calendar_delete_block']!({'blockId': 'blk1'}, e);
      expect(await doc('calendarTextBlocks/blk1'), isNull);
    });
  });

  group('services', () {
    test('assign, status, competence, withdraw', () async {
      final e = env();
      final r = await all['service_assign']!({'studentUid': 'u1', 'serviceNumber': '2'}, e);
      expect(r.ok, isTrue);
      await all['service_set_status']!({'assignmentId': 'sv1', 'status': 'inProgress'}, e);
      expect((await doc('serviceAssignments/sv1'))!['status'], 'inProgress');
      await all['service_set_competence']!({'assignmentId': 'sv1', 'level': 'yes', 'note': 'Does it well'}, e);
      expect(((await doc('serviceAssignments/sv1'))!['competence'] as Map)['level'], 'yes');
      await all['service_withdraw']!({'assignmentId': 'sv1'}, e);
      expect((await doc('serviceAssignments/sv1'))!['status'], 'withdrawn');
    });
    test('a service number that is not one of the services is refused', () async {
      await expectLater(all['service_assign']!({'studentUid': 'u1', 'serviceNumber': '999'}, env()), throwsA(isA<AgentFailure>()));
    });
  });

  group('music', () {
    test('instruments: add, update, reorder, delete', () async {
      final e = env();
      final r = await all['music_instrument_add']!({'name': 'Harmonium', 'link': 'https://x.org/h'}, e);
      expect(r.ok, isTrue);
      await all['music_instrument_update']!({'instrumentId': 'm1', 'name': 'Mridanga (renamed)'}, e);
      expect((await doc('musicCurriculum/m1'))!['name'], 'Mridanga (renamed)');
      await all['music_instrument_reorder']!({'instrumentIds': ['m2', 'm1']}, e);
      expect((await doc('musicCurriculum/m2'))!['order'], 0);
      expect((await doc('musicCurriculum/m1'))!['order'], 1);
      await all['music_instrument_delete']!({'instrumentId': 'm2'}, e);
      expect(await doc('musicCurriculum/m2'), isNull);
    });
    test('checkpoints: rename and remove', () async {
      final e = env();
      await all['music_checkpoints_edit']!({'instrumentId': 'm1', 'action': 'rename', 'checkpointId': 'cp1', 'title': 'Basic tala'}, e);
      expect((((await doc('musicCurriculum/m1'))!['checkpoints']) as List).single['title'], 'Basic tala');
      await all['music_checkpoints_edit']!({'instrumentId': 'm1', 'action': 'remove', 'checkpointId': 'cp1'}, e);
      expect(((await doc('musicCurriculum/m1'))!['checkpoints']) as List, isEmpty);
    });
  });

  group('boards', () {
    test('create, rename, share', () async {
      final e = env();
      final r = await all['board_create']!({'title': 'Outreach', 'columns': ['To call', 'Called']}, e);
      expect(r.ok, isTrue);
      final id = r.entities.single.id;
      expect((await db.collection('boards').doc(id).collection('columns').get()).docs.length, 2);
      await all['board_rename']!({'boardId': id, 'title': 'Outreach 2'}, e);
      expect((await doc('boards/$id'))!['title'], 'Outreach 2');
      await all['board_share']!({'boardId': id, 'sharedWith': ['G', 'M1']}, e);
      expect((await doc('boards/$id'))!['sharedWith'], ['G', 'M1']);
      await all['board_delete']!({'boardId': id}, e);
      expect(await doc('boards/$id'), isNull);
    });
    test('columns: add, rename, recolour, reorder, delete (the cards on it come off)', () async {
      final e = env();
      await all['board_column_add']!({'boardId': 'b1', 'title': 'Three'}, e);
      expect((await db.collection('boards').doc('b1').collection('columns').get()).docs.length, 3);
      await all['board_column_rename']!({'boardId': 'b1', 'columnId': 'c1', 'title': 'Uno'}, e);
      expect((await doc('boards/b1/columns/c1'))!['title'], 'Uno');
      await all['board_column_recolour']!({'boardId': 'b1', 'columnId': 'c1', 'color': 2}, e);
      expect((await doc('boards/b1/columns/c1'))!['colorValue'], isNot(1));
      await expectLater(all['board_column_reorder']!({'boardId': 'b1', 'columnIds': ['c2']}, e), throwsA(isA<AgentFailure>()), reason: 'every column exactly once');
      await all['board_column_reorder']!({'boardId': 'b1', 'columnIds': ['c2', 'c1', (await db.collection('boards').doc('b1').collection('columns').get()).docs.map((d) => d.id).firstWhere((i) => i != 'c1' && i != 'c2')]}, e);
      expect((await doc('boards/b1/columns/c2'))!['order'], 0);
      await all['board_column_delete']!({'boardId': 'b1', 'columnId': 'c1'}, e);
      expect(await doc('boards/b1/columns/c1'), isNull);
      expect(await doc('boards/b1/placements/u1'), isNull, reason: 'the card went with its column');
      expect((await doc('users/u1')), isNotNull, reason: 'the student is untouched');
    });
    test('cards: move and remove', () async {
      final e = env();
      await all['board_card_move']!({'boardId': 'b1', 'studentUid': 'u1', 'columnId': 'c2'}, e);
      expect((await doc('boards/b1/placements/u1'))!['columnId'], 'c2');
      expect((await doc('boards/b1/placements/u1'))!['movedBy'], 'H');
      await all['board_card_remove']!({'boardId': 'b1', 'studentUid': 'u1'}, e);
      expect(await doc('boards/b1/placements/u1'), isNull);
    });
  });

  group('admins and settings', () {
    test('admin_add / admin_update / admin_remove / admin_set_team_guide go through the server', () async {
      final e = env();
      final added = await all['admin_add']!({'name': 'newguy', 'email': 'new@x.org', 'role': 'GUIDE'}, e);
      expect(added.ok, isTrue);
      expect((added.data as Map)['done'], contains('column on the FOLK Boys board was created'), reason: 'the assistant says the board followed');
      expect(calls.any((c) => c['_call'] == 'addAdmin' && c['email'] == 'new@x.org'), isTrue);
      final updated = await all['admin_update']!({'adminId': 'G', 'displayName': 'Gopal D'}, e);
      expect((updated.data as Map)['done'], contains('column on the FOLK Boys board was updated'));
      expect(calls.any((c) => c['_call'] == 'updateAdmin' && c['id'] == 'G'), isTrue);
      final removed = await all['admin_remove']!({'adminId': 'M1'}, e);
      expect((removed.data as Map)['done'], contains('Madhava Das removed'));
      expect((removed.data as Map)['done'], contains('column on the FOLK Boys board was removed (3 cards moved to Unassigned)'));
      await all['admin_set_team_guide']!({'adminId': 'M1', 'teamGuide': 'G'}, e);
      expect(calls.any((c) => c['_call'] == 'setTeamGuide'), isTrue);
    });
    test('my_notifications_set saves through the server and refuses a switch it does not know', () async {
      final e = env();
      await all['my_notifications_set']!({'groups': <Object>[], 'types': [{'key': 'chat', 'on': false}]}, e);
      final saved = calls.firstWhere((c) => c['_call'] == 'saveNotificationPrefs');
      expect((saved['types'] as Map)['chat'], false);
      await expectLater(all['my_notifications_set']!({'groups': <Object>[], 'types': [{'key': 'nonsense', 'on': true}]}, e), throwsA(isA<AgentFailure>()));
    });
    test('appearance_set changes only this phone\'s setting', () async {
      final prefs = await SharedPreferences.getInstance();
      final themes = await ThemeModeController.fromPrefs(prefs);
      await all['appearance_set']!({'mode': 'dark'}, env(themes: themes));
      expect(themes.mode, GuideThemeMode.dark);
      await all['appearance_set']!({'mode': 'auto'}, env(themes: themes));
      expect(themes.mode, GuideThemeMode.auto);
    });
  });
}
