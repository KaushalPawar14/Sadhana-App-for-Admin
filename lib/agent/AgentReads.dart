import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/GuideNotes.dart';

import '../Services/HierarchyApi.dart';
import '../actions/SubmissionActions.dart';
import '../utils/AbcdeActivity.dart' show sadhanaDateKey, latestDayWithPossibleData;
import '../utils/AdminProfile.dart';
import '../utils/BoardQueries.dart';
import '../utils/BookProgressData.dart';
import '../utils/CalendarQueries.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/MusicData.dart';
import '../utils/PlanningQueries.dart' show associationOverdueSince, currentWeekRange, fallsInRange;
import '../utils/SadhanaReportSource.dart' show fetchDateReports;
import '../utils/ServiceAssignments.dart';
import '../utils/ServiceBankContent.dart';
import '../utils/StudentDoubts.dart';
import 'AgentDuplicates.dart';
import 'AgentEnv.dart';
import 'AgentTypes.dart';
import 'NameMatch.dart';
import '../utils/AutoCalendar.dart';

/// The agent's look-ups — everything the model may be told about the guide's world.
///
/// ---------------------------------------------------------------------------
/// Every one runs HERE, under the guide's own sign-in
/// ---------------------------------------------------------------------------
/// The server never reads a student's data; it asks, and these answer. Each student-keyed read
/// goes through [AgentEnv.students] / [StudentScope] (HOD all; Guide own + team + unassigned boys;
/// Male Enabler own + unassigned boys; Female Enabler own + unassigned girls; category separation as
/// built), so what the model sees is exactly what the guide sees in the app — no more, and never a
/// count, a name or a hint of anyone else. `test/agent_scope_test.dart` asks every one of these, as
/// every role, about students that exist only outside that role's scope.
///
/// A result carries `data` (what the model reads) and `entities` (the ids it may then use in a change).

typedef AgentRun = Future<AgentResult> Function(Map<String, dynamic> args, AgentEnv env);

AgentEntity _student(String uid, Map<String, dynamic> d) =>
    AgentEntity('student', uid, (d['name'] ?? '').toString(), {'residence': (d['role'] ?? '').toString(), 'gender': _genderOf(d)});

/// The student's gender as the model reads it: male / female, or 'missing' (it never guesses: it uses the name).
String _genderOf(Map<String, dynamic> d) {
  final g = (d['gender'] ?? '').toString().trim().toLowerCase();
  return g == 'male' || g == 'female' ? g : 'missing';
}

String _s(Object? v) => (v ?? '').toString();

int _limit(Map<String, dynamic> a, {int def = 25, int max = 50}) {
  final n = a['limit'];
  return n is num ? n.toInt().clamp(1, max) : def;
}

DateTime? _dt(Object? v) => v is Timestamp ? v.toDate() : null;

/// Whole days from [from] to [to], by calendar day.
int _daysBetween(DateTime from, DateTime to) =>
    DateTime(to.year, to.month, to.day).difference(DateTime(from.year, from.month, from.day)).inDays;

/// How the student's own guide reads: a name, or "unassigned".
String _guideOf(Map<String, dynamic> d, AgentEnv env) {
  final id = _s(d['guideId']);
  return id.isEmpty ? 'unassigned' : env.adminName(id);
}

Map<String, Object?> _studentRow(String uid, Map<String, dynamic> d, AgentEnv env) => {
      'name': _s(d['name']),
      'residence': _s(d['role']),
      'gender': _genderOf(d),
      'guide': _guideOf(d, env),
      if (d['commitmentRounds'] is num) 'chantingCommitmentRounds': (d['commitmentRounds'] as num).toInt(),
      if (d['readingCommitmentMinutes'] is num) 'readingCommitmentMinutes': (d['readingCommitmentMinutes'] as num).toInt(),
    };

/// Days in a row, ending yesterday, with no sadhana report — the same window the Priority list uses.
Future<int> _daysMissed(String name, String role, DateTime now) async {
  final reports = await fetchDateReports(name, role);
  var day = latestDayWithPossibleData(now);
  var n = 0;
  while (n < 60 && reports[sadhanaDateKey(day)] == null) {
    n++;
    day = day.subtract(const Duration(days: 1));
  }
  return n;
}

