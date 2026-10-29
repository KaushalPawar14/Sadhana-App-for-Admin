import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

import 'support/guide_test_support.dart';

/// PLANS — PRACTICAL DAILY BATCHES in the Guide app: Today is a batch of students (each with why, how to meet him, the questions, what to
/// encourage and "After talking, report his answers to the AI."), a tick on report-back, "Next 4 ready", "Carried over"; This week is the
/// progress picture (needed · done · left, per source) with every student's planned day; the guide's own "Students a day" number.

final DateTime _now = DateTime.utc(2026, 10, 30, 4, 30);

class _FakePlanData extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => _now;
}

PlanItem _student(String uid, String name, int pos, {bool done = false, bool carried = false, String how = 'In person — he lives in FOLK.'}) => PlanItem(
      id: 'interaction:$uid:2026-10-28',
      kind: 'interaction',
      title: 'Interaction with $name',
      detail: 'Why: Not fulfilling his commitments for 3 days.',
      studentName: name,
      forYou: true,
      done: done,
      how: how,
      encourage: const ['Agree a date, not a promise of everything.'],
      reportBack: 'After talking, report his answers to the AI.',
      carriedOver: carried,
      batchPosition: pos,
      batchRound: 1,
      topics: const [
        PlanTopic(key: 'sadhana_slip', label: 'His sadhana', reason: 'Not fulfilling his commitments for 3 days', questions: ['Why do you think it has been hard these days?', 'When do you think it will improve?', 'When will you be chanting your 16 rounds again?'], suggestions: ['Keep it simple and kind.']),
      ],
    );

PlanDoc _plan({List<PlanItem>? today, PlanBatch? batch, PlanProgress? progress, List<PlanSection>? sections}) => PlanDoc(
      todayDate: '2026-10-30',
      todayItems: today ??
          [
            _student('u1', 'Ravi', 1, carried: true),
            _student('u2', 'Amit', 2),
            _student('u3', 'Kishan', 3, how: 'By call or online — he is a localite; check with him before suggesting a visit.'),
            _student('u4', 'Mohit', 4, done: true),
            const PlanItem(id: 'meeting:u9:2026-10-30', kind: 'meeting', title: 'Meet Harsh', detail: 'A confirmed meeting.', forYou: true),
            const PlanItem(id: 'doubts_to_answer::2026-10-30', kind: 'doubtsToAnswer', title: '2 doubts waiting for your answer', detail: 'Ravi, Amit.', forYou: true),
          ],
      weekOf: '2026-10-26',
      intro: 'Hare Krishna Gopal! 16 students need an interaction (4 done this week), about 4 a day.',
      sections: sections ??
          [
            const PlanSection(id: 'interactions', title: 'Students to contact — planned days', items: [
              PlanItem(id: 'interaction:u1:2026-10-28', kind: 'interaction', title: 'Interaction with Ravi', detail: 'Why: Not fulfilling his commitments for 3 days.', studentName: 'Ravi', scheduledFor: '2026-10-30', inToday: true, topicLabels: ['His sadhana'], how: 'In person — he lives in FOLK.'),
              PlanItem(id: 'interaction:u5:2026-10-28', kind: 'interaction', title: 'Interaction with Sohan', detail: 'Why: Chanting target.', studentName: 'Sohan', scheduledFor: '2026-10-31', topicLabels: ['Chanting target', 'His doubt'], how: 'In person (he lives in a hostel), or by call.'),
            ]),
          ],
      generatedAt: _now.subtract(const Duration(minutes: 20)),
      status: 'upToDate',
      pendingRunAt: null,
      changedAt: _now,
      batch: batch ?? const PlanBatch(size: 4, round: 1, members: 4, carried: 1, nextReady: false, done: 1, left: 3),
      progress: progress ??
          const PlanProgress(needed: 20, done: 4, left: 16, summary: 'Interactions needed: 20 · done 4 · left 16', bySource: [
            PlanSourceProgress(id: 'target', label: 'Targets', needed: 6, done: 1, left: 5),
            PlanSourceProgress(id: 'sadhana', label: 'Sadhana', needed: 9, done: 2, left: 7),
            PlanSourceProgress(id: 'doubts', label: 'Doubts and concerns', needed: 3, done: 1, left: 2),
            PlanSourceProgress(id: 'surrender', label: 'Surrender steps', needed: 2, done: 0, left: 2),
          ]),
    );

