import 'package:flutter/material.dart';

import '../theme/GuideTokens.dart';

/// Press feedback for every Guide component: scales to 0.97 over ~130 ms while a
/// pointer is down. It only watches pointers, so it never steals a tap from the
/// child. No scale at all when "reduce animations" is on.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (!widget.enabled || _pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final animate = !GuideMotion.reduced(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: animate && _pressed && widget.enabled ? GuideMotion.pressScale : 1,
        duration: GuideMotion.press,
        curve: GuideMotion.out,
        child: widget.child,
      ),
    );
  }
}
