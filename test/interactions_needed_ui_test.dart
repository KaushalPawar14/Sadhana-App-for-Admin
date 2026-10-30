import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BoardData.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/StudentHistory.dart';
import 'package:folk_guide_app/utils/SurrenderData.dart';
import 'package:folk_guide_app/widgets/SurrenderBar.dart' show surrenderPoints;
import 'package:folk_guide_app/widgets/StudentHistoryList.dart';

import 'board_test.dart' show FakeBoardData, openBoard, roster;
import 'support/guide_test_support.dart';

/// MASTER 4 in the Guide app: the board card's SURRENDER % (guides and HODs only), the interaction cards in the plans (one per student,
/// a section of questions for each topic, a tick once reported back), the threshold lines in the history, and the removed buttons.

final DateTime _now = DateTime.utc(2026, 10, 30, 4, 30);

class _FakePlanData extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => _now;
}

const _topics = [
  PlanTopic(
    key: 'concern_m1',
    label: 'His worry',
    reason: 'Sounded discouraged or worried in his AI chat',
    questions: ['How are you feeling, Harsh?', 'What happened?', 'How can I help?'],
    suggestions: ['Listen first; do not correct or push.'],
  ),
  PlanTopic(
    key: 'target_chanting_t1',
    label: 'Chanting target',
    reason: 'Chanting target: at 12 rounds, the phase asks for 14',
    questions: ['You chant 12 rounds now. Would you like to increase?', 'What is stopping you from chanting more?', 'When could you move to 14?', 'What would help?'],
    suggestions: ['Agree one concrete day to start 14 rounds.'],
  ),
  PlanTopic(
    key: 'surrender_thr_1',
    label: 'Surrender step',
    reason: 'Surrender crossed 40% (up)',
    questions: ['What does surrender mean to you?', 'Which service would you like?', 'What helps your timings?', 'What would it take to stay in FOLK?'],
    suggestions: ['His next step: coming to stay in FOLK.'],
    conclusions: ['Surrender grows through regular sadhana, service and association.'],
    meaning: 'Surrender is not giving up something; it is giving ourselves in service.',
  ),
];

PlanDoc _plan({bool done = false, String source = 'ai'}) => PlanDoc(
      todayDate: '2026-10-30',
      todayItems: [
        PlanItem(
          id: 'interaction:u1:2026-10-28',
          kind: 'interaction',
          title: 'Interaction with Harsh',
          detail: 'Why: Sounded discouraged or worried in his AI chat. Chanting target: at 12 rounds. Surrender crossed 40% (up).',
          studentName: 'Harsh',
          forYou: true,
          done: done,
          topics: _topics,
          percent: 42,
          level: '30–50%: Deepen',
          briefSource: source,
        ),
      ],
      weekOf: '2026-10-26',
      intro: 'Hare Krishna Gopal! 1 interaction is needed.',
      sections: const [
        PlanSection(id: 'interactions', title: 'Interactions needed', items: [
          PlanItem(id: 'interaction:u2:2026-10-29', kind: 'interaction', title: 'Interaction with Kishan', detail: 'Why: Surrender crossed 30% (down).', scheduledFor: '2026-11-01', forYou: true, topics: [
            PlanTopic(key: 'surrender_thr_2', label: 'Surrender step', reason: 'Surrender crossed 30% (down)', questions: ['What happened this month?', 'What is hard?', 'What helps?', 'When will you restart?'], suggestions: []),
          ]),
        ]),
      ],
      generatedAt: _now.subtract(const Duration(minutes: 20)),
      status: 'upToDate',
      changedAt: _now,
    );

AdminProfile _me() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

Future<void> _openPlan(WidgetTester tester, {double scale = 1.0, bool dark = false, PlanDoc? doc}) async {
  // tall, so the batch card and the counts above Today's cards do not push a card off the screen
  phone(tester, scale, size: const Size(360, 2400));
  AdminProfileProvider.instance.debugSet(_me());
  final data = _FakePlanData();
  PlanData.instance = data;
  await tester.pumpWidget(guideHost(const PlanPage(), dark: dark));
  data.controller.add(doc ?? _plan());
  await tester.pump();
  await tester.pump();
}

