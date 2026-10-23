import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideWait.dart';

/// What the AI assistant has done, for HODs: who asked, what it proposed, what the guide decided,
/// and what came of it.
///
/// Read-only. The server writes every entry (the Admin SDK ignores rules); the security rules let only
/// a HOD read them and nobody write them, so what is shown here cannot be edited from any phone.
class AgentLogPage extends StatelessWidget {
  const AgentLogPage({super.key, this.limit = 100});

  final int limit;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return GuideScaffold(
      appBar: const GuideAppBar(title: Text('Assistant log')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: GuideDb.instance.collection('agentActions').orderBy('createdMs', descending: true).limit(limit).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(GuideSpace.pagePadding),
              child: Text("Couldn't load the log (${snap.error}).", key: const ValueKey('agent-log-error'), style: t.body),
            );
          }
          if (!snap.hasData) return const GuideWait();
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(GuideSpace.pagePadding),
              child: Text('Nothing yet. Every change the assistant proposes or makes will be listed here.', key: const ValueKey('agent-log-empty'), style: t.small),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(GuideSpace.lg),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _LogCard(docs[i].data()),
          );
        },
      ),
    );
  }
}

final DateFormat _stamp = DateFormat('d MMM yyyy, h:mm a');

class _LogCard extends StatelessWidget {
  const _LogCard(this.d);
  final Map<String, dynamic> d;

  static String _words(String status) => switch (status) {
        'proposed' => 'Waiting / not answered',
        'executed' => 'Done',
        'partial' => 'Partly done',
        'failed' => 'Failed',
        'cancelled' => 'Cancelled by the guide',
        'abandoned' => 'Abandoned',
        'denied' => 'Refused: not allowed',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final status = (d['status'] ?? '').toString();
    final colour = switch (status) {
      'executed' => g.success,
      'failed' || 'denied' => g.danger,
      'partial' => g.warning,
      _ => g.mutedText,
    };
    final ms = d['createdMs'];
    final when = ms is num ? _stamp.format(DateTime.fromMillisecondsSinceEpoch(ms.toInt())) : '';
    final actions = (d['actions'] as List? ?? const []).whereType<Map>().toList();
    final results = {for (final r in (d['results'] as List? ?? const []).whereType<Map>()) (r['callId'] ?? '').toString(): r};

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: g.surface,
        borderRadius: BorderRadius.circular(GuideShape.cardRadius),
        border: Border.all(color: g.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('${d['adminName'] ?? d['adminId'] ?? '?'} (${_role((d['role'] ?? '').toString())})', style: t.cardTitleSmall)),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: colour.withValues(alpha: .14), borderRadius: BorderRadius.circular(GuideShape.chipRadius)),
                  child: Text(_words(status), style: t.pill.copyWith(color: colour)),
                ),
              ),
            ],
          ),
          if (when.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(when, style: t.caption)),
          if ((d['request'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Asked: "${d['request']}"', style: t.small.copyWith(color: g.text, height: 1.4)),
          ],
          if (d['tainted'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text("Prepared after reading students' own words.", style: t.caption.copyWith(color: g.warning)),
            ),
          if (d['unconfirmedDelete'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('A deletion was reported without both confirmations.', style: t.caption.copyWith(color: g.danger)),
            ),
          for (final a in actions) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (results[(a['callId'] ?? '').toString()] case final r?) ...[
                  Icon(r['ok'] == true ? Icons.check_circle : Icons.cancel, size: 16, color: r['ok'] == true ? g.success : g.danger),
                  const SizedBox(width: 6),
                ],
                Expanded(child: Text((a['title'] ?? a['tool'] ?? '').toString(), style: t.bodyStrong)),
              ],
            ),
            for (final l in (a['lines'] as List? ?? const []).whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 2),
                child: Text('${l['label']}: ${l['value']}', style: t.small.copyWith(height: 1.35)),
              ),
            if (results[(a['callId'] ?? '').toString()]?['error'] case final String err when err.isNotEmpty)
              Padding(padding: const EdgeInsets.only(left: 2, top: 2), child: Text(err, style: t.small.copyWith(color: g.danger))),
          ],
          if ((d['note'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text((d['note']).toString(), style: t.caption),
          ],
        ],
      ),
    );
  }

  static String _role(String wire) => switch (wire) {
        'HOD' => 'HOD',
        'GUIDE' => 'Guide',
        'MALE_ENABLER' => 'Male Enabler',
        'FEMALE_ENABLER' => 'Female Enabler',
        _ => wire,
      };
}