// ---------------------------------------------------------------------------
// Students
// ---------------------------------------------------------------------------
Future<AgentResult> findStudents(Map<String, dynamic> a, AgentEnv env) async {
  final all = await env.students();
  final query = _s(a['query']).toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final filter = _s(a['filter']).isEmpty ? 'any' : _s(a['filter']);
  final days = a['days'] is num ? (a['days'] as num).toInt() : null;
  final residence = _s(a['residence']);

  var rows = all.entries.where((e) {
    final name = _s(e.value['name']).toLowerCase();
    if (!query.every(name.contains)) return false;
    if (residence.isNotEmpty && _s(e.value['role']) != residence) return false;
    if (filter == 'unassigned' && _s(e.value['guideId']).isNotEmpty) return false;
    return true;
  }).toList();

  // No exact match for a typed name: look for CLOSE names (a slip, only the first name, digits, spelling) among the students this guide
  // may see - never outside - and hand them back as suggestions only. They are deliberately NOT entities: the assistant must ask
  // "Did you mean ...?", and only after a yes search again by the exact name, which then hands the student over.
  if (query.isNotEmpty && rows.isEmpty) {
    final pool = all.entries.where((e) {
      if (residence.isNotEmpty && _s(e.value['role']) != residence) return false;
      if (filter == 'unassigned' && _s(e.value['guideId']).isNotEmpty) return false;
      return true;
    });
    final close = closeNames<MapEntry<String, Map<String, dynamic>>>(_s(a['query']), pool, (e) => _s(e.value['name']));
    if (close.isNotEmpty) {
      final clear = hasClearBest(close);
      return AgentResult.ok({
        'count': 0,
        'students': <Object?>[],
        'noExactMatch': true,
        'didYouMean': [
          for (final m in (clear ? close.take(1) : close))
            {'name': _s(m.item.value['name']), 'residence': _s(m.item.value['role']), 'gender': _genderOf(m.item.value), 'guide': _guideOf(m.item.value, env)},
        ],
        'note': clear
            ? 'No student is named exactly that, but ONE name is close. Ask the guide once with ask_user: "Did you mean <name>?" with two choices, Yes and No. '
                'Do not act yet. If they say yes, call find_students again with that exact name, then continue. If no, say you could not find that student.'
            : 'No student is named exactly that, but several names are close. Call ask_user with one choice per name (and a "None of these" choice) so the guide picks. '
                'Do not act yet. When they pick, call find_students again with that exact name, then continue.',
      });
    }
  }

  final extra = <String, Map<String, Object?>>{};

  switch (filter) {
    case 'priority':
      final p = await env.priority();
      final on = {for (final s in p.students) s.uid: s};
      rows = rows.where((r) => on.containsKey(r.key)).toList();
      for (final r in rows) {
        extra[r.key] = {'concerns': [for (final f in on[r.key]!.flags) f.label]};
      }
    case 'missed_reports':
      final need = days ?? 3;
      final capped = rows.take(300).toList();
      final missed = <String, int>{};
      for (var i = 0; i < capped.length; i += 15) {
        await Future.wait(capped.skip(i).take(15).map((r) async {
          try {
            missed[r.key] = await _daysMissed(_s(r.value['name']), _s(r.value['role']), env.now);
          } catch (_) {/* one student's failed read must not lose the rest */}
        }));
      }
      rows = capped.where((r) => (missed[r.key] ?? 0) >= need).toList()
        ..sort((x, y) => missed[y.key]!.compareTo(missed[x.key]!));
      for (final r in rows) {
        extra[r.key] = {'daysWithoutReport': missed[r.key]};
      }
    case 'no_recent_meeting':
      final within = days ?? 30;
      final last = <String, DateTime>{};
      for (final d in (await env.scope.historyGet('associations')).docs) {
        final m = d.data();
        if (_s(m['status']) == 'cancelled') continue;
        final when = _dt(m['confirmedDate']) ?? _dt(m['preferredDate']);
        final uid = _s(m['studentUid']);
        if (when != null && (last[uid] == null || when.isAfter(last[uid]!))) last[uid] = when;
      }
      rows = rows.where((r) => last[r.key] == null || _daysBetween(last[r.key]!, env.now) > within).toList();
      for (final r in rows) {
        extra[r.key] = {'lastMeeting': last[r.key] == null ? 'never' : agentDateOf(last[r.key]!)};
      }
    case 'no_recent_interaction':
      final within = days ?? 30;
      final last = <String, DateTime>{};
      for (final d in (await env.scope.historyGet('interactionLogs')).docs) {
        final m = d.data();
        final when = _dt(m['interactionDate']);
        final uid = _s(m['studentUid']);
        if (when != null && (last[uid] == null || when.isAfter(last[uid]!))) last[uid] = when;
      }
      rows = rows.where((r) => last[r.key] == null || _daysBetween(last[r.key]!, env.now) > within).toList();
      for (final r in rows) {
        extra[r.key] = {'lastInteraction': last[r.key] == null ? 'never' : agentDateOf(last[r.key]!)};
      }
    case 'no_book':
      final reading = <String>{};
      for (final d in (await env.scope.historyGet('booksRead')).docs) {
        final m = d.data();
        if (statusForBookEntry(m) == BookStatus.readingNow) reading.add(_s(m['uid']));
      }
      rows = rows.where((r) => !reading.contains(r.key)).toList();
    default:
  }

  rows.sort((x, y) => _s(x.value['name']).toLowerCase().compareTo(_s(y.value['name']).toLowerCase()));
  final shown = rows.take(_limit(a)).toList();
  return AgentResult.ok(
    {
      'count': rows.length,
      'students': [
        for (final r in shown) {..._studentRow(r.key, r.value, env), ...?extra[r.key]},
      ],
      if (query.isNotEmpty && rows.length > 1)
        'note': 'More than one student matches. Ask the guide which one — do not pick.',
      if (rows.length > shown.length) 'more': rows.length - shown.length,
    },
    entities: [for (final r in shown) _student(r.key, r.value)],
  );
}

Future<AgentResult> getStudent(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);

  final booksSnap = await env.scope.historyGet('booksRead', extraEquals: {'uid': uid});
  final assocDocs = await _recordsOf('associations', uid, _s(s['name']), env);
  final logDocs = await _logsOf(uid, _s(s['name']), env);

  final books = [
    for (final d in booksSnap.docs)
      {
        'title': _s(d.data()['bookTitle']),
        'level': _s(d.data()['level']),
        'status': switch (statusForBookEntry(d.data())) {
          BookStatus.finished => 'finished',
          BookStatus.readingNow => 'reading now',
          BookStatus.notStarted => 'not started',
        },
        if (_s(d.data()['commitmentDate']).isNotEmpty) 'finishBy': _s(d.data()['commitmentDate']),
      }
  ];

  final meetings = assocDocs.toList()
    ..sort((x, y) => (_dt(y.data()['confirmedDate']) ?? _dt(y.data()['preferredDate']) ?? DateTime(2000))
        .compareTo(_dt(x.data()['confirmedDate']) ?? _dt(x.data()['preferredDate']) ?? DateTime(2000)));

  final logs = logDocs.map((d) => _dt(d.data()['interactionDate'])).whereType<DateTime>().toList()..sort();

  final p = await env.priority();
  final onList = p.students.where((x) => x.uid == uid).toList();

  final dob = _dt(s['dob']);
  return AgentResult.ok(
    {
      ..._studentRow(uid, s, env),
      if (dob != null) 'dateOfBirth': agentDateOf(dob),
      'books': books,
      'meetings': [
        for (final m in meetings.take(8))
          {
            'status': _s(m.data()['status']),
            'when': agentStamp(m.data()['confirmedDate'] ?? m.data()['preferredDate']),
            'id': m.id,
          }
      ],
      'interactions': {'count': logs.length, if (logs.isNotEmpty) 'last': agentDateOf(logs.last)},
      'priorityConcerns': onList.isEmpty ? <String>[] : [for (final f in onList.first.flags) f.label],
    },
    entities: [
      _student(uid, s),
      for (final m in meetings.take(8)) AgentEntity('association', m.id, 'Meeting with ${_s(s['name'])}', {'status': _s(m.data()['status'])}),
    ],
  );
}

