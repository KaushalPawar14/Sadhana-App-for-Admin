import 'GuideBoardMotion.dart';
import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideChips.dart';

/// Snap scrolling for the board's row of columns: a fling (or a slow drag) comes to
/// rest with a column's left edge at the page padding, never between two columns.
/// [snapOffsets] are the scroll offsets of every column's left edge (the board
/// computes them from the column widths, so a gender-lane label between columns
/// is accounted for).
class GuideSnapPhysics extends ScrollPhysics {
  const GuideSnapPhysics({required this.snapOffsets, super.parent});

  final List<double> snapOffsets;

  @override
  GuideSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      GuideSnapPhysics(snapOffsets: snapOffsets, parent: buildParent(ancestor));

  double _target(ScrollMetrics position, double velocity) {
    if (snapOffsets.isEmpty) return position.pixels;
    final max = position.maxScrollExtent;
    final offsets = [
      for (final o in snapOffsets) o.clamp(0.0, max),
      // The last column may not be able to reach the left edge: the end of the
      // scroll is a resting place too.
      max,
    ]..sort();
    // Where the scroll would end up on its own, nudged by the fling velocity.
    final projected = position.pixels + velocity * .18;
    var best = offsets.first;
    for (final o in offsets) {
      if ((o - projected).abs() < (best - projected).abs()) best = o;
    }
    // A fling always moves on to the neighbouring column at least.
    if (velocity.abs() > 120) {
      final dir = velocity.sign;
      final here = offsets.lastWhere((o) => o <= position.pixels + 1, orElse: () => offsets.first);
      final idx = offsets.indexOf(here);
      final next = (idx + (dir > 0 ? 1 : -1)).clamp(0, offsets.length - 1);
      final candidate = offsets[next];
      if (dir > 0 ? candidate > best : candidate < best) best = candidate;
    }
    return best;
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // Out of range: the default spring brings it back.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final target = _target(position, velocity);
    if ((target - position.pixels).abs() < toleranceFor(position).distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}

/// A dashed rounded outline (the "New board" / "Add a list" column).
class GuideDashedBox extends StatelessWidget {
  const GuideDashedBox({super.key, required this.child, this.radius = GuideShape.columnRadius});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return CustomPaint(
      foregroundPainter: _DashedRRect(color: g.mutedText.withValues(alpha: .55), radius: radius),
      child: child,
    );
  }
}

class _DashedRRect extends CustomPainter {
  _DashedRRect({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRect old) => old.color != color || old.radius != radius;
}

/// One board column: a rounded surface with a faint tint at the top, the
/// header, and the cards. While a card is dragged over it ([hovering]) its
/// outline turns brass.
class GuideBoardColumnShell extends StatelessWidget {
  const GuideBoardColumnShell({
    super.key,
    required this.tone,
    required this.header,
    required this.body,
    this.hovering = false,
    this.width = GuideBoardTokens.columnWidth,
  });

  final GuideColumnTone tone;
  final Widget header;
  final Widget body;
  final bool hovering;
  final double width;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Container(
      width: width,
      margin: const EdgeInsets.only(right: GuideBoardTokens.columnGap),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [g.columnTint(tone), g.columnSurface],
          stops: const [0, .22],
        ),
        borderRadius: BorderRadius.circular(GuideShape.columnRadius),
        border: Border.all(
          color: hovering ? g.brass : g.border,
          width: hovering ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 6),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// The column header: a coloured vertical bar, the name (serif 18), a small line
/// under it ("2 boys - 2 FOLK / 0 Hostel / 0 Localite") and a count badge, then any
/// trailing action buttons.
class GuideBoardColumnHeader extends StatelessWidget {
  const GuideBoardColumnHeader({
    super.key,
    required this.title,
    required this.accent,
    required this.count,
    this.subtitle,
    this.actions = const [],
    this.scroll,
    this.columnWidth = GuideBoardTokens.columnWidth,
  });

  final String title;
  final Color accent;
  final int count;
  final String? subtitle;
  final List<Widget> actions;

  /// The row's scroll controller: the header drifts slightly while it scrolls.
  final ScrollController? scroll;
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return GuideHeaderParallax(
      scroll: scroll,
      columnWidth: columnWidth,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.isEmpty ? '(untitled)' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.columnTitle,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.caption),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GuideCountBadge(count),
          for (final a in actions) a,
        ],
      ),
    ),
    );
  }
}

/// A student card on the board: surface, radius 16, 1 px border. A card tinted by
/// nothing (the group colour lives on the avatar and the pill).
class GuideBoardCardFrame extends StatelessWidget {
  const GuideBoardCardFrame({super.key, required this.child, this.lifted = false});

  final Widget child;

  /// While dragged: a soft shadow.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Container(
      decoration: BoxDecoration(
        color: g.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: g.border),
        boxShadow: lifted
            ? const [BoxShadow(color: Color(0x3314192B), blurRadius: 24, offset: Offset(0, 10))]
            : g.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A small icon button inside a card: a 48 x 48 dp touch target with a 18 dp icon.
class GuideCardIconButton extends StatelessWidget {
  const GuideCardIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tooltip,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: GuideShape.touchTarget,
            height: GuideShape.touchTarget,
            child: Icon(icon,
                size: 18, color: onTap == null ? g.mutedText.withValues(alpha: .4) : g.mutedText),
          ),
        ),
      ),
    );
  }
}

/// The students' group legend under the top bar: FOLK / Hostel / Localite pills.
class GuideGroupLegend extends StatelessWidget {
  const GuideGroupLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.fromLTRB(GuideSpace.pagePadding, 14, GuideSpace.pagePadding, 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            GuideGroupPill(group: GuideGroup.folk, legend: true),
            GuideGroupPill(group: GuideGroup.hostel, legend: true),
            GuideGroupPill(group: GuideGroup.localite, legend: true),
          ],
        ),
      ),
    );
  }
}

/// A tinted notice box for dialogs ("This changes who can see ...").
class GuideNotice extends StatelessWidget {
  const GuideNotice({super.key, required this.child, this.danger = false});

  final Widget child;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final tone = danger ? g.danger : g.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: .4)),
      ),
      child: DefaultTextStyle.merge(
        style: context.gText.small.copyWith(color: g.text, height: 1.45),
        child: child,
      ),
    );
  }
}
