import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../Pages/NotificationSettings.dart' show groupSwitchesFor;
import '../Services/HierarchyApi.dart';
import '../theme/ThemeModeController.dart';
import '../actions/CommentActions.dart';
import '../utils/AdminProfile.dart';
import '../utils/BoardQueries.dart';
import '../utils/CalendarQueries.dart';
import '../utils/GoalCompoundQueries.dart';
import '../utils/MusicData.dart';
import '../utils/ServiceAssignments.dart';
import '../utils/ServiceBankContent.dart';
import 'AgentEnv.dart';
import 'AgentReads.dart' show AgentRun;
import 'AgentTypes.dart';

/// The second half of the agent's changes: targets, calendar, services, music, boards, admins and
/// the guide's own settings. Same rule as the first half (AgentWrites.dart): every executor calls the
/// shared function the matching screen calls, after checking the thing is in this guide's scope.

AgentResult _done(String message, {List<AgentEntity> entities = const []}) =>
    AgentResult.ok({'done': message}, entities: entities);

final DateFormat _day = DateFormat('EEE d MMM yyyy');

String _s(Object? v) => (v ?? '').toString();

Future<({String guide, String target})> _targetId(Object? id) async {
  final parts = _s(id).split('/');
  if (parts.length != 2 || parts.any((p) => p.isEmpty)) throw AgentFailure("That isn't a target I looked up.");
  return (guide: parts[0], target: parts[1]);
}

// ---------------------------------------------------------------------------
// Targets
// ---------------------------------------------------------------------------
Future<AgentResult> targetCreate(Map<String, dynamic> a, AgentEnv env) async {
  try {
    final targetId = await createCompoundTargetShell(
      guideId: env.me.id,
      metric: _s(a['metric']),
      studentCountGoal: a['studentCountGoal'] as int,
      perStudentValueGoal: a['perStudentValueGoal'] as int,
      endDate: agentDay(a['endDate']),
    );
    final phases = await callGenerateCompoundPlan(guideId: env.me.id, targetId: targetId);
    return _done('Target created and a plan of $phases phase${phases == 1 ? '' : 's'} generated.',
        entities: [AgentEntity('target', '${env.me.id}/$targetId', '${_s(a['metric'])} target')]);
  } on CompoundTargetLimitException catch (e) {
    throw AgentFailure(e.message);
  }
}

Future<AgentResult> targetRegeneratePlan(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  final phases = await callRegenerateCompoundPlan(guideId: t.guide, targetId: t.target, note: a['note'] == null ? null : _s(a['note']));
  return _done('The plan was regenerated: $phases phase${phases == 1 ? '' : 's'}.');
}

Future<AgentResult> targetAbandon(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  await abandonCompoundTarget(t.guide, t.target);
  return _done('Target given up (kept in history).');
}

Future<AgentResult> targetDelete(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  await callDeleteCompoundTarget(guideId: t.guide, targetId: t.target);
  return _done('Target and its phases deleted.');
}

Future<AgentResult> targetSetEndDate(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  final d = agentDay(a['endDate']);
  await updateTargetEndDate(guideId: t.guide, targetId: t.target, endDate: d);
  return _done('Target end date moved to ${_day.format(d)}.');
}

/// The agent's tasks as the app's own, after checking every student named is one this guide may see.
Future<List<CompoundTask>> _tasks(Object? raw, AgentEnv env) async {
  final all = await env.students();
  final out = <CompoundTask>[];
  for (final item in (raw as List)) {
    final t = CompoundTask.from(item);
    if (t == null) throw AgentFailure("A task wasn't in a form the app understands.");
    for (final u in t.studentUids) {
      if (!all.containsKey(u)) throw AgentFailure("I can't find that student among your students.");
    }
    out.add(t);
  }
  return out;
}

Future<AgentResult> targetEditPhaseTasks(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  await directlyEditPhaseTasks(
    guideId: t.guide, targetId: t.target, phaseNumber: a['phaseNumber'] as int, tasks: await _tasks(a['tasks'], env));
  return _done('Phase ${a['phaseNumber']} tasks updated.');
}