Future<AgentResult> getStudentReports(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final days = a['days'] is num ? (a['days'] as num).toInt().clamp(1, 30) : 7;
  final reports = await fetchDateReports(_s(s['name']), _s(s['role']));
  final rows = <Map<String, Object?>>[];
  var day = latestDayWithPossibleData(env.now);
  for (var i = 0; i < days; i++) {
    final r = reports[sadhanaDateKey(day)];
    rows.add({
      'date': agentDateOf(day),
      if (r == null) 'report': 'none' else ...{
        for (final k in const ['chantRounds', 'bookReading', 'wakeUpTime', 'templeEntry', 'sleepTiming'])
          if (r[k] != null) k: r[k],
      },
    });
    day = day.subtract(const Duration(days: 1));
  }
  return AgentResult.ok(
    {
      'student': _s(s['name']),
      'daysWithoutReportInARow': await _daysMissed(_s(s['name']), _s(s['role']), env.now),
      'days': rows,
    },
    entities: [_student(uid, s)],
  );
}

// ---------------------------------------------------------------------------
// Meetings and interactions
// ---------------------------------------------------------------------------
Future<AgentResult> listMeetings(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  Map<String, dynamic>? one;
  if (uid.isNotEmpty) one = await env.student(uid);
  final status = _s(a['status']);
  final snapDocs = uid.isEmpty ? (await env.scope.historyGet('associations')).docs : await _recordsOf('associations', uid, _s(one!['name']), env);
  final all = await env.students();
  final now = env.now;

  final docs = snapDocs.where((d) {
    final m = d.data();
    final st = _s(m['status']);
    final when = _dt(m['confirmedDate']) ?? _dt(m['preferredDate']);
    return switch (status) {
      'pending' => st == 'pending',
      'confirmed' => st == 'confirmed',
      'upcoming' => st == 'confirmed' && (when == null || !when.isBefore(DateTime(now.year, now.month, now.day))),
      'history' => st == 'completed' || st == 'cancelled',
      'overdue' => associationOverdueSince(m, now) != null,
      _ => true,
    };
  }).toList()
    ..sort((x, y) => (_dt(y.data()['confirmedDate']) ?? _dt(y.data()['preferredDate']) ?? DateTime(2000))
        .compareTo(_dt(x.data()['confirmedDate']) ?? _dt(x.data()['preferredDate']) ?? DateTime(2000)));

  final shown = docs.take(_limit(a)).toList();
  // the guide's own notes on meetings live in the guide-only collection (never on the record the student reads)
  final notes = await guideNotesOf(shown.map((d) => d.id));
  return AgentResult.ok(
    {
      'count': docs.length,
      'meetings': [
        for (final d in shown)
          {
            'id': d.id,
            'student': _s(d.data()['studentName']),
            'status': _s(d.data()['status']),
            'requestedBy': _s(d.data()['requestedBy']),
            'preferred': agentStamp(d.data()['preferredDate']),
            if (d.data()['confirmedDate'] != null) 'confirmed': agentStamp(d.data()['confirmedDate']),
            if (d.data()['counterProposalDate'] != null) 'studentProposed': agentStamp(d.data()['counterProposalDate']),
            if (_s(d.data()['counterProposalNote']).isNotEmpty) 'studentProposalNote': _s(d.data()['counterProposalNote']),
            if (_s(d.data()['studentNotes']).isNotEmpty) 'studentMessage': _s(d.data()['studentNotes']),
            if ((notes[d.id] ?? '').isNotEmpty) 'guideNotes': notes[d.id]!,
          }
      ],
    },
    entities: [
      for (final d in shown)
        AgentEntity('association', d.id, 'Meeting with ${_s(d.data()['studentName'])}', {'status': _s(d.data()['status'])}),
      for (final d in shown)
        if (all[_s(d.data()['studentUid'])] != null) _student(_s(d.data()['studentUid']), all[_s(d.data()['studentUid'])]!),
      if (one != null) _student(uid, one),
    ],
  );
}

/// One student's interaction logs, the way the screens find them. Normally by the student's id. A log written for a student who was
/// added by hand (`manual_...`) and has since registered may still carry the old id (the merge now moves them; older ones are repaired by
/// tools/rekeyManualRecords.js): when the id finds nothing, logs whose id belongs to NO student at all are matched by the name written
/// in them - the way the screens show them - so the assistant never says "none" about what the guide can see.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _recordsOf(String collection, String uid, String name, AgentEnv env) async {
  final direct = (await env.scope.historyGet(collection, extraEquals: {'studentUid': uid})).docs.toList();
  if (direct.isNotEmpty || name.trim().isEmpty) return direct;
  final known = await env.students();
  return (await env.scope.historyGet(collection)).docs.where((d) {
    final u = _s(d.data()['studentUid']);
    return u != uid && !known.containsKey(u) && nameScore(name, _s(d.data()['studentName'])) >= 0.85;
  }).toList();
}

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _logsOf(String uid, String name, AgentEnv env) => _recordsOf('interactionLogs', uid, name, env);

