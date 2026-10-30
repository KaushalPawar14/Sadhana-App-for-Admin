import '../utils/Pronouns.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:intl/intl.dart';

import '../Services/HierarchyApi.dart';
import '../actions/AssociationActions.dart';
import '../actions/BookActions.dart';
import '../actions/BookLinkActions.dart';
import '../actions/CommentActions.dart';
import '../actions/CompetitionActions.dart';
import '../actions/DeleteActions.dart';
import '../actions/FlaggedActions.dart';
import '../actions/InteractionActions.dart';
import '../actions/LitActions.dart';
import '../actions/PriorityActions.dart';
import '../actions/StudentActions.dart';
import '../actions/SubmissionActions.dart';
import '../actions/TripActions.dart';
import '../utils/BookProgressData.dart';
import '../utils/StudentDeletion.dart';
import '../utils/StudentDoubts.dart';
import '../utils/StudentScope.dart';
import 'AgentEnv.dart';
import 'AgentReads.dart' show AgentRun;
import 'AgentTypes.dart';

/// The agent's changes — each one runs the SAME shared function the screen runs.
///
/// Nothing here writes to Firestore itself. Every executor checks, first, that the thing it was
/// asked to change is in THIS guide's scope (a student through [AgentEnv.student]; a meeting, an
/// interaction or a message through the student it is about), then calls the shared function the
/// matching screen calls — which is where the app's own validation, notifications and rules apply.
/// So the agent can do exactly what the guide could do by hand: no more, and no other way.
///
/// What an executor returns is a sentence saying what was done, in the app's words; the server
/// passes it to the model, which tells the guide.

AgentResult _done(String message, {List<AgentEntity> entities = const [], Future<void> Function()? undo}) =>
    AgentResult.ok({'done': message}, entities: entities, undo: undo);

final DateFormat _when = DateFormat('EEE d MMM yyyy, h:mm a');
final DateFormat _day = DateFormat('EEE d MMM yyyy');

String _s(Object? v) => (v ?? '').toString();

/// A document that must exist, and the student it is about, who must be in scope.
Future<({DocumentSnapshot<Map<String, dynamic>> snap, Map<String, dynamic> data, String studentUid, Map<String, dynamic> student})>
    _aboutStudent(AgentEnv env, String collection, String id, {String uidField = 'studentUid', String what = 'record'}) async {
  final snap = await env.db.collection(collection).doc(id).get();
  final data = snap.data();
  if (!snap.exists || data == null) throw AgentFailure('That $what no longer exists.');
  final uid = _s(data[uidField]);
  final student = await env.student(uid); // not in scope → "I can't find that student among your students."
  return (snap: snap, data: data, studentUid: uid, student: student);
}

// ---------------------------------------------------------------------------
// Meetings
// ---------------------------------------------------------------------------
Future<AgentResult> meetingRequest(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final when = agentWhen(a['date'], a['time']);
  await requestMeeting(
    guideId: env.me.id,
    studentUid: uid,
    studentName: _s(s['name']),
    preferred: when,
    message: _s(a['message']),
  );
  return _done('Meeting requested with ${_s(s['name'])} for ${_when.format(when)}; they have been told.');
}

Future<AgentResult> meetingConfirm(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'associations', _s(a['associationId']), what: 'meeting');
  final when = agentWhen(a['date'], a['time']);
  await confirmMeeting(m.snap.id, studentUid: m.studentUid, when: when);
  return _done('Meeting with ${_s(m.student['name'])} confirmed for ${_when.format(when)}; they have been told.');
}

Future<AgentResult> meetingAcceptStudentDate(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'associations', _s(a['associationId']), what: 'meeting');
  final proposed = m.data['counterProposalDate'];
  if (proposed is! Timestamp) throw AgentFailure('This student has not proposed another date.');
  await acceptStudentProposal(m.snap.id, studentUid: m.studentUid, proposed: proposed);
  return _done("Accepted ${_s(m.student['name'])}'s proposed date, ${_when.format(proposed.toDate())}; they have been told.");
}

