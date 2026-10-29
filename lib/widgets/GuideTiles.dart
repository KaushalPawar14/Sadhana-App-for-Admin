import 'package:flutter/material.dart';
import '../utils/Responsive.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideEntry.dart';
import 'PressScale.dart';

/// The small icon square inside a pastel widget: 40 dp, radius 12, translucent white.
class GuideIconTile extends StatelessWidget {
  const GuideIconTile({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
    this.radius = GuideShape.iconTileRadius,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: GuideColors.pastelIconTile,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: GuideColors.onPastel),
    );
  }
}

/// The brass progress bar: 5 dp, radius 3, a brass-gradient fill that grows from
/// 0 to its value the first time it appears (400 ms; no animation under "reduce
/// animations"). [onPastel] draws the track in ink (the theme's dark-mode track
/// is white and vanishes on a pastel widget).
class GuideProgressBar extends StatelessWidget {
  const GuideProgressBar({super.key, required this.value, this.onPastel = false, this.height = 5});

  /// 0.0 - 1.0.
  final double value;
  final bool onPastel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final track = onPastel ? const Color(0x1714192B) : g.progressTrack;
    return Semantics(
      value: '${(v * 100).round()} percent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: height,
          child: ColoredBox(
            color: track,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: v),
              duration: GuideMotion.of(context, GuideMotion.progressFill),
              curve: GuideMotion.out,
              builder: (context, value, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: g.primaryGradient,
                      borderRadius: BorderRadius.circular(3),
                    ),
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

/// A pastel gradient container (sand, slate, sage, clay, mauve): the same in
/// light and dark, text always #14192B / #565B6C. Radius 18, 1 px ink border.
/// [abcde] selects the slightly darker dark-mode set the ABCDE rows use.
class GuidePastelBox extends StatelessWidget {
  const GuidePastelBox({
    super.key,
    required this.pastel,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = GuideShape.tileRadius,
    this.abcde = false,
    this.minHeight = 0,
    this.fillWidth = true,
  });

  final GuidePastel pastel;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool abcde;
  final double minHeight;

  /// Fill the width it is given (the default): inside a Stack (an unseen dot) a
  /// box would otherwise shrink to its content.
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Container(
      width: fillWidth ? double.infinity : null,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      decoration: BoxDecoration(
        gradient: g.pastel(pastel, abcde: abcde),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: GuideColors.pastelBorder),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: GuideColors.onPastel),
        child: child,
      ),
    );
  }
}

/// A tappable pastel tile: icon tile and chevron on top, title and subtitle at
/// the bottom. [minHeight] is a minimum (116 on Home, 150 on Other tasks / Folk
/// analysis): the tile grows with the text, never clips it.
class GuideGradientTile extends StatelessWidget {
  const GuideGradientTile({
    super.key,
    required this.pastel,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.minHeight = 116,
    this.showChevron = true,
    this.badge,
    this.semanticLabel,
    this.large = false,
  });

  final GuidePastel pastel;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final double minHeight;
  final bool showChevron;

  /// Drawn over the tile's top-right corner (an unseen dot).
  final Widget? badge;
  final String? semanticLabel;

  /// The big grid tile (Other tasks, Folk analysis): padding 16, radius 20, a 44 dp
  /// icon tile, title 16, no chevron, the text pinned to the bottom of the tile.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final tile = GuidePastelBox(
      pastel: pastel,
      minHeight: minHeight,
      padding: const EdgeInsets.all(14),
      radius: large ? 20 : GuideShape.tileRadius,
      child: Column(
        mainAxisSize: large ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              large
                  ? GuideIconTile(icon: icon, size: 40, iconSize: 20, radius: 12)
                  : GuideIconTile(icon: icon),
              if (showChevron && !large)
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: GuideColors.onPastelMuted),
            ],
          ),
          const SizedBox(height: 12),
          if (large) const Spacer(),
          Text(title, style: large ? t.onPastelTitle.copyWith(fontSize: 16) : t.onPastelTitle),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!,
                style: large ? t.onPastelSmall.copyWith(height: 1.3) : t.onPastelSmall),
          ],
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: PressScale(
        enabled: onTap != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: badge == null
              ? tile
              : Stack(
                  clipBehavior: Clip.none,
                  children: [tile, Positioned(right: 8, top: 8, child: badge!)],
                ),
        ),
      ),
    );
  }
}

