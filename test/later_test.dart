import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/AutoCalendar.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/PlanTopicActions.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

// "LATER": every topic of Today where postponing makes sense has a second button, Later, beside its own. The panel offers tomorrow, next week, next month, mid next month or a chosen
// date, and a note; after the end of the target the topic belongs to it says "He will be removed from this target." The server does the rest (functions/test/topicLater.test.js).

PlanPoint pt(String kind, String title, String text, {String bookId = '', String metric = '', int? to, String targetEnd = '', String bookTitle = '', bool done = false, PlanGroup group = PlanGroup.followUp}) => PlanPoint(
      text: text, group: group, kind: kind, title: title, bookId: bookId, metric: metric, to: to, targetEnd: targetEnd, bookTitle: bookTitle, done: done, id: '$kind:$bookId',
    );

PlanItem card(String uid, String name, List<PlanPoint> points) => PlanItem(
      id: 'interaction:$uid:2026-10-30',
      kind: 'interaction',
      title: 'Interaction with $name',
      studentName: name,
      studentUid: uid,
      points: points,
      cardGroups: [for (final g in PlanGroup.values) if (points.any((p) => p.group == g)) g],
    );

class _Fake extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
}

AdminProfile _me() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

Future<void> _open(WidgetTester tester, PlanItem c) async {
  AdminProfileProvider.instance.debugSet(_me());
  final data = _Fake();
  PlanData.instance = data;
  await pumpScreen(tester, const PlanPage(), size: const Size(360, 4000));
  data.controller.add(planDoc(today: [c], left: 0));
  await tester.pump();
  await tester.pump();
  final rows = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('plan-row-') && !(w.key! as ValueKey<String>).value.startsWith('plan-row-body-'));
  for (var i = 0; i < rows.evaluate().length; i++) {
    await tester.tap(rows.at(i));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDown(() {
    laterClock = DateTime.now;
    debugLaterDatePicker = null;
    HierarchyApi.useForTests(null);
  });
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  group('which topics get Later', () {
    test('every topic where postponing makes sense has a key; a meeting, a request, a done topic and a topic with nothing to name it have none', () {
      final keys = {
        'concern': laterKeyOf(pt('concern', 'Worry', 'x')),
        'doubt': laterKeyOf(pt('doubt', 'Doubt', 'x')),
        'sadhana_slip': laterKeyOf(pt('sadhana_slip', 'His sadhana', 'x')),
        'reporting_habit': laterKeyOf(pt('reporting_habit', 'His daily report', 'x')),
        'discipline_habit': laterKeyOf(pt('discipline_habit', 'His timings', 'x')),
        'surrender': laterKeyOf(pt('surrender', 'Surrender step', 'x')),
        'good_sadhana': laterKeyOf(pt('good_sadhana', 'Well done', 'x')),
        'festival_boost': laterKeyOf(pt('festival_boost', 'Festival', 'x')),
        'surrender_check': laterKeyOf(pt('surrender_check', 'Surrender check', 'x')),
        'target_chanting': laterKeyOf(pt('target_chanting', 'Chanting target', 'x')),
        'target_books': laterKeyOf(pt('target_books', 'Book target', 'x')),
        'target_folk': laterKeyOf(pt('target_folk', 'FOLK target', 'x')),
        'target_task': laterKeyOf(pt('target_task', 'Chanting target', 'x', metric: 'chanting')),
        'book due': laterKeyOf(pt('bookDue', 'Book due', 'x', bookId: 'b1')),
        'overdue book': laterKeyOf(pt('bookDue', 'Overdue book', 'x', bookId: 'b2')),
      };
      expect(keys.values.every((k) => k != null), isTrue, reason: '$keys');
      expect(keys['target_chanting'], 'target:chanting');
      expect(keys['target_task'], 'target:chanting');
      expect(keys['book due'], 'bookDue:b1');
      expect(keys['concern'], 'concern');
      expect(laterKeyOf(pt('meeting', 'Meeting', 'x')), isNull, reason: 'a meeting is rescheduled in the meeting itself');
      expect(laterKeyOf(pt('meeting_request', 'Meeting request', 'x')), isNull);
      expect(laterKeyOf(pt('later_followup', 'Postponed follow-up', 'x')), isNull);
      expect(laterKeyOf(pt('bookDue', 'Book due', 'x')), isNull, reason: 'no book to name');
      expect(laterKeyOf(pt('concern', 'Worry', 'x', done: true)), isNull, reason: 'a done topic');
    });

    test('the quick choices: tomorrow, next week, next month (the same day), mid next month (the 15th); the end of a short month and the year are handled', () {
      String f(DateTime d) => laterDayKey(d);
      var p = laterQuickPicks(DateTime(2026, 10, 30));
      expect(p.map((x) => x.$2), ['Tomorrow', 'Next week', 'Next month', 'Mid next month']);
      expect(p.map((x) => f(x.$3)), ['2026-10-31', '2026-11-06', '2026-11-30', '2026-11-15']);
      p = laterQuickPicks(DateTime(2026, 1, 31));
      expect(f(p[2].$3), '2026-02-28', reason: 'next month has no 31st');
      p = laterQuickPicks(DateTime(2026, 12, 31));
      expect(p.map((x) => f(x.$3)), ['2027-01-01', '2027-01-07', '2027-01-31', '2027-01-15']);
    });
  });

  group('the button on Today', () {
    testWidgets('each postponable topic has Later next to its own button; a meeting, a request and a done topic have none', (tester) async {
      await prepareApp(tester);
      final c = card('s1', 'Ravi', [
        pt('concern', 'Worry', 'Sounded discouraged', group: PlanGroup.worry),
        pt('bookDue', 'Overdue book', 'Gita, due Wed 28 Oct. Overdue by 2 days', bookId: 'b1', bookTitle: 'Gita', group: PlanGroup.other),
        pt('target_chanting', 'Chanting target', 'Chanting: 8 → 12', to: 12, group: PlanGroup.target),
        pt('meeting', 'Meeting', 'Meeting with him today', group: PlanGroup.other),
        pt('doubt', 'Doubt', 'Unanswered doubt', done: true),
      ]);
      await _open(tester, c);
      for (final i in [0, 1, 2]) {
        expect(find.byKey(ValueKey('plan-later-${c.id}-$i')), findsOneWidget, reason: 'topic $i');
        expect(find.byKey(ValueKey('plan-action-${c.id}-$i')), findsOneWidget, reason: 'its own button stays');
        expect(find.descendant(of: find.byKey(ValueKey('plan-later-${c.id}-$i')), matching: find.text('Later')), findsOneWidget);
        expect(tester.getSize(find.byKey(ValueKey('plan-later-${c.id}-$i'))).height, greaterThanOrEqualTo(48));
      }
      expect(find.byKey(ValueKey('plan-later-${c.id}-3')), findsNothing, reason: 'a meeting');
      expect(find.byKey(ValueKey('plan-later-${c.id}-4')), findsNothing, reason: 'a done topic');
    });
  });

  group('the Later panel', () {
    Future<List<Map<String, dynamic>>> openPanel(WidgetTester tester, PlanPoint p, {DateTime? today}) async {
      await prepareApp(tester);
      laterClock = () => today ?? DateTime(2026, 10, 30, 10);
      final calls = <Map<String, dynamic>>[];
      HierarchyApi.useForTests((name, args) async {
        calls.add({'_call': name, ...args});
        return {'ok': true, 'message': 'Postponed.', 'afterTargetEnd': false};
      });
      final c = card('s1', 'Ravi', [p]);
      await _open(tester, c);
      await tester.tap(find.byKey(ValueKey('plan-later-${c.id}-0')));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('it names the topic, offers the five choices and a note; Postpone is off until a date is chosen', (tester) async {
      await openPanel(tester, pt('target_chanting', 'Chanting target', 'Chanting: 8 → 12', to: 12, group: PlanGroup.target));
      expect(find.byKey(const ValueKey('later-title')), findsOneWidget);
      expect(find.textContaining('Ravi: Chanting target'), findsOneWidget);
      for (final k in ['tomorrow', 'week', 'month', 'mid', 'custom']) {
        expect(find.byKey(ValueKey('later-pick-$k')), findsOneWidget, reason: k);
      }
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('Next week'), findsOneWidget);
      expect(find.text('Next month'), findsOneWidget);
      expect(find.text('Mid next month'), findsOneWidget);
      expect(find.byKey(const ValueKey('later-note')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('later-postpone'))).onPressed, isNull, reason: 'no date yet');
      expect(find.byKey(const ValueKey('later-after-target')), findsNothing);
    });

    testWidgets('a quick pick and a note: Postpone sends the topic key, the date, the note, the step and the student; the panel closes and says what happened', (tester) async {
      final calls = await openPanel(tester, pt('target_chanting', 'Chanting target', 'Chanting: 8 → 12', to: 12, group: PlanGroup.target));
      await tester.tap(find.byKey(const ValueKey('later-pick-mid')));
      await tester.pump();
      expect(find.byKey(const ValueKey('later-date')), findsOneWidget);
      expect(find.text('Sunday 15 November 2026'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('later-note')), 'He will move to 12 rounds by mid-November');
      await tester.tap(find.byKey(const ValueKey('later-postpone')));
      await tester.pumpAndSettle();
      final c = calls.singleWhere((c) => c['_call'] == 'postponeTopic');
      expect([c['studentUid'], c['key'], c['date'], c['note'], c['to']], ['s1', 'target:chanting', '2026-11-15', 'He will move to 12 rounds by mid-November', 12]);
      expect(find.byKey(const ValueKey('later-title')), findsNothing, reason: 'the panel closed');
      expect(find.text('Postponed.'), findsOneWidget, reason: 'the server\'s words');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('every quick pick sends its own date; a book carries its id and title; nothing is sent by Cancel', (tester) async {
      final expected = {'tomorrow': '2026-10-31', 'week': '2026-11-06', 'month': '2026-11-30', 'mid': '2026-11-15'};
      for (final e in expected.entries) {
        final calls = await openPanel(tester, pt('bookDue', 'Overdue book', 'Gita, due Wed 28 Oct.', bookId: 'b1', bookTitle: 'Gita', group: PlanGroup.other));
        await tester.tap(find.byKey(ValueKey('later-pick-${e.key}')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('later-postpone')));
        await tester.pumpAndSettle();
        final c = calls.singleWhere((c) => c['_call'] == 'postponeTopic');
        expect([c['key'], c['date'], c['bookTitle']], ['bookDue:b1', e.value, 'Gita'], reason: e.key);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpWidget(const SizedBox());
      }
      final calls = await openPanel(tester, pt('concern', 'Worry', 'x', group: PlanGroup.worry));
      await tester.tap(find.byKey(const ValueKey('later-pick-tomorrow')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('later-cancel')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'Cancel writes nothing');
    });

    testWidgets('a chosen date after the end of the target says so and the button says what it will do; on or before the end there is no warning', (tester) async {
      debugLaterDatePicker = (context, first) async => DateTime(2026, 12, 15);
      final calls = await openPanel(tester, pt('target_chanting', 'Chanting target', 'Chanting: 8 → 12', to: 12, targetEnd: '2026-11-30', group: PlanGroup.target));
      await tester.tap(find.byKey(const ValueKey('later-pick-custom')));
      await tester.pumpAndSettle();
      expect(find.text('Tuesday 15 December 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('later-after-target')), findsOneWidget);
      expect(find.text('This is after your target ends (30 Nov 2026). He will be removed from this target.'), findsOneWidget);
      expect(find.text('Postpone and remove from the target'), findsOneWidget);
      // inside the target: no warning
      await tester.tap(find.byKey(const ValueKey('later-pick-month')));
      await tester.pump();
      expect(find.byKey(const ValueKey('later-after-target')), findsNothing, reason: '30 Nov is the last day of the target: still inside it');
      expect(find.text('Postpone'), findsOneWidget);
      // and on the later date it is sent as it is: the server takes him out
      await tester.tap(find.byKey(const ValueKey('later-pick-custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('later-postpone')));
      await tester.pumpAndSettle();
      expect(calls.single['date'], '2026-12-15');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a failed save keeps the panel open with a sentence, and the guide can try again', (tester) async {
      await prepareApp(tester);
      laterClock = () => DateTime(2026, 10, 30, 10);
      HierarchyApi.useForTests((name, args) async => throw HierarchyException('internal', 'The server is not answering'));
      final c = card('s1', 'Ravi', [pt('concern', 'Worry', 'x', group: PlanGroup.worry)]);
      await _open(tester, c);
      await tester.tap(find.byKey(ValueKey('plan-later-${c.id}-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('later-pick-tomorrow')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('later-postpone')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('later-error')), findsOneWidget);
      expect(find.textContaining('The server is not answering'), findsOneWidget);
      expect(find.byKey(const ValueKey('later-title')), findsOneWidget, reason: 'still open');
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('later-postpone'))).onPressed, isNotNull, reason: 'it can be tried again');
    });

    for (final scale in [1.0, 1.6]) {
      testWidgets('text $scale on a 360 dp phone: the panel fits, nothing overflows', (tester) async {
        await prepareApp(tester);
        phone(tester, scale);
        laterClock = () => DateTime(2026, 10, 30, 10);
        final c = card('s1', 'Ravi', [pt('target_chanting', 'Chanting target', 'Chanting: 8 → 12', to: 12, targetEnd: '2026-11-30', group: PlanGroup.target)]);
        debugLaterDatePicker = (context, first) async => DateTime(2026, 12, 15);
        await _open(tester, c);
        await tester.tap(find.byKey(ValueKey('plan-later-${c.id}-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('later-pick-custom')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('later-after-target')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the calendar', () {
    test('a postponed topic is a calendar entry on its date: "Testing — raise to 12 rounds", with the note, for that student', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('topicPostponements').doc('t8__target:chanting').set({
        'studentUid': 't8', 'studentName': 'Testing', 'label': 'raise to 12 rounds', 'date': '2026-11-15', 'note': 'by mid-November', 'scopeGuide': 'G', 'key': 'target:chanting',
      });
      await db.collection('topicPostponements').doc('bad').set({'studentUid': 'x', 'label': 'x', 'date': 'soon'});
      final events = laterEvents((await db.collection('topicPostponements').get()).docs);
      expect(events, hasLength(1), reason: 'an entry without a real date is skipped');
      final e = events.single;
      expect(e.title, 'Testing — raise to 12 rounds');
      expect(e.eventDate, DateTime(2026, 11, 15));
      expect(e.note, 'by mid-November');
      expect(e.studentUid, 't8');
      expect(e.source, kSourcePlan);
    });
  });
}