AdminProfile _me() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

Future<_FakePlanData> _open(WidgetTester tester, {double scale = 1.0, bool dark = false, PlanDoc? doc, bool tall = true}) async {
  phone(tester, scale, size: tall ? const Size(360, 3200) : const Size(360, 800));
  AdminProfileProvider.instance.debugSet(_me());
  final data = _FakePlanData();
  PlanData.instance = data;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(guideHost(const PlanPage(), dark: dark));
  data.controller.add(doc ?? _plan());
  await tester.pump();
  await tester.pump();
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDown(() => HierarchyApi.useForTests(null));
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  testWidgets('TODAY: the batch card (done · left), each student with his place, why, how, questions open, what to encourage and the report-back line', (tester) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('plan-batch')), findsOneWidget);
    expect(find.text('done 1 · left 3'), findsOneWidget);
    expect(find.text('Student 1 of 4'), findsOneWidget);
    expect(find.text('Student 3 of 4'), findsOneWidget);
    expect(find.text('Interaction with Ravi'), findsOneWidget);
    expect(find.text('In person — he lives in FOLK.'), findsWidgets);
    expect(find.textContaining('By call or online — he is a localite'), findsOneWidget);
    expect(find.text('Why: Not fulfilling his commitments for 3 days.'), findsWidgets);
    // the questions are already open (the guide goes through them with the student)
    expect(find.text('1. Why do you think it has been hard these days?'), findsWidgets);
    expect(find.text('Encourage: Keep it simple and kind.'), findsWidgets);
    expect(find.text('After talking, report his answers to the AI.'), findsNWidgets(3), reason: 'on every student still to talk to, not on the one already done');
    expect(find.byKey(const ValueKey('plan-report-interaction:u4:2026-10-28')), findsNothing);
  });

  testWidgets('a student the guide has reported to the AI shows a tick; "Carried over" marks one from an earlier day', (tester) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('plan-done-interaction:u4:2026-10-28')), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-carried-interaction:u1:2026-10-28')), findsOneWidget);
    expect(find.text('Carried over'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-carried-note')), findsOneWidget);
  });

  testWidgets('the questions can be hidden and shown again with a tap', (tester) async {
    await _open(tester);
    final toggle = find.byKey(const ValueKey('plan-topics-toggle-interaction:u1:2026-10-28'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-topics-interaction:u1:2026-10-28')), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-topics-interaction:u1:2026-10-28')), findsOneWidget);
  });

  testWidgets('the other one-day items are short and separate, under "Also today"', (tester) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('plan-also-today')), findsOneWidget);
    expect(find.text('Meet Harsh'), findsOneWidget);
    expect(find.text('2 doubts waiting for your answer'), findsOneWidget);
    final alsoY = tester.getTopLeft(find.byKey(const ValueKey('plan-also-today'))).dy;
    expect(tester.getTopLeft(find.text('Interaction with Mohit')).dy, lessThan(alsoY), reason: 'the batch comes first');
  });

  testWidgets('"Next 4 ready" shows after a refill; a day with nobody to contact says so', (tester) async {
    await _open(tester, doc: _plan(batch: const PlanBatch(size: 4, round: 2, members: 8, carried: 0, nextReady: true, done: 4, left: 4)));
    expect(find.byKey(const ValueKey('plan-next-ready')), findsOneWidget);
    expect(find.text('Next 4 ready'), findsOneWidget);
    expect(find.text('done 4 · left 4'), findsOneWidget);
    await _open(tester, doc: _plan(today: const [], batch: const PlanBatch(size: 4, round: 1, members: 0, carried: 0, nextReady: false, done: 0, left: 0)));
    expect(find.text('none needed'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-today-empty')), findsOneWidget);
  });

  testWidgets('STUDENTS A DAY: the guide changes the number (saved on the server); it shows at once; 1 and 12 are the limits', (tester) async {
    final calls = <Map<String, dynamic>>[];
    HierarchyApi.useForTests((name, data) async {
      if (name == 'savePlanSettings') calls.add(data);
      return {'ok': true};
    });
    await _open(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-size'))).data, '4');
    await tester.tap(find.byKey(const ValueKey('plan-size-more')));
    await tester.pump();
    await tester.pump();
    expect(calls, [
      {'dailyBatch': 5}
    ]);
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-size'))).data, '5');
    await tester.tap(find.byKey(const ValueKey('plan-size-less')));
    await tester.pump();
    await tester.pump();
    expect(calls.last, {'dailyBatch': 4});
    // the limits
    await _open(tester, doc: _plan(batch: const PlanBatch(size: 1, round: 1, members: 1, carried: 0, nextReady: false, done: 0, left: 1)));
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('plan-size-less'))).onPressed, isNull);
    await _open(tester, doc: _plan(batch: const PlanBatch(size: 12, round: 1, members: 12, carried: 0, nextReady: false, done: 0, left: 12)));
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('plan-size-more'))).onPressed, isNull);
  });

  testWidgets('a failed save puts the old number back and says why', (tester) async {
    HierarchyApi.useForTests((name, data) async => throw HierarchyException('invalid-argument', 'Choose a number from 1 to 12.'));
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('plan-size-more')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Choose a number from 1 to 12.'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-size'))).data, '4');
  });

  testWidgets('THIS WEEK: "Interactions needed: 20 · done 4 · left 16", the four sources with their own counts, and every student with his planned day', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-progress')), findsOneWidget);
    expect(find.text('Interactions needed: 20 · done 4 · left 16'), findsOneWidget);
    for (final l in ['Targets', 'Sadhana', 'Doubts and concerns', 'Surrender steps']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.text('done 2 · left 7'), findsOneWidget);
    expect(find.text('Students to contact — planned days'), findsOneWidget);
    expect(find.text('Fri 30 Oct'), findsOneWidget, reason: 'today for the batch');
    expect(find.text('Sat 31 Oct'), findsOneWidget, reason: "tomorrow's students");
    expect(find.text('Topics: Chanting target, His doubt'), findsOneWidget);
    expect(find.text("In today's batch"), findsOneWidget);
    expect(find.text('Students a day'), findsNothing, reason: 'the number is set on Today');
    expect(find.textContaining('How are you'), findsNothing, reason: 'no questions in the week list: they are in Today');
  });

  testWidgets('a HOD plan (no batch, no progress) still shows as before', (tester) async {
    await _open(tester, doc: PlanDoc(todayDate: '2026-10-30', todayItems: const [PlanItem(id: 'guide:G', kind: 'guideSummary', title: 'Gopal: 0 for today, 3 interactions needed')], weekOf: '2026-10-26', intro: 'Hare Krishna', sections: const [], generatedAt: _now, status: 'upToDate', pendingRunAt: null, changedAt: _now));
    expect(find.byKey(const ValueKey('plan-batch')), findsNothing);
    expect(find.text('Gopal: 0 for today, 3 interactions needed'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-progress')), findsNothing);
  });

  group('every state: light and dark, text scale 1.0 / 1.3 / 1.6, no overflow', () {
    for (final dark in [false, true]) {
      for (final scale in kScales) {
        for (final tab in ['today', 'week']) {
          testWidgets('${dark ? 'dark' : 'light'}, ×$scale, $tab', (tester) async {
            await _open(tester, scale: scale, dark: dark, tall: false);
            if (tab == 'week') {
              await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            await tester.scrollUntilVisible(find.byType(Text).last, 100, scrollable: find.byType(Scrollable).first);
            expect(tester.takeException(), isNull);
            for (final k in ['plan-size-less', 'plan-size-more']) {
              if (tab == 'today') expect(tester.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48), reason: k);
            }
          });
        }
      }
    }

    testWidgets('screenshots: Today and This week (for looking at)', (tester) async {
      for (final dark in [false, true]) {
        await _open(tester, dark: dark, tall: false);
        await shot(tester, 'plan_batch_today_${dark ? 'dark' : 'light'}');
        await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
        await tester.pumpAndSettle();
        await shot(tester, 'plan_batch_week_${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
