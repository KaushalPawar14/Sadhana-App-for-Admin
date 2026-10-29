import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentReads.dart';
import 'package:folk_guide_app/agent/AgentWrites2.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';

/// The assistant reads the calendar exactly as the calendar screen shows it (the guide's own events AND the automatic ones),
/// answers for a day / a week / a range, marks the automatic ones read-only (with where to change them), and its edit / delete of a
/// guide's own event is untouched. "Today" is Fri 30 Oct 2026.

Timestamp ts(int y, int m, int d) => Timestamp.fromDate(DateTime(y, m, d, 12));

AdminProfile _profile(String id, String role, {String team = ''}) => AdminProfile.fromMap({
      'id': id,
      'displayName': 'Admin $id',
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [
        {'id': 'H', 'displayName': 'Hari', 'role': 'HOD', 'teamGuide': ''},
        {'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': ''},
        {'id': 'M1', 'displayName': 'Madhava', 'role': 'MALE_ENABLER', 'teamGuide': 'G'},
      ],
    });

Future<void> _seed(FakeFirebaseFirestore db) async {
  Map<String, Object?> stamp(String g, String t) => {'scopeGuide': g, 'scopeTeam': t, 'scopeGender': 'male'};
  for (final s in [('u_own', 'Own', 'G', 'G'), ('u_me', 'MeBoy', 'M1', 'G'), ('u_other', 'Other', 'G2', 'G2')]) {
    await db.collection('users').doc(s.$1).set({'name': s.$2, 'gender': 'male', 'guideId': s.$3, 'teamGuide': s.$4, 'role': 'Stay at FOLK'});
  }
  await db.collection('interactionLogs').doc('l1').set({
    'studentUid': 'u_own', 'studentName': 'Own', 'status': 'approved', 'interactionDate': ts(2026, 10, 20), 'createdAt': ts(2026, 10, 20),
    'approvedSummary': {'followUpDate': ts(2026, 11, 2), 'recommendedNextAction': 'Ask about japa'}, ...stamp('G', 'G'),
  });
  await db.collection('interactionLogs').doc('l2').set({
    'studentUid': 'u_me', 'studentName': 'MeBoy', 'status': 'approved', 'interactionDate': ts(2026, 10, 20), 'createdAt': ts(2026, 10, 20),
    'approvedSummary': {'followUpDate': ts(2026, 11, 3)}, ...stamp('M1', 'G'),
  });
  await db.collection('interactionLogs').doc('l3').set({
    'studentUid': 'u_other', 'studentName': 'Other', 'status': 'approved', 'interactionDate': ts(2026, 10, 20), 'createdAt': ts(2026, 10, 20),
    'approvedSummary': {'followUpDate': ts(2026, 11, 4)}, ...stamp('G2', 'G2'),
  });
  await db.collection('expeditions').doc('t1').set({'title': 'Mayapur', 'tripDate': ts(2026, 11, 20), 'endDate': ts(2026, 11, 23), 'createdBy': 'G', 'status': 'upcoming', 'archived': false});
  await db.collection('chantingChallenges').doc('c1').set({'name': 'Diwali Push', 'startDate': ts(2026, 11, 1), 'endDate': ts(2026, 11, 5), 'guideId': 'G', 'status': 'active'});

  // the guide's own events: two in one note block, one alone
  await db.collection('calendarTextBlocks').doc('b1').set({'rawText': 'Exams and a festival', 'submittedBy': 'G', 'submittedAt': ts(2026, 10, 1), 'scope': 'personal', 'ownerGuideId': 'G'});
  await db.collection('calendarTextBlocks').doc('b2').set({'rawText': 'Diwali', 'submittedBy': 'G', 'submittedAt': ts(2026, 10, 1), 'scope': 'personal', 'ownerGuideId': 'G'});
  await db.collection('calendarEvents').doc('e_exam').set({
    'eventDate': ts(2026, 12, 31), 'endDate': ts(2027, 1, 17), 'type': 'exam', 'title': 'Exams', 'note': '', 'sourceTextBlockId': 'b1', 'scope': 'personal',
    'ownerGuideId': 'G', 'createdAt': ts(2026, 10, 1), 'notifyOffsets': ['oneWeekBefore'],
  });
  await db.collection('calendarEvents').doc('e_fest').set({
    'eventDate': ts(2026, 11, 12), 'type': 'festival', 'title': 'Diwali', 'note': '', 'sourceTextBlockId': 'b1', 'scope': 'personal',
    'ownerGuideId': 'G', 'createdAt': ts(2026, 10, 1), 'notifyOffsets': ['oneWeekBefore'],
  });
  await db.collection('calendarEvents').doc('e_solo').set({
    'eventDate': ts(2026, 11, 14), 'type': 'other', 'title': 'Solo errand', 'note': '', 'sourceTextBlockId': 'b2', 'scope': 'personal',
    'ownerGuideId': 'G', 'createdAt': ts(2026, 10, 1), 'notifyOffsets': ['oneWeekBefore'],
  });
  await db.collection('calendarEvents').doc('e_mand').set({
    'eventDate': ts(2026, 11, 10), 'type': 'program', 'title': 'Camp', 'note': '', 'sourceTextBlockId': 'bm', 'scope': 'mandatory', 'createdAt': ts(2026, 10, 1),
    'notifyOffsets': ['oneWeekBefore'],
  });
}