Future<AgentResult> targetProposePhaseEdit(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  final target = await compoundTargetStream(t.guide, t.target).first;
  if (target == null) throw AgentFailure('That target no longer exists.');
  await proposeManualPhaseEdit(
    guideId: t.guide, targetId: t.target, hodUid: env.me.id,
    currentPhaseNumber: target.currentPhase, totalPhases: target.totalPhases,
    editedTasks: await _tasks(a['tasks'], env), note: _s(a['note']),
  );
  return _done('Proposal sent to ${env.adminName(t.guide)}; they can approve or reject it.');
}

Future<AgentResult> targetProposalApprove(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  await approveProposal(guideId: t.guide, targetId: t.target);
  return _done('The plan edit was approved and applied.');
}

Future<AgentResult> targetProposalReject(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  await rejectProposal(guideId: t.guide, targetId: t.target);
  return _done('The plan edit was rejected.');
}

Future<AgentResult> targetSuggestPlan(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  await callSuggestCompoundPlan(guideId: t.guide, targetId: t.target, hodUid: env.me.id, note: a['note'] == null ? null : _s(a['note']));
  return _done('A suggested plan edit was prepared and sent to ${env.adminName(t.guide)}.');
}

Future<AgentResult> targetCheckAdvance(Map<String, dynamic> a, AgentEnv env) async {
  final t = await _targetId(a['targetId']);
  final advanced = await callCheckAndAdvanceIfAheadOfSchedule(guideId: t.guide, targetId: t.target);
  return _done(advanced ? 'The target was ahead of schedule and has moved to the next phase.' : 'The target is not ready to move on yet.');
}

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------
List<ParsedCalendarEvent> _events(Object? raw) => [
      for (final e in (raw as List))
        ParsedCalendarEvent(
          date: agentDay((e as Map)['date']),
          endDate: e['endDate'] == null ? null : agentDay(e['endDate']),
          type: _s(e['type']),
          title: _s(e['title']),
          note: _s(e['note']),
          notifyOffsets: e['notifyOffsets'] == null ? null : [for (final o in (e['notifyOffsets'] as List)) _s(o)],
        ),
    ];

// ---------------------------------------------------------------------------
// Plan (corrected in chat only: the plan pages are read-only)
// ---------------------------------------------------------------------------
/// The student a plan item belongs to: ids are `kind:studentUid:slot`.
String _planItemStudent(Object? itemId) {
  final parts = _s(itemId).split(':');
  return parts.length >= 2 && parts[1] != '-' ? parts[1] : '';
}

/// What the guide said, remembered as a visible note on the student's thread (the constraint itself is stored by the server).
Future<void> _planNote(AgentEnv env, String uid, String text) async {
  if (uid.isEmpty || text.trim().isEmpty) return;
  await postStudentComment(
    studentUid: uid,
    text: 'Plan note: ${text.trim()}',
    authorId: env.me.id,
    authorName: env.me.displayName,
    authorIsHod: env.me.isHod,
  );
}

Future<AgentResult> planItemSkip(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _planItemStudent(a['itemId']);
  if (uid.isNotEmpty) await env.student(uid); // in the guide's scope, or "I can't find that student"
  final message = await HierarchyApi.instance.planCorrection(
    itemId: _s(a['itemId']),
    mode: 'remove',
    reason: _s(a['reason']),
    constraint: a['constraint'] == null ? null : _s(a['constraint']),
    noteText: a['note'] == null ? null : _s(a['note']),
  );
  await _planNote(env, uid, _s(a['note']));
  return _done('$message It will not come back, and I will remember why.');
}

Future<AgentResult> planItemChange(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _planItemStudent(a['itemId']);
  if (uid.isNotEmpty) await env.student(uid);
  final mode = _s(a['mode']);
  if (mode == 'other_day' && a['newDate'] == null) throw AgentFailure('Which day should it move to?');
  final message = await HierarchyApi.instance.planCorrection(
    itemId: _s(a['itemId']),
    mode: mode,
    newDate: a['newDate'] == null ? null : _s(a['newDate']),
    reason: _s(a['reason']),
    constraint: a['constraint'] == null ? null : _s(a['constraint']),
    noteText: a['note'] == null ? null : _s(a['note']),
  );
  await _planNote(env, uid, _s(a['note']));
  return _done('$message Your plan is updated.');
}

