import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../Services/HierarchyApi.dart';
import '../utils/VoiceNote.dart' show voiceReason;
import 'AgentAdvisor.dart';
import 'AgentEnv.dart';
import 'AgentReads.dart';
import 'TaskProgress.dart';
import 'AgentTypes.dart';
import 'AgentWrites.dart';
import 'AgentWrites2.dart';

/// What the guide reads when something goes wrong in the agent: what happened, in words, with the
/// real reason — never a bare "failed" and never a stack trace.
String agentFailureMessage(Object error) {
  if (error is AgentFailure) return error.message;
  if (error is HierarchyException) {
    switch (error.code) {
      case 'failed-precondition':
      case 'resource-exhausted':
        return error.message; // the server's own sentence already carries the reason
      case 'unauthenticated':
      case 'permission-denied':
        return 'Your sign-in has lapsed, or this was not allowed. (${voiceReason(error)})';
      case 'not-found':
        return "The assistant isn't on the server yet. Please tell whoever looks after the app. (${voiceReason(error)})";
      case 'unavailable':
      case 'deadline-exceeded':
        return "Couldn't reach the assistant just now. Check your connection and try again. (${voiceReason(error)})";
      default:
        return "The assistant had a problem. Try again. (${voiceReason(error)})";
    }
  }
  if (error is FirebaseException) {
    final reason = '${error.code}${(error.message ?? '').isEmpty ? '' : ': ${error.message}'}';
    return error.code == 'permission-denied'
        ? "The app's rules did not allow that for you, so nothing was changed. ($reason)"
        : "That didn't go through. ($reason)";
  }
  if (error is FirebaseFunctionsException) {
    return "The server said no. (${error.code}${(error.message ?? '').isEmpty ? '' : ': ${error.message}'})";
  }
  if (error is ArgumentError) return error.message?.toString() ?? error.toString();
  final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return "That didn't work. (${text.length > 200 ? '${text.substring(0, 200)}…' : text})";
}

/// One line of the conversation as the page shows it.
sealed class ChatEntry {}

class UserEntry extends ChatEntry {
  UserEntry(this.text);
  final String text;
}

class AssistantEntry extends ChatEntry {
  AssistantEntry(this.text, [this.links = const []]);
  final String text;
  final List<AgentLink> links;
}

class ErrorEntry extends ChatEntry {
  ErrorEntry(this.text);
  final String text;
}

/// A task's progress card: its percentage, driven by the real steps the task goes through (see [TaskProgress]). It is made when the
/// guide asks for something and follows that request all the way - through a confirmation, the saving and the result. It lives
/// on the phone only; a saved chat does not carry it.
class ProgressEntry extends ChatEntry {
  ProgressEntry(this.request);

  /// What the guide asked, shortened for the card.
  final String request;
  final TaskProgress progress = TaskProgress();

  /// Words for the waiting step when it is not a confirmation ("Waiting for your answer"), and for the end when it is not "Done".
  String? waitingText;
  String? doneText;
}

/// [expired]: shown in an old chat and not answered in time (or the guide moved on): nothing was changed, and it can no longer be confirmed.
enum ProposalState { waiting, running, done, cancelled, expired }

/// A question the assistant asks with choices to tap ("which of these two?"). Tapping one sends its words as the guide's
/// next message; [chosen] is the one tapped. In a saved chat that was answered it is shown read-only.
class QuestionEntry extends ChatEntry {
  QuestionEntry(this.question, this.choices, {this.chosen, this.task});

  /// The progress card of the request that led to this question; answering it finishes that card.
  final ProgressEntry? task;

  final String question;
  final List<AgentChoice> choices;
  int? chosen;

  bool get answered => chosen != null;
}

/// A change proposed and waiting for the guide, then what came of it.
class ProposalEntry extends ChatEntry {
  ProposalEntry(this.proposal, this.advice, {this.atMs, this.task});

  /// The progress card of the request that led to this card, so confirming or cancelling moves the same percentage on.
  final ProgressEntry? task;

  final AgentProposal proposal;

  /// When it was proposed (from a saved chat); a card older than [AgentController.proposalStale] cannot be confirmed.
  final int? atMs;

  /// Notes worked out on the phone, from the guide's own data.
  final List<String> advice;

