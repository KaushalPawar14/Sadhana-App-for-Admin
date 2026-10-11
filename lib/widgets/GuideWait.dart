import 'package:flutter/material.dart';

import '../theme/GuideTokens.dart';
import 'GuideGhost.dart';
import 'GuideStates.dart';

/// What a screen shows while its data loads (README Part 6): ghost cards that breathe,
/// never a spinner. Give it the failed [snapshot] and a failure shows the ghost frozen
/// with a short message and Retry (which rebuilds the screen, so a stream built in
/// `build` is subscribed again; pass [onRetry] to do something else).
///
/// [compact] is a smaller block (two rows) for a section inside a page; the default is
/// a page's worth of list rows.
class GuideWait extends StatelessWidget {
  const GuideWait({
    super.key,
    this.snapshot,
    this.compact = false,
    this.onRetry,
    this.rowHeight = 72,
  });

  final AsyncSnapshot<Object?>? snapshot;
  final bool compact;
  final VoidCallback? onRetry;
  final double rowHeight;

  /// Marks the nearest StatefulWidget's State dirty: its `build` runs again.
  static void rebuildNearestState(BuildContext context) {
    context.visitAncestorElements((e) {
      if (e is StatefulElement) {
        e.markNeedsBuild();
        return false;
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = compact ? 2 : 5;
    final padding = compact
        ? const EdgeInsets.symmetric(vertical: 8)
        : const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 0);
    if (snapshot?.hasError ?? false) {
      return GuideStateView(
        state: GuideLoad.error,
        ghost: GuideGhostList(rows: rows, rowHeight: rowHeight, pulsing: false, padding: padding),
        content: const SizedBox.shrink(),
        errorMessage: 'Could not load this. Check your connection and try again.',
        onRetry: onRetry ?? () => rebuildNearestState(context),
      );
    }
    return GuideGhostList(rows: rows, rowHeight: rowHeight, padding: padding);
  }
}

/// A small breathing ghost dot for a busy button or a row that is saving: the "no
/// spinners" version of a 16-24 dp progress ring. Fills the box it is given (or 20 dp).
class GuideBusyDot extends StatelessWidget {
  const GuideBusyDot({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return GuideGhostArea(
      child: Center(child: GuideGhost(width: size, height: size, circle: true)),
    );
  }
}
