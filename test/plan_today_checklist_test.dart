import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/PlanToday.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/PlanBlocks.dart';

import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

/// TODAY AS A CHECKLIST: one summary line, three sections (Follow-ups, Target tasks, Other tasks) each with a circular checkbox and its count and opening
/// on a tap, every task with a circular checkbox and, inside it, its topics; a done topic is struck through with a tick and "done"; done things stay
/// visible. Read-only: nothing is ticked by tapping, and there is no stepper.

class _FakePlanData extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PendingChanges> pending(String adminId) => const Stream.empty();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => DateTime.utc(2026, 10, 30, 4, 30);
}

PlanPoint pt(String kind, String title, String text, {PlanGroup group = PlanGroup.followUp, bool done = false, String id = ''}) => PlanPoint(kind: kind, title: title, text: text, group: group, done: done, id: id);

PlanItem card(String uid, String name, List<PlanPoint> points, {bool done = false, List<PlanGroup>? groups, int? percent = 40}) => PlanItem(
      id: 'interaction:$uid:2026-10-30',
      kind: 'interaction',
      title: 'Interaction with $name',
      studentName: name,
      studentUid: uid,
      percent: percent,
      done: done,
      points: points,
      cardGroups: groups ?? [for (final g in PlanGroup.values) if (points.any((p) => p.group == g)) g],
    );

// Ravi: a worry (done) and a doubt (open) -> Follow-ups. Amit: a chanting target (open) -> Target tasks. Mohit: everything done -> Follow-ups, done.
final _ravi = card('u1', 'Ravi', [pt('concern', 'Worry', 'Sounded discouraged', group: PlanGroup.worry, done: true), pt('doubt', 'Doubt', 'Unanswered doubt in the Gita')], groups: [PlanGroup.worry, PlanGroup.followUp]);
final _amit = card('u2', 'Amit', [pt('target_chanting', 'Chanting target', 'Chanting 8 of 12 for your target', group: PlanGroup.target)]);
final _mohit = card('u3', 'Mohit', [pt('doubt', 'Doubt', 'Unanswered doubt in the Gita', done: true), pt('bookDue', 'Book due', 'Gita (due Fri 30 Oct). Has he finished it? If not, when will he finish? Set a new date.', group: PlanGroup.other, done: true)],
    done: true, groups: [PlanGroup.followUp, PlanGroup.other]);
const _meeting = PlanItem(id: 'meeting:u9:2026-10-30', kind: 'meeting', title: 'Meet Harsh', detail: 'A confirmed meeting.', forYou: true);
const _calendar = PlanItem(id: 'calendar::x', kind: 'calendar', title: 'Midterm exam');
const _targetTask = PlanItem(id: 'target_task:G:t1', kind: 'targetTask', title: 'Move Twelve from 12 to 16 rounds', detail: 'Phase 1 of your chanting target.', forYou: true);

PlanDoc _plan(List<PlanItem> today) => planDoc(today: today, left: 0);

Future<_FakePlanData> _open(WidgetTester tester, PlanDoc doc, {double scale = 1.0, bool dark = false, PlanPage page = const PlanPage(), Size size = const Size(360, 2400)}) async {
  phone(tester, scale, size: size);
  AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []}));
  final data = _FakePlanData();
  PlanData.instance = data;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(guideHost(page, dark: dark));
  data.controller.add(doc);
  await tester.pump();
  await tester.pump();
  return data;
}

