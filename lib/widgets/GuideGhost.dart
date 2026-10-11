import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideSurface.dart';

/// The one clock every breathing ghost shares (README Part 6): opacity 0.5 <-> 1.0
/// over 1.8 s, ease in-out. Its [Ticker] exists only while at least one pulsing
/// ghost area is on screen, and is muted while the app is in the background.
class GhostClock with WidgetsBindingObserver implements TickerProvider {
  GhostClock._();

  static final GhostClock instance = GhostClock._();

  static const Duration period = Duration(milliseconds: 1800);

  /// 0.5 .. 1.0; the ghost fill alpha is multiplied by it.
  final ValueNotifier<double> pulse = ValueNotifier<double>(0.5);

  Ticker? _ticker;
  int _users = 0;
  bool _observing = false;

  /// How many pulsing ghost areas are listening (tests read it).
  int get users => _users;
  bool get running => _ticker != null;

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick, debugLabel: 'GhostClock');

  void acquire() {
    _users++;
    if (_ticker != null) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final ticker = createTicker((elapsed) {
      final t = (elapsed.inMicroseconds % period.inMicroseconds) / period.inMicroseconds;
      // Starts at 0.5, peaks at 1.0 half way: a smooth sine ease in-out.
      pulse.value = 0.75 - 0.25 * math.cos(2 * math.pi * t);
    });
    _ticker = ticker..start();
    _syncWithLifecycle();
  }

  void release() {
    if (_users > 0) _users--;
    if (_users > 0) return;
    _ticker?.dispose();
    _ticker = null;
    pulse.value = 0.5;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  void _syncWithLifecycle() {
    final state = WidgetsBinding.instance.lifecycleState;
    final active = state == null || state == AppLifecycleState.resumed;
    _ticker?.muted = !active;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncWithLifecycle();
}

class _GhostScope extends InheritedWidget {
  const _GhostScope({required this.pulsing, required super.child});

  final bool pulsing;

  @override
  bool updateShouldNotify(_GhostScope old) => pulsing != old.pulsing;
}

/// A region of ghosts. Pulsing (loading) it holds the shared clock; still (empty,
/// error, reduced motion) it holds nothing and the ghosts are drawn at rest.
class GuideGhostArea extends StatefulWidget {
  const GuideGhostArea({super.key, required this.child, this.pulsing = true});

  final Widget child;
  final bool pulsing;

  @override
  State<GuideGhostArea> createState() => _GuideGhostAreaState();
}

class _GuideGhostAreaState extends State<GuideGhostArea> {
  bool _held = false;

  bool _wantClock(BuildContext context) => widget.pulsing && !GuideMotion.reduced(context);

  void _sync(bool want) {
    if (want == _held) return;
    _held = want;
    if (want) {
      GhostClock.instance.acquire();
    } else {
      GhostClock.instance.release();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(_wantClock(context));
  }

  @override
  void didUpdateWidget(GuideGhostArea old) {
    super.didUpdateWidget(old);
    _sync(_wantClock(context));
  }

  @override
  void dispose() {
    _sync(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: _GhostScope(pulsing: _held, child: widget.child),
      ),
    );
  }
}

/// One ghost shape: a soft fill, no border, the real widget's size and radius.
class GuideGhost extends StatelessWidget {
  const GuideGhost({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
    this.circle = false,
  });

  /// Null width = as wide as the parent gives.
  final double? width;
  final double? height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_GhostScope>();
    final pulsing = scope?.pulsing ?? false;
    final fill = context.g.ghostFill;
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: CustomPaint(
        painter: _GhostPainter(
          fill: fill,
          radius: radius,
          circle: circle,
          pulse: pulsing ? GhostClock.instance.pulse : null,
        ),
      ),
    );
  }
}

class _GhostPainter extends CustomPainter {
  _GhostPainter({required this.fill, required this.radius, required this.circle, required this.pulse})
      : super(repaint: pulse);

  final Color fill;
  final double radius;
  final bool circle;
  final ValueNotifier<double>? pulse;

  /// A ghost at rest sits between the two extremes of the breathing.
  static const double rest = 0.75;

  @override
  void paint(Canvas canvas, Size size) {
    final factor = pulse?.value ?? rest;
    final paint = Paint()..color = fill.withValues(alpha: fill.a * factor);
    if (circle) {
      canvas.drawOval(Offset.zero & size, paint);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)), paint);
    }
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.fill != fill || old.radius != radius || old.circle != circle || old.pulse != pulse;
}

/// The ghost of a text line: a bar as tall as the text's own line box would be.
class GuideGhostBar extends StatelessWidget {
  const GuideGhostBar({super.key, this.width, this.height = 12});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      GuideGhost(width: width, height: height, radius: height / 2);
}

// ---------------------------------------------------------------------------
// Ready-made ghosts at the real sizes of the shared components.
// ---------------------------------------------------------------------------

/// A card row (avatar circle + two lines): the ghost of the list rows used by the
/// managers and reports. [height] matches the real row (default 72 = 10 dp padding
/// around a 52 dp content, the height of [GuideCard] list rows).
class GuideGhostRow extends StatelessWidget {
  const GuideGhostRow({super.key, this.height = 72, this.avatar = true, this.trailing = false});

  final double height;
  final bool avatar;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          const Positioned.fill(child: GuideGhost(radius: GuideShape.cardRadius)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                if (avatar) ...[
                  GuideGhost(width: 38, height: 38, circle: true),
                  const SizedBox(width: 12),
                ],
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GuideGhostBar(width: 150, height: 13),
                      SizedBox(height: 8),
                      GuideGhostBar(width: 96, height: 10),
                    ],
                  ),
                ),
                if (trailing) GuideGhost(width: 24, height: 24, radius: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [rows] ghost rows with the page padding and the real gap between cards.
class GuideGhostList extends StatelessWidget {
  const GuideGhostList({
    super.key,
    this.rows = 6,
    this.rowHeight = 72,
    this.avatar = true,
    this.padding = const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 0),
    this.gap = 10,
    this.pulsing = true,
  });

  final int rows;
  final double rowHeight;
  final bool avatar;
  final EdgeInsetsGeometry padding;
  final double gap;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    return GuideGhostArea(
      pulsing: pulsing,
      child: Padding(
        padding: padding,
        child: Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) SizedBox(height: gap),
              GuideGhostRow(height: rowHeight, avatar: avatar),
            ],
          ],
        ),
      ),
    );
  }
}

/// A block (card / tile / hero) of a given height and radius.
class GuideGhostBlock extends StatelessWidget {
  const GuideGhostBlock({super.key, required this.height, this.radius = GuideShape.cardRadius, this.width});

  final double height;
  final double radius;
  final double? width;

  @override
  Widget build(BuildContext context) => GuideGhost(width: width, height: height, radius: radius);
}