Future<AgentResult> studentNoteAdd(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final message = await HierarchyApi.instance.studentGuideNote(studentUid: uid, kind: 'note', text: _s(a['text']));
  return _done('$message (${_s(s['name'])}: "${_s(a['text'])}")');
}

Future<AgentResult> studentFolkInterestSet(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final notInterested = _s(a['interest']) == 'not_interested';
  final message = await HierarchyApi.instance.studentGuideNote(
    studentUid: uid,
    kind: notInterested ? 'not_folk' : 'folk_open',
    text: a['reason'] == null ? null : _s(a['reason']),
  );
  return _done('$message (${_s(s['name'])})');
}

Future<AgentResult> calendarAddNotes(Map<String, dynamic> a, AgentEnv env) async {
  final mandatory = a['mandatory'] == true;
  await saveTextBlockWithEvents(
    rawText: _s(a['text']),
    submittedBy: env.me.id,
    submittedByIsHod: env.me.isHod,
    scope: mandatory ? kScopeMandatory : kScopePersonal,
    ownerGuideId: mandatory ? null : env.me.id,
    parsedEvents: _events(a['events']),
  );
  final n = (a['events'] as List).length;
  return _done('Calendar notes saved with $n event${n == 1 ? '' : 's'}${mandatory ? ', for everyone' : ''}.');
}

Future<AgentResult> calendarUpdateBlock(Map<String, dynamic> a, AgentEnv env) async {
  await updateTextBlockWithEvents(
    blockId: _s(a['blockId']), rawText: _s(a['text']), editedBy: env.me.id, actingIsHod: env.me.isHod, parsedEvents: _events(a['events']));
  return _done('The note block and its events were replaced.');
}

Future<AgentResult> calendarDeleteBlock(Map<String, dynamic> a, AgentEnv env) async {
  final n = await deleteTextBlockAndItsEvents(blockId: _s(a['blockId']), actingIsHod: env.me.isHod);
  return _done('The note block and its $n event${n == 1 ? '' : 's'} were deleted.');
}

Future<AgentResult> calendarEditEvent(Map<String, dynamic> a, AgentEnv env) async {
  final id = _s(a['eventId']);
  final snap = await env.db.collection('calendarEvents').doc(id).get();
  if (!snap.exists) throw AgentFailure('That event no longer exists.');
  final current = [for (final o in (snap.data()?['notifyOffsets'] as List? ?? const [])) _s(o)];
  try {
    await editEvent(
      eventId: id,
      eventDate: agentDay(a['date']),
      endDate: a['endDate'] == null ? null : agentDay(a['endDate']),
      type: _s(a['type']),
      title: _s(a['title']),
      note: _s(a['note']),
      editedBy: env.me.id,
      actingIsHod: env.me.isHod,
      notifyOffsets: a['notifyOffsets'] == null ? (current.isEmpty ? List<String>.from(kDefaultNotifyOffsets) : current) : [for (final o in (a['notifyOffsets'] as List)) _s(o)],
    );
  } on MandatoryEventPermissionError catch (e) {
    throw AgentFailure(e.toString());
  } on InvalidEventRangeError catch (e) {
    throw AgentFailure(e.toString());
  }
  return _done('Event "${_s(a['title'])}" updated.');
}

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------
Future<({DocumentSnapshot<Map<String, dynamic>> snap, Map<String, dynamic> student})> _assignment(AgentEnv env, Object? id) async {
  final snap = await env.db.collection('serviceAssignments').doc(_s(id)).get();
  final data = snap.data();
  if (!snap.exists || data == null) throw AgentFailure('That assignment no longer exists.');
  final student = await env.student(_s(data['studentUid']));
  return (snap: snap, student: student);
}

String _serviceTitle(int n) => kServiceBank.firstWhere((s) => s.number == n, orElse: () => kServiceBank.first).title;

