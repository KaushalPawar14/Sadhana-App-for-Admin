import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';

/// A raised, "real" button for the actions on Today's topics (Record interaction, Update book, ...): a soft sky-blue gradient, a glossy highlight on the
/// top half, a solid darker edge under it and a soft shadow, and a PRESS-DOWN animation (the face moves down onto its edge, the shadow shrinks).
/// 48 dp high at least, the label in [GuideColors.onAgent] (at least 4.5:1 on every stop of the gradient, light and dark). Disabled: flat, muted.
///
/// It is only a control: what it opens is the caller's business, and it never ticks anything.
class Guide3dButton extends StatefulWidget {
  const Guide3dButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// How far the face sinks when pressed (dp).
  static const double sink = 3;

  @override
  State<Guide3dButton> createState() => _Guide3dButtonState();
}

class _Guide3dButtonState extends State<Guide3dButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null;

  void _set(bool v) {
    if (!_enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final reduce = GuideMotion.reduced(context);
    final pressed = _down && _enabled;
    final edge = Color.lerp(g.agentBottom, g.onAgent, .35)!;
    final fg = _enabled ? g.onAgent : g.mutedText;
    const radius = BorderRadius.all(Radius.circular(14));
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 90);
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? widget.onPressed : null,
          // the whole raised button, edge included, is the 48 dp+ target; the face moves, the layout never does
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: GuideShape.touchTarget, minWidth: GuideShape.touchTarget),
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 5),
              child: AnimatedContainer(
                key: const ValueKey('btn3d-face'),
                duration: duration,
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, pressed ? Guide3dButton.sink : 0, 0),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: _enabled ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [g.agentTop, g.agentMid, g.agentBottom]) : null,
                  color: _enabled ? null : g.chipBackground,
                  boxShadow: _enabled
                      ? [
                          // the solid edge under the face (the "thickness"), then a soft drop shadow: both shrink when pressed
                          BoxShadow(color: edge, offset: Offset(0, pressed ? 1 : Guide3dButton.sink + 1), blurRadius: 0),
                          BoxShadow(color: g.onAgent.withValues(alpha: pressed ? .14 : .30), offset: Offset(0, pressed ? 2 : 7), blurRadius: pressed ? 3 : 10),
                        ]
                      : const [],
                  border: Border.all(color: _enabled ? Colors.white.withValues(alpha: .55) : g.border, width: 1),
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    children: [
                      if (_enabled)
                        // the glossy highlight on the top half
                        Positioned(
                          key: const ValueKey('btn3d-gloss'),
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 22,
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: .55), Colors.white.withValues(alpha: 0)])),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.icon != null) ...[Icon(widget.icon, size: 18, color: fg), const SizedBox(width: 6)],
                            Flexible(child: Text(widget.label, textAlign: TextAlign.center, style: t.button.copyWith(color: fg, fontSize: 14, fontWeight: FontWeight.w700))),
                          ],
                        ),
                      ),
                    ],
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