Future<AgentResult> meetingComplete(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'associations', _s(a['associationId']), what: 'meeting');
  await completeMeeting(m.snap.id, notes: _s(a['notes']));
  return _done('Meeting with ${_s(m.student['name'])} marked complete, with your notes.');
}

Future<AgentResult> meetingCancel(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'associations', _s(a['associationId']), what: 'meeting');
  await cancelMeeting(m.snap.id, studentUid: m.studentUid);
  return _done('Meeting with ${_s(m.student['name'])} cancelled; they have been told.');
}

Future<AgentResult> meetingReschedule(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'associations', _s(a['associationId']), what: 'meeting');
  final when = agentWhen(a['date'], a['time']);
  await rescheduleMeeting(m.snap.id, studentUid: m.studentUid, when: when);
  return _done('Meeting with ${_s(m.student['name'])} moved to ${_when.format(when)}; they have been told.');
}

Future<AgentResult> meetingDelete(Map<String, dynamic> a, AgentEnv env) async {
  final ids = [for (final x in (a['associationIds'] as List)) _s(x)];
  for (final id in ids) {
    await _aboutStudent(env, 'associations', id, what: 'meeting');
  }
  final out = await deleteRecords(
    collection: 'associations',
    ids: ids.toSet(),
    canDelete: (data) async => canDeleteStamped(data, env.me),
  );
  return _deleteResult(out, 'meeting');
}

AgentResult _deleteResult(DeleteOutcome out, String noun) {
  if (out.clean) return _done('Deleted ${out.deleted.length} $noun${out.deleted.length == 1 ? '' : 's'}.');
  final parts = [
    if (out.deleted.isNotEmpty) '${out.deleted.length} deleted',
    if (out.denied > 0) "${out.denied} not permitted — they aren't yours to delete",
    if (out.failed > 0) '${out.failed} failed',
  ];
  return AgentResult.failed(parts.join(', '));
}

// ---------------------------------------------------------------------------
// Interactions, LIT, comments
// ---------------------------------------------------------------------------
/// What the assistant understood from the report, in the keys the server's interaction record uses (only what it filled in).
Map<String, dynamic>? _analysisOf(Object? raw) {
  if (raw is! Map) return null;
  const text = ['studentConcerns', 'personalRevelation', 'commitmentsMade', 'abcdeEvidence', 'possibleLitEvidence', 'temporaryCircumstances', 'recommendedNextAction', 'recommendedReasoning'];
  final out = <String, dynamic>{
    for (final k in text)
      if (_s(raw[k]).trim().isNotEmpty) k: _s(raw[k]).trim(),
    if (raw['themes'] is List) 'themes': [for (final t in raw['themes'] as List) if (_s(t).trim().isNotEmpty) _s(t).trim()],
    if (raw['durationMinutes'] is num) 'durationMinutes': (raw['durationMinutes'] as num).toInt(),
  };
  return out.isEmpty ? null : out;
}

Future<AgentResult> interactionAdd(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final when = agentWhen(a['date'], a['time'], fallback: const TimeOfDay(hour: 12, minute: 0));
  final saved = await saveInteraction(
    guideId: env.me.id,
    studentUid: uid,
    studentName: _s(s['name']),
    raw: _s(a['notes']),
    interactionType: _s(a['interactionType']),
    interactionDate: when,
    followUpDate: a['followUpDate'] == null ? null : agentDay(a['followUpDate']),
    topicAnswers: [
      for (final t in (a['topicAnswers'] as List? ?? const []))
        if (t is Map && _s(t['topic']).isNotEmpty && (_s(t['answer']).isNotEmpty || _s(t['conclusion']).isNotEmpty))
          {
            'topic': _s(t['topic']),
            if (_s(t['questionsAsked']).isNotEmpty) 'questionsAsked': _s(t['questionsAsked']),
            'answer': _s(t['answer']),
            if (_s(t['conclusion']).isNotEmpty) 'conclusion': _s(t['conclusion']),
          },
    ],
    willingness: a['willingness'] == null ? null : _s(a['willingness']),
    addressed: a['addressed'] == null ? true : a['addressed'] == true,
    analysis: _analysisOf(a['analysis']),
  );
  return _done('Interaction with ${_s(s['name'])} recorded for ${_when.format(when)}. ${pronouned('It is saved in his history, the plan item is ticked and his reasons are cleared from Interactions needed.', _s(s['gender']), name: _s(s['name']))}',
      entities: [AgentEntity('interaction', saved.id, 'Interaction with ${_s(s['name'])} on ${_day.format(when)}')]);
}

