import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PriorityHub.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/UnseenDot.dart';
import 'package:folk_guide_app/utils/UnseenFeatureBadge.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// THE DOT TRAILS: a parent dot shows ONLY when a child has something genuinely new; the child with the new item shows its own dot; opening a child clears it, and the
// parent clears when no child dot is left. Nothing shows until the live value is known; the admin's own pending "seen" counts as seen (no flash).
//
// What was wrong: the Analysis tab's "Interactions needed" card was lit by THREE sources (new reasons, flagged messages, doubts) but the page behind it had a dot for only TWO (the
// row "Interactions needed" had none), and the Analysis tab itself left out the new reasons altogether while it included goal proposals that have no child in Analysis. So the card
// showed an orange dot nobody could follow, and it cleared only by opening the one row that had no dot.

final t1 = Timestamp.fromDate(DateTime(2026, 9, 2));
final t2 = Timestamp.fromDate(DateTime(2026, 9, 3));
final tSeen = Timestamp.fromDate(DateTime(2026, 9, 10));

AdminProfile guide() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

const stamp = {'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'};

Future<FakeFirebaseFirestore> world({bool needsNew = false, bool flaggedNew = false}) async {
  final db = FakeFirebaseFirestore();
  GuideDb.useForTests(db);
  AdminProfileProvider.instance.debugSet(guide());
  SeenMarkers.debugDisable = false;
  UnseenAggregates.debugDisable = false;
  await db.collection('users').doc('s1').set({'name': 'Ravi', 'guideId': 'G', 'teamGuide': 'G', 'gender': 'male', 'role': 'Stay at FOLK'});
  // the guide has opened Interactions needed and Flagged messages after everything old
  await db.collection('seenMarkers').doc('G').set({'priorityReasons': tSeen, 'flaggedMessages': tSeen});
  await db.collection('interactionNeeds').doc('s1').set({'studentUid': 's1', 'needs': [], 'changedAt': needsNew ? Timestamp.fromDate(DateTime(2026, 9, 20)) : t1, ...stamp});
  await db.collection('flaggedChatMessages').doc('f1').set({'studentUid': 's1', 'createdAt': flaggedNew ? Timestamp.fromDate(DateTime(2026, 9, 21)) : t2, 'reviewed': false, ...stamp});
  return db;
}

