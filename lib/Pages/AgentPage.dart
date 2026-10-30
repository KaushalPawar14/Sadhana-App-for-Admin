import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/Responsive.dart';

import '../agent/AgentController.dart';
import '../agent/AgentOverlay.dart';
import '../agent/AgentRoutes.dart';
import '../agent/AgentTypes.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/UnseenAggregates.dart';
import '../utils/UnseenDot.dart';
import '../utils/Snackbar.dart';
import '../utils/VoiceNote.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideSurface.dart';
import '../utils/AiMarkdown.dart';
import '../theme/AgentLook.dart';
import '../widgets/AiText.dart';
import '../widgets/TaskProgressCard.dart';
import '../widgets/ThinkingDots.dart';
import '../widgets/GuideWait.dart';
import '../widgets/VoiceNoteButton.dart';
import 'AgentChatsPage.dart';
import 'PlanPage.dart';

/// The assistant: one chat page, reached from the floating button on any screen.
///
/// It helps with THIS app only — where things are, and doing them — and does nothing without showing
/// exactly what it will do and being told to. A deletion asks twice. What it can do is exactly what the
/// signed-in guide can do by hand, nothing more (see `lib/agent/`).
class AgentPage extends StatefulWidget {
  const AgentPage({super.key, this.controller, this.onClose});

  /// Set when the page is the side panel of a computer: shows a close button (there is no "back" in a panel).
  final VoidCallback? onClose;

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

  /// Orange dot on "Plan" while the plan changed since it was last opened. Built once (a live listener).
  late final Stream<bool> _planUnseen = UnseenAggregates.planUnseen(AdminProfileProvider.current?.id ?? '');