Future<AgentResult> interactionEdit(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'interactionLogs', _s(a['interactionId']), what: 'interaction');
  final changes = <String, dynamic>{
    if (a['concerns'] != null) 'studentConcerns': _s(a['concerns']),
    if (a['litEvidence'] != null) 'possibleLitEvidence': _s(a['litEvidence']),
    if (a['nextAction'] != null) 'recommendedNextAction': _s(a['nextAction']),
    if (a['themes'] != null) 'themes': [for (final t in (a['themes'] as List)) _s(t)],
    if (a['followUpDate'] != null) 'followUpDate': agentDay(a['followUpDate']).toIso8601String(),
  };
  await editInteractionFields(
    m.snap.id,
    changes: changes,
    interactionDate: a['date'] == null ? null : agentDay(a['date']),
  );
  return _done('Interaction with ${_s(m.student['name'])} updated.');
}

Future<AgentResult> interactionReextract(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'interactionLogs', _s(a['interactionId']), what: 'interaction');
  final raw = _s(m.data['rawDictation']);
  if (raw.trim().isEmpty) throw AgentFailure('That interaction has no original notes to run the AI on again.');
  await reExtractInteraction(m.snap.id);
  return _done("The AI has read the interaction with ${_s(m.student['name'])} again and updated its details.");
}

Future<AgentResult> interactionDelete(Map<String, dynamic> a, AgentEnv env) async {
  final ids = [for (final x in (a['interactionIds'] as List)) _s(x)];
  final refs = <String, StudentRef>{};
  for (final id in ids) {
    final m = await _aboutStudent(env, 'interactionLogs', id, what: 'interaction');
    refs[m.studentUid] = StudentRef.fromUser(m.studentUid, m.student);
  }
  final out = await deleteRecords(
    collection: 'interactionLogs',
    ids: ids.toSet(),
    canDelete: (data) async => canDeleteForStudent(refs[_s(data['studentUid'])], env.me),
  );
  return _deleteResult(out, 'interaction log');
}

Future<AgentResult> litRecord(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  await saveLitAssessment(
    studentUid: uid,
    studentName: _s(s['name']),
    guideId: env.me.id,
    scores: {'L': a['L'] as int, 'I': a['I'] as int, 'T': a['T'] as int},
    evidence: _s(a['evidence']),
    confidence: _s(a['confidence']),
  );
  return _done('LIT assessment recorded for ${_s(s['name'])}: L ${a['L']}, I ${a['I']}, T ${a['T']}.');
}

Future<AgentResult> studentCommentAdd(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  await postStudentComment(
    studentUid: uid,
    text: _s(a['text']),
    authorId: env.me.id,
    authorName: env.me.displayName,
    authorIsHod: env.me.isHod,
  );
  return _done('Comment added for ${_s(s['name'])}.');
}

// ---------------------------------------------------------------------------
// Books
// ---------------------------------------------------------------------------
/// `level-1/book_3` → (level, key, title).
Future<({String level, String key, String title})> _book(Object? id) async {
  final parts = _s(id).split('/');
  if (parts.length != 2) throw AgentFailure("That isn't a book I looked up.");
  final config = await loadBooksConfig();
  final entry = (config.byLevel[parts[0]] ?? const []).where((b) => b.key == parts[1]).toList();
  if (entry.isEmpty) throw AgentFailure('That book is not in the app.');
  return (level: parts[0], key: parts[1], title: entry.first.title);
}

