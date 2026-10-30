/// What passes between the phone and the agent's server (functions/guideAgent.js).
///
/// Everything here is plain data. The server decides what to do next and says so in
/// [AgentReply.status]; the phone answers reads, shows proposals, and runs confirmed changes.

/// Something the phone found that the agent may now refer to by id: a student, a meeting, a book.
///
/// The server accepts an id in a change only if the phone handed it over in this
/// conversation, so a name the phone never showed (a student outside the guide's scope, say)
/// cannot be acted on — and cannot even be named.
class AgentEntity {
  const AgentEntity(this.kind, this.id, this.name, [this.extra = const {}]);

  final String kind;
  final String id;
  final String name;

  /// A few small facts the server may need to check a change (an admin's role, say).
  final Map<String, Object> extra;

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'id': id,
        'name': name,
        if (extra.isNotEmpty) 'extra': extra,
      };
}

/// What a tool run on the phone came to.
class AgentResult {
  const AgentResult.ok(this.data, {this.entities = const [], this.undo})
      : ok = true,
        error = null;

  /// A failure the guide can act on, in words. Never a stack trace.
  const AgentResult.failed(String this.error)
      : ok = false,
        data = null,
        entities = const [],
        undo = null;

  /// How to take this change back (the Undo button, for a few minutes); null when it cannot be undone (a message already sent ...).
  final Future<void> Function()? undo;

  final bool ok;
  final Object? data;
  final String? error;
  final List<AgentEntity> entities;

  Map<String, dynamic> toWire(String callId) => {
        'callId': callId,
        'ok': ok,
        if (ok) 'data': data,
        if (!ok) 'error': error,
        if (entities.isNotEmpty) 'entities': [for (final e in entities) e.toMap()],
      };
}

/// A button the agent offers under its answer: open a screen.
class AgentLink {
  const AgentLink({required this.route, this.studentUid, this.studentName});

  final String route;
  final String? studentUid;
  final String? studentName;

  factory AgentLink.fromMap(Map m) => AgentLink(
        route: (m['route'] ?? '').toString(),
        studentUid: m['studentUid']?.toString(),
        studentName: m['studentName']?.toString(),
      );
}

/// One line of a confirmation card: what, and its value in the app's own words.
class AgentLine {
  const AgentLine(this.label, this.value, [this.items = const []]);

  final String label;
  final String value;

  /// The whole list, when the value is a list: the card shows EVERY name.
  final List<String> items;

  factory AgentLine.fromMap(Map m) => AgentLine(
        (m['label'] ?? '').toString(),
        (m['value'] ?? '').toString(),
        [for (final i in (m['items'] as List? ?? const [])) i.toString()],
      );
}

/// One change the agent proposes.
class AgentAction {
  const AgentAction({
    required this.callId,
    required this.tool,
    required this.args,
    required this.title,
    required this.lines,
    required this.notifies,
    required this.double,
  });

  final String callId;
  final String tool;
  final Map<String, dynamic> args;
  final String title;
  final List<AgentLine> lines;

  /// Who is told, and how — from the catalogue.
  final List<String> notifies;

  /// A deletion: the guide is asked twice.
  final bool double;

  factory AgentAction.fromMap(Map m) => AgentAction(
        callId: (m['callId'] ?? '').toString(),
        tool: (m['tool'] ?? '').toString(),
        args: Map<String, dynamic>.from((m['args'] as Map?) ?? const {}),
        title: (m['title'] ?? '').toString(),
        lines: [for (final l in (m['lines'] as List? ?? const [])) AgentLine.fromMap(l as Map)],
        notifies: [for (final n in (m['notifies'] as List? ?? const [])) n.toString()],
        double: m['double'] == true,
      );
}

/// What the agent would do, shown for confirmation before anything happens.
class AgentProposal {
  AgentProposal({
    required this.id,
    required this.actions,
    required this.headsUp,
    required this.tainted,
    this.auto = false,
  });

  /// The server says it runs at once (with an Undo afterwards): nothing in it is a deletion and nothing came from what a student wrote.
  final bool auto;

  final String id;
  final List<AgentAction> actions;

  /// Notes beside the card: who gets notified, what cannot be undone, a warning if it was
  /// prepared after reading students' own words — plus advice worked out on the phone.
  final List<String> headsUp;
  final bool tainted;

  /// Any action in it is a deletion.
  bool get needsSecondConfirmation => actions.any((a) => a.double);

  factory AgentProposal.fromMap(Map m) => AgentProposal(
        id: (m['id'] ?? '').toString(),
        actions: [for (final a in (m['actions'] as List? ?? const [])) AgentAction.fromMap(a as Map)],
        headsUp: [for (final h in (m['headsUp'] as List? ?? const [])) h.toString()],
        auto: m['auto'] == true,
        tainted: m['tainted'] == true,
      );
}

/// One choice of a question the assistant asks: what it is called, what to compare it by, and what tapping it says.
class AgentChoice {
  const AgentChoice({required this.label, this.detail = '', required this.reply});

  final String label;
  final String detail;

  /// Sent as the guide's next message when they tap it.
  final String reply;

  factory AgentChoice.fromMap(Map m) => AgentChoice(
        label: (m['label'] ?? '').toString(),
        detail: (m['detail'] ?? '').toString(),
        reply: (m['reply'] ?? m['label'] ?? '').toString(),
      );
}

/// A look-up the agent asked the phone to make.
class AgentRead {
  const AgentRead(this.callId, this.tool, this.args);