/// A full-width pastel row: a letter or icon tile, a title and a one-line
/// description, and a chevron (the ABCDE rows).
class GuidePastelRow extends StatelessWidget {
  const GuidePastelRow({
    super.key,
    required this.pastel,
    required this.title,
    this.description,
    this.letter,
    this.icon,
    this.onTap,
    this.abcde = false,
    this.badge,
  });

  final GuidePastel pastel;
  final String title;
  final String? description;
  final String? letter;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool abcde;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final lead = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GuideColors.pastelIconTile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: letter != null
          ? Text(letter!, style: t.letterTile)
          : Icon(icon, size: 22, color: GuideColors.onPastel),
    );
    final row = GuidePastelBox(
      pastel: pastel,
      abcde: abcde,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          lead,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: t.onPastelTitle),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(description!, style: t.onPastelSmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded,
              size: 22, color: GuideColors.onPastelMuted),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      child: PressScale(
        enabled: onTap != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: badge == null
              ? row
              : Stack(clipBehavior: Clip.none, children: [
                  row,
                  Positioned(right: 8, top: 8, child: badge!),
                ]),
        ),
      ),
    );
  }
}

/// The navy panel of the hero card (the same in both themes) with the three thin
/// concentric rings top-right. [padding] is inside the panel. [gradient] / [shadowColor] give the same panel another colour (TODAY'S TASKS is
/// the dark green one).
class GuideHeroPanel extends StatelessWidget {
  const GuideHeroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 18),
    this.gradient = GuideColors.heroGradient,
    this.shadowColor = GuideColors.heroShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient gradient;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(GuideShape.heroRadius),
        boxShadow: [
          BoxShadow(color: shadowColor, blurRadius: 28, offset: const Offset(0, 14)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GuideShape.heroRadius),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned(
              right: -48,
              top: -60,
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: SizedBox(
                      width: 170, height: 170, child: CustomPaint(painter: _RingsPainter())),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// One of the numbers in the hero card.
class GuideHeroStat {
  const GuideHeroStat(this.value, this.label);
  final String value;
  final String label;
}

/// The hero card: a label and date range, then [stats] as equal columns with
/// hairline dividers. The whole card is tappable when [onTap] is given.
class GuideHeroCard extends StatelessWidget {
  const GuideHeroCard({
    super.key,
    required this.label,
    this.trailing,
    required this.stats,
    this.onTap,
    this.footer,
  });

  final String label;
  final String? trailing;
  final List<GuideHeroStat> stats;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final card = GuideHeroPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text(label.toUpperCase(), style: t.heroLabel)),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  Text(trailing!, style: t.heroCaption),
                ],
              ],
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0)
                    const VerticalDivider(width: 1, thickness: 1, color: GuideColors.heroDivider),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GuideCountUp(stats[i].value, style: t.heroNumber),
                          const SizedBox(height: 7),
                          Text(stats[i].label,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: t.heroCaption),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), child: footer),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      child: PressScale(
        enabled: onTap != null,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 0 0 160 160 drawn at 170 x 170; radii 36 / 56 / 76.
    final scale = size.width / 160;
    final c = Offset(80 * scale, 80 * scale);
    const radii = [36.0, 56.0, 76.0];
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        c,
        radii[i] * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = GuideColors.heroRings[i],
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tiles in two equal columns, a row at a time: both tiles of a row are as tall as
/// the taller one (heights are minimums and grow with the text; nothing is clipped).
class GuideTileGrid extends StatelessWidget {
  const GuideTileGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : GuideSpace.cardGap),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: GuideEntry(index: i, child: tiles[i])),
              const SizedBox(width: GuideSpace.cardGap),
              Expanded(
                child: i + 1 < tiles.length
                    ? GuideEntry(index: i + 1, child: tiles[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
  }
}


/// The summary at the top of a report screen: a status icon, a serif headline and
/// up to a few muted lines, on the navy hero panel. [tone] colours the icon only.
enum GuideTone { good, warn, bad }

class GuideSummaryBanner extends StatelessWidget {
  const GuideSummaryBanner({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.lines = const [],
    this.emphasis,
  });

  final GuideTone tone;
  final IconData icon;
  final String title;
  final List<String> lines;

  /// An extra line shown in the full hero text colour (e.g. "2 needing urgent attention").
  final String? emphasis;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final iconColor = switch (tone) {
      GuideTone.good => g.success,
      GuideTone.warn => g.warning,
      GuideTone.bad => g.danger,
    };
    return GuideHeroPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: t.cardTitle.copyWith(color: GuideColors.heroText, fontSize: 22)),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(l,
                        style: t.small.copyWith(color: GuideColors.heroMuted, height: 1.4)),
                  ),
                if (emphasis != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(emphasis!,
                        style: t.small.copyWith(
                            color: GuideColors.heroText, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// A full-width rectangular navigation card (the Analysis tab, the wide cards of the
/// Tasks tab): a pastel gradient, an icon tile on the left, a serif title with a
/// one-line description under it, and a chevron on the right. At least 92 dp tall,
/// it grows with the text; press feedback is the shared 0.97 scale. [badge] is an
/// unseen dot drawn on its top-right corner.
class GuideNavCard extends StatelessWidget {
  const GuideNavCard({
    super.key,
    required this.pastel,
    required this.icon,
    required this.title,
    this.description,
    this.onTap,
    this.badge,
  });

  final GuidePastel pastel;
  final IconData icon;
  final String title;
  final String? description;
  final VoidCallback? onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final card = GuidePastelBox(
      pastel: pastel,
      minHeight: 92,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: 20,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GuideColors.pastelIconTile,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 26, color: GuideColors.onPastel),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: t.onPastelSerifTitle),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(description!, style: t.onPastelSmall.copyWith(fontSize: 13, height: 1.35)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 24, color: GuideColors.onPastelMuted),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: description == null ? title : '$title, $description',
      excludeSemantics: true,
      child: PressScale(
        enabled: onTap != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: badge == null
              ? card
              : Stack(clipBehavior: Clip.none, children: [card, Positioned(right: 8, top: 8, child: badge!)]),
        ),
      ),
    );
  }
}

