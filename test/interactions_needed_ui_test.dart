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
      pendingRunAt: null,
      changedAt: _now,
    );

AdminProfile _me() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

Future<void> _openPlan(WidgetTester tester, {double scale = 1.0, bool dark = false, PlanDoc? doc}) async {
  phone(tester, scale);
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
      parts: const [
        SurrenderPart(key: 'commitment', label: 'Commitment', weight: 20, score: 0.6, reason: 'Committed to 12 rounds and 30 min of reading a day.'),
        SurrenderPart(key: 'sadhana', label: 'Sadhana actually done', weight: 40, score: 0.5, reason: 'Last 30 days: rounds 70% of 16.'),
        SurrenderPart(key: 'association', label: 'Association with his guide', weight: 15, score: 0.8, reason: '2 interactions in the last 30 days.'),
        SurrenderPart(key: 'attitude', label: 'Attitude and willingness', weight: 15, score: null, reason: 'No guide\'s observation of his willingness yet (not enough data).'),
        SurrenderPart(key: 'lit', label: 'LIT', weight: 10, score: null, reason: 'No complete LIT assessment yet (not enough data).'),
      ],
    );

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
      for (final k in ['commitment', 'sadhana', 'association', 'attitude', 'lit']) {
        expect(find.byKey(ValueKey('surrender-part-$k')), findsOneWidget, reason: k);
      }
      expect(find.text('Committed to 12 rounds and 30 min of reading a day.'), findsOneWidget, reason: 'a reason each');
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('not enough data'), findsNWidgets(2), reason: 'a missing part is not a failure');
      expect(find.text('20% of the total'), findsOneWidget);
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

    testWidgets('truly no reports and no commitment: "not enough data yet" with a tap for why (each missing part has its reason); parts left out are scaled up', (tester) async {
      const noData = SurrenderInfo(
        percent: 0, trend: null, cap: null, complete: false, residence: 'hostel', noData: true,
        parts: [
          SurrenderPart(key: 'commitment', label: 'Commitment', weight: 20, score: null, reason: 'No commitment recorded yet — this part is left out, the others count a little more.'),
          SurrenderPart(key: 'sadhana', label: 'Sadhana actually done', weight: 40, score: null, reason: 'No sadhana reports in the last 30 days — this part is left out, the others count a little more.'),
          SurrenderPart(key: 'association', label: 'Association with his guide', weight: 15, score: null, reason: 'No interactions yet — this part is left out, the others count a little more.'),
          SurrenderPart(key: 'attitude', label: 'Attitude and willingness', weight: 15, score: null, reason: 'No guide\'s report of his willingness yet, and no services or trips.'),
          SurrenderPart(key: 'lit', label: 'LIT', weight: 10, score: null, reason: 'No LIT yet — this part is left out, the others count a little more.'),
        ],
      );
      final data = FakeBoardData(users: roster)..surrenders['sg1'] = noData;
      await openBoard(tester, data: data);
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('surrender-percent')), findsNothing, reason: 'no made-up 0%');
      expect(find.byKey(const ValueKey('surrender-nodata')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('surrender-nodata')));
      await tester.pumpAndSettle();
      expect(find.text('Arjun: not enough data yet'), findsOneWidget);
      expect(find.textContaining('No LIT yet'), findsOneWidget);
      expect(find.textContaining('No interactions yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('surrender-leftout')), findsOneWidget);
      // a percent worked out from whatever exists: the parts with data count for more, and the page says so
      data.surrenders['sg1'] = const SurrenderInfo(percent: 66, trend: null, cap: null, complete: false, residence: 'hostel', parts: [
        SurrenderPart(key: 'commitment', label: 'Commitment', weight: 20, score: 0.6, reason: 'Committed.', effectiveWeight: 33.3),
        SurrenderPart(key: 'sadhana', label: 'Sadhana actually done', weight: 40, score: 0.7, reason: 'Last 30 days.', effectiveWeight: 66.7),
        SurrenderPart(key: 'lit', label: 'LIT', weight: 10, score: null, reason: 'No LIT yet — this part is left out, the others count a little more.'),
      ]);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      data.surrenderC.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('surrender-bar')));
      await tester.pumpAndSettle();
      expect(find.text('counts 33.3% (20% when every part is known)'), findsOneWidget);
      expect(find.text('counts 66.7% (40% when every part is known)'), findsOneWidget);
      expect(find.byKey(const ValueKey('surrender-leftout')), findsOneWidget);
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
  group('an interaction in the plan: one card per student, a section for each topic', () {
    testWidgets('Today shows ONE card for Harsh with every reason; the questions open with a tap, a section per topic', (tester) async {
      await _openPlan(tester);
      expect(find.text('Interaction with Harsh'), findsOneWidget);
      expect(find.textContaining('Why: Sounded discouraged or worried'), findsOneWidget);
      expect(find.text('Surrender 42%'), findsOneWidget);
      expect(find.text('Questions and suggestions (3 topics)'), findsOneWidget);
      expect(find.text('How are you feeling, Harsh?'), findsNothing, reason: 'closed until tapped');
      await tester.tap(find.byKey(const ValueKey('plan-topics-toggle-interaction:u1:2026-10-28')));
      await tester.pump();
      for (final label in ['His worry', 'Chanting target', 'Surrender step']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('1. How are you feeling, Harsh?'), findsOneWidget);
      expect(find.text('2. What is stopping you from chanting more?'), findsOneWidget);
      expect(find.text('Suggestion: Listen first; do not correct or push.'), findsOneWidget);
      expect(find.text('To share: Surrender grows through regular sadhana, service and association.'), findsOneWidget);
      expect(find.text('Surrender is not giving up something; it is giving ourselves in service.'), findsOneWidget);
      expect(find.text('Hide the questions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-topics-toggle-interaction:u1:2026-10-28')));
      await tester.pump();
      expect(find.text('1. How are you feeling, Harsh?'), findsNothing);
    });

    testWidgets('a plain (fallback) brief says so; the AI one does not', (tester) async {
      await _openPlan(tester, doc: _plan(source: 'fallback'));
      await tester.tap(find.byKey(const ValueKey('plan-topics-toggle-interaction:u1:2026-10-28')));
      await tester.pump();
      expect(find.text('A plain version: the AI had not written these yet.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _openPlan(tester, doc: _plan());
      await tester.tap(find.byKey(const ValueKey('plan-topics-toggle-interaction:u1:2026-10-28')));
      await tester.pump();
      expect(find.text('A plain version: the AI had not written these yet.'), findsNothing);
    });

    testWidgets('once the guide has reported back, the item is ticked (a tick and "Done"), read-only as always', (tester) async {
      await _openPlan(tester, doc: _plan(done: true));
      expect(find.byKey(const ValueKey('plan-done-interaction:u1:2026-10-28')), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('For you to do'), findsNothing, reason: 'it has been done');
      await tester.tap(find.byKey(const ValueKey('plan-done-interaction:u1:2026-10-28')));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'the page is read-only: nothing to untick');
    });

    testWidgets('This week lists the scheduled interaction with its day, in the "Interactions needed" section', (tester) async {
      await _openPlan(tester);
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pump();
      expect(find.text('Interactions needed'), findsOneWidget);
      expect(find.text('Interaction with Kishan'), findsOneWidget);
      expect(find.text('Sun 1 Nov'), findsOneWidget);
      expect(find.text('Students who need you'), findsNothing, reason: 'the old approach section is gone');
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: the interaction card and its questions fit', (tester) async {
          await _openPlan(tester, scale: scale, dark: dark);
          await tester.tap(find.byKey(const ValueKey('plan-topics-toggle-interaction:u1:2026-10-28')));
          await tester.pump();
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
