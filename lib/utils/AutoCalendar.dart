/// The calendar's AUTOMATIC events: everything the app already knows is coming, drawn on the calendar without anyone typing it.
///
///   target deadline / phase end   `guideTargets/{guide}/targets/{id}` (+ its running phase)
///   follow-up                     an approved interaction's `approvedSummary.followUpDate`
///   interaction                   an interaction dated after the day it was logged (planned ahead)
///   meeting                       a confirmed association (`confirmedDate`)
///   trip (a range)                `expeditions` (`tripDate` .. `endDate`)
///   chanting competition (range)  `chantingChallenges` (`startDate` .. `endDate`)
///
/// Live: [AutoCalendarFeed] listens to the same collections the screens use, so a change at the source (a follow-up date moved, a
/// trip deleted) changes the calendar at once; nothing is copied. Read-only here: a tap opens the screen that edits the item.
/// Scope: the student-based ones come through [StudentScope] (HOD all; a Guide his own, his team's and the unassigned boys'; an
/// Enabler her own and the unassigned of her gender); trips, competitions and targets are the admin's own (the HOD sees all).
///
/// The server's 7 PM reminder (`functions/calendarDayBefore.js`) reads the same sources with the same rules.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../Home/Calendar.dart';
import '../Pages/AssociationManager.dart';
import '../Pages/PlanPage.dart';
import '../Pages/StudentProfilePage.dart';
import '../Pages/ChantingChallengeManager.dart';
import '../Pages/ExpeditionManager.dart';
import '../Pages/GoalHomePage.dart';
import '../Pages/InteractionLogger.dart';
import 'AdminProfile.dart';
import 'CalendarQueries.dart';
import 'GoalCompoundQueries.dart';
import 'GuideDb.dart';
import 'PlanCalendar.dart';
import 'PlanData.dart';
import 'StudentScope.dart';

const String kSourceTarget = 'target';
const String kSourcePhase = 'phase';
const String kSourceFollowUp = 'followUp';
const String kSourceInteraction = 'interaction';
const String kSourceMeeting = 'meeting';
const String kSourceTrip = 'trip';
const String kSourceCompetition = 'competition';

/// A task of the guide's PLAN (Today's and This week's: an interaction, a follow-up, a surrender check, a worry, a doubt, a book due, a target step ...), drawn on
/// its day with the same done state as the plan. See [planCalendarEvents].
const String kSourcePlan = 'plan';

/// A book's due date (an unfinished book with a finish-by date).
const String kSourceBook = 'book';

/// Every automatic kind, in the order the legend lists them.
const List<String> kAutoSources = [
  kSourceTarget,
  kSourceFollowUp,
  kSourceInteraction,
  kSourceMeeting,
  kSourceTrip,
  kSourceCompetition,
];

/// What a guide calls each kind.
const Map<String, String> kAutoSourceLabels = {
  kSourceTarget: 'Target',
  kSourcePhase: 'Target',
  kSourceFollowUp: 'Follow-up',
  kSourceInteraction: 'Interaction',
  kSourceMeeting: 'Meeting',
  kSourcePlan: 'Task',
  kSourceBook: 'Book due',
  kSourceTrip: 'Trip',
  kSourceCompetition: 'Competition',
};

DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String _s(Object? v) => (v ?? '').toString().trim();

/// An automatic calendar event (read from the app's own data, never edited here). Public so the plan's tasks can be drawn too.
CalendarEvent autoCalendarEvent({
  required String id,
  required String source,
  bool done = false,
  String section = '',
  required DateTime start,
  DateTime? end,
  required String title,
  String note = '',
  String refId = '',
  String studentUid = '',
  String studentName = '',
  String guideId = '',
}) {
  final s = _day(start);
  final e = end == null ? null : _day(end);
  return CalendarEvent(
    id: id,
    eventDate: s,
    endDate: e != null && e.isAfter(s) ? e : null,
    type: kDefaultEventType,
    title: title,
    note: note,
    sourceTextBlockId: '',
    scope: kScopePersonal,
    ownerGuideId: null,
    notifyOffsets: const [],
    source: source,
    refId: refId.isEmpty ? id : refId,
    studentUid: studentUid,
    studentName: studentName,
    guideId: guideId,
    done: done,
    section: section,
  );
}

