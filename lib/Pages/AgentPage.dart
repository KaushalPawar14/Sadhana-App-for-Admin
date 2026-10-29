import 'package:flutter/material.dart';

import '../agent/AgentController.dart';
import '../agent/AgentOverlay.dart';
import '../agent/AgentRoutes.dart';
import '../agent/AgentTypes.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/Snackbar.dart';
import '../utils/VoiceNote.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideSurface.dart';
import '../utils/AiMarkdown.dart';
import '../widgets/AiText.dart';
import '../widgets/GuideWait.dart';
import '../widgets/VoiceNoteButton.dart';
import 'AgentChatsPage.dart';
import 'AgentLogPage.dart';

/// The assistant: one chat page, reached from the floating button on any screen.
///
/// It helps with THIS app only — where things are, and doing them — and does nothing without showing
/// exactly what it will do and being told to. A deletion asks twice. What it can do is exactly what the
/// signed-in guide can do by hand, nothing more (see `lib/agent/`).
class AgentPage extends StatefulWidget {
  const AgentPage({super.key, this.controller});

  /// Tests hand in their own controller; the app uses the one conversation of the session.
  final AgentController? controller;

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  late final AgentController _c = widget.controller ?? AgentSession.controller;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _seen = _c.entries.length;
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_c.entries.length != _seen) {
      _seen = _c.entries.length;
      _toEnd();
    }
  }

  /// Shows the newest entry. The list builds lazily, so its true end is only known once the new entry has been
  /// laid out: go to the end after the next frames, not before (a card taller than the screen would otherwise stop
  /// short, with its Confirm button under the box below).
  void _toEnd([int frames = 3]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      if (frames > 1) _toEnd(frames - 1);
    });
  }
  Future<void> _send([String? text]) async {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty || !_c.canAsk) return;
    _input.clear();
    await _c.send(t);
  }

  Future<void> _confirm(ProposalEntry entry) async {
    final p = entry.proposal;
    if (p.needsSecondConfirmation) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => GuideDialog(
          title: const Text('Delete for good?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This cannot be undone. You are about to:'),
              const SizedBox(height: 8),
              for (final a in p.actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(plainAiText('• ${a.title}${a.lines.isEmpty ? '' : ' — ${a.lines.map((l) => l.value).join(', ')}'}'), style: context.gText.bodyStrong),
                ),
            ],
          ),
          actions: [
            TextButton(key: const ValueKey('agent-keep'), onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
            TextButton(
              key: const ValueKey('agent-delete-yes'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Yes, delete', style: TextStyle(color: dialogContext.g.danger, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
      await _c.confirm(entry, confirmations: 2);
    } else {
      await _c.confirm(entry, confirmations: 1);
    }
  }

  Future<void> _open(AgentLink link) async {
    final problem = await openAgentLink(link, navigator: Navigator.of(context));
    if (problem != null && mounted) showSnackbar(context, problem, context.g.warning, Icons.info);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final isHod = AdminProfileProvider.viewerIsHod;
    return GuideScaffold(
      appBar: GuideAppBar(
        title: const Text('Assistant'),
        actions: [
          if (isHod)
            IconButton(
              key: const ValueKey('agent-log'),
              tooltip: 'What the assistant did',
              icon: Icon(Icons.history, color: g.text),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentLogPage())),
            ),
          IconButton(
            key: const ValueKey('agent-chats'),
            tooltip: 'Chat history',
            icon: Icon(Icons.forum_outlined, color: g.text),
            onPressed: _c.busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => AgentChatsPage(controller: _c))),
          ),
          IconButton(
            key: const ValueKey('agent-new-chat'),
            tooltip: 'New chat',
            icon: Icon(Icons.add_comment_outlined, color: g.text),
            onPressed: _c.busy
                ? null
                : () {
                    _c.reset();
                    _input.clear();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _c.entries.isEmpty ? _welcome(context) : _conversation(context)),
          _composer(context),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  Widget _welcome(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    const ideas = [
      'Where do I add a trip?',
      'Who needs my attention this week?',
      'Set up a meeting with a student',
      'Start a chanting competition',
    ];
    return ListView(
      key: const ValueKey('agent-welcome'),
      padding: const EdgeInsets.all(GuideSpace.pagePadding),
      children: [
        const SizedBox(height: 12),
        Icon(Icons.auto_awesome, color: g.agent, size: 34),
        const SizedBox(height: 12),
        Text('How can I help?', style: t.sectionTitle),
        const SizedBox(height: 8),
        Text(
          'I can find things in this app and do them for you — set up meetings, log interactions, assign books, '
          'start competitions and more. I always show you exactly what I will do, and I only go ahead when you say so.',
          style: t.small.copyWith(height: 1.45),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final i in ideas)
              Material(
                color: g.surface,
                shape: StadiumBorder(side: BorderSide(color: g.agent.withValues(alpha: .5))),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _send(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Text(i, style: t.buttonSecondary),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _conversation(BuildContext context) {
    return ListView(
      key: const ValueKey('agent-conversation'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(GuideSpace.lg, GuideSpace.lg, GuideSpace.lg, GuideSpace.sm),
      children: [
        for (final e in _c.entries) Padding(padding: const EdgeInsets.only(bottom: 10), child: _entry(context, e)),
        if (_c.busy) _working(context),
      ],
    );
  }

  Widget _working(BuildContext context) => Padding(
        key: const ValueKey('agent-working'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: 18, height: 18, child: GuideBusyDot()),
            const SizedBox(width: 12),
            Expanded(child: Text('Working on it…', style: context.gText.small)),
          ],
        ),
      );

  Widget _entry(BuildContext context, ChatEntry e) {
    final g = context.g;
    final t = context.gText;
    final width = MediaQuery.of(context).size.width;
    switch (e) {
      case UserEntry():
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width * .85),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: g.agent, borderRadius: BorderRadius.circular(GuideShape.inputRadius)),
              child: Text(e.text, style: t.body.copyWith(color: g.onPrimary)),
            ),
          ),
        );
      case AssistantEntry():
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width * .92),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: g.surface,
                borderRadius: BorderRadius.circular(GuideShape.inputRadius),
                border: Border.all(color: g.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e.text.isNotEmpty) AiText(e.text, selectable: true, style: t.body.copyWith(height: 1.45)),
                  if (e.links.isNotEmpty) ...[
                    if (e.text.isNotEmpty) const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final l in e.links)
                          OutlinedButton.icon(
                            key: ValueKey('agent-link-${l.route}'),
                            onPressed: () => _open(l),
                            icon: Icon(Icons.arrow_forward, size: 16, color: g.agent),
                            label: Text(agentLinkLabel(l), style: TextStyle(color: g.agent)),
                            style: OutlinedButton.styleFrom(side: BorderSide(color: g.agent)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      case ErrorEntry():
        return Container(
          key: const ValueKey('agent-error'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: g.warning.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(GuideShape.inputRadius),
            border: Border.all(color: g.warning.withValues(alpha: .4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 18, color: g.warning),
              const SizedBox(width: 8),
              Expanded(child: Text(e.text, style: t.body.copyWith(height: 1.4))),
            ],
          ),
        );
      case ProposalEntry():
        return _ProposalCard(entry: e, busy: _c.busy, onConfirm: () => _confirm(e), onCancel: () => _c.cancel(e));
      case QuestionEntry():
        return _QuestionCard(key: ValueKey('agent-question-${identityHashCode(e)}'), entry: e, enabled: _c.canAsk, onChoose: (i) => _c.choose(e, i));
    }
  }

  /// Why the box is closed, in the guide's words; null while they can ask.
  String? get _closedReason {
    if (_c.sessionGone) return 'This conversation has ended — start a New chat';
    if (_c.dailyLimit) return 'Daily limit reached — try again tomorrow';
    if (_c.sessionFull) return 'This session is full — start a New chat';
    return null;
  }

  Widget _composer(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final closed = _closedReason;
    final left = _c.questionsLeft;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(GuideSpace.md, 6, GuideSpace.md, GuideSpace.sm),
        decoration: BoxDecoration(color: g.surface, border: Border(top: BorderSide(color: g.border))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (closed != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: g.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        closed,
                        key: ValueKey(_c.sessionGone ? 'agent-session-gone' : _c.dailyLimit ? 'agent-daily-limit' : 'agent-session-full'),
                        style: t.small.copyWith(color: g.warning, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$left ${left == 1 ? 'question' : 'questions'} left in this session',
                    key: const ValueKey('agent-questions-left'),
                    style: t.caption,
                  ),
                ),
              ),
            VoiceNoteButton(
              purpose: VoicePurpose.assistant,
              enabled: !_c.busy && closed == null,
              existingText: () => _input.text,
              onText: (spoken) {
                _input.text = appendNote(_input.text, spoken);
                _input.selection = TextSelection.collapsed(offset: _input.text.length);
                _focus.requestFocus();
              },
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('agent-input'),
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textInputAction: TextInputAction.newline,
                    enabled: closed == null,
                    decoration: InputDecoration(hintText: closed ?? 'Ask me, or tell me what to do', counterText: ''),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const ValueKey('agent-send'),
                  tooltip: 'Send',
                  onPressed: _c.canAsk ? _send : null,
                  icon: Icon(Icons.send_rounded, color: _c.canAsk ? g.agent : g.mutedText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The confirmation card
// ---------------------------------------------------------------------------
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.entry, required this.busy, required this.onConfirm, required this.onCancel});

  final ProposalEntry entry;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final p = entry.proposal;
    final delete = p.needsSecondConfirmation;
    final accent = delete ? g.danger : g.agent;

    return Container(
      key: ValueKey('agent-proposal-${p.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: g.surface,
        borderRadius: BorderRadius.circular(GuideShape.cardRadius),
        border: Border.all(color: accent, width: 1.4),
        boxShadow: g.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(delete ? Icons.delete_outline : Icons.fact_check_outlined, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  switch (entry.state) {
                    ProposalState.waiting => delete ? 'This will delete — please check' : "Here's what I'll do — please check",
                    ProposalState.running => 'Doing it…',
                    ProposalState.done => 'Done',
                    ProposalState.cancelled => 'Cancelled — nothing was changed',
                    ProposalState.expired => 'Not confirmed — nothing was changed',
                  },
                  style: t.cardTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < p.actions.length; i++) ...[
            if (i > 0) Divider(color: g.border, height: 20),
            _action(context, p.actions[i]),
          ],
          if (entry.state == ProposalState.waiting && entry.advice.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final line in entry.advice)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(p.tainted && line == entry.advice.first ? Icons.warning_amber_rounded : Icons.lightbulb_outline,
                        size: 16, color: p.tainted && line == entry.advice.first ? g.warning : g.agent),
                    const SizedBox(width: 8),
                    Expanded(child: AiText(line, style: t.small.copyWith(height: 1.4, color: g.text))),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          _footer(context, accent, delete),
        ],
      ),
    );
  }

  Widget _action(BuildContext context, AgentAction a) {
    final g = context.g;
    final t = context.gText;
    final result = entry.results[a.callId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result != null) ...[
              Icon(result.$1 ? Icons.check_circle : Icons.cancel, size: 18, color: result.$1 ? g.success : g.danger),
              const SizedBox(width: 6),
            ],
            Expanded(child: AiText(a.title, style: t.cardTitleSmall)),
          ],
        ),
        const SizedBox(height: 6),
        for (final l in a.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.label, style: t.caption),
                if (l.items.length > 3)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final item in l.items)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: g.chipBackground, borderRadius: BorderRadius.circular(GuideShape.chipRadius)),
                          child: Text(item, style: t.pill),
                        ),
                    ],
                  )
                else
                  AiText(l.value, style: t.body),
              ],
            ),
          ),
        for (final n in a.notifies)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notifications_none, size: 15, color: g.mutedText),
                const SizedBox(width: 6),
                Expanded(child: Text('Tells ${n.startsWith('the ') ? n : n}', style: t.caption)),
              ],
            ),
          ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AiText(result.$2, key: ValueKey('agent-result-${a.callId}'), style: t.small.copyWith(color: result.$1 ? g.text : g.danger, height: 1.4)),
          ),
      ],
    );
  }

  Widget _footer(BuildContext context, Color accent, bool delete) {
    final g = context.g;
    switch (entry.state) {
      case ProposalState.waiting:
        return Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(key: const ValueKey('agent-cancel'), onPressed: busy ? null : onCancel, child: const Text('Cancel')),
              ElevatedButton(
                key: const ValueKey('agent-confirm'),
                onPressed: busy ? null : onConfirm,
                style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: g.onPrimary),
                child: Text(delete ? 'Delete…' : 'Confirm'),
              ),
            ],
          ),
        );
      case ProposalState.running:
        return Row(children: [
          const SizedBox(width: 16, height: 16, child: GuideBusyDot()),
          const SizedBox(width: 10),
          Text('Working…', style: context.gText.small),
        ]);
      case ProposalState.done:
      case ProposalState.cancelled:
      case ProposalState.expired:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// A question with choices to tap
