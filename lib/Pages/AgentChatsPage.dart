import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../agent/AgentController.dart';
import '../agent/AgentTypes.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/Snackbar.dart';
import '../widgets/AiText.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideExpandable.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideWait.dart';

/// The assistant's CHAT HISTORY, compact, with two levels of drop-downs and nothing shown in full until it is opened.
///
///  * Level 1 — one collapsed card per session, newest first: when it was, a short title the AI made from the first request,
///    and what it did ("3 tasks · 2 successful · 1 failed"). Opening it lists that session's tasks and an "Open chat" button.
///  * Level 2 — inside a session, one collapsed row per TASK (an action the guide confirmed; a cancelled one is not a task):
///    a short title with a tick or a cross for how it went. Opening it shows the whole action: what was changed, who was
///    told, the result or the error.
///
/// "Open chat" shows that chat exactly as it looked, ready to continue (as long as its 20 questions are not used up).
///
/// Each admin sees only their own chats: the query asks for this admin's, and the security rules answer for nobody else's
/// (a HOD included — the HOD's view of what was done is the Assistant log). Nothing is ever deleted automatically.
/// The server writes the chats (`functions/agentChats.js`); this page only reads them.
class AgentChatsPage extends StatelessWidget {
  const AgentChatsPage({super.key, required this.controller});

  final AgentController controller;

  Future<void> _open(BuildContext context, String id) async {
    final navigator = Navigator.of(context);
    try {
      await controller.openChat(id);
      if (navigator.mounted) navigator.pop();
    } catch (e) {
      if (context.mounted) showSnackbar(context, agentFailureMessage(e), context.g.warning, Icons.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final mine = controller.env.me.id;
    return GuideScaffold(
      appBar: const GuideAppBar(title: Text('Chat history')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Only this admin's own chats; no ordering in the query, so no index is needed (newest first is done here).
        stream: controller.env.db.collection('agentChats').where('adminId', isEqualTo: mine).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(GuideSpace.pagePadding),
              child: Text("Couldn't load your chats. Check your connection and try again.", key: const ValueKey('agent-chats-error'), style: t.body),
            );
          }
          if (!snap.hasData) return const GuideWait();
          final chats = [for (final d in snap.data!.docs) (id: d.id, data: d.data())]
            ..sort((a, b) => _ms(b.data['updatedMs']).compareTo(_ms(a.data['updatedMs'])));
          if (chats.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(GuideSpace.pagePadding),
              child: Text('No chats yet. Your conversations with the assistant will be kept here.', key: const ValueKey('agent-chats-empty'), style: t.small),
            );
          }
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) => ListView.separated(
              key: const ValueKey('agent-chats-list'),
              padding: const EdgeInsets.all(GuideSpace.lg),
              itemCount: chats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _SessionCard(
                key: ValueKey('agent-chat-${chats[i].id}'),
                controller: controller,
                id: chats[i].id,
                data: chats[i].data,
                current: chats[i].id == controller.sessionId,
                onOpen: controller.busy ? null : () => _open(context, chats[i].id),
              ),
            ),
          );
        },
      ),
    );
  }

  static int _ms(Object? v) => v is num ? v.toInt() : 0;
}

final DateFormat _stamp = DateFormat('d MMM yyyy, h:mm a');

/// "3 tasks · 2 successful · 1 failed".
String chatCountsText(Map<String, dynamic> d) {
  int n(String k) => (d[k] as num?)?.toInt() ?? 0;
  final tasks = n('tasks');
  return '$tasks ${tasks == 1 ? 'task' : 'tasks'} · ${n('successful')} successful · ${n('failed')} failed';
}

/// One confirmed action of a session, as the guide saw it.
class ChatTask {
  const ChatTask({required this.key, required this.action, required this.ok, required this.result, required this.atMs});

  /// Unique within the session: the card's line number and the action's id.
  final String key;
  final AgentAction action;
  final bool ok;
  final String result;
  final int? atMs;

  /// "Request a meeting with a student — Arjun Kumar, Mon 26 Oct 2026": the action's title and its first short details.
  String get shortTitle {
    final details = <String>[];
    for (final l in action.lines) {
      final v = l.value.trim();
      if (v.isEmpty || v.length > 36 || v.contains('\n') || l.items.length > 3) continue;
      details.add(v);
      if (details.length == 2) break;
    }
    return details.isEmpty ? action.title : '${action.title} — ${details.join(', ')}';
  }
}

/// The tasks in a saved chat's lines: every action of a card the guide confirmed. A cancelled or unanswered card has none.
List<ChatTask> chatTasksOf(Iterable<Map<String, dynamic>> lines) {
  final tasks = <ChatTask>[];
  for (final m in lines) {
    if (m['kind'] != 'proposal' || m['state'] != 'done' || m['proposal'] is! Map) continue;
    final proposal = AgentProposal.fromMap(m['proposal'] as Map);
    final results = m['results'] is Map ? m['results'] as Map : const {};
    for (final a in proposal.actions) {
      final r = results[a.callId];
      if (r is! Map) continue;
      tasks.add(ChatTask(
        key: '${m['seq'] ?? tasks.length}-${a.callId}',
        action: a,
        ok: r['ok'] == true,
        result: (r['text'] ?? '').toString(),
        atMs: (m['atMs'] as num?)?.toInt(),
      ));
    }
  }
  return tasks;
}