/// Follow-ups: approved interactions with a follow-up date.
List<CalendarEvent> followUpEvents(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> logs) {
  final out = <CalendarEvent>[];
  for (final d in logs) {
    final m = d.data();
    if (m['status'] != 'approved') continue;
    final sum = m['approvedSummary'];
    if (sum is! Map) continue;
    final when = _ts(sum['followUpDate']);
    if (when == null) continue;
    final who = _s(m['studentName']).isEmpty ? 'a student' : _s(m['studentName']);
    out.add(autoCalendarEvent(
      id: 'followUp_${d.id}',
      source: kSourceFollowUp,
      start: when,
      title: 'Follow-up: $who',
      note: _s(sum['recommendedNextAction']),
      refId: d.id,
      studentUid: _s(m['studentUid']),
      studentName: _s(m['studentName']),
      guideId: _s(m['scopeGuide']).isNotEmpty ? _s(m['scopeGuide']) : _s(m['guideId']),
    ));
  }
  return out;
}

/// Interactions planned ahead: dated after the day they were logged (or, with no log time yet, after today).
List<CalendarEvent> plannedInteractionEvents(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> logs, {DateTime? now}) {
  final today = _day(now ?? DateTime.now());
  final out = <CalendarEvent>[];
  for (final d in logs) {
    final m = d.data();
    final when = _ts(m['interactionDate']);
    if (when == null) continue;
    final made = _ts(m['createdAt']);
    final planned = made != null ? _day(when).isAfter(_day(made)) : _day(when).isAfter(today);
    if (!planned) continue;
    final who = _s(m['studentName']).isEmpty ? 'a student' : _s(m['studentName']);
    out.add(autoCalendarEvent(
      id: 'interaction_${d.id}',
      source: kSourceInteraction,
      start: when,
      title: 'Interaction: $who',
      note: _s(m['interactionType']),
      refId: d.id,
      studentUid: _s(m['studentUid']),
      studentName: _s(m['studentName']),
      guideId: _s(m['scopeGuide']).isNotEmpty ? _s(m['scopeGuide']) : _s(m['guideId']),
    ));
  }
  return out;
}

/// Meetings, in every state: a REQUEST waiting for the guide (on the day asked for), a CONFIRMED one (its day) and a HELD one (its day, ticked). A cancelled
/// one is not shown.
List<CalendarEvent> meetingEvents(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> meetings) {
  final out = <CalendarEvent>[];
  for (final d in meetings) {
    final m = d.data();
    final status = _s(m['status']);
    if (status != 'confirmed' && status != 'pending' && status != 'completed') continue;
    final when = status == 'pending' ? (_ts(m['preferredDate']) ?? _ts(m['confirmedDate'])) : (_ts(m['confirmedDate']) ?? _ts(m['preferredDate']));
    if (when == null) continue;
    final who = _s(m['studentName']).isEmpty ? 'a student' : _s(m['studentName']);
    out.add(autoCalendarEvent(
      id: 'meeting_${d.id}',
      source: kSourceMeeting,
      start: when,
      title: switch (status) { 'pending' => 'Meeting request: $who', 'completed' => 'Meeting held: $who', _ => 'Meeting: $who' },
      note: status == 'pending' ? _s(m['studentNotes']) : '',
      refId: d.id,
      studentUid: _s(m['studentUid']),
      studentName: _s(m['studentName']),
      guideId: _s(m['scopeGuide']).isNotEmpty ? _s(m['scopeGuide']) : _s(m['guideId']),
      done: status == 'completed',
      section: 'meetings',
    ));
  }
  return out;
}