Future<AgentResult> bookAssign(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final b = await _book(a['bookId']);
  final by = agentDay(a['commitmentDate']);
  final assigned = await assignBook(
    guideId: env.me.id, studentUid: uid, level: b.level, bookKey: b.key, title: b.title, commitment: by,
  );
  if (!assigned) throw AgentFailure('${_s(s['name'])} has already finished "${b.title}", so it was not assigned again.');
  return _done('"${b.title}" assigned to ${_s(s['name'])} to finish by ${_day.format(by)}; they have been told.');
}

Future<AgentResult> bookFinish(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final b = await _book(a['bookId']);
  final doc = await env.db.collection('booksRead').doc(bookDocId(uid, b.level, b.key)).get();
  await markBookFinished(
    studentUid: uid, level: b.level, bookKey: b.key, title: b.title,
    hasStarted: _s(doc.data()?['startDate']).isNotEmpty,
  );
  return _done('"${b.title}" marked finished for ${_s(s['name'])}.');
}

Future<AgentResult> bookUnfinish(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final b = await _book(a['bookId']);
  await markBookNotFinished(studentUid: uid, level: b.level, bookKey: b.key, title: b.title);
  return _done('"${b.title}" is no longer marked finished for ${_s(s['name'])}.');
}

Future<AgentResult> bookLinkSet(Map<String, dynamic> a, AgentEnv env) async {
  final b = await _book(a['bookId']);
  final language = a['language'] == null ? 'en' : _s(a['language']);
  await setBookLink(level: b.level, bookKey: b.key, url: _s(a['url']), language: language);
  return _done('The ${kBookLinkLanguages[language]} link for "${b.title}" is set.');
}

// ---------------------------------------------------------------------------
// Student details
// ---------------------------------------------------------------------------
Future<AgentResult> studentCommitmentsSet(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  // the shared write sets both fields; an omitted one keeps what the student has now
  int? keep(String key) => s[key] is num ? (s[key] as num).toInt() : null;
  final rounds = a['rounds'] is int ? a['rounds'] as int : keep('commitmentRounds');
  final reading = a['readingMinutes'] is int ? a['readingMinutes'] as int : keep('readingCommitmentMinutes');
  final beforeRounds = keep('commitmentRounds');
  final beforeReading = keep('readingCommitmentMinutes');
  await setStudentCommitments(uid, rounds: rounds, readingMinutes: reading);
  env.invalidate();
  return _done(
    "${_s(s['name'])}'s commitments are now ${rounds ?? 'unset'} rounds and ${reading ?? 'unset'} minutes of reading a day.",
    undo: () => setStudentCommitments(uid, rounds: beforeRounds, readingMinutes: beforeReading),
  );
}

Future<AgentResult> studentNotificationSet(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  await setStudentNotificationPref(uid, _s(a['key']), a['value'] == true);
  return _done("${_s(a['key'])} notifications turned ${a['value'] == true ? 'on' : 'off'} for ${_s(s['name'])}.");
}

Future<AgentResult> studentResidenceSet(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  await setStudentResidence(uid, _s(a['residence']));
  env.invalidate();
  return _done('${_s(s['name'])} now stays: ${_s(a['residence'])}.');
}

Future<AgentResult> studentDobSet(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final d = agentDay(a['dob']);
  await setStudentDob(uid, d);
  return _done("${_s(s['name'])}'s date of birth set to ${_day.format(d)}.");
}

Future<AgentResult> studentAdd(Map<String, dynamic> a, AgentEnv env) async {
  final me = env.me;
  // a guide adding a student takes them on; a HOD's new student starts unassigned
  final id = await addManualStudent(
    name: _s(a['name']),
    mobile: _s(a['mobile']),
    residence: _s(a['residence']),
    gender: _s(a['gender']),
    addedBy: me.id,
    guideId: me.isHod ? null : me.id,
    rounds: a['rounds'] as int?,
  );
  env.invalidate();
  return _done('${_s(a['name'])} added${me.isHod ? '' : ' to your students'}.',
      entities: [AgentEntity('student', id, _s(a['name']))]);
}