/// Level 1: a session, collapsed. Its tasks are read only when it is opened.
class _SessionCard extends StatelessWidget {
  const _SessionCard({super.key, required this.controller, required this.id, required this.data, required this.current, required this.onOpen});

  final AgentController controller;
  final String id;
  final Map<String, dynamic> data;
  final bool current;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final ms = data['updatedMs'] ?? data['createdMs'];
    final when = ms is num ? _stamp.format(DateTime.fromMillisecondsSinceEpoch(ms.toInt())) : '';
    final title = (data['title'] ?? '').toString().trim();
    return GuideExpandableCard(
      headerMinHeight: 64,
      headerPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      title: Text(title.isEmpty ? 'New chat' : title, key: ValueKey('agent-chat-title-$id')),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(when, style: t.caption),
          const SizedBox(height: 2),
          Text(chatCountsText(data), key: ValueKey('agent-chat-counts-$id'), style: t.small),
        ],
      ),
      trailing: current
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: g.agent.withValues(alpha: .12), borderRadius: BorderRadius.circular(GuideShape.chipRadius)),
              child: Text('Open now', style: t.pill.copyWith(color: g.agent)),
            )
          : null,
      body: _SessionBody(controller: controller, id: id, data: data, onOpen: onOpen),
    );
  }
}

class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.controller, required this.id, required this.data, required this.onOpen});

  final AgentController controller;
  final String id;
  final Map<String, dynamic> data;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final questions = (data['questions'] as num?)?.toInt() ?? 0;
    final limit = (data['questionLimit'] as num?)?.toInt() ?? AgentController.defaultQuestionLimit;
    final left = (limit - questions).clamp(0, limit);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: controller.env.db.collection('agentChats').doc(id).collection('entries').orderBy('seq').get(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text("Couldn't load this chat's tasks.", key: ValueKey('agent-chat-error-$id'), style: t.small.copyWith(color: g.danger));
              }
              if (!snap.hasData) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Center(child: SizedBox(width: 18, height: 18, child: GuideBusyDot())));
              }
              final tasks = chatTasksOf([for (final d in snap.data!.docs) d.data()]);
              if (tasks.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('No tasks in this chat — only questions and answers.', key: ValueKey('agent-chat-no-tasks-$id'), style: t.small),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final task in tasks) Padding(padding: const EdgeInsets.only(bottom: 8), child: _TaskRow(sessionId: id, task: task)),
                ],
              );
            },
          ),
          const SizedBox(height: 2),
          Text(
            left == 0 ? 'Full — start a New chat to ask more' : '$left ${left == 1 ? 'question' : 'questions'} left',
            style: t.caption,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              key: ValueKey('agent-chat-open-$id'),
              onPressed: onOpen,
              icon: Icon(Icons.chat_bubble_outline, size: 18, color: onOpen == null ? g.mutedText : g.agent),
              label: Text('Open chat', style: TextStyle(color: onOpen == null ? g.mutedText : g.agent)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: onOpen == null ? g.border : g.agent)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Level 2: one task, collapsed: a short title and a tick or a cross. Opened, it shows the whole action.
class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.sessionId, required this.task});

  final String sessionId;
  final ChatTask task;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final a = task.action;
    final colour = task.ok ? g.success : g.danger;
    return GuideExpandableCard(
      key: ValueKey('agent-task-$sessionId-${task.key}'),
      radius: GuideShape.inputRadius,
      headerMinHeight: 44,
      headerPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      titleStyle: t.small.copyWith(fontWeight: FontWeight.w600, height: 1.3),
      leading: Icon(task.ok ? Icons.check_circle : Icons.cancel, key: ValueKey('agent-task-status-${task.ok ? 'ok' : 'failed'}'), size: 20, color: colour),
      title: Text(task.shortTitle),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What was changed', style: t.caption.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(a.title, style: t.small.copyWith(fontWeight: FontWeight.w600)),
            for (final l in a.lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.label, style: t.caption),
                    AiText(l.items.length > 3 ? l.items.join(', ') : l.value, style: t.small.copyWith(height: 1.35)),
                  ],
                ),
              ),
            if (a.notifies.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Who was told', style: t.caption.copyWith(fontWeight: FontWeight.w700)),
              for (final n in a.notifies)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notifications_none, size: 15, color: g.mutedText),
                      const SizedBox(width: 6),
                      Expanded(child: Text(n, style: t.small.copyWith(height: 1.35))),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(task.ok ? 'Result' : 'Error', style: t.caption.copyWith(fontWeight: FontWeight.w700, color: task.ok ? null : g.danger)),
            const SizedBox(height: 2),
            AiText(
              task.result.isEmpty ? (task.ok ? 'Done.' : 'That did not work.') : task.result,
              key: ValueKey('agent-task-result-$sessionId-${task.key}'),
              style: t.small.copyWith(color: colour, height: 1.35),
            ),
            if (task.atMs != null) ...[
              const SizedBox(height: 6),
              Text(_stamp.format(DateTime.fromMillisecondsSinceEpoch(task.atMs!)), style: t.caption),
            ],
          ],
        ),
      ),
    );
  }
}