/// Follow-ups: the dates the guide set on approved interactions ("follow up with ... on ..."), exactly what Home and Weekly Planning
/// list (same scoped read, same `status == approved` and `approvedSummary.followUpDate` rules, same Monday-to-Sunday week).
/// `when`: this_week (what the screens show; the default), overdue (before today), upcoming (today or later), all.
Future<AgentResult> listFollowups(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final when = _s(a['when']).isEmpty ? 'this_week' : _s(a['when']);
  final now = env.now;
  final today = DateTime(now.year, now.month, now.day);
  final week = currentWeekRange(now);

  Map<String, dynamic>? one;
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> logs;
  if (uid.isNotEmpty) {
    one = await env.student(uid);
    logs = await _logsOf(uid, _s(one['name']), env);
  } else {
    logs = (await env.scope.historyGet('interactionLogs')).docs;
  }

  final rows = <({String id, String student, String uid, DateTime date, String action})>[];
  for (final d in logs) {
    final m = d.data();
    if (m['status'] != 'approved') continue;
    final sum = m['approvedSummary'];
    if (sum is! Map) continue;
    final raw = sum['followUpDate'];
    if (raw is! Timestamp) continue;
    final date = raw.toDate();
    final keep = switch (when) {
      'overdue' => date.isBefore(today),
      'upcoming' => !date.isBefore(today),
      'all' => true,
      _ => fallsInRange(raw, week.start, week.end),
    };
    if (!keep) continue;
    rows.add((id: d.id, student: (m['studentName'] ?? 'Unknown').toString(), uid: _s(m['studentUid']), date: date, action: _s(sum['recommendedNextAction'])));
  }
  rows.sort((x, y) => x.date.compareTo(y.date));
  final shown = rows.take(_limit(a)).toList();
  final all = await env.students();
  return AgentResult.ok(
    {
      if (one != null) 'student': _s(one['name']),
      'when': when,
      if (when == 'this_week') 'week': '${agentDateOf(week.start)} to ${agentDateOf(week.end.subtract(const Duration(days: 1)))}',
      'count': rows.length,
      'followUps': [
        for (final r in shown)
          {
            'id': r.id,
            'student': r.student,
            'date': agentDateOf(r.date),
            if (r.action.isNotEmpty) 'action': r.action,
            if (r.date.isBefore(today)) 'overdue': true,
          },
      ],
      if (rows.length > shown.length) 'more': rows.length - shown.length,
      if (rows.isEmpty) 'note': 'Nothing is scheduled for that time. Say that plainly; try "upcoming" or "overdue" if useful.',
    },
    entities: [
      if (one != null) _student(uid, one),
      for (final r in shown) AgentEntity('interaction', r.id, 'Interaction with ${r.student} on ${agentDateOf(r.date)}'),
      for (final r in shown)
        if (one == null && all[r.uid] != null) _student(r.uid, all[r.uid]!),
    ],
  );
}

Future<AgentResult> listInteractions(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final docs = await _logsOf(uid, _s(s['name']), env);
  docs
    .sort((x, y) => (_dt(y.data()['interactionDate']) ?? DateTime(2000)).compareTo(_dt(x.data()['interactionDate']) ?? DateTime(2000)));
  final shown = docs.take(a['limit'] is num ? (a['limit'] as num).toInt().clamp(1, 30) : 10).toList();
  return AgentResult.ok(
    {
      'student': _s(s['name']),
      'count': docs.length,
      'interactions': [
        for (final d in shown)
          {
            'id': d.id,
            'date': agentStamp(d.data()['interactionDate']),
            'type': _s(d.data()['interactionType']),
            'status': _s(d.data()['status']),
            if (_s(d.data()['rawDictation']).isNotEmpty) 'notes': _s(d.data()['rawDictation']),
            ...(() {
              final sum = d.data()['approvedSummary'];
              if (sum is! Map) return <String, Object?>{};
              return {
                if (_s(sum['studentConcerns']).isNotEmpty) 'concerns': _s(sum['studentConcerns']),
                if (_s(sum['recommendedNextAction']).isNotEmpty) 'nextAction': _s(sum['recommendedNextAction']),
                if (sum['followUpDate'] != null) 'followUp': agentStamp(sum['followUpDate']),
              };
            })(),
          }
      ],
    },
    entities: [
      _student(uid, s),
      for (final d in shown) AgentEntity('interaction', d.id, 'Interaction with ${_s(s['name'])} on ${agentStamp(d.data()['interactionDate']) ?? '?'}'),
    ],
  );
}

// ---------------------------------------------------------------------------
// Books
// ---------------------------------------------------------------------------
Future<AgentResult> listBooks(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  Map<String, dynamic>? s;
  if (uid.isNotEmpty) s = await env.student(uid);
  final config = await loadBooksConfig();
  final status = <String, BookStatus>{};
  final finishBy = <String, String>{};
  if (uid.isNotEmpty) {
    for (final d in (await env.scope.historyGet('booksRead', extraEquals: {'uid': uid})).docs) {
      final m = d.data();
      final id = '${_s(m['level'])}/${_s(m['bookKey'])}';
      status[id] = statusForBookEntry(m);
      if (_s(m['commitmentDate']).isNotEmpty) finishBy[id] = _s(m['commitmentDate']);
    }
  }
  final entries = [for (final level in kBookLevels) ...?config.byLevel[level]];
  return AgentResult.ok(
    {
      if (s != null) 'student': _s(s['name']),
      'books': [
        for (final b in entries)
          {
            'id': '${b.level}/${b.key}',
            'title': b.title,
            'level': kBookLevelLabels[b.level] ?? b.level,
            'hasLink': b.hasLink,
            if (uid.isNotEmpty)
              'status': switch (status['${b.level}/${b.key}'] ?? BookStatus.notStarted) {
                BookStatus.finished => 'finished',
                BookStatus.readingNow => 'reading now',
                BookStatus.notStarted => 'not started',
              },
            if (finishBy['${b.level}/${b.key}'] != null) 'finishBy': finishBy['${b.level}/${b.key}'],
          }
      ],
    },
    entities: [
      if (s != null) _student(uid, s),
      for (final b in entries) AgentEntity('book', '${b.level}/${b.key}', b.title),
    ],
  );
}