Future<AgentResult> studentAssign(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final to = _s(a['toGuideId']);
  await HierarchyApi.instance.assignStudent(studentId: uid, toGuideId: to);
  env.invalidate();
  return _done('${_s(s['name'])} moved to ${env.adminName(to)}\'s team.');
}

/// Makes a student Unassigned: the same server call as dropping the card on the Unassigned column ('' = release). The server enforces who may release
/// whom (a guide his own and his team's, a HOD anyone's) and the gender rules, exactly as for the board.
Future<AgentResult> studentUnassign(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  await HierarchyApi.instance.assignStudent(studentId: uid, toGuideId: '');
  env.invalidate();
  return _done('${_s(s['name'])} is now unassigned.');
}

Future<AgentResult> studentDelete(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final r = await deleteStudentEverywhere(uid: uid, name: _s(s['name']));
  env.invalidate();
  if (r.refused) throw AgentFailure(r.refusalReason ?? 'The server refused to delete this student.');
  if (r.anyStepFailed) {
    final failed = [for (final st in r.steps) if (st.failed) '${st.label}: ${st.error}'];
    throw AgentFailure('Deleting ${_s(s['name'])} only partly worked. ${failed.join('; ')}');
  }
  return _done('${_s(s['name'])} and everything about them were deleted.${r.notFullyScrubbed.isEmpty ? '' : ' (Some references elsewhere may remain: ${r.notFullyScrubbed.length}.)'}');
}

// ---------------------------------------------------------------------------
// Priority, flagged, doubts, submissions, AI
// ---------------------------------------------------------------------------
Future<AgentResult> priorityRemove(Map<String, dynamic> a, AgentEnv env) async {
  final uids = [for (final x in (a['studentUids'] as List)) _s(x)];
  for (final u in uids) {
    await env.student(u);
  }
  final list = await env.priority();
  final on = {for (final s in list.students) s.uid: s};
  final missing = [for (final u in uids) if (!on.containsKey(u)) u];
  if (missing.isNotEmpty) {
    final all = await env.students();
    throw AgentFailure('${[for (final u in missing) _s(all[u]?['name'])].join(', ')} ${missing.length == 1 ? 'is' : 'are'} not on your priority list.');
  }
  await removeFromPriority([for (final u in uids) on[u]!]);
  env.invalidate();
  return _done('${uids.length} student${uids.length == 1 ? '' : 's'} taken off your priority list. They come back if a new kind of concern appears.');
}

Future<AgentResult> priorityRestore(Map<String, dynamic> a, AgentEnv env) async {
  final uids = [for (final x in (a['studentUids'] as List)) _s(x)];
  for (final u in uids) {
    await env.student(u);
  }
  await restoreToPriority(uids);
  env.invalidate();
  return _done('${uids.length} student${uids.length == 1 ? '' : 's'} put back on your priority list.');
}

Future<AgentResult> flaggedMarkReviewed(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'flaggedChatMessages', _s(a['messageId']), what: 'message');
  await markFlaggedReviewed(m.snap.id, a['reviewed'] == true);
  return _done('The message from ${_s(m.student['name'])} is marked ${a['reviewed'] == true ? 'reviewed' : 'not reviewed'}.');
}

Future<AgentResult> flaggedDelete(Map<String, dynamic> a, AgentEnv env) async {
  final ids = [for (final x in (a['messageIds'] as List)) _s(x)];
  for (final id in ids) {
    await _aboutStudent(env, 'flaggedChatMessages', id, what: 'message');
  }
  final out = await deleteRecords(
    collection: 'flaggedChatMessages', ids: ids.toSet(), canDelete: (data) async => canDeleteStamped(data, env.me));
  return _deleteResult(out, 'flagged message');
}

