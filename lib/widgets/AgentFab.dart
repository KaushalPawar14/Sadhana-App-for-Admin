import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/AgentLook.dart';
import '../theme/GuideTheme.dart';

/// The assistant's floating button: a glossy 3D sky-blue ball.
///
/// Layers, bottom to top: a drop shadow and a soft sky-blue glow; the sky-blue gradient (pale at the top, clear blue at the bottom); an
/// inner shade that darkens the lower edge; a bright rim along the top; a glossy highlight over the upper half; the icon. Pressed,
/// it sinks: it shrinks a little, moves down a touch and its shadow tightens, as a real button would.
///
/// A light SHINE sweeps across it every [kAgentShineEvery] (5.5 s): a soft diagonal band, smooth and subtle, repeating. It
/// PAUSES when the app is in the background or the button is hidden (no ticker runs, so no battery is used), and with the
/// phone's reduce-motion setting there is no sweep at all: the button is static.
class AgentFab extends StatefulWidget {
  const AgentFab({super.key, required this.size, this.pressed = false});

  final double size;

  /// Held down: the button sinks.
  final bool pressed;

  @override
  State<AgentFab> createState() => AgentFabState();
}

/// How often the shine sweeps, from the start of one sweep to the start of the next.
const Duration kAgentShineEvery = Duration(milliseconds: 5500);

/// How long one sweep takes. Between sweeps nothing runs at all (a timer waits), so the resting button costs no frames.
const Duration kAgentShineSweep = Duration(milliseconds: 1100);

class AgentFabState extends State<AgentFab> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _shine;
  Timer? _next;
  bool _foreground = true;
  bool _reduce = false;
  bool _tickerOn = true;
  bool _cycling = false;

  /// Whether the shine cycle is on (a sweep is running or the next one is waiting). False when the button is hidden, the app
  /// is in the background, or the phone asks for reduced motion: then nothing runs.
  bool get shining => _cycling;

  /// Whether a sweep is crossing the button this very moment.
  bool get sweeping => _shine.isAnimating;

  @override
  void initState() {
    super.initState();
    _shine = AnimationController(vsync: this, duration: kAgentShineSweep);
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _tickerOn = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  /// Runs the shine only while it can be seen: foreground, not hidden (TickerMode), and animations allowed.
  void _sync() {
    final should = _foreground && !_reduce && _tickerOn;
    if (should && !_cycling) {
      _cycling = true;
      _wait(const Duration(milliseconds: 1400));
    } else if (!should && _cycling) {
      _cycling = false;
      _next?.cancel();
      _next = null;
      _shine.stop();
      _shine.value = 0;
    }
    if (mounted) setState(() {});
  }

  /// Rests, then sweeps once, then rests again.
  void _wait(Duration delay) {
    _next?.cancel();
    _next = Timer(delay, () {
      if (!mounted || !_cycling) return;
      _shine.forward(from: 0).whenComplete(() {
        if (!mounted || !_cycling) return;
        _wait(kAgentShineEvery - kAgentShineSweep);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _next?.cancel();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final s = widget.size;
    final pressed = widget.pressed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      width: s,
      height: s,
      transform: Matrix4.identity()
        ..translateByDouble(0, pressed ? 2.5 : 0, 0, 1)
        ..scaleByDouble(pressed ? .94 : 1, pressed ? .94 : 1, 1, 1),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: pressed
            ? [
                BoxShadow(color: g.agentShade(g.isDark ? .55 : .28), blurRadius: 4, offset: const Offset(0, 1.5)),
              ]
            : g.agentGlow,
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // everything that does not move is drawn once and cached; only the shine layer repaints
            RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
              // the sky-blue body
              DecoratedBox(decoration: BoxDecoration(gradient: g.agentGradient)),
              // inner shade: the lower edge falls away
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -.35),
                    radius: .95,
                    colors: [Colors.transparent, Colors.transparent, g.agentBottom.withValues(alpha: .0), g.agentShade(.28)],
                    stops: const [0, .55, .7, 1],
                  ),
                ),
              ),
              // the bright rim along the top, a dark one underneath
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: GradientBoxBorder(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withValues(alpha: .75), Colors.white.withValues(alpha: .0), g.agentShade(.22)],
                      stops: const [0, .5, 1],
                    ),
                    width: 1.6,
                  ),
                ),
              ),
              // the glossy highlight over the upper half
              Align(
                alignment: const Alignment(0, -.62),
                child: FractionallySizedBox(
                  widthFactor: .66,
                  heightFactor: .44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.elliptical(s * .33, s * .22)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white.withValues(alpha: .62), Colors.white.withValues(alpha: .04)],
                      ),
                    ),
                  ),
                ),
              ),
              // the icon, with a touch of depth
              Center(
                child: Icon(
                  Icons.auto_awesome,
                  size: s * .46,
                  color: g.onAgent,
                  shadows: [Shadow(color: Colors.white.withValues(alpha: .55), blurRadius: 0, offset: const Offset(0, 1))],
                ),
              ),
                ],
              ),
            ),
            // the shine that sweeps across, on a layer of its own (not built at all while it is not running)
            if (_cycling)
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _ShinePainter(_shine)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A one-colour-stop border drawn with a gradient (a circle's rim).
class GradientBoxBorder extends BoxBorder {
  const GradientBoxBorder({required this.gradient, this.width = 1});

  final Gradient gradient;
  final double width;

  @override
  BorderSide get bottom => BorderSide.none;

  @override
  BorderSide get top => BorderSide.none;

  @override
  bool get isUniform => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  ShapeBorder scale(double t) => this;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection, BoxShape shape = BoxShape.rectangle, BorderRadius? borderRadius}) {
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawCircle(rect.center, (math.min(rect.width, rect.height) - width) / 2, paint);
  }
}

/// The sweep: a soft diagonal band of light that crosses the ball.
class _ShinePainter extends CustomPainter {
  _ShinePainter(this.animation) : super(repaint: animation);

  /// 0..1 across one sweep.
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0 || t >= 1) return; // resting between sweeps: nothing to draw
    final p = Curves.easeInOut.transform(t);
    final w = size.width;
    final band = w * .42;
    final x = -band + (w + band * 2) * p;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(x, 0);
    canvas.skew(-.38, 0);
    final rect = Rect.fromLTWH(0, -size.height * .2, band, size.height * 1.4);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .5), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShinePainter old) => false;
}
