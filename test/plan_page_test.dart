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

/// The Plan page (Today | This week), READ-ONLY, kept current two ways: the free updates that appear by themselves, and the REFRESH button
/// (the AI writes it again; once per 2 minutes; a HOD also has "Refresh all guides"). Under "Last updated" it says when and by what:
/// "Last updated: Fri 30 Oct, 6:00 AM (daily update)", then Up to date / Refreshing… / Updated.

/// Friday 30 Oct 2026, 10:00 IST = 04:30 UTC.
final DateTime _now = DateTime.utc(2026, 10, 30, 4, 30);

class _FakePlanData extends PlanData {
  _FakePlanData();
  final controller = StreamController<PlanDoc?>.broadcast();
  final pendingC = StreamController<PendingChanges>.broadcast();
  @override
  Stream<PendingChanges> pending(String adminId) => pendingC.stream;
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
  String intro = 'Hare Krishna Gopal! 2 students could use a little of your time this week.',
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
            PlanSection(id: 'approach', title: 'Students who need you', items: [
              PlanItem(id: 'invite:u3:2026-10-26', kind: 'invite', title: 'Call Kishan', detail: 'Call him. Check with him first: he may not be able to come.', checkWithHim: true, forYou: true, gender: 'male'),
              PlanItem(id: 'approach:u4:2026-10-26', kind: 'approach', title: 'Spend time with Kishor', detail: 'Spend personal time with him.', forYou: true),
            ]),
            PlanSection(id: 'build', title: 'Interactions to build this week', items: [
              PlanItem(id: 'buildInteraction:u5:2026-10-26', kind: 'buildInteraction', title: 'Call Ravi (build the connection)', scheduledFor: '2026-11-02'),
            ]),
            PlanSection(id: 'targets', title: 'Your targets', items: [PlanItem(id: 'target:t1', kind: 'targetProgress', title: 'Chanting target: phase 2 of 4', detail: '8 weeks left.')]),
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

  group('the words: "Last updated … (by …)" and the status', () {
    test('by refresh / daily update / weekly update, India time', () {
      final at = DateTime.utc(2026, 10, 30, 0, 30); // 6:00 AM IST
      expect(planLastUpdated(_plan(refreshedAt: at, refreshedBy: 'daily')), 'Last updated: Fri 30 Oct, 6:00 AM (daily update)');
      expect(planLastUpdated(_plan(refreshedAt: at, refreshedBy: 'refresh')), 'Last updated: Fri 30 Oct, 6:00 AM (by refresh)');
      expect(planLastUpdated(_plan(refreshedAt: at, refreshedBy: 'weekly')), 'Last updated: Fri 30 Oct, 6:00 AM (weekly update)');
    });
    test('a plan the AI has not rewritten yet shows when it was worked out, with no "by"', () {
      expect(planLastUpdated(_plan(generatedAt: DateTime.utc(2026, 10, 30, 0, 30))), 'Last updated: Fri 30 Oct, 6:00 AM');
    });
    test('status: up to date, or refreshing', () {
      expect(planStatusText(_plan()), 'Up to date');
      expect(planStatusText(_plan(status: 'updating')), 'Refreshing…');
      expect(planStatusText(_plan(), refreshing: true), 'Refreshing…');
    });
    test('clock face in India time, 12-hour', () {
      expect(planClock(DateTime.utc(2026, 10, 30, 0, 30)), '6:00 AM');
      expect(planClock(DateTime.utc(2026, 10, 30, 6, 30)), '12:00 PM');
      expect(planClock(DateTime.utc(2026, 10, 30, 18, 25)), '11:55 PM');
      expect(planClock(DateTime.utc(2026, 10, 30, 18, 30)), '12:00 AM');
    });
  });