  /// How many entries were already there when the page opened: those are drawn without an entrance, new ones ease in.
  int _opened = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _seen = _c.entries.length;
    _opened = _c.entries.length;
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
    return GuideScaffold(
      appBar: GuideAppBar(
        title: const Text('Assistant'),
        // three buttons: Chat history, New chat, Plan (the Assistant log lives in the Tasks tab)
        actions: [
          if (widget.onClose != null)
            IconButton(key: const ValueKey('agent-close'), tooltip: 'Close the assistant', icon: Icon(Icons.close, color: g.text), onPressed: widget.onClose),
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
          StreamBuilder<bool>(
            stream: _planUnseen,
            builder: (context, snap) => UnseenBadge(
              key: const ValueKey('agent-plan-dot'),
              show: snap.data ?? false,
              offset: const Offset(6, 6),
              child: IconButton(
                key: const ValueKey('agent-plan'),
                tooltip: 'Plan',
                icon: Icon(Icons.event_available_outlined, color: g.text),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanPage())),
              ),
            ),
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
                color: g.agentWash,
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
        for (var i = 0; i < _c.entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _EntryIn(key: ObjectKey(_c.entries[i]), animate: i >= _opened, fromRight: _c.entries[i] is UserEntry, child: _entry(context, _c.entries[i])),
          ),
        if (_c.busy) _working(context),
      ],
    );
  }

  Widget _working(BuildContext context) => const Padding(
        key: ValueKey('agent-working'),
        padding: EdgeInsets.symmetric(vertical: 4),
        child: _TypingBubble(),
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
              decoration: BoxDecoration(
                gradient: g.agentGradientWide,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(5)),
                boxShadow: [BoxShadow(color: g.agentBottom.withValues(alpha: g.isDark ? .30 : .26), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Text(e.text, style: t.body.copyWith(color: g.onAgent, fontWeight: FontWeight.w600)),
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
                color: g.agentWash,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
                border: Border.all(color: g.agent.withValues(alpha: .28)),
                boxShadow: g.cardShadow,
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
        return _ProposalCard(entry: e, busy: _c.busy, onConfirm: () => _confirm(e), onCancel: () => _c.cancel(e), onUndo: () => _c.undo(e));
      case ProgressEntry():
        return TaskProgressCard(key: ObjectKey(e), entry: e);
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
                revealAppend(_input, spoken, animate: !(MediaQuery.maybeDisableAnimationsOf(context) ?? false), done: _focus.requestFocus);
              },
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CallbackShortcuts(
                    // A keyboard: Enter sends, Shift+Enter is a new line (only where there is a keyboard-sized window; a phone's Enter stays a new line).
                    bindings: context.isWide
                        ? {
                            const SingleActivator(LogicalKeyboardKey.enter): () {
                              if (_c.canAsk && _input.text.trim().isNotEmpty) _send();
                            },
                          }
                        : const {},
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
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 2),
                  child: _SendButton(key: const ValueKey('agent-send'), onPressed: _c.canAsk ? _send : null),
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
  const _ProposalCard({required this.entry, required this.busy, required this.onConfirm, required this.onCancel, required this.onUndo});

  final ProposalEntry entry;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onUndo;

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
              Icon(
                switch (entry.state) {
                  ProposalState.done => entry.results.values.every((r) => r.$1) ? Icons.check_circle : Icons.cancel,
                  ProposalState.cancelled || ProposalState.expired => Icons.block,
                  _ => delete ? Icons.delete_outline : Icons.fact_check_outlined,
                },
                color: entry.state == ProposalState.done ? (entry.results.values.every((r) => r.$1) ? g.success : g.danger) : accent,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  switch (entry.state) {
                    ProposalState.waiting => delete ? 'This will delete — please check' : "Here's what I'll do — please check",
                    ProposalState.running => p.actions.length > 1 ? 'Doing it… ${entry.results.length} of ${p.actions.length} done' : 'Doing it…',
                    ProposalState.done => _doneTitle(),
                    ProposalState.cancelled => 'Cancelled — nothing was changed',
                    ProposalState.expired => 'Not confirmed — nothing was changed',
                  },
                  style: t.cardTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (entry.state == ProposalState.done && p.actions.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                key: const ValueKey('agent-batch-summary'),
                children: [
                  Icon(Icons.check_circle, size: 16, color: g.success),
                  const SizedBox(width: 4),
                  Text('${entry.results.values.where((r) => r.$1).length} done', style: t.bodyStrong),
                  if (entry.results.values.any((r) => !r.$1)) ...[
                    const SizedBox(width: 14),
                    Icon(Icons.cancel, size: 16, color: g.danger),
                    const SizedBox(width: 4),
                    Text('${entry.results.values.where((r) => !r.$1).length} failed', style: t.bodyStrong.copyWith(color: g.danger)),
                  ],
                ],
              ),
            ),
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

  /// "Done", or how many of a batch went through (some may fail while the rest are done).
  String _doneTitle() {
    final total = entry.proposal.actions.length;
    final ok = entry.results.values.where((r) => r.$1).length;
    if (entry.undone) return 'Undone';
    if (total <= 1 || ok == total) return 'Done: ${plainAiText(entry.proposal.actions.map((a) => a.title).take(2).join(', '))}${total > 2 ? ' and ${total - 2} more' : ''}';
    return ok == 0 ? 'None of these went through' : '$ok of $total done';
  }

  Widget _action(BuildContext context, AgentAction a) {
    final g = context.g;
    final t = context.gText;
    final result = entry.results[a.callId];
    // while a batch runs, the item being done now spins and the ones still to come wait
    final running = entry.state == ProposalState.running && entry.proposal.actions.length > 1;
    final current = running && result == null && entry.proposal.actions.firstWhere((x) => entry.results[x.callId] == null).callId == a.callId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (running && result == null) ...[
              SizedBox(
                key: ValueKey(current ? 'agent-item-running-${a.callId}' : 'agent-item-waiting-${a.callId}'),
                width: 18,
                height: 18,
                child: current
                    ? CircularProgressIndicator(strokeWidth: 2.2, color: g.agent)
                    : Icon(Icons.circle_outlined, size: 18, color: g.mutedText),
              ),
              const SizedBox(width: 6),
            ],
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
                style: ElevatedButton.styleFrom(backgroundColor: delete ? accent : g.agentMid, foregroundColor: delete ? g.onPrimary : g.onAgent, elevation: delete ? 1 : 3, shadowColor: g.agentBottom),
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
        // UNDO, for a few minutes, when the change can be taken back
        if (entry.canUndo || entry.undoing) {
          return Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              key: const ValueKey('agent-undo'),
              onPressed: entry.undoing || busy ? null : onUndo,
              icon: const Icon(Icons.undo, size: 18),
              label: Text(entry.undoing ? 'Undoing…' : 'Undo'),
            ),
          );
        }
        return const SizedBox.shrink();
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

// ---------------------------------------------------------------------------
// Entrance, typing indicator, send button
// ---------------------------------------------------------------------------
/// A new line of the conversation eases in: it fades up from a little below (the guide's own from the right). Lines that were
/// already there when the page opened, and any line with reduce-motion on, are simply drawn.
class _EntryIn extends StatelessWidget {
  const _EntryIn({super.key, required this.animate, required this.fromRight, required this.child});

  final bool animate;
  final bool fromRight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: GuideMotion.of(context, const Duration(milliseconds: 320)),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(fromRight ? (1 - v) * 18 : 0, (1 - v) * 14), child: child),
      ),
      child: child,
    );
  }
}

/// "The assistant is thinking": three dots that rise and fall in turn (see [ThinkingDots]), in a bubble like the assistant's own.
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Semantics(
      label: 'The assistant is thinking',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: g.surface,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
            border: Border.all(color: g.agent.withValues(alpha: .28)),
          ),
          child: ThinkingDots(key: const ValueKey('agent-thinking-dots'), colour: g.agent),
        ),
      ),
    );
  }
}

/// The send button: a sky-blue disc with the arrow on it (greyed when nothing can be sent).
class _SendButton extends StatelessWidget {
  const _SendButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final on = onPressed != null;
    return Semantics(
      button: true,
      enabled: on,
      label: 'Send',
      child: Tooltip(
        message: 'Send',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: on ? g.agentGradient : null,
                color: on ? null : g.border,
                boxShadow: on ? [BoxShadow(color: g.agentBottom.withValues(alpha: .35), blurRadius: 8, offset: const Offset(0, 3))] : null,
              ),
              child: Icon(Icons.send_rounded, size: 20, color: on ? g.onAgent : g.mutedText),
            ),
          ),
        ),
      ),
    );
  }
}