Future<AgentResult> doubtAnswer(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'bookDoubts', _s(a['doubtId']), uidField: 'uid', what: 'doubt');
  // sent as the GUIDE's answer; when the assistant prepared it from the teachings, the student is told so
  final byAi = a['byAi'] == true;
  final text = byAi ? '${_s(a['text'])}\n\n(Prepared with AI from Śrīla Prabhupāda\'s teachings, and sent by ${env.me.displayName}.)' : _s(a['text']);
  await StudentDoubts.answer(doubtId: m.snap.id, text: text, me: env.me);
  return _done("Answered ${_s(m.student['name'])}'s doubt${byAi ? ' (prepared with AI)' : ''}; they have been told.");
}

Future<AgentResult> submissionRemind(Map<String, dynamic> a, AgentEnv env) async {
  final uids = [for (final x in (a['studentUids'] as List)) _s(x)];
  final all = await env.students();
  for (final u in uids) {
    if (!all.containsKey(u)) throw AgentFailure("I can't find that student among your students.");
  }
  final sent = await sendSubmissionReminders(uids);
  return _done('Reminder sent to $sent of ${uids.length} student${uids.length == 1 ? '' : 's'}'
      '${sent < uids.length ? ' — the rest have no notification token or have muted reminders' : ''}.');
}

// ---------------------------------------------------------------------------
// Competitions and trips
// ---------------------------------------------------------------------------
Future<AgentResult> competitionCreate(Map<String, dynamic> a, AgentEnv env) async {
  final made = await createChantingChallenge(
    name: _s(a['name']),
    targetRounds: a['targetRounds'] as int,
    start: agentDay(a['startDate']),
    end: agentDay(a['endDate']),
    selectedGuideIds: {for (final g in (a['guideIds'] as List? ?? const [])) _s(g)},
  );
  final told = made.notifyFailed ? 'The competition is saved, but telling the students failed.' : 'Told ${made.sent} of ${made.total} students.';
  return _done('Competition "${_s(a['name'])}" started. $told',
      entities: [AgentEntity('challenge', made.id, _s(a['name']))]);
}

Future<AgentResult> competitionSetStatus(Map<String, dynamic> a, AgentEnv env) async {
  await setChallengeStatus(_s(a['challengeId']), _s(a['status']));
  return _done(a['status'] == 'missed' ? 'Competition closed.' : 'Competition reopened.');
}

Future<AgentResult> competitionDelete(Map<String, dynamic> a, AgentEnv env) async {
  await deleteChantingChallenge(_s(a['challengeId']));
  return _done('Competition and every contribution to it deleted.');
}

Future<AgentResult> tripCreate(Map<String, dynamic> a, AgentEnv env) async {
  final id = await createTrip(
    createdBy: env.me.id,
    title: _s(a['title']),
    start: agentDay(a['startDate']),
    end: agentDay(a['endDate']),
    targetGender: _s(a['targetGender']),
    description: _s(a['description']),
    location: _s(a['location']),
    registrationDeadline: a['registrationDeadline'] == null ? null : agentDay(a['registrationDeadline']),
    maxParticipants: a['maxParticipants'] as int?,
  );
  return _done('Trip "${_s(a['title'])}" created for ${a['targetGender'] == 'female' ? 'girls' : 'boys'}.',
      entities: [AgentEntity('trip', id, _s(a['title']))]);
}

Future<AgentResult> tripSetStatus(Map<String, dynamic> a, AgentEnv env) async {
  await setTripStatus(_s(a['tripId']), _s(a['status']));
  return _done('Trip moved to ${_s(a['status'])}.');
}

Future<AgentResult> tripAttendanceSet(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'expeditionRegistrations', _s(a['registrationId']), what: 'registration');
  await setTripAttendance(m.snap.id, _s(a['attendance']));
  return _done('${_s(m.student['name'])} marked ${_s(a['attendance']) == 'full' ? 'fully completed' : _s(a['attendance']) == 'partial' ? 'partially completed' : 'pending'}.');
}

Future<AgentResult> tripDelete(Map<String, dynamic> a, AgentEnv env) async {
  final r = await HierarchyApi.instance.deleteExpedition(_s(a['tripId']));
  return _done('Trip deleted, with ${r.registrationsDeleted} registration${r.registrationsDeleted == 1 ? '' : 's'}.');
}