/// Every row opens (a tap on the row shows its topics); the blocks are open to begin with.
Future<void> _openAll(WidgetTester tester) async {
  final rows = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('plan-row-') && !(w.key! as ValueKey<String>).value.startsWith('plan-row-body-'));
  final n = rows.evaluate().length;
  for (var i = 0; i < n; i++) {
    await tester.tap(rows.at(i));
    await tester.pump();
  }
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;

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

  test('THE VIEW: tasks are counted once whatever their topics; a calendar line is information, not a task; a section holds the student\'s one card in his most important section', () {
    final v = TodayView.of(_plan([_ravi, _amit, _mohit, _meeting, _calendar, _targetTask]));
    expect([v.total, v.done, v.left], [5, 1, 4], reason: 'Ravi, Amit, Mohit, the meeting and the target task; the calendar line is not one');
    expect(v.summaryText, 'Total tasks today: 5 · Done 1 · Left 4');
    expect(v.section(kSectionFollowUps).tasks.map((t) => t.studentName), ['Ravi', 'Mohit'], reason: 'a worry is a follow-up; what is still to do first, the done one after');
    expect(v.section(kSectionTargets).tasks.map((t) => t.id), ['interaction:u2:2026-10-30', 'target_task:G:t1']);
    expect(v.section(kSectionOthers).tasks.map((t) => t.id), ['meeting:u9:2026-10-30']);
    expect(v.information.single.title, 'Midterm exam');
    expect([v.section(kSectionFollowUps).done, v.section(kSectionFollowUps).total, v.section(kSectionFollowUps).allDone], [1, 2, false]);
  });

  testWidgets('THE SUMMARY ONLY: "Total tasks today: N · Done D · Left L"; the "Students a day" stepper and the batch line are GONE', (tester) async {
    await _open(tester, _plan([_ravi, _amit, _mohit, _meeting]));
    expect(_text(tester, 'plan-summary'), 'Total tasks today: 4 · Done 1 · Left 3');
    for (final k in ['plan-size-less', 'plan-size-more', 'plan-size', 'plan-batch', 'plan-batch-counts', 'plan-today-counts', 'plan-next-ready']) {
      expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
    }
    expect(find.textContaining('Students a day'), findsNothing);
    expect(find.textContaining('pending'), findsNothing);
    // nothing but the summary sits between the page's own bar and the first block
    expect(tester.getTopLeft(find.byKey(const ValueKey('plan-summary'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('plan-section-followups'))).dy));
  });

  testWidgets('THE DAILY NUMBER NOTE (muted gold, above the summary): the number limits only the guide\'s targets; it follows the guide\'s number; a HOD\'s plan (no batch) has none', (tester) async {
    await _open(tester, _plan([_ravi, _amit]));
    const text = 'Up to 4 students a day for your targets. To change this number, ask the AI.';
    final note = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('plan-batch-note')), matching: find.byType(Text)));
    expect(note.data, text);
    final gold = note.style!.color!;
    expect(gold, const Color(0xFF9A7B2F), reason: 'a muted gold, not the grey of the other small texts');
    expect(tester.getTopLeft(find.byKey(const ValueKey('plan-batch-note'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('plan-summary'))).dy), reason: 'at the top of Today');
    expect(find.byKey(const ValueKey('plan-size-less')), findsNothing, reason: 'still no stepper or buttons');
    // dark theme: a lighter gold that stays readable
    await tester.pumpWidget(const SizedBox());
    await _open(tester, _plan([_ravi]), dark: true);
    expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('plan-batch-note')), matching: find.byType(Text))).style!.color, const Color(0xFFD2B773));
    // another number
    await tester.pumpWidget(const SizedBox());
    final base = _plan([_ravi]);
    final seven = PlanDoc(
      todayDate: base.todayDate, todayItems: base.todayItems, weekOf: base.weekOf, intro: base.intro, sections: base.sections, generatedAt: base.generatedAt, status: base.status, changedAt: base.changedAt,
      batch: const PlanBatch(size: 7, round: 1, members: 1, carried: 0, nextReady: false, done: 0, left: 1),
    );
    await _open(tester, seven);
    expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('plan-batch-note')), matching: find.byType(Text))).data, 'Up to 7 students a day for your targets. To change this number, ask the AI.');
    // a HOD's plan has no batch: no note
    await tester.pumpWidget(const SizedBox());
    final hod = PlanDoc(todayDate: base.todayDate, todayItems: base.todayItems, weekOf: base.weekOf, intro: base.intro, sections: base.sections, generatedAt: base.generatedAt, status: base.status, changedAt: base.changedAt);
    await _open(tester, hod);
    expect(find.byKey(const ValueKey('plan-batch-note')), findsNothing);
  });

  testWidgets('THREE BLOCKS in order, each with an icon, its name, done/total and a circular check; OPEN to begin with; a tap on the header collapses (and expands) them; dividers between', (tester) async {
    await _open(tester, _plan([_ravi, _amit, _mohit, _meeting]));
    expect([_text(tester, 'plan-section-count-followups'), _text(tester, 'plan-section-count-targets'), _text(tester, 'plan-section-count-others')], ['1/2', '0/1', '0/1']);
    final y = ['followups', 'targets', 'others'].map((id) => tester.getTopLeft(find.byKey(ValueKey('plan-section-$id'))).dy).toList();
    expect(y, [...y]..sort(), reason: 'Follow-ups, Target tasks, Other tasks - in that order');
    for (final id in ['followups', 'targets', 'others']) {
      expect(find.byKey(ValueKey('plan-section-check-$id')), findsOneWidget);
      expect(find.byKey(ValueKey('plan-section-body-$id')), findsOneWidget, reason: 'open at first, like a to-do list');
      expect(find.descendant(of: find.byKey(ValueKey('plan-section-$id')), matching: find.byType(Icon)), findsWidgets, reason: 'an icon, the check, the arrow');
    }
    expect(find.byType(PlanBlockDivider), findsNWidgets(2), reason: 'a divider between the blocks');
    expect(find.text('Follow-ups'), findsOneWidget);
    expect(find.text('Target tasks'), findsOneWidget);
    expect(find.text('Other tasks'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-section-followups')));
    await tester.pump();
    expect(find.byKey(const ValueKey('plan-section-body-followups')), findsNothing, reason: 'collapsed');
    expect(find.byKey(const ValueKey('plan-item-interaction:u2:2026-10-30')), findsOneWidget, reason: 'the others stay');
    await tester.tap(find.byKey(const ValueKey('plan-section-followups')));
    await tester.pump();
    expect(find.byKey(const ValueKey('plan-section-body-followups')), findsOneWidget);
  });

  testWidgets('ONE ROW PER STUDENT, never in two blocks: his name with his small %, coloured topic CHIPS, and the topics only after a tap on the row', (tester) async {
    final two = card('u1', 'Ravi', [pt('concern', 'Worry', 'Sounded discouraged', group: PlanGroup.worry), pt('bookDue', 'Book due', 'Gita', group: PlanGroup.other), pt('doubt', 'Doubt', 'q')], groups: [PlanGroup.worry, PlanGroup.other, PlanGroup.followUp]);
    await _open(tester, _plan([two, _amit]));
    final rowId = two.id;
    expect(find.byKey(ValueKey('plan-item-$rowId')), findsOneWidget, reason: 'exactly one row for Ravi, in all the blocks together');
    expect(find.descendant(of: find.byKey(const ValueKey('plan-section-body-followups')), matching: find.byKey(ValueKey('plan-item-$rowId'))), findsOneWidget, reason: 'his most important block (the worry: Follow-ups)');
    expect(_text(tester, 'plan-title-$rowId'), 'Ravi');
    expect(_text(tester, 'plan-percent-$rowId'), '40%');
    final chips = find.descendant(of: find.byKey(ValueKey('plan-chips-$rowId')), matching: find.byType(PlanChip));
    expect(chips, findsNWidgets(3));
    expect([for (final c in chips.evaluate()) (c.widget as PlanChip).label], ['Worry', 'Book due', 'Doubt']);
    expect((chips.evaluate().first.widget as PlanChip).color, isNot((chips.evaluate().last.widget as PlanChip).color), reason: 'coloured by the kind of topic');
    expect(find.byKey(ValueKey('plan-point-$rowId-0')), findsNothing, reason: 'the topics show after a tap on the row');
    await tester.tap(find.byKey(ValueKey('plan-row-$rowId')));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('plan-point-$rowId-$i')), findsOneWidget);
      expect(find.byKey(ValueKey('plan-point-circle-$rowId-$i')), findsOneWidget, reason: 'each topic has its own circle');
    }
    await tester.tap(find.byKey(ValueKey('plan-row-$rowId')));
    await tester.pump();
    expect(find.byKey(ValueKey('plan-point-$rowId-0')), findsNothing, reason: 'and closes again');
  });

  testWidgets('DONE ROWS stay, DIMMED, at the BOTTOM of their block; an empty block says "Nothing here today"', (tester) async {
    await _open(tester, _plan([_mohit, _ravi]));
    final ys = [_mohit.id, _ravi.id].map((id) => tester.getTopLeft(find.byKey(ValueKey('plan-item-$id'))).dy).toList();
    expect(ys[0], greaterThan(ys[1]), reason: 'Mohit (done) is below Ravi (still to do)');
    final dim = tester.widget<Opacity>(find.descendant(of: find.byKey(ValueKey('plan-item-${_mohit.id}')), matching: find.byType(Opacity)).first);
    expect(dim.opacity, lessThan(1), reason: 'dimmed');
    expect(tester.widget<Text>(find.byKey(ValueKey('plan-title-${_mohit.id}'))).style!.decoration, TextDecoration.lineThrough);
    expect(_text(tester, 'plan-section-empty-targets'), 'Nothing here today');
    expect(_text(tester, 'plan-section-empty-others'), 'Nothing here today');
  });

  testWidgets('CHECKBOXES TICK BY THEMSELVES: a task is ticked when all its topics are done, a block when all its tasks are', (tester) async {
    await _open(tester, _plan([_ravi, _mohit]));
    Icon icon(String key) => tester.widget<Icon>(find.byKey(ValueKey(key)));
    expect(icon('plan-check-interaction:u1:2026-10-30').icon, Icons.radio_button_unchecked, reason: 'one of his topics is still open');
    expect(icon('plan-check-interaction:u3:2026-10-30').icon, Icons.check_circle, reason: "all of Mohit's topics are done");
    expect(icon('plan-section-check-followups').icon, Icons.radio_button_unchecked, reason: 'one task of the block is left');
    await _open(tester, _plan([card('u1', 'Ravi', [pt('doubt', 'Doubt', 'x', done: true)], done: true), _mohit]));
    expect(icon('plan-section-check-followups').icon, Icons.check_circle);
    expect(_text(tester, 'plan-section-count-followups'), '2/2');
    expect(_text(tester, 'plan-summary'), 'Total tasks today: 2 · Done 2 · Left 0');
  });

  testWidgets('A DONE TOPIC has a line through its title and its line, a tick and "done"; an open topic has none; the done ones STAY visible', (tester) async {
    await _open(tester, _plan([_ravi]));
    await _openAll(tester);
    TextStyle? style(String key) => tester.widget<Text>(find.byKey(ValueKey(key))).style;
    expect(style('plan-point-title-interaction:u1:2026-10-30-0')!.decoration, TextDecoration.lineThrough);
    expect(style('plan-point-text-interaction:u1:2026-10-30-0')!.decoration, TextDecoration.lineThrough);
    expect(find.byKey(const ValueKey('plan-point-tick-interaction:u1:2026-10-30-0')), findsOneWidget);
    expect(_text(tester, 'plan-point-done-interaction:u1:2026-10-30-0'), 'done');
    expect(style('plan-point-title-interaction:u1:2026-10-30-1')!.decoration, isNot(TextDecoration.lineThrough));
    expect(find.byKey(const ValueKey('plan-point-tick-interaction:u1:2026-10-30-1')), findsNothing);
    expect(find.text('Worry'), findsWidgets, reason: 'the finished topic is still there (its chip and its line)');
  });

  testWidgets("NOTHING IS TICKED BY TAPPING: no checkbox or switch; the only buttons are the topics' action buttons; tapping the circle changes nothing", (tester) async {
    await _open(tester, _plan([_ravi, _amit, _meeting]));
    await _openAll(tester);
    final others = find.byWidgetPredicate((w) => w is Checkbox || w is Switch || w is FloatingActionButton || w is Radio);
    for (final id in ['plan-section-body-followups', 'plan-section-body-targets', 'plan-section-body-others']) {
      expect(find.descendant(of: find.byKey(ValueKey(id)), matching: others), findsNothing, reason: id);
    }
    final before = _text(tester, 'plan-summary');
    await tester.tap(find.byKey(const ValueKey('plan-check-interaction:u1:2026-10-30')), warnIfMissed: false);
    await tester.pump();
    expect(_text(tester, 'plan-summary'), before);
    expect(tester.widget<Icon>(find.byKey(const ValueKey('plan-check-interaction:u1:2026-10-30'))).icon, Icons.radio_button_unchecked);
  });

  testWidgets('A BOOK DUE is ONE topic with the book, the due date and the question; a student with a worry, a doubt and a book due is ONE row, never split across blocks', (tester) async {
    final one = card('u1', 'Ravi', [
      pt('concern', 'Worry', 'Sounded discouraged', group: PlanGroup.worry),
      pt('bookDue', 'Book due', 'Bhagavad-gita (due Fri 30 Oct). Has he finished it? If not, when will he finish? Set a new date.', group: PlanGroup.other),
    ], groups: [PlanGroup.worry, PlanGroup.other]);
    await _open(tester, _plan([one]));
    await _openAll(tester);
    expect(find.text('Book due'), findsNWidgets(2), reason: 'the chip and the topic title; never a second topic');
    expect(find.textContaining('Bhagavad-gita (due Fri 30 Oct)'), findsOneWidget);
    expect(find.textContaining('Has he finished it? If not, when will he finish? Set a new date.'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-item-interaction:u1:2026-10-30')), findsOneWidget, reason: 'one row, in his most important block (the worry: Follow-ups)');
    expect(find.descendant(of: find.byKey(const ValueKey('plan-section-body-followups')), matching: find.byKey(const ValueKey('plan-item-interaction:u1:2026-10-30'))), findsOneWidget);
  });

  testWidgets('TASKS OF THEIR OWN: a phase end is in Target tasks, the meeting in Other tasks, the calendar line is only information (no checkbox)', (tester) async {
    await _open(tester, _plan([_targetTask, _meeting, _calendar]));
    await _openAll(tester);
    expect(find.descendant(of: find.byKey(const ValueKey('plan-section-body-targets')), matching: find.byKey(const ValueKey('plan-item-target_task:G:t1'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('plan-section-body-others')), matching: find.byKey(const ValueKey('plan-item-meeting:u9:2026-10-30'))), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-info-calendar::x')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-check-calendar::x')), findsNothing);
    expect(_text(tester, 'plan-summary'), 'Total tasks today: 2 · Done 0 · Left 2');
  });

  testWidgets('A TASK THAT IS DONE stays, struck through and ticked, and is counted as done', (tester) async {
    await _open(tester, _plan([const PlanItem(id: 'target_task:G:t0', kind: 'targetTask', title: 'Move Eight from 8 to 12 rounds', done: true), _targetTask]));
    expect(_text(tester, 'plan-summary'), 'Total tasks today: 2 · Done 1 · Left 1');
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-title-target_task:G:t0'))).style!.decoration, TextDecoration.lineThrough);
    expect(tester.widget<Icon>(find.byKey(const ValueKey('plan-check-target_task:G:t0'))).icon, Icons.check_circle);
  });

  testWidgets('FROM HOME: opened on a count, the page shows that block (a worry opens Follow-ups)', (tester) async {
    await _open(tester, _plan([_ravi, _amit]), page: const PlanPage(section: PlanGroup.worry));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('plan-section-body-followups')), findsOneWidget);
  });

  testWidgets('THIS WEEK names the students of each target with their steps as chips; the done ones are ticked and struck through', (tester) async {
    const week = PlanItem(
      id: 'weektarget:t1',
      kind: 'weekTask',
      title: 'Chanting 16 by 30 Nov',
      steps: [PlanStep(name: 'Testing', from: 12, to: 16), PlanStep(name: 'Amit', from: 8, to: 12, done: true), PlanStep(name: 'Amit', from: 12, to: 16)],
    );
    final doc = PlanDoc(
      todayDate: '2026-10-30',
      todayItems: const [],
      weekOf: '2026-10-26',
      intro: '',
      sections: const [PlanSection(id: 'targettasks', title: 'Target tasks', items: [week])],
      generatedAt: DateTime.utc(2026, 10, 30, 4, 10),
      status: 'upToDate',
      changedAt: DateTime.utc(2026, 10, 30, 4, 10),
    );
    await _open(tester, doc, page: const PlanPage(initialWeek: true));
    expect(find.text('Chanting 16 by 30 Nov'), findsOneWidget);
    expect(find.text('Testing 12 → 16'), findsOneWidget);
    expect(find.text('Amit 8 → 12'), findsOneWidget);
    expect(find.text('Amit 12 → 16'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Amit 8 → 12')).style!.decoration, TextDecoration.lineThrough, reason: 'the done step');
    expect(tester.widget<Text>(find.text('Testing 12 → 16')).style!.decoration, isNot(TextDecoration.lineThrough));
    expect(find.byKey(const ValueKey('plan-week-step-weektarget:t1-1')), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'}, on a WEBSITE width (1100 dp): the blocks stay compact and readable, no overflow', (tester) async {
      await _open(tester, _plan([_ravi, _amit, _mohit, _meeting, _targetTask]), dark: dark, size: const Size(1100, 1800));
      await _openAll(tester);
      expect(tester.takeException(), isNull);
      for (final id in ['followups', 'targets', 'others']) {
        expect(tester.getRect(find.byKey(ValueKey('plan-section-$id'))).right, lessThanOrEqualTo(1100.5), reason: id);
      }
      expect(tester.getRect(find.byKey(const ValueKey('plan-item-interaction:u1:2026-10-30'))).width, lessThanOrEqualTo(900), reason: 'a sensible maximum width, not stretched across the screen');
    });
  }

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: the summary, the block headers, the rows, the topics and their 3D buttons fit; headers are 48 dp targets', (tester) async {
        await _open(tester, _plan([_ravi, _amit, _mohit, _meeting, _targetTask]), scale: scale, dark: dark);
        await _openAll(tester);
        expect(tester.takeException(), isNull);
        for (final id in ['followups', 'targets', 'others']) {
          final r = tester.getRect(find.byKey(ValueKey('plan-section-$id')));
          expect(r.right, lessThanOrEqualTo(360.5), reason: id);
          expect(r.height, greaterThanOrEqualTo(48), reason: id);
        }
        final row = tester.getRect(find.byKey(const ValueKey('plan-item-interaction:u1:2026-10-30')));
        expect(row.right, lessThanOrEqualTo(360.5));
        final btn = tester.getRect(find.byKey(const ValueKey('plan-action-interaction:u1:2026-10-30-1')));
        expect(btn.height, greaterThanOrEqualTo(48));
        expect(btn.right, lessThanOrEqualTo(360.5));
      });
    }
  }
}