Future<AgentResult> serviceAssign(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final n = int.tryParse(_s(a['serviceNumber']));
  if (n == null || !kServiceBank.any((x) => x.number == n)) throw AgentFailure("That isn't one of the services.");
  final id = await assignService(serviceNumber: n, studentUid: uid, assignedByGuideId: env.me.id);
  return _done('${_serviceTitle(n)} assigned to ${_s(s['name'])}.', entities: [AgentEntity('assignment', id, '${_serviceTitle(n)} — ${_s(s['name'])}')]);
}

Future<AgentResult> serviceSetStatus(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _assignment(env, a['assignmentId']);
  await updateAssignmentStatus(assignmentId: m.snap.id, newStatus: _s(a['status']), updatedBy: env.me.id);
  return _done("${_s(m.student['name'])}'s service marked ${_s(a['status']) == 'inProgress' ? 'in progress' : _s(a['status'])}.");
}

Future<AgentResult> serviceSetCompetence(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _assignment(env, a['assignmentId']);
  await setCompetence(assignmentId: m.snap.id, level: _s(a['level']), assessedByGuideId: env.me.id, note: a['note'] == null ? null : _s(a['note']));
  return _done('Recorded: ${_s(m.student['name'])} ${_s(a['level']) == 'yes' ? 'can do this service on their own' : 'cannot yet do this service on their own'}.');
}

Future<AgentResult> serviceWithdraw(Map<String, dynamic> a, AgentEnv env) async {
  final m = await _assignment(env, a['assignmentId']);
  await withdrawAssignment(assignmentId: m.snap.id, withdrawnBy: env.me.id);
  return _done("${_s(m.student['name'])}'s service assignment was withdrawn.");
}

// ---------------------------------------------------------------------------
// Music
// ---------------------------------------------------------------------------
Future<AgentResult> musicInstrumentAdd(Map<String, dynamic> a, AgentEnv env) async {
  final store = FirestoreMusicStore(env.db);
  final order = (await store.curriculum().first).length;
  final id = await store.addInstrument(name: _s(a['name']), link: _s(a['link']), order: order);
  return _done('Instrument "${_s(a['name'])}" added.', entities: [AgentEntity('instrument', id, _s(a['name']))]);
}

Future<AgentResult> musicInstrumentUpdate(Map<String, dynamic> a, AgentEnv env) async {
  await FirestoreMusicStore(env.db).updateInstrument(_s(a['instrumentId']), name: a['name'] == null ? null : _s(a['name']), link: a['link'] == null ? null : _s(a['link']));
  return _done('Instrument updated.');
}

Future<AgentResult> musicInstrumentDelete(Map<String, dynamic> a, AgentEnv env) async {
  await FirestoreMusicStore(env.db).deleteInstrument(_s(a['instrumentId']));
  return _done('Instrument deleted.');
}

Future<AgentResult> musicInstrumentReorder(Map<String, dynamic> a, AgentEnv env) async {
  await FirestoreMusicStore(env.db).reorderInstruments([for (final i in (a['instrumentIds'] as List)) _s(i)]);
  return _done('Instruments reordered.');
}

Future<AgentResult> musicCheckpointsEdit(Map<String, dynamic> a, AgentEnv env) async {
  final action = _s(a['action']);
  final cp = _s(a['checkpointId']);
  final title = _s(a['title']);
  await FirestoreMusicStore(env.db).editCheckpoints(_s(a['instrumentId']), (current) {
    switch (action) {
      case 'add':
        return [...current, MusicCheckpoint(id: newMusicId('cp'), title: title)];
      case 'rename':
        return [for (final c in current) c.id == cp ? c.copyWith(title: title) : c];
      default:
        return [for (final c in current) if (c.id != cp) c];
    }
  });
  return _done(action == 'add' ? 'Checkpoint "$title" added.' : action == 'rename' ? 'Checkpoint renamed to "$title".' : 'Checkpoint removed.');
}

Future<AgentResult> musicTickSet(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  await FirestoreMusicStore(env.db).setTick(uid, _s(a['checkpointId']), a['ticked'] == true, by: env.me.id, byName: env.me.displayName);
  return _done('Checkpoint ${a['ticked'] == true ? 'ticked' : 'unticked'} for ${_s(s['name'])}.');
}

