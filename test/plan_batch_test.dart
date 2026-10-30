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
  _FakePlanData({this.needs = const {}});
  final Map<String, List<String>> needs;
  @override
  Future<List<String>> needsOf(String studentUid) async => needs[studentUid] ?? const [];
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => _now;
}

PlanItem _student(String uid, String name, int pos, {bool done = false, bool carried = false, int? percent}) => PlanItem(
      id: 'interaction:$uid:2026-10-28',
      kind: 'interaction',
      title: 'Interaction with $name',
      studentName: name,
      studentUid: uid,
      forYou: true,
      done: done,
      percent: percent,
      carriedOver: carried,
      batchPosition: pos,
      batchRound: 1,
      points: const [PlanPoint(title: 'Chanting', text: 'Chanting under 16 rounds on 5 days — talk with him and help resolve it.', group: PlanGroup.followUp, kind: 'sadhana_slip')],
      cardGroups: const [PlanGroup.followUp],
    );

PlanDoc _plan({List<PlanItem>? today, PlanBatch? batch, PlanProgress? progress, List<PlanSection>? sections}) => PlanDoc(
      todayDate: '2026-10-30',
      todayItems: today ??
          [
            _student('u1', 'Ravi', 1, carried: true, percent: 42),
            _student('u2', 'Amit', 2),
            _student('u3', 'Kishan', 3),
            _student('u4', 'Mohit', 4, done: true),
            const PlanItem(id: 'meeting:u9:2026-10-30', kind: 'meeting', title: 'Meet Harsh', detail: 'A confirmed meeting.', forYou: true),
          ],
      weekOf: '2026-10-26',
      intro: '',
      sections: sections ??
          const [
            PlanSection(id: 'interactions', title: 'Interactions', items: [
              PlanItem(id: 'week:u1', kind: 'weekStudent', title: '', studentUid: 'u1', studentName: 'Ravi', percent: 42, scheduledFor: '2026-10-30', inToday: true),
              PlanItem(id: 'week:u2', kind: 'weekStudent', title: '', studentUid: 'u2', studentName: 'Amit', scheduledFor: '2026-10-30', inToday: true),
              PlanItem(id: 'week:u4', kind: 'weekStudent', title: '', studentUid: 'u4', studentName: 'Mohit', scheduledFor: '2026-10-30', done: true),
              PlanItem(id: 'week:u5', kind: 'weekStudent', title: '', studentUid: 'u5', studentName: 'Sohan', percent: 12, scheduledFor: '2026-10-31'),
              PlanItem(id: 'week:u6', kind: 'weekStudent', title: '', studentUid: 'u6', studentName: 'Deep', scheduledFor: '2026-10-31'),
            ]),
            PlanSection(id: 'targettasks', title: 'Target tasks', items: [PlanItem(id: 'tt1', kind: 'weekTask', title: 'Chanting 16 by Mon 30 Nov: 2 of 5 students'), PlanItem(id: 'tt2', kind: 'weekTask', title: 'Bring FOLK residents 3 → 5')]),
            PlanSection(id: 'othertasks', title: 'Other tasks', items: [PlanItem(id: 'ot1', kind: 'weekOther', title: 'Meeting: Harsh', scheduledFor: '2026-10-30'), PlanItem(id: 'ot2', kind: 'weekOther', title: 'Book deadline: Ravi, Gita', scheduledFor: '2026-11-01')]),
          ],
      generatedAt: _now.subtract(const Duration(minutes: 20)),
      status: 'upToDate',
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

  testWidgets('THIS WEEK is a clean overview: the totals, the interactions DAY BY DAY (names only, done ones ticked), target tasks, other tasks; no advice', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-progress-summary'))).data, 'Interactions this week: 20 · done 4 · left 16');
    // day by day, in order
    expect(find.byKey(const ValueKey('plan-week-day-2026-10-30')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-week-day-2026-10-31')), findsOneWidget);
    double y(String k) => tester.getTopLeft(find.byKey(ValueKey(k))).dy;
    expect(y('plan-week-day-2026-10-30'), lessThan(y('plan-week-day-2026-10-31')));
    expect(find.text('Fri 30 Oct'), findsWidgets);
    expect(find.text('Sat 31 Oct'), findsOneWidget);
    for (final uid in ['u1', 'u2', 'u4', 'u5', 'u6']) {
      expect(find.byKey(ValueKey('plan-week-name-$uid')), findsOneWidget, reason: uid);
    }
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    // the done one is ticked, the others are not
    expect(find.byKey(const ValueKey('plan-week-tick-u4')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-week-tick-u1')), findsNothing);
    // the two short lists
    expect(find.text('Chanting 16 by Mon 30 Nov: 2 of 5 students'), findsOneWidget);
    expect(find.text('Bring FOLK residents 3 → 5'), findsOneWidget);
    expect(find.text('Meeting: Harsh'), findsOneWidget);
    expect(find.text('Book deadline: Ravi, Gita'), findsOneWidget);
    expect(find.text('Sun 1 Nov'), findsOneWidget, reason: 'with its date');
    // no advice, no details, no questions, no topics
    for (final gone in ['talk with him', 'Chanting under', 'Why:', 'Topics:', 'How are you', 'In person', 'Students a day', 'Surrender steps', 'Sadhana']) {
      expect(find.textContaining(gone), findsNothing, reason: gone);
    }
  });

  testWidgets('THIS WEEK: a tap on a name opens that student\'s card in Today (scrolled to); a student planned for another day opens his open topics', (tester) async {
    HierarchyApi.useForTests((name, data) async => {'ok': true});
    PlanData.instance = _FakePlanData(needs: {'u5': ['Chanting target: at 12 rounds, the phase asks for 16']});
    final data = PlanData.instance as _FakePlanData;
    phone(tester, 1.0, size: const Size(360, 700));
    AdminProfileProvider.instance.debugSet(_me());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(guideHost(const PlanPage(initialWeek: true)));
    data.controller.add(_plan());
    await tester.pump();
    await tester.pump();
    // Ravi has a card in Today: the page goes to Today
    await tester.tap(find.byKey(const ValueKey('plan-week-name-u1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-summary')), findsOneWidget, reason: 'the Today tab is showing');
    expect(find.byKey(const ValueKey('plan-item-interaction:u1:2026-10-28')), findsOneWidget, reason: 'his section opened and the card is there');
    // Sohan is planned for tomorrow: a small dialog with his open topics
    await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-week-name-u5')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-student-dialog-title')), findsOneWidget);
    expect(find.text('Sohan · 12%'), findsOneWidget);
    expect(find.textContaining('Planned for Saturday 31 October'), findsOneWidget);
    expect(find.text('• Chanting target: at 12 rounds, the phase asks for 16'), findsOneWidget);
  });

  testWidgets('a HOD plan (no batch, no progress) still shows: with zero counts, never missing ones', (tester) async {
    await _open(tester, doc: PlanDoc(todayDate: '2026-10-30', todayItems: const [PlanItem(id: 'guide:G', kind: 'guideSummary', title: 'Gopal: 0 for today, 3 interactions needed')], weekOf: '2026-10-26', intro: 'Hare Krishna', sections: const [], generatedAt: _now, status: 'upToDate', changedAt: _now));
    expect(find.text('Total tasks today: 0 · Done 0 · Left 0'), findsOneWidget);
    expect(find.text('Gopal: 0 for today, 3 interactions needed'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-progress')), findsOneWidget);
    expect(find.text('Interactions this week: 0 · done 0 · left 0'), findsOneWidget);
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
            if (tab == 'today') {
              for (final id in ['followups', 'targets', 'others']) {
                expect(tester.getSize(find.byKey(ValueKey('plan-section-$id'))).height, greaterThanOrEqualTo(48), reason: 'the section header is a 48 dp target');
              }
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
