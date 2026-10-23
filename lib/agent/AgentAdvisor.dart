import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../actions/SubmissionActions.dart';
import 'AgentEnv.dart';
import 'AgentTypes.dart';

/// What a thoughtful colleague would say before you press Confirm — worked out on the phone, from
/// the guide's own data, and shown beside the card.
///
/// "He already has two meetings with you that week." "That date has already passed." "This will tell
/// about 40 students." Advice never replaces the confirmation and never blocks it: if working it out
/// fails, there is simply less advice.
///
/// The server adds its own notes (who is notified, what cannot be undone, a warning after student
/// text was read); these are the ones that need the guide's data.
Future<List<String>> adviseFor(AgentProposal proposal, AgentEnv env) async {
  final out = <String>[];
  for (final action in proposal.actions) {
    try {
      out.addAll(await _adviseAction(action, env));
    } catch (_) {/* advice is a courtesy */}
  }
  // the same sentence twice (two meetings, same week) is said once
  return out.toSet().toList();
}

final DateFormat _day = DateFormat('EEE d MMM');

DateTime? _dateArg(Map<String, dynamic> a, String key) {
  final v = a[key];
  if (v is! String) return null;
  try {
    return agentDay(v);
  } catch (_) {
    return null;
  }
}

bool _past(DateTime d, DateTime now) => d.isBefore(DateTime(now.year, now.month, now.day));

/// Monday to Sunday around [d].
(DateTime, DateTime) _weekOf(DateTime d) {
  final monday = DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  return (monday, monday.add(const Duration(days: 7)));
}