void main() {
  late FakeFirebaseFirestore db;
  setUp(() async {
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    await _seed(db);
  });
  tearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  AgentEnv envFor(AdminProfile p) {
    AdminProfileProvider.instance.debugSet(p);
    return AgentEnv(profile: p, db: db, clock: () => DateTime(2026, 10, 30, 12));
  }

  Future<List<Map>> calendar(AdminProfile p, [Map<String, dynamic> args = const {}]) async {
    final r = await listCalendar(args, envFor(p));
    return [for (final e in (r.data as Map)['events'] as List) e as Map];
  }

  test('"what\'s coming up": the guide\'s own events and the automatic ones, in date order, each with its kind', () async {
    final events = await calendar(_profile('G', 'GUIDE'));
    expect([for (final e in events) e['title']], [
      'Competition: Diwali Push', 'Follow-up: Own', 'Follow-up: MeBoy', 'Camp', 'Diwali', 'Solo errand', 'Trip: Mayapur',
    ], reason: 'the default window is the next 31 days: 30 Oct - 30 Nov');
    final byTitle = {for (final e in events) e['title']: e};
    expect(byTitle['Follow-up: Own']!['kind'], 'Follow-up');
    expect(byTitle['Follow-up: Own']!['readOnly'], true);
    expect(byTitle['Follow-up: Own']!['changeItIn'], "the student's Interactions");
    expect(byTitle['Trip: Mayapur']!['lastDay'], '2026-11-23');
    expect(byTitle['Trip: Mayapur']!['changeItIn'], 'Expeditions');
    expect(byTitle['Diwali']!.containsKey('readOnly'), isFalse, reason: 'the guide\'s own events are editable');
    expect(byTitle['Diwali']!['type'], 'festival');
  });

  test('a day, a week and a range', () async {
    final g = _profile('G', 'GUIDE');
    expect([for (final e in await calendar(g, {'fromDate': '2026-11-02', 'toDate': '2026-11-02'})) e['title']], ['Competition: Diwali Push', 'Follow-up: Own']);
    expect([for (final e in await calendar(g, {'fromDate': '2026-11-02', 'toDate': '2026-11-08'})) e['title']], ['Competition: Diwali Push', 'Follow-up: Own', 'Follow-up: MeBoy']);
    // a range that starts before and ends inside the window still shows: the exams run 31 Dec - 17 Jan
    final across = await calendar(g, {'fromDate': '2027-01-10', 'toDate': '2027-01-12'});
    expect([for (final e in across) e['title']], ['Exams']);
    expect(across.single['lastDay'], '2027-01-17');
    expect(await calendar(g, {'fromDate': '2027-02-01', 'toDate': '2027-02-28'}), isEmpty);
  });

  test('scope: each role is told only what it sees; never another Guide\'s student, trip or competition', () async {
    final g = (await calendar(_profile('G', 'GUIDE'))).map((e) => e['title']).join(' | ');
    expect(g.contains('Other'), isFalse);
    final me = await calendar(_profile('M1', 'MALE_ENABLER', team: 'G'));
    expect([for (final e in me) e['title']], ['Follow-up: MeBoy', 'Camp'], reason: 'his own student, and the HOD\'s mandatory event; not the Guide\'s trip, competition or own events');
    final hod = (await calendar(_profile('H', 'HOD'))).map((e) => e['title']).toList();
    expect(hod, containsAll(['Follow-up: Own', 'Follow-up: MeBoy', 'Follow-up: Other', 'Trip: Mayapur', 'Competition: Diwali Push', 'Camp']));
  });

  test('only the guide\'s own events are things the assistant may edit or delete: the automatic ones are not entities', () async {
    final r = await listCalendar({}, envFor(_profile('G', 'GUIDE')));
    final ids = {for (final e in r.entities) e.id};
    expect(ids, containsAll(['e_fest', 'e_solo']));
    expect(ids.any((i) => i.startsWith('followUp_') || i.startsWith('trip_') || i.startsWith('competition_')), isFalse);
  });

  test('a manual event says which note block holds it and how many events that block has (so a delete is not a surprise)', () async {
    final events = await calendar(_profile('G', 'GUIDE'), {'fromDate': '2026-11-01', 'toDate': '2027-01-31'});
    final diwali = events.firstWhere((e) => e['title'] == 'Diwali');
    expect(diwali['blockId'], 'b1');
    expect(diwali['eventsInItsBlock'], 2, reason: 'Exams and Diwali are in one block');
    final solo = events.firstWhere((e) => e['title'] == 'Solo errand');
    expect(solo['blockId'], 'b2');
    expect(solo['eventsInItsBlock'], 1);
  });

  test('the guide\'s own event can still be edited and its block deleted; a mandatory one only by the HOD', () async {
    final env = envFor(_profile('G', 'GUIDE'));
    await calendarEditEvent({'eventId': 'e_fest', 'date': '2026-11-13', 'type': 'festival', 'title': 'Diwali'}, env);
    final moved = ((await db.collection('calendarEvents').doc('e_fest').get()).data()!['eventDate'] as Timestamp).toDate();
    expect([moved.year, moved.month, moved.day], [2026, 11, 13]);
    await calendarDeleteBlock({'blockId': 'b2'}, env);
    expect((await db.collection('calendarEvents').doc('e_solo').get()).exists, isFalse);
    await expectLater(calendarEditEvent({'eventId': 'e_mand', 'date': '2026-11-11', 'type': 'program', 'title': 'Camp'}, env), throwsA(anything));
    // an automatic event's id is not a calendar event: nothing to edit
    await expectLater(calendarEditEvent({'eventId': 'followUp_l1', 'date': '2026-11-11', 'type': 'other', 'title': 'x'}, env), throwsA(anything));
  });
}