Future<bool> latest(Stream<bool> s) async => (await s.first.timeout(const Duration(seconds: 5)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
  });
  tearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
    SeenMarkers.debugDisable = true;
    UnseenAggregates.debugDisable = true;
  });

  group('THE TRAIL: Analysis -> Interactions needed -> its three rows', () {
    test('nothing new: no dot anywhere (the rows, the card, the tab)', () async {
      await world();
      expect(await latest(UnseenAggregates.priorityReasonsUnseen('G', false)), isFalse);
      expect(await latest(UnseenAggregates.flaggedMessagesUnseen('G', false)), isFalse);
      expect(await latest(UnseenAggregates.priorityTrail('G', false)), isFalse, reason: 'the card');
      expect(await latest(UnseenAggregates.analysisTrail('G', false, adminId: 'G')), isFalse, reason: 'the tab');
    });

    test('a NEW REASON: its own row is lit, the card and the Analysis TAB are lit (they were not: the tab left the new reasons out); the other rows are not', () async {
      await world(needsNew: true);
      expect(await latest(UnseenAggregates.priorityReasonsUnseen('G', false)), isTrue, reason: 'the row "Interactions needed"');
      expect(await latest(UnseenAggregates.flaggedMessagesUnseen('G', false)), isFalse);
      expect(await latest(UnseenAggregates.priorityTrail('G', false)), isTrue, reason: 'the card');
      expect(await latest(UnseenAggregates.analysisTrail('G', false, adminId: 'G')), isTrue, reason: 'the tab');
    });

    test('a NEW FLAGGED MESSAGE: only that row, the card and the tab', () async {
      await world(flaggedNew: true);
      expect(await latest(UnseenAggregates.priorityReasonsUnseen('G', false)), isFalse);
      expect(await latest(UnseenAggregates.flaggedMessagesUnseen('G', false)), isTrue);
      expect(await latest(UnseenAggregates.priorityTrail('G', false)), isTrue);
      expect(await latest(UnseenAggregates.analysisTrail('G', false, adminId: 'G')), isTrue);
    });

    test('OPENING A ROW clears that row; the card and the tab clear when no child dot is left (not before)', () async {
      await world(needsNew: true, flaggedNew: true);
      expect(await latest(UnseenAggregates.priorityTrail('G', false)), isTrue);
      await SeenMarkers.markSeen('G', 'priorityReasons'); // the guide opens "Interactions needed"
      expect(await latest(UnseenAggregates.priorityReasonsUnseen('G', false)), isFalse, reason: 'its row is clear');
      expect(await latest(UnseenAggregates.flaggedMessagesUnseen('G', false)), isTrue, reason: 'the other row still has its own dot');
      expect(await latest(UnseenAggregates.priorityTrail('G', false)), isTrue, reason: 'the card stays: a child dot remains');
      expect(await latest(UnseenAggregates.analysisTrail('G', false, adminId: 'G')), isTrue);
      await SeenMarkers.markSeen('G', 'flaggedMessages'); // then "Flagged messages"
      expect(await latest(UnseenAggregates.flaggedMessagesUnseen('G', false)), isFalse);
      expect(await latest(UnseenAggregates.priorityTrail('G', false)), isFalse, reason: 'no child dot left: the card is clear');
      expect(await latest(UnseenAggregates.analysisTrail('G', false, adminId: 'G')), isFalse, reason: 'and the tab');
    });

    test('A PARENT IS EXACTLY "ANY CHILD": every combination of the children', () async {
      for (final needs in [false, true]) {
        for (final flagged in [false, true]) {
          await world(needsNew: needs, flaggedNew: flagged);
          final children = [await latest(UnseenAggregates.priorityReasonsUnseen('G', false)), await latest(UnseenAggregates.flaggedMessagesUnseen('G', false)), await latest(UnseenAggregates.studentDoubtsUnseen('G', false))];
          expect(await latest(UnseenAggregates.priorityTrail('G', false)), children.any((c) => c), reason: 'needs=$needs flagged=$flagged');
        }
      }
    });

    test('NO FLASH: nothing is shown until both the activity and the seen cursor are live; his own pending "seen" never lights a dot', () async {
      final latestC = Stream<Timestamp?>.value(t2);
      final shown = <bool>[];
      // a pending write of his own seen-field reads as "seen everything"
      final seen = Stream<Timestamp?>.fromIterable([SeenMarkers.seenValue(null, pending: true), SeenMarkers.seenValue(tSeen, pending: false)]);
      final sub = SeenMarkers.unseenFrom(latestC, seen).listen(shown.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(shown, isNotEmpty);
      expect(shown.every((v) => !v), isTrue, reason: 'never lit, not even for a frame: $shown');
    });
  });

  group('THE PAGE: each row shows its own dot', () {
    Future<void> open(WidgetTester tester, FakeFirebaseFirestore db) async {
      await prepareApp(tester, seeded: false, who: Who.guide);
      GuideDb.useForTests(db);
      AdminProfileProvider.instance.debugSet(guide());
      SeenMarkers.debugDisable = false;
      UnseenAggregates.debugDisable = false;
      await pumpScreen(tester, const PriorityHubPage());
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await letDataArrive(tester, frames: 6);
      }
    }

    bool dot(WidgetTester tester, String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(UnseenDot)).evaluate().isNotEmpty;

    testWidgets('nothing new: no row has a dot', (tester) async {
      final db = await world();
      await open(tester, db);
      for (final k in ['needs-hub-dot', 'flagged-hub-dot', 'doubts-hub-dot']) expect(dot(tester, k), isFalse, reason: k);
    });

    testWidgets('a new reason: THE ROW "Interactions needed" has the dot, so the guide knows where to go; the others have none; it clears when seen', (tester) async {
      final db = await world(needsNew: true);
      await open(tester, db);
      expect(dot(tester, 'needs-hub-dot'), isTrue);
      expect(dot(tester, 'flagged-hub-dot'), isFalse);
      expect(dot(tester, 'doubts-hub-dot'), isFalse);
      await SeenMarkers.markSeen('G', 'priorityReasons');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await letDataArrive(tester, frames: 6);
      expect(dot(tester, 'needs-hub-dot'), isFalse, reason: 'cleared');
    });

    testWidgets('a new flagged message: only "Flagged messages" has the dot', (tester) async {
      final db = await world(flaggedNew: true);
      await open(tester, db);
      expect(dot(tester, 'flagged-hub-dot'), isTrue);
      expect(dot(tester, 'needs-hub-dot'), isFalse);
      expect(dot(tester, 'doubts-hub-dot'), isFalse);
    });
  });

  group('THE TARGETS: a proposal waiting has its child dots too', () {
    Future<FakeFirebaseFirestore> targetWorld({required bool seen}) async {
      final db = await world();
      await db.collection('guideTargets').doc('G').collection('targets').doc('t1').set({
        'status': 'active',
        'pendingProposal': {'proposedBy': 'H', 'proposedPhases': [], 'proposedAt': Timestamp.fromDate(DateTime(2026, 9, 5)), 'note': ''},
      });
      if (seen) await db.collection('seenMarkers').doc('G').set({'goalProposals': {'t1': tSeen}}, SetOptions(merge: true));
      if (!seen) await db.collection('guideTargets').doc('G').collection('targets').doc('t1').set({'pendingProposal': {'proposedAt': Timestamp.fromDate(DateTime(2026, 9, 20))}}, SetOptions(merge: true));
      return db;
    }

    test('a proposal not opened yet lights the Home tab through its own children; opening that target clears it', () async {
      await targetWorld(seen: false);
      expect(await latest(UnseenAggregates.goalProposalsUnseen('G')), isTrue);
      expect(await latest(UnseenAggregates.homeTrail('G', false)), isTrue, reason: 'the Home tab');
      expect(await latest(UnseenAggregates.analysisTrail('G', false, adminId: 'G')), isFalse, reason: 'it is NOT an Analysis dot any more: nothing in Analysis leads to it');
      await SeenMarkers.markSeenSub('G', 'goalProposals', 't1');
      expect(await latest(UnseenAggregates.goalProposalsUnseen('G')), isFalse);
    });

    test('a proposal already opened: no dot', () async {
      await targetWorld(seen: true);
      expect(await latest(UnseenAggregates.goalProposalsUnseen('G')), isFalse);
    });

    testWidgets('the dot on the target itself follows the same cursor', (tester) async {
      final db = await targetWorld(seen: false);
      await prepareApp(tester, seeded: false, who: Who.guide);
      GuideDb.useForTests(db);
      SeenMarkers.debugDisable = false;
      await tester.pumpWidget(guideHost(Scaffold(body: GoalProposalDot(guideId: 'G', targetId: 't1', proposedAt: DateTime(2026, 9, 20), child: const SizedBox(width: 40, height: 40)))));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump();
      }
      expect(find.byType(UnseenDot), findsOneWidget);
      await SeenMarkers.markSeenSub('G', 'goalProposals', 't1');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
      await tester.pump();
      expect(find.byType(UnseenDot), findsNothing);
    });
  });
}
