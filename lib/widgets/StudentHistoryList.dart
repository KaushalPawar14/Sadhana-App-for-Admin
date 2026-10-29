import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/BoardData.dart';
import '../utils/StudentHistory.dart';
import 'GuideDialog.dart';
import 'GuideWait.dart';

/// The board card's drop-down: ONE LINE per thing that happened with this student, newest first, the last 30 (AI advice, interactions,
/// dealings, the guide's notes to the assistant, significant sadhana changes). A tap opens a dialog with the full details. Updated
/// live by the server.
class StudentHistoryList extends StatefulWidget {
  const StudentHistoryList({super.key, required this.studentUid, this.firstShown = 8});

  final String studentUid;

  /// How many lines show before "Show more".
  final int firstShown;

  @override
  State<StudentHistoryList> createState() => _StudentHistoryListState();
}

IconData historyIcon(String kind) => switch (kind) {
      kHistoryAdvice => Icons.lightbulb_outline_rounded,
      kHistoryInteraction => Icons.chat_bubble_outline_rounded,
      kHistoryNote => Icons.sticky_note_2_outlined,
      kHistorySadhana => Icons.show_chart_rounded,
      _ => Icons.handshake_outlined,
    };

String historyKindLabel(String kind) => switch (kind) {
      kHistoryAdvice => 'AI advice',
      kHistoryInteraction => 'Interaction',
      kHistoryNote => 'Note',
      kHistorySadhana => 'Sadhana',
      _ => 'Dealing',
    };

/// "29 Oct" (and the year when it is not this one).
String historyDay(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateFormat(d.year == n.year ? 'd MMM' : 'd MMM yyyy').format(d);
}

class _StudentHistoryListState extends State<StudentHistoryList> {
  late final Stream<List<HistoryLine>> _stream = BoardData.instance.history(widget.studentUid);
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return StreamBuilder<List<HistoryLine>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Text('Could not load the history.', style: t.caption);
        if (!snap.hasData) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: GuideWait(compact: true));
        final lines = snap.data!;
        if (lines.isEmpty) {
          return Padding(
            key: const ValueKey('history-empty'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Nothing yet. Advice, interactions, dealings and notes about him appear here.', style: t.caption),
          );
        }
        final shown = _all ? lines : lines.take(widget.firstShown).toList();
        final hidden = lines.length - shown.length;
        return Column(
          key: const ValueKey('history-list'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in shown) _line(context, l),
            if (hidden > 0)
              GestureDetector(
                key: const ValueKey('history-more'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _all = true),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
                  child: Align(alignment: Alignment.centerLeft, child: Text('Show $hidden more', style: t.bodyStrong.copyWith(color: g.brass))),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _line(BuildContext context, HistoryLine l) {
    final g = context.g;
    final t = context.gText;
    return GestureDetector(
      key: ValueKey('history-line-${l.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showStudentHistoryDetail(context, l),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(historyIcon(l.kind), size: 16, color: g.mutedText),
              const SizedBox(width: 8),
              Expanded(child: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body.copyWith(fontSize: 13))),
              if (l.at != null) ...[
                const SizedBox(width: 8),
                Text(historyDay(l.at!), style: t.caption),
              ],
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 16, color: g.mutedText),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dialog a tap opens: the kind and date, the line, and the full details.
Future<void> showStudentHistoryDetail(BuildContext context, HistoryLine l) => showDialog<void>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text(l.title, key: const ValueKey('history-dialog-title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${historyKindLabel(l.kind)}${l.at == null ? '' : ' · ${DateFormat('EEE d MMM yyyy, h:mm a').format(l.at!)}'}', style: dialogContext.gText.caption),
              const SizedBox(height: 10),
              Text(l.detail, key: const ValueKey('history-dialog-detail'), style: dialogContext.gText.body.copyWith(height: 1.4)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