Future<List<String>> _adviseAction(AgentAction action, AgentEnv env) async {
  final a = action.args;
  final now = env.now;
  final out = <String>[];

  // --- dates that have already passed -------------------------------------------------
  for (final key in const ['date', 'startDate', 'endDate', 'commitmentDate', 'registrationDeadline']) {
    final d = _dateArg(a, key);
    if (d != null && _past(d, now) && const {
      'meeting_request', 'meeting_confirm', 'meeting_reschedule', 'trip_create', 'competition_create', 'book_assign', 'target_set_end_date', 'target_create',
    }.contains(action.tool)) {
      out.add('${action.title}: ${_day.format(d)} has already passed — check the date.');
      break;
    }
  }

  switch (action.tool) {
    case 'meeting_request':
    case 'meeting_confirm':
    case 'meeting_reschedule':
      final day = _dateArg(a, 'date');
      if (day == null) break;
      String? uid = a['studentUid'] as String?;
      if (uid == null && a['associationId'] is String) {
        final snap = await env.db.collection('associations').doc(a['associationId'] as String).get();
        uid = snap.data()?['studentUid']?.toString();
      }
      if (uid == null) break;
      final student = await env.student(uid);
      final week = _weekOf(day);
      final docs = (await env.scope.historyGet('associations', extraEquals: {'studentUid': uid})).docs;
      final inWeek = docs.where((d) {
        final m = d.data();
        final st = (m['status'] ?? '').toString();
        if (st == 'cancelled' || st == 'completed') return false;
        if (d.id == a['associationId']) return false;
        final when = (m['confirmedDate'] ?? m['preferredDate']);
        if (when is! Timestamp) return false;
        final w = when.toDate();
        return !w.isBefore(week.$1) && w.isBefore(week.$2);
      }).length;
      if (inWeek > 0) {
        out.add('${student['name']} already has $inWeek meeting${inWeek == 1 ? '' : 's'} with you that week.');
      }
      // a meeting in the evening hours the guide did not set is most often a slip of AM/PM
      final time = a['time'];
      if (time is String && RegExp(r'^0[0-4]:').hasMatch(time)) {
        out.add('${action.title}: $time is in the early hours — did you mean the evening?');
      }

    case 'book_assign':
      final uid = a['studentUid'] as String;
      final student = await env.student(uid);
      final reading = (await env.scope.historyGet('booksRead', extraEquals: {'uid': uid})).docs.where((d) {
        final m = d.data();
        return m['isCurrentBook'] == true && (m['endDate'] == null || '${m['endDate']}'.trim().isEmpty);
      }).map((d) => (d.data()['bookTitle'] ?? '').toString()).where((t) => t.isNotEmpty).toList();
      if (reading.isNotEmpty) {
        out.add('${student['name']} is already reading ${reading.join(', ')} — assigning another sets it as the current book.');
      }

    case 'competition_create':
      final everyone = await env.students();
      final guides = (a['guideIds'] as List?)?.cast<String>() ?? const [];
      final n = env.me.isHod && guides.isNotEmpty
          ? everyone.values.where((s) => guides.contains((s['guideId'] ?? '').toString()) || guides.contains((s['teamGuide'] ?? '').toString())).length
          : everyone.length;
      out.add('About $n student${n == 1 ? '' : 's'} will be told about this competition (those who have not muted competitions).');
      final start = _dateArg(a, 'startDate');
      final end = _dateArg(a, 'endDate');
      if (start != null && end != null) {
        final snap = await env.db.collection('chantingChallenges').where('status', isEqualTo: 'active').get();
        final overlaps = snap.docs.where((d) {
          final s = d.data()['startDate'];
          final e = d.data()['endDate'] ?? d.data()['targetDate'];
          if (s is! Timestamp || e is! Timestamp) return false;
          return !s.toDate().isAfter(end) && !e.toDate().isBefore(start);
        }).map((d) => (d.data()['name'] ?? '').toString()).toList();
        if (overlaps.isNotEmpty) out.add('It overlaps ${overlaps.join(', ')}; students would be chanting for both.');
      }

    case 'submission_remind':
      final uids = (a['studentUids'] as List).cast<String>();
      final status = await loadSubmissionStatus();
      final already = status.submitted.where((s) => uids.contains(s.uid)).map((s) => s.name).toList();
      if (already.isNotEmpty) {
        out.add('${already.take(3).join(', ')}${already.length > 3 ? ' and ${already.length - 3} more' : ''} ${already.length == 1 ? 'has' : 'have'} already submitted today — a reminder would be unnecessary.');
      }

    case 'student_delete':
      final uid = a['studentUid'] as String;
      final s = await env.student(uid);
      final meetings = (await env.scope.historyGet('associations', extraEquals: {'studentUid': uid})).docs.length;
      final logs = (await env.scope.historyGet('interactionLogs', extraEquals: {'studentUid': uid})).docs.length;
      out.add('This removes ${s['name']}\'s account, reports, chats, $meetings meeting${meetings == 1 ? '' : 's'} and $logs interaction${logs == 1 ? '' : 's'} for good. '
          'If you only want them off your lists, removing them from your priority list does not delete anything.');

    case 'priority_remove':
      out.add('They come back to your list on their own if a new kind of concern appears.');

    case 'trip_create':
      final start = _dateArg(a, 'startDate');
      final end = _dateArg(a, 'endDate') ?? start;
      if (start != null && end != null) {
        final mine = (await env.db.collection('expeditions').where('createdBy', isEqualTo: env.me.id).get()).docs.where((d) {
          if (d.data()['archived'] == true) return false;
          final s = d.data()['tripDate'];
          final e = d.data()['endDate'] ?? s;
          if (s is! Timestamp || e is! Timestamp) return false;
          return !s.toDate().isAfter(end) && !e.toDate().isBefore(start);
        }).map((d) => (d.data()['title'] ?? '').toString()).toList();
        if (mine.isNotEmpty) out.add('You already have ${mine.join(', ')} on those dates.');
      }

    case 'interaction_add':
      final d = _dateArg(a, 'date');
      if (d != null && d.isAfter(DateTime(now.year, now.month, now.day, 23, 59))) {
        out.add('That interaction is dated in the future — did you mean today?');
      }

    case 'meeting_cancel':
    case 'meeting_delete':
      out.add(action.tool == 'meeting_delete' ? 'Deleting a meeting removes it from history too; cancelling keeps the record.' : 'The student will be told it was cancelled.');

    default:
  }
  return out;
}
