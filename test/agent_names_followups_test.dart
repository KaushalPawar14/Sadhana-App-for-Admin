import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentReads.dart';
import 'package:folk_guide_app/agent/AgentTypes.dart';
import 'package:folk_guide_app/agent/NameMatch.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/PlanningQueries.dart';
import 'package:folk_guide_app/utils/StudentScope.dart';
import 'package:folk_guide_app/utils/WeekSummary.dart';

/// Names that do not match exactly ("Did you mean ...?"), and follow-ups the assistant must find exactly as the screens show them.
///
/// The real case behind it: a student the guide added by hand as "Mananjit" registered as "mananjeet"; his two follow-ups were on
/// Home and Weekly Planning, but the assistant said "no follow-ups" (it looked them up by a student id the merge had left behind).

const _real = 'zqhJDgo84QVjtqsmr5aTogmxkkO2';
const _manual = 'manual_fudltkDcqS8CxlNTUP2x';

AdminProfile _profile(String id, {String role = 'GUIDE', String team = ''}) => AdminProfile.fromMap({
      'id': id,
      'displayName': 'Admin $id',
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [
        {'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': ''},
        {'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': ''},
        {'id': 'G2', 'displayName': 'Govinda Das', 'role': 'GUIDE', 'teamGuide': ''},
        {'id': 'M1', 'displayName': 'Madhava Das', 'role': 'MALE_ENABLER', 'teamGuide': 'G'},
      ],
    });

