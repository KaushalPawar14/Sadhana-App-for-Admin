import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/StudentNotificationSettings.dart';
import 'package:folk_guide_app/widgets/StudentCommitmentsCard.dart';

import 'support/guide_test_support.dart';

/// Feature 1 — the guide editing a student's commitments and notification
/// switches, writing the SAME `users/{uid}` fields the Student app owns.

Future<void> pumpCard(
  WidgetTester tester,
  FakeFirebaseFirestore db, {
  int? rounds,
  int? reading,
  bool canEdit = true,
  double scale = 1.0,
  bool dark = false,
}) async {
  phone(tester, scale, resetBoardMemory: false);
  await tester.pumpWidget(guideHost(
    Scaffold(
      body: SingleChildScrollView(
        child: StudentCommitmentsCard(
          studentUid: 'u1',
          studentName: 'Yash',
          commitmentRounds: rounds,
          readingCommitmentMinutes: reading,
          canEdit: canEdit,
          firestore: db,
        ),
      ),
    ),
    dark: dark,
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGuideFonts();
  });

  // -------------------------------------------------------------------------
  // the summary line
  // -------------------------------------------------------------------------
  test('the line reads "Chanting: N rounds · Reading: N min"', () {
    expect(commitmentsLine(16, 30), 'Chanting: 16 rounds · Reading: 30 min');
  });

  test('a commitment that was never set says so, instead of inventing a 0', () {
    expect(commitmentsLine(null, null), 'Chanting: not set · Reading: not set');
    expect(commitmentsLine(0, null), contains('Chanting: not set'));
    // 0 reading minutes IS a real answer (a beginner), not "not set".
    expect(commitmentsLine(16, 0), 'Chanting: 16 rounds · Reading: 0 min');
  });

  // -------------------------------------------------------------------------
  // the card
  // -------------------------------------------------------------------------
  testWidgets('the card shows both commitments', (tester) async {
    await pumpCard(tester, FakeFirebaseFirestore(), rounds: 16, reading: 30);
    expect(find.text('Chanting: 16 rounds · Reading: 30 min'), findsOneWidget);
  });

  testWidgets('an admin who may not act on the student gets no Edit button',
      (tester) async {
    await pumpCard(tester, FakeFirebaseFirestore(),
        rounds: 16, reading: 30, canEdit: false);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('an admin in scope does get one', (tester) async {
    await pumpCard(tester, FakeFirebaseFirestore(), rounds: 16, reading: 30);
    expect(find.text('Edit'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // editing
  // -------------------------------------------------------------------------
  testWidgets('saving writes the two fields the Student app reads',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'name': 'Yash'});
    await pumpCard(tester, db, rounds: 16, reading: 30);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // Field 0 is chanting, field 1 is reading (their order in the dialog).
    await tester.enterText(find.byType(TextField).at(0), '24');
    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // the success snackbar holds a 3s timer; let it expire before the tree goes
    await tester.pump(const Duration(seconds: 4));

    final saved = (await db.collection('users').doc('u1').get()).data()!;
    expect(saved['commitmentRounds'], 24);
    expect(saved['readingCommitmentMinutes'], 45);
    // merged, not replaced — an unrelated field survives
    expect(saved['name'], 'Yash');
  });

  testWidgets('chanting must be a whole number of at least 1', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'name': 'Yash'});
    await pumpCard(tester, db, rounds: 16, reading: 30);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('at least 1'), findsOneWidget);
    // nothing was written
    final saved = (await db.collection('users').doc('u1').get()).data()!;
    expect(saved.containsKey('commitmentRounds'), isFalse);
  });

  testWidgets('reading minutes of 0 is accepted — it is a real answer',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'name': 'Yash'});
    await pumpCard(tester, db, rounds: 16, reading: 30);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    final saved = (await db.collection('users').doc('u1').get()).data()!;
    expect(saved['readingCommitmentMinutes'], 0);
  });

  testWidgets('reading minutes above a day are refused by the form, because '
      'the deployed rules refuse them too', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'name': 'Yash'});
    await pumpCard(tester, db, rounds: 16, reading: 30);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '2000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1440 minutes'), findsOneWidget);
    final saved = (await db.collection('users').doc('u1').get()).data()!;
    expect(saved.containsKey('readingCommitmentMinutes'), isFalse);
  });

  testWidgets('exactly a day is accepted', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'name': 'Yash'});
    await pumpCard(tester, db, rounds: 16, reading: 30);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '1440');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    final saved = (await db.collection('users').doc('u1').get()).data()!;
    expect(saved['readingCommitmentMinutes'], kMaxReadingCommitmentMinutes);
  });

  // -------------------------------------------------------------------------
  // notification switches
  // -------------------------------------------------------------------------
  test('absent or true both mean ON; only an explicit false is OFF', () {
    expect(prefIsOn(null, 'newTrip'), isTrue);
    expect(prefIsOn(<String, dynamic>{}, 'newTrip'), isTrue);
    expect(prefIsOn({'newTrip': true}, 'newTrip'), isTrue);
    expect(prefIsOn({'newTrip': false}, 'newTrip'), isFalse);
    // a non-bool is not an opt-out
    expect(prefIsOn({'newTrip': 'no'}, 'newTrip'), isTrue);
  });

  test('the six keys are exactly the Student app\'s, in its order', () {
    expect(kStudentPrefs.map((p) => p.key).toList(), [
      'sadhanaReminderMorning',
      'sadhanaReminderMidday',
      'associationUpdates',
      'chantingChallenge',
      'newTrip',
      'guideManualReminder',
    ]);
  });

  testWidgets('every switch is shown, reflecting the stored value',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({
      'name': 'Yash',
      'notificationPrefs': {'newTrip': false},
    });
    phone(tester, 1.0, resetBoardMemory: false);
    await tester.pumpWidget(guideHost(StudentNotificationSettingsPage(
      studentUid: 'u1',
      studentName: 'Yash',
      canEdit: true,
      firestore: db,
    )));
    await tester.pumpAndSettle();

    expect(find.byType(SwitchListTile), findsNWidgets(kStudentPrefs.length));
    final tiles = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    // newTrip is index 4 and is the only one off
    expect(tiles[4].value, isFalse);
    expect(tiles.where((t) => t.value).length, kStudentPrefs.length - 1);
  });

  testWidgets('flipping one writes only that dotted key', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({
      'name': 'Yash',
      'notificationPrefs': {'newTrip': false},
    });
    phone(tester, 1.0, resetBoardMemory: false);
    await tester.pumpWidget(guideHost(StudentNotificationSettingsPage(
      studentUid: 'u1',
      studentName: 'Yash',
      canEdit: true,
      firestore: db,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning sadhana reminder'));
    await tester.pumpAndSettle();

    final prefs = (await db.collection('users').doc('u1').get())
        .data()!['notificationPrefs'] as Map;
    expect(prefs['sadhanaReminderMorning'], isFalse);
    // the key that was already there is untouched
    expect(prefs['newTrip'], isFalse);
  });

  testWidgets('out of scope, the switches are inert', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'name': 'Yash'});
    phone(tester, 1.0, resetBoardMemory: false);
    await tester.pumpWidget(guideHost(StudentNotificationSettingsPage(
      studentUid: 'u1',
      studentName: 'Yash',
      canEdit: false,
      firestore: db,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning sadhana reminder'), warnIfMissed: false);
    await tester.pumpAndSettle();

    final data = (await db.collection('users').doc('u1').get()).data()!;
    expect(data.containsKey('notificationPrefs'), isFalse);
  });

  // -------------------------------------------------------------------------
  // layout: both themes, every text scale
  // -------------------------------------------------------------------------
  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets(
          'the card fits at text $scale, ${dark ? 'dark' : 'light'}',
          (tester) async {
        await pumpCard(tester, FakeFirebaseFirestore(),
            rounds: 16, reading: 30, scale: scale, dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.byType(StudentCommitmentsCard), findsOneWidget);
      });

      testWidgets(
          'the switches fit at text $scale, ${dark ? 'dark' : 'light'}',
          (tester) async {
        final db = FakeFirebaseFirestore();
        await db.collection('users').doc('u1').set({'name': 'Yash'});
        phone(tester, scale, resetBoardMemory: false);
        await tester.pumpWidget(guideHost(
          StudentNotificationSettingsPage(
            studentUid: 'u1',
            studentName: 'Yash',
            canEdit: true,
            firestore: db,
          ),
          dark: dark,
        ));
        await tester.pumpAndSettle();
        // The list is lazy, so at a large text scale fewer rows are BUILT than
        // exist — that is the ListView doing its job, not a missing switch.
        // What matters here is that nothing overflows or throws.
        expect(tester.takeException(), isNull);
        expect(find.byType(SwitchListTile), findsAtLeastNWidgets(1));
      });
    }
  }
}
