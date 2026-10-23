import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../Services/HierarchyApi.dart';
import '../utils/VoiceNote.dart' show voiceReason;
import 'AgentAdvisor.dart';
import 'AgentEnv.dart';
import 'AgentReads.dart';
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

enum ProposalState { waiting, running, done, cancelled }

/// A change proposed and waiting for the guide, then what came of it.
class ProposalEntry extends ChatEntry {
  ProposalEntry(this.proposal, this.advice);

  final AgentProposal proposal;

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

  final List<ChatEntry> entries = [];
  String? _sessionId;
  bool _busy = false;
  bool get busy => _busy;

  /// Starts afresh: a new conversation.
  void reset() {
    entries.clear();
    _sessionId = null;
    _busy = false;
    env.invalidate();
    notifyListeners();
  }

  void _add(ChatEntry e) {
    entries.add(e);
    notifyListeners();
  }

  Future<AgentReply> _turn(Map<String, dynamic> data) async {
    final raw = await api.guideAgentTurn({if (_sessionId != null) 'sessionId': _sessionId, ...data});
    final reply = AgentReply.fromMap(raw);
    if (reply.sessionId != null) _sessionId = reply.sessionId;
    return reply;
  }

  /// The guide said something.
  Future<void> send(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _busy) return;
    _busy = true;
    _add(UserEntry(clean));
    try {
      await _handle(await _turn({'text': clean}));
    } catch (e) {
      _add(ErrorEntry(agentFailureMessage(e)));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// What the server said, and whatever it asks for next, until it is the guide's turn.
  Future<void> _handle(AgentReply first) async {
    var reply = first;
    for (var round = 0; round < maxRounds; round++) {
      if (reply.ended) _sessionId = null;
      switch (reply.status) {
        case AgentStatus.message:
        case AgentStatus.limit:
          if (reply.text != null || reply.links.isNotEmpty) _add(AssistantEntry(reply.text ?? '', reply.links));
          return;

        case AgentStatus.confirm:
          if (reply.text != null) _add(AssistantEntry(reply.text!, const []));
          final p = reply.proposal!;
          final advice = await adviseFor(p, env);
          _add(ProposalEntry(p, [...p.headsUp, ...advice]));
          return;

        case AgentStatus.needReads:
          final results = await Future.wait(reply.reads.map(_runTool));
          reply = await _turn({'toolResults': results});
      }
    }
    _add(ErrorEntry('That took too many steps, so I stopped. Please say it again more simply.'));
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

  /// The guide pressed Confirm. [confirmations] is how many times they confirmed (1, or 2 for a
  /// deletion): a deletion with fewer than two does not run.
  Future<void> confirm(ProposalEntry entry, {required int confirmations}) async {
    if (entry.state != ProposalState.waiting || _busy) return;
    if (entry.proposal.needsSecondConfirmation && confirmations < 2) {
      throw StateError('A deletion needs two confirmations.');
    }
    _busy = true;
    entry.state = ProposalState.running;
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
      await _handle(await _turn({
        'proposalId': entry.proposal.id,
        'outcome': 'executed',
        'confirmations': confirmations,
        'results': results,
      }));
    } catch (e) {
      entry.state = ProposalState.done;
      _add(ErrorEntry(agentFailureMessage(e)));
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
    notifyListeners();
    try {
      await _handle(await _turn({'proposalId': entry.proposal.id, 'outcome': 'cancelled', 'results': const []}));
    } catch (e) {
      _add(ErrorEntry(agentFailureMessage(e)));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static String _sentence(Object? data) {
    if (data is Map && data['done'] is String) return data['done'] as String;
    return 'Done.';
  }
}
