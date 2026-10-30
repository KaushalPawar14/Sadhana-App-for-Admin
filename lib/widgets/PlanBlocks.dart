import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';

/// The shared look of Today and This week: BLOCKS (an icon, a name, "done/total", a circular check, a tap to collapse / expand) separated by a
/// divider, with TO-DO ROWS and small coloured TOPIC CHIPS inside. Nothing here is a control that ticks: the circle is a picture.

/// One block: a header (tap = collapse / expand) and, when open, its rows or [emptyText].
class PlanBlock extends StatelessWidget {
  const PlanBlock({
    super.key,
    required this.id,
    required this.icon,
    required this.title,
    required this.open,
    required this.onToggle,
    required this.children,
    this.done,
    this.total,
    this.emptyText = 'Nothing here today',
    this.showCheck = true,
  });

  /// The key suffix: `plan-section-<id>` (the header), `plan-section-body-<id>`, `plan-section-check-<id>`, `plan-section-count-<id>`.
  final String id;
  final IconData icon;
  final String title;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  /// The count shown as "done/total"; with only [total] (no [done]) just the number.
  final int? done;
  final int? total;
  final String emptyText;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final all = done != null && total != null && total! > 0 && done == total;
    final count = total == null ? null : (done == null ? '$total' : '$done/$total');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: g.chipBackground.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(GuideShape.cardRadius),
          child: InkWell(
            key: ValueKey('plan-section-$id'),
            borderRadius: BorderRadius.circular(GuideShape.cardRadius),
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(icon, size: 22, color: g.agent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(title, style: t.cardTitleSmall.copyWith(fontWeight: FontWeight.w800, letterSpacing: .2))),
                    if (count != null) Text(count, key: ValueKey('plan-section-count-$id'), style: t.bodyStrong.copyWith(color: g.agent)),
                    if (showCheck) ...[const SizedBox(width: 10), planCircle(context, all, key: ValueKey('plan-section-check-$id'))],
                    const SizedBox(width: 6),
                    Icon(open ? Icons.expand_less : Icons.expand_more, color: g.mutedText),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  key: ValueKey('plan-section-body-$id'),
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children.isEmpty
                        ? [Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 8), child: Text(emptyText, key: ValueKey('plan-section-empty-$id'), style: t.small.copyWith(color: g.mutedText)))]
                        : children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// The divider between two blocks.
class PlanBlockDivider extends StatelessWidget {
  const PlanBlockDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Divider(height: 2, thickness: 1.5, color: context.g.border),
      );
}

/// The circular check: a picture (filled and ticked when done), never a control. The [key] sits on the icon itself.
Widget planCircle(BuildContext context, bool done, {Key? key, double size = 24}) {
  final g = context.g;
  return Semantics(
    label: done ? 'Done' : 'Not done yet',
    child: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, key: key, size: size, color: done ? g.success : g.mutedText),
  );
}

/// The colour of a topic's chip, by what the topic is about.
Color planChipColor(GuideColors g, String kind) {
  switch (kind) {
    case 'concern':
      return g.danger;
    case 'doubt':
      return g.agent;
    case 'bookDue':
    case 'target_books':
      return g.warning;
    case 'meeting':
    case 'meeting_request':
      return g.eventMeeting;
    case 'target_chanting':
    case 'target_folk':
    case 'target_task':
      return g.eventTarget;
    case 'surrender':
    case 'good_sadhana':
      return g.eventFollowUp;
    case 'sadhana_slip':
    case 'reporting_habit':
    case 'discipline_habit':
      return g.attention;
    default:
      return g.mutedText;
  }
}

/// A small coloured chip: what a task contains ("Book due", "Worry", "Doubt", "Chanting target", "Meeting" ...). Done: struck through and dimmed.
class PlanChip extends StatelessWidget {
  const PlanChip({super.key, required this.label, required this.color, this.done = false});

  final String label;
  final Color color;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: done ? .08 : .16),
        borderRadius: BorderRadius.circular(GuideShape.chipRadius),
        border: Border.all(color: color.withValues(alpha: done ? .35 : .75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done) ...[Icon(Icons.check_rounded, size: 12, color: g.success), const SizedBox(width: 2)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.pill.copyWith(color: done ? g.mutedText : g.text, decoration: done ? TextDecoration.lineThrough : null),
            ),
          ),
        ],
      ),
    );
  }
}
