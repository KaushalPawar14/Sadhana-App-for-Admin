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
  const AgentResult.ok(this.data, {this.entities = const []})
      : ok = true,
        error = null;

  /// A failure the guide can act on, in words. Never a stack trace.
  const AgentResult.failed(String this.error)
      : ok = false,
        data = null,
        entities = const [];

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
  });

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
        tainted: m['tainted'] == true,
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

enum AgentStatus { message, needReads, confirm, limit, full }

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
  });

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

  factory AgentReply.fromMap(Map<String, dynamic> m) {
    final status = switch (m['status']) {
      'need_reads' => AgentStatus.needReads,
      'confirm' => AgentStatus.confirm,
      'limit' => AgentStatus.limit,
      'full' => AgentStatus.full,
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
    );
  }
}
