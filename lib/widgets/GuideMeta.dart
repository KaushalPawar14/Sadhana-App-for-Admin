import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'PressScale.dart';

/// A small status pill ("Counter-proposal", "Awaiting student", "Reviewed"): 11 px,
/// 600, on a soft tint of its own colour. It wraps its text rather than overflowing.
class GuideBadge extends StatelessWidget {
  const GuideBadge(this.label, {super.key, this.color, this.icon});

  final String label;

  /// Defaults to the muted text colour.
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final c = color ?? g.mutedText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(GuideShape.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: context.gText.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

/// An icon and a line of text (a date, a guide's name): the text wraps to a second
/// line before it ever overflows.
class GuideMeta extends StatelessWidget {
  const GuideMeta(this.text, {super.key, this.icon, this.color, this.maxLines = 2});

  final String text;
  final IconData? icon;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final c = color ?? g.mutedText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 6),
            child: Icon(icon, size: 14, color: c),
          ),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: context.gText.caption.copyWith(fontSize: 12, color: c),
          ),
        ),
      ],
    );
  }
}

/// Meta items side by side, flowing to the next line when the width or the text size
/// asks for it.
class GuideMetaWrap extends StatelessWidget {
  const GuideMetaWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: children);
}

/// A selectable pill (the language switch, a filter): a 1 px border, brass tint when
/// selected, a 48 dp touch target around a 38 dp pill, the label wraps.
class GuideChoiceChip extends StatelessWidget {
  const GuideChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  final String label;
  final bool selected;

  /// Null = disabled. Receives the new value (like ChoiceChip's).
  final ValueChanged<bool>? onSelected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final c = color ?? g.brass;
    final enabled = onSelected != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onSelected!(!selected) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: GuideShape.touchTarget, minWidth: GuideShape.touchTarget),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(minHeight: 38),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? c.withValues(alpha: .16) : g.chipBackground,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: selected ? c : g.border),
                ),
                // One Text.rich: the check mark and the label wrap together and can
                // never overflow a Row.
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (selected)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.check_rounded, size: 16, color: c),
                          ),
                        ),
                      TextSpan(text: label),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: t.buttonSecondary.copyWith(
                    fontSize: 13,
                    color: selected ? c : g.text,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
