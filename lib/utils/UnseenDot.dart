import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';

/// A small, restrained "new content" indicator — Master Task 2026-09-10,
/// Part 6 item 7. One consistent look everywhere it appears in this app
/// (and mirrored, same colour/size, in the Student app), regardless of
/// light/dark theme: a plain solid orange fill reads clearly against both,
/// and a thin surface-coloured ring keeps it visually separated from
/// whatever it sits on top of instead of blending into a similarly-hued
/// icon or background.
class UnseenDot extends StatelessWidget {
  final double size;
  const UnseenDot({super.key, this.size = 9});

  @override
  Widget build(BuildContext context) {
    final ringColor = Theme.of(context).scaffoldBackgroundColor;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.g.attention,
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 1.2),
      ),
    );
  }
}

/// Wraps [child] with an [UnseenDot] pinned to its top-right corner when
/// [show] is true — the one place every "badge this icon/tile" call site
/// in this app should go through, so the dot's exact size/position/colour
/// never drifts between features.
///
/// ⚠️ **Two layout modes, and BOTH are needed — 2026-09-11.**
///
/// This widget is used in two structurally opposite situations, and no
/// single fixed strategy satisfies both:
///
///  * A GRID CELL (`Competition.dart`'s tiles): the PARENT gives TIGHT,
///    bounded constraints, and `child` (an `AnimatedContainer` with no
///    `width`/`height` of its own) relies entirely on that tight box to
///    know its own size. [child] must be FORCED to fill — [fillParent]
///    `true`, via [Positioned.fill] (a positioned child is governed
///    purely by its own edge offsets, never by `fit`/loosening, so it
///    fills the Stack's resolved size regardless of its own intrinsic
///    size). This is the grid-squeeze fix: leaving `child` a bare,
///    non-positioned `Stack` child let a `Stack`'s default `fit:
///    StackFit.loose` loosen the tight box before handing it down,
///    collapsing the tile to its intrinsic content size (roughly half
///    width) with the dot then resolving against that shrunken Stack
///    instead of the real cell.
///
///  * An UNCONSTRAINED parent (the floating assistant button, wrapped in
///    a `Positioned` that sets only `left`/`top` — no `width`/`height`,
///    so its child gets loose, effectively UNBOUNDED constraints; also
///    every plain icon badge, and every `ListView`-hosted tile whose
///    `Row`+`Expanded` already forces its own width regardless of the
///    parent): [child] ALREADY has (or resolves to) an explicit, finite
///    size, and it is the STACK that needs to size itself FROM [child],
///    not the other way around. [fillParent] `false` (the default) keeps
///    `child` a plain non-positioned `Stack` child under the default
///    `StackFit.loose` — the loosened constraint only drops the MINIMUM,
///    so `child`'s own explicit/intrinsic size passes through untouched,
///    and the Stack's own size becomes that same finite size. Using
///    [Positioned.fill] here instead (zero non-positioned children left
///    to size the Stack from) makes `RenderStack` fall back to
///    `constraints.biggest` — which is INFINITE under an unbounded
///    parent, and `Stack` explicitly asserts against that: "A Stack
///    requires bounded constraints from its parent." This is the
///    disappearing-icon bug: the floating button's own `Positioned`
///    only sets `left`/`top`, so its subtree is unconstrained, and the
///    unconditional `Positioned.fill` above crashed it on every single
///    frame — silently, since the crash is caught and simply prevents
///    that frame's layout, at exactly the same instant the daily-message
///    dot could show at all.
///
/// Every existing call site was re-checked against this exact contract
/// (2026-09-11): only `Competition.dart`'s three grid tiles pass
/// `fillParent: true`. Every other consumer — the nav bar icons in both
/// apps, `AbcdeHub.dart`/`PriorityHub.dart`'s `ListView`-hosted tiles
/// (their own internal `Row`+`Expanded` already forces full width
/// regardless of the Stack's own fit), `FolkBoysEntry.dart`'s
/// `SizedBox`-wrapped board/calendar tiles, `FolkBoysWorkspace.dart`'s
/// per-student comment icon, and every journey-card avatar in the
/// Student app — keeps the default `false`, unchanged from how it
/// already (correctly) behaved.
class UnseenBadge extends StatelessWidget {
  final Widget child;
  final bool show;
  final double dotSize;
  final Offset offset;

  /// `true` only when the parent gives TIGHT, bounded constraints and
  /// [child] has no explicit size of its own to fall back on (a grid
  /// cell). `false` (default) whenever [child] already has an explicit
  /// or self-determined finite size, or the parent may be unbounded.
  final bool fillParent;

  const UnseenBadge({
    super.key,
    required this.child,
    required this.show,
    this.dotSize = 9,
    this.offset = const Offset(2, -2),
    this.fillParent = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        fillParent ? Positioned.fill(child: child) : child,
        Positioned(
          top: offset.dy,
          right: offset.dx,
          child: UnseenDot(size: dotSize),
        ),
      ],
    );
  }
}
