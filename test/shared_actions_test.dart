import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/actions/BookActions.dart';
import 'package:folk_guide_app/actions/BookLinkActions.dart';
import 'package:folk_guide_app/actions/CommentActions.dart';
import 'package:folk_guide_app/actions/CompetitionActions.dart';
import 'package:folk_guide_app/actions/FlaggedActions.dart';
import 'package:folk_guide_app/actions/LitActions.dart';
import 'package:folk_guide_app/actions/PriorityActions.dart';
import 'package:folk_guide_app/actions/StudentActions.dart';
import 'package:folk_guide_app/actions/SubmissionActions.dart';
import 'package:folk_guide_app/actions/TripActions.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';

import 'support/app_harness.dart';

/// The writes the Guide screens and the AI agent share.
///
/// Each of these moved out of a screen into `lib/actions/` so the agent calls the
/// SAME code the screen does — never a copy. These pin what each one writes (read off
/// the screen's own code before it moved), what it refuses, and what it tells people.

void main() {
  late FakeFirebaseFirestore db;
  late List<({String name, Map<String, dynamic> args})> calls;
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? respond;

  setUp(() {
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    AdminProfileProvider.instance.debugSet(adminProfile(Who.hod));
    calls = [];
    respond = null;
    HierarchyApi.useForTests((name, args) async {
      calls.add((name: name, args: args));
      if (respond != null) return respond!(name, args);
      if (name == 'sendStudentNotification') return {'sent': 1, 'total': 1};
      if (name == 'checkMobileTaken') return {'taken': false};
      return <String, dynamic>{};
    });
  });
  tearDown(() {
    GuideDb.useForTests(null);
    HierarchyApi.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  Future<Map<String, dynamic>?> doc(String path) async =>
      (await db.doc(path).get()).data();

  Iterable<Map<String, dynamic>> pushes([String? kind]) => calls
      .where((c) => c.name == 'sendStudentNotification')
      .map((c) => c.args)
      .where((a) => kind == null || a['kind'] == kind);

  // ---------------------------------------------------------------------------
  group('books', () {
    Future<bool> assign({String uid = 's1'}) => assignBook(
          guideId: 'G',
          studentUid: uid,
          level: 'level1',
          bookKey: 'gita',
          title: 'Bhagavad Gita',
          commitment: DateTime(2026, 11, 30),
        );

    test('assigning writes the open book and tells the student', () async {
      expect(await assign(), isTrue);
      final d = (await doc('booksRead/${bookDocId('s1', 'level1', 'gita')}'))!;
      expect(d['isCurrentBook'], isTrue);
      expect(d['commitmentDate'], '2026-11-30');
      expect(d['commitmentSetBy'], 'guide');
      expect(d['bookTitle'], 'Bhagavad Gita');
      expect(pushes('book_assigned').single['studentUid'], 's1');
    });

    test('a finished book is never reassigned, and nobody is told', () async {
      await markBookFinished(
          studentUid: 's1', level: 'level1', bookKey: 'gita', title: 'Gita', hasStarted: true);
      expect(await assign(), isFalse);
      expect(pushes('book_assigned'), isEmpty);
      expect((await doc('booksRead/${bookDocId('s1', 'level1', 'gita')}'))!['isCurrentBook'], isFalse);
    });

    test('finishing stamps today; a book never started gets today as its start too', () async {
      await markBookFinished(
          studentUid: 's2', level: 'level1', bookKey: 'gita', title: 'Gita', hasStarted: false);
      final d = (await doc('booksRead/${bookDocId('s2', 'level1', 'gita')}'))!;
      expect(d['endedBy'], 'guide');
      expect(d['endDate'], isNotEmpty);
      expect(d['startDate'], d['endDate']);
    });

    test('un-finishing clears the end markers and keeps the rest', () async {
      await markBookFinished(
          studentUid: 's2', level: 'level1', bookKey: 'gita', title: 'Gita', hasStarted: true);
      await markBookNotFinished(
          studentUid: 's2', level: 'level1', bookKey: 'gita', title: 'Gita');
      final d = (await doc('booksRead/${bookDocId('s2', 'level1', 'gita')}'))!;
      expect(d.containsKey('endDate'), isFalse);
      expect(d.containsKey('endedBy'), isFalse);
      expect(d['bookTitle'], 'Gita');
    });

    test('a failed push never undoes the assignment', () async {
      respond = (n, a) async => throw StateError('offline');
      expect(await assign(), isTrue);
      expect(await doc('booksRead/${bookDocId('s1', 'level1', 'gita')}'), isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('LIT assessment', () {
    Future<String> save({Map<String, int?>? scores, String evidence = 'Asked good questions'}) =>
        saveLitAssessment(
          studentUid: 's1',
          studentName: 'Arjun',
          guideId: 'G',
          scores: scores ?? {'L': 4, 'I': 3, 'T': 2},
          evidence: evidence,
          confidence: 'medium',
        );

    test('writes the three axes separately, never a sum', () async {
      final id = await save();
      final d = (await doc('litAssessments/$id'))!;
      expect([d['L'], d['I'], d['T']], [4, 3, 2]);
      expect(d.keys, isNot(contains('total')));
      expect(d['evidence'], 'Asked good questions');
    });

    test('refuses an unset axis, an out-of-range score and empty evidence — writing nothing', () async {
      for (final bad in [
        () => save(scores: {'L': 4, 'I': null, 'T': 2}),
        () => save(scores: {'L': 6, 'I': 3, 'T': 2}),
        () => save(evidence: '   '),
      ]) {
        await expectLater(bad(), throwsArgumentError);
      }
      expect((await db.collection('litAssessments').get()).docs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('comments', () {
    test('a comment is trimmed and stamped with who wrote it', () async {
      final id = await postStudentComment(
        studentUid: 's1',
        text: '  Doing well  ',
        authorId: 'G',
        authorName: 'Gopal Das',
        authorIsHod: false,
      );
      final d = (await doc('$kStudentCommentsCollection/s1/messages/$id'))!;
      expect(d['text'], 'Doing well');
      expect(d['authorRole'], 'guide');
    });

    test('empty and over-long comments are refused', () async {
      for (final text in ['   ', 'x' * (kMaxCommentChars + 1)]) {
        await expectLater(
          postStudentComment(
              studentUid: 's1', text: text, authorId: 'G', authorName: 'G', authorIsHod: true),
          throwsArgumentError,
        );
      }
      expect((await db.collection(kStudentCommentsCollection).doc('s1').collection('messages').get()).docs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('book links', () {
    test('English lives in {level}_links, other languages beside it', () {
      expect(bookLinksDocId('level1', 'en'), 'level1_links');
      expect(bookLinksDocId('level1', 'hi'), 'level1_links_hi');
    });

    test('a Dropbox share link is normalised and merged without touching the others', () async {
      await db.doc('books/level1_links').set({'other': 'keep'});
      final saved = await setBookLink(
          level: 'level1', bookKey: 'gita', url: 'https://www.dropbox.com/s/abc/gita.pdf?dl=0');
      expect(saved, contains('dl=1'));
      final d = (await doc('books/level1_links'))!;
      expect(d['gita'], saved);
      expect(d['other'], 'keep');
    });

    test('an unknown language is refused', () async {
      await expectLater(
          setBookLink(level: 'level1', bookKey: 'gita', url: 'https://x.org/a', language: 'fr'),
          throwsArgumentError);
    });
  });

  // ---------------------------------------------------------------------------
  group('student details', () {
    test('commitments are merged — nothing else on the student is lost', () async {
      await db.doc('users/s1').set({'name': 'Arjun', 'newerField': 7});
      await setStudentCommitments('s1', rounds: 20, readingMinutes: 45);
      final d = (await doc('users/s1'))!;
      expect(d['commitmentRounds'], 20);
      expect(d['readingCommitmentMinutes'], 45);
      expect(d['newerField'], 7);
    });

    test('nonsense commitments are refused and nothing is written', () async {
      await db.doc('users/s1').set({'name': 'Arjun'});
      for (final bad in [
        () => setStudentCommitments('s1', rounds: 0, readingMinutes: 10),
        () => setStudentCommitments('s1', rounds: 16, readingMinutes: -1),
        () => setStudentCommitments('s1', rounds: 16, readingMinutes: kMaxReadingMinutes + 1),
      ]) {
        await expectLater(bad(), throwsArgumentError);
      }
      expect((await doc('users/s1'))!.keys, ['name']);
    });

    test('a notification preference changes one key and leaves the others', () async {
      await db.doc('users/s1').set({
        'notificationPrefs': {'a': true, 'b': true},
      });
      await setStudentNotificationPref('s1', 'a', false);
      expect((await doc('users/s1'))!['notificationPrefs'], {'a': false, 'b': true});
    });

    test('residence must be one of the three; date of birth is stored as a date', () async {
      await setStudentResidence('s1', 'Stay at Hostel');
      expect((await doc('users/s1'))!['role'], 'Stay at Hostel');
      await expectLater(setStudentResidence('s1', 'Moon base'), throwsArgumentError);
      await setStudentDob('s1', DateTime(2004, 5, 17));
      expect(((await doc('users/s1'))!['dob'] as Timestamp).toDate(), DateTime(2004, 5, 17));
    });

    group('adding a student', () {
      Future<String> add({String name = ' arjun   kumar ', String mobile = '98765 43210', String gender = 'male'}) =>
          addManualStudent(
            name: name,
            mobile: mobile,
            residence: 'Stay at FOLK',
            gender: gender,
            addedBy: 'G',
            guideId: 'G',
            rounds: 16,
          );

      test('writes the normalised name and number, marked as a manual entry', () async {
        final id = await add();
        final d = (await doc('users/$id'))!;
        expect(d['name'], 'arjun kumar', reason: 'trimmed and single-spaced');
        expect(d['mobileNumber'], isNot(contains(' ')));
        expect(d['isManualEntry'], isTrue);
        expect(d['addedByGuideId'], 'G');
        expect(d['guideId'], 'G');
        expect(d['commitmentRounds'], 16);
      });

      test('a mobile that already belongs to someone is refused outright', () async {
        respond = (n, a) async =>
            n == 'checkMobileTaken' ? {'taken': true, 'name': 'Bhima Sen'} : {};
        await expectLater(
          add(),
          throwsA(isA<DuplicateMobileException>()
              .having((e) => e.toString(), 'message', contains('Bhima Sen'))),
        );
        expect((await db.collection('users').get()).docs, isEmpty);
      });

      test('bad input writes nothing', () async {
        for (final bad in [
          () => add(name: '   '),
          () => add(mobile: '123'),
          () => add(gender: 'other'),
        ]) {
          await expectLater(bad(), throwsArgumentError);
        }
        expect((await db.collection('users').get()).docs, isEmpty);
      });
    });
  });

  // ---------------------------------------------------------------------------
  group('chanting competitions', () {
    Future<CreatedChallenge> create({DateTime? end, Set<String> guides = const {}}) =>
        createChantingChallenge(
          name: ' Diwali push ',
          targetRounds: 5000,
          start: DateTime(2026, 11, 1),
          end: end ?? DateTime(2026, 11, 5),
          selectedGuideIds: guides,
        );

    test('a range is stored with its last day as the old single date, and students are told once', () async {
      final made = await create();
      final d = (await doc('chantingChallenges/${made.id}'))!;
      expect(d['name'], 'Diwali push');
      expect(d['startDateKey'], '01-11-2026');
      expect(d['endDateKey'], '05-11-2026');
      expect(d['targetDateKey'], '05-11-2026', reason: 'old readers keep working');
      expect(d['status'], 'active');
      expect(d['currentTotal'], 0);
      expect(d['allStudents'], isTrue, reason: 'a HOD who picks no guide means everyone');
      expect(made.sent, 1);
      expect(made.notifyFailed, isFalse);
      final p = pushes('chanting_challenge').single;
      expect(p['startDate'], '2026-11-01');
      expect(p['targetDate'], '2026-11-05');
    });

    test('a HOD who picks guides limits it to their rosters', () async {
      final made = await create(guides: {'G'});
      final d = (await doc('chantingChallenges/${made.id}'))!;
      expect(d['guideIds'], ['G']);
      expect(d.containsKey('allStudents'), isFalse);
      expect(pushes('chanting_challenge').single['ownerIds'], ['G']);
    });

    test('a Guide gets his own roster and his Male Enablers, never everyone', () async {
      AdminProfileProvider.instance.debugSet(adminProfile(Who.guide));
      final made = await create();
      final d = (await doc('chantingChallenges/${made.id}'))!;
      expect(d['guideIds'], ['G', 'M1']);
      expect(d.containsKey('allStudents'), isFalse);
      expect(pushes('chanting_challenge').single.containsKey('ownerIds'), isFalse);
    });

    test('a failed push keeps the competition and says so', () async {
      respond = (n, a) async => throw StateError('offline');
      final made = await create();
      expect(made.notifyFailed, isTrue);
      expect(await doc('chantingChallenges/${made.id}'), isNotNull);
    });

    test('an end before the start, or a blank name, is refused before anything is written', () async {
      await expectLater(create(end: DateTime(2026, 10, 1)), throwsArgumentError);
      await expectLater(
        createChantingChallenge(name: ' ', targetRounds: 10, start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 2)),
        throwsArgumentError,
      );
      expect((await db.collection('chantingChallenges').get()).docs, isEmpty);
      expect(pushes(), isEmpty);
    });

    test('closing records when; reopening clears it', () async {
      final made = await create();
      await setChallengeStatus(made.id, 'missed');
      var d = (await doc('chantingChallenges/${made.id}'))!;
      expect(d['status'], 'missed');
      expect(d['closedAt'], isNotNull);
      await setChallengeStatus(made.id, 'active');
      d = (await doc('chantingChallenges/${made.id}'))!;
      expect(d['status'], 'active');
      expect(d.containsKey('closedAt'), isFalse);
      await expectLater(setChallengeStatus(made.id, 'achieved'), throwsArgumentError);
    });

    test('deleting takes the competition and every contribution to it, and only that one', () async {
      final made = await create();
      final other = await create();
      await db.collection('chantingChallengeContributions').doc('a').set({'challengeId': made.id});
      await db.collection('chantingChallengeContributions').doc('b').set({'challengeId': made.id});
      await db.collection('chantingChallengeContributions').doc('c').set({'challengeId': other.id});
      await deleteChantingChallenge(made.id);
      expect(await doc('chantingChallenges/${made.id}'), isNull);
      expect((await db.collection('chantingChallengeContributions').get()).docs.map((d) => d.id), ['c']);
      expect(await doc('chantingChallenges/${other.id}'), isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('trips', () {
    Future<String> create({String gender = 'male', DateTime? end}) => createTrip(
          createdBy: 'G',
          title: ' Govardhan parikrama ',
          start: DateTime(2026, 12, 5),
          end: end ?? DateTime(2026, 12, 6),
          targetGender: gender,
          location: 'Vrindavan',
          maxParticipants: 30,
        );

    test('a trip keeps its start as tripDate and carries an end date', () async {
      final id = await create();
      final d = (await doc('expeditions/$id'))!;
      expect(d['title'], 'Govardhan parikrama');
      expect(((d['tripDate'] as Timestamp).toDate()), DateTime(2026, 12, 5));
      expect(((d['endDate'] as Timestamp).toDate()), DateTime(2026, 12, 6));
      expect(d['status'], 'upcoming');
      expect(d['archived'], isFalse);
      expect(d['targetGender'], 'male');
      expect(d['maxParticipants'], 30);
    });

    test('bad input writes nothing', () async {
      await expectLater(create(gender: 'both'), throwsArgumentError);
      await expectLater(create(end: DateTime(2026, 12, 1)), throwsArgumentError);
      await expectLater(
          createTrip(createdBy: 'G', title: ' ', start: DateTime(2026, 12, 5), end: DateTime(2026, 12, 5), targetGender: 'male'),
          throwsArgumentError);
      expect((await db.collection('expeditions').get()).docs, isEmpty);
    });

    test('status moves through the three states only', () async {
      final id = await create();
      await setTripStatus(id, 'ongoing');
      expect((await doc('expeditions/$id'))!['status'], 'ongoing');
      await expectLater(setTripStatus(id, 'cancelled'), throwsArgumentError);
    });

    test('attendance accepts only the known values', () async {
      await db.doc('expeditionRegistrations/t1_s1').set({'attendance': 'pending'});
      await setTripAttendance('t1_s1', 'full');
      expect((await doc('expeditionRegistrations/t1_s1'))!['attendance'], 'full');
      await expectLater(setTripAttendance('t1_s1', 'whenever'), throwsArgumentError);
    });
  });

  // ---------------------------------------------------------------------------
  group('flagged messages', () {
    test('marking reviewed changes that one field only', () async {
      await db.doc('flaggedChatMessages/m1').set({'text': 'hello', 'reviewed': false});
      await markFlaggedReviewed('m1', true);
      expect(await doc('flaggedChatMessages/m1'), {'text': 'hello', 'reviewed': true});
      await markFlaggedReviewed('m1', false);
      expect((await doc('flaggedChatMessages/m1'))!['reviewed'], isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('submission reminders', () {
    test('one student goes as studentUid, several as a list', () async {
      await sendSubmissionReminders(['a']);
      await sendSubmissionReminders(['a', 'b']);
      final p = pushes('submission_nudge').toList();
      expect(p[0]['studentUid'], 'a');
      expect(p[1]['studentUids'], ['a', 'b']);
    });

    test('450 students go in chunks of 200 and the delivered counts add up', () async {
      respond = (n, a) async => {'sent': (a['studentUids'] as List).length - 1};
      final progress = <(int, int)>[];
      final sent = await sendSubmissionReminders(
        [for (var i = 0; i < 450; i++) 'u$i'],
        onProgress: (d, s) => progress.add((d, s)),
      );
      expect(pushes('submission_nudge').map((a) => (a['studentUids'] as List).length), [200, 200, 50]);
      expect(sent, 199 + 199 + 49);
      expect(progress.last, (450, sent));
    });

    test('a failed chunk counts zero and the rest still go', () async {
      var n = 0;
      respond = (name, a) async {
        if (n++ == 0) throw StateError('offline');
        return {'sent': 200};
      };
      final sent = await sendSubmissionReminders([for (var i = 0; i < 400; i++) 'u$i']);
      expect(sent, 200);
      expect(pushes('submission_nudge').length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  group('priority list', () {
    PriorityStudent student(String uid, List<String> kinds) => (
          uid: uid,
          name: 'Student $uid',
          flags: [for (final k in kinds) (kind: k, label: k, tone: PriorityTone.warning)],
        );

    test('removing remembers the kinds shown, one record per student, under this admin', () async {
      await removeFromPriority([student('s1', ['stale_contact', 'no_report']), student('s2', ['never_logged'])]);
      final a = (await doc('priorityDismissals/H__s1'))!;
      expect(a['adminId'], 'H');
      expect(a['studentUid'], 's1');
      expect(a['kinds'], ['stale_contact', 'no_report']);
      expect(a['dismissedAt'], isNotNull);
      expect((await doc('priorityDismissals/H__s2'))!['kinds'], ['never_logged']);
      expect(await readPriorityDismissals('H'), {
        's1': {'stale_contact', 'no_report'},
        's2': {'never_logged'},
      });
    });

    test("restoring deletes only the named students' records, and never anyone else's", () async {
      await removeFromPriority([student('s1', ['a']), student('s2', ['b'])]);
      await db.doc('priorityDismissals/G__s1').set({'adminId': 'G', 'studentUid': 's1', 'kinds': ['a']});
      await restoreToPriority(['s1']);
      expect(await doc('priorityDismissals/H__s1'), isNull);
      expect(await doc('priorityDismissals/H__s2'), isNotNull);
      expect(await doc('priorityDismissals/G__s1'), isNotNull, reason: 'another admin\'s list is theirs');
    });

    test('removing nobody writes nothing', () async {
      await removeFromPriority(const []);
      expect((await db.collection('priorityDismissals').get()).docs, isEmpty);
    });
  });
}
