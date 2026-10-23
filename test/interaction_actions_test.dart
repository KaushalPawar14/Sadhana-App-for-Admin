import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/InteractionLogger.dart' as logger;
import 'package:folk_guide_app/Services/GeminiService.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/actions/InteractionActions.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';

/// Saving an interaction, as one shared write.
///
/// `InteractionLoggerPage` and the AI agent both call [saveInteraction]. These pin
/// what the screen always did — read off its own code before it moved: the
/// record is saved FIRST and complete, the notification carries the fact and
/// nothing else, the AI fills in details afterwards, and a failure of the AI can
/// never lose what the guide wrote.

void main() {
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

  final when = DateTime(2026, 10, 22, 18, 0);

  Future<SavedInteraction> save({
    DateTime? followUp,
    Future<Map<String, dynamic>> Function(String, String)? extract,
  }) =>
      saveInteraction(
        guideId: 'G',
        studentUid: 's1',
        studentName: 'Arjun Kumar',
        raw: 'Met after the evening program. He is struggling in exam week.',
        interactionType: 'Call',
        interactionDate: when,
        followUpDate: followUp,
        extract: extract ?? (r, n) async => {
              'themes': ['exams'],
              'studentConcerns': 'exam week',
              'possibleLitEvidence': 'Time is limited',
              'interactionType': 'WhatsApp', // the AI's guess — must be overridden
              'recommendedNextAction': 'Check in on Friday',
            },
      );

  Future<Map<String, dynamic>> read(String id) async =>
      (await db.collection('interactionLogs').doc(id).get()).data()!;

  test('the types a guide can pick, in the order the screen offers them', () {
    expect(kInteractionTypes, ['WhatsApp', 'Call', 'Live (in-person)']);
    // and still reachable from where it always was
    expect(logger.kInteractionTypes, kInteractionTypes);
  });

  test('saves the complete record first, with the fields every reader expects', () async {
    String? seenWhileExtracting;
    final saved = await save(extract: (r, n) async {
      // By the time the AI is asked, the note must already be safely stored.
      final snap = await db.collection('interactionLogs').get();
      seenWhileExtracting = snap.docs.single.data()['rawDictation'] as String?;
      return {'themes': <String>[]};
    });
    expect(seenWhileExtracting, contains('Met after the evening program'),
        reason: 'saved BEFORE extraction, so an AI failure can never lose it');

    final d = await read(saved.id);
    expect(d['studentUid'], 's1');
    expect(d['studentName'], 'Arjun Kumar');
    expect(d['guideId'], 'G');
    expect(d['status'], 'approved', reason: 'no draft, no approval step');
    expect(d['extractedDraft'], isNull);
    expect((d['interactionDate'] as Timestamp).toDate(), when);
    expect(d['createdAt'], isNotNull);
    expect(d['approvedAt'], isNotNull);
  });

  test("the guide's own choices beat the AI's guesses", () async {
    final saved = await save(followUp: DateTime(2026, 10, 30));
    final summary = (await read(saved.id))['approvedSummary'] as Map<String, dynamic>;
    expect(summary['interactionType'], 'Call', reason: "not the AI's 'WhatsApp'");
    expect((summary['interactionDateTime'] as Timestamp).toDate(), when);
    expect((summary['followUpDate'] as Timestamp).toDate(), DateTime(2026, 10, 30));
    expect(summary['themes'], ['exams'], reason: 'what the AI filled in is kept');
    expect(summary['recommendedNextAction'], 'Check in on Friday');
  });

  test('once the details are filled in the raw dictation is dropped', () async {
    final saved = await save();
    expect((await read(saved.id)).containsKey('rawDictation'), isFalse);
    expect(saved.extractionError, isNull);
    expect(saved.litPrefill, 'Time is limited');
  });

  test('the notification carries the fact and none of the content', () async {
    await save();
    expect(pushes.single, {'kind': 'interaction_logged', 'studentUid': 's1'});
    final sent = pushes.single.toString();
    expect(sent.contains('exam'), isFalse);
    expect(sent.contains('Met after'), isFalse);
  });

  test('the notification goes out BEFORE the AI is asked', () async {
    int? pushesWhenAsked;
    await save(extract: (r, n) async {
      pushesWhenAsked = pushes.length;
      return {};
    });
    expect(pushesWhenAsked, 1,
        reason: 'at least as reliable as before: never lost to an AI failure');
  });

  test('when the AI fails the note still stands, with its dictation, and says why', () async {
    final saved = await save(extract: (r, n) async => throw GeminiException('Gemini returned 429.'));
    expect(saved.extractionError, 'Gemini returned 429.');
    final d = await read(saved.id);
    expect(d['rawDictation'], contains('Met after'),
        reason: 'kept, so the guide can Re-extract from the entry later');
    expect(d['status'], 'approved');
  });

  test('any other AI failure is reported too, not swallowed or fatal', () async {
    final saved = await save(extract: (r, n) async => throw StateError('boom'));
    expect(saved.extractionError, startsWith('Extraction failed'));
    expect((await db.collection('interactionLogs').get()).docs.length, 1);
  });

  test('a failure of the first write throws — and nothing else happens', () async {
    // A Firestore that refuses the add.
    GuideDb.useForTests(_Refusing(db));
    var asked = false;
    await expectLater(
      save(extract: (r, n) async {
        asked = true;
        return {};
      }),
      throwsA(anything),
    );
    expect(asked, isFalse, reason: 'no AI call for a note that was not saved');
    expect(pushes, isEmpty, reason: 'and nobody is told about a note that does not exist');
  });

  test('no follow-up date means none is stored', () async {
    final saved = await save();
    final summary = (await read(saved.id))['approvedSummary'] as Map<String, dynamic>;
    expect(summary['followUpDate'], isNull);
  });

  test('dates round-trip between the AI draft and Firestore', () {
    final ts = Timestamp.fromDate(DateTime(2026, 10, 22));
    expect(tsFromIso(ts), ts);
    expect(tsFromIso('2026-10-22T00:00:00.000'), isA<Timestamp>());
    expect(tsFromIso(''), isNull);
    expect(tsFromIso(null), isNull);
    expect(tsFromIso('not a date'), isNull);
    final out = interactionDraftForFirestore({
      'interactionDateTime': '2026-10-22T18:00:00.000',
      'followUpDate': '',
      'themes': ['a'],
    });
    expect(out['interactionDateTime'], isA<Timestamp>());
    expect(out['followUpDate'], isNull);
    expect(out['themes'], ['a']);
  });
}

/// A Firestore whose `interactionLogs.add` always fails.
class _Refusing extends FakeFirebaseFirestore {
  _Refusing(FakeFirebaseFirestore inner);

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (path == 'interactionLogs') throw StateError('permission-denied');
    return super.collection(path);
  }
}
