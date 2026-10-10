import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'PressScale.dart';

/// The brass primary button: fully rounded, brass gradient, soft brass glow.
/// 50 dp tall at least (46-54 in the design); it grows with the label.
class GuidePrimaryButton extends StatelessWidget {
  const GuidePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  /// Full width (default) or as wide as its label.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final enabled = onPressed != null && !loading;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: g.onPrimary),
          )
        else if (icon != null)
          Icon(icon, size: 20, color: g.onPrimary),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              textAlign: TextAlign.center, style: t.button.copyWith(color: g.onPrimary)),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: GuideShape.primaryButtonHeight),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              gradient: enabled ? g.primaryGradient : null,
              color: enabled ? null : g.chipBackground,
              borderRadius: BorderRadius.circular(999),
              boxShadow: enabled
                  ? [BoxShadow(color: g.brassGlow, blurRadius: 24, offset: const Offset(0, 12))]
                  : null,
            ),
            child: enabled
                ? content
                : DefaultTextStyle.merge(
                    style: TextStyle(color: g.mutedText), child: content),
          ),
        ),
      ),
    );
  }
}

/// The outlined secondary button: fully rounded, 1 px border, transparent.
/// 42 dp tall at least.
class GuideSecondaryButton extends StatelessWidget {
  const GuideSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(
                minHeight: GuideShape.secondaryButtonHeight,
                // The touch target is 48 dp even though the pill is 42.
                minWidth: GuideShape.touchTarget),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: g.border),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: enabled ? g.text : g.mutedText),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: t.buttonSecondary
                          .copyWith(color: enabled ? g.text : g.mutedText)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