// ---------------------------------------------------------------------------
// Correcting and removing what a guide manages (the same writes the screens make, or - where the app has no button - the
// same rules-checked write, always on a record of a student in THIS guide's scope)
// ---------------------------------------------------------------------------
Future<AgentResult> interactionFollowupRemove(Map<String, dynamic> a, AgentEnv env) async {
  final ids = [for (final x in (a['interactionIds'] as List)) _s(x)];
  var removed = 0;
  var without = 0;
  for (final id in ids) {
    final m = await _aboutStudent(env, 'interactionLogs', id, what: 'interaction');
    final summary = m.data['approvedSummary'];
    if (summary is! Map || summary['followUpDate'] == null) {
      without++;
      continue;
    }
    await removeInteractionFollowUp(id);
    removed++;
  }
  if (removed == 0) throw AgentFailure('None of those interactions has a follow-up to remove.');
  return _done('Follow-up removed from $removed interaction${removed == 1 ? '' : 's'}; the interaction${removed == 1 ? '' : 's'} stay.${without > 0 ? ' ($without had no follow-up.)' : ''}');
}

/// A comment id is `studentUid/messageId`, as the comment list hands it over.
Future<({String studentUid, String messageId, Map<String, dynamic> data, Map<String, dynamic> student})> _comment(AgentEnv env, Object? id) async {
  final parts = _s(id).split('/');
  if (parts.length != 2 || parts.any((p) => p.isEmpty)) throw AgentFailure("That isn't a comment I looked up.");
  final student = await env.student(parts[0]);
  final snap = await env.db.collection('studentComments').doc(parts[0]).collection('messages').doc(parts[1]).get();
  final data = snap.data();
  if (!snap.exists || data == null) throw AgentFailure('That comment no longer exists.');
  // a guide changes their own comments; a HOD any comment on a student they see
  if (!env.me.isHod && _s(data['authorId']) != env.me.id) throw AgentFailure('You can only change comments you wrote yourself.');
  return (studentUid: parts[0], messageId: parts[1], data: data, student: student);
}

Future<AgentResult> studentCommentEdit(Map<String, dynamic> a, AgentEnv env) async {
  final c = await _comment(env, a['commentId']);
  await editStudentComment(studentUid: c.studentUid, messageId: c.messageId, text: _s(a['text']));
  return _done('Your comment on ${_s(c.student['name'])} was changed.');
}

Future<AgentResult> studentCommentDelete(Map<String, dynamic> a, AgentEnv env) async {
  final ids = [for (final x in (a['commentIds'] as List)) _s(x)];
  final found = [for (final id in ids) await _comment(env, id)];
  for (final c in found) {
    await deleteStudentComment(studentUid: c.studentUid, messageId: c.messageId);
  }
  return _done('${found.length} comment${found.length == 1 ? '' : 's'} deleted.');
}

Future<AgentResult> litEdit(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'litAssessments', _s(a['assessmentId']), what: 'LIT assessment');
  await editLitAssessment(
    m.snap.id,
    scores: {
      if (a['L'] != null) 'L': a['L'] as int,
      if (a['I'] != null) 'I': a['I'] as int,
      if (a['T'] != null) 'T': a['T'] as int,
    },
    evidence: a['evidence'] == null ? null : _s(a['evidence']),
    confidence: a['confidence'] == null ? null : _s(a['confidence']),
  );
  return _done('The LIT assessment for ${_s(m.student['name'])} was corrected.');
}

Future<AgentResult> litDelete(Map<String, dynamic> a, AgentEnv env) async {
  final ids = [for (final x in (a['assessmentIds'] as List)) _s(x)];
  for (final id in ids) {
    await _aboutStudent(env, 'litAssessments', id, what: 'LIT assessment');
  }
  for (final id in ids) {
    await deleteLitAssessment(id);
  }
  return _done('${ids.length} LIT assessment${ids.length == 1 ? '' : 's'} deleted.');
}

