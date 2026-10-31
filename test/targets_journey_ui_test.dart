import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/AutoCalendar.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/PlanCalendar.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/PlanToday.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// TARGETS AS ONE JOURNEY in the Guide app: ONE card per student placed by his most important topic (a worry, then anything about a target, then follow-ups, then the rest); This week's ONE combined
// line ("Chanting 3 of 5 · Reading 2 of 4 · FOLK 1 of 3", each student's combined next step); every date of a target on the calendar (start, phase ends, end — "Target ended — choose" —, the students'
// target days, postponed target topics).

PlanPoint pt(String kind, PlanGroup group, {String title = 'x'}) => PlanPoint(kind: kind, title: title, text: 'x', group: group, id: '$kind:1');

PlanItem card(String uid, String name, List<PlanPoint> points) => PlanItem(
      id: 'interaction:$uid:2026-10-30',
      kind: 'interaction',
      title: 'Interaction with $name',
      studentName: name,
      studentUid: uid,
      points: points,
      cardGroups: [for (final g in PlanGroup.values) if (points.any((p) => p.group == g)) g],
    );

class _Plan extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
}

PlanDoc planOf({List<PlanItem> today = const [], List<PlanSection> sections = const []}) => PlanDoc(
      todayDate: '2026-10-30',
      todayItems: today,
      weekOf: '2026-10-26',
      intro: '',
      sections: sections,
      generatedAt: DateTime.utc(2026, 10, 30, 4),
      status: 'upToDate',
      changedAt: DateTime.utc(2026, 10, 30, 4),
    );

CompoundTarget tgt(String metric, {DateTime? created, DateTime? end}) => CompoundTarget.from('G', 't$metric', {
      'metric': metric,
      'studentCountGoal': 5,
      'perStudentValueGoal': 16,
      'status': 'active',
      'currentPhase': 2,
      'totalPhases': 4,
      'createdAt': Timestamp.fromDate(created ?? DateTime(2026, 10, 12)),
      'endDate': Timestamp.fromDate(end ?? DateTime(2026, 12, 31)),
    });

CompoundPhase phase(int n, String status, DateTime? started) => CompoundPhase.from('$n', {'phaseNumber': n, 'status': status, if (started != null) 'startedAt': Timestamp.fromDate(started), 'tasks': const []});