  ProposalState state = ProposalState.waiting;

  /// What happened to each action, once run: callId → (ok, message).
  final Map<String, (bool, String)> results = {};
}

/// Runs the conversation with the server: sends what the guide says, answers the look-ups it asks
/// for, shows what it proposes, and runs what the guide confirms.
///
/// The server decides and checks; this class only obeys it, and only ever through the executors in
/// `AgentReads` / `AgentWrites*` — the shared functions the screens use, under the guide's own
/// sign-in. A deletion cannot run without both confirmations: that is enforced HERE, not just by
/// the buttons, so a bug in the page cannot skip the second one.
class AgentController extends ChangeNotifier {
  AgentController({HierarchyApi? api, AgentEnv? env, Map<String, AgentRun>? tools})
      : _api = api,
        _env = env,
        _tools = tools;

  final HierarchyApi? _api;
  final AgentEnv? _env;
  final Map<String, AgentRun>? _tools;

  HierarchyApi get api => _api ?? HierarchyApi.instance;
  AgentEnv get env => _env ?? (_defaultEnv ??= AgentEnv());
  AgentEnv? _defaultEnv;

  Map<String, AgentRun> get tools => _tools ?? _allTools;
  static final Map<String, AgentRun> _allTools = {...kAgentReads, ...kAgentWritesA, ...kAgentWritesB};

  /// The most look-up rounds one message may cost, so a confused model cannot spin the phone.
  static const int maxRounds = 12;

  /// The sub-collection of a saved chat that holds its lines (read only here; the server writes it).
  static const String _chatLines = 'entries';

  /// A change proposed longer ago than this is shown as not confirmed in an old chat (the server's own rule).
  static const Duration proposalStale = Duration(hours: 6);

  /// The most questions one session takes (the server's number; it repeats it in every reply).
  static const int defaultQuestionLimit = 20;

  final List<ChatEntry> entries = [];

  /// The progress card of the task being worked on right now.
  ProgressEntry? _task;
  String? _sessionId;
  bool _busy = false;
  bool get busy => _busy;

  /// This session's id; null before its first question.
  String? get sessionId => _sessionId;

  int questionLimit = defaultQuestionLimit;
  int questionsLeft = defaultQuestionLimit;

  /// The conversation is gone from the server: only a New chat helps, and only the guide starts one.
  bool sessionGone = false;

  /// The day the daily cap was reached (a date), so the notice ends by itself tomorrow.
  String? _limitDay;
  String _today() {
    final n = env.now;
    return '${n.year}-${n.month}-${n.day}';
  }

  bool get dailyLimit => _limitDay == _today();

  bool get sessionFull => questionsLeft <= 0;

  /// Can a question be asked now? (A card already shown can still be confirmed or cancelled either way.)
  bool get canAsk => !_busy && !dailyLimit && !sessionGone && !sessionFull;

  /// Starts afresh: a new conversation. Only ever called from the "New chat" button.
  void reset() {
    entries.clear();
    _sessionId = null;
    _busy = false;
    sessionGone = false;
    questionLimit = defaultQuestionLimit;
    questionsLeft = defaultQuestionLimit;
    env.invalidate();
    notifyListeners();
  }

  /// Opens one of this guide's saved chats exactly as it looked, ready to continue (the server still has its context).
  /// Throws an [AgentFailure] in words when it cannot.
  Future<void> openChat(String id) async {
    if (_busy) return;
    final ref = env.db.collection('agentChats').doc(id);
    final snap = await ref.get();
    final chat = snap.data();
    if (chat == null || chat['adminId'] != env.me.id) throw AgentFailure('That chat is not available.');
    final lines = await ref.collection(_chatLines).orderBy('seq').get();
    final rebuilt = <ChatEntry>[];
    for (final d in lines.docs) {
      final e = _entryFrom(d.data());
      if (e != null) rebuilt.add(e);
    }
    // a question is still open only if nothing came after it
    for (var i = 0; i < rebuilt.length - 1; i++) {
      final e = rebuilt[i];
      if (e is QuestionEntry) e.chosen = -1;
    }
    entries
      ..clear()
      ..addAll(rebuilt);
    _sessionId = id;
    sessionGone = false;
    questionLimit = (chat['questionLimit'] as num?)?.toInt() ?? defaultQuestionLimit;
    questionsLeft = (questionLimit - ((chat['questions'] as num?)?.toInt() ?? 0)).clamp(0, questionLimit);
    env.invalidate();
    notifyListeners();
  }

