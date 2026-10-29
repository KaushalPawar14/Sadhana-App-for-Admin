import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../agent/AgentController.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/Snackbar.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideWait.dart';

/// The assistant's CHAT HISTORY: one card per session, newest first — when it was, a short title the AI made from the
/// first request, and what it did ("3 tasks · 2 successful · 1 failed"). Tapping a card opens that chat exactly as it
/// looked, ready to continue (as long as its 20 questions are not used up).
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
              itemBuilder: (context, i) => _ChatCard(
                id: chats[i].id,
                data: chats[i].data,
                current: chats[i].id == controller.sessionId,
                onTap: controller.busy ? null : () => _open(context, chats[i].id),
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

class _ChatCard extends StatelessWidget {
  const _ChatCard({required this.id, required this.data, required this.current, required this.onTap});

  final String id;
  final Map<String, dynamic> data;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final ms = data['updatedMs'] ?? data['createdMs'];
    final when = ms is num ? _stamp.format(DateTime.fromMillisecondsSinceEpoch(ms.toInt())) : '';
    final title = (data['title'] ?? '').toString().trim();
    final questions = (data['questions'] as num?)?.toInt() ?? 0;
    final limit = (data['questionLimit'] as num?)?.toInt() ?? AgentController.defaultQuestionLimit;
    final left = (limit - questions).clamp(0, limit);
    return Material(
      color: g.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GuideShape.cardRadius),
        side: BorderSide(color: current ? g.agent : g.border, width: current ? 1.4 : 1),
      ),
      child: InkWell(
        key: ValueKey('agent-chat-$id'),
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GuideShape.cardRadius)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(when, style: t.caption)),
                  if (current)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: g.agent.withValues(alpha: .12), borderRadius: BorderRadius.circular(GuideShape.chipRadius)),
                      child: Text('Open now', style: t.pill.copyWith(color: g.agent)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(title.isEmpty ? 'New chat' : title, style: t.cardTitleSmall),
              const SizedBox(height: 6),
              Text(chatCountsText(data), key: ValueKey('agent-chat-counts-$id'), style: t.small),
              const SizedBox(height: 2),
              Text(
                left == 0 ? 'Full — start a New chat to ask more' : '$left ${left == 1 ? 'question' : 'questions'} left',
                style: t.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
