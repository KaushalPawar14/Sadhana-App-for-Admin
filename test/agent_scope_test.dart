import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentReads.dart';
import 'package:folk_guide_app/agent/AgentTypes.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';

/// The agent sees exactly what the guide sees: nothing more, and not a hint of anyone else.
///
///   HOD              all students
///   Guide G          own + team (his Male Enablers') + unassigned boys
///   Male Enabler M1  own + unassigned boys
///   Female Enabler   own + unassigned girls
///
/// Every read is asked, as every role, about students that exist only outside that role's scope —
/// including a name ("Ravi") that exists ONLY outside it, "list everybody", counts, and filters
/// that sweep the whole roster. Nothing outside the scope may appear anywhere in what the model is
/// told: not a name, not an id, not a count, not "there is another Ravi you can't see".

const kNotYours = "I can't find that student among your students.";

class _S {
  const _S(this.uid, this.name, this.gender, this.guide, this.team);
  final String uid;
  final String name;
  final String gender;
  final String guide;
  final String team;
}

const _students = [
  _S('u_arjun_k', 'Arjun Kumar', 'male', 'G', 'G'),
  _S('u_arjun_p', 'Arjun Patel', 'male', 'G', 'G'),
  _S('u_bhima', 'Bhima Sen', 'male', 'M1', 'G'),
  _S('u_ravi_o', 'Ravi Other', 'male', 'G2', 'G2'),
  _S('u_dhruva', 'Dhruva Nair', 'male', '', ''),
  _S('u_gauri', 'Gauri Devi', 'female', 'F1', ''),
  _S('u_radha', 'Radha Unassigned', 'female', '', ''),
  _S('u_ravi_k', 'Ravi Kumari', 'female', 'F1', ''),
];

/// Who may see whom, by role (the rules of the app, spelled out once more for the test).
const _visible = {
  'H': {'u_arjun_k', 'u_arjun_p', 'u_bhima', 'u_ravi_o', 'u_dhruva', 'u_gauri', 'u_radha', 'u_ravi_k'},
  'G': {'u_arjun_k', 'u_arjun_p', 'u_bhima', 'u_dhruva'},
  'M1': {'u_bhima', 'u_dhruva'},
  'F1': {'u_gauri', 'u_radha', 'u_ravi_k'},
};

AdminProfile _profile(String id) {
  final role = {'H': 'HOD', 'G': 'GUIDE', 'G2': 'GUIDE', 'M1': 'MALE_ENABLER', 'F1': 'FEMALE_ENABLER'}[id]!;
  return AdminProfile.fromMap({
    'id': id,
    'displayName': 'Admin $id',
    'role': role,
    'teamGuide': id == 'M1' ? 'G' : '',
    'email': '$id@x.org',
    'notificationPrefs': {},
    'notificationTypes': [],
    'admins': [
      {'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': ''},
      {'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': ''},
      {'id': 'G2', 'displayName': 'Govinda Das', 'role': 'GUIDE', 'teamGuide': ''},
      {'id': 'M1', 'displayName': 'Madhava Das', 'role': 'MALE_ENABLER', 'teamGuide': 'G'},
      {'id': 'F1', 'displayName': 'Radha Devi', 'role': 'FEMALE_ENABLER', 'teamGuide': ''},
    ],
  });
}

