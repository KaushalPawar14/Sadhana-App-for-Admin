import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AbcdeActivityCard.dart';
import 'package:folk_guide_app/Pages/AssociationManager.dart';
import 'package:folk_guide_app/Pages/InteractionLogger.dart';
import 'package:folk_guide_app/Pages/StudentProfilePage.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// Feature 4 — interactions move INTO Associations and stay guide-app only.
///
/// `interactionLogs` keeps its own collection and document shape, so every
/// existing reader is untouched; only the way in and the place they are shown
/// moved. Nothing is written to `associations`, and the Student app — which
/// never read `interactionLogs` — is unaffected.

Future<void> openAssociations(WidgetTester tester,
    {double scale = 1.0, bool dark = false}) async {
  await pumpScreen(tester, const AssociationManagerPage(),
      scale: scale, dark: dark);
  await tester.pumpAndSettle();
}

/// Moves to the "Upcoming & History" tab, where interactions live.
Future<void> openHistoryTab(WidgetTester tester) async {
  await tester.tap(find.text('Upcoming & History'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  // -------------------------------------------------------------------------
  // the separate feature is gone
  // -------------------------------------------------------------------------
  testWidgets('the Student profile no longer offers "Log Interaction"',
      (tester) async {
    await prepareApp(tester);
    await pumpScreen(tester, const StudentProfilePage(studentUid: 's1'));
    await tester.pumpAndSettle();

    expect(find.text('Log Interaction'), findsNothing);
    expect(find.text('Interactions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // -------------------------------------------------------------------------
  // the new way in
  // -------------------------------------------------------------------------
  testWidgets('Associations offers "Add interaction" on both tabs',
      (tester) async {
    await prepareApp(tester);
    await openAssociations(tester);
    expect(find.text('Add interaction'), findsOneWidget);
    // creating a MEETING still belongs only on the pending tab
    expect(find.text('New Meeting'), findsOneWidget);

    await openHistoryTab(tester);
    expect(find.text('Add interaction'), findsOneWidget);
    expect(find.text('New Meeting'), findsNothing);
  });

  testWidgets('"Add interaction" asks which student, then opens the form',
      (tester) async {
    await prepareApp(tester);
    await openAssociations(tester);

    await tester.tap(find.text('Add interaction'));
    await tester.pumpAndSettle();

    // the scoped roster, by name
    expect(find.text('Add interaction'), findsWidgets);
    expect(find.text('Arjun Kumar'), findsWidgets);

    await tester.tap(find.text('Arjun Kumar').last);
    await tester.pumpAndSettle();

    expect(find.byType(InteractionLoggerPage), findsOneWidget);
  });

  testWidgets('cancelling the student picker opens nothing', (tester) async {
    await prepareApp(tester);
    await openAssociations(tester);
    await tester.tap(find.text('Add interaction'));
    await tester.pumpAndSettle();
    // the picker's own Cancel is the last one in the tree
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byType(InteractionLoggerPage), findsNothing);
  });

  // -------------------------------------------------------------------------
  // they show in the association history, and are counted
  // -------------------------------------------------------------------------
  testWidgets('existing interaction logs show in the history, with a count',
      (tester) async {
    await prepareApp(tester);
    await openAssociations(tester);
    await openHistoryTab(tester);

    expect(find.text('Interactions (1)'), findsOneWidget);
    // the seeded note is about Arjun
    expect(find.text('Arjun Kumar'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new interaction appears there too — the list is live',
      (tester) async {
    final db = await prepareApp(tester);
    await openAssociations(tester);
    await openHistoryTab(tester);
    expect(find.text('Interactions (1)'), findsOneWidget);

    await db.collection('interactionLogs').add({
      'studentUid': 's2',
      'studentName': 'Bhima Sen',
      'guideId': 'G',
      'status': 'approved',
      'interactionDate': Timestamp.fromDate(DateTime.now()),
      'rawDictation': 'Talked about his reading.',
      'approvedSummary': {'recommendedNextAction': 'Check again next week'},
    });
    await tester.pumpAndSettle();

    expect(find.text('Interactions (2)'), findsOneWidget);
    expect(find.text('Check again next week'), findsOneWidget);
  });

  testWidgets('the card reads the summary MAP, never prints it raw',
      (tester) async {
    final db = await prepareApp(tester);
    await db.collection('interactionLogs').add({
      'studentUid': 's2',
      'studentName': 'Bhima Sen',
      'guideId': 'G',
      'interactionDate': Timestamp.fromDate(DateTime.now()),
      'approvedSummary': {'recommendedNextAction': 'Ring him on Friday'},
    });
    await openAssociations(tester);
    await openHistoryTab(tester);

    expect(find.text('Ring him on Friday'), findsOneWidget);
    // no raw map ever reaches the screen
    expect(find.textContaining('recommendedNextAction:'), findsNothing);
    expect(find.textContaining('{'), findsNothing);
  });

  testWidgets('with no meetings at all, interactions still show', (tester) async {
    final db = await prepareApp(tester, seeded: false);
    await db.collection('users').doc('s9').set({
      'name': 'Solo Student',
      'role': 'Stay at FOLK',
      'gender': 'male',
      'guideId': 'G',
      'teamGuide': 'G',
    });
    await db.collection('interactionLogs').add({
      'studentUid': 's9',
      'studentName': 'Solo Student',
      'guideId': 'G',
      'interactionDate': Timestamp.fromDate(DateTime.now()),
      'rawDictation': 'A quiet chat.',
    });
    await openAssociations(tester);
    await openHistoryTab(tester);

    expect(find.text('Interactions (1)'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('with nothing at all, the tab still says so', (tester) async {
    await prepareApp(tester, seeded: false);
    await openAssociations(tester);
    await openHistoryTab(tester);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // counted on the student's own profile
  // -------------------------------------------------------------------------
  testWidgets('the ABCDE card counts interactions under A, separately from meetings',
      (tester) async {
    await prepareApp(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: AbcdeActivityCard(
            studentUid: 's1',
            studentName: 'Arjun Kumar',
            role: 'Stay at FOLK',
            lifetimeRounds: 1200,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('interaction'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no interactions reads as none, not as a blank', (tester) async {
    await prepareApp(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: AbcdeActivityCard(
            studentUid: 's2',
            studentName: 'Bhima Sen',
            role: 'Stay at Hostel',
            lifetimeRounds: 400,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No interactions logged in the last 90 days'), findsOneWidget);
  });

  testWidgets('the count updates LIVE — no reopening the profile',
      (tester) async {
    final db = await prepareApp(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: AbcdeActivityCard(
            studentUid: 's2',
            studentName: 'Bhima Sen',
            role: 'Stay at Hostel',
            lifetimeRounds: 400,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No interactions logged in the last 90 days'),
        findsOneWidget);

    // an interaction saved elsewhere, while this card stays on screen
    await db.collection('interactionLogs').add({
      'studentUid': 's2',
      'studentName': 'Bhima Sen',
      'guideId': 'G',
      'interactionDate': Timestamp.fromDate(DateTime.now()),
      'rawDictation': 'Spoke after class.',
    });
    await tester.pumpAndSettle();

    expect(find.text('No interactions logged in the last 90 days'), findsNothing);
    expect(find.textContaining('1 interaction in the last 90 days'),
        findsOneWidget);
  });

  testWidgets('a new MEETING updates the A limb live too', (tester) async {
    final db = await prepareApp(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: AbcdeActivityCard(
            studentUid: 's2',
            studentName: 'Bhima Sen',
            role: 'Stay at Hostel',
            lifetimeRounds: 400,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No meeting held yet'), findsOneWidget);

    await db.collection('associations').add({
      'studentUid': 's2',
      'studentName': 'Bhima Sen',
      'guideId': 'G',
      'status': 'completed',
      'confirmedDate':
          Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
    });
    await tester.pumpAndSettle();

    expect(find.text('No meeting held yet'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // nothing was written into associations
  // -------------------------------------------------------------------------
  testWidgets('interactions are NOT written into the associations collection',
      (tester) async {
    final db = await prepareApp(tester);
    final before = (await db.collection('associations').get()).docs.length;
    await openAssociations(tester);
    await openHistoryTab(tester);
    final after = (await db.collection('associations').get()).docs.length;
    expect(after, before, reason: 'showing interactions must not create any');
  });

  // -------------------------------------------------------------------------
  // both themes, every text scale
  // -------------------------------------------------------------------------
  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('Associations with interactions fits at text $scale, '
          '${dark ? 'dark' : 'light'}', (tester) async {
        await prepareApp(tester);
        await openAssociations(tester, scale: scale, dark: dark);
        await openHistoryTab(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Add interaction'), findsOneWidget);
      });
    }
  }
}
