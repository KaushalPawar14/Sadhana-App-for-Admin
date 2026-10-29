import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/actions/BookActions.dart';
import 'package:folk_guide_app/agent/AgentDuplicates.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentReads.dart';
import 'package:folk_guide_app/agent/AgentWrites.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The assistant can CORRECT and REMOVE what a guide manages: a follow-up, comments, LIT assessments, a book assignment,
/// the AI suggestions, a competition, a trip, the notes on a meeting — and find near-identical records ("delete the
/// duplicate"). Each runs the shared function the app uses, only on a student in the guide's own scope, and never touches
/// what a student submitted.

AdminProfile _profile(String role) {
  final hod = role == 'HOD';
  return AdminProfile.fromMap({
    'id': hod ? 'H' : 'G', 'displayName': hod ? 'Harinam Das' : 'Gopal Das', 'role': role, 'teamGuide': '', 'email': 'x@x.org',
    'notificationPrefs': {}, 'notificationTypes': <Object>[],
    'admins': [
      {'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': ''},
      {'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': ''},
      {'id': 'G2', 'displayName': 'Govinda Das', 'role': 'GUIDE', 'teamGuide': ''},
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore db;
  final stamp = {'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'};
  final other = {'scopeGuide': 'G2', 'scopeTeam': 'G2', 'scopeGender': 'male'};
  final day = Timestamp.fromDate(DateTime(2026, 11, 3));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    AdminProfileProvider.instance.debugSet(_profile('GUIDE'));
    HierarchyApi.useForTests((name, args) async => <String, dynamic>{});
    await db.collection('users').doc('u1').set({'name': 'Bhima Sen', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at FOLK'});
    await db.collection('users').doc('u2').set({'name': 'Other Boy', 'gender': 'male', 'guideId': 'G2', 'teamGuide': 'G2', 'role': 'Stay at FOLK'});
  });
  tearDown(() {
    GuideDb.useForTests(null);
    HierarchyApi.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  AgentEnv env([String role = 'GUIDE']) => AgentEnv(profile: _profile(role), db: db, clock: () => DateTime(2026, 10, 23, 12));
  Future<Map<String, dynamic>?> doc(String path) async => (await db.doc(path).get()).data();

  Future<void> interaction(String id, {String uid = 'u1', Timestamp? followUp, String action = 'Call him', String notes = 'We spoke about his japa', Map<String, dynamic>? scope, DateTime? when}) =>
      db.collection('interactionLogs').doc(id).set({
        'studentUid': uid, 'studentName': 'Bhima Sen', 'interactionDate': Timestamp.fromDate(when ?? DateTime(2026, 10, 20, 18)), 'interactionType': 'Call',
        'rawDictation': notes, 'status': 'approved',
        'approvedSummary': {'interactionType': 'Call', 'recommendedNextAction': action, if (followUp != null) 'followUpDate': followUp},
        ...(scope ?? stamp),
      });

  // ------------------------------------------------------------------------------------------ follow-ups
  group('removing a follow-up', () {
    test('clears only the follow-up date: the interaction, its notes and its next action stay', () async {
      await interaction('i1', followUp: day);
      final r = await kAgentWritesA['interaction_followup_remove']!({'interactionIds': ['i1']}, env());
      expect(r.ok, isTrue);
      final d = (await doc('interactionLogs/i1'))!;
      expect((d['approvedSummary'] as Map).containsKey('followUpDate'), isFalse);
      expect((d['approvedSummary'] as Map)['recommendedNextAction'], 'Call him');
      expect(d['rawDictation'], 'We spoke about his japa');
      expect(d['status'], 'approved');
    });

    test('an interaction with no follow-up is refused, in words', () async {
      await interaction('i1');
      await expectLater(kAgentWritesA['interaction_followup_remove']!({'interactionIds': ['i1']}, env()), throwsA(isA<AgentFailure>()));
    });

    test('an interaction of a student outside the guide\'s scope is refused and untouched', () async {
      await interaction('i2', uid: 'u2', followUp: day, scope: other);
      await expectLater(kAgentWritesA['interaction_followup_remove']!({'interactionIds': ['i2']}, env()), throwsA(isA<AgentFailure>()));
      expect(((await doc('interactionLogs/i2'))!['approvedSummary'] as Map).containsKey('followUpDate'), isTrue);
    });
  });

  // ------------------------------------------------------------------------------------------ comments
  group('comments', () {
    setUp(() async {
      await db.collection('studentComments').doc('u1').collection('messages').doc('m1').set({'text': 'Ask about japa', 'authorId': 'G', 'authorName': 'Gopal Das', 'createdAt': day});
      await db.collection('studentComments').doc('u1').collection('messages').doc('m2').set({'text': 'Ask about japa', 'authorId': 'H', 'authorName': 'Harinam Das', 'createdAt': day});
    });

    test('a guide edits and deletes their own comment', () async {
      final e = await kAgentWritesA['student_comment_edit']!({'commentId': 'u1/m1', 'text': 'Ask about reading'}, env());
      expect(e.ok, isTrue);
      expect((await doc('studentComments/u1/messages/m1'))!['text'], 'Ask about reading');
      expect((await doc('studentComments/u1/messages/m1'))!['editedAt'], isNotNull);
      final d = await kAgentWritesA['student_comment_delete']!({'commentIds': ['u1/m1']}, env());
      expect(d.ok, isTrue);
      expect(await doc('studentComments/u1/messages/m1'), isNull);
    });

    test("a guide cannot change someone else's comment, a HOD can", () async {
      await expectLater(kAgentWritesA['student_comment_edit']!({'commentId': 'u1/m2', 'text': 'x'}, env()), throwsA(isA<AgentFailure>()));
      await expectLater(kAgentWritesA['student_comment_delete']!({'commentIds': ['u1/m2']}, env()), throwsA(isA<AgentFailure>()));
      expect((await doc('studentComments/u1/messages/m2')), isNotNull);
      AdminProfileProvider.instance.debugSet(_profile('HOD'));
      final r = await kAgentWritesA['student_comment_delete']!({'commentIds': ['u1/m2']}, env('HOD'));
      expect(r.ok, isTrue);
      expect(await doc('studentComments/u1/messages/m2'), isNull);
    });

    test('a comment on a student outside the scope is refused', () async {
      await db.collection('studentComments').doc('u2').collection('messages').doc('m9').set({'text': 'hidden', 'authorId': 'G', 'authorName': 'Gopal Das', 'createdAt': day});
      await expectLater(kAgentWritesA['student_comment_edit']!({'commentId': 'u2/m9', 'text': 'x'}, env()), throwsA(isA<AgentFailure>()));
      expect((await doc('studentComments/u2/messages/m9'))!['text'], 'hidden');
    });

    test('a bad id is refused', () async {
      await expectLater(kAgentWritesA['student_comment_edit']!({'commentId': 'nonsense', 'text': 'x'}, env()), throwsA(isA<AgentFailure>()));
    });
  });

  // ------------------------------------------------------------------------------------------ LIT
  group('LIT assessments', () {
    setUp(() => db.collection('litAssessments').doc('l1').set({
          'studentUid': 'u1', 'studentName': 'Bhima Sen', 'guideId': 'G', 'L': 3, 'I': 4, 'T': 2, 'evidence': 'Asked many questions', 'confidence': 'medium', ...stamp,
        }));

    test('edit changes only what is given; the three readings stay separate', () async {
      final r = await kAgentWritesA['lit_edit']!({'assessmentId': 'l1', 'L': 5}, env());
      expect(r.ok, isTrue);
      final d = (await doc('litAssessments/l1'))!;
      expect([d['L'], d['I'], d['T']], [5, 4, 2]);
      expect(d['evidence'], 'Asked many questions');
      expect(d.containsKey('total'), isFalse);
    });

    test('an edit that breaks the rules (a score out of 1-5) is refused', () async {
      await expectLater(kAgentWritesA['lit_edit']!({'assessmentId': 'l1', 'T': 9}, env()), throwsA(anything));
      expect((await doc('litAssessments/l1'))!['T'], 2);
    });

    test('delete removes it; a student outside the scope is refused', () async {
      await db.collection('litAssessments').doc('l2').set({'studentUid': 'u2', 'studentName': 'Other Boy', 'guideId': 'G2', 'L': 1, 'I': 1, 'T': 1, 'evidence': 'x', 'confidence': 'low', ...other});
      await expectLater(kAgentWritesA['lit_delete']!({'assessmentIds': ['l2']}, env()), throwsA(isA<AgentFailure>()));
      expect(await doc('litAssessments/l2'), isNotNull);
      final r = await kAgentWritesA['lit_delete']!({'assessmentIds': ['l1']}, env());
      expect(r.ok, isTrue);
      expect(await doc('litAssessments/l1'), isNull);
    });
  });

  // ------------------------------------------------------------------------------------------ books, suggestions
  group('book assignment and AI suggestions', () {
    test("taking back a guide's assignment removes the commitment; the student's own reading is untouched", () async {
      await db.collection('booksRead').doc('u1_level-1_book_1').set({
        'uid': 'u1', 'level': 'level-1', 'bookKey': 'book_1', 'bookTitle': 'Bhagavad-gita', 'isCurrentBook': true, 'startDate': '2026-10-01',
        'commitmentDate': '2026-12-15', 'commitmentSetBy': 'guide', 'commitmentSetAt': day, 'pagesRead': 40, ...stamp,
      });
      final book = await db.collection('booksRead').doc('u1_level-1_book_1').get();
      expect(book.exists, isTrue);
      // the executor resolves the book through the app's book config, which the test phone does not have: its shared function is pinned directly
      final ok = await _unassign('u1', 'level-1', 'book_1');
      expect(ok, isTrue);
      final d = (await doc('booksRead/u1_level-1_book_1'))!;
      expect(d.containsKey('commitmentDate'), isFalse);
      expect(d['isCurrentBook'], isFalse);
      expect(d['pagesRead'], 40, reason: "the student's own progress stays");
    });

    test('a finished book, or one the student chose themselves, is never touched', () async {
      await db.collection('booksRead').doc('u1_level-1_book_2').set({'uid': 'u1', 'level': 'level-1', 'bookKey': 'book_2', 'endDate': '2026-10-10', 'commitmentDate': '2026-10-09', 'commitmentSetBy': 'guide', ...stamp});
      await db.collection('booksRead').doc('u1_level-1_book_3').set({'uid': 'u1', 'level': 'level-1', 'bookKey': 'book_3', 'isCurrentBook': true, ...stamp});
      expect(await _unassign('u1', 'level-1', 'book_2'), isFalse);
      expect(await _unassign('u1', 'level-1', 'book_3'), isFalse);
      expect((await doc('booksRead/u1_level-1_book_2'))!['commitmentDate'], '2026-10-09');
      expect((await doc('booksRead/u1_level-1_book_3'))!['isCurrentBook'], isTrue);
    });

    test('deleting the AI suggestions removes only that document, for a student in scope', () async {
      await db.collection('holisticSuggestions').doc('u1').set({'studentUid': 'u1', 'suggestions': [{'action': 'x', 'why': 'y', 'next': 'z'}], ...stamp});
      final r = await kAgentWritesA['suggestions_delete']!({'studentUid': 'u1'}, env());
      expect(r.ok, isTrue);
      expect(await doc('holisticSuggestions/u1'), isNull);
      await expectLater(kAgentWritesA['suggestions_delete']!({'studentUid': 'u2'}, env()), throwsA(isA<AgentFailure>()));
    });
  });

  // ------------------------------------------------------------------------------------------ competitions, trips, meetings
  group('competitions, trips and meeting notes', () {
    test('a competition can be renamed, retargeted and its last day changed; a span over 31 days is refused', () async {
      await db.collection('chantingChallenges').doc('c1').set({
        'name': 'Diwali Push', 'targetRounds': 1000, 'guideId': 'G', 'status': 'active',
        'startDate': Timestamp.fromDate(DateTime(2026, 10, 25)), 'endDate': Timestamp.fromDate(DateTime(2026, 10, 30)),
      });
      final r = await kAgentWritesA['competition_edit']!({'challengeId': 'c1', 'name': 'Diwali Super Push', 'targetRounds': 2000, 'endDate': '2026-11-02'}, env());
      expect(r.ok, isTrue);
      final d = (await doc('chantingChallenges/c1'))!;
      expect(d['name'], 'Diwali Super Push');
      expect(d['targetRounds'], 2000);
      expect((d['endDate'] as Timestamp).toDate(), DateTime(2026, 11, 2));
      expect((d['targetDate'] as Timestamp).toDate(), DateTime(2026, 11, 2), reason: 'the older reader field moves with it');
      await expectLater(kAgentWritesA['competition_edit']!({'challengeId': 'c1', 'endDate': '2026-12-25'}, env()), throwsA(anything));
      expect((await doc('chantingChallenges/c1'))!['name'], 'Diwali Super Push');
    });

    test('a trip can be edited; dates in the wrong order are refused', () async {
      await db.collection('expeditions').doc('t1').set({
        'title': 'Mayapur', 'tripDate': Timestamp.fromDate(DateTime(2026, 12, 5)), 'endDate': Timestamp.fromDate(DateTime(2026, 12, 6)),
        'createdBy': 'G', 'targetGender': 'male', 'archived': false, 'status': 'upcoming',
      });
      final r = await kAgentWritesA['trip_edit']!({'tripId': 't1', 'title': 'Mayapur Dham', 'location': 'West Bengal', 'maxParticipants': 30}, env());
      expect(r.ok, isTrue);
      final d = (await doc('expeditions/t1'))!;
      expect([d['title'], d['location'], d['maxParticipants']], ['Mayapur Dham', 'West Bengal', 30]);
      expect((d['tripDate'] as Timestamp).toDate(), DateTime(2026, 12, 5), reason: 'untouched');
      await expectLater(kAgentWritesA['trip_edit']!({'tripId': 't1', 'endDate': '2026-12-01'}, env()), throwsA(anything));
    });

    test('the notes on a completed meeting can be changed; a meeting not completed has none to change', () async {
      await db.collection('associations').doc('a1').set({'studentUid': 'u1', 'studentName': 'Bhima Sen', 'status': 'completed', 'guideNotes': 'Old notes', ...stamp});
      await db.collection('associations').doc('a2').set({'studentUid': 'u1', 'studentName': 'Bhima Sen', 'status': 'confirmed', ...stamp});
      final r = await kAgentWritesA['meeting_notes_edit']!({'associationId': 'a1', 'notes': 'Better notes'}, env());
      expect(r.ok, isTrue);
      expect((await doc('associations/a1'))!['guideNotes'], 'Better notes');
      await expectLater(kAgentWritesA['meeting_notes_edit']!({'associationId': 'a2', 'notes': 'x'}, env()), throwsA(isA<AgentFailure>()));
    });
  });

  // ------------------------------------------------------------------------------------------ duplicates
  group('finding duplicates', () {
    test('two near-identical follow-ups on the same day are found side by side; a different one is not', () async {
      await interaction('f1', followUp: day, action: 'Call Bhima about his Gita reading', when: DateTime(2026, 10, 20, 18));
      await interaction('f2', followUp: day, action: 'Call Bhima about Gita reading', when: DateTime(2026, 10, 20, 18, 30));
      await interaction('f3', followUp: Timestamp.fromDate(DateTime(2026, 11, 20)), action: 'Arrange the Mayapur trip');
      final r = await kAgentReads['find_duplicates']!({'studentUid': 'u1', 'kind': 'follow_up'}, env());
      expect(r.ok, isTrue);
      final data = r.data as Map;
      expect(data['groupsFound'], 1);
      final group = (data['groups'] as List).single as List;
      expect(group.map((x) => (x as Map)['id']).toSet(), {'f1', 'f2'});
      expect((group.first as Map)['followUp'], isNotNull);
      expect((group.first as Map)['nextAction'], contains('Bhima'));
      expect(r.entities.where((e) => e.kind == 'interaction').map((e) => e.id).toSet(), {'f1', 'f2'}, reason: 'the ids the model may then act on');
      expect(r.entities.any((e) => e.id == 'f3'), isFalse);
    });

    test('identical comments are found; the same words by different authors are not duplicates', () async {
      final c = db.collection('studentComments').doc('u1').collection('messages');
      await c.doc('a').set({'text': 'Ask about japa this week', 'authorId': 'G', 'authorName': 'Gopal Das', 'createdAt': day});
      await c.doc('b').set({'text': 'Ask about japa this week', 'authorId': 'G', 'authorName': 'Gopal Das', 'createdAt': day});
      await c.doc('c').set({'text': 'Ask about japa this week', 'authorId': 'H', 'authorName': 'Harinam Das', 'createdAt': day});
      final r = await kAgentReads['find_duplicates']!({'studentUid': 'u1', 'kind': 'comment'}, env());
      final groups = (r.data as Map)['groups'] as List;
      expect(groups.length, 1);
      expect((groups.single as List).map((x) => (x as Map)['id']).toSet(), {'u1/a', 'u1/b'});
    });

    test('nothing similar says so; a student outside the scope is refused', () async {
      await interaction('only');
      final r = await kAgentReads['find_duplicates']!({'studentUid': 'u1', 'kind': 'interaction'}, env());
      expect((r.data as Map)['groupsFound'], 0);
      expect((r.data as Map)['note'], isNotNull);
      await expectLater(kAgentReads['find_duplicates']!({'studentUid': 'u2', 'kind': 'interaction'}, env()), throwsA(isA<AgentFailure>()));
    });

    test('the reads for comments and LIT hand over ids and stay in scope', () async {
      await db.collection('studentComments').doc('u1').collection('messages').doc('m1').set({'text': 'Hello', 'authorId': 'G', 'authorName': 'Gopal Das', 'createdAt': day});
      final c = await kAgentReads['list_comments']!({'studentUid': 'u1'}, env());
      expect(((c.data as Map)['comments'] as List).single['id'], 'u1/m1');
      expect(((c.data as Map)['comments'] as List).single['yours'], isTrue);
      expect(c.entities.any((e) => e.kind == 'comment' && e.id == 'u1/m1'), isTrue);
      await expectLater(kAgentReads['list_comments']!({'studentUid': 'u2'}, env()), throwsA(isA<AgentFailure>()));
      await db.collection('litAssessments').doc('l1').set({'studentUid': 'u1', 'studentName': 'Bhima Sen', 'guideId': 'G', 'L': 3, 'I': 4, 'T': 2, 'evidence': 'e', 'confidence': 'low', 'assessedAt': day, ...stamp});
      final l = await kAgentReads['list_lit']!({'studentUid': 'u1'}, env());
      expect(((l.data as Map)['assessments'] as List).single['availableTime'], 2);
      expect(l.entities.any((e) => e.kind == 'lit' && e.id == 'l1'), isTrue);
    });
  });

  group('the similarity rules', () {
    test('words in common, case and punctuation ignored', () {
      expect(textSimilarity('Call Bhima about his Gita reading!', 'call bhima about GITA reading'), greaterThan(0.6));
      expect(textSimilarity('Call Bhima about his Gita reading', 'Arrange the Mayapur trip'), lessThan(0.2));
      expect(textSimilarity('', ''), 1);
      expect(textSimilarity('hello there', ''), 0);
    });

    test('grouping needs the same type, a close time and similar words', () {
      final a = DupItem(id: 'a', when: DateTime(2026, 10, 20, 9), type: 'Call', text: 'call about japa rounds');
      final b = DupItem(id: 'b', when: DateTime(2026, 10, 20, 17), type: 'Call', text: 'call about japa rounds');
      final c = DupItem(id: 'c', when: DateTime(2026, 10, 20, 17), type: 'WhatsApp', text: 'call about japa rounds');
      final d = DupItem(id: 'd', when: DateTime(2026, 10, 25), type: 'Call', text: 'call about japa rounds');
      final groups = findDuplicateGroups([a, b, c, d]);
      expect(groups.length, 1);
      expect(groups.single.map((x) => x.id).toSet(), {'a', 'b'});
      expect(findDuplicateGroups([a, d], days: 10).length, 1, reason: 'a wider window groups them');
    });
  });
}

/// `unassignBook` is the shared function; the executor adds only the book lookup from the app's book list.
Future<bool> _unassign(String uid, String level, String key) => unassignBook(studentUid: uid, level: level, bookKey: key);
