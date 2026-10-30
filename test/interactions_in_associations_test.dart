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
  testWidgets('a student\'s Interactions page has no "New" button either; it says how to record one', (tester) async {
    await prepareApp(tester);
    await pumpScreen(tester, const InteractionLoggerPage(studentUid: 's4', studentName: 'Dhruva Nair'));
    await tester.pumpAndSettle();
    expect(find.text('New'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.textContaining('Tell the assistant about your next conversation'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // they show in the association history, and are counted
  // -------------------------------------------------------------------------
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
        expect(tester.takeException(), isNull);
        expect(find.text('Add interaction'), findsNothing);
      });
    }
  }
}