SurrenderInfo _info({int percent = 42, int? trend = 6, String? cap, bool complete = true}) => SurrenderInfo(
      percent: percent,
      trend: trend,
      cap: cap,
      complete: complete,
      residence: 'hostel',
      gender: 'male',
      parts: const [
        SurrenderPart(key: 'commitment', label: 'Commitment', weight: 10, score: 0.6, points: 6, reason: 'Committed to 12 rounds and 30 min of reading a day.'),
        SurrenderPart(key: 'sadhana', label: 'Sadhana actually done', weight: 40, score: 0.5, points: 20, reason: 'Last 30 days: rounds 70% of 16.'),
        SurrenderPart(key: 'attitude', label: 'Association — attitude & willingness', weight: 20, score: 0, points: 0, missing: true, reason: 'No interaction or meeting with his guide in the last 30 days → 0 of 20'),
        SurrenderPart(key: 'lit', label: 'LIT', weight: 20, score: 0, points: 0, missing: true, reason: 'No LIT yet → 0 of 20'),
        SurrenderPart(key: 'bonus', label: 'Bonus', weight: 10, score: 0, points: 0, reason: 'No bonus earned yet (it comes from the daily report forms, the last 30 days)'),
      ],
    );


/// Every row of Today opens (a tap on the row shows its topics).
Future<void> _openRows(WidgetTester tester) async {
  final rows = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('plan-row-') && !(w.key! as ValueKey<String>).value.startsWith('plan-row-body-'));
  final n = rows.evaluate().length;
  for (var i = 0; i < n; i++) {
    await tester.tap(rows.at(i));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDown(() {
    BoardData.instance = const FirestoreBoardData();
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  // ------------------------------------------------------------------------------------------------ the data
  group('the Surrender data', () {
    test('a document becomes a percent with its parts, the trend and the cap', () {
      final i = SurrenderInfo.fromDoc({
        'percent': 41.6,
        'trend': -3,
        'cap': 'residence',
        'complete': false,
        'residence': 'hostel',
        'parts': [
          {'key': 'lit', 'label': 'LIT', 'weight': 10, 'score': null, 'reason': 'No complete LIT assessment yet (not enough data).'},
          {'key': 'sadhana', 'label': 'Sadhana actually done', 'weight': 40, 'score': 0.5, 'reason': 'r'},
          'junk',
        ],
      })!;
      expect(i.percent, 42);
      expect(i.trend, -3);
      expect(i.cap, 'residence');
      expect(i.parts.length, 2);
      expect(i.parts.first.score, isNull, reason: 'not enough data is not a failure');
      expect(SurrenderInfo.fromDoc(null), isNull);
      expect(SurrenderInfo.fromDoc({'parts': []}), isNull);
    });

    test('the six stages', () {
      expect([0, 9, 10, 29, 30, 49, 50, 69, 70, 89, 90, 100].map(surrenderStageOf).toList(),
          ['Start', 'Start', 'Consistency', 'Consistency', 'Deepen', 'Deepen', 'Commit', 'Commit', 'Strict sadhana', 'Strict sadhana', 'Surrender', 'Surrender']);
    });

    test('the history has a Surrender kind with its own icon and label', () {
      expect(historyKindLabel(kHistorySurrender), 'Surrender');
      expect(historyIcon(kHistorySurrender), isNot(historyIcon(kHistoryDealing)));
    });
  });

  // ------------------------------------------------------------------------------------------------ the board card
  group('the board card shows "Surrender %" (guides and HODs only)', () {
    testWidgets('the bar: percent, the change since last week, the stage; a tap opens each part with its reason', (tester) async {
      final data = FakeBoardData(users: roster)..surrenders['sg1'] = _info();
      await openBoard(tester, data: data);
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('surrender-bar')), findsOneWidget);
      expect(find.text('Surrender'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.text('↑ 6 vs last week'), findsOneWidget);
      expect(find.text('Deepen'), findsOneWidget);
      expect(find.textContaining('Committed to'), findsNothing, reason: '"committed to N rounds" is replaced by the bar');
      await tester.tap(find.byKey(const ValueKey('surrender-bar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('surrender-dialog-title')), findsOneWidget);
      expect(find.text('Arjun: Surrender 42%'), findsOneWidget);
      for (final k in ['commitment', 'sadhana', 'attitude', 'lit', 'bonus']) {
        expect(find.byKey(ValueKey('surrender-part-$k')), findsOneWidget, reason: k);
      }
      expect(find.text('Committed to 12 rounds and 30 min of reading a day.'), findsOneWidget, reason: 'a reason each');
      // every part: its points earned of the points possible (6 + 20 + 0 + 0 + 0 here)
      for (final e in {'commitment': '6 of 10', 'sadhana': '20 of 40', 'attitude': '0 of 20', 'lit': '0 of 20', 'bonus': '0 of 10'}.entries) {
        expect(find.descendant(of: find.byKey(ValueKey('surrender-part-${e.key}')), matching: find.text(e.value)), findsOneWidget, reason: e.key);
      }
      expect(find.text('No LIT yet → 0 of 20'), findsOneWidget);
      expect(find.textContaining('not enough data'), findsNothing, reason: 'that label is gone');
      expect(find.textContaining('the student never sees this'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('surrender-dialog-title')), findsNothing);
    });

    testWidgets('a fall shows ↓; no change shows no arrow; no document says there is not enough data yet; it updates live', (tester) async {
      final data = FakeBoardData(users: roster)..surrenders['sg1'] = _info(percent: 35, trend: -4);
      await openBoard(tester, data: data);
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      expect(find.text('↓ 4 vs last week'), findsOneWidget);
      data.surrenders['sg1'] = _info(percent: 35, trend: 0);
      data.surrenderC.add(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('surrender-trend')), findsNothing);
      data.surrenders['sg1'] = null;
      data.surrenderC.add(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('surrender-none')), findsOneWidget);
      expect(find.text('Surrender %: not worked out yet (it is calculated every night).'), findsOneWidget);
    });

    testWidgets('NOTHING SHOWN YET: a real number (never "not enough data"), every part "0 of N" with its reason, and a note that nothing is scaled up', (tester) async {
      final data = FakeBoardData(users: roster)
        ..surrenders['sg1'] = const SurrenderInfo(percent: 10, trend: null, cap: null, complete: false, residence: 'hostel', parts: [
          SurrenderPart(key: 'commitment', label: 'Commitment', weight: 10, score: 1, points: 10, reason: 'Committed to 16 rounds and 60 min of reading a day (16 rounds and 60 min is full).'),
          SurrenderPart(key: 'sadhana', label: 'Sadhana actually done', weight: 40, score: 0, points: 0, missing: true, reason: 'No reports in the last 30 days → 0 of 40'),
          SurrenderPart(key: 'attitude', label: 'Association — attitude & willingness', weight: 20, score: 0, points: 0, missing: true, reason: 'No interaction or meeting with his guide in the last 30 days → 0 of 20'),
          SurrenderPart(key: 'lit', label: 'LIT', weight: 20, score: 0, points: 0, missing: true, reason: 'No LIT yet → 0 of 20'),
          SurrenderPart(key: 'bonus', label: 'Bonus', weight: 10, score: 0, points: 0, reason: 'No bonus earned yet (it comes from the daily report forms, the last 30 days)'),
        ]);
      await openBoard(tester, data: data);
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('surrender-nodata')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('surrender-percent'))).data, '10%');
      await tester.tap(find.byKey(const ValueKey('surrender-bar')));
      await tester.pumpAndSettle();
      expect(find.text('Arjun: Surrender 10%'), findsOneWidget);
      expect(find.text('No reports in the last 30 days → 0 of 40'), findsOneWidget);
      expect(find.text('No LIT yet → 0 of 20'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('surrender-part-commitment')), matching: find.text('10 of 10')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('surrender-part-sadhana')), matching: find.text('0 of 40')), findsOneWidget);
      expect(find.byKey(const ValueKey('surrender-leftout')), findsOneWidget);
      expect(find.textContaining('not enough data'), findsNothing);
      expect(find.textContaining('counts '), findsNothing, reason: 'no scaled-up weights any more');
    });

    testWidgets('points show one decimal only when they have one', (tester) async {
      expect(surrenderPoints(31.5), '31.5');
      expect(surrenderPoints(40), '40');
      expect(surrenderPoints(2.04), '2');
      expect(surrenderPoints(0), '0');
    });

    testWidgets('the residence cap is explained in the breakdown (not in FOLK: at most 90%)', (tester) async {
      final data = FakeBoardData(users: roster)..surrenders['sg1'] = _info(percent: 90, cap: 'residence');
      await openBoard(tester, data: data);
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('surrender-bar')));
      await tester.pumpAndSettle();
      expect(find.textContaining('does not live in FOLK, so the most he can show is 90%'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: the bar, the breakdown and the history fit', (tester) async {
          final data = FakeBoardData(users: roster)..surrenders['sg1'] = _info();
          await openBoard(tester, data: data, scale: scale, dark: dark);
          await tester.tap(find.text('Arjun Kumar'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final r = tester.getRect(find.byKey(const ValueKey('surrender-bar')));
          expect(r.height, greaterThanOrEqualTo(48));
          expect(r.right, lessThanOrEqualTo(360));
          await tester.tap(find.byKey(const ValueKey('surrender-bar')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('guide-only: the number never reaches a student', () {
    test('the student app is another repo and no student-readable collection or function here carries it', () {
      final rules = File('../../functions/firestore.rules').readAsStringSync();
      for (final c in ['studentSurrender', 'interactionNeeds']) {
        final block = RegExp('match /$c/\\{studentUid\\} \\{[^}]*\\}').firstMatch(rules)!.group(0)!;
        expect(block.contains('isAdmin() && adminSeesScope(resource.data)'), isTrue, reason: c);
        expect(block.contains('allow write: if false'), isTrue, reason: c);
        expect(block.contains('isStudent()'), isFalse, reason: '$c: a student has no rule');
      }
    });
  });

  // ------------------------------------------------------------------------------------------------ the plans
  group('an interaction in the plan: one card per student, each topic a title and ONE line', () {
    const harsh = PlanItem(
      id: 'interaction:u1:2026-10-28',
      kind: 'interaction',
      title: 'Interaction with Harsh',
      studentName: 'Harsh',
      studentUid: 'u1',
      percent: 42,
      forYou: true,
      batchPosition: 1,
      also: 'Also: no report since 26 Oct',
      points: [
        PlanPoint(title: 'Worry', text: 'Sounded discouraged or worried in his AI chat — talk with him and listen first.', group: PlanGroup.worry, kind: 'concern'),
        PlanPoint(title: 'Chanting target', text: 'Chanting 12 of 16 for your target — talk about moving to 16.', group: PlanGroup.target, kind: 'target_chanting'),
        PlanPoint(title: 'Surrender 42%', text: 'Crossed 40% — encourage him to take the next step.', group: PlanGroup.followUp, kind: 'surrender'),
      ],
      cardGroups: [PlanGroup.worry, PlanGroup.target, PlanGroup.followUp],
    );

    PlanDoc doc() => PlanDoc(
          todayDate: '2026-10-30',
          todayItems: [harsh],
          weekOf: '2026-10-26',
          intro: '',
          sections: const [
            PlanSection(id: 'interactions', title: 'Interactions', items: [PlanItem(id: 'week:u2', kind: 'weekStudent', title: '', studentUid: 'u2', studentName: 'Kishan', scheduledFor: '2026-11-01')]),
          ],
          generatedAt: DateTime.utc(2026, 10, 30, 4, 10),
          status: 'upToDate',
          changedAt: DateTime.utc(2026, 10, 30, 4, 10),
          batch: const PlanBatch(size: 4, round: 1, members: 1, carried: 0, nextReady: false, done: 0, left: 1),
          progress: const PlanProgress(needed: 2, done: 0, left: 2, summary: '', bySource: []),
        );

    testWidgets('Today shows ONE card for Harsh: his name and %, each topic a title and ONE line, one "Also:" line; no questions, no talking points', (tester) async {
      await _openPlan(tester, doc: doc());
      await _openRows(tester);
      expect(find.text('Harsh'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-item-interaction:u1:2026-10-28')), findsOneWidget);
      for (final t in ['Worry', 'Chanting target', 'Surrender 42%']) {
        expect(find.text(t), findsNWidgets(2), reason: '$t: its chip and its topic');
      }
      expect(find.text('Sounded discouraged or worried in his AI chat — talk with him and listen first.'), findsOneWidget);
      expect(find.text('Chanting 12 of 16 for your target — talk about moving to 16.'), findsOneWidget);
      expect(find.text('Also: no report since 26 Oct'), findsOneWidget);
      for (final gone in ['Questions and suggestions', 'How are you feeling', 'Suggestion:', 'To share:', 'Why:', 'Encourage:']) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('once the guide has reported back, the item is ticked (a tick and "Done"), read-only as always', (tester) async {
      await _openPlan(tester, doc: _plan(done: true));
      expect(tester.widget<Icon>(find.byKey(const ValueKey('plan-check-interaction:u1:2026-10-28'))).icon, Icons.check_circle, reason: 'the task is ticked');
      expect(find.text('For you to do'), findsNothing, reason: 'it has been done');
      await tester.tap(find.byKey(const ValueKey('plan-check-interaction:u1:2026-10-28')), warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'the page is read-only: nothing to untick');
    });

    testWidgets('This week lists the student by name under his day, nothing else', (tester) async {
      await _openPlan(tester, doc: doc());
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pump();
      expect(find.text('Interactions'), findsOneWidget);
      expect(find.text('Kishan'), findsOneWidget);
      expect(find.text('Sun 1 Nov'), findsOneWidget);
      expect(find.text('Students who need you'), findsNothing, reason: 'the old approach section is gone');
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: the card, its lines and the week fit', (tester) async {
          await _openPlan(tester, scale: scale, dark: dark, doc: doc());
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // ------------------------------------------------------------------------------------------------ the removed buttons
  group('interactions are recorded only through the assistant', () {
    test('no "Add interaction" / "New interaction" button or sheet is left in the app', () {
      final assoc = File('lib/Pages/AssociationManager.dart').readAsStringSync();
      expect(assoc.contains('"Add interaction"'), isFalse);
      expect(assoc.contains('_openAddInteractionSheet'), isFalse);
      expect(assoc.contains("heroTag: 'addInteraction'"), isFalse);
      final logger = File('lib/Pages/InteractionLogger.dart').readAsStringSync();
      expect(logger.contains('_EntrySheet'), isFalse);
      expect(logger.contains('"New"'), isFalse);
      expect(logger.contains('Delete interaction'), isTrue, reason: 'deleting an interaction stays possible');
      expect(logger.contains('InteractionDetailPage'), isTrue, reason: 'viewing / editing a saved one stays');
    });

    test('the assistant saves the same interactionLogs record, with the per-topic answers and willingness', () {
      final writes = File('lib/agent/AgentWrites.dart').readAsStringSync();
      expect(writes.contains("'topicAnswers'") || writes.contains('topicAnswers:'), isTrue);
      expect(writes.contains('willingness'), isTrue);
      final actions = File('lib/actions/InteractionActions.dart').readAsStringSync();
      expect(actions.contains("'interactionLogs'"), isTrue);
      expect(actions.contains("'status': 'approved'"), isTrue, reason: 'nothing lost: the same record as before');
    });

    test('the old suggestion / priority computations are gone: the list is the server\'s four sources', () {
      expect(File('lib/utils/PriorityReasons.dart').existsSync(), isFalse);
      final actions = File('lib/actions/PriorityActions.dart').readAsStringSync();
      expect(actions.contains('never_logged'), isFalse);
      expect(actions.contains('stale_contact'), isFalse);
      expect(actions.contains('follow_up_due'), isFalse);
      expect(actions.contains("'interactionNeeds'"), isTrue);
    });
  });
}
