import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';

import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

/// The Plan page (Today | This week), READ-ONLY. It UPDATES ITSELF (the server works it out again within a minute of any change): there is no Refresh button
/// (guide or HOD), no "Refresh all guides", no countdown. It says "Updated Fri 30 Oct, 6:00 AM", then Up to date / Updating… / Updated. A badge counts the NEW
/// changes (not seen yet), a tap lists them, the rows they concern carry a "New" tag; leaving the page marks them seen.

/// Friday 30 Oct 2026, 10:00 IST = 04:30 UTC.
final DateTime _now = DateTime.utc(2026, 10, 30, 4, 30);

class _FakePlanData extends PlanData {
  _FakePlanData();
  final controller = StreamController<PlanDoc?>.broadcast();
  final pendingC = StreamController<PendingChanges>.broadcast();
  @override
  Stream<PendingChanges> pending(String adminId) => pendingC.stream;

  /// When the admin last left the page (null: never), and the leavings the page reported.
  DateTime? seen;
  final marked = <String>[];
  @override
  Stream<DateTime?> seenAt(String adminId) async* {
    yield seen;
  }

  @override
  Future<void> markPlanSeen(String adminId) async => marked.add(adminId);
  DateTime clock = _now;
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => clock;
}

PlanDoc _plan({
  String status = 'upToDate',
  DateTime? generatedAt,
  DateTime? refreshedAt,
  String refreshedBy = '',
  List<PlanItem>? today,
  List<PlanSection>? sections,
  PlanBatch? batch,
  String intro = '',
}) =>
    PlanDoc(
      todayDate: '2026-10-30',
      todayItems: today ??
          const [
            PlanItem(id: 'meeting:u1:2026-10-30', kind: 'meeting', title: 'Meet Harsh', detail: 'A confirmed meeting.', forYou: true),
            PlanItem(id: 'followup:u2:2026-10-30', kind: 'followUp', title: 'Follow up with Kishan', detail: 'Ask about his Gita reading'),
          ],
      weekOf: '2026-10-26',
      intro: intro,
      sections: sections ??
          const [
            PlanSection(id: 'interactions', title: 'Interactions', items: [
              PlanItem(id: 'week:u1', kind: 'weekStudent', title: '', studentUid: 'u1', studentName: 'Ravi', percent: 42, scheduledFor: '2026-10-30'),
              PlanItem(id: 'week:u2', kind: 'weekStudent', title: '', studentUid: 'u2', studentName: 'Amit', scheduledFor: '2026-10-30'),
              PlanItem(id: 'week:u4', kind: 'weekStudent', title: '', studentUid: 'u4', studentName: 'Mohit', scheduledFor: '2026-10-30', done: true),
              PlanItem(id: 'week:u3', kind: 'weekStudent', title: '', studentUid: 'u3', studentName: 'Deep', percent: 57, scheduledFor: '2026-10-31'),
            ]),
            PlanSection(id: 'targettasks', title: 'Target tasks', items: [
              PlanItem(id: 'tt1', kind: 'weekTask', title: 'Chanting 16 by Mon 30 Nov: 2 of 5 students'),
              PlanItem(id: 'tt2', kind: 'weekTask', title: 'Bring FOLK residents 3 → 5', done: true),
            ]),
            PlanSection(id: 'othertasks', title: 'Other tasks', items: [
              PlanItem(id: 'ot1', kind: 'weekOther', title: 'Meeting: Kishan', scheduledFor: '2026-11-02'),
              PlanItem(id: 'ot2', kind: 'weekOther', title: 'Trip: Mayapur', scheduledFor: '2026-11-04'),
            ]),
          ],
      generatedAt: generatedAt ?? _now.subtract(const Duration(minutes: 20)),
      status: status,
      changedAt: generatedAt ?? _now,
      refreshedAt: refreshedAt,
      refreshedBy: refreshedBy,
      batch: batch,
    );

