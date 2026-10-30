import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/BoardData.dart';
import '../utils/StudentHistory.dart';
import 'GuideDialog.dart';
import 'GuideWait.dart';

/// The board card's drop-down: ONE LINE per MEANINGFUL thing that happened with this student, in SEVEN COLLAPSIBLE SECTIONS ([kHistoryCategories]: Interactions &
/// meetings, Surrender & targets, Sadhana, Books, Trips & services, Worries, Doubts), each header with its count and the date of its latest line. A tap on a
/// header opens it: its lines newest first (at most 30), GROUPED BY DAY under a small day heading. A tap on a line opens a dialog with the full details.
/// All are closed to begin with, except the first when it has lines. Updated live by the server, which never writes status re-checks or repeats.
class StudentHistoryList extends StatefulWidget {
  const StudentHistoryList({super.key, required this.studentUid});

  final String studentUid;

  @override
  State<StudentHistoryList> createState() => _StudentHistoryListState();
}

IconData historyIcon(String kind) => switch (kind) {
      kHistoryAdvice => Icons.lightbulb_outline_rounded,
      kHistoryInteraction => Icons.chat_bubble_outline_rounded,
      kHistoryNote => Icons.sticky_note_2_outlined,
      kHistorySadhana => Icons.show_chart_rounded,
      kHistorySurrender => Icons.flag_circle_outlined,
      _ => Icons.handshake_outlined,
    };

String historyKindLabel(String kind) => switch (kind) {
      kHistoryAdvice => 'AI advice',
      kHistoryInteraction => 'Interaction',
      kHistoryNote => 'Note',
      kHistorySadhana => 'Sadhana',
      kHistorySurrender => 'Surrender',
      _ => 'Dealing',
    };

/// The heading of a day group: "Today", "Yesterday", else "29 Oct" (with the year when it is not this one).
String historyDayHeading(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return historyDay(d, n);
}

/// "29 Oct" (and the year when it is not this one).
String historyDay(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateFormat(d.year == n.year ? 'd MMM' : 'd MMM yyyy').format(d);
}

class _StudentHistoryListState extends State<StudentHistoryList> {
  late final Stream<List<HistoryLine>> _stream = BoardData.instance.history(widget.studentUid);

  /// The sections the guide opened or closed himself; until he does, the first one is open when it has lines.
  final Map<String, bool> _open = {};

  @override
  Widget build(BuildContext context) {
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
            child: Text('Nothing yet. Interactions, doubts, meetings, books and notes about this student appear here.', style: t.caption),
          );
        }
        return Column(
          key: const ValueKey('history-list'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // (the stream gives the lines newest first; each section is sorted again so it never depends on that)
            for (final c in kHistoryCategories)
              _section(context, c.key, c.label, [for (final l in lines) if (l.category == c.key) l]..sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)))),
          ],
        );
      },
    );
  }

  /// One category: its header (name, count, date of the latest line) and, open, its lines.
  Widget _section(BuildContext context, String key, String label, List<HistoryLine> lines) {
    final g = context.g;
    final t = context.gText;
    final open = lines.isNotEmpty && (_open[key] ?? (key == kHistoryCategories.first.key));
    final latest = lines.isEmpty ? null : lines.first.at;
    final duration = GuideMotion.of(context, GuideMotion.expand);
    return Column(
      key: ValueKey('history-cat-$key'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: ValueKey('history-cat-header-$key'),
          behavior: HitTestBehavior.opaque,
          onTap: lines.isEmpty ? null : () => setState(() => _open[key] = !open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyStrong.copyWith(color: lines.isEmpty ? g.mutedText : null)),
                  ),
                  const SizedBox(width: 8),
                  Text('${lines.length}', key: ValueKey('history-cat-count-$key'), style: t.bodyStrong.copyWith(color: lines.isEmpty ? g.mutedText : g.brass)),
                  if (latest != null) ...[
                    const SizedBox(width: 8),
                    Text(historyDay(latest), key: ValueKey('history-cat-latest-$key'), style: t.caption),
                  ],
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: open ? .5 : 0,
                    duration: duration,
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: lines.isEmpty ? g.border : g.mutedText),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Column(
            key: ValueKey('history-cat-lines-$key'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i == 0 || !_sameDay(lines[i - 1].at, lines[i].at)) _dayHeading(context, lines[i].at),
                _line(context, lines[i]),
              ],
            ],
          ),
        Divider(height: 1, color: g.border),
      ],
    );
  }

  static bool _sameDay(DateTime? a, DateTime? b) => a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _dayHeading(BuildContext context, DateTime? at) {
    final g = context.g;
    final t = context.gText;
    return Padding(
      key: ValueKey('history-day-${at == null ? 'none' : '${at.year}-${at.month}-${at.day}'}'),
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(at == null ? 'Earlier' : historyDayHeading(at), style: t.caption.copyWith(color: g.mutedText, fontWeight: FontWeight.w700)),
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