  final String callId;
  final String tool;
  final Map<String, dynamic> args;

  factory AgentRead.fromMap(Map m) => AgentRead(
        (m['callId'] ?? '').toString(),
        (m['tool'] ?? '').toString(),
        Map<String, dynamic>.from((m['args'] as Map?) ?? const {}),
      );
}

/// A "Guide me" button: one instruction of the assistant's answer and the screen that does it (the same seven places as Today's buttons). It is only a
/// pointer — the student, and a book title as a hint — so it can be saved with the chat and resolved when it is tapped.
class GuideButton {
  const GuideButton({required this.action, required this.label, required this.line, this.studentUid = '', this.studentName = '', this.hint = ''});

  /// record_interaction | update_book | assign_book | change_commitment | answer_doubt | open_meeting | open_profile
  final String action;
  final String label;
  final String line;
  final String studentUid;
  final String studentName;
  final String hint;

  static GuideButton? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final action = (raw['action'] ?? '').toString();
    if (action.isEmpty) return null;
    return GuideButton(
      action: action,
      label: (raw['label'] ?? '').toString(),
      line: (raw['line'] ?? '').toString(),
      studentUid: (raw['studentUid'] ?? '').toString(),
      studentName: (raw['studentName'] ?? '').toString(),
      hint: (raw['hint'] ?? '').toString(),
    );
  }
}

enum AgentStatus { message, needReads, confirm, limit, full, question }

/// The server's answer to one step.
class AgentReply {
  AgentReply({
    required this.sessionId,
    required this.status,
    this.text,
    this.links = const [],
    this.reads = const [],
    this.proposal,
    this.ended = false,
    this.why,
    this.questionsLeft,
    this.questionLimit,
    this.question,
    this.choices = const [],
    this.executed,
    this.buttons = const [],
    this.notDone = false,
  });

  /// The server says nothing was done for this request (it could not, or was refused): the progress card then says "Not done", never "Done".
  final bool notDone;

  /// "Guide me": the buttons of the answer (each opens a screen for a student).
  final List<GuideButton> buttons;

  /// Changes the SERVER ran by itself (so they finish even if the app is closed): shown as a card that is already done, with its Undo.
  final ExecutedByServer? executed;

  final String? sessionId;
  final AgentStatus status;
  final String? text;
  final List<AgentLink> links;
  final List<AgentRead> reads;
  final AgentProposal? proposal;

  /// The conversation is gone from the server: the guide starts a New chat (never done for them).
  final bool ended;

  /// With [AgentStatus.limit]: "day" (the daily cap) or "hour".
  final String? why;

  /// How many more questions this session takes, and its limit (the server says so in every reply).
  final int? questionsLeft;
  final int? questionLimit;

  /// With [AgentStatus.question]: what the assistant asks, and the choices to tap.
  final String? question;
  final List<AgentChoice> choices;

  factory AgentReply.fromMap(Map<String, dynamic> m) {
    final status = switch (m['status']) {
      'need_reads' => AgentStatus.needReads,
      'confirm' => AgentStatus.confirm,
      'limit' => AgentStatus.limit,
      'full' => AgentStatus.full,
      'question' => AgentStatus.question,
      _ => AgentStatus.message,
    };
    return AgentReply(
      sessionId: m['sessionId']?.toString(),
      status: status,
      text: (m['text'] as String?)?.trim().isEmpty ?? true ? null : (m['text'] as String).trim(),
      links: [for (final l in (m['links'] as List? ?? const [])) AgentLink.fromMap(l as Map)],
      reads: [for (final r in (m['reads'] as List? ?? const [])) AgentRead.fromMap(r as Map)],
      proposal: m['proposal'] is Map ? AgentProposal.fromMap(m['proposal'] as Map) : null,
      ended: m['ended'] == true,
      why: m['why']?.toString(),
      questionsLeft: (m['questionsLeft'] as num?)?.toInt(),
      questionLimit: (m['questionLimit'] as num?)?.toInt(),
      question: m['question']?.toString(),
      choices: [for (final c in (m['choices'] as List? ?? const []).whereType<Map>()) AgentChoice.fromMap(c)],
      executed: m['executed'] is Map ? ExecutedByServer.fromMap(m['executed'] as Map) : null,
      buttons: [for (final b in (m['buttons'] as List? ?? const [])) if (GuideButton.fromMap(b) case final x?) x],
      notDone: m['notDone'] == true,
    );
  }
}

/// What the server did on its own: the proposal, what each action came to, and the server calls that take each back.
class ExecutedByServer {
  const ExecutedByServer({required this.proposal, required this.results, required this.undo});

  final AgentProposal proposal;

  /// callId → (ok, the sentence).
  final Map<String, (bool, String)> results;

  /// The callable and data of each Undo.
  final List<({String name, Map<String, dynamic> data})> undo;

  factory ExecutedByServer.fromMap(Map m) => ExecutedByServer(
        proposal: AgentProposal.fromMap(m['proposal'] as Map),
        results: {
          for (final r in (m['results'] as List? ?? const []).whereType<Map>()) (r['callId'] ?? '').toString(): (r['ok'] != false, (r['text'] ?? '').toString()),
        },
        undo: [
          for (final u in (m['undo'] as List? ?? const []).whereType<Map>()) (name: (u['name'] ?? '').toString(), data: Map<String, dynamic>.from((u['data'] as Map?) ?? const {})),
        ],
      );
}
