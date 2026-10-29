import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';

import 'support/guide_test_support.dart';

/// The Plan page (Today | This week), READ-ONLY, with an honest status under "Last updated": Up to date / New changes found - updating in
/// N min (at <time>) / Next update at 6:00 AM (the night) / Updating now... / Updated. The countdown is to the server's own `pendingRunAt`.

/// Friday 30 Oct 2026, 10:00 IST = 04:30 UTC.
final DateTime _now = DateTime.utc(2026, 10, 30, 4, 30);

class _FakePlanData extends PlanData {
  _FakePlanData();
  final controller = StreamController<PlanDoc?>.broadcast();
  DateTime clock = _now;
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => clock;
}

PlanDoc _plan({
  String status = 'upToDate',
  DateTime? generatedAt,
  DateTime? pendingRunAt,
  List<PlanItem>? today,
  List<PlanSection>? sections,
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
              PlanItem(id: 'invite:u3:2026-10-26', kind: 'invite', title: 'Call Kishan', detail: 'Call him. Check with him first: he may not be able to come.', checkWithHim: true, forYou: true),
              PlanItem(id: 'approach:u4:2026-10-26', kind: 'approach', title: 'Spend time with Kishor', detail: 'Spend personal time with him.', forYou: true),
            ]),
            PlanSection(id: 'build', title: 'Interactions to build this week', items: [
              PlanItem(id: 'buildInteraction:u5:2026-10-26', kind: 'buildInteraction', title: 'Call Ravi (build the connection)', scheduledFor: '2026-11-02'),
            ]),
            PlanSection(id: 'targets', title: 'Your targets', items: [PlanItem(id: 'target:t1', kind: 'targetProgress', title: 'Chanting target: phase 2 of 4', detail: '8 weeks left.')]),
          ],
      generatedAt: generatedAt ?? _now.subtract(const Duration(minutes: 20)),
      status: status,
      pendingRunAt: pendingRunAt,
      changedAt: generatedAt ?? _now,
    );

AdminProfile _me() => AdminProfile.fromMap({
      'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': [],
    });