AdminProfile _me({String role = 'GUIDE'}) => AdminProfile.fromMap({
      'id': 'G', 'displayName': 'Gopal', 'role': role, 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': [],
    });

Future<_FakePlanData> _open(WidgetTester tester, {double scale = 1.0, bool dark = false, PlanDoc? doc, String role = 'GUIDE', PlanPage page = const PlanPage(), Size? size}) async {
  phone(tester, scale, size: size ?? const Size(360, 800));
  AdminProfileProvider.instance.debugSet(_me(role: role));
  final data = _FakePlanData();
  PlanData.instance = data;
  await tester.pumpWidget(guideHost(page, dark: dark));
  await _emit(tester, data, doc ?? _plan());
  return data;
}

/// Sends a plan to the page and lets the stream event and the frame both happen.
Future<void> _emit(WidgetTester tester, _FakePlanData data, PlanDoc? doc) async {
  data.controller.add(doc);
  await tester.pump();
  await tester.pump();
}

String _statusText(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('plan-status-text'))).data!;
String _lastUpdated(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('plan-last-updated'))).data!;

/// A plan with a batch: 2 follow-ups, 1 target task, 2 other tasks (what the page's three sections are made of).
PlanDoc _batchPlan() => planDoc(left: 5, today: [
      interactionItem('u1', 'Ravi', ['sadhana']),
      interactionItem('u2', 'Amit', ['doubts', 'target']),
      interactionItem('u3', 'Mohit', ['target']),
      const PlanItem(id: 'meeting:u9:2026-10-30', kind: 'meeting', title: 'Meet Harsh', forYou: true),
      const PlanItem(id: 'calendar::x', kind: 'calendar', title: 'Midterm exam'),
    ]);

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

  group('the words: "Updated …" and the status', () {
    test('"Updated" and the time the plan was last worked out, India time', () {
      expect(planLastUpdated(_plan(generatedAt: DateTime.utc(2026, 10, 30, 0, 30))), 'Updated Fri 30 Oct, 6:00 AM');
      expect(planLastUpdated(_plan(generatedAt: DateTime.utc(2026, 10, 30, 6, 30))), 'Updated Fri 30 Oct, 12:00 PM');
    });
    test('status: up to date, or updating', () {
      expect(planStatusText(_plan()), 'Up to date');
      expect(planStatusText(_plan(status: 'updating')), 'Updating…');
    });
    test('clock face in India time, 12-hour', () {
      expect(planClock(DateTime.utc(2026, 10, 30, 0, 30)), '6:00 AM');
      expect(planClock(DateTime.utc(2026, 10, 30, 6, 30)), '12:00 PM');
      expect(planClock(DateTime.utc(2026, 10, 30, 18, 25)), '11:55 PM');
      expect(planClock(DateTime.utc(2026, 10, 30, 18, 30)), '12:00 AM');
    });
  });

  group('the page', () {
    testWidgets('read-only line and the note that it updates by itself, at the top; TODAY | THIS WEEK in the app bar; no hourly promise, no countdown', (tester) async {
      await _open(tester);
      expect(find.text('Read-only — for any help, ask the AI in a chat.'), findsOneWidget);
      expect(find.text('The plan updates by itself, within a minute of any change.'), findsOneWidget);
      expect(find.textContaining('Refresh'), findsNothing);
      expect(find.textContaining('about an hour'), findsNothing);
      expect(find.textContaining('updating in'), findsNothing);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
    });

    testWidgets('NO REFRESH BUTTONS: not for a guide, not for a HOD (no "Refresh all guides"), no countdown, no refusal line', (tester) async {
      for (final role in ['GUIDE', 'HOD']) {
        await _open(tester, role: role);
        for (final k in ['plan-refresh', 'plan-refresh-all', 'plan-refresh-wait', 'plan-refresh-error']) {
          expect(find.byKey(ValueKey(k)), findsNothing, reason: '$role $k');
        }
        expect(find.text('Refresh'), findsNothing);
        expect(find.text('Refresh all guides'), findsNothing);
        expect(find.textContaining('refresh again'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the first thing under the app bar is the "Nothing new" line (or the badge), above the notes', (tester) async {
      await _open(tester);
      expect(tester.getTopLeft(find.byKey(const ValueKey('plan-pending-ok'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('plan-readonly'))).dy));
    });

    testWidgets('READ-ONLY: nothing to tick, nothing to type, nothing to switch', (tester) async {
      await _open(tester);
      for (final type in [Checkbox, Switch, TextField, Radio<int>, TextButton, ElevatedButton, FloatingActionButton]) {
        expect(find.byType(type), findsNothing, reason: '$type');
      }
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      for (final type in [Checkbox, Switch, TextField]) {
        expect(find.byType(type), findsNothing, reason: 'This week: $type');
      }
      expect(find.byTooltip('Back'), findsNothing, reason: 'the root of this test has no back button');
    });

    testWidgets('no plan yet: a friendly line; an empty day says so', (tester) async {
      final data = await _open(tester);
      await _emit(tester, data, null);
      expect(find.byKey(const ValueKey('plan-empty')), findsOneWidget);
      await _emit(tester, data, _plan(today: const [], sections: const []));
      for (final id in ['followups', 'targets', 'others']) {
        expect(find.byKey(ValueKey('plan-section-empty-$id')), findsOneWidget, reason: 'an empty block says "Nothing here today"');
      }
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      // nothing is hidden: the counts are 0 and every section says "None yet"
      expect(find.byKey(const ValueKey('plan-progress')), findsOneWidget);
      expect(find.text('Interactions this week: 0 · Done 0 · Left 0'), findsOneWidget);
      for (final id in ['week-interactions', 'week-targettasks', 'week-othertasks']) {
        expect(find.byKey(ValueKey('plan-section-empty-$id')), findsOneWidget, reason: id);
      }
    });

    testWidgets('opened for THIS WEEK (from Home) it starts on that tab', (tester) async {
      await _open(tester, page: const PlanPage(initialWeek: true));
      expect(find.byKey(const ValueKey('plan-section-week-interactions')), findsOneWidget);
      expect(find.textContaining('Today — Friday'), findsNothing);
    });
  });

  group('"Updated" and the status', () {
    testWidgets('"Updated" shows the time the plan was last worked out (India time), on both tabs', (tester) async {
      await _open(tester, doc: _plan(generatedAt: DateTime.utc(2026, 10, 30, 0, 30)));
      expect(_lastUpdated(tester), 'Updated Fri 30 Oct, 6:00 AM');
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-last-updated')), findsOneWidget);
    });

    testWidgets('Up to date when nothing is being written; Updating… while the server writes it', (tester) async {
      final data = await _open(tester);
      expect(_statusText(tester), 'Up to date');
      await _emit(tester, data, _plan(status: 'updating'));
      expect(_statusText(tester), 'Updating…');
    });

    testWidgets('a new plan arriving by itself shows at once with a short "Updated" highlight; the time moves on', (tester) async {
      final data = await _open(tester);
      await _emit(tester, data, _plan(generatedAt: _now, today: const [PlanItem(id: 'followup:u9:2026-10-30', kind: 'followUp', title: 'Follow up with Ravi')]));
      expect(_statusText(tester), 'Updated');
      expect(_lastUpdated(tester), 'Updated Fri 30 Oct, 10:00 AM');
      expect(find.text('Follow up with Ravi'), findsOneWidget, reason: 'the new plan is on screen');
      expect(find.text('Meet Harsh'), findsNothing);
      final lit = tester.widget<AnimatedContainer>(find.byKey(const ValueKey('plan-status')));
      expect((lit.decoration as BoxDecoration).border, isNotNull);
      await tester.pump(kPlanUpdatedHighlight + const Duration(milliseconds: 100));
      expect(_statusText(tester), 'Up to date');
    });

    testWidgets('a plan that is the same as before does not flash "Updated" on first show', (tester) async {
      await _open(tester);
      expect(_statusText(tester), 'Up to date');
    });
  });

  group('THE NEW-CHANGES BADGE: what the admin has not SEEN yet (since he last left the Plan page)', () {
    // the changes as the server records them (the newest is the LAST in [texts]); [at] is the minute of the first
    PendingChanges changes(List<String> texts, {List<String> uids = const [], List<String> types = const [], int minute = 0}) => PendingChanges([
          for (var i = 0; i < texts.length; i++)
            PendingChange(type: i < types.length ? types[i] : 'interaction', text: texts[i], studentUid: i < uids.length ? uids[i] : '', at: DateTime(2026, 10, 30, 10, minute + i)),
        ]);
    Future<void> emitPending(WidgetTester tester, _FakePlanData data, PendingChanges p) async {
      data.pendingC.add(p);
      await tester.pump();
      await tester.pump();
    }

    Future<_FakePlanData> openSeen(WidgetTester tester, DateTime? seen, {double scale = 1.0, bool dark = false, PlanDoc? doc}) async {
      phone(tester, scale);
      AdminProfileProvider.instance.debugSet(_me());
      final data = _FakePlanData()..seen = seen;
      PlanData.instance = data;
      await tester.pumpWidget(guideHost(const PlanPage(), dark: dark));
      await _emit(tester, data, doc ?? _plan());
      return data;
    }

    String badge(WidgetTester tester) => tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('plan-refresh-badge')), matching: find.byType(Text))).data!;
    final seenAt = DateTime(2026, 10, 30, 9, 59);

    testWidgets('nothing new: "✓ Nothing new" and no badge', (tester) async {
      final data = await openSeen(tester, seenAt);
      await emitPending(tester, data, PendingChanges.none);
      expect(find.byKey(const ValueKey('plan-pending-ok')), findsOneWidget);
      expect(find.text('✓ Nothing new'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing);
    });

    testWidgets('the badge counts only the changes NEWER than the last time he left the page; the older ones are seen', (tester) async {
      final data = await openSeen(tester, DateTime(2026, 10, 30, 10, 1)); // left at 10:01
      await emitPending(tester, data, changes(['Interaction recorded: Old', 'New doubt: Testing', 'Book finished: Ayush'])); // 10:00, 10:01, 10:02
      expect(badge(tester), '1', reason: 'only 10:02 is newer than 10:01');
      expect(find.text('new — tap to see'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-pending-line')));
      await tester.pumpAndSettle();
      expect(find.text('1 new'), findsOneWidget);
      expect(find.text('• Book finished: Ayush'), findsOneWidget);
      expect(find.text('• New doubt: Testing'), findsNothing);
    });

    testWidgets('a tap on the badge lists them newest first: "New doubt: Testing", "Book finished: Ayush", "New task: Surrender check — Ravi"', (tester) async {
      final data = await openSeen(tester, seenAt);
      await emitPending(tester, data, changes(['New doubt: Testing', 'Book finished: Ayush', 'New task: Surrender check — Ravi']));
      expect(badge(tester), '3');
      await tester.tap(find.byKey(const ValueKey('plan-refresh-badge')));
      await tester.pumpAndSettle();
      expect(find.text('3 new'), findsOneWidget);
      final y = [for (final x in ['New task: Surrender check — Ravi', 'Book finished: Ayush', 'New doubt: Testing']) tester.getTopLeft(find.text('• $x')).dy];
      expect(y, [...y]..sort(), reason: 'newest first');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('the rows they concern carry a small "New" tag: Today and This week (a student; a target task); the others do not', (tester) async {
      final data = await openSeen(tester, seenAt, doc: _batchPlan());
      await emitPending(tester, data, changes(['New doubt: Amit'], uids: ['u2'], types: ['doubt']));
      // Today: Amit's task
      final amitId = _batchPlan().todayItems.firstWhere((i) => i.studentUid == 'u2').id;
      final raviId = _batchPlan().todayItems.firstWhere((i) => i.studentUid == 'u1').id;
      expect(find.byKey(ValueKey('plan-new-$amitId')), findsOneWidget);
      expect(find.byKey(ValueKey('plan-new-$raviId')), findsNothing);
      expect(find.text('New'), findsOneWidget);
      // This week
      await _emit(tester, data, _plan());
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-week-new-u2')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-week-new-u1')), findsNothing);
      // a new target: the target tasks
      await emitPending(tester, data, changes(['Chanting target changed'], types: ['target']));
      expect(find.byKey(const ValueKey('plan-week-task-new-tt1')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-week-new-u2')), findsNothing, reason: 'no student change now');
    });

    testWidgets('SEEN = he LEFT the page: leaving reports it (the cursor moves to now); until then the tags stay', (tester) async {
      final data = await openSeen(tester, seenAt);
      await emitPending(tester, data, changes(['New doubt: Testing']));
      expect(badge(tester), '1');
      expect(data.marked, isEmpty, reason: 'opening is not leaving');
      await tester.pumpWidget(const SizedBox());
      expect(data.marked, ['G'], reason: 'leaving the page marks it seen');
    });

    testWidgets('THE NEXT VISIT: with the cursor at the time he left there are no tags and no badge; a change after that is a FRESH count', (tester) async {
      // visit 1: two new changes; he leaves at 10:30
      var data = await openSeen(tester, seenAt, doc: _batchPlan());
      await emitPending(tester, data, changes(['New doubt: Amit', 'Book finished: Ravi'], uids: ['u2', 'u1'], minute: 5));
      expect(badge(tester), '2');
      await tester.pumpWidget(const SizedBox());
      final left = DateTime(2026, 10, 30, 10, 30);
      // visit 2: the same records, the cursor now 10:30: nothing is new
      data = await openSeen(tester, left, doc: _batchPlan());
      await emitPending(tester, data, changes(['New doubt: Amit', 'Book finished: Ravi'], uids: ['u2', 'u1'], minute: 5));
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing, reason: 'the badge is cleared');
      expect(find.text('✓ Nothing new'), findsOneWidget);
      expect(find.text('New'), findsNothing, reason: 'the New tags are gone');
      // a new change after that: a fresh count of one
      await emitPending(tester, data, PendingChanges([
        ...changes(['New doubt: Amit', 'Book finished: Ravi'], uids: ['u2', 'u1'], minute: 5).items,
        PendingChange(type: 'surrender', text: 'Surrender crossed 40%: Ravi', studentUid: 'u1', at: DateTime(2026, 10, 30, 10, 40)),
      ]));
      expect(badge(tester), '1');
      await tester.tap(find.byKey(const ValueKey('plan-refresh-badge')));
      await tester.pumpAndSettle();
      expect(find.text('• Surrender crossed 40%: Ravi'), findsOneWidget);
      expect(find.text('• New doubt: Amit'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('it counts live while the page is open: a change that arrives now is new at once', (tester) async {
      final data = await openSeen(tester, seenAt);
      await emitPending(tester, data, PendingChanges.none);
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing);
      await emitPending(tester, data, changes(['New worry: Ravi Kumar'], minute: 20));
      expect(badge(tester), '1');
    });

    testWidgets('a long list still fits: 120 new changes read as 99+; no overflow in light, dark or large text', (tester) async {
      for (final dark in [false, true]) {
        for (final scale in kScales) {
          final data = await openSeen(tester, seenAt, scale: scale, dark: dark);
          await emitPending(tester, data, PendingChanges([for (var i = 0; i < 120; i++) PendingChange(type: 'interaction', text: 'Interaction recorded: Student $i', at: DateTime(2026, 10, 30, 11, i % 60))]));
          expect(badge(tester), '99+');
          await tester.tap(find.byKey(const ValueKey('plan-refresh-badge')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$dark $scale');
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
        }
      }
    });

    test('NewChanges: only the records newer than the cursor (the last 24 hours when he has never left), the newest first; empty records ignored', () {
      final all = PendingChanges.fromDocs([
        {'type': 'interaction', 'text': 'older', 'at': Timestamp.fromDate(DateTime(2026, 10, 30, 9))},
        {'type': 'doubt', 'text': 'newer', 'studentUid': 'u1', 'at': Timestamp.fromDate(DateTime(2026, 10, 30, 11))},
        {'type': 'x', 'text': ''},
        {'type': 'book', 'text': 'ancient', 'at': Timestamp.fromDate(DateTime(2026, 10, 20, 9))},
      ]);
      expect(all.count, 3);
      final seen = NewChanges.of(all, DateTime(2026, 10, 30, 10), DateTime(2026, 10, 30, 12));
      expect(seen.items.map((c) => c.text), ['newer']);
      expect(seen.isNewFor(studentUid: 'u1'), isTrue);
      expect(seen.isNewFor(studentUid: 'u2'), isFalse);
      expect(seen.isNewFor(isTarget: true), isFalse);
      final never = NewChanges.of(all, null, DateTime(2026, 10, 30, 12));
      expect(never.items.map((c) => c.text), ['newer', 'older'], reason: 'the last 24 hours');
    });
  });

  group('A HOD\'s OWN plan first, the guides\' summaries below', () {
    PlanDoc hodDoc() => PlanDoc(
          todayDate: '2026-10-30',
          todayItems: [
            interactionItem('u1', 'Ravi', ['sadhana']),
            interactionItem('u2', 'Amit', ['doubts']),
            const PlanItem(id: 'meeting:u9:2026-10-30', kind: 'meeting', title: 'Meet Harsh', forYou: true),
            const PlanItem(id: 'phase_end:HOD:t1_1', kind: 'phaseTask', title: 'Phase 1 of your chanting target ends'),
            const PlanItem(id: 'guide:G1', kind: 'guideSummary', title: 'Gopal: 3 for today, 5 interactions needed'),
            const PlanItem(id: 'guide:G2', kind: 'guideSummary', title: 'Govinda: 1 for today, 2 interactions needed'),
          ],
          weekOf: '2026-10-26',
          intro: 'Hare Krishna Hari!',
          sections: const [
            PlanSection(id: 'interactions', title: 'Interactions', items: [PlanItem(id: 'week:u3', kind: 'weekStudent', title: '', studentUid: 'u3', studentName: 'Mohit', scheduledFor: '2026-10-30')]),
            PlanSection(id: 'guides', title: 'Guide by guide', items: [PlanItem(id: 'guide:G1', kind: 'guideSummary', title: 'Gopal: 3 for today, 5 interactions needed')]),
          ],
          generatedAt: _now,
          status: 'upToDate',
          changedAt: _now,
          batch: const PlanBatch(size: 4, round: 1, members: 2, carried: 0, nextReady: false, done: 0, left: 2),
          progress: const PlanProgress(needed: 3, done: 0, left: 3, summary: 'Interactions needed: 3 · done 0 · left 3', bySource: []),
        );

    testWidgets('This week: his own progress and planned students first, "Guide by guide" last', (tester) async {
      await _open(tester, role: 'HOD', doc: hodDoc(), size: const Size(360, 3200));
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-week-interactions')), findsOneWidget);
      expect(find.text('Guide by guide'), findsOneWidget);
      double y(Finder f) => tester.getTopLeft(f).dy;
      expect(y(find.byKey(const ValueKey('plan-section-week-interactions'))), lessThan(y(find.text('Guide by guide'))));
    });

    test('the Home counts are his OWN tasks: the guides\' summary lines are never counted', () {
      final c = PlanCounts.of(hodDoc());
      expect(c.followUps, 2);
      expect(c.targets, 1);
      expect(c.others, 1);
      expect(c.total, 4);
      expect(hodDoc().todayItems.last.isGuideSummary, isTrue);
    });

    testWidgets('no overflow in light and dark at every text size', (tester) async {
      for (final dark in [false, true]) {
        for (final scale in kScales) {
          await _open(tester, role: 'HOD', doc: hodDoc(), scale: scale, dark: dark, size: const Size(360, 3200));
          expect(tester.takeException(), isNull, reason: '$dark $scale');
          await tester.pumpWidget(const SizedBox());
        }
      }
    });

  });

  group('every state: light and dark, text scale 1.0 / 1.3 / 1.6', () {
    for (final dark in [false, true]) {
      for (final scale in kScales) {
        for (final tab in ['today', 'week']) {
          testWidgets('${dark ? 'dark' : 'light'}, ×$scale, $tab: no overflow, targets of 48 dp', (tester) async {
            final data = await _open(tester, scale: scale, dark: dark, role: 'HOD', doc: _plan(status: 'updating'));
            if (tab == 'week') {
              await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            for (final k in ['plan-tab-today', 'plan-tab-week']) {
              expect(tester.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48), reason: k);
            }
            for (final status in [_plan(status: 'updating'), _plan(), _plan(generatedAt: _now), _batchPlan()]) {
              await _emit(tester, data, status);
              expect(tester.takeException(), isNull);
            }
            await tester.scrollUntilVisible(find.byType(Text).last, 100, scrollable: find.byType(Scrollable).first);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('screenshots: Today and This week (for looking at)', (tester) async {
      for (final dark in [false, true]) {
        await _open(tester, dark: dark, doc: _plan(generatedAt: DateTime.utc(2026, 10, 30, 0, 30)));
        await shot(tester, 'plan_today_${dark ? 'dark' : 'light'}');
        await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
        await tester.pumpAndSettle();
        await shot(tester, 'plan_week_${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('the orange dot: the plan changed since the guide last opened it', () {
    late FakeFirebaseFirestore db;
    setUp(() async {
      db = FakeFirebaseFirestore();
      GuideDb.useForTests(db);
      SeenMarkers.debugDisable = false;
      UnseenAggregates.debugDisable = false;
    });
    tearDown(() {
      GuideDb.useForTests(null);
      SeenMarkers.debugDisable = true;
      UnseenAggregates.debugDisable = false;
    });

    Future<bool> dot() => UnseenAggregates.planUnseen('G').first.timeout(const Duration(seconds: 2));
    Future<void> writePlan(DateTime changedAt) => db.collection('guidePlans').doc('G').set({
          'adminId': 'G', 'today': {'date': '2026-10-30', 'items': <Object>[]}, 'week': {'weekOf': '2026-10-26', 'intro': '', 'sections': <Object>[]},
          'status': 'upToDate', 'generatedAt': Timestamp.fromDate(changedAt), 'changedAt': Timestamp.fromDate(changedAt),
        });

    test('a new plan nobody has opened shows the dot; opening the Plan page clears it; a later change brings it back', () async {
      await writePlan(DateTime(2026, 10, 1, 6));
      expect(await dot(), isTrue, reason: 'never opened');
      await SeenMarkers.markSeen('G', 'plan');
      expect(await dot(), isFalse, reason: 'opened');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await writePlan(DateTime.now().add(const Duration(minutes: 5)));
      expect(await dot(), isTrue, reason: 'the plan changed after it was last seen');
    });

    test('no plan, no dot', () async {
      expect(await dot(), isFalse);
    });

    testWidgets('opening the page marks it seen', (tester) async {
      await writePlan(DateTime(2026, 10, 1, 6));
      phone(tester, 1.0);
      AdminProfileProvider.instance.debugSet(_me());
      PlanData.instance = const FirestorePlanData();
      await tester.pumpWidget(guideHost(const PlanPage()));
      await tester.pump();
      await tester.pump();
      final seen = (await db.collection('seenMarkers').doc('G').get()).data();
      expect(seen?['plan'], isNotNull, reason: 'the marker is written when the page opens');
    });
  });
}
