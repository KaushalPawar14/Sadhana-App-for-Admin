import 'AutoCalendar.dart';
import 'CalendarQueries.dart';
import 'PlanData.dart';
import 'PlanToday.dart';

/// THE PLAN ON THE CALENDAR. The guide's plan (live) draws itself on the calendar, so the calendar shows everything the guide has to do:
///
///   TODAY       exactly Today's tasks (the same rows, the same done ticks), each on today's date, grouped like Today: Follow-ups, Target tasks, Other tasks
///   THIS WEEK   each planned interaction on its planned day (done ones ticked); a target task line (a target's students' steps, a roster task) as a band over the week
///
/// A planned interaction that is already one of Today's tasks is not drawn twice. Meetings, trips, competitions, book deadlines and target dates come from their own
/// sources (see [AutoCalendarFeed]), so they are not drawn again from the plan's "Other tasks" lines.
List<CalendarEvent> planCalendarEvents(PlanDoc? plan) {
  if (plan == null) return const [];
  final today = DateTime.tryParse(plan.todayDate);
  if (today == null) return const [];
  final out = <CalendarEvent>[];
  final view = TodayView.of(plan);
  final inToday = <String>{};
  for (final sec in view.sections) {
    for (final t in sec.tasks) {
      if (t.studentUid.isNotEmpty) inToday.add(t.studentUid);
      // a MEETING topic is the meeting itself: the calendar draws it from the meeting (one entry, with its date and time, gone when it is cancelled), never a second time from the plan
      bool isMeeting(PlanPoint p) => p.kind == 'meeting' || p.kind == 'meeting_request';
      if (t.isCard && t.points.isNotEmpty && t.points.every(isMeeting)) continue;
      final topics = [for (final p in t.points) if (p.title.isNotEmpty && !isMeeting(p)) p.title];
      final who = t.isCard && t.studentName.isNotEmpty ? t.studentName : t.title;
      out.add(autoCalendarEvent(
        id: 'plan_today_${t.id}',
        source: kSourcePlan,
        start: today,
        title: t.isCard && topics.isNotEmpty ? '$who — ${topics.join(', ')}' : who,
        note: t.calNote,
        refId: t.id,
        studentUid: t.studentUid,
        studentName: t.studentName,
        done: t.done,
        section: sec.id,
      ));
    }
  }
  final weekOf = DateTime.tryParse(plan.weekOf);
  for (final sec in plan.sections) {
    if (sec.id == 'interactions') {
      for (final it in sec.items) {
        final day = DateTime.tryParse(it.scheduledFor);
        if (day == null || it.studentUid.isEmpty) continue;
        final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
        if (isToday && inToday.contains(it.studentUid)) continue;
        out.add(autoCalendarEvent(
          id: 'plan_week_${it.studentUid}_${it.scheduledFor}',
          source: kSourcePlan,
          start: day,
          title: 'Interaction: ${it.studentName}',
          note: it.calNote,
          refId: it.id,
          studentUid: it.studentUid,
          studentName: it.studentName,
          done: it.done,
          section: kSectionFollowUps,
        ));
      }
    } else if (sec.id == 'targettasks' && weekOf != null) {
      for (final it in sec.items) {
        final steps = [for (final s in it.steps) s.words];
        out.add(autoCalendarEvent(
          id: 'plan_target_${it.id}',
          source: kSourcePlan,
          start: weekOf,
          end: weekOf.add(const Duration(days: 6)),
          title: it.title,
          note: steps.join(', '),
          refId: it.id,
          done: it.done,
          section: kSectionTargets,
        ));
      }
    }
  }
  return out;
}

/// The groups of a day's list, in the order they are shown: like Today (Follow-ups, Target tasks, Other tasks), then Meetings and Events.
const List<(String, String)> kCalendarGroups = [
  ('followups', 'Follow-ups'),
  ('targets', 'Target tasks'),
  ('others', 'Other tasks'),
  ('meetings', 'Meetings'),
  ('events', 'Events'),
];

/// Which group of a day's list an event is in.
String calendarGroupOf(CalendarEvent e) {
  switch (e.source) {
    case kSourcePlan:
    case kSourceBook:
      return e.section.isEmpty ? 'others' : e.section;
    case kSourceFollowUp:
    case kSourceInteraction:
      return 'followups';
    case kSourceTarget:
    case kSourcePhase:
      return 'targets';
    case kSourceMeeting:
      return 'meetings';
    default:
      return 'events'; // the guide's own events, trips, competitions
  }
}