// ---------------------------------------------------------------------------
// Targets, competitions, trips
// ---------------------------------------------------------------------------
Future<AgentResult> listTargets(Map<String, dynamic> a, AgentEnv env) async {
  final me = env.me;
  final owners = me.isHod ? [for (final x in me.admins) if (x.role.name != 'hod') x.id] : [me.id];
  if (me.isHod) owners.add(me.id);
  final targets = <CompoundTarget>[];
  for (final owner in owners.toSet()) {
    try {
      targets.addAll(await compoundTargetsStream(owner).first);
    } catch (_) {/* one guide's unreadable list must not lose the others */}
  }
  return AgentResult.ok(
    {
      'count': targets.length,
      'targets': [
        for (final t in targets)
          {
            'id': '${t.guideId}/${t.targetId}',
            'guide': env.adminName(t.guideId),
            'metric': t.metric,
            'goal': '${t.studentCountGoal} students each at ${t.perStudentValueGoal}',
            'endDate': t.endDate == null ? null : agentDateOf(t.endDate!),
            'status': t.status,
            'phase': '${t.currentPhase} of ${t.totalPhases}',
            if (t.pendingProposal != null) 'planEditWaiting': true,
          }
      ],
    },
    entities: [
      for (final t in targets)
        AgentEntity('target', '${t.guideId}/${t.targetId}', '${t.metric} target ending ${t.endDate == null ? '?' : agentDateOf(t.endDate!)}'),
    ],
  );
}

Future<AgentResult> listCompetitions(Map<String, dynamic> a, AgentEnv env) async {
  final me = env.me;
  final col = env.db.collection('chantingChallenges');
  final snap = await (me.isHod ? col : col.where('guideId', isEqualTo: me.id)).get();
  final want = _s(a['status']);
  final docs = snap.docs.where((d) => want.isEmpty || want == 'all' || _s(d.data()['status']) == want).toList()
    ..sort((x, y) => (_dt(y.data()['endDate']) ?? DateTime(2000)).compareTo(_dt(x.data()['endDate']) ?? DateTime(2000)));
  return AgentResult.ok(
    {
      'count': docs.length,
      'competitions': [
        for (final d in docs.take(30))
          {
            'id': d.id,
            'name': _s(d.data()['name']),
            'target': d.data()['targetRounds'],
            'rounds': d.data()['currentTotal'],
            'from': _s(d.data()['startDateKey']),
            'to': _s(d.data()['endDateKey']).isEmpty ? _s(d.data()['targetDateKey']) : _s(d.data()['endDateKey']),
            'status': _s(d.data()['status']),
          }
      ],
    },
    entities: [for (final d in docs.take(30)) AgentEntity('challenge', d.id, _s(d.data()['name']))],
  );
}