void main() {
  group('NameMatch', () {
    test('normalises case, digits, dots and spaces', () {
      expect(normaliseName('  Manan21 '), 'manan');
      expect(normaliseName('A.  B-Das'), 'a b das');
    });

    test('typos, missing/extra letters, first name only, spelling variants', () {
      for (final (typed, name) in [
        ('Mananjit', 'mananjeet'),
        ('Manan21', 'mananjeet'),
        ('mananjeet', 'Mananjeet Singh'),
        ('Bima', 'Bhima Sen'),
        ('Bhima Sn', 'Bhima Sen'),
        ('Arjan', 'Arjun Kumar'),
        ('Dhruv', 'Dhruva Nair'),
        ('Dhrva Nair', 'Dhruva Nair'),
        ('SEN BHIMA', 'Bhima Sen'),
        ('Gauri Devi ', 'gauri devi'),
        ('Krisna', 'Krishna'),
        ('Radhey', 'Radhe'),
      ]) {
        expect(nameScore(typed, name), greaterThanOrEqualTo(0.6), reason: '"$typed" should be close to "$name"');
      }
    });

    test('unrelated names are not close', () {
      for (final (typed, name) in [
        ('Zubin Mehta', 'Arjun Kumar'),
        ('Manan Joshi', 'mananjeet'),
        ('Ravi', 'Dhruva Nair'),
        ('Ravi', 'Gopal Das'),
        ('Ram', 'Raj'),
        ('Dev', 'Dhruva'),
      ]) {
        expect(nameScore(typed, name), lessThan(0.6), reason: '"$typed" must not be offered for "$name"');
      }
    });

    test('closeNames: best first, capped, and one clear best is recognised', () {
      final names = ['Arjun Kumar', 'Arjun Patel', 'Bhima Sen', 'Dhruva Nair'];
      final two = closeNames<String>('Arjan', names, (n) => n);
      expect(two.map((m) => m.item), ['Arjun Kumar', 'Arjun Patel']);
      expect(hasClearBest(two), isFalse, reason: 'two equally close names are shown as choices');
      final one = closeNames<String>('Bima Sen', names, (n) => n);
      expect(one.first.item, 'Bhima Sen');
      expect(hasClearBest(one), isTrue);
      expect(closeNames<String>('Zubin Mehta', names, (n) => n), isEmpty);
    });
  });

  group('the assistant, as a Guide', () {
    late FakeFirebaseFirestore db;

    Future<void> seed() async {
      Future<void> student(String uid, String name, String guide, String team, {String gender = 'male'}) => db.collection('users').doc(uid).set({
            'name': name, 'gender': gender, 'guideId': guide, 'teamGuide': team, 'role': 'Stay at FOLK', 'commitmentRounds': 16,
          });
      await student(_real, 'mananjeet', 'G', 'G');
      await student('u_arjun_k', 'Arjun Kumar', 'G', 'G');
      await student('u_arjun_p', 'Arjun Patel', 'G', 'G');
      await student('u_bhima', 'Bhima Sen', 'M1', 'G');
      await student('u_manan_o', 'Manan Joshi', 'G2', 'G2');

      Map<String, Object?> stamp(String guide, String team) => {'scopeGuide': guide, 'scopeTeam': team, 'scopeGender': 'male'};
      Future<void> log(String studentUid, String name, DateTime? followUp, {String status = 'approved', String guide = 'G', String team = 'G', String action = 'Call him'}) =>
          db.collection('interactionLogs').add({
            'studentUid': studentUid, 'studentName': name, 'status': status, 'interactionType': 'Call',
            'interactionDate': Timestamp.fromDate(DateTime(2026, 10, 20, 18)),
            if (followUp != null) 'approvedSummary': {'recommendedNextAction': action, 'followUpDate': Timestamp.fromDate(followUp)},
            ...stamp(guide, team),
          });
      // the real case: the logs still carry the id of the deleted manual entry, and the name the guide typed
      await log(_manual, 'Mananjit', DateTime(2026, 10, 25), action: 'Ask about his Gita reading');
      await log(_manual, 'Mananjit', DateTime(2026, 10, 25), action: 'Call about the trip');
      // ordinary ones
      await log('u_arjun_k', 'Arjun Kumar', DateTime(2026, 10, 22));
      await log('u_arjun_p', 'Arjun Patel', DateTime(2026, 11, 3));
      await log('u_arjun_p', 'Arjun Patel', null);
      await log('u_arjun_k', 'Arjun Kumar', DateTime(2026, 10, 21), status: 'pending');
      await log('u_manan_o', 'Manan Joshi', DateTime(2026, 10, 24), guide: 'G2', team: 'G2', action: 'Other team');
    }

    setUp(() async {
      db = FakeFirebaseFirestore();
      GuideDb.useForTests(db);
      await seed();
      HierarchyApi.useForTests((name, args) async => name == 'listAdmins'
          ? {
              'admins': [
                for (final a in _profile('H', role: 'HOD').admins) {'id': a.id, 'displayName': a.displayName, 'role': a.role.wire, 'teamGuide': a.teamGuide},
              ]
            }
          : <String, dynamic>{});
    });
    tearDown(() {
      GuideDb.useForTests(null);
      HierarchyApi.useForTests(null);
      AdminProfileProvider.instance.debugSet(null);
    });

    AgentEnv envFor(AdminProfile p) {
      AdminProfileProvider.instance.debugSet(p);
      return AgentEnv(profile: p, db: db, clock: () => DateTime(2026, 10, 23, 12));
    }

    String wire(AgentResult r) => jsonEncode({'data': r.data, 'entities': [for (final e in r.entities) e.toMap()]});

    test('"Mananjit" finds no exact name: one close name, as a suggestion only (no student is handed over)', () async {
      final r = await findStudents({'query': 'Mananjit'}, envFor(_profile('G')));
      final d = r.data as Map;
      expect(d['count'], 0);
      expect(d['noExactMatch'], true);
      expect((d['didYouMean'] as List).map((m) => (m as Map)['name']), ['mananjeet']);
      expect(r.entities, isEmpty, reason: 'a suggestion is not a student the assistant may act on until the guide says yes');
      expect(wire(r).contains(_real), isFalse, reason: 'not even the id is given before the guide agrees');
      expect(d['note'], contains('Did you mean'));
    });

    test('"Manan21" (digits) is also recognised', () async {
      final r = await findStudents({'query': 'Manan21'}, envFor(_profile('G')));
      expect(((r.data as Map)['didYouMean'] as List).map((m) => (m as Map)['name']), ['mananjeet']);
    });

    test('several close names are all offered, as choices', () async {
      final r = await findStudents({'query': 'Arjan'}, envFor(_profile('G')));
      final d = r.data as Map;
      expect((d['didYouMean'] as List).map((m) => (m as Map)['name']).toSet(), {'Arjun Kumar', 'Arjun Patel'});
      expect(d['note'], contains('one choice per name'));
      expect(r.entities, isEmpty);
    });

    test('an exact name asks nothing', () async {
      final r = await findStudents({'query': 'Bhima Sen'}, envFor(_profile('G')));
      final d = r.data as Map;
      expect(d['count'], 1);
      expect(d.containsKey('didYouMean'), isFalse);
      expect(d.containsKey('noExactMatch'), isFalse);
      expect(r.entities.map((e) => e.id), ['u_bhima']);
    });

    test('part of a name still finds it exactly (as before)', () async {
      final r = await findStudents({'query': 'bhim'}, envFor(_profile('G')));
      expect((r.data as Map)['count'], 1);
      expect((r.data as Map).containsKey('didYouMean'), isFalse);
    });

    test('nothing close: it says so, and offers nobody', () async {
      final r = await findStudents({'query': 'Zubin Mehta'}, envFor(_profile('G')));
      final d = r.data as Map;
      expect(d['count'], 0);
      expect(d.containsKey('didYouMean'), isFalse);
    });

    test('a name that exists only outside the scope is never offered (not by a typo either)', () async {
      // "Manan Joshi" is Govinda's student; Gopal must not even be told the name is close to anything
      final r = await findStudents({'query': 'Manan Joshi'}, envFor(_profile('G')));
      expect(wire(r).contains('Joshi'), isFalse);
      expect(wire(r).contains('u_manan_o'), isFalse);
      // and a typo of it ("Manan Joshy") must not suggest the in-scope "mananjeet" as if it were the same person
      final typo = await findStudents({'query': 'Manan Joshy'}, envFor(_profile('G')));
      expect(((typo.data as Map)['didYouMean'] as List?) ?? const [], isEmpty);
      // the HOD sees it, and an exact search finds it
      final hod = await findStudents({'query': 'Manan Joshi'}, envFor(_profile('H', role: 'HOD')));
      expect((hod.data as Map)['count'], 1);
    });

    test('an Enabler is offered only names in their own scope', () async {
      final r = await findStudents({'query': 'Arjan'}, envFor(_profile('M1', role: 'MALE_ENABLER', team: 'G')));
      expect(wire(r).contains('Arjun'), isFalse, reason: 'M1 does not see the Arjuns');
    });
  });

  group('follow-ups: the assistant reads what the screens show', () {
    late FakeFirebaseFirestore db;

    setUp(() async {
      db = FakeFirebaseFirestore();
      GuideDb.useForTests(db);
      await db.collection('users').doc(_real).set({'name': 'mananjeet', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at FOLK'});
      await db.collection('users').doc('u_arjun_k').set({'name': 'Arjun Kumar', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at FOLK'});
      await db.collection('users').doc('u_other').set({'name': 'Other Boy', 'gender': 'male', 'guideId': 'G2', 'teamGuide': 'G2', 'role': 'Stay at FOLK'});
      Future<void> log(String uid, String name, DateTime? due, {String status = 'approved', String guide = 'G', String team = 'G'}) => db.collection('interactionLogs').add({
            'studentUid': uid, 'studentName': name, 'status': status, 'interactionType': 'Call',
            'interactionDate': Timestamp.fromDate(DateTime(2026, 10, 20, 18)),
            if (due != null) 'approvedSummary': {'recommendedNextAction': 'Next step for $name', 'followUpDate': Timestamp.fromDate(due)},
            'scopeGuide': guide, 'scopeTeam': team, 'scopeGender': 'male',
          });
      await log(_manual, 'Mananjit', DateTime(2026, 10, 25));
      await log(_manual, 'Mananjit', DateTime(2026, 10, 25));
      await log('u_arjun_k', 'Arjun Kumar', DateTime(2026, 10, 22));
      await log('u_arjun_k', 'Arjun Kumar', DateTime(2026, 11, 3));
      await log('u_arjun_k', 'Arjun Kumar', DateTime(2026, 10, 21), status: 'pending');
      await log('u_arjun_k', 'Arjun Kumar', null); // no follow-up at all
      await log('u_other', 'Other Boy', DateTime(2026, 10, 24), guide: 'G2', team: 'G2');
      HierarchyApi.useForTests((name, args) async => <String, dynamic>{});
    });
    tearDown(() {
      GuideDb.useForTests(null);
      HierarchyApi.useForTests(null);
      AdminProfileProvider.instance.debugSet(null);
    });

    AgentEnv envFor(AdminProfile p) {
      AdminProfileProvider.instance.debugSet(p);
      return AgentEnv(profile: p, db: db, clock: () => DateTime(2026, 10, 23, 12));
    }

    /// The Home / Weekly Planning list, from the same scoped read the screens use.
    Future<List<FollowUpItem>> screen(AgentEnv env) async {
      final snap = await StudentScope.current().historyGet('interactionLogs');
      return followUpsDue(snap.docs, currentWeekRange(env.now));
    }

    test('what is due this week matches Home and Weekly Planning, row for row (Guide)', () async {
      final env = envFor(_profile('G'));
      final onScreen = await screen(env);
      final r = await listFollowups({}, env);
      final d = r.data as Map;
      final got = [for (final f in d['followUps'] as List) ((f as Map)['student'], f['date'], f['action'])];
      expect(got, [for (final i in onScreen) (i.student, agentDateOf(i.when), i.action)]);
      expect(d['count'], onScreen.length);
      expect(d['count'], 3, reason: 'two for Mananjit, one for Arjun Kumar; not the pending one, not next week, not the other team');
    });

    test('what is due this week matches the screens for the HOD, who sees every team', () async {
      final env = envFor(_profile('H', role: 'HOD'));
      final onScreen = await screen(env);
      final d = (await listFollowups({}, env)).data as Map;
      expect(d['count'], onScreen.length);
      expect(d['count'], 4);
    });

    test('an Enabler without those students sees none, and is told nothing about others', () async {
      final env = envFor(_profile('M1', role: 'MALE_ENABLER', team: 'G'));
      final r = await listFollowups({}, env);
      final d = r.data as Map;
      expect(d['count'], 0);
      expect(jsonEncode(d).contains('Mananjit'), isFalse);
      expect(jsonEncode(d).contains('Other Boy'), isFalse);
    });

    test('the real case: the follow-ups of a student whose records still carry the old manual id are found (by the id first, then the name written in them)', () async {
      final env = envFor(_profile('G'));
      final r = await listFollowups({'studentUid': _real, 'when': 'all'}, env);
      final d = r.data as Map;
      expect(d['student'], 'mananjeet');
      expect(d['count'], 2);
      expect(((d['followUps'] as List).first as Map)['student'], 'Mananjit');
      final i = await listInteractions({'studentUid': _real}, env);
      expect((i.data as Map)['count'], 2, reason: 'list_interactions finds them too');
    });

    test('once the records carry the real id (after the merge re-keys them) the plain id lookup finds them', () async {
      final env = envFor(_profile('G'));
      for (final d in (await db.collection('interactionLogs').where('studentUid', isEqualTo: _manual).get()).docs) {
        await d.reference.update({'studentUid': _real});
      }
      final r = await listFollowups({'studentUid': _real, 'when': 'all'}, env);
      expect((r.data as Map)['count'], 2);
      final i = await listInteractions({'studentUid': _real}, env);
      expect((i.data as Map)['count'], 2);
    });

    test('another student of the same guide is not mixed in, and nothing from outside the scope is', () async {
      final env = envFor(_profile('G'));
      final r = await listFollowups({'studentUid': 'u_arjun_k', 'when': 'all'}, env);
      final d = r.data as Map;
      expect(d['count'], 2);
      expect(jsonEncode(d).contains('Mananjit'), isFalse);
      await expectLater(listFollowups({'studentUid': 'u_other'}, env), throwsA(anything), reason: 'a student outside the scope is simply not found');
    });

    test('every look-up of a student finds what the screens show, even for records still under the old manual id', () async {
      await db.collection('litAssessments').add({
        'studentUid': _manual, 'studentName': 'Mananjit', 'assessedAt': Timestamp.fromDate(DateTime(2026, 10, 18, 9)),
        'L': 3, 'I': 4, 'T': 2, 'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male',
      });
      await db.collection('associations').add({
        'studentUid': _manual, 'studentName': 'Mananjit', 'status': 'confirmed', 'preferredDate': Timestamp.fromDate(DateTime(2026, 10, 27, 18)),
        'confirmedDate': Timestamp.fromDate(DateTime(2026, 10, 27, 18)), 'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male',
      });
      final env = envFor(_profile('G'));
      expect(((await listLit({'studentUid': _real}, env)).data as Map)['count'], 1);
      expect(((await listMeetings({'studentUid': _real}, env)).data as Map)['count'], 1);
      final overview = (await getStudent({'studentUid': _real}, env)).data as Map;
      expect(jsonEncode(overview).contains('"interactions'), isTrue, reason: 'the overview still builds');
      // and a student with nothing of their own (Arjun) does not borrow someone else's
      expect(((await listLit({'studentUid': 'u_arjun_k'}, env)).data as Map)['count'], 0);
      expect(((await listMeetings({'studentUid': 'u_arjun_k'}, env)).data as Map)['count'], 0);
    });

    test('upcoming / overdue split at today', () async {
      final env = envFor(_profile('G'));
      final up = (await listFollowups({'when': 'upcoming'}, env)).data as Map;
      final over = (await listFollowups({'when': 'overdue'}, env)).data as Map;
      expect(up['count'], 3, reason: '25 Oct x2 and 3 Nov');
      expect(over['count'], 1, reason: '22 Oct');
    });

    test('nothing scheduled is said plainly, with a note', () async {
      final env = envFor(_profile('M1', role: 'MALE_ENABLER', team: 'G'));
      final d = (await listFollowups({'when': 'overdue'}, env)).data as Map;
      expect(d['count'], 0);
      expect(d['note'], isNotNull);
    });
  });
}
