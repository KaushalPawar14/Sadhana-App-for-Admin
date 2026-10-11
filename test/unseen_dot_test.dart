import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';

/// What the Home "FOLK Boys Board" dot counts, role by role:
///   - a book commitment set by a guide that this admin has not seen, for a student on
///     THIS admin's board (a student with no name has no card; a student outside the
///     scope cannot be opened);
///   - a comment on a student's thread written by SOMEONE ELSE and not yet seen.
/// An admin's own actions never count, and opening the item clears it.

AdminProfile profile(String id, String role, {String team = ''}) => AdminProfile.fromMap({
      'id': id,
      'displayName': '$id Das',
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

final t0 = Timestamp.fromDate(DateTime(2026, 9, 1));
final t1 = Timestamp.fromDate(DateTime(2026, 9, 2));
final t2 = Timestamp.fromDate(DateTime(2026, 9, 3));

Future<FakeFirebaseFirestore> world() async {
  final db = FakeFirebaseFirestore();
  Future<void> user(String uid, String name, String guide, String team, String gender) =>
      db.collection('users').doc(uid).set({'name': name, 'guideId': guide, 'teamGuide': team, 'gender': gender, 'role': 'Stay at FOLK'});
  await user('s1', 'Arjun', 'G', 'G', 'male'); // G's own
  await user('s2', 'Bhima', 'M1', 'G', 'male'); // a Male Enabler of G's team
  await user('s3', 'Chaitanya', '', '', 'male'); // unassigned male
  await user('s4', 'Dhruva', 'G2', 'G2', 'male'); // another team
  await user('s5', 'Gauri', '', '', 'female'); // unassigned female
  await user('s6', '', 'G', 'G', 'male'); // no name: the board has no card for it

  Future<void> commitment(String uid, String guide, String team, String gender, {Timestamp? at}) =>
      db.collection('booksRead').doc('${uid}_level-1_book_1').set({
        'uid': uid,
        'commitmentSetBy': 'guide',
        'commitmentSetAt': at ?? t1,
        'scopeGuide': guide,
        'scopeTeam': team,
        'scopeGender': gender,
      });
  await commitment('s1', 'G', 'G', 'male');
  await commitment('s2', 'M1', 'G', 'male');
  await commitment('s3', '', '', 'male');
  await commitment('s4', 'G2', 'G2', 'male');
  await commitment('s5', '', '', 'female');
  await commitment('s6', 'G', 'G', 'male'); // no card
  await commitment('ghost', 'G', 'G', 'male'); // a student that no longer exists
  return db;
}

Future<Set<String>> unseenCommitments(String viewer) => UnseenAggregates.bookCommitmentUnseenUids(viewer).firstWhere((_) => true);

void main() {
  tearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  Future<void> as(FakeFirebaseFirestore db, AdminProfile p) async {
    GuideDb.useForTests(db);
    AdminProfileProvider.instance.debugSet(p);
  }

  group('book commitments: only students on this admin\'s board', () {
    test('HOD: everyone with a card - not a nameless user, not a student that no longer exists', () async {
      final db = await world();
      await as(db, profile('H', 'HOD'));
      expect(await unseenCommitments('H'), {'s1', 's2', 's3', 's4', 's5'});
    });

    test('Guide G: his team and the unassigned males - never another team or the girls', () async {
      final db = await world();
      await as(db, profile('G', 'GUIDE'));
      expect(await unseenCommitments('G'), {'s1', 's2', 's3'});
    });

    test('Male Enabler M1: own students and the unassigned males', () async {
      final db = await world();
      await as(db, profile('M1', 'MALE_ENABLER', team: 'G'));
      expect(await unseenCommitments('M1'), {'s2', 's3'});
    });

    test('Female Enabler F1: the unassigned girls', () async {
      final db = await world();
      await as(db, profile('F1', 'FEMALE_ENABLER'));
      expect(await unseenCommitments('F1'), {'s5'});
    });
  });

  group('it clears once seen, and only for that student', () {
    test('opening one student\'s card clears that student only', () async {
      final db = await world();
      await as(db, profile('H', 'HOD'));
      await db.collection('seenMarkers').doc('H').set({
        'bookCommitments': {'s1': t2},
      });
      expect(await unseenCommitments('H'), {'s2', 's3', 's4', 's5'});
    });

    test('a newer commitment after the cursor shows again', () async {
      final db = await world();
      await as(db, profile('H', 'HOD'));
      await db.collection('seenMarkers').doc('H').set({
        'bookCommitments': {'s1': t2, 's2': t2, 's3': t2, 's4': t2, 's5': t2},
      });
      await db.collection('booksRead').doc('s1_level-2_book_1').set({
        'uid': 's1',
        'commitmentSetBy': 'guide',
        'commitmentSetAt': t2,
        'scopeGuide': 'G',
        'scopeTeam': 'G',
        'scopeGender': 'male',
      });
      expect(await unseenCommitments('H'), isEmpty, reason: 'same time as the cursor is not newer');
      await db.collection('booksRead').doc('s1_level-3_book_1').set({
        'uid': 's1',
        'commitmentSetBy': 'guide',
        'commitmentSetAt': Timestamp.fromDate(DateTime(2026, 9, 9)),
        'scopeGuide': 'G',
        'scopeTeam': 'G',
        'scopeGender': 'male',
      });
      expect(await unseenCommitments('H'), {'s1'});
    });

    test('everything seen: the Home tile dot is off', () async {
      final db = await world();
      await as(db, profile('H', 'HOD'));
      await db.collection('seenMarkers').doc('H').set({
        'bookCommitments': {for (final u in ['s1', 's2', 's3', 's4', 's5']) u: t2},
      });
      expect(await UnseenAggregates.bookCommitmentsRosterUnseen('H', true).firstWhere((_) => true), isFalse);
    });

    test('a student\'s commitment set by the student is not counted', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('s1').set({'name': 'Arjun', 'guideId': 'G', 'teamGuide': 'G', 'gender': 'male'});
      await db.collection('booksRead').doc('s1_level-1_book_1').set({
        'uid': 's1',
        'commitmentSetBy': 'student',
        'commitmentSetAt': t1,
        'scopeGuide': 'G',
        'scopeTeam': 'G',
        'scopeGender': 'male',
      });
      await as(db, profile('H', 'HOD'));
      expect(await unseenCommitments('H'), isEmpty);
    });
  });

  group('comments: only what someone else wrote, only for students on the board', () {
    Future<FakeFirebaseFirestore> withComments() async {
      final db = await world();
      Future<void> msg(String uid, String author, Timestamp at) =>
          db.collection('studentComments').doc(uid).collection('messages').add({
            'authorId': author,
            'authorRole': 'guide',
            'text': 'hello',
            'createdAt': at,
          });
      await msg('s1', 'H', t1); // written by the HOD himself
      await msg('s2', 'G', t1); // written by G
      await msg('s4', 'G2', t1); // another team's student
      return db;
    }

    Future<bool> dot(String viewer) =>
        UnseenAggregates.studentCommentsRosterUnseen(viewer, false).firstWhere((_) => true);

    test('HOD: his own comment does not count; G\'s comment does', () async {
      final db = await withComments();
      await as(db, profile('H', 'HOD'));
      expect(await dot('H'), isTrue);
      // seen once he opens s2's thread (and s4's)
      await db.collection('seenMarkers').doc('H').set({
        'studentComments': {'s2': t2, 's4': t2},
      });
      expect(await dot('H'), isFalse, reason: 's1 is his own comment');
    });

    test('only his own comments: no dot at all', () async {
      final db = FakeFirebaseFirestore();
      GuideDb.useForTests(db);
      await db.collection('users').doc('s1').set({'name': 'Arjun', 'guideId': 'G', 'teamGuide': 'G', 'gender': 'male'});
      await db.collection('studentComments').doc('s1').collection('messages').add({'authorId': 'H', 'createdAt': t1});
      await as(db, profile('H', 'HOD'));
      expect(await dot('H'), isFalse);
    });

    test('Guide G: sees G2\'s student? no - a comment on another team\'s student never counts', () async {
      final db = await withComments();
      await as(db, profile('G', 'GUIDE'));
      // s1 (HOD's comment) counts for G; s2 is G's own comment; s4 is not G's student
      expect(await dot('G'), isTrue);
      await db.collection('seenMarkers').doc('G').set({
        'studentComments': {'s1': t2},
      });
      expect(await dot('G'), isFalse, reason: 's2 is G\'s own, s4 is out of scope');
    });

    test('Female Enabler: comments on boys never count', () async {
      final db = await withComments();
      await as(db, profile('F1', 'FEMALE_ENABLER'));
      expect(await dot('F1'), isFalse);
    });
  });
}