Future<AgentResult> listTrips(Map<String, dynamic> a, AgentEnv env) async {
  final me = env.me;
  final trips = env.db.collection('expeditions');
  final snap = await (me.isHod ? trips : trips.where('createdBy', isEqualTo: me.id)).get();
  final want = _s(a['status']);
  var docs = snap.docs.where((d) {
    final archived = d.data()['archived'] == true;
    if (want == 'archived') return archived;
    if (want == 'all') return true;
    if (archived) return false;
    return want.isEmpty || _s(d.data()['status']) == want;
  }).toList()
    ..sort((x, y) => (_dt(y.data()['tripDate']) ?? DateTime(2000)).compareTo(_dt(x.data()['tripDate']) ?? DateTime(2000)));

  final tripId = _s(a['tripId']);
  final regs = (await env.scope.historyGet('expeditionRegistrations')).docs;
  final byTrip = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  for (final r in regs) {
    byTrip.putIfAbsent(_s(r.data()['tripId']), () => []).add(r);
  }
  if (tripId.isNotEmpty) docs = docs.where((d) => d.id == tripId).toList();

  final students = await env.students();
  return AgentResult.ok(
    {
      'count': docs.length,
      'trips': [
        for (final d in docs.take(20))
          {
            'id': d.id,
            'title': _s(d.data()['title']),
            'from': agentStamp(d.data()['tripDate'])?.substring(0, 10),
            'to': agentStamp(d.data()['endDate'] ?? d.data()['tripDate'])?.substring(0, 10),
            'status': _s(d.data()['status']),
            'for': d.data()['targetGender'] == 'female' ? 'girls' : 'boys',
            'registered': (byTrip[d.id] ?? const []).length,
            if (tripId.isNotEmpty)
              'registrations': [
                for (final r in byTrip[d.id] ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  {'id': r.id, 'student': _s(r.data()['studentName']), 'attendance': _s(r.data()['attendance']).isEmpty ? 'pending' : _s(r.data()['attendance'])},
              ],
          }
      ],
    },
    entities: [
      for (final d in docs.take(20)) AgentEntity('trip', d.id, _s(d.data()['title'])),
      if (tripId.isNotEmpty)
        for (final r in byTrip[tripId] ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) ...[
          AgentEntity('registration', r.id, '${_s(r.data()['studentName'])} on ${docs.isEmpty ? 'the trip' : _s(docs.first.data()['title'])}'),
          if (students[_s(r.data()['studentUid'])] != null) _student(_s(r.data()['studentUid']), students[_s(r.data()['studentUid'])]!),
        ],
    ],
  );
}

// ---------------------------------------------------------------------------
// Priority, doubts, flagged, submissions
// ---------------------------------------------------------------------------
Future<AgentResult> listPriority(Map<String, dynamic> a, AgentEnv env) async {
  final p = await env.priority();
  if (p.rosterFailed) return const AgentResult.failed("I couldn't read your student list just now.");
  final all = await env.students();
  return AgentResult.ok(
    {
      'count': p.students.length,
      'students': [
        for (final s in p.students) {'name': s.name, 'concerns': [for (final f in s.flags) f.label]},
      ],
      'removedByYou': p.hiddenCount,
    },
    entities: [for (final s in p.students) if (all[s.uid] != null) _student(s.uid, all[s.uid]!)],
  );
}

Future<AgentResult> listDoubts(Map<String, dynamic> a, AgentEnv env) async {
  final doubts = await StudentDoubts.stream().first;
  final all = await env.students();
  return AgentResult.ok(
    {
      'count': doubts.length,
      'doubts': [
        for (final d in doubts.take(30))
          {
            'id': d.id,
            'student': d.studentName,
            'book': d.bookTitle,
            'question': d.question,
            if (d.paragraph.isNotEmpty) 'paragraph': d.paragraph,
            'asked': agentStamp(d.askedAt),
          }
      ],
    },
    entities: [
      for (final d in doubts.take(30)) AgentEntity('doubt', d.id, "${d.studentName}'s doubt on ${d.bookTitle}"),
      for (final d in doubts.take(30)) if (all[d.studentUid] != null) _student(d.studentUid, all[d.studentUid]!),
    ],
  );
}

Future<AgentResult> listFlagged(Map<String, dynamic> a, AgentEnv env) async {
  final snap = await env.scope.historyGet('flaggedChatMessages');
  final want = a['reviewed'];
  final docs = snap.docs.where((d) => want is! bool || (d.data()['reviewed'] == true) == want).toList()
    ..sort((x, y) => (_dt(y.data()['createdAt']) ?? DateTime(2000)).compareTo(_dt(x.data()['createdAt']) ?? DateTime(2000)));
  final all = await env.students();
  return AgentResult.ok(
    {
      'count': docs.length,
      'messages': [
        for (final d in docs.take(30))
          {
            'id': d.id,
            'student': _s(d.data()['studentName']),
            'kind': _s(d.data()['kind']).isEmpty ? 'flagged' : _s(d.data()['kind']),
            if (d.data()['acuteRisk'] == true) 'acuteRisk': true,
            if (_s(d.data()['pastoralReason']).isNotEmpty) 'reason': _s(d.data()['pastoralReason']),
            'text': _s(d.data()['text']),
            'reviewed': d.data()['reviewed'] == true,
            'when': agentStamp(d.data()['createdAt']),
          }
      ],
    },
    entities: [
      for (final d in docs.take(30)) AgentEntity('message', d.id, 'Message from ${_s(d.data()['studentName'])}'),
      for (final d in docs.take(30)) if (all[_s(d.data()['studentUid'])] != null) _student(_s(d.data()['studentUid']), all[_s(d.data()['studentUid'])]!),
    ],
  );
}

Future<AgentResult> listSubmissions(Map<String, dynamic> a, AgentEnv env) async {
  final st = await loadSubmissionStatus();
  final all = await env.students();
  return AgentResult.ok(
    {
      'inScope': st.inScope,
      'notSubmitted': [for (final e in st.notSubmitted) e.name],
      'submittedCount': st.submitted.length,
      if (st.unchecked.isNotEmpty) 'couldNotCheck': [for (final e in st.unchecked) e.name],
    },
    entities: [for (final e in st.notSubmitted) if (all[e.uid] != null) _student(e.uid, all[e.uid]!)],
  );
}

// ---------------------------------------------------------------------------
// Calendar, services, music, admins, boards
// ---------------------------------------------------------------------------
Future<AgentResult> listCalendar(Map<String, dynamic> a, AgentEnv env) async {
  final from = a['fromDate'] == null ? DateTime(env.now.year, env.now.month, env.now.day) : agentDay(a['fromDate']);
  final to = a['toDate'] == null ? from.add(const Duration(days: 31)) : agentDay(a['toDate']).add(const Duration(days: 1));
  // The guide's own events AND the ones the app shows by itself (targets, follow-ups, meetings, trips, competitions, planned
  // interactions): exactly what the calendar screen shows, from the same sources.
  final manual = await visibleEventsFor(env.me.id);
  final automatic = await AutoCalendarFeed(env.me, clock: () => env.now).load();
  final events = [...manual, ...automatic].where((e) {
    final end = e.endDate ?? e.eventDate;
    return !end.isBefore(from) && e.eventDate.isBefore(to);
  }).toList()
    ..sort((x, y) => x.eventDate.compareTo(y.eventDate));
  final blocks = await visibleTextBlocksFor(env.me.id);
  final perBlock = <String, int>{for (final e in manual) e.sourceTextBlockId: 0};
  for (final e in manual) {
    perBlock[e.sourceTextBlockId] = (perBlock[e.sourceTextBlockId] ?? 0) + 1;
  }
  return AgentResult.ok(
    {
      'events': [
        for (final e in events.take(60))
          {
            'id': e.id,
            'date': agentDateOf(e.eventDate),
            if (e.endDate != null) 'lastDay': agentDateOf(e.endDate!),
            'title': e.title,
            if (e.note.isNotEmpty) 'note': e.note,
            if (e.isAutomatic) ...{
              // shown by the app from its own data: read-only for you; change it where it lives
              'kind': kAutoSourceLabels[e.source] ?? e.source,
              'readOnly': true,
              'changeItIn': switch (e.source) {
                kSourceTarget || kSourcePhase => 'Targets',
                kSourceFollowUp || kSourceInteraction => "the student's Interactions",
                kSourceMeeting => 'Meetings',
                kSourceTrip => 'Expeditions',
                kSourceCompetition => 'Chanting competitions',
                _ => 'its own screen',
              },
            } else ...{
              'type': e.type,
              'forEveryone': e.scope == kScopeMandatory,
              'blockId': e.sourceTextBlockId,
              'eventsInItsBlock': perBlock[e.sourceTextBlockId] ?? 1,
            },
          }
      ],
      'noteBlocks': [
        for (final b in blocks.take(15))
          {'id': b.id, 'text': b.rawText.length > 300 ? '${b.rawText.substring(0, 300)}…' : b.rawText, 'forEveryone': b.isMandatory},
      ],
    },
    entities: [
      // only the guide's own events are things the assistant may edit or delete; the automatic ones are not entities at all
      for (final e in events.take(60))
        if (!e.isAutomatic) AgentEntity('event', e.id, e.title),
      for (final b in blocks.take(15)) AgentEntity('block', b.id, b.rawText.length > 40 ? '${b.rawText.substring(0, 40)}…' : b.rawText),
    ],
  );
}

Future<AgentResult> listServices(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  Map<String, dynamic>? s;
  if (uid.isNotEmpty) s = await env.student(uid);
  final snap = await env.scope.historyGet('serviceAssignments', extraEquals: uid.isEmpty ? const {} : {'studentUid': uid});
  final all = await env.students();
  final assignments = [for (final d in snap.docs) ServiceAssignment.fromDoc(d.id, d.data())].where((x) => !x.isWithdrawn).toList();
  String title(int n) => kServiceBank.firstWhere((x) => x.number == n, orElse: () => kServiceBank.first).title;
  return AgentResult.ok(
    {
      'services': [for (final x in kServiceBank) {'number': x.number, 'title': x.title}],
      'assignments': [
        for (final x in assignments.take(60))
          if (all[x.studentUid] != null)
            {
              'id': x.id,
              'service': title(x.serviceNumber),
              'student': _s(all[x.studentUid]!['name']),
              'status': x.status,
              if (x.competence != null) 'canDoIt': x.competence!.level,
            }
      ],
    },
    entities: [
      for (final x in kServiceBank) AgentEntity('service', '${x.number}', x.title),
      for (final x in assignments.take(60))
        if (all[x.studentUid] != null) ...[
          AgentEntity('assignment', x.id, '${title(x.serviceNumber)} — ${_s(all[x.studentUid]!['name'])}'),
          _student(x.studentUid, all[x.studentUid]!),
        ],
      if (s != null) _student(uid, s),
    ],
  );
}

Future<AgentResult> listMusic(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  Map<String, dynamic>? s;
  if (uid.isNotEmpty) s = await env.student(uid);
  final store = FirestoreMusicStore(env.db);
  final curriculum = await store.curriculum().first;
  final progress = uid.isEmpty ? MusicProgress.empty : await store.progress(uid).first;
  return AgentResult.ok(
    {
      if (s != null) 'student': _s(s['name']),
      'instruments': [
        for (final i in curriculum)
          {
            'id': i.id,
            'name': i.name,
            if (i.hasLink) 'link': i.link,
            'checkpoints': [
              for (final c in i.checkpoints) {'id': c.id, 'title': c.title, if (uid.isNotEmpty) 'ticked': progress.ticks.containsKey(c.id)},
            ],
          }
      ],
    },
    entities: [
      if (s != null) _student(uid, s),
      for (final i in curriculum) AgentEntity('instrument', i.id, i.name),
      for (final i in curriculum) for (final c in i.checkpoints) AgentEntity('checkpoint', c.id, '${i.name}: ${c.title}'),
    ],
  );
}

Future<AgentResult> listAdmins(Map<String, dynamic> a, AgentEnv env) async {
  final admins = await HierarchyApi.instance.listAdmins();
  return AgentResult.ok(
    {
      'admins': [
        for (final x in admins) {'id': x.id, 'name': x.displayName, 'role': x.role.label, if (x.teamGuide.isNotEmpty) 'team': env.adminName(x.teamGuide)},
      ],
    },
    entities: [for (final x in admins) AgentEntity('admin', x.id, x.displayName, {'role': x.role.wire})],
  );
}

Future<AgentResult> listBoards(Map<String, dynamic> a, AgentEnv env) async {
  final all = await allBoardsStream().first;
  final boards = visibleBoards(all: all, guide: env.me.id, isHod: env.me.isHod);
  final students = await env.students();
  final entities = <AgentEntity>[];
  final out = <Map<String, Object?>>[];
  for (final b in boards.take(20)) {
    final columns = await columnsStream(b.id).first;
    final placements = (await placementsStream(b.id).first).docs;
    entities.add(AgentEntity('board', b.id, b.title));
    out.add({
      'id': b.id,
      'title': b.title,
      'kind': b.isGuideAssignment ? 'guide assignment' : 'custom',
      'mine': b.isOwnedBy(env.me.id),
      'columns': [
        for (final c in columns)
          {
            'id': c.id,
            'title': c.title,
            // only students this guide may see are ever named or counted
            'students': [
              for (final p in placements)
                if (_s(p.data()['columnId']) == c.id && students[p.id] != null) _s(students[p.id]!['name']),
            ],
          }
      ],
    });
    for (final c in columns) {
      entities.add(AgentEntity('column', c.id, '${b.title}: ${c.title}'));
    }
  }
  for (final s in students.entries) {
    entities.add(_student(s.key, s.value));
  }
  return AgentResult.ok({'boards': out}, entities: entities);
}

/// Every read, by the tool id the server knows it as.
// ---------------------------------------------------------------------------
// Comments, LIT assessments and near-duplicate records
// ---------------------------------------------------------------------------
Future<AgentResult> listComments(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final snap = await env.db.collection('studentComments').doc(uid).collection('messages').get();
  final docs = snap.docs.toList()
    ..sort((x, y) => (_dt(y.data()['createdAt']) ?? DateTime(2000)).compareTo(_dt(x.data()['createdAt']) ?? DateTime(2000)));
  final shown = docs.take(a['limit'] is num ? (a['limit'] as num).toInt().clamp(1, 50) : 20).toList();
  return AgentResult.ok(
    {
      'student': _s(s['name']),
      'count': docs.length,
      'comments': [
        for (final d in shown)
          {
            'id': '$uid/${d.id}',
            'when': agentStamp(d.data()['createdAt']),
            'by': _s(d.data()['authorName']),
            'yours': _s(d.data()['authorId']) == env.me.id,
            'text': _s(d.data()['text']),
          }
      ],
    },
    entities: [
      _student(uid, s),
      for (final d in shown) AgentEntity('comment', '$uid/${d.id}', 'Comment by ${_s(d.data()['authorName'])} on ${agentStamp(d.data()['createdAt']) ?? '?'}'),
    ],
  );
}

Future<AgentResult> listLit(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final docs = (await _recordsOf('litAssessments', uid, _s(s['name']), env)).toList()
    ..sort((x, y) => (_dt(y.data()['assessedAt']) ?? DateTime(2000)).compareTo(_dt(x.data()['assessedAt']) ?? DateTime(2000)));
  final shown = docs.take(a['limit'] is num ? (a['limit'] as num).toInt().clamp(1, 30) : 10).toList();
  return AgentResult.ok(
    {
      'student': _s(s['name']),
      'count': docs.length,
      'assessments': [
        for (final d in shown)
          {
            'id': d.id,
            'when': agentStamp(d.data()['assessedAt']),
            'receptivity': d.data()['L'],
            'interest': d.data()['I'],
            'availableTime': d.data()['T'],
            'confidence': _s(d.data()['confidence']),
            'evidence': _s(d.data()['evidence']),
          }
      ],
    },
    entities: [
      _student(uid, s),
      for (final d in shown) AgentEntity('lit', d.id, 'LIT assessment of ${_s(s['name'])} on ${agentStamp(d.data()['assessedAt']) ?? '?'}'),
    ],
  );
}

String _short(String s, [int n = 160]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= n ? t : '${t.substring(0, n - 1)}…';
}

/// Near-identical records of ONE student, for "delete the duplicate": groups of two or more, each record with what the
/// guide needs to compare them, and the ids to act on. Nothing is decided here.
Future<AgentResult> findDuplicates(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final kind = _s(a['kind']);
  final items = <DupItem>[];
  var entityKind = 'interaction';
  var days = 0;
  var minSimilarity = 0.5;

  if (kind == 'interaction' || kind == 'follow_up') {
    final snap = await _logsOf(uid, _s((await env.student(uid))['name']), env);
    for (final d in snap) {
      final m = d.data();
      final sum = m['approvedSummary'] is Map ? m['approvedSummary'] as Map : const {};
      final follow = _dt(sum['followUpDate']);
      if (kind == 'follow_up' && follow == null) continue;
      final nextAction = _s(sum['recommendedNextAction']);
      items.add(DupItem(
        id: d.id,
        // an interaction is "the same" on the same day; a follow-up on the same follow-up day
        when: kind == 'follow_up' ? follow : _dt(m['interactionDate']),
        type: kind == 'follow_up' ? 'follow_up' : _s(m['interactionType']),
        text: kind == 'follow_up' ? nextAction : '${_s(m['rawDictation'])} ${_s(sum['studentConcerns'])} $nextAction ${(sum['themes'] is List ? (sum['themes'] as List).join(' ') : '')}',
        show: {
          'id': d.id,
          'date': agentStamp(m['interactionDate']),
          'type': _s(m['interactionType']),
          if (follow != null) 'followUp': agentStamp(sum['followUpDate']),
          if (nextAction.isNotEmpty) 'nextAction': _short(nextAction),
          if (_s(m['rawDictation']).isNotEmpty) 'notes': _short(_s(m['rawDictation'])),
          if (_s(sum['studentConcerns']).isNotEmpty) 'concerns': _short(_s(sum['studentConcerns'])),
        },
      ));
    }
    if (kind == 'follow_up') minSimilarity = 0.4;
  } else if (kind == 'meeting') {
    entityKind = 'association';
    final snap = await _recordsOf('associations', uid, _s((await env.student(uid))['name']), env);
    final notes = await guideNotesOf(snap.map((d) => d.id));
    for (final d in snap) {
      final m = d.data();
      items.add(DupItem(
        id: d.id,
        when: _dt(m['confirmedDate']) ?? _dt(m['preferredDate']),
        type: _s(m['status']),
        text: '${_s(m['studentNotes'])} ${notes[d.id] ?? ''}',
        show: {
          'id': d.id,
          'status': _s(m['status']),
          'when': agentStamp(m['confirmedDate'] ?? m['preferredDate']),
          if ((notes[d.id] ?? '').isNotEmpty) 'notes': _short(notes[d.id]!),
        },
      ));
    }
    minSimilarity = 0;
  } else {
    entityKind = 'comment';
    final snap = await env.db.collection('studentComments').doc(uid).collection('messages').get();
    days = 2;
    minSimilarity = 0.7;
    for (final d in snap.docs) {
      final m = d.data();
      items.add(DupItem(
        id: '$uid/${d.id}',
        when: _dt(m['createdAt']),
        type: _s(m['authorId']),
        text: _s(m['text']),
        show: {'id': '$uid/${d.id}', 'when': agentStamp(m['createdAt']), 'by': _s(m['authorName']), 'text': _short(_s(m['text']))},
      ));
    }
  }

  final groups = findDuplicateGroups(items, days: days, minSimilarity: minSimilarity);
  return AgentResult.ok(
    {
      'student': _s(s['name']),
      'kind': kind,
      'groupsFound': groups.length,
      'groups': [
        for (final g in groups) [for (final i in g) i.show]
      ],
      if (groups.isEmpty) 'note': 'No near-identical ${kind.replaceAll('_', ' ')}s were found for this student.',
    },
    entities: [
      _student(uid, s),
      for (final g in groups) for (final i in g) AgentEntity(entityKind, i.id, '${kind.replaceAll('_', '-')} of ${_s(s['name'])} on ${agentStamp(i.when) ?? '?'}'),
    ],
  );
}

final Map<String, AgentRun> kAgentReads = {
  'find_students': findStudents,
  'get_student': getStudent,
  'get_student_reports': getStudentReports,
  'list_meetings': listMeetings,
  'list_interactions': listInteractions,
  'list_followups': listFollowups,
  'list_books': listBooks,
  'list_targets': listTargets,
  'list_competitions': listCompetitions,
  'list_trips': listTrips,
  'list_priority': listPriority,
  'list_doubts': listDoubts,
  'list_flagged': listFlagged,
  'list_calendar': listCalendar,
  'list_submissions': listSubmissions,
  'list_services': listServices,
  'list_music': listMusic,
  'list_admins': listAdmins,
  'list_boards': listBoards,
  'list_comments': listComments,
  'list_lit': listLit,
  'find_duplicates': findDuplicates,
};
