import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

// The new-changes count against the real data shape: `planChanges/{admin}/items` (what the server records) and `seenMarkers/{admin}.planNew` (the moment he last
// left the Plan page): only an admin's own records, only the ones newer than the cursor, and a fresh count after he has left.

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    SeenMarkers.debugDisable = false;
  });
  tearDown(() {
    GuideDb.useForTests(null);
    SeenMarkers.debugDisable = true;
  });

  Future<void> record(String admin, String key, String text, DateTime at, {String uid = '', String type = 'doubt'}) =>
      db.collection('planChanges').doc(admin).collection('items').doc(key).set({'type': type, 'text': text, 'at': Timestamp.fromDate(at), 'adminId': admin, if (uid.isNotEmpty) 'studentUid': uid});

  test('the count is the admin\'s own records newer than the moment he last left the page; another admin\'s are not his', () async {
    final now = DateTime.now();
    await record('G', 'a', 'New doubt: Testing', now.subtract(const Duration(minutes: 5)), uid: 'u1');
    await record('G', 'b', 'Book finished: Ayush', now.subtract(const Duration(minutes: 1)), uid: 'u2', type: 'book');
    await record('G2', 'c', 'New doubt: Someone else', now.subtract(const Duration(minutes: 1)));
    const data = FirestorePlanData();
    var c = await data.newChanges('G').first;
    expect(c.count, 2, reason: 'never left: the last 24 hours; G2\'s is not his');
    expect(c.items.map((x) => x.text), ['Book finished: Ayush', 'New doubt: Testing'], reason: 'newest first');
    expect(c.isNewFor(studentUid: 'u1'), isTrue);
    // he leaves the page (a moment later than the newest record): nothing is new any more
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await data.markPlanSeen('G');
    c = await data.newChanges('G').first;
    expect(c.count, 0, reason: 'seen: the badge is cleared');
    // something happens after that: a fresh count of one
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await record('G', 'd', 'New worry: Ravi', DateTime.now().add(const Duration(seconds: 1)), uid: 'u3', type: 'concern');
    c = await data.newChanges('G').first;
    expect(c.count, 1);
    expect(c.items.single.text, 'New worry: Ravi');
    // another admin's cursor is his own
    expect((await data.newChanges('G2').first).count, 1);
  });
}