  group('the page', () {
    testWidgets('read-only line and the Refresh note, at the top; TODAY | THIS WEEK in the app bar; no hourly promise, no countdown', (tester) async {
      await _open(tester);
      expect(find.text('Read-only — for any help, ask the AI in a chat.'), findsOneWidget);
      expect(find.text('Tap Refresh to update the plan with your latest changes.'), findsOneWidget);
      expect(find.textContaining('about an hour'), findsNothing);
      expect(find.textContaining('updating in'), findsNothing);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
    });

    testWidgets('the Refresh button is the first thing under the app bar, above the notes', (tester) async {
      await _open(tester);
      final refresh = tester.getTopLeft(find.byKey(const ValueKey('plan-refresh'))).dy;
      expect(refresh, lessThan(tester.getTopLeft(find.byKey(const ValueKey('plan-readonly'))).dy));
      expect(tester.getSize(find.byKey(const ValueKey('plan-refresh'))).height, greaterThanOrEqualTo(48));
      expect(find.text('Refresh'), findsOneWidget);
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

    testWidgets('Today lists exactly what the server wrote; This week shows its intro and sections, with dates for scheduled items', (tester) async {
      await _open(tester);
      expect(find.textContaining('Today — Friday 30 October'), findsOneWidget);
      expect(find.text('Meet Harsh'), findsOneWidget);
      expect(find.text('Follow up with Kishan'), findsOneWidget);
      expect(find.text('Students who need you'), findsNothing, reason: 'the week plan is on the other tab');
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hare Krishna Gopal!'), findsOneWidget);
      for (final t in ['Students who need you', 'Interactions to build this week', 'Your targets', 'Call Kishan', 'Chanting target: phase 2 of 4']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Mon 2 Nov'), findsOneWidget, reason: 'a scheduled item shows its day');
      expect(find.text('Meet Harsh'), findsNothing, reason: 'one-day tasks are in Today only');
      expect(find.text('Follow up with Kishan'), findsNothing);
    });

    testWidgets('a Localite suggestion carries "Check with him first"; in-person items say "For you to do"', (tester) async {
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      expect(find.text('Check with him first'), findsOneWidget);
      expect(find.text('For you to do'), findsNWidgets(2));
    });

    testWidgets('no plan yet: a friendly line; an empty day says so', (tester) async {
      final data = await _open(tester);
      await _emit(tester, data, null);
      expect(find.byKey(const ValueKey('plan-empty')), findsOneWidget);
      await _emit(tester, data, _plan(today: const [], sections: const []));
      expect(find.byKey(const ValueKey('plan-today-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      // nothing is hidden: the counts are 0 and every section says "None yet"
      expect(find.byKey(const ValueKey('plan-progress')), findsOneWidget);
      expect(find.text('Interactions needed: 0 · done 0 · left 0'), findsOneWidget);
      for (final id in ['interactions', 'targets', 'ahead', 'calendar', 'milestones']) {
        expect(find.byKey(ValueKey('plan-week-empty-$id')), findsOneWidget, reason: id);
      }
    });

    testWidgets('opened for THIS WEEK (from Home) it starts on that tab', (tester) async {
      await _open(tester, page: const PlanPage(initialWeek: true));
      expect(find.textContaining('Hare Krishna Gopal!'), findsOneWidget);
      expect(find.textContaining('Today — Friday'), findsNothing);
    });
  });

  group('TODAY is three sections: Follow-ups, Target tasks, Other tasks', () {
    testWidgets('each task is in exactly one section (an interaction with any non-target reason is a follow-up)', (tester) async {
      await _open(tester, doc: _batchPlan(), size: const Size(360, 3200));
      for (final k in ['followups', 'targets', 'other']) {
        expect(find.byKey(ValueKey('plan-section-$k')), findsOneWidget, reason: k);
      }
      for (final title in ['Follow-ups', 'Target tasks', 'Other tasks']) {
        expect(find.descendant(of: find.byType(Scrollable).first, matching: find.text(title)), findsWidgets, reason: title);
      }
      double y(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
      expect(y('plan-section-followups'), lessThan(y('plan-item-interaction:u1:2026-10-28')));
      expect(y('plan-item-interaction:u1:2026-10-28'), lessThan(y('plan-item-interaction:u2:2026-10-28')), reason: 'Amit (doubt + target) is a follow-up');
      expect(y('plan-item-interaction:u2:2026-10-28'), lessThan(y('plan-section-targets')));
      expect(y('plan-section-targets'), lessThan(y('plan-item-interaction:u3:2026-10-28')), reason: 'Mohit (target only) is a target task');
      expect(y('plan-item-interaction:u3:2026-10-28'), lessThan(y('plan-section-other')));
      expect(y('plan-section-other'), lessThan(y('plan-item-meeting:u9:2026-10-30')));
    });

    testWidgets('a section with nothing in it is still there: "None yet"', (tester) async {
      await _open(tester, doc: planDoc(left: 1, today: [interactionItem('u1', 'Ravi', ['sadhana'])]), size: const Size(360, 3200));
      expect(find.byKey(const ValueKey('plan-section-followups')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-targets')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-other')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-empty-followups')), findsNothing);
      expect(find.byKey(const ValueKey('plan-section-empty-targets')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-empty-other')), findsOneWidget);
      expect(find.text('None yet'), findsNWidgets(2));
    });

    testWidgets('EVERY COUNT IS ALWAYS SHOWN, 0 when there is none: interactions done / left, pending this week, target tasks, other tasks, meetings, doubts', (tester) async {
      await _open(tester, doc: planDoc(), size: const Size(360, 3200));
      String c(String k) => tester.widget<Text>(find.byKey(ValueKey('plan-count-$k'))).data!;
      for (final k in ['interactions-done', 'interactions-left', 'pending', 'target-tasks', 'other-tasks', 'meetings', 'doubts']) {
        expect(c(k), '0', reason: k);
      }
      expect(find.textContaining('done 0 · left'), findsOneWidget, reason: "the batch card shows counts");
      await tester.pumpWidget(const SizedBox());
      await _open(tester, doc: _batchPlan(), size: const Size(360, 3200));
      expect(c('interactions-left'), '3');
      expect(c('interactions-done'), '0');
      expect(c('meetings'), '1');
      expect(c('other-tasks'), '2');
      expect(c('target-tasks'), '1');
    });

    for (final g in PlanGroup.values) {
      testWidgets('opened from Home on ${g.name}: the page opens on TODAY and scrolls to that section', (tester) async {
        final items = [
          for (var i = 0; i < 3; i++) interactionItem('f$i', 'Follow$i', ['sadhana']),
          for (var i = 0; i < 3; i++) interactionItem('t$i', 'Target$i', ['target']),
          for (var i = 0; i < 4; i++) PlanItem(id: 'meeting:o$i:2026-10-30', kind: 'meeting', title: 'Meet Other$i', forYou: true),
        ];
        await _open(tester, doc: planDoc(left: 6, today: items), page: PlanPage(section: g));
        await tester.pumpAndSettle();
        final key = switch (g) { PlanGroup.followUp => 'followups', PlanGroup.target => 'targets', PlanGroup.other => 'other' };
        final top = tester.getTopLeft(find.byKey(ValueKey('plan-section-$key'))).dy;
        expect(top, inInclusiveRange(0, 800), reason: 'the section is on screen');
        if (g != PlanGroup.followUp) {
          expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, greaterThan(0), reason: 'the page scrolled down to it');
        }
      });
    }

    testWidgets('opened on a section that is empty today: its title and "Nothing here today."', (tester) async {
      await _open(tester, doc: planDoc(left: 1, today: [interactionItem('u1', 'Ravi', ['sadhana'])]), page: const PlanPage(section: PlanGroup.target));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-section-targets')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-empty-targets')), findsOneWidget);
    });

    testWidgets('a plan with no batch block (an old HOD plan) still shows every section and zero counts', (tester) async {
      await _open(tester, role: 'HOD', doc: _plan());
      expect(find.byKey(const ValueKey('plan-section-other')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-today-counts')), findsOneWidget);
      expect(find.text('Meet Harsh'), findsOneWidget);
    });
  });

  group('"Last updated" and the status', () {
    testWidgets('Last updated shows the time of the last AI update and what made it (India time), on both tabs', (tester) async {
      await _open(tester, doc: _plan(generatedAt: DateTime.utc(2026, 10, 30, 3, 0), refreshedAt: DateTime.utc(2026, 10, 30, 0, 30), refreshedBy: 'daily'));
      expect(_lastUpdated(tester), 'Last updated: Fri 30 Oct, 6:00 AM (daily update)');
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-last-updated')), findsOneWidget);
    });

    testWidgets('Up to date when nothing is being written; Refreshing… while the server writes it', (tester) async {
      final data = await _open(tester);
      expect(_statusText(tester), 'Up to date');
      await _emit(tester, data, _plan(status: 'updating'));
      expect(_statusText(tester), 'Refreshing…');
    });

    testWidgets('Refreshing…, then the new plan appears with a short "Updated" highlight', (tester) async {
      final data = await _open(tester);
      await _emit(tester, data, _plan(status: 'updating'));
      expect(_statusText(tester), 'Refreshing…');
      await _emit(
        tester,
        data,
        _plan(generatedAt: _now, refreshedAt: _now, refreshedBy: 'refresh', today: const [PlanItem(id: 'followup:u9:2026-10-30', kind: 'followUp', title: 'Follow up with Ravi')]),
      );
      expect(_statusText(tester), 'Updated');
      expect(_lastUpdated(tester), 'Last updated: Fri 30 Oct, 10:00 AM (by refresh)');
      expect(find.text('Follow up with Ravi'), findsOneWidget, reason: 'the new plan is on screen');
      expect(find.text('Meet Harsh'), findsNothing);
      final lit = tester.widget<AnimatedContainer>(find.byKey(const ValueKey('plan-status')));
      expect((lit.decoration as BoxDecoration).border, isNotNull);
      await tester.pump(kPlanUpdatedHighlight + const Duration(milliseconds: 100));
      expect(_statusText(tester), 'Up to date');
    });

    testWidgets('a FREE update (a tick, a new item) shows at once on an open page; "Last updated" stays', (tester) async {
      final at = DateTime.utc(2026, 10, 30, 0, 30);
      final data = await _open(tester, doc: _plan(refreshedAt: at, refreshedBy: 'daily'));
      await _emit(tester, data, _plan(generatedAt: _now, refreshedAt: at, refreshedBy: 'daily', today: const [PlanItem(id: 'doubts::x', kind: 'doubtsToAnswer', title: '1 doubt waiting for your answer')]));
      expect(find.text('1 doubt waiting for your answer'), findsOneWidget);
      expect(_lastUpdated(tester), 'Last updated: Fri 30 Oct, 6:00 AM (daily update)');
    });

    testWidgets('a plan that is the same as before does not flash "Updated" on first show', (tester) async {
      await _open(tester);
      expect(_statusText(tester), 'Up to date');
    });
  });

  group('THE PENDING-CHANGES BADGE on the Refresh button', () {
    Future<void> emitPending(WidgetTester tester, _FakePlanData data, PendingChanges p) async {
      data.pendingC.add(p);
      await tester.pump();
      await tester.pump();
    }

    String badge(WidgetTester tester) => tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('plan-refresh-badge')), matching: find.byType(Text))).data!;

    testWidgets('no pending changes: "✓ Up to date" and no badge', (tester) async {
      final data = await _open(tester);
      await emitPending(tester, data, PendingChanges.none);
      expect(find.byKey(const ValueKey('plan-pending-ok')), findsOneWidget);
      expect(find.text('✓ Up to date'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing);
      expect(find.byKey(const ValueKey('plan-pending-line')), findsNothing);
    });

    testWidgets('the badge shows the count; the line says so; a tap lists them newest first', (tester) async {
      final data = await _open(tester);
      await emitPending(tester, data, pendingOf(['interaction with Amit', 'interaction with Ravi']));
      expect(badge(tester), '2');
      expect(find.byKey(const ValueKey('plan-pending-ok')), findsNothing);
      expect(find.text('2 changes the AI has not looked at yet — tap to see'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-refresh-badge')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('pending-summary'))).data, '2 changes: interaction with Ravi; interaction with Amit');
      expect(find.text('2 changes since the last refresh'), findsOneWidget);
      expect(find.text('• interaction with Ravi'), findsOneWidget);
      expect(find.text('• interaction with Amit'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      // the line opens the same list; one change reads in the singular
      await emitPending(tester, data, pendingOf(['doubt from Amit Shah']));
      expect(find.text('1 change the AI has not looked at yet — tap to see'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-pending-line')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('pending-summary'))).data, '1 change: doubt from Amit Shah');
    });

    testWidgets('it counts live, also during the 2-minute wait after a refresh; the refresh clears it', (tester) async {
      HierarchyApi.useForTests((name, data) async => {'ok': true});
      final data = await _open(tester);
      await emitPending(tester, data, pendingOf(['interaction with Ravi']));
      expect(badge(tester), '1');
      await tester.tap(find.byKey(const ValueKey('plan-refresh')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('plan-refresh-wait')), findsOneWidget, reason: 'the 2-minute wait is running');
      // the server cleared the list when the AI considered it ...
      await emitPending(tester, data, PendingChanges.none);
      expect(find.text('✓ Up to date'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing);
      // ... and a new change during the wait shows at once, the button still waiting
      await emitPending(tester, data, pendingOf(['book change: Ravi Kumar, Gita']));
      expect(badge(tester), '1');
      expect(find.byKey(const ValueKey('plan-refresh-wait')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a long list still fits: 120 changes read as 99+; no overflow in light, dark or large text', (tester) async {
      for (final dark in [false, true]) {
        for (final scale in kScales) {
          final data = await _open(tester, scale: scale, dark: dark);
          await emitPending(tester, data, pendingOf([for (var i = 0; i < 120; i++) 'interaction with Student $i']));
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

    test('PendingChanges: the newest first, the summary line, empty records ignored', () {
      final p = PendingChanges.fromDocs([
        {'type': 'interaction', 'text': 'older', 'at': Timestamp.fromDate(DateTime(2026, 10, 30, 9))},
        {'type': 'doubt', 'text': 'newer', 'at': Timestamp.fromDate(DateTime(2026, 10, 30, 11))},
        {'type': 'x', 'text': ''},
      ]);
      expect(p.count, 2);
      expect(p.summary, '2 changes: newer; older');
      expect(PendingChanges.none.summary, '');
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
            PlanSection(id: 'interactions', title: 'Students to contact — planned days', items: [PlanItem(id: 'interaction:u3:2026-10-28', kind: 'interaction', title: 'Interaction with Mohit', studentName: 'Mohit')]),
            PlanSection(id: 'guides', title: 'Guide by guide', items: [PlanItem(id: 'guide:G1', kind: 'guideSummary', title: 'Gopal: 3 for today, 5 interactions needed')]),
          ],
          generatedAt: _now,
          status: 'upToDate',
          changedAt: _now,
          batch: const PlanBatch(size: 4, round: 1, members: 2, carried: 0, nextReady: false, done: 0, left: 2),
          progress: const PlanProgress(needed: 3, done: 0, left: 3, summary: 'Interactions needed: 3 · done 0 · left 3', bySource: []),
        );

    testWidgets('Today: his own batch card, students and tasks in the three sections, THEN "Guide by guide" with one line per guide', (tester) async {
      await _open(tester, role: 'HOD', doc: hodDoc(), size: const Size(360, 3200));
      expect(find.byKey(const ValueKey('plan-batch')), findsOneWidget);
      expect(find.text('Interaction with Ravi'), findsOneWidget);
      expect(find.text('Interaction with Amit'), findsOneWidget);
      expect(find.text('Meet Harsh'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-followups')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-targets')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-other')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-section-guides')), findsOneWidget);
      expect(find.text('Gopal: 3 for today, 5 interactions needed'), findsOneWidget);
      expect(find.text('Govinda: 1 for today, 2 interactions needed'), findsOneWidget);
      // the order on the page: his own tasks, then the guides
      double y(Finder f) => tester.getTopLeft(f).dy;
      expect(y(find.text('Interaction with Ravi')), lessThan(y(find.byKey(const ValueKey('plan-section-guides')))));
      expect(y(find.text('Meet Harsh')), lessThan(y(find.byKey(const ValueKey('plan-section-guides')))));
      expect(y(find.byKey(const ValueKey('plan-section-guides'))), lessThan(y(find.text('Gopal: 3 for today, 5 interactions needed'))));
    });

    testWidgets('This week: his own progress and planned students first, "Guide by guide" last', (tester) async {
      await _open(tester, role: 'HOD', doc: hodDoc(), size: const Size(360, 3200));
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-progress')), findsOneWidget);
      expect(find.text('Interaction with Mohit'), findsOneWidget);
      expect(find.text('Guide by guide'), findsOneWidget);
      double y(Finder f) => tester.getTopLeft(f).dy;
      expect(y(find.text('Interaction with Mohit')), lessThan(y(find.text('Guide by guide'))));
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

    testWidgets('"Last updated" says when the AI wrote it: "(first open today)"', (tester) async {
      final plan = _plan(refreshedAt: DateTime.utc(2026, 10, 30, 3, 30), refreshedBy: 'open');
      expect(planLastUpdated(plan), 'Last updated: Fri 30 Oct, 9:00 AM (first open today)');
    });
  });

  group('the REFRESH button', () {
    Future<List<Map<String, dynamic>>> calls(WidgetTester tester, {Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? answer}) async {
      final sent = <Map<String, dynamic>>[];
      HierarchyApi.useForTests((name, data) async {
        sent.add({'name': name, ...data});
        return answer != null ? answer(name, data) : {'ok': true};
      });
      return sent;
    }

    testWidgets('a tap asks the server to refresh THIS guide\'s plan; "Refreshing…" shows while it works; then the 2-minute wait counts down', (tester) async {
      final done = Completer<Map<String, dynamic>>();
      final sent = await calls(tester, answer: (_, __) => done.future);
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('plan-refresh')));
      await tester.pump();
      expect(sent, [
        {'name': 'refreshPlan'}
      ], reason: 'no "all": only his own plan');
      expect(find.text('Refreshing…'), findsWidgets);
      expect(_statusText(tester), 'Refreshing…');
      await tester.tap(find.byKey(const ValueKey('plan-refresh')));
      await tester.pump();
      expect(sent.length, 1, reason: 'a second tap while it works does nothing');
      done.complete({'ok': true, 'refreshed': 1});
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('plan-refresh-wait')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('plan-refresh-wait'))).data, 'You can refresh again in 120 sec');
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(find.byKey(const ValueKey('plan-refresh-wait'))).data, 'You can refresh again in 119 sec');
      await tester.tap(find.byKey(const ValueKey('plan-refresh')));
      await tester.pump();
      expect(sent.length, 1, reason: 'held back for 2 minutes');
      await tester.pump(const Duration(seconds: 119));
      expect(find.byKey(const ValueKey('plan-refresh-wait')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('plan-refresh')));
      await tester.pump();
      expect(sent.length, 2, reason: 'after the wait it works again');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the server says how long is left when the guide is early (another phone, a second tap): "You can refresh again in N sec"', (tester) async {
      await calls(tester, answer: (_, __) async => {'ok': false, 'retryInSec': 75});
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('plan-refresh')));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('plan-refresh-wait'))).data, 'You can refresh again in 75 sec');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('BUDGET USED UP: the server\'s clear message is shown, and the guide can try again (nothing was used)', (tester) async {
      const message = "This month's AI budget is used up, so the plan can't be refreshed with the AI until next month (a HOD can raise the budget). It still updates by itself when you finish a task or something new comes up.";
      await calls(tester, answer: (_, __) async => throw HierarchyException('resource-exhausted', message));
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('plan-refresh')));
      await tester.pump();
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-refresh-wait')), findsNothing, reason: 'no wait: nothing ran');
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('any other failure says so kindly', (tester) async {
      await calls(tester, answer: (_, __) async => throw Exception('boom'));
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('plan-refresh')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Could not refresh the plan. Please try again.'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('a guide has no "Refresh all guides"; a HOD has, and it sends all: true, with its own wait', (tester) async {
      final sent = await calls(tester);
      await _open(tester);
      expect(find.byKey(const ValueKey('plan-refresh-all')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _open(tester, role: 'HOD');
      expect(find.byKey(const ValueKey('plan-refresh-all')), findsOneWidget);
      expect(find.text('Refresh all guides'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-refresh-all')));
      await tester.pump();
      await tester.pump();
      expect(sent, [
        {'name': 'refreshPlan', 'all': true}
      ]);
      expect(tester.widget<Text>(find.byKey(const ValueKey('plan-refresh-wait'))).data, 'You can refresh all guides again in 120 sec');
      // his own refresh has its own clock
      await tester.tap(find.byKey(const ValueKey('plan-refresh')));
      await tester.pump();
      expect(sent.length, 2);
      expect(sent.last, {'name': 'refreshPlan'});
      await tester.pumpWidget(const SizedBox());
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
            for (final k in ['plan-tab-today', 'plan-tab-week', 'plan-refresh', 'plan-refresh-all']) {
              expect(tester.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48), reason: k);
            }
            for (final status in [_plan(status: 'updating'), _plan(), _plan(refreshedAt: _now, refreshedBy: 'weekly'), _batchPlan()]) {
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
        await _open(tester, dark: dark, doc: _plan(refreshedAt: DateTime.utc(2026, 10, 30, 0, 30), refreshedBy: 'daily'));
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
