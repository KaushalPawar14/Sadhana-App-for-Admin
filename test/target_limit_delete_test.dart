import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';

/// Master 1 A1 — a guide may hold ONE active target per metric.
///
/// The limit is enforced in `createCompoundTargetShell`, not only in the setup
/// screen, so every path to a new target goes past it.

Future<String> seedTarget(
  FakeFirebaseFirestore db, {
  String guideId = 'G',
  String metric = 'chanting',
  String status = kCompoundStatusActive,
}) async {
  final ref = db
      .collection('guideTargets')
      .doc(guideId)
      .collection('targets')
      .doc();
  await ref.set({
    'metric': metric,
    'studentCountGoal': 15,
    'perStudentValueGoal': 16,
    'endDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
    'status': status,
    'currentPhase': 1,
    'totalPhases': 3,
  });
  return ref.id;
}

Future<String> create(String metric) => createCompoundTargetShell(
      guideId: 'G',
      metric: metric,
      studentCountGoal: 15,
      perStudentValueGoal: metric == 'books' ? 3 : 16,
      endDate: DateTime.now().add(const Duration(days: 30)),
    );

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
  });
  tearDown(() => GuideDb.useForTests(null));

  // -------------------------------------------------------------------------
  // the message
  // -------------------------------------------------------------------------
  test('the message names the metric the guide must clear', () {
    expect(targetLimitMessage('chanting'),
        'Delete your current chanting target first');
    expect(targetLimitMessage('books'),
        'Delete your current book reading target first');
  });

  // -------------------------------------------------------------------------
  // finding the active one
  // -------------------------------------------------------------------------
  test('with nothing there, no active target is found', () async {
    expect(await activeTargetOfMetric('G', 'chanting'), isNull);
  });

  test('an active target of that metric is found', () async {
    await seedTarget(db, metric: 'chanting');
    final found = await activeTargetOfMetric('G', 'chanting');
    expect(found, isNotNull);
    expect(found!.metric, 'chanting');
    // the other metric is unaffected
    expect(await activeTargetOfMetric('G', 'books'), isNull);
  });

  test('a completed or abandoned target does not count', () async {
    await seedTarget(db, metric: 'chanting', status: kCompoundStatusCompleted);
    await seedTarget(db, metric: 'books', status: kCompoundStatusAbandoned);
    expect(await activeTargetOfMetric('G', 'chanting'), isNull);
    expect(await activeTargetOfMetric('G', 'books'), isNull);
  });

  test("another guide's target does not block this one", () async {
    await seedTarget(db, guideId: 'G2', metric: 'chanting');
    expect(await activeTargetOfMetric('G', 'chanting'), isNull);
  });

  // -------------------------------------------------------------------------
  // the limit itself
  // -------------------------------------------------------------------------
  test('the first target of a metric is created', () async {
    final id = await create('chanting');
    expect(id, isNotEmpty);
    final snap = await db
        .collection('guideTargets').doc('G').collection('targets').get();
    expect(snap.docs.length, 1);
  });

  test('a SECOND active target of the same metric is refused', () async {
    await create('chanting');
    await expectLater(
      create('chanting'),
      throwsA(isA<CompoundTargetLimitException>().having(
          (e) => e.message, 'message',
          'Delete your current chanting target first')),
    );
    // and nothing was written by the refused attempt
    final snap = await db
        .collection('guideTargets').doc('G').collection('targets').get();
    expect(snap.docs.length, 1);
  });

  test('the OTHER metric is still allowed alongside it', () async {
    await create('chanting');
    final books = await create('books');
    expect(books, isNotEmpty);
    final snap = await db
        .collection('guideTargets').doc('G').collection('targets').get();
    expect(snap.docs.length, 2);
  });

  test('both metrics are limited, each on its own', () async {
    await create('books');
    await expectLater(
      create('books'),
      throwsA(isA<CompoundTargetLimitException>().having(
          (e) => e.message, 'message',
          'Delete your current book reading target first')),
    );
  });

  test('after the old one is abandoned, a new one is allowed', () async {
    final id = await create('chanting');
    await abandonCompoundTarget('G', id);
    final second = await create('chanting');
    expect(second, isNotEmpty);
  });

  _messageTests();

  test('a metric that is not chanting or books is still refused outright',
      () async {
    await expectLater(create('association'), throwsA(isA<ArgumentError>()));
  });
}

// ---------------------------------------------------------------------------
// The delete failure message — the bug the HOD hit on 22 Oct 2026
// ---------------------------------------------------------------------------
// The callable was unreachable (its container would not start), so every
// attempt threw and the screen said "Could not delete the target just now."
// That reads as "the delete is broken" when the delete was fine, and it hid
// the one fact that identified the real cause: the error code.

/// The exception the callable throws. Its constructor is @protected, so it
/// is built here once rather than at every call site.
FirebaseFunctionsException fnError(String code, [String message = 'x']) =>
    // ignore: invalid_use_of_protected_member
    FirebaseFunctionsException(code: code, message: message);

void _messageTests() {
  test('an unreachable function says so, with its code', () {
    for (final code in ['unavailable', 'internal', 'deadline-exceeded']) {
      final msg = deleteFailureMessage(
          fnError(code, 'INTERNAL'));
      expect(msg, 'The server did not answer ($code)');
      expect(msg, isNot(contains('just now')));
    }
  });

  test('each code that means something specific says what it means', () {
    expect(
        deleteFailureMessage(fnError('unauthenticated')),
        'Your sign-in has lapsed — sign in again (unauthenticated)');
    expect(
        deleteFailureMessage(fnError('permission-denied')),
        'Refused — either the target is not yours, or the app is shut out '
        'of this function (permission-denied)');
    expect(
        deleteFailureMessage(
            fnError('not-found')),
        'That target no longer exists (not-found)');
  });

  test('an unknown code still shows the code AND the server sentence', () {
    final msg = deleteFailureMessage(fnError('resource-exhausted', 'Quota exceeded'));
    expect(msg, contains('resource-exhausted'));
    expect(msg, contains('Quota exceeded'));
  });

  test('a plain Firestore error is reported too, never swallowed', () {
    final msg = deleteFailureMessage(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    expect(msg, contains('permission-denied'));
  });

  test('even a non-Firebase error is shown rather than hidden', () {
    expect(deleteFailureMessage(StateError('boom')), contains('boom'));
  });

  test('no failure is ever reported with the old generic wording', () {
    final errors = <Object>[
      fnError('internal', 'INTERNAL'),
      FirebaseException(plugin: 'cloud_firestore', code: 'aborted'),
      StateError('boom'),
    ];
    for (final e in errors) {
      expect(deleteFailureMessage(e), isNot(contains('just now')));
      expect(deleteFailureMessage(e), isNot(contains('Could not delete')));
    }
  });
}
