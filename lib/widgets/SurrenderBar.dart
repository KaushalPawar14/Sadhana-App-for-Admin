import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/BoardData.dart';
import '../utils/SurrenderData.dart';
import 'GuideDialog.dart';
import 'GuideTiles.dart';

/// The board card's "Surrender %": a progress bar with the number and the change since last week (↑ / ↓). A tap opens the breakdown: each
/// part with its reason. GUIDES AND HODs ONLY — the number is never shown to a student (this app is the guides'; the student app never
/// reads it). A part with nothing to judge says "not enough data"; it is never counted as a failure.
class SurrenderBar extends StatefulWidget {
  const SurrenderBar({super.key, required this.studentUid, required this.studentName});

  final String studentUid;
  final String studentName;

  @override
  State<SurrenderBar> createState() => _SurrenderBarState();
}

class _SurrenderBarState extends State<SurrenderBar> {
  late final Stream<SurrenderInfo?> _stream = BoardData.instance.surrender(widget.studentUid);

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return StreamBuilder<SurrenderInfo?>(
      stream: _stream,
      builder: (context, snap) {
        final info = snap.data;
        if (info == null) {
          return Padding(
            key: const ValueKey('surrender-none'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Surrender %: not enough data yet.', style: t.caption),
          );
        }
        return GestureDetector(
          key: const ValueKey('surrender-bar'),
          behavior: HitTestBehavior.opaque,
          onTap: () => showSurrenderBreakdown(context, widget.studentName, info),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text('Surrender', style: t.bodyStrong),
                      Text('${info.percent}%', key: const ValueKey('surrender-percent'), style: t.bodyStrong.copyWith(color: g.brass)),
                      if (info.trend != null && info.trend != 0)
                        Text(
                          '${info.trend! > 0 ? '↑' : '↓'} ${info.trend!.abs()} vs last week',
                          key: const ValueKey('surrender-trend'),
                          style: t.caption.copyWith(color: info.trend! > 0 ? g.success : g.warning),
                        ),
                      Text(info.stage, style: t.caption),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GuideProgressBar(value: info.percent / 100, height: 8),
                  const SizedBox(height: 2),
                  Text('Tap for the breakdown', style: t.caption),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The breakdown: each part (its weight, how it scored) with the reason, the trend, and the residence / data limits.
Future<void> showSurrenderBreakdown(BuildContext context, String name, SurrenderInfo info) => showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final g = dialogContext.g;
        final t = dialogContext.gText;
        return GuideDialog(
          title: Text('${name.split(' ').first}: Surrender ${info.percent}%', key: const ValueKey('surrender-dialog-title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${info.stage}${info.trend == null ? '' : info.trend == 0 ? ' · the same as last week' : ' · ${info.trend! > 0 ? '↑ up' : '↓ down'} ${info.trend!.abs()} since last week'}',
                  style: t.caption,
                ),
                const SizedBox(height: 10),
                for (final p in info.parts)
                  Padding(
                    key: ValueKey('surrender-part-${p.key}'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            Text(p.label, style: t.bodyStrong),
                            Text(p.score == null ? 'not enough data' : '${(p.score! * 100).round()}%', style: t.bodyStrong.copyWith(color: p.score == null ? g.mutedText : g.brass)),
                            Text('${p.weight}% of the total', style: t.caption),
                          ],
                        ),
                        if (p.score != null) ...[
                          const SizedBox(height: 4),
                          GuideProgressBar(value: p.score!, height: 5),
                        ],
                        const SizedBox(height: 4),
                        Text(p.reason, style: t.body.copyWith(fontSize: 13, height: 1.35)),
                      ],
                    ),
                  ),
                if (info.cap == 'residence')
                  Text('He does not live in FOLK, so the most he can show is 90%. Staying in FOLK, with everything else strong, allows 95% and more.', key: const ValueKey('surrender-cap'), style: t.caption),
                if (info.cap == 'incomplete')
                  Text('Not everything is known yet, so the most it can show is 95% until every part has something to judge.', key: const ValueKey('surrender-cap'), style: t.caption),
                const SizedBox(height: 8),
                Text('For you and the HOD only: the student never sees this.', style: t.caption),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
        );
      },
    );