Future<void> _seed(FakeFirebaseFirestore db) async {
  Map<String, Object?> stamp(_S s) => {'scopeGuide': s.guide, 'scopeTeam': s.team, 'scopeGender': s.gender};
  final when = Timestamp.fromDate(DateTime(2026, 10, 20, 18));

  for (final s in _students) {
    await db.collection('users').doc(s.uid).set({
      'name': s.name, 'gender': s.gender, 'guideId': s.guide, 'teamGuide': s.team,
      'role': 'Stay at FOLK', 'commitmentRounds': 16,
    });
    await db.collection('associations').add({
      'studentUid': s.uid, 'studentName': s.name, 'status': 'pending', 'requestedBy': 'student',
      'preferredDate': when, 'studentNotes': 'Message from ${s.name}', ...stamp(s),
    });
    await db.collection('interactionLogs').add({
      'studentUid': s.uid, 'studentName': s.name, 'status': 'approved', 'interactionType': 'Call',
      'interactionDate': when, 'rawDictation': 'Spoke with ${s.name}', ...stamp(s),
    });
    await db.collection('booksRead').doc('${s.uid}_level-1_book_1').set({
      'uid': s.uid, 'level': 'level-1', 'bookKey': 'book_1', 'bookTitle': 'Gita for ${s.name}', 'isCurrentBook': true, ...stamp(s),
    });
    await db.collection('bookDoubts').add({
      'uid': s.uid, 'studentName': s.name, 'mode': 'guide', 'question': 'A question from ${s.name}', 'bookTitle': 'Gita',
      'status': 'open', 'askedAt': when, ...stamp(s),
    });
    await db.collection('flaggedChatMessages').add({
      'studentUid': s.uid, 'studentName': s.name, 'text': 'Worried message from ${s.name}', 'reviewed': false, 'createdAt': when, ...stamp(s),
    });
    await db.collection('serviceAssignments').add({
      'studentUid': s.uid, 'serviceNumber': 1, 'assignedByGuideId': 'G', 'status': 'assigned', ...stamp(s),
    });
    await db.collection('expeditionRegistrations').doc('t1_${s.uid}').set({
      'tripId': 't1', 'studentUid': s.uid, 'studentName': s.name, 'attendance': 'pending', ...stamp(s),
    });
    await db.collection('sadhana-reports').doc(s.name).collection('dates').doc('20-10-2026').set({
      'chantRounds': 16, 'bookReading': 30, ...stamp(s),
    });
  }

  await db.collection('expeditions').doc('t1').set({
    'title': 'Vrindavan trip', 'tripDate': when, 'endDate': when, 'status': 'upcoming', 'createdBy': 'G', 'targetGender': 'male', 'archived': false,
  });
  await db.collection('expeditions').doc('t2').set({
    'title': 'Other guide trip', 'tripDate': when, 'endDate': when, 'status': 'upcoming', 'createdBy': 'G2', 'targetGender': 'male', 'archived': false,
  });

  // A board of G's that holds a student G does not see: only the student he sees may be named.
  await db.collection('boards').doc('b1').set({'kind': 'custom', 'ownerGuideId': 'G', 'title': 'My board', 'sharedWith': ['M1']});
  await db.collection('boards').doc('b1').collection('columns').doc('c1').set({'title': 'To meet', 'order': 0, 'colorValue': 0xFF000000, 'kind': 'normal'});
  for (final uid in ['u_arjun_k', 'u_ravi_o', 'u_gauri']) {
    await db.collection('boards').doc('b1').collection('placements').doc(uid).set({'columnId': 'c1', 'order': 0});
  }
}

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    await _seed(db);
    HierarchyApi.useForTests((name, args) async {
      if (name == 'listAdmins') {
        return {
          'admins': [
            for (final a in _profile('H').admins) {'id': a.id, 'displayName': a.displayName, 'role': a.role.wire, 'teamGuide': a.teamGuide},
          ]
        };
      }
      return <String, dynamic>{};
    });
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

  String wire(AgentResult r) => jsonEncode({'ok': r.ok, 'data': r.data, 'error': r.error, 'entities': [for (final e in r.entities) e.toMap()]});

  Set<String> namesOf(Set<String> uids) => {for (final s in _students) if (uids.contains(s.uid)) s.name};

  /// Every name and id the guide may NOT see, and the first names that exist only outside the scope.
  ({List<String> forbidden, List<String> firstNames}) hidden(String role) {
    final outside = {for (final s in _students) s.uid}.difference(_visible[role]!);
    final out = [for (final s in _students) if (outside.contains(s.uid)) s];
    final seenInside = namesOf(_visible[role]!).expand((n) => n.split(' ')).toSet();
    return (
      forbidden: [for (final s in out) ...[s.name, s.uid]],
      firstNames: [for (final s in out) s.name.split(' ').first].where((f) => !seenInside.contains(f)).toSet().toList(),
    );
  }

  const roles = ['H', 'G', 'M1', 'F1'];

  for (final role in roles) {
    group('as $role', () {
      test('"list all students" returns exactly this role\'s students, and the count is theirs', () async {
        final env = envFor(role);
        final r = await findStudents({}, env);
        final got = {for (final s in (r.data as Map)['students'] as List) (s as Map)['name'] as String};
        expect(got, namesOf(_visible[role]!));
        expect((r.data as Map)['count'], _visible[role]!.length, reason: 'the count never includes anyone outside');
        expect({for (final e in r.entities) e.id}, _visible[role]);
      });

      test('a name that exists only outside the scope is simply not there — no count, no hint', () async {
        final env = envFor(role);
        final h = hidden(role);
        for (final first in h.firstNames) {
          final r = await findStudents({'query': first}, env);
          final d = r.data as Map;
          expect(d['count'], 0, reason: first);
          expect(d['students'], isEmpty);
          expect(d.containsKey('note'), isFalse, reason: 'no "several match" note when nothing visible matches');
          expect(r.entities, isEmpty);
          final json = wire(r);
          for (final f in h.forbidden) {
            expect(json.contains(f), isFalse, reason: '"$f" leaked into a search for $first');
          }
        }
      });

      test('a name shared by someone inside and someone outside finds only the one inside', () async {
        final env = envFor(role);
        final r = await findStudents({'query': 'ravi'}, env);
        final names = {for (final s in (r.data as Map)['students'] as List) (s as Map)['name'] as String};
        expect(names, namesOf(_visible[role]!).where((n) => n.toLowerCase().contains('ravi')).toSet());
      });

      test('an out-of-scope student is refused with the same sentence as one that does not exist', () async {
        final env = envFor(role);
        final outside = [for (final s in _students) if (!_visible[role]!.contains(s.uid)) s.uid];
        final tools = <String, AgentRun>{
          for (final t in const ['get_student', 'get_student_reports', 'list_interactions', 'list_meetings', 'list_books', 'list_services', 'list_music'])
            t: kAgentReads[t]!,
        };
        for (final uid in [...outside, 'u_no_such_student']) {
          for (final e in tools.entries) {
            Object? error;
            try {
              final r = await e.value({'studentUid': uid}, env);
              error = r.ok ? 'returned data' : r.error;
            } on AgentFailure catch (f) {
              error = f.message;
            }
            expect(error, kNotYours, reason: '${e.key} for $uid');
          }
        }
      });

      test('every read, swept, never mentions anyone outside the scope', () async {
        final env = envFor(role);
        final h = hidden(role);
        final results = <String, AgentResult>{};
        final noArgs = const [
          'list_meetings', 'list_books', 'list_targets', 'list_competitions', 'list_trips', 'list_priority', 'list_doubts',
          'list_flagged', 'list_calendar', 'list_submissions', 'list_services', 'list_music', 'list_boards',
        ];
        for (final t in noArgs) {
          results[t] = await kAgentReads[t]!({}, env);
        }
        for (final f in const ['any', 'priority', 'missed_reports', 'no_recent_meeting', 'no_recent_interaction', 'no_book', 'unassigned']) {
          results['find:$f'] = await findStudents({'filter': f, 'days': 1}, env);
        }
        results['trip registrations'] = await listTrips({'tripId': 't1'}, env);
        for (final uid in _visible[role]!) {
          results['get_student $uid'] = await getStudent({'studentUid': uid}, env);
          results['reports $uid'] = await getStudentReports({'studentUid': uid}, env);
          results['interactions $uid'] = await listInteractions({'studentUid': uid}, env);
        }
        for (final e in results.entries) {
          expect(e.value.ok, isTrue, reason: '${e.key}: ${e.value.error}');
          final json = wire(e.value);
          for (final f in h.forbidden) {
            expect(json.contains(f), isFalse, reason: '"$f" appeared in ${e.key}');
          }
        }
      });

      test('what each list returns is limited to this role (doubts, flagged messages, meetings, services, registrations)', () async {
        final env = envFor(role);
        final inside = namesOf(_visible[role]!);

        final doubts = await listDoubts({}, env);
        expect({for (final d in (doubts.data as Map)['doubts'] as List) (d as Map)['student']}, inside);

        final flagged = await listFlagged({}, env);
        expect({for (final m in (flagged.data as Map)['messages'] as List) (m as Map)['student']}, inside);

        final meetings = await listMeetings({}, env);
        expect({for (final m in (meetings.data as Map)['meetings'] as List) (m as Map)['student']}, inside);

        final services = await listServices({}, env);
        expect({for (final m in (services.data as Map)['assignments'] as List) (m as Map)['student']}, inside);

        final trip = await listTrips({'tripId': 't1'}, env);
        final regs = [for (final t in (trip.data as Map)['trips'] as List) ...((t as Map)['registrations'] as List? ?? const [])];
        expect({for (final r in regs) (r as Map)['student']}, inside.isEmpty ? <Object?>{} : {for (final s in inside) s}.intersection({for (final r in regs) (r as Map)['student'] as String}));
      });

      test('a board that holds an outsider names only the students this role may see', () async {
        final env = envFor(role);
        final r = await listBoards({}, env);
        final boards = (r.data as Map)['boards'] as List;
        final named = {for (final b in boards) for (final c in (b as Map)['columns'] as List) ...((c as Map)['students'] as List).cast<String>()};
        expect(named.difference(namesOf(_visible[role]!)), isEmpty);
      });

      test('the priority list is this role\'s students only', () async {
        final env = envFor(role);
        final r = await listPriority({}, env);
        final named = {for (final s in (r.data as Map)['students'] as List) (s as Map)['name'] as String};
        expect(named.difference(namesOf(_visible[role]!)), isEmpty);
        expect((r.data as Map)['count'], lessThanOrEqualTo(_visible[role]!.length));
      });

      test('"who has not submitted today" counts only this role\'s students', () async {
        final env = envFor(role);
        final r = await listSubmissions({}, env);
        expect((r.data as Map)['inScope'], _visible[role]!.length);
        final named = {...(((r.data as Map)['notSubmitted']) as List).cast<String>()};
        expect(named.difference(namesOf(_visible[role]!)), isEmpty);
      });
    });
  }

  group('across roles', () {
    test('a Guide and a Male Enabler asking about girls get nothing; a Female Enabler asking about boys gets nothing', () async {
      for (final (role, others) in [
        ('G', ['Gauri', 'Radha', 'Kumari']),
        ('M1', ['Gauri', 'Radha', 'Kumari']),
        ('F1', ['Arjun', 'Bhima', 'Dhruva', 'Ravi Other']),
      ]) {
        final env = envFor(role);
        for (final q in others) {
          final r = await findStudents({'query': q}, env);
          expect((r.data as Map)['count'], 0, reason: '$role asked about $q');
        }
      }
    });

    test('unassigned students show only to the matching gender, and to the HOD', () async {
      final unassigned = {
        for (final role in roles)
          role: {for (final s in ((await findStudents({'filter': 'unassigned'}, envFor(role))).data as Map)['students'] as List) (s as Map)['name'] as String},
      };
      expect(unassigned['H'], {'Dhruva Nair', 'Radha Unassigned'});
      expect(unassigned['G'], {'Dhruva Nair'});
      expect(unassigned['M1'], {'Dhruva Nair'});
      expect(unassigned['F1'], {'Radha Unassigned'});
    });

    test('a student refused for one role is found by the role that may see them', () async {
      expect((await getStudent({'studentUid': 'u_ravi_o'}, envFor('H'))).ok, isTrue);
      await expectLater(getStudent({'studentUid': 'u_ravi_o'}, envFor('G')), throwsA(isA<AgentFailure>()));
      expect((await getStudent({'studentUid': 'u_gauri'}, envFor('F1'))).ok, isTrue);
      await expectLater(getStudent({'studentUid': 'u_gauri'}, envFor('G')), throwsA(isA<AgentFailure>()));
    });

    test('an ambiguous name inside the scope is flagged for the model to ask about', () async {
      final r = await findStudents({'query': 'arjun'}, envFor('G'));
      expect((r.data as Map)['count'], 2);
      expect((r.data as Map)['note'], contains('Ask the guide which one'));
      final one = await findStudents({'query': 'arjun kumar'}, envFor('G'));
      expect((one.data as Map)['count'], 1);
      expect((one.data as Map).containsKey('note'), isFalse);
    });

    test('the roster is read once per minute and re-read after a change', () async {
      final env = envFor('G');
      final a = await env.students();
      await db.collection('users').doc('u_new').set({'name': 'New Boy', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at FOLK'});
      expect((await env.students()).containsKey('u_new'), isFalse, reason: 'cached');
      env.invalidate();
      expect((await env.students()).containsKey('u_new'), isTrue);
      expect(identical(a, await env.students()), isFalse);
    });
  });
}