/// Book due dates: every unfinished book that has a finish-by date, on that date ([names] gives the students' names by uid).
List<CalendarEvent> bookDueEvents(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> books, Map<String, String> names) {
  final out = <CalendarEvent>[];
  for (final d in books) {
    final m = d.data();
    if (_s(m['endDate']).isNotEmpty) continue;
    final due = DateTime.tryParse(_s(m['commitmentDate']));
    if (due == null) continue;
    final uid = _s(m['uid']);
    final who = names[uid] ?? 'a student';
    final title = _s(m['bookTitle']).isEmpty ? 'a book' : _s(m['bookTitle']);
    out.add(autoCalendarEvent(
      id: 'book_${d.id}',
      source: kSourceBook,
      start: due,
      title: 'Book due: $who',
      note: title,
      refId: d.id,
      studentUid: uid,
      studentName: who,
      guideId: _s(m['scopeGuide']),
      section: 'others',
    ));
  }
  return out;
}

/// Trips: a range from the trip date to its last day (archived and cancelled ones are not shown).
List<CalendarEvent> tripEvents(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> trips) {
  final out = <CalendarEvent>[];
  for (final d in trips) {
    final m = d.data();
    if (m['archived'] == true || _s(m['status']) == 'cancelled') continue;
    final start = _ts(m['tripDate']);
    if (start == null) continue;
    final name = _s(m['title']).isNotEmpty ? _s(m['title']) : (_s(m['location']).isNotEmpty ? _s(m['location']) : 'a trip');
    out.add(autoCalendarEvent(
      id: 'trip_${d.id}',
      source: kSourceTrip,
      start: start,
      end: _ts(m['endDate']),
      title: 'Trip: $name',
      note: _s(m['location']) == name ? '' : _s(m['location']),
      refId: d.id,
      guideId: _s(m['createdBy']),
    ));
  }
  return out;
}

/// `dd-MM-yyyy` (the competitions' date keys) as a date.
DateTime? _dateOfKey(Object? key) {
  final m = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(_s(key));
  return m == null ? null : DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
}

/// Chanting competitions: a range from the first to the last day (only the ones still running).
List<CalendarEvent> competitionEvents(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> competitions) {
  final out = <CalendarEvent>[];
  for (final d in competitions) {
    final m = d.data();
    final status = _s(m['status']);
    if (status.isNotEmpty && status != 'active') continue;
    final start = _ts(m['startDate']) ?? _dateOfKey(m['startDateKey']) ?? _ts(m['targetDate']) ?? _dateOfKey(m['targetDateKey']);
    final end = _ts(m['endDate']) ?? _dateOfKey(m['endDateKey']) ?? _ts(m['targetDate']) ?? _dateOfKey(m['targetDateKey']);
    if (start == null) continue;
    out.add(autoCalendarEvent(
      id: 'competition_${d.id}',
      source: kSourceCompetition,
      start: start,
      end: end,
      title: 'Competition: ${_s(m['name']).isEmpty ? 'chanting competition' : _s(m['name'])}',
      refId: d.id,
      guideId: _s(m['guideId']),
    ));
  }
  return out;
}

/// A target's deadline, and the end of the phase now running (a phase runs a week from when it started; never past the deadline).
List<CalendarEvent> targetEvents(String guideId, CompoundTarget t, CompoundPhase? running) {
  if (!t.isActive) return const [];
  final label = t.metric == 'books' ? 'books' : 'chanting';
  final out = <CalendarEvent>[];
  final deadline = t.endDate;
  if (deadline != null) {
    out.add(autoCalendarEvent(id: 'target_${guideId}_${t.targetId}', source: kSourceTarget, start: deadline, title: 'Target deadline: $label', refId: t.targetId, guideId: guideId));
  }
  final started = running?.startedAt;
  if (running != null && started != null && running.status == kCompoundPhaseActive) {
    var end = _day(started).add(const Duration(days: 6));
    if (deadline != null && end.isAfter(_day(deadline))) end = _day(deadline);
    out.add(autoCalendarEvent(
      id: 'phase_${guideId}_${t.targetId}_${running.phaseNumber}',
      source: kSourcePhase,
      start: end,
      title: 'Phase ${running.phaseNumber} ends: $label',
      refId: t.targetId,
      guideId: guideId,
    ));
  }
  return out;
}