  ChatEntry? _entryFrom(Map<String, dynamic> m) {
    switch (m['kind']) {
      case 'user':
        return UserEntry((m['text'] ?? '').toString());
      case 'assistant':
        return AssistantEntry(
          (m['text'] ?? '').toString(),
          [for (final l in (m['links'] as List? ?? const []).whereType<Map>()) AgentLink.fromMap(l)],
        );
      case 'question':
        return QuestionEntry(
          (m['question'] ?? '').toString(),
          [for (final c in (m['choices'] as List? ?? const []).whereType<Map>()) AgentChoice.fromMap(c)],
        );
      case 'proposal':
        final raw = m['proposal'];
        if (raw is! Map) return null;
        final atMs = (m['atMs'] as num?)?.toInt();
        final entry = ProposalEntry(
          AgentProposal.fromMap(raw),
          [for (final a in (m['advice'] as List? ?? const [])) a.toString()],
          atMs: atMs,
        );
        entry.state = switch (m['state']) {
          'done' => ProposalState.done,
          'cancelled' => ProposalState.cancelled,
          'expired' => ProposalState.expired,
          _ => atMs != null && env.now.difference(DateTime.fromMillisecondsSinceEpoch(atMs)) > proposalStale ? ProposalState.expired : ProposalState.waiting,
        };
        final results = m['results'];
        if (results is Map) {
          results.forEach((k, v) {
            if (v is Map) entry.results[k.toString()] = (v['ok'] == true, (v['text'] ?? '').toString());
          });
        }
        return entry;
    }
    return null;
  }

  void _add(ChatEntry e) {
    entries.add(e);
    notifyListeners();
  }

  Future<AgentReply> _turn(Map<String, dynamic> data) async {
    final raw = await api.guideAgentTurn({if (_sessionId != null) 'sessionId': _sessionId, ...data});
    final reply = AgentReply.fromMap(raw);
    if (reply.sessionId != null) _sessionId = reply.sessionId;
    if (reply.questionLimit != null) questionLimit = reply.questionLimit!;
    if (reply.questionsLeft != null) questionsLeft = reply.questionsLeft!;
    return reply;
  }