Future<AgentResult> bookUnassignTool(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final b = await _book(a['bookId']);
  final ok = await unassignBook(studentUid: uid, level: b.level, bookKey: b.key);
  if (!ok) throw AgentFailure('"${b.title}" was not assigned to ${_s(s['name'])} by a guide, or is already finished, so there is nothing to take back.');
  return _done('"${b.title}" is no longer assigned to ${_s(s['name'])}.');
}

Future<AgentResult> competitionEdit(Map<String, dynamic> a, AgentEnv env) async {
  await editChantingChallenge(
    _s(a['challengeId']),
    name: a['name'] == null ? null : _s(a['name']),
    targetRounds: a['targetRounds'] as int?,
    end: a['endDate'] == null ? null : agentDay(a['endDate']),
  );
  return _done('Competition changed.');
}

Future<AgentResult> tripEdit(Map<String, dynamic> a, AgentEnv env) async {
  await editTrip(
    _s(a['tripId']),
    title: a['title'] == null ? null : _s(a['title']),
    description: a['description'] == null ? null : _s(a['description']),
    location: a['location'] == null ? null : _s(a['location']),
    start: a['startDate'] == null ? null : agentDay(a['startDate']),
    end: a['endDate'] == null ? null : agentDay(a['endDate']),
    registrationDeadline: a['registrationDeadline'] == null ? null : agentDay(a['registrationDeadline']),
    maxParticipants: a['maxParticipants'] as int?,
  );
  return _done('Trip changed.');
}

Future<AgentResult> meetingNotesEdit(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _aboutStudent(env, 'associations', _s(a['associationId']), what: 'meeting');
  if (_s(m.data['status']) != 'completed') throw AgentFailure('Only a completed meeting has notes to change.');
  await editMeetingNotes(m.snap.id, notes: _s(a['notes']));
  return _done('Your notes on the meeting with ${_s(m.student['name'])} were changed.');
}

/// The first half of the changes; targets, calendar, services, music, boards, admins and settings
/// are in AgentWrites2.dart.
final Map<String, AgentRun> kAgentWritesA = {
  'meeting_request': meetingRequest,
  'meeting_confirm': meetingConfirm,
  'meeting_accept_student_date': meetingAcceptStudentDate,
  'meeting_complete': meetingComplete,
  'meeting_cancel': meetingCancel,
  'meeting_reschedule': meetingReschedule,
  'meeting_delete': meetingDelete,
  'interaction_add': interactionAdd,
  'interaction_edit': interactionEdit,
  'interaction_reextract': interactionReextract,
  'interaction_delete': interactionDelete,
  'lit_record': litRecord,
  'student_comment_add': studentCommentAdd,
  'book_assign': bookAssign,
  'book_finish': bookFinish,
  'book_unfinish': bookUnfinish,
  'book_link_set': bookLinkSet,
  'student_commitments_set': studentCommitmentsSet,
  'student_notification_set': studentNotificationSet,
  'student_residence_set': studentResidenceSet,
  'student_dob_set': studentDobSet,
  'student_add': studentAdd,
  'student_assign': studentAssign,
  'student_unassign': studentUnassign,
  'student_delete': studentDelete,
  'priority_remove': priorityRemove,
  'priority_restore': priorityRestore,
  'flagged_mark_reviewed': flaggedMarkReviewed,
  'flagged_delete': flaggedDelete,
  'doubt_answer': doubtAnswer,
  'submission_remind': submissionRemind,
  'competition_create': competitionCreate,
  'competition_set_status': competitionSetStatus,
  'competition_delete': competitionDelete,
  'trip_create': tripCreate,
  'trip_set_status': tripSetStatus,
  'trip_attendance_set': tripAttendanceSet,
  'trip_delete': tripDelete,
  'interaction_followup_remove': interactionFollowupRemove,
  'student_comment_edit': studentCommentEdit,
  'student_comment_delete': studentCommentDelete,
  'lit_edit': litEdit,
  'lit_delete': litDelete,
  'book_unassign': bookUnassignTool,
  'competition_edit': competitionEdit,
  'trip_edit': tripEdit,
  'meeting_notes_edit': meetingNotesEdit,
};