// ---------------------------------------------------------------------------
/// The assistant asks WHICH one ("which of these two follow-ups?"): each choice is a tile with its details, side by side
/// when there are two and the screen allows, so the guide compares them and taps. The tap is sent as their next message. The
/// card eases in; with reduce-motion it simply appears.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({super.key, required this.entry, required this.enabled, required this.onChoose});

  final QuestionEntry entry;
  final bool enabled;
  final void Function(int index) onChoose;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final media = MediaQuery.of(context);
    final sideBySide = entry.choices.length == 2 && media.size.width >= 340 && media.textScaler.scale(14) <= 14 * 1.3;
    final open = enabled && !entry.answered;

    Widget tile(int i) {
      final c = entry.choices[i];
      final picked = entry.chosen == i;
      return Material(
        color: picked ? g.agent.withValues(alpha: .14) : g.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GuideShape.inputRadius),
          side: BorderSide(color: picked ? g.agent : g.border, width: picked ? 1.6 : 1),
        ),
        child: InkWell(
          key: ValueKey('agent-choice-$i'),
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GuideShape.inputRadius)),
          onTap: open ? () => onChoose(i) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: AiText(c.label, style: t.small.copyWith(fontWeight: FontWeight.w700, height: 1.3, color: g.text))),
                    if (picked) Icon(Icons.check_circle, size: 18, color: g.agent),
                  ],
                ),
                if (c.detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  AiText(c.detail, style: t.caption.copyWith(height: 1.35)),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final tiles = sideBySide
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: tile(0)), const SizedBox(width: 8), Expanded(child: tile(1))],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (var i = 0; i < entry.choices.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: tile(i))],
          );

    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: g.surface,
        borderRadius: BorderRadius.circular(GuideShape.cardRadius),
        border: Border.all(color: g.agent.withValues(alpha: .6), width: 1.4),
        boxShadow: g.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.help_outline_rounded, size: 20, color: g.agent),
              const SizedBox(width: 8),
              Expanded(child: AiText(entry.question, style: t.cardTitleSmall)),
            ],
          ),
          const SizedBox(height: 10),
          tiles,
        ],
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: GuideMotion.of(context, GuideMotion.expand),
      curve: GuideMotion.standard,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child)),
      child: card,
    );
  }
}
