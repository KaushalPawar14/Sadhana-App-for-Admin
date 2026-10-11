import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideButtons.dart';
import 'GuideGhost.dart';

/// Ghost -> content, 250 ms cross-fade (README Part 6). The ghost and the real widget
/// have identical sizes, so nothing moves when the content arrives: both children
/// are laid out in one Stack, top-aligned, and the Stack is as big as the bigger one.
class GuideCrossFade extends StatelessWidget {
  const GuideCrossFade({super.key, required this.child});

  /// Give the loaded and the loading child different keys.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = GuideMotion.of(context, GuideMotion.ghostCrossFade);
    return AnimatedSwitcher(
      duration: d,
      reverseDuration: d,
      switchInCurve: GuideMotion.standard,
      switchOutCurve: GuideMotion.standard,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

enum GuideLoad { loading, content, empty, error }

/// An optional primary action under an empty-state line ("Create your first board").
class GuideEmptyAction {
  const GuideEmptyAction(this.label, this.onPressed, {this.icon});
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
}

/// Loading, empty and error for one data area, with ghosts instead of spinners.
///
/// - loading: the [ghost] breathes (all ghosts share one clock).
/// - content: the real [content], cross-faded from the ghost.
/// - empty: the same [ghost], still, with one friendly muted line (+ an action).
/// - error: the ghost frozen, a short message and a Retry button.
class GuideStateView extends StatelessWidget {
  const GuideStateView({
    super.key,
    required this.state,
    required this.ghost,
    required this.content,
    this.emptyMessage = 'Nothing here yet.',
    this.emptyAction,
    this.errorMessage = 'Could not load this. Check your connection and try again.',
    this.onRetry,
  });

  final GuideLoad state;

  /// Built from [GuideGhost]s at the sizes of the real widgets. It is wrapped in a
  /// [GuideGhostArea] here; do not add your own.
  final Widget ghost;
  final Widget content;
  final String emptyMessage;
  final GuideEmptyAction? emptyAction;
  final String errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    switch (state) {
      case GuideLoad.loading:
        child = KeyedSubtree(
          key: const ValueKey('ghost-loading'),
          child: GuideGhostArea(child: ghost),
        );
      case GuideLoad.content:
        child = KeyedSubtree(key: const ValueKey('content'), child: content);
      case GuideLoad.empty:
        child = KeyedSubtree(
          key: const ValueKey('ghost-empty'),
          child: _Overlaid(
            ghost: GuideGhostArea(pulsing: false, child: ghost),
            message: emptyMessage,
            action: emptyAction == null
                ? null
                : GuidePrimaryButton(
                    label: emptyAction!.label,
                    icon: emptyAction!.icon,
                    onPressed: emptyAction!.onPressed,
                    expand: false,
                  ),
          ),
        );
      case GuideLoad.error:
        child = KeyedSubtree(
          key: const ValueKey('ghost-error'),
          child: _Overlaid(
            ghost: GuideGhostArea(pulsing: false, child: ghost),
            message: errorMessage,
            action: onRetry == null
                ? null
                : GuideSecondaryButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
          ),
        );
    }
    return GuideCrossFade(child: child);
  }
}

/// The still ghost with its one line (and action) under it.
class _Overlaid extends StatelessWidget {
  const _Overlaid({required this.ghost, required this.message, this.action});

  final Widget ghost;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ghost,
        Padding(
          padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 20, GuideSpace.pagePadding, 0),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: t.body.copyWith(color: context.g.mutedText, height: 1.5),
          ),
        ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Center(child: action),
          ),
      ],
    );
  }
}

/// The shortest way to the three states from a [StreamBuilder] / [FutureBuilder]
/// snapshot: error beats data beats waiting.
GuideLoad guideLoadOf(AsyncSnapshot snapshot, {bool Function(Object data)? isEmpty}) {
  if (snapshot.hasError) return GuideLoad.error;
  if (!snapshot.hasData) return GuideLoad.loading;
  final d = snapshot.data as Object;
  if (isEmpty != null && isEmpty(d)) return GuideLoad.empty;
  return GuideLoad.content;
}
