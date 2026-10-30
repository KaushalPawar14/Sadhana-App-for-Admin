import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/PlanTopicActions.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// THE SURRENDER CHECK on Today: one topic on the student's single card (Other tasks), titled with the direction and level, carried over since its first
/// day, with the points to discuss and the data gaps (each with its own button, ticked by itself when the data is there); done = struck through and visible.

class _FakePlanData extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PendingChanges> pending(String adminId) => const Stream.empty();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => DateTime.utc(2026, 10, 30, 4, 30);
}

const _title = 'Surrender check — crossed 40% ↑';

PlanPoint _check({bool done = false, bool carried = false, bool litDone = false, String text = 'He is at 42% now — 3 things to discuss with him:'}) => PlanPoint(
      id: 'surrender_check:u1',
      kind: 'surrender_check',
      title: _title,
      text: text,
      group: PlanGroup.other,
      done: done,
      since: '2026-10-28',
      carriedOver: carried,
      sub: [
        const PlanSub(id: 'p0', kind: 'point', text: 'Raise his chanting by two rounds.'),
        const PlanSub(id: 'p1', kind: 'point', text: 'Ask how his reading is going.'),
        const PlanSub(id: 'p2', kind: 'point', text: 'Invite him to serve at the festival.'),
        PlanSub(id: 'gap_lit', kind: 'gap_lit', text: 'No LIT yet — set his LIT.', done: litDone),
        const PlanSub(id: 'gap_interaction', kind: 'gap_interaction', text: 'No interaction or meeting recorded in the last 30 days — record one.'),
        const PlanSub(id: 'gap_attitude', kind: 'gap_attitude', text: 'No attitude observed yet — note his willingness after you talk to him.'),
        const PlanSub(id: 'gap_reports', kind: 'gap_reports', text: 'He has filed no daily reports yet — ask him to start.'),
      ],
    );

PlanItem _card(List<PlanPoint> points, {bool done = false}) => PlanItem(
      id: 'student:u1:2026-10-30',
      kind: 'student',
      title: 'Ravi',
      studentName: 'Ravi',
      studentUid: 'u1',
      percent: 42,
      done: done,
      points: points,
      cardGroups: [for (final g in PlanGroup.values) if (points.any((p) => p.group == g)) g],
    );

Future<_FakePlanData> _open(WidgetTester tester, PlanDoc doc, {double scale = 1.0, bool dark = false, Size size = const Size(360, 3000)}) async {
  AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []}));
  final data = _FakePlanData();
  PlanData.instance = data;
  await pumpScreen(tester, const PlanPage(), scale: scale, dark: dark, size: size);
  data.controller.add(doc);
  await tester.pump();
  await tester.pump();
  return data;
}

PlanDoc _doc(PlanItem c) => PlanDoc(
      todayDate: '2026-10-30',
      todayItems: [c],
      weekOf: '2026-10-27',
      intro: '',
      sections: const [],
      generatedAt: DateTime.utc(2026, 10, 30, 4, 10),
      status: 'upToDate',
      changedAt: DateTime.utc(2026, 10, 30, 4, 10),
    );