// ---------------------------------------------------------------------------
// Boards (custom boards)
// ---------------------------------------------------------------------------
Future<BoardDoc> _board(AgentEnv env, Object? id) async {
  final snap = await env.db.collection(kBoardsCollection).doc(_s(id)).get();
  final data = snap.data();
  if (!snap.exists || data == null) throw AgentFailure('That board no longer exists.');
  return BoardDoc.from(snap.id, data);
}

Future<BoardDoc> _customBoard(AgentEnv env, Object? id) async {
  final b = await _board(env, id);
  if (b.kind != kBoardKindCustom) throw AgentFailure("The Guide Assignment board is managed automatically — I can only change your own boards.");
  return b;
}

Future<AgentResult> boardCreate(Map<String, dynamic> a, AgentEnv env) async {
  final id = await createBoard(
    kind: kBoardKindCustom, ownerGuideId: env.me.id, title: _s(a['title']), createdBy: env.me.id,
    seedColumnTitles: [for (final c in (a['columns'] as List)) _s(c)], withUnsorted: false,
  );
  return _done('Board "${_s(a['title'])}" created with ${(a['columns'] as List).length} column${(a['columns'] as List).length == 1 ? '' : 's'}.',
      entities: [AgentEntity('board', id, _s(a['title']))]);
}

Future<AgentResult> boardRename(Map<String, dynamic> a, AgentEnv env) async {
  final b = await _customBoard(env, a['boardId']);
  await renameBoard(b.id, _s(a['title']));
  return _done('Board renamed to "${_s(a['title'])}".');
}

Future<AgentResult> boardShare(Map<String, dynamic> a, AgentEnv env) async {
  final b = await _customBoard(env, a['boardId']);
  await setBoardSharedWith(boardId: b.id, sharedWith: [for (final x in (a['sharedWith'] as List)) _s(x)]);
  final n = (a['sharedWith'] as List).length;
  return _done(n == 0 ? 'Board "${b.title}" is no longer shared.' : 'Board "${b.title}" shared with $n admin${n == 1 ? '' : 's'}.');
}

Future<AgentResult> boardDelete(Map<String, dynamic> a, AgentEnv env) async {
  final b = await _customBoard(env, a['boardId']);
  await deleteBoard(b.id);
  return _done('Board "${b.title}" deleted.');
}

Future<AgentResult> boardColumnAdd(Map<String, dynamic> a, AgentEnv env) async {
  final b = await _customBoard(env, a['boardId']);
  final order = (await columnsStream(b.id).first).length;
  await addColumn(boardId: b.id, title: _s(a['title']), order: order);
  return _done('Column "${_s(a['title'])}" added to "${b.title}".');
}

Future<AgentResult> boardColumnRename(Map<String, dynamic> a, AgentEnv env) async {
  final b = await _customBoard(env, a['boardId']);
  await renameColumn(b.id, _s(a['columnId']), _s(a['title']));
  return _done('Column renamed to "${_s(a['title'])}".');
}

Future<AgentResult> boardColumnRecolour(Map<String, dynamic> a, AgentEnv env) async {
  final b = await _customBoard(env, a['boardId']);
  final i = a['color'] as int;
  await recolourColumn(b.id, _s(a['columnId']), kColumnPalette[i % kColumnPalette.length]);
  return _done('Column recoloured.');
}

Future<AgentResult> boardColumnReorder(Map<String, dynamic> a, AgentEnv env) async {
  final b = await _customBoard(env, a['boardId']);
  final current = await columnsStream(b.id).first;
  final ids = [for (final i in (a['columnIds'] as List)) _s(i)];
  if (ids.length != current.length || ids.toSet().length != ids.length || !current.every((c) => ids.contains(c.id))) {
    throw AgentFailure('Give every column of the board exactly once, in the order you want.');
  }
  final byId = {for (final c in current) c.id: c};
  await reorderColumns(boardId: b.id, inNewOrder: [for (final i in ids) byId[i]!]);
  return _done('Columns of "${b.title}" reordered.');
}

Future<AgentResult> boardColumnDelete(Map<String, dynamic> a, AgentEnv env) async {
  final b = await _customBoard(env, a['boardId']);
  await deleteColumnDeletingPlacements(boardId: b.id, columnId: _s(a['columnId']));
  return _done('Column deleted; its cards came off the board (the students themselves are untouched).');
}