String day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  group('ONE CARD, placed by the most important topic', () {
    test('a worry first (Follow-ups); then anything about a target (Target tasks), including a FOLK invitation and a surrender check that carries it; then follow-ups; then the rest', () {
      String of(List<PlanPoint> p) => todaySectionOf(card('u', 'Ravi', p));
      expect(of([pt('concern', PlanGroup.worry), pt('target_chanting', PlanGroup.target)]), kSectionFollowUps, reason: 'a worry beats a target');
      expect(of([pt('target_chanting', PlanGroup.target), pt('doubt', PlanGroup.followUp)]), kSectionTargets, reason: 'a target beats a follow-up');
      expect(of([pt('target_folk', PlanGroup.target), pt('bookDue', PlanGroup.other)]), kSectionTargets, reason: 'the FOLK invitation is a target topic');
      expect(of([pt('surrender_check', PlanGroup.target), pt('bookDue', PlanGroup.other)]), kSectionTargets, reason: '40% reached + the FOLK target: ONE card in Target tasks (the check carries the FOLK point)');
      expect(of([pt('doubt', PlanGroup.followUp), pt('bookDue', PlanGroup.other)]), kSectionFollowUps);
      expect(of([pt('bookDue', PlanGroup.other), pt('surrender_check', PlanGroup.other)]), kSectionOthers);
    });

    test('ONE student is ONE task in the view, however many topics he has', () {
      final v = TodayView.of(planOf(today: [
        card('k', 'Kiran', [pt('target_chanting', PlanGroup.target), pt('surrender_check', PlanGroup.target), pt('bookDue', PlanGroup.other), pt('doubt', PlanGroup.followUp)]),
      ]));
      expect(v.total, 1);
      expect(v.section(kSectionTargets).tasks.single.studentName, 'Kiran');
      expect(v.section(kSectionFollowUps).total + v.section(kSectionOthers).total, 0);
    });
  });

  group('THIS WEEK: one combined picture', () {
    testWidgets('the combined line with each pending student\'s combined next step is shown; a target\'s own line it already says is not shown twice', (tester) async {
      AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []}));
      final data = _Plan();
      PlanData.instance = data;
      await pumpScreen(tester, const PlanPage(initialWeek: true), size: const Size(360, 3000));
      data.controller.add(planOf(sections: [
        PlanSection(id: 'targettasks', title: 'Target tasks', items: [
          const PlanItem(id: 'weekjourney', kind: 'weekTask', title: 'Chanting 3 of 5 · FOLK 1 of 3', steps: [PlanStep(name: 'Amit', from: 0, to: 0, label: 'Amit — 12 → 16 · invite to FOLK (direct)')]),
          const PlanItem(id: 'weektarget:tc', kind: 'weekTask', title: 'Chanting 16 by 30 Nov', inCombined: true, steps: [PlanStep(name: 'Amit', from: 12, to: 16)]),
        ]),
      ]));
      await tester.pump();
      await tester.pump();
      expect(find.text('Chanting 3 of 5 · FOLK 1 of 3'), findsOneWidget);
      expect(find.text('Amit — 12 → 16 · invite to FOLK (direct)'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-week-task-weektarget:tc')), findsNothing, reason: 'said by the combined line');
      expect(find.text('Chanting 16 by 30 Nov'), findsNothing);
    });

    testWidgets('without a combined line (an older plan) the target\'s own line is shown as before', (tester) async {
      AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []}));
      final data = _Plan();
      PlanData.instance = data;
      await pumpScreen(tester, const PlanPage(initialWeek: true), size: const Size(360, 3000));
      data.controller.add(planOf(sections: [
        PlanSection(id: 'targettasks', title: 'Target tasks', items: [
          const PlanItem(id: 'weektarget:tc', kind: 'weekTask', title: 'Chanting 16 by 30 Nov', steps: [PlanStep(name: 'Amit', from: 12, to: 16)]),
        ]),
      ]));
      await tester.pump();
      await tester.pump();
      expect(find.text('Chanting 16 by 30 Nov'), findsOneWidget);
      expect(find.text('Amit 12 → 16'), findsOneWidget);
    });
  });

  group('EVERY TARGET DATE ON THE CALENDAR', () {
    final today = DateTime(2026, 10, 30);

    test('start, the end of each phase (the running one a week from its start, the next planned a week after), and the end date', () {
      final phases = [phase(1, 'achieved', DateTime(2026, 10, 12)), phase(2, 'active', DateTime(2026, 10, 26)), phase(3, 'pending', null), phase(4, 'pending', null)];
      final ev = targetEvents('G', tgt('chanting'), phases[1], phases: phases, today: today);
      String line(CalendarEvent e) => '${day(e.eventDate)} ${e.title}';
      expect(ev.map(line), [
        '2026-10-12 Target starts: chanting',
        '2026-12-31 Target deadline: chanting',
        '2026-10-18 Phase 1 ends: chanting',
        '2026-11-01 Phase 2 ends: chanting',
        '2026-11-08 Phase 3 ends: chanting (planned)',
        '2026-11-15 Phase 4 ends: chanting (planned)',
      ]);
      expect(ev.every((e) => e.section == 'targets'), isTrue);
      expect(ev.firstWhere((e) => e.title.startsWith('Phase 1')).done, isTrue, reason: 'a finished phase is ticked');
    });

    test('an end date that has been reached reads "Target ended — choose"; a phase never ends after the deadline; the FOLK target has its label', () {
      final ended = targetEvents('G', tgt('folk', end: DateTime(2026, 10, 30)), null, today: today);
      expect(ended.map((e) => e.title), contains('Target ended — choose: FOLK'));
      expect(ended.firstWhere((e) => e.title.startsWith('Target ended')).note, 'Delete it or extend its end date.');
      final capped = targetEvents('G', tgt('chanting', end: DateTime(2026, 10, 29)), phase(2, 'active', DateTime(2026, 10, 26)), phases: [phase(2, 'active', DateTime(2026, 10, 26))], today: DateTime(2026, 10, 20));
      expect(day(capped.firstWhere((e) => e.title.startsWith('Phase 2')).eventDate), '2026-10-29');
      expect(targetEvents('G', tgt('chanting'), null, today: today).map((e) => e.title), ['Target starts: chanting', 'Target deadline: chanting']);
    });

    test('a student coming for a target is a TARGET day in This week: his entry names the targets and sits with the target tasks; the combined line is not drawn (each target has its band)', () {
      final plan = planOf(sections: [
        PlanSection(id: 'interactions', title: 'Interactions', items: [
          const PlanItem(id: 'week:a', kind: 'weekStudent', title: '', studentUid: 'a', studentName: 'Amit', scheduledFor: '2026-10-31', topicLabels: ['Chanting target', 'FOLK target']),
          const PlanItem(id: 'week:b', kind: 'weekStudent', title: '', studentUid: 'b', studentName: 'Bala', scheduledFor: '2026-10-31', topicLabels: ['Doubt']),
        ]),
        PlanSection(id: 'targettasks', title: 'Target tasks', items: [
          const PlanItem(id: 'weekjourney', kind: 'weekTask', title: 'Chanting 3 of 5'),
          const PlanItem(id: 'weektarget:tc', kind: 'weekTask', title: 'Chanting 16 by 30 Nov', inCombined: true),
        ]),
      ]);
      final ev = planCalendarEvents(plan);
      final amit = ev.firstWhere((e) => e.studentUid == 'a');
      expect([amit.title, amit.section], ['Interaction: Amit — Chanting target, FOLK target', 'targets']);
      final bala = ev.firstWhere((e) => e.studentUid == 'b');
      expect([bala.title, bala.section], ['Interaction: Bala', 'followups']);
      expect(ev.any((e) => e.id == 'plan_target_weekjourney'), isFalse);
      expect(ev.any((e) => e.id == 'plan_target_weektarget:tc'), isTrue);
    });

    test('postponed (Later) target topics come back on their date among the target tasks; done early is ticked', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('topicPostponements').doc('a__target:chanting').set({'studentUid': 'a', 'studentName': 'Amit', 'key': 'target:chanting', 'label': 'raise to 16 rounds', 'date': '2026-11-15', 'scopeGuide': 'G'});
      await db.collection('topicPostponements').doc('a__target:folk').set({'studentUid': 'a', 'studentName': 'Amit', 'key': 'target:folk', 'label': 'FOLK invitation', 'date': '2026-11-20', 'resolvedDay': '2026-11-18', 'resolvedText': 'Came to stay', 'scopeGuide': 'G'});
      await db.collection('topicPostponements').doc('b__doubt').set({'studentUid': 'b', 'studentName': 'Bala', 'key': 'doubt', 'label': 'his doubt', 'date': '2026-11-16', 'scopeGuide': 'G'});
      final ev = laterEvents((await db.collection('topicPostponements').get()).docs);
      Map<String, CalendarEvent> by() => {for (final e in ev) e.studentUid + e.title: e};
      final chant = ev.firstWhere((e) => e.title == 'Amit — raise to 16 rounds');
      expect([day(chant.eventDate), chant.section, chant.done], ['2026-11-15', 'targets', false]);
      final folk = ev.firstWhere((e) => e.title.startsWith('✓ Done early: Amit — FOLK'));
      expect([folk.section, folk.done], ['targets', true]);
      expect(ev.firstWhere((e) => e.studentUid == 'b').section, 'followups');
      expect(by().length, 3);
    });
  });
}
