import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/actions/AssociationActions.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// Meetings with students, as one shared write.
///
/// `AssociationManager` and the AI agent both call `actions/AssociationActions`,
/// so a meeting the agent sets up is the same document, the same notification
/// and the same student-visible wording as one a guide sets up by hand. These
/// pin those shapes — they were read off the screen's own code before it moved
/// — and the one new thing, Reschedule, which the app did not have.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  late FakeFirebaseFirestore db;
  late List<Map<String, dynamic>> pushes;

  setUp(() {
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    pushes = [];
    HierarchyApi.useForTests((name, args) async {
      if (name == 'sendStudentNotification') pushes.add(args);
      return <String, dynamic>{};
    });
  });
  tearDown(() {
    GuideDb.useForTests(null);
    HierarchyApi.useForTests(null);
  });

  final when = DateTime(2026, 11, 3, 17, 30); // 5:30 PM

  Future<String> seed({String status = 'confirmed', Map<String, dynamic>? extra}) async {
    final ref = await db.collection('associations').add({
      'studentUid': 's1',
      'studentName': 'Arjun Kumar',
      'guideId': 'G',
      'status': status,
      'preferredDate': Timestamp.fromDate(DateTime(2026, 11, 1, 10)),
      'confirmedDate': status == 'confirmed' ? Timestamp.fromDate(DateTime(2026, 11, 2, 9)) : null,
      'studentNotes': '',
      ...?extra,
    });
    return ref.id;
  }

  Future<Map<String, dynamic>> read(String id) async =>
      (await db.collection('associations').doc(id).get()).data()!;

  // -------------------------------------------------------------------------
  group('requesting a meeting', () {
    test('writes the document the screen always wrote', () async {
      final id = await requestMeeting(
        guideId: 'G',
        studentUid: 's1',
        studentName: 'Arjun Kumar',
        preferred: when,
        message: '  Let us talk about exams  ',
      );
      final d = await read(id);
      expect(d['studentUid'], 's1');
      expect(d['studentName'], 'Arjun Kumar');
      expect(d['guideId'], 'G');
      expect(d['requestedBy'], 'guide');
      expect(d['status'], 'pending', reason: 'until the student confirms');
      expect(d['confirmedDate'], isNull);
      expect((d['preferredDate'] as Timestamp).toDate(), when);
      expect(d['studentNotes'], 'Let us talk about exams', reason: 'trimmed');
      expect(d.containsKey('guideNotes'), isFalse, reason: 'no guide note on the record the student reads');
      expect(d['createdAt'], isNotNull);
      expect(d['updatedAt'], isNotNull);
    });

    test('tells the student, in the words the screen always used', () async {
      await requestMeeting(
          guideId: 'G', studentUid: 's1', studentName: 'Arjun Kumar', preferred: when);
      expect(pushes.single, {
        'kind': 'association_update',
        'studentUid': 's1',
        'title': 'Meeting Scheduled',
        'body': 'Your guide has requested a meeting on 03 Nov 2026, 05:30 PM',
      });
    });

    test('a failed notification never undoes the meeting', () async {
      HierarchyApi.useForTests((n, a) async => throw HierarchyException('unavailable', 'x'));
      final id = await requestMeeting(
          guideId: 'G', studentUid: 's1', studentName: 'Arjun Kumar', preferred: when);
      expect((await read(id))['status'], 'pending');
    });
  });

  // -------------------------------------------------------------------------
  group('answering a request', () {
    test('Confirm fixes the time and tells the student', () async {
      final id = await seed(status: 'pending');
      await confirmMeeting(id, studentUid: 's1', when: when);
      final d = await read(id);
      expect(d['status'], 'confirmed');
      expect((d['confirmedDate'] as Timestamp).toDate(), when);
      expect(pushes.single['title'], 'Meeting Confirmed');
      expect(pushes.single['body'], 'Your meeting is confirmed for 03 Nov 2026, 05:30 PM');
    });

    test("Accept Student's Date takes their proposal as it stands", () async {
      final proposed = Timestamp.fromDate(DateTime(2026, 11, 5, 8));
      final id = await seed(status: 'pending', extra: {
        'isCounterProposal': true,
        'counterProposalDate': proposed,
      });
      await acceptStudentProposal(id, studentUid: 's1', proposed: proposed);
      final d = await read(id);
      expect(d['status'], 'confirmed');
      expect(d['confirmedDate'], proposed);
      expect(pushes.single['body'], 'Your meeting is confirmed for 05 Nov 2026, 08:00 AM');
    });

    test('Cancel says so to the student', () async {
      final id = await seed();
      await cancelMeeting(id, studentUid: 's1');
      expect((await read(id))['status'], 'cancelled');
      expect(pushes.single['title'], 'Meeting Cancelled');
      expect(pushes.single['body'], 'Your meeting request was cancelled');
    });

    test('Mark Complete records the notes, trimmed, and notifies nobody', () async {
      final id = await seed();
      await completeMeeting(id, notes: '  We agreed a smaller target.  ');
      final d = await read(id);
      expect(d['status'], 'completed');
      expect(d.containsKey('guideNotes'), isFalse, reason: 'the student reads this record: no guide note on it');
      final note = (await db.collection('associationGuideNotes').doc(id).get()).data()!;
      expect(note['notes'], 'We agreed a smaller target.', reason: 'the guide-only place, trimmed');
      expect([note['studentUid'], note['studentName']], ['s1', 'Arjun Kumar']);
      expect(pushes, isEmpty, reason: 'completing was never announced to the student');
    });
  });

  // -------------------------------------------------------------------------
  group('rescheduling', () {
    test('moves a confirmed meeting and tells the student', () async {
      final id = await seed();
      await rescheduleMeeting(id, studentUid: 's1', when: when);
      final d = await read(id);
      expect(d['status'], 'confirmed', reason: 'still a confirmed meeting, at a new time');
      expect((d['confirmedDate'] as Timestamp).toDate(), when);
      expect(pushes.single['title'], 'Meeting Rescheduled');
      expect(pushes.single['body'], 'Your meeting has been moved to 03 Nov 2026, 05:30 PM');
    });

    test('changes nothing else about the meeting', () async {
      final id = await seed(extra: {'studentNotes': 'keep me'});
      final before = await read(id);
      await rescheduleMeeting(id, studentUid: 's1', when: when);
      final after = await read(id);
      for (final k in ['studentUid', 'studentName', 'guideId', 'studentNotes', 'preferredDate']) {
        expect(after[k], before[k], reason: k);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('a held meeting counts as an interaction; a cancelled confirmed one is deleted', () {
    test('Completed with a signed-in guide also saves the interaction record of the meeting (no AI), the notes still guide-only', () async {
      AdminProfileProvider.instance.debugSet(adminProfile(Who.guide));
      addTearDown(() => AdminProfileProvider.instance.debugSet(null));
      final id = await seed();
      await completeMeeting(id, notes: 'We agreed a smaller target.');
      final logs = (await db.collection('interactionLogs').get()).docs;
      expect(logs.length, 1);
      final d = logs.single.data();
      expect([d['studentUid'], d['source'], d['analysis'], d['status'], d['addressed'], d['rawDictation']], ['s1', 'meeting', 'done', 'approved', true, 'We agreed a smaller target.']);
      expect(d.containsKey('preAnalysis'), isFalse, reason: 'no AI');
      expect((await read(id))['status'], 'completed');
    });

    test('Cancelled on a confirmed meeting DELETES it completely (and its guide note) and tells the student', () async {
      final id = await seed();
      await db.collection('associationGuideNotes').doc(id).set({'notes': 'x', 'studentUid': 's1'});
      await cancelAndDeleteMeeting(id, studentUid: 's1');
      expect((await db.collection('associations').doc(id).get()).exists, isFalse);
      expect((await db.collection('associationGuideNotes').doc(id).get()).exists, isFalse);
      expect(pushes.single['title'], 'Meeting Cancelled');
      expect(pushes.single['body'], 'Your meeting request was cancelled');
    });
  });
}
