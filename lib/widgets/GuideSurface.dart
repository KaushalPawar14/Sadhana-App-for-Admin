import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'PressScale.dart';

/// The page: warm paper (light) or graphite (dark) with the full-width top fade
/// (champagne in light, soft grey in dark) behind everything.
class GuidePageBackground extends StatelessWidget {
  const GuidePageBackground({super.key, required this.child});

  final Widget child;

  static const double fadeHeight = 360;
  static const double fadeMidAt = 170;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return ColoredBox(
      color: g.pageBackground,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: fadeHeight,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        g.pageFadeTop,
                        g.pageFadeMid,
                        g.pageFadeMid.withValues(alpha: 0),
                      ],
                      stops: const [0, fadeMidAt / fadeHeight, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// A screen on the Ink & Brass page: the page colour with the top fade behind
/// EVERYTHING (the Material app bar included, which the theme makes transparent),
/// and a status bar whose icons suit the theme. Pages bring their own top bar
/// ([GuideTopBar]) or pass a Material [appBar]. Takes the Scaffold parameters the
/// app's screens use, so a screen converts by renaming `Scaffold` to this.
class GuideScaffold extends StatelessWidget {
  const GuideScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset,
    this.extendBody = false,
    this.drawer,
    this.endDrawer,
  });

  final Widget? body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final bool? resizeToAvoidBottomInset;
  final bool extendBody;
  final Widget? drawer;
  final Widget? endDrawer;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: g.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: GuidePageBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          floatingActionButton: floatingActionButton,
          floatingActionButtonLocation: floatingActionButtonLocation,
          bottomNavigationBar: bottomNavigationBar,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          extendBody: extendBody,
          drawer: drawer,
          endDrawer: endDrawer,
          body: body,
        ),
      ),
    );
  }
}

/// The brass "Add ..." floating button: a fully rounded gradient pill, 48 dp tall,
/// with the soft brass glow. Used as a Scaffold `floatingActionButton`.
class GuideFab extends StatelessWidget {
  const GuideFab({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: g.primaryGradient,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [BoxShadow(color: g.brassGlow, blurRadius: 24, offset: const Offset(0, 12))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: g.onPrimary),
                const SizedBox(width: 8),
                Text(label, style: context.gText.button.copyWith(color: g.onPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card: surface, 1 px border, radius 18, the soft light-mode shadow (none in dark).
class GuideCard extends StatelessWidget {
  const GuideCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = GuideShape.cardRadius,
    this.color,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? color;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final inner = padding == null ? child : Padding(padding: padding!, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? g.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: g.border),
        boxShadow: g.cardShadow,
      ),
      child: clip
          ? ClipRRect(borderRadius: BorderRadius.circular(radius - 1), child: inner)
          : inner,
    );
  }
}

/// The 40 dp round icon button of the top bar (1 px border, surface, soft shadow).
/// The tap target is 48 dp.
class GuideRoundButton extends StatelessWidget {
  const GuideRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 20,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;

  /// Drawn over the button's top-right corner (an unseen dot).
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: PressScale(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox(
              width: GuideShape.touchTarget,
              height: GuideShape.touchTarget,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: GuideShape.roundButton,
                      height: GuideShape.roundButton,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: g.surface,
                        border: Border.all(color: g.border),
                        boxShadow: g.cardShadow,
                      ),
                      child: Icon(icon,
                          size: iconSize, color: enabled ? g.text : g.mutedText),
                    ),
                    if (badge != null) Positioned(right: 0, top: 0, child: badge!),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The top bar of a new-style screen: optional back arrow, the title (serif 22,
/// one line, ellipsis) and round action buttons. At least 48 dp tall.
class GuideTopBar extends StatelessWidget {
  const GuideTopBar({
    super.key,
    this.title,
    this.titleWidget,
    this.onBack,
    this.showBack,
    this.actions = const [],
    this.titleMaxLines = 1,
  });

  /// Plain-text title (serif 22).
  final String? title;

  /// A custom title (the Home screen's uppercase date label).
  final Widget? titleWidget;

  /// Called by the back arrow; defaults to popping the route.
  final VoidCallback? onBack;

  /// Force the back arrow on or off; by default it shows when the route can pop.
  final bool? showBack;
  final List<Widget> actions;

  /// A long title wraps onto this many lines (text is never cut off mid-word at
  /// large text sizes) before it is ellipsised.
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final withBack = showBack ?? (onBack != null || Navigator.of(context).canPop());
    final titleChild = titleWidget ??
        (title == null
            ? const SizedBox.shrink()
            : Text(title!,
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: t.topBarTitle));
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            GuideSpace.pagePadding - 4, 8, GuideSpace.pagePadding - 4, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
          child: Row(
            children: [
              if (withBack)
                GuideRoundButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: onBack ?? () => Navigator.maybePop(context),
                ),
              SizedBox(width: withBack ? 8 : 4),
              Expanded(child: titleChild),
              for (final a in actions) a,
            ],
          ),
        ),
      ),
    );
  }
}

/// The small uppercase label (11 px, 0.12 em, 600, muted).
class GuideLabel extends StatelessWidget {
  const GuideLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = context.gText.label;
    return Text(text.toUpperCase(),
        style: color == null ? style : style.copyWith(color: color));
  }
}

/// A section title: serif 19.
class GuideSectionTitle extends StatelessWidget {
  const GuideSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.gText.sectionTitle),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// The five pastel gradients as a one-liner on a context.
extension GuidePastelGradient on BuildContext {
  LinearGradient pastel(GuidePastel p, {bool abcde = false}) =>
      g.pastel(p, abcde: abcde);
}

/// [AnimatedSize] that is simply its child when animations are reduced (an
/// AnimatedSize with a zero duration re-dirties itself during layout).
class GuideAnimatedSize extends StatelessWidget {
  const GuideAnimatedSize({
    super.key,
    required this.child,
    this.duration = GuideMotion.expand,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (GuideMotion.reduced(context)) return child;
    return AnimatedSize(
      duration: duration,
      curve: GuideMotion.standard,
      alignment: alignment,
      child: child,
    );
  }
}

/// The look of [GuideRoundButton] without its own tap handling, for a control that
/// brings its own (a popup menu button): a 40 dp circle in a 48 dp box.
class GuideRoundIcon extends StatelessWidget {
  const GuideRoundIcon({super.key, required this.icon, this.iconSize = 20});

  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return SizedBox(
      width: GuideShape.touchTarget,
      height: GuideShape.touchTarget,
      child: Center(
        child: Container(
          width: GuideShape.roundButton,
          height: GuideShape.roundButton,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: g.surface,
            border: Border.all(color: g.border),
            boxShadow: g.cardShadow,
          ),
          child: Icon(icon, size: iconSize, color: g.text),
        ),
      ),
    );
  }
}
