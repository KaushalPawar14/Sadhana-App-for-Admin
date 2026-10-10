import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideSurface.dart';

/// An accordion card: a header row (leading, title, subtitle, trailing, chevron)
/// that expands inline to show [body] with a smooth height animation (250 ms),
/// the chevron rotating. The header is at least 48 dp tall and grows with text.
///
/// Controlled when [expanded] is given (the board keeps one card open per
/// column); otherwise it keeps its own state starting at [initiallyExpanded].
class GuideExpandableCard extends StatefulWidget {
  const GuideExpandableCard({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.leading,
    this.trailing,
    this.expanded,
    this.initiallyExpanded = false,
    this.onChanged,
    this.headerMinHeight = 56,
    this.radius = GuideShape.cardRadius,
    this.titleStyle,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget body;
  final bool? expanded;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onChanged;
  final double headerMinHeight;
  final double radius;
  final TextStyle? titleStyle;
  final EdgeInsetsGeometry headerPadding;

  @override
  State<GuideExpandableCard> createState() => _GuideExpandableCardState();
}

class _GuideExpandableCardState extends State<GuideExpandableCard> {
  late bool _open = widget.initiallyExpanded;

  bool get _isOpen => widget.expanded ?? _open;

  void _toggle() {
    final next = !_isOpen;
    if (widget.expanded == null) setState(() => _open = next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final duration = GuideMotion.of(context, GuideMotion.expand);
    final open = _isOpen;
    return GuideCard(
      radius: widget.radius,
      clip: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: _toggle,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: widget.headerMinHeight),
                child: Padding(
                  padding: widget.headerPadding,
                  child: Row(
                    children: [
                      if (widget.leading != null) ...[
                        widget.leading!,
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DefaultTextStyle.merge(
                              style: widget.titleStyle ?? context.gText.cardTitleSmall,
                              child: widget.title,
                            ),
                            if (widget.subtitle != null) ...[
                              const SizedBox(height: 3),
                              widget.subtitle!,
                            ],
                          ],
                        ),
                      ),
                      if (widget.trailing != null) ...[
                        const SizedBox(width: 8),
                        widget.trailing!,
                      ],
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: open ? .5 : 0,
                        duration: duration,
                        curve: GuideMotion.standard,
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            size: 22, color: g.mutedText),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          GuideAnimatedSize(
            duration: duration,
            child: open
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(height: 1, thickness: 1, color: g.border, indent: 12, endIndent: 12),
                      widget.body,
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