Future<AgentResult> boardCardMove(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final b = await _customBoard(env, a['boardId']);
  final column = _s(a['columnId']);
  final inColumn = (await placementsStream(b.id).first).docs.where((d) => _s(d.data()['columnId']) == column).length;
  await movePlacement(boardId: b.id, studentUid: uid, columnId: column, order: inColumn, movedBy: env.me.id);
  return _done("${_s(s['name'])}'s card moved on \"${b.title}\".");
}

Future<AgentResult> boardCardRemove(Map<String, dynamic> a, AgentEnv env) async {
  final uid = _s(a['studentUid']);
  final s = await env.student(uid);
  final b = await _customBoard(env, a['boardId']);
  await removePlacement(b.id, uid);
  return _done("${_s(s['name'])} taken off \"${b.title}\" (the student is not changed).");
}

// ---------------------------------------------------------------------------
// Admins
// ---------------------------------------------------------------------------
/// The board's side of an admin change, in words, so the assistant can say whether the FOLK Boys board followed:
/// "Their column on the FOLK Boys board was created." Empty when the server did not say.
String boardColumnSentence(String? effect, {String who = 'Their', int cardsMoved = 0}) {
  switch (effect) {
    case 'created':
      return ' $who column on the FOLK Boys board was created.';
    case 'updated':
      return ' $who column on the FOLK Boys board was updated.';
    case 'removed':
      return ' $who column on the FOLK Boys board was removed${cardsMoved > 0 ? ' ($cardsMoved card${cardsMoved == 1 ? '' : 's'} moved to Unassigned)' : ''}.';
    case 'unchanged':
      return ' The FOLK Boys board needed no change.';
    case 'no-board':
      return ' The FOLK Boys board has not been opened yet; the column appears when it is.';
    case 'failed':
      return " The FOLK Boys board column could not be updated just now; it will be corrected automatically, and opening the board repairs it.";
    default:
      return '';
  }
}

Future<AgentResult> adminAdd(Map<String, dynamic> a, AgentEnv env) async {
  final added = await HierarchyApi.instance.addAdmin(
    name: _s(a['name']),
    email: _s(a['email']),
    role: AdminRoleX.fromWire(_s(a['role'])),
    displayName: a['displayName'] == null ? null : _s(a['displayName']),
    teamGuide: a['teamGuide'] == null ? null : _s(a['teamGuide']),
  );
  return _done('${added.displayName} added as ${added.role.label}.${boardColumnSentence(added.boardColumn)}', entities: [AgentEntity('admin', added.id, added.displayName, {'role': added.role.wire})]);
}

Future<AgentResult> adminUpdate(Map<String, dynamic> a, AgentEnv env) async {
  final u = await HierarchyApi.instance.updateAdmin(
    id: _s(a['adminId']),
    email: a['email'] == null ? null : _s(a['email']),
    displayName: a['displayName'] == null ? null : _s(a['displayName']),
    role: a['role'] == null ? null : AdminRoleX.fromWire(_s(a['role'])),
    teamGuide: a['teamGuide'] == null ? null : _s(a['teamGuide']),
  );
  return _done('${u.displayName} updated.${boardColumnSentence(u.boardColumn)}');
}

Future<AgentResult> adminRemove(Map<String, dynamic> a, AgentEnv env) async {
  final id = _s(a['adminId']);
  final name = env.adminName(id);
  final r = await HierarchyApi.instance.removeAdmin(id);
  return _done('$name removed. ${r.studentCount} student${r.studentCount == 1 ? ' was' : 's were'} moved to unassigned first.${boardColumnSentence(r.boardColumn, cardsMoved: r.cardsMoved)}');
}

Future<AgentResult> adminSetTeamGuide(Map<String, dynamic> a, AgentEnv env) async {
  await HierarchyApi.instance.setTeamGuide(_s(a['adminId']), _s(a['teamGuide']));
  return _done('${env.adminName(_s(a['adminId']))} is now on ${env.adminName(_s(a['teamGuide']))}\'s team.');
}