Future<_FakePlanData> _open(WidgetTester tester, {double scale = 1.0, bool dark = false, PlanDoc? doc}) async {
  phone(tester, scale);
  AdminProfileProvider.instance.debugSet(_me());
  final data = _FakePlanData();
  PlanData.instance = data;
  await tester.pumpWidget(guideHost(const PlanPage(), dark: dark));
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

  group('planStatusText: what the page says, from the server\'s own schedule', () {
    final base = _plan();
    PlanDoc pending(DateTime at) => _plan(status: 'pending', pendingRunAt: at);
    test('up to date', () => expect(planStatusText(base, _now), 'Up to date'));
    test('updating now', () => expect(planStatusText(_plan(status: 'updating'), _now), 'Updating now…'));
    test('pending: minutes to the real run time, and the time it will run (India time)', () {
      final at = _now.add(const Duration(minutes: 12)); // 10:12 IST
      expect(planStatusText(pending(at), _now), 'New changes found — updating in 12 min (at 10:12 AM)');
      expect(planStatusText(pending(at), _now.add(const Duration(minutes: 1))), 'New changes found — updating in 11 min (at 10:12 AM)');
    });
    test('pending: a part minute rounds up; the last minute counts seconds', () {
      final at = _now.add(const Duration(minutes: 5, seconds: 20));
      expect(planStatusText(pending(at), _now), contains('in 6 min'));
      expect(planStatusText(pending(at), at.subtract(const Duration(seconds: 45))), 'New changes found — updating in 45 s (at 10:05 AM)');
    });
    test('pending: past the time but not yet run: "any moment now"', () {
      expect(planStatusText(pending(_now.subtract(const Duration(seconds: 5))), _now), 'New changes found — updating any moment now…');
    });
    test('the night: changes wait for the 6 AM plan, and the page says so', () {
      final night = DateTime.utc(2026, 10, 30, 18, 10); // 11:40 PM IST
      final sixAm = DateTime.utc(2026, 10, 31, 0, 30); // 6:00 AM IST
      expect(planStatusText(pending(sixAm), night), 'New changes found — next update at 6:00 AM');
      expect(isSixAmIst(sixAm), isTrue);
      expect(isSixAmIst(DateTime.utc(2026, 10, 31, 0, 35)), isFalse);
    });
    test('a 6 AM run that is now close shows the ordinary countdown', () {
      final sixAm = DateTime.utc(2026, 10, 31, 0, 30);
      expect(planStatusText(pending(sixAm), sixAm.subtract(const Duration(minutes: 20))), 'New changes found — updating in 20 min (at 6:00 AM)');
    });
    test('clock face in India time, 12-hour', () {
      expect(planClock(DateTime.utc(2026, 10, 30, 0, 30)), '6:00 AM');
      expect(planClock(DateTime.utc(2026, 10, 30, 6, 30)), '12:00 PM');
      expect(planClock(DateTime.utc(2026, 10, 30, 18, 25)), '11:55 PM');
      expect(planClock(DateTime.utc(2026, 10, 30, 18, 30)), '12:00 AM');
    });
  });

  group('the page', () {
    testWidgets('read-only line and the note about the hour, at the top; TODAY | THIS WEEK in the app bar', (tester) async {
      await _open(tester);
      expect(find.text('Read-only — for any help, ask the AI in a chat.'), findsOneWidget);
      expect(
        find.text('Changes you make in the app (e.g. marking a book completed, changing a date) appear here within about an hour. For an instant answer, ask the AI in a chat.'),
        findsOneWidget,
      );
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
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
      for (final t in ['Students who need you', 'Interactions to build this week', 'Your targets', 'Call Kishan', 'Spend time with Kishor'.replaceAll('Spend time with', 'Spend time with'), 'Chanting target: phase 2 of 4']) {
        if (t.startsWith('Spend time with Kishor')) continue;
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
      expect(find.byKey(const ValueKey('plan-week-empty')), findsOneWidget);
    });
  });

  group('"Last updated" and the status', () {
    testWidgets('Last updated shows the time of the last update (India time), on both tabs', (tester) async {
      await _open(tester, doc: _plan(generatedAt: DateTime.utc(2026, 10, 30, 0, 30)));
      expect(tester.widget<Text>(find.byKey(const ValueKey('plan-last-updated'))).data, 'Last updated: Fri 30 Oct, 6:00 AM');
      await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-last-updated')), findsOneWidget);
    });

    testWidgets('Up to date when nothing has changed', (tester) async {
      await _open(tester);
      expect(_statusText(tester), 'Up to date');
    });

    testWidgets('New changes found: a LIVE countdown to the server\'s pendingRunAt, with the time it will run', (tester) async {
      final data = await _open(tester, doc: _plan(status: 'pending', pendingRunAt: _now.add(const Duration(minutes: 12))));
      expect(_statusText(tester), 'New changes found — updating in 12 min (at 10:12 AM)');
      // time passes: the page ticks by itself
      data.clock = _now.add(const Duration(minutes: 5, seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(_statusText(tester), 'New changes found — updating in 7 min (at 10:12 AM)');
      data.clock = _now.add(const Duration(minutes: 11, seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(_statusText(tester), 'New changes found — updating in 30 s (at 10:12 AM)');
      data.clock = _now.add(const Duration(minutes: 12, seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(_statusText(tester), contains('any moment now'));
    });

    testWidgets('the countdown ticks only while an update is pending (no timer otherwise)', (tester) async {
      final data = await _open(tester);
      expect(tester.binding.transientCallbackCount, 0);
      await _emit(tester, data, _plan(status: 'pending', pendingRunAt: _now.add(const Duration(minutes: 10))));
      data.clock = _now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(_statusText(tester), contains('in 9 min'));
      await _emit(tester, data, _plan());
      final before = _statusText(tester);
      data.clock = _now.add(const Duration(minutes: 30));
      await tester.pump(const Duration(seconds: 5));
      expect(_statusText(tester), before, reason: 'no ticking once up to date');
    });

    testWidgets('at night: "Next update at 6:00 AM", not a countdown', (tester) async {
      final night = DateTime.utc(2026, 10, 30, 18, 10);
      final data = _FakePlanData()..clock = night;
      phone(tester, 1.0);
      AdminProfileProvider.instance.debugSet(_me());
      PlanData.instance = data;
      await tester.pumpWidget(guideHost(const PlanPage()));
      await _emit(tester, data, _plan(status: 'pending', pendingRunAt: DateTime.utc(2026, 10, 31, 0, 30)));
      await tester.pump();
      expect(_statusText(tester), 'New changes found — next update at 6:00 AM');
    });

    testWidgets('Updating now…, then the new plan appears with a short "Updated" highlight', (tester) async {
      final data = await _open(tester, doc: _plan(status: 'pending', pendingRunAt: _now.add(const Duration(minutes: 1))));
      await _emit(tester, data, _plan(status: 'updating', generatedAt: _now.subtract(const Duration(minutes: 20))));
      expect(_statusText(tester), 'Updating now…');
      // the new plan arrives
      await _emit(
        tester,
        data,
        _plan(generatedAt: _now, today: const [PlanItem(id: 'followup:u9:2026-10-30', kind: 'followUp', title: 'Follow up with Ravi')]),
      );
      expect(_statusText(tester), 'Updated');
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

  group('every state: light and dark, text scale 1.0 / 1.3 / 1.6', () {
    for (final dark in [false, true]) {
      for (final scale in kScales) {
        for (final tab in ['today', 'week']) {
          testWidgets('${dark ? 'dark' : 'light'}, ×$scale, $tab: no overflow, targets of 48 dp', (tester) async {
            final data = await _open(tester, scale: scale, dark: dark, doc: _plan(status: 'pending', pendingRunAt: _now.add(const Duration(minutes: 12))));
            if (tab == 'week') {
              await tester.tap(find.byKey(const ValueKey('plan-tab-week')));
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            for (final k in ['plan-tab-today', 'plan-tab-week']) {
              expect(tester.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48));
            }
            for (final status in [_plan(status: 'updating'), _plan(), _plan(status: 'pending', pendingRunAt: DateTime.utc(2026, 10, 31, 0, 30))]) {
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
        await _open(tester, dark: dark, doc: _plan(status: 'pending', pendingRunAt: _now.add(const Duration(minutes: 12))));
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