/// The page where an automatic event's item is edited (null for a manual event: its own dialog edits it).
Widget? autoEventPage(CalendarEvent e) {
  switch (e.source) {
    case kSourceTarget:
    case kSourcePhase:
      return GoalHomePage(guideId: e.guideId);
    case kSourceFollowUp:
    case kSourceInteraction:
      return e.studentUid.isEmpty ? null : InteractionLoggerPage(studentUid: e.studentUid, studentName: e.studentName);
    case kSourceMeeting:
      return AssociationManagerPage(highlightAssociationId: e.refId.isEmpty ? null : e.refId);
    case kSourceBook:
      return e.studentUid.isEmpty ? null : CalendarPage(username: e.studentName, role: '', studentUid: e.studentUid, startOnBooks: true, focusBookDocId: e.refId, booksHint: 'Mark it finished, or tap the book to set a new due date.');
    case kSourcePlan:
      return e.studentUid.isEmpty ? const PlanPage() : StudentProfilePage(studentUid: e.studentUid);
    case kSourceTrip:
      return const ExpeditionManagerPage();
    case kSourceCompetition:
      return const ChantingChallengeManagerPage();
    default:
      return null;
  }
}

/// The live feed of automatic events for the signed-in admin.
///
/// One subscription per source; whenever any of them changes, the whole merged list is emitted again. A source that fails (a
/// permission, a network blip) simply contributes nothing - the others still show.
class AutoCalendarFeed {
  AutoCalendarFeed(this.profile, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AdminProfile profile;
  final DateTime Function() _clock;

  /// The same events, read once (for the AI assistant): the same sources, the same scope, the same builders as [events].
  Future<List<CalendarEvent>> load() async {
    final scope = StudentScope(profile);
    final db = GuideDb.instance;
    final out = <CalendarEvent>[];
    Future<void> part(Future<List<CalendarEvent>> Function() read) async {
      try {
        out.addAll(await read());
      } catch (_) {/* a source that cannot be read costs only itself */}
    }

    await part(() async {
      final logs = (await scope.historyGet('interactionLogs')).docs;
      return [...followUpEvents(logs), ...plannedInteractionEvents(logs, now: _clock())];
    });
    await part(() async => meetingEvents((await scope.historyGet('associations')).docs));
    await part(() async {
      final names = {for (final d in (await scope.studentsGet()).docs) d.id: _s(d.data()['name'])};
      return bookDueEvents((await scope.historyGet('booksRead')).docs, names);
    });
    await part(() async => planCalendarEvents(await PlanData.instance.plan(profile.id).first.timeout(const Duration(seconds: 4))));
    await part(() async {
      final trips = db.collection('expeditions');
      return tripEvents((await (profile.isHod ? trips : trips.where('createdBy', isEqualTo: profile.id)).get()).docs);
    });
    await part(() async {
      final comps = db.collection('chantingChallenges');
      return competitionEvents((await (profile.isHod ? comps : comps.where('guideId', isEqualTo: profile.id)).get()).docs);
    });
    final guides = profile.isHod ? [for (final a in profile.admins) a.id] : [profile.id];
    for (final guide in guides) {
      await part(() async {
        final events = <CalendarEvent>[];
        for (final doc in (await compoundTargetsRef(guide).get()).docs) {
          final t = CompoundTarget.from(guide, doc.id, doc.data());
          CompoundPhase? running;
          if (t.isActive) {
            final p = await compoundPhasesRef(guide, doc.id).doc('${t.currentPhase}').get();
            if (p.exists) running = CompoundPhase.from(p.id, p.data() ?? const {});
          }
          events.addAll(targetEvents(guide, t, running));
        }
        return events;
      });
    }
    return out;
  }

  Stream<List<CalendarEvent>> events() {
    late StreamController<List<CalendarEvent>> controller;
    final subs = <StreamSubscription<Object?>>[];
    final parts = <String, List<CalendarEvent>>{};
    // per-target phase subscriptions, rebuilt when the targets change
    final phaseSubs = <String, StreamSubscription<Object?>>{};
    var studentNames = <String, String>{};
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? lastBooks;

    void emit() {
      if (controller.isClosed) return;
      controller.add([for (final p in parts.values) ...p]);
    }

    void listen<T>(String key, Stream<T> source, List<CalendarEvent> Function(T) build) {
      subs.add(source.listen(
        (data) {
          parts[key] = build(data);
          emit();
        },
        onError: (_) {
          parts[key] = const [];
          emit();
        },
      ));
    }

    controller = StreamController<List<CalendarEvent>>(
      onListen: () {
        final scope = StudentScope(profile);
        final db = GuideDb.instance;

        listen('followUps', scope.historyStream('interactionLogs'), (s) => followUpEvents(s.docs));
        listen('interactions', scope.historyStream('interactionLogs'), (s) => plannedInteractionEvents(s.docs, now: _clock()));
        listen('meetings', scope.historyStream('associations'), (s) => meetingEvents(s.docs));
        // EVERYTHING I HAVE TO DO: the plan's own tasks (Today and This week), live with the plan
        listen('plan', PlanData.instance.plan(profile.id), planCalendarEvents);
        // every book's due date, with the students' names (read once; the books stream live)
        subs.add(Stream.fromFuture(scope.studentsGet()).listen((snap) {
          studentNames = {for (final d in snap.docs) d.id: _s(d.data()['name'])};
          if (lastBooks != null) {
            parts['books'] = bookDueEvents(lastBooks!, studentNames);
            emit();
          }
        }, onError: (_) {}));
        subs.add(scope.historyStream('booksRead').listen((s) {
          lastBooks = s.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
          parts['books'] = bookDueEvents(lastBooks!, studentNames);
          emit();
        }, onError: (_) {
          parts['books'] = const [];
          emit();
        }));

        final trips = db.collection('expeditions');
        listen('trips', (profile.isHod ? trips : trips.where('createdBy', isEqualTo: profile.id)).snapshots(), (s) => tripEvents(s.docs));
        final comps = db.collection('chantingChallenges');
        listen('competitions', (profile.isHod ? comps : comps.where('guideId', isEqualTo: profile.id)).snapshots(), (s) => competitionEvents(s.docs));

        // targets: the HOD's calendar carries every admin's, everyone else's their own
        final guides = profile.isHod ? [for (final a in profile.admins) a.id] : [profile.id];
        for (final guide in guides) {
          subs.add(compoundTargetsStream(guide).listen(
            (targets) {
              parts['targets_$guide'] = [for (final t in targets) ...targetEvents(guide, t, null)];
              emit();
              for (final k in phaseSubs.keys.where((k) => k.startsWith('${guide}_')).toList()) {
                phaseSubs.remove(k)?.cancel();
              }
              for (final t in targets.where((t) => t.isActive)) {
                final key = '${guide}_${t.targetId}';
                phaseSubs[key] = compoundPhasesStream(guide, t.targetId).listen(
                  (phases) {
                    CompoundPhase? running;
                    for (final p in phases) {
                      if (p.phaseNumber == t.currentPhase) running = p;
                    }
                    parts['targets_$guide'] = [
                      ...(parts['targets_$guide'] ?? const <CalendarEvent>[]).where((e) => e.refId != t.targetId),
                      ...targetEvents(guide, t, running),
                    ];
                    emit();
                  },
                  onError: (_) {},
                );
              }
            },
            onError: (_) {
              parts['targets_$guide'] = const [];
              emit();
            },
          ));
        }
        emit();
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        for (final s in phaseSubs.values) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }
}
