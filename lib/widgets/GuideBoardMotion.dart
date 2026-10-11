import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';

/// The column header drifts a few dp against the column while the row of columns
/// scrolls (README Part 7, "slight parallax on column headers"): the further the
/// column is from its resting place at the left, the further the header sits back.
/// It only repaints the header (a [Transform]); it never rebuilds the cards. None at
/// all with "reduce animations".
class GuideHeaderParallax extends StatelessWidget {
  const GuideHeaderParallax({
    super.key,
    required this.scroll,
    required this.columnWidth,
    required this.child,
  });

  final ScrollController? scroll;
  final double columnWidth;
  final Widget child;

  /// The most the header moves, in dp.
  static const double maxShift = 8;

  @override
  Widget build(BuildContext context) {
    final controller = scroll;
    if (controller == null || GuideMotion.reduced(context)) return child;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final box = context.findRenderObject();
        var shift = 0.0;
        if (box is RenderBox && box.attached && box.hasSize) {
          final x = box.localToGlobal(Offset.zero).dx;
          // 0 when the column rests at the left padding; -1..1 one column either side.
          final delta = ((x - GuideSpace.pagePadding) / columnWidth).clamp(-1.0, 1.0);
          shift = delta * maxShift;
        }
        return Transform.translate(offset: Offset(-shift, 0), child: child);
      },
    );
  }
}

/// The placeholder gap that opens at the end of a column while a card is dragged over
/// it: 60 dp (a card), 200 ms. Zero height otherwise, so a column is unchanged.
class GuideDropGap extends StatelessWidget {
  const GuideDropGap({super.key, required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final d = GuideMotion.of(context, const Duration(milliseconds: 200));
    final height = open ? GuideBoardTokens.cardHeight + 9 : 0.0;
    final gap = Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: g.brass.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: g.brass.withValues(alpha: .5)),
        ),
        child: const SizedBox(height: GuideBoardTokens.cardHeight, width: double.infinity),
      ),
    );
    if (d == Duration.zero) return open ? gap : const SizedBox.shrink();
    return ClipRect(
      child: AnimatedContainer(
        duration: d,
        curve: GuideMotion.out,
        height: height,
        child: OverflowBox(alignment: Alignment.topCenter, minHeight: 0, maxHeight: GuideBoardTokens.cardHeight + 9, child: gap),
      ),
    );
  }
}

/// A dropped card settles: it shrinks from the lifted 1.02 to 1.0 over 150 ms, once,
/// the first time it is built in its new column when [active]. [onSettled] clears the
/// "just dropped" marker.
class GuideSettle extends StatefulWidget {
  const GuideSettle({super.key, required this.active, required this.child, this.onSettled});

  final bool active;
  final Widget child;
  final VoidCallback? onSettled;

  @override
  State<GuideSettle> createState() => _GuideSettleState();
}

class _GuideSettleState extends State<GuideSettle> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!widget.active) return;
    if (GuideMotion.reduced(context)) {
      widget.onSettled?.call();
      return;
    }
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _controller = c
      ..forward().whenComplete(() {
        widget.onSettled?.call();
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
    if (c == null || c.isCompleted) return widget.child;
    return ScaleTransition(
      scale: Tween<double>(begin: 1.02, end: 1).animate(CurvedAnimation(parent: c, curve: GuideMotion.out)),
      child: widget.child,
    );
  }
}

/// The children of an expanded card fade in (200 ms) as the card opens.
class GuideFadeIn extends StatefulWidget {
  const GuideFadeIn({super.key, required this.child});

  final Widget child;

  @override
  State<GuideFadeIn> createState() => _GuideFadeInState();
}

class _GuideFadeInState extends State<GuideFadeIn> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (GuideMotion.reduced(context)) return;
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))
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
    if (c == null || c.isCompleted) return widget.child;
    return FadeTransition(opacity: CurvedAnimation(parent: c, curve: GuideMotion.out), child: widget.child);
  }
}
