import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/InteractionLogger.dart' as logger;
import 'package:folk_guide_app/Services/GuideAi.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/actions/InteractionActions.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';

/// Saving an interaction, as one shared write.
///
/// `InteractionLoggerPage` and the AI agent both call [saveInteraction]. These pin what the guide gets:
/// the record is saved FIRST and complete, the notification carries the fact and nothing else, and the AI
/// work (analysing the note, making suggestions) is the SERVER's, afterwards, without a screen — the app
/// itself never calls an AI to save a note.

void main() {
  group('one call and quick reports', quickReportTests);
  late FakeFirebaseFirestore db;
  late List<Map<String, dynamic>> pushes;
  late List<String> calls;
  Object? failWith;

  setUp(() {
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
    pushes = [];
    calls = [];
    failWith = null;
    HierarchyApi.useForTests((name, args) async {
      calls.add(name);
      if (name == 'sendStudentNotification') pushes.add(args);
      if (failWith != null && name != 'sendStudentNotification') throw failWith!;
      if (name == 'generateStudentSuggestions') return {'count': 4};
      return <String, dynamic>{};
    });
  });
  tearDown(() {
    GuideDb.useForTests(null);
    HierarchyApi.useForTests(null);
  });

  final when = DateTime(2026, 10, 22, 18, 0);

  Future<SavedInteraction> save({DateTime? followUp, String type = 'Call'}) => saveInteraction(
        guideId: 'G',
        studentUid: 's1',
        studentName: 'Arjun Kumar',
        raw: 'Met after the evening program. He is struggling in exam week.',
        interactionType: type,
        interactionDate: when,
        followUpDate: followUp,
      );

  Future<Map<String, dynamic>> read(String id) async =>
      (await db.collection('interactionLogs').doc(id).get()).data()!;

  test('the types a guide can pick, in the order the screen offers them', () {
    expect(kInteractionTypes, ['WhatsApp', 'Call', 'Live (in-person)']);
    // and still reachable from where it always was
    expect(logger.kInteractionTypes, kInteractionTypes);
  });

  test('saves the complete record in ONE write, with the fields every reader expects', () async {
    final saved = await save();
    final d = await read(saved.id);
    expect(d['studentUid'], 's1');
    expect(d['studentName'], 'Arjun Kumar');
    expect(d['guideId'], 'G');
    expect(d['status'], 'approved', reason: 'no draft, no approval step');
    expect(d['extractedDraft'], isNull);
    expect(d['rawDictation'], contains('Met after the evening program'), reason: 'the note, for the server to analyse');
    expect((d['interactionDate'] as Timestamp).toDate(), when);
    expect(d['createdAt'], isNotNull);
    expect(d['approvedAt'], isNotNull);
    expect((await db.collection('interactionLogs').get()).docs.length, 1);
  });

  test('it is queued for the server to analyse — the app calls no AI at all', () async {
    final saved = await save();
    expect((await read(saved.id))['analysis'], 'queued');
    expect(calls, ['sendStudentNotification'], reason: 'nothing but the "logged" notification leaves the phone');
  });

  test("the guide's own choices are in the record from the first write", () async {
    final saved = await save(followUp: DateTime(2026, 10, 30));
    final summary = (await read(saved.id))['approvedSummary'] as Map<String, dynamic>;
    expect(summary['interactionType'], 'Call');
    expect((summary['interactionDateTime'] as Timestamp).toDate(), when);
    expect((summary['followUpDate'] as Timestamp).toDate(), DateTime(2026, 10, 30));
    expect(summary['themes'], isEmpty, reason: 'the server fills these in later');
  });

  test('how they connected is optional', () async {
    final saved = await saveInteraction(
      guideId: 'G',
      studentUid: 's1',
      studentName: 'Arjun Kumar',
      raw: 'Chatted after class.',
      interactionDate: when,
    );
    final summary = (await read(saved.id))['approvedSummary'] as Map<String, dynamic>;
    expect(summary['interactionType'], '');
  });

  test('the notification carries the fact and none of the content', () async {
    await save();
    expect(pushes.single, {'kind': 'interaction_logged', 'studentUid': 's1'});
    final sent = pushes.single.toString();
    expect(sent.contains('exam'), isFalse);
    expect(sent.contains('Met after'), isFalse);
  });

  test('a failed notification never undoes the save', () async {
    HierarchyApi.useForTests((name, args) async => throw StateError('offline'));
    final saved = await save();
    expect((await read(saved.id))['analysis'], 'queued');
  });

  test('a failure of the first write throws — and nobody is told', () async {
    GuideDb.useForTests(_Refusing(db));
    await expectLater(save(), throwsA(anything));
    expect(pushes, isEmpty, reason: 'nobody is told about a note that does not exist');
  });

  test('no follow-up date means none is stored', () async {
    final saved = await save();
    final summary = (await read(saved.id))['approvedSummary'] as Map<String, dynamic>;
    expect(summary['followUpDate'], isNull);
  });

  test('re-extracting asks the SERVER, which saves the result; the app only reports the outcome', () async {
    await reExtractInteraction('log1');
    expect(calls, ['analyseInteraction']);
  });

  test('a re-extract the server refuses says why, readably', () async {
    failWith = HierarchyException('resource-exhausted', "The server's OpenAI account has no credit left.");
    await expectLater(
      reExtractInteraction('log1'),
      throwsA(isA<AiException>().having((e) => e.message, 'message', contains('no credit left'))),
    );
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

/// ONE AI CALL for a report, and QUICK REPORTS (one tap, no notes, no AI): what is written is the same kind of record the server already
/// follows up (the plan item ticked, the history line, the Surrender %, the next association).
void quickReportTests() {
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

  Future<Map<String, dynamic>> read(String id) async => (await db.collection('interactionLogs').doc(id).get()).data()!;

  test('ONE CALL: the understanding the assistant already made rides on the log (preAnalysis); the server saves it as it stands', () async {
    final saved = await saveInteraction(
      guideId: 'G',
      studentUid: 's1',
      studentName: 'Arjun',
      raw: 'He is keen but has exams',
      interactionType: 'Call',
      interactionDate: DateTime(2026, 10, 22, 18),
      analysis: {'themes': ['exams'], 'studentConcerns': 'Exam stress', 'recommendedNextAction': 'Call after exams'},
    );
    final d = await read(saved.id);
    expect(d['preAnalysis'], {'themes': ['exams'], 'studentConcerns': 'Exam stress', 'recommendedNextAction': 'Call after exams'});
    expect(d['analysis'], 'queued', reason: 'the server finishes it (without a model call)');
    // no analysis: exactly the old record (the server reads the notes)
    final plain = await saveInteraction(guideId: 'G', studentUid: 's1', studentName: 'Arjun', raw: 'x', interactionDate: DateTime(2026, 10, 22));
    expect((await read(plain.id)).containsKey('preAnalysis'), isFalse);
  });

  test('QUICK REPORT "Talked": a complete record, no notes, reached him, told the others; the willingness taps carry only the shift', () async {
    final talked = await saveQuickReport(guideId: 'G', studentUid: 's1', studentName: 'Arjun', outcome: QuickOutcome.talked, mode: 'call', topics: ['His sadhana', 'His doubt']);
    final d = await read(talked.id);
    expect(d['rawDictation'], '', reason: 'no notes: the server has nothing to send to a model');
    expect(d['addressed'], true);
    expect(d['quick'], 'talked');
    expect(d['status'], 'approved');
    expect(d['analysis'], 'queued');
    expect(d.containsKey('willingnessShift'), isFalse);
    expect((d['approvedSummary'] as Map)['interactionType'], 'Call');
    expect((d['approvedSummary'] as Map)['themes'], ['His sadhana', 'His doubt']);
    expect(pushes.any((p) => p['kind'] == 'interaction_logged' && p['studentUid'] == 's1'), isTrue, reason: 'the same notification as any report');
    for (final e in {QuickOutcome.moreWilling: 1, QuickOutcome.sameWilling: 0, QuickOutcome.lessWilling: -1}.entries) {
      final s = await saveQuickReport(guideId: 'G', studentUid: 's1', studentName: 'Arjun', outcome: e.key);
      final r = await read(s.id);
      expect(r['willingnessShift'], e.value, reason: '${e.key}');
      expect(r['addressed'], true);
      expect((r['approvedSummary'] as Map)['interactionType'], 'Live (in-person)', reason: 'no mode: in person');
    }
  });

  test('QUICK REPORT "Not reachable": a report that did not reach him: the interaction stays in the plan; the others are not told', () async {
    final s = await saveQuickReport(guideId: 'G', studentUid: 's1', studentName: 'Arjun', outcome: QuickOutcome.notReachable, mode: 'call');
    final d = await read(s.id);
    expect(d['addressed'], false);
    expect(d['quick'], 'not_reachable');
    expect((d['approvedSummary'] as Map)['temporaryCircumstances'], 'Not reachable');
    expect(pushes, isEmpty);
  });
}
