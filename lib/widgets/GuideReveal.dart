import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideButtons.dart';
import 'GuideGhost.dart';
import 'GuideStates.dart';

/// Reveals [child] over its own [ghost] the first time it is built: the ghost fades
/// out and the content fades in over 250 ms, both in the same box, so nothing moves.
/// Use it where the content appears from deep inside nested builders (the board),
/// where an AnimatedSwitcher at the top cannot see the change. With "reduce
/// animations" it is just the child. [animate] false (a screen the user has already seen
/// loaded, shown again) is just the child too: nothing fades in a second time.
class GuideReveal extends StatefulWidget {
  const GuideReveal({super.key, required this.ghost, required this.child, this.animate = true});

  final Widget ghost;
  final Widget child;
  final bool animate;

  @override
  State<GuideReveal> createState() => _GuideRevealState();
}

class _GuideRevealState extends State<GuideReveal> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _decided = false;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!widget.animate || GuideMotion.reduced(context)) {
      _done = true;
      return;
    }
    final c = AnimationController(vsync: this, duration: GuideMotion.ghostCrossFade);
    _controller = c
      ..forward().whenComplete(() {
        if (mounted) setState(() => _done = true);
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Two fixed slots: the ghost (an empty box once it is gone) and the content. The
  // content never changes place in the tree, so it is never remounted when the
  // ghost leaves.
  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return widget.child;
    final curve = CurvedAnimation(parent: c, curve: GuideMotion.standard);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        _done
            ? const SizedBox.shrink()
            : Positioned.fill(
                child: IgnorePointer(
                  child: FadeTransition(
                    opacity: ReverseAnimation(curve),
                    child: GuideGhostArea(child: widget.ghost),
                  ),
                ),
              ),
        FadeTransition(opacity: curve, child: widget.child),
      ],
    );
  }
}

/// A short, friendly empty state laid over a still ghost of what would be there,
/// for a screen area that has no natural height of its own (the board).
class GuideEmptyOverGhost extends StatelessWidget {
  const GuideEmptyOverGhost({
    super.key,
    required this.ghost,
    required this.title,
    required this.message,
    this.action,
  });

  final Widget ghost;
  final String title;
  final String message;
  final GuideEmptyAction? action;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return Stack(
      children: [
        Positioned.fill(child: GuideGhostArea(pulsing: false, child: ghost)),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, textAlign: TextAlign.center, style: t.sectionTitle),
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    style: t.body.copyWith(color: context.g.mutedText, height: 1.5)),
                if (action != null) ...[
                  const SizedBox(height: 16),
                  GuidePrimaryButton(
                    label: action!.label,
                    icon: action!.icon,
                    expand: false,
                    onPressed: action!.onPressed,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// An error laid over a frozen ghost: a short message and Retry.
class GuideErrorOverGhost extends StatelessWidget {
  const GuideErrorOverGhost({super.key, required this.ghost, required this.message, required this.onRetry});

  final Widget ghost;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return Stack(
      children: [
        Positioned.fill(child: GuideGhostArea(pulsing: false, child: ghost)),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message,
                    textAlign: TextAlign.center,
                    style: t.body.copyWith(color: context.g.mutedText, height: 1.5)),
                const SizedBox(height: 14),
                GuideSecondaryButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The ghost of the modal "working" dialog (replaces a spinner while a Cloud Function
/// runs): a card with the message and two breathing bars. Not dismissible by itself;
/// the caller pops it, exactly as it popped the spinner.
class GuideBusyDialog extends StatelessWidget {
  const GuideBusyDialog({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    return PopScope(
      canPop: false,
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: g.surface,
            borderRadius: BorderRadius.circular(GuideShape.dialogRadius),
            border: Border.all(color: g.border),
            boxShadow: g.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle(style: t.cardTitle, child: Text(message)),
              const SizedBox(height: 14),
              const GuideGhostArea(
                child: Column(
                  children: [
                    GuideGhostBar(height: 12),
                    SizedBox(height: 8),
                    GuideGhostBar(width: 120, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