// ---------------------------------------------------------------------------
// The guide's own settings
// ---------------------------------------------------------------------------
Future<AgentResult> myNotificationsSet(Map<String, dynamic> a, AgentEnv env) async {
  final me = env.me;
  final groups = {for (final g in groupSwitchesFor(me)) g.key: me.groupOn(g.key)};
  final types = {for (final t in me.notificationTypes) t.key: me.typeOn(t.key)};
  for (final g in (a['groups'] as List)) {
    final key = _s((g as Map)['key']);
    if (!groups.containsKey(key)) throw AgentFailure('"$key" is not a group of students you can switch.');
    groups[key] = g['on'] == true;
  }
  for (final t in (a['types'] as List)) {
    final key = _s((t as Map)['key']);
    if (!types.containsKey(key)) throw AgentFailure('"$key" is not a kind of alert you can switch.');
    types[key] = t['on'] == true;
  }
  await HierarchyApi.instance.saveNotificationPrefs(groups: groups, types: types);
  AdminProfileProvider.instance.applyPrefs(groups: groups, types: types);
  return _done('Your alert settings were saved.');
}

Future<AgentResult> appearanceSet(Map<String, dynamic> a, AgentEnv env) async {
  final themes = env.themes;
  if (themes == null) throw AgentFailure("I can't change this phone's appearance from here.");
  final mode = switch (_s(a['mode'])) {
    'dark' => GuideThemeMode.dark,
    'light' => GuideThemeMode.light,
    _ => GuideThemeMode.auto,
  };
  await themes.setMode(mode);
  return _done('Appearance set to ${_s(a['mode'])}. This changes only this phone.');
}

Future<AgentResult> signOutTool(Map<String, dynamic> a, AgentEnv env) async {
  final out = env.signOut;
  if (out == null) throw AgentFailure("I can't sign you out from here.");
  await out();
  return _done('Signed out of this phone.');
}

final Map<String, AgentRun> kAgentWritesB = {
  'target_create': targetCreate,
  'target_regenerate_plan': targetRegeneratePlan,
  'target_abandon': targetAbandon,
  'target_delete': targetDelete,
  'target_set_end_date': targetSetEndDate,
  'target_edit_phase_tasks': targetEditPhaseTasks,
  'target_propose_phase_edit': targetProposePhaseEdit,
  'target_proposal_approve': targetProposalApprove,
  'target_proposal_reject': targetProposalReject,
  'target_suggest_plan': targetSuggestPlan,
  'target_check_advance': targetCheckAdvance,
  'student_note_add': studentNoteAdd,
  'student_folk_interest_set': studentFolkInterestSet,
  'plan_item_skip': planItemSkip,
  'plan_item_change': planItemChange,
  'calendar_add_notes': calendarAddNotes,
  'calendar_update_block': calendarUpdateBlock,
  'calendar_delete_block': calendarDeleteBlock,
  'calendar_edit_event': calendarEditEvent,
  'service_assign': serviceAssign,
  'service_set_status': serviceSetStatus,
  'service_set_competence': serviceSetCompetence,
  'service_withdraw': serviceWithdraw,
  'music_instrument_add': musicInstrumentAdd,
  'music_instrument_update': musicInstrumentUpdate,
  'music_instrument_delete': musicInstrumentDelete,
  'music_instrument_reorder': musicInstrumentReorder,
  'music_checkpoints_edit': musicCheckpointsEdit,
  'music_tick_set': musicTickSet,
  'board_create': boardCreate,
  'board_rename': boardRename,
  'board_share': boardShare,
  'board_delete': boardDelete,
  'board_column_add': boardColumnAdd,
  'board_column_rename': boardColumnRename,
  'board_column_recolour': boardColumnRecolour,
  'board_column_reorder': boardColumnReorder,
  'board_column_delete': boardColumnDelete,
  'board_card_move': boardCardMove,
  'board_card_remove': boardCardRemove,
  'admin_add': adminAdd,
  'admin_update': adminUpdate,
  'admin_remove': adminRemove,
  'admin_set_team_guide': adminSetTeamGuide,
  'my_notifications_set': myNotificationsSet,
  'appearance_set': appearanceSet,
  'sign_out': signOutTool,
};