  /// The guide said something.
  Future<void> send(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || !canAsk) return;
    _busy = true;
    _add(UserEntry(clean));
    final task = ProgressEntry(clean);
    _task = task;
    _add(task);
    try {
      await _handle(await _turn({'text': clean}));
    } catch (e) {
      final message = agentFailureMessage(e);
      task.progress.fail(message);
      _add(ErrorEntry(message));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// What the server said, and whatever it asks for next, until it is the guide's turn.
  Future<void> _handle(AgentReply first) async {
    var reply = first;
    for (var round = 0; round < maxRounds; round++) {
      // The conversation is gone from the server: say so; a New chat is the guide's to start, never started for them.
      if (reply.ended) sessionGone = true;
      switch (reply.status) {
        case AgentStatus.message:
          _task?.progress.finish();
          if (reply.text != null || reply.links.isNotEmpty) _add(AssistantEntry(reply.text ?? '', reply.links));
          return;

        case AgentStatus.limit:
        case AgentStatus.full:
          if (reply.status == AgentStatus.limit && reply.why != 'hour') _limitDay = _today();
          // the request was refused, not carried out: the card stops, with the reason
          _task?.progress.fail(reply.text ?? 'This could not be done now.');
          if (reply.text != null || reply.links.isNotEmpty) _add(AssistantEntry(reply.text ?? '', reply.links));
          return;

        case AgentStatus.question:
          _task?.waitingText = 'Waiting for your answer';
          _task?.progress.enter(TaskStep.preparing);
          _task?.progress.enter(TaskStep.confirming);
          if (reply.text != null) _add(AssistantEntry(reply.text!, const []));
          _add(QuestionEntry(reply.question ?? '', reply.choices, task: _task));
          return;

        case AgentStatus.confirm:
          _task?.progress.enter(TaskStep.preparing);
          if (reply.text != null) _add(AssistantEntry(reply.text!, const []));
          final p = reply.proposal!;
          final advice = await adviseFor(p, env);
          _task?.progress.enter(TaskStep.confirming);
          _add(ProposalEntry(p, [...p.headsUp, ...advice], task: _task));
          return;

        case AgentStatus.needReads:
          _task?.progress.enter(TaskStep.finding);
          final results = await Future.wait(reply.reads.map(_runTool));
          _task?.progress.enter(TaskStep.preparing);
          reply = await _turn({'toolResults': results});
      }
    }
    const tooMany = 'That took too many steps, so I stopped. Please say it again more simply.';
    _task?.progress.fail(tooMany);
    _add(ErrorEntry(tooMany));
  }

  Future<Map<String, dynamic>> _runTool(AgentRead read) async => (await _run(read.tool, read.args)).toWire(read.callId);

  Future<AgentResult> _run(String tool, Map<String, dynamic> args) async {
    final run = tools[tool];
    if (run == null) return AgentResult.failed("I can't do that on this phone.");
    try {
      return await run(args, env);
    } catch (e) {
      return AgentResult.failed(agentFailureMessage(e));
    }
  }

  /// The guide tapped a choice of a question: its words go as their next message.
  Future<void> choose(QuestionEntry entry, int index) async {
    if (entry.answered || !canAsk || index < 0 || index >= entry.choices.length) return;
    entry.chosen = index;
    entry.task?.doneText = 'Answered';
    entry.task?.progress.finish();
    notifyListeners();
    await send(entry.choices[index].reply);
  }

  /// The guide pressed Confirm. [confirmations] is how many times they confirmed (1, or 2 for a
  /// deletion): a deletion with fewer than two does not run.
  Future<void> confirm(ProposalEntry entry, {required int confirmations}) async {
    if (entry.state != ProposalState.waiting || _busy) return;
    if (entry.proposal.needsSecondConfirmation && confirmations < 2) {
      throw StateError('A deletion needs two confirmations.');
    }
    _busy = true;
    entry.state = ProposalState.running;
    _task = entry.task;
    _task?.progress.enter(TaskStep.saving);
    notifyListeners();
    try {
      final results = <Map<String, dynamic>>[];
      for (final action in entry.proposal.actions) {
        final r = await _run(action.tool, action.args);
        env.invalidate(); // the next look sees this change
        entry.results[action.callId] = (r.ok, r.ok ? _sentence(r.data) : (r.error ?? 'failed'));
        results.add(r.toWire(action.callId));
        notifyListeners();
      }
      entry.state = ProposalState.done;
      // a change that did not go through stops the card, with the reason; finishing is only for what truly worked
      final failed = entry.results.values.where((r) => !r.$1).toList();
      if (failed.isNotEmpty) _task?.progress.fail(failed.first.$2);
      await _handle(await _turn({
        'proposalId': entry.proposal.id,
        'outcome': 'executed',
        'confirmations': confirmations,
        'results': results,
        ..._shown(entry),
      }));
    } catch (e) {
      entry.state = ProposalState.done;
      final message = agentFailureMessage(e);
      _task?.progress.fail(message);
      _add(ErrorEntry(message));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// The guide pressed Cancel: nothing runs, and the server is told.
  Future<void> cancel(ProposalEntry entry) async {
    if (entry.state != ProposalState.waiting || _busy) return;
    _busy = true;
    entry.state = ProposalState.cancelled;
    _task = entry.task;
    _task?.progress.cancel();
    notifyListeners();
    try {
      await _handle(await _turn({'proposalId': entry.proposal.id, 'outcome': 'cancelled', 'results': const [], ..._shown(entry)}));
    } catch (e) {
      _add(ErrorEntry(agentFailureMessage(e)));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// What the guide saw on the card, for the chat history: the advice beside it and the words of each result.
  static Map<String, dynamic> _shown(ProposalEntry entry) => {
        'advice': entry.advice,
        'shown': [
          for (final a in entry.proposal.actions)
            if (entry.results[a.callId] case final r?) {'callId': a.callId, 'ok': r.$1, 'text': r.$2},
        ],
      };

  static String _sentence(Object? data) {
    if (data is Map && data['done'] is String) return data['done'] as String;
    return 'Done.';
  }
}
