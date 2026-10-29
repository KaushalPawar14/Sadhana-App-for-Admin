import 'package:flutter/material.dart';

/// Three dots that rise and fall in turn - "the assistant is thinking", "turning your voice into text". Each dot is a third of a
/// cycle behind the one before, with a smooth rise and fall. Painted, not rebuilt: each frame only moves three circles, in a
/// layer of its own. With the phone's reduce-motion setting the dots simply stand still.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key, required this.colour, this.dot = 4});

  final Color colour;

  /// Radius of one dot.
  final double dot;

  @override
  State<ThinkingDots> createState() => ThinkingDotsState();
}

class ThinkingDotsState extends State<ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _running = false;

  /// Whether the dots are moving (false with reduce-motion).
  bool get moving => _running;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduce && !_running) {
      _running = true;
      _c.repeat();
    } else if (reduce && _running) {
      _running = false;
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.dot;
    return RepaintBoundary(
      child: CustomPaint(size: Size(r * 8.5, r * 4), painter: ThinkingDotsPainter(_c, widget.colour, r)),
    );
  }
}

class ThinkingDotsPainter extends CustomPainter {
  ThinkingDotsPainter(this.t, this.colour, this.r) : super(repaint: t);

  final Animation<double> t;
  final Color colour;
  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final phase = (t.value - i / 3) % 1.0;
      final wave = phase < .5 ? Curves.easeInOut.transform(phase * 2) : Curves.easeInOut.transform((1 - phase) * 2);
      canvas.drawCircle(
        Offset(r + i * r * 3.25, size.height / 2 + r * .5 - r * wave),
        r,
        Paint()..color = colour.withValues(alpha: .45 + .55 * wave),
      );
    }
  }

  @override
  bool shouldRepaint(ThinkingDotsPainter old) => old.colour != colour || old.r != r;
}