/// Two tiles side by side, exactly the same size and square: each is as wide as half the
/// row ([side]), and at least [side] tall; if the text of either needs more room (a
/// large text size) BOTH grow to the taller, so they always match and never clip.
/// No LayoutBuilder: the side comes from the screen width and the page padding.
class GuideSquarePair extends StatelessWidget {
  const GuideSquarePair({super.key, required this.left, required this.right});

  /// Each builds its tile for the given square [side] (use it as `minHeight`).
  final Widget Function(double side) left;
  final Widget Function(double side) right;

  /// The side of one square for the current screen. On a wide window it is capped ([kTileMaxSide]): the tiles stay tile-sized instead of
  /// filling the window.
  static double sideOf(BuildContext context) {
    final side = (MediaQuery.sizeOf(context).width - 2 * GuideSpace.pagePadding - GuideSpace.cardGap) / 2;
    return context.isWide && side > kTileMaxSide ? kTileMaxSide : side;
  }

  @override
  Widget build(BuildContext context) {
    final side = sideOf(context);
    if (context.isWide) {
      // a wide window: two tile-sized squares side by side (equal heights), left-aligned in the column
      return Align(
        alignment: Alignment.centerLeft,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: side, child: left(side)),
              const SizedBox(width: GuideSpace.cardGap),
              SizedBox(width: side, child: right(side)),
            ],
          ),
        ),
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left(side)),
          const SizedBox(width: GuideSpace.cardGap),
          Expanded(child: right(side)),
        ],
      ),
    );
  }
}

/// Navigation cards (and a [GuideSquarePair]) on a WIDE window: they flow into a grid, about three cards per row, each a comfortable
/// [kCardGridWidth] wide, instead of stretching across the window. [selfSized] are the indexes of children that size themselves (a
/// [GuideSquarePair]). On a phone the page keeps its own single column; this is only built for a wide window.
class GuideWideFlow extends StatelessWidget {
  const GuideWideFlow({super.key, required this.children, this.selfSized = const {}});

  final List<Widget> children;
  final Set<int> selfSized;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: GuideSpace.cardGap,
      runSpacing: GuideSpace.cardGap,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) selfSized.contains(i) ? children[i] : SizedBox(width: kCardGridWidth, child: children[i]),
      ],
    );
  }
}