Future<void> _openRow(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('plan-row-student:u1:2026-10-30')));
  await tester.pumpAndSettle();
}

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

  test('the buttons of a gap: Set LIT for the LIT, Record interaction for the interaction and the attitude, none for "no reports"; a point to discuss has none', () {
    expect(subActionOf(const PlanSub(id: 'a', kind: 'gap_lit', text: 'x')), TopicAction.setLit);
    expect(subActionOf(const PlanSub(id: 'a', kind: 'gap_interaction', text: 'x')), TopicAction.recordInteraction);
    expect(subActionOf(const PlanSub(id: 'a', kind: 'gap_attitude', text: 'x')), TopicAction.recordInteraction);
    expect(subActionOf(const PlanSub(id: 'a', kind: 'gap_reports', text: 'x')), isNull);
    expect(subActionOf(const PlanSub(id: 'a', kind: 'point', text: 'x')), isNull);
    expect(kTopicActionLabels[TopicAction.setLit], 'Set LIT');
    expect(topicActionOf(_check()), TopicAction.recordInteraction, reason: 'the topic itself: Record interaction (with the Surrender check ticked)');
  });

  test('the plan document brings the points, the gaps, the day it began and the carried-over mark', () {
    final p = PlanPoint.fromMap({
      'id': 'surrender_check:u1', 'kind': 'surrender_check', 'title': _title, 'text': 't', 'group': 'other', 'since': '2026-10-28', 'carriedOver': true,
      'sub': [{'id': 'p0', 'kind': 'point', 'text': 'Talk.'}, {'id': 'gap_lit', 'kind': 'gap_lit', 'text': 'No LIT yet', 'done': true}],
    })!;
    expect([p.since, p.carriedOver, p.sub.length, p.sub.last.done, p.sub.last.isGap], ['2026-10-28', true, 2, true, true]);
  });

  testWidgets('THE ROW: his card sits in OTHER TASKS with a Surrender-check chip; opened, the title, the line, the points to discuss and the gaps show', (tester) async {
    await _open(tester, _doc(_card([_check()])));
    expect(find.descendant(of: find.byKey(const ValueKey('plan-section-body-others')), matching: find.byKey(const ValueKey('plan-item-student:u1:2026-10-30'))), findsOneWidget);
    final chips = find.descendant(of: find.byKey(const ValueKey('plan-chips-student:u1:2026-10-30')), matching: find.byType(Text));
    expect(tester.widgetList<Text>(chips).map((t) => t.data), contains(_title));
    await _openRow(tester);
    expect(find.text('He is at 42% now — 3 things to discuss with him:'), findsOneWidget);
    for (final x in ['Raise his chanting by two rounds.', 'Ask how his reading is going.', 'Invite him to serve at the festival.']) {
      expect(find.text(x), findsOneWidget);
    }
    expect(find.text('No LIT yet — set his LIT.'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-sub-circle-student:u1:2026-10-30-0-3')), findsOneWidget, reason: 'each gap has its own circle');
  });

  testWidgets('CARRIED OVER: "Carried over since 28 Oct" on a topic from an earlier day, none on its first day', (tester) async {
    await _open(tester, _doc(_card([_check(carried: true)])));
    await _openRow(tester);
    expect(find.text('Carried over since 28 Oct'), findsOneWidget);
    await _open(tester, _doc(_card([_check()])));
    await _openRow(tester);
    expect(find.textContaining('Carried over since'), findsNothing);
  });

  testWidgets('EACH GAP HAS ITS BUTTON: Set LIT, Record interaction (twice); none for "no reports"; nothing ticks by pressing', (tester) async {
    await _open(tester, _doc(_card([_check()])));
    await _openRow(tester);
    String label(int j) => (tester.widget(find.byKey(ValueKey('plan-sub-action-student:u1:2026-10-30-0-$j'))) as dynamic).label as String;
    expect(label(3), 'Set LIT');
    expect(label(4), 'Record interaction');
    expect(label(5), 'Record interaction');
    expect(find.byKey(const ValueKey('plan-sub-action-student:u1:2026-10-30-0-6')), findsNothing, reason: 'no reports: he has to file them');
    expect(find.byKey(const ValueKey('plan-sub-action-student:u1:2026-10-30-0-0')), findsNothing, reason: 'a point to discuss has no button');
    // the topic's own button
    expect(find.byKey(const ValueKey('plan-action-student:u1:2026-10-30-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-point-tick-student:u1:2026-10-30-0')), findsNothing);
  });

  testWidgets('A GAP THAT IS FILLED is ticked by itself and loses its button; "Record interaction" from the check lists the Surrender check topic', (tester) async {
    final db = await prepareApp(tester);
    await _open(tester, _doc(_card([_check(litDone: true)])));
    await _openRow(tester);
    expect(tester.widget<Icon>(find.byKey(const ValueKey('plan-sub-circle-student:u1:2026-10-30-0-3'))).icon, Icons.check_circle);
    expect(find.byKey(const ValueKey('plan-sub-action-student:u1:2026-10-30-0-3')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('plan-action-student:u1:2026-10-30-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rec-title')), findsOneWidget);
    expect(find.text(_title), findsWidgets, reason: 'the Surrender check is a topic to tick');
    await tester.tap(find.byKey(const ValueKey('rec-save')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    final logs = (await db.collection('interactionLogs').where('source', isEqualTo: 'guide_form').get()).docs;
    expect((logs.single.data()['topicAnswers'] as List).map((x) => x['topic']), ['surrender_check'], reason: 'the server reads this as covering the surrender check');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('DONE: the topic and its gap are struck through and ticked, no buttons; the card stays in Today', (tester) async {
    await _open(tester, _doc(_card([_check(done: true)], done: true)));
    await _openRow(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-point-title-student:u1:2026-10-30-0'))).style!.decoration, TextDecoration.lineThrough);
    expect(find.byKey(const ValueKey('plan-point-tick-student:u1:2026-10-30-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-action-student:u1:2026-10-30-0')), findsNothing);
    expect(find.byKey(const ValueKey('plan-sub-action-student:u1:2026-10-30-0-3')), findsNothing);
    expect(find.text('Total tasks today: 1 · Done 1 · Left 0'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on a phone and a website width: the check with its points, gaps and buttons fits', (tester) async {
        for (final size in [const Size(360, 3600), const Size(1100, 2400)]) {
          await tester.pumpWidget(const SizedBox()); // a fresh page each time (its row starts closed)
          await _open(tester, _doc(_card([_check(carried: true)])), scale: scale, dark: dark, size: size);
          await _openRow(tester);
          expect(tester.takeException(), isNull, reason: '$size');
          final btn = tester.getRect(find.byKey(const ValueKey('plan-sub-action-student:u1:2026-10-30-0-3')));
          expect(btn.height, greaterThanOrEqualTo(48));
          expect(btn.right, lessThanOrEqualTo(size.width + .5));
        }
      });
    }
  }
}
