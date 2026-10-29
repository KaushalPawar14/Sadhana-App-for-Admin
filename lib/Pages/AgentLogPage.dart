import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../widgets/AiCostPanel.dart';
import '../widgets/AiText.dart';
import '../utils/AdminProfile.dart';
import '../utils/GuideDb.dart';
import '../utils/SeenMarkers.dart';
import '../utils/UnseenDot.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideWait.dart';

/// What the AI assistant has done, for HODs: who asked, what it proposed, what the guide decided,
/// and what came of it.
///
/// Read-only. The server writes every entry (the Admin SDK ignores rules); the security rules let only
/// a HOD read them and nobody write them, so what is shown here cannot be edited from any phone.
///
/// Only the latest [kAgentLogKeep] entries exist (the server deletes the oldest as new ones come in, all admins together).
///
/// NEW: an entry a Guide or Enabler made since THIS HOD last opened the log is marked "New" with an orange dot (the HOD's own
/// actions are never new to them). The marks clear when the HOD opens the log, per HOD (`seenMarkers/{hod}.assistantLog`); the dots
/// on the Tasks tab and the Assistant log card (see `UnseenAggregates.assistantLogUnseen`) clear with them.
class AgentLogPage extends StatefulWidget {
  const AgentLogPage({super.key, this.limit = kAgentLogKeep});

  final int limit;

  @override
  State<AgentLogPage> createState() => _AgentLogPageState();
}

/// How many entries the Assistant log keeps (the same number as `AUDIT_KEEP` on the server).
const int kAgentLogKeep = 50;

class _AgentLogPageState extends State<AgentLogPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _entries =
      GuideDb.instance.collection('agentActions').orderBy('createdMs', descending: true).limit(widget.limit).snapshots();

  String get _me => AdminProfileProvider.current?.id ?? '';

  /// The cost view's month (`yyyy-MM`) and the guide it is filtered to (null: everyone). The list below follows the same filter.
  String _month = istMonth(DateTime.now());
  String? _guide;

  /// When this HOD last opened the log, read BEFORE it is marked seen, so what was new until now can be shown as new.
  DateTime? _since;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    DateTime? since;
    if (_me.isNotEmpty) {
      try {
        final doc = await GuideDb.instance.collection('seenMarkers').doc(_me).get();
        final v = doc.data()?['assistantLog'];
        if (v is Timestamp) since = v.toDate();
      } catch (_) {/* a mark is a convenience: with none, everything from others counts as new */}
    }
    if (!mounted) return;
    setState(() {
      _since = since;
      _ready = true;
    });
    // Opening the log clears the dots (the marks stay on this screen until it closes)
    _markSeen();
  }

  void _markSeen() {
    if (_me.isEmpty) return;
    SeenMarkers.markSeen(_me, 'assistantLog').catchError((_) {});
  }

  @override
  void dispose() {
    // an entry that arrived while the log was open was seen here: it must not light the dots again
    _markSeen();
    super.dispose();
  }

  /// Made by a Guide or an Enabler (never a HOD) after this HOD last looked.
  bool _isNew(Map<String, dynamic> d) {
    if (!_ready) return false;
    if ((d['role'] ?? '').toString() == 'HOD') return false;
    final ms = d['createdMs'];
    if (ms is! num) return false;
    final since = _since;
    return since == null || ms.toInt() > since.millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return GuideScaffold(
      appBar: const GuideAppBar(title: Text('Assistant log')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _entries,
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(GuideSpace.pagePadding),
              child: Text("Couldn't load the log (${snap.error}).", key: const ValueKey('agent-log-error'), style: t.body),
            );
          }
          if (!snap.hasData) return const GuideWait();
          // the same month and guide as the cost view above
          final docs = snap.data!.docs.where((d) {
            final x = d.data();
            if (_guide != null && x['adminId'] != _guide) return false;
            final ms = x['createdMs'];
            return ms is! num || istMonth(DateTime.fromMillisecondsSinceEpoch(ms.toInt())) == _month;
          }).toList();
          final panel = AiCostPanel(month: _month, guide: _guide, onMonth: (m) => setState(() => _month = m), onGuide: (g) => setState(() => _guide = g));
          return ListView(
            padding: const EdgeInsets.all(GuideSpace.lg),
            children: [
              panel,
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: GuideSpace.pagePadding),
                  child: Text('Nothing yet. Every change the assistant proposes or makes will be listed here.', key: const ValueKey('agent-log-empty'), style: t.small),
                ),
              for (var i = 0; i < docs.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _LogCard(docs[i].data(), isNew: _isNew(docs[i].data())),
              ],
            ],
          );
        },
      ),
    );
  }
}

final DateFormat _stamp = DateFormat('d MMM yyyy, h:mm a');

class _LogCard extends StatelessWidget {
  const _LogCard(this.d, {this.isNew = false});

  /// Marked "New" with an orange dot (see [AgentLogPage]).
  final bool isNew;
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
              if (isNew) ...[
                const Padding(padding: EdgeInsets.only(top: 4), child: UnseenDot(key: ValueKey('agent-log-new-dot'))),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text('${d['adminName'] ?? d['adminId'] ?? '?'} (${_role((d['role'] ?? '').toString())})', style: t.cardTitleSmall)),
              const SizedBox(width: 8),
              if (isNew) ...[
                Container(
                  key: const ValueKey('agent-log-new'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: g.attention.withValues(alpha: .16), borderRadius: BorderRadius.circular(GuideShape.chipRadius)),
                  child: Text('New', style: t.pill.copyWith(color: g.attention, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
              ],
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
          if (d['costInr'] is num) Padding(padding: const EdgeInsets.only(top: 2), child: Text('AI cost ${inr(d['costInr'] as num)}', key: const ValueKey('agent-log-cost'), style: t.caption.copyWith(color: g.mutedText))),
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
                Expanded(child: AiText((a['title'] ?? a['tool'] ?? '').toString(), style: t.bodyStrong)),
              ],
            ),
            for (final l in (a['lines'] as List? ?? const []).whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 2),
                child: AiText('${l['label']}: ${l['value']}', style: t.small.copyWith(height: 1.35)),
              ),
            if (results[(a['callId'] ?? '').toString()]?['error'] case final String err when err.isNotEmpty)
              Padding(padding: const EdgeInsets.only(left: 2, top: 2), child: AiText(err, style: t.small.copyWith(color: g.danger))),
          ],
          if ((d['note'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            AiText((d['note']).toString(), style: t.caption),
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
