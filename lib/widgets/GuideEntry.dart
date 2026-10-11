import 'package:flutter/material.dart';

import '../theme/GuideTokens.dart';

/// Screen entry (README Part 7): the child fades in and rises [GuideMotion.entryOffset]
/// dp over ~300 ms, delayed by 50 ms per [index] (the delay stops growing after
/// [maxStagger] items so a long list does not wait). It plays once, when first built;
/// a rebuild with new data never replays it. With "reduce animations" it is the plain
/// child, and its controller (the only ticker) is gone as soon as it finishes.
class GuideEntry extends StatefulWidget {
  const GuideEntry({super.key, required this.child, this.index = 0, this.maxStagger = 8});

  final Widget child;
  final int index;
  final int maxStagger;

  @override
  State<GuideEntry> createState() => _GuideEntryState();
}

class _GuideEntryState extends State<GuideEntry> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Animation<double> _curve;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (GuideMotion.reduced(context)) return;
    final delay = GuideMotion.entryStagger * (widget.index.clamp(0, widget.maxStagger));
    final total = GuideMotion.entry + delay;
    final c = AnimationController(vsync: this, duration: total);
    _curve = CurvedAnimation(
      parent: c,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: GuideMotion.out),
    );
    _controller = c..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // The child keeps the same place in the tree for its whole life (a finished
  // animation is simply "fully visible, no offset"): swapping the wrapper away when
  // it ends would remount the child, and re-subscribe every stream inside it.
  @override
  Widget build(BuildContext context) {
    if (_controller == null) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final v = _curve.value;
        return FadeTransition(
          opacity: _curve,
          child: Transform.translate(offset: Offset(0, (1 - v) * GuideMotion.entryOffset), child: child),
        );
      },
    );
  }
}

/// A hero number that counts up from 0 the first time it appears (about 600 ms) and
/// never again: a live update replaces it at once. Text that is not a whole number
/// (or has a suffix like "/30") counts its leading integer and keeps the rest.
class GuideCountUp extends StatefulWidget {
  const GuideCountUp(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<GuideCountUp> createState() => _GuideCountUpState();
}

class _GuideCountUpState extends State<GuideCountUp> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _decided = false;

  static final RegExp _lead = RegExp(r'^(\d+)(.*)$');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final m = _lead.firstMatch(widget.text);
    if (m == null || GuideMotion.reduced(context)) return;
    final end = int.tryParse(m.group(1)!) ?? 0;
    if (end == 0) return;
    final c = AnimationController(vsync: this, duration: GuideMotion.countUp);
    _controller = c
      ..forward().whenComplete(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final m = _lead.firstMatch(widget.text);
    if (c == null || c.isCompleted || m == null) {
      return Text(widget.text, style: widget.style, textAlign: widget.textAlign);
    }
    final end = int.parse(m.group(1)!);
    final rest = m.group(2)!;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final v = GuideMotion.out.transform(c.value);
        // The widest the number gets is its final text, so the layout never moves:
        // the digits are tabular and the box is as wide as the final value.
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Text(widget.text, style: widget.style, textAlign: widget.textAlign),
            ),
            Text('${(end * v).round()}$rest', style: widget.style, textAlign: widget.textAlign),
          ],
        );
      },
    );
  }
}
