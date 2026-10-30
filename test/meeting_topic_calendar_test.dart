import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/PlanCalendar.dart';
import 'package:folk_guide_app/utils/PlanData.dart';

import 'support/plan_fakes.dart';

// A MEETING TOPIC in Today is the meeting itself: the calendar draws the meeting once, from the meeting (with its date and time; gone when it is cancelled), never a
// second time from the plan's topic. The other topics of the same student's card are still drawn.

PlanItem card(List<PlanPoint> points) => PlanItem(
      id: 'interaction:u1:2026-10-30',
      kind: 'interaction',
      title: 'Interaction with Ravi',
      studentUid: 'u1',
      studentName: 'Ravi',
      forYou: true,
      points: points,
    );

void main() {
  const request = PlanPoint(id: 'meeting:m1', kind: 'meeting_request', group: PlanGroup.other, title: 'Meeting request', text: 'He has asked to meet', assocId: 'm1');
  const meeting = PlanPoint(id: 'meeting:m1', kind: 'meeting', group: PlanGroup.other, title: 'Meeting — Fri 30 Oct, 5:00 PM', text: 'Meeting with him', assocId: 'm1');
  const doubt = PlanPoint(id: 'd1', kind: 'doubt', group: PlanGroup.worry, title: 'His doubt', text: 'Answer it');

  test('a card whose only topic is a meeting (a request or the confirmed meeting) adds nothing to the calendar: the meeting itself is drawn from the meeting', () {
    for (final p in [request, meeting]) {
      final events = planCalendarEvents(planDoc(today: [card([p])]));
      expect(events, isEmpty, reason: p.kind);
    }
  });

  test('a card with a meeting AND another topic: the calendar shows the other topic only (never the meeting a second time)', () {
    final events = planCalendarEvents(planDoc(today: [card([meeting, doubt])]));
    expect(events.length, 1);
    expect(events.single.title, 'Ravi — His doubt');
    expect(events.single.title, isNot(contains('Meeting')));
  });

  test('a cancelled meeting is in no topic any more: nothing about it anywhere on the calendar', () {
    final events = planCalendarEvents(planDoc(today: [card([doubt])]));
    expect(events.any((e) => e.title.contains('Meeting')), isFalse);
  });
}
