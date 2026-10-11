import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/StartupGate.dart';
import '../utils/StartupTrace.dart';
import '../widgets/GuideGhost.dart';
import '../widgets/GuideSurface.dart';

/// The launch screen: the splash (the app's animation, in the Ink & Brass theme) for a
/// MINIMUM of [minDuration] on every cold start, with ALL the startup work (force-update
/// read, install-source check, cached profile, background re-check) running IN PARALLEL
/// during that time — the splash never adds waiting on top of it.
///
///   - after [minDuration], if the startup decision is ready: straight to the right screen;
///   - if it is not ready yet: the startup ghost (the shape of the app) until it is;
///   - "reduce animations": a static splash (no animation, no fade), still for the full time.
///
/// The decision itself, its order and every route are [StartupGate]'s and the callers' —
/// this widget only decides WHEN to leave and what to show meanwhile.
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({
    super.key,
    required this.start,
    required this.pageFor,
    this.beforeNavigate,
    this.afterNavigate,
    this.minDuration = const Duration(seconds: 2),
  });

  /// The startup work; started the moment the splash is on screen.
  final Future<StartupOutcome> Function() start;

  /// The screen for a decision.
  final Widget Function(StartupOutcome outcome) pageFor;

  /// Runs before the navigation (e.g. signing out an account that is no longer registered).
  final Future<void> Function(StartupOutcome outcome)? beforeNavigate;

  /// Runs right after the navigation (e.g. flushing a queued notification route).
  final void Function(StartupOutcome outcome)? afterNavigate;

  final Duration minDuration;

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _waiting = false; // past the minimum time, decision not ready: show the ghost

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    StartupTrace.mark('splash shown');
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The gentle breathing of the logo; none under "reduce animations".
    if (GuideMotion.reduced(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  Future<void> _run() async {
    // Both start together: the minimum time and the work.
    final minimum = Future<void>.delayed(widget.minDuration);
    var ready = false;
    final decision = widget.start();
    unawaited(decision.then((_) => ready = true, onError: (_) => ready = true));

    await minimum;
    if (!mounted) return;
    StartupTrace.mark('splash minimum time passed (decision ${ready ? 'ready' : 'not ready'})');
    if (!ready) setState(() => _waiting = true);

    // A startup step that fails in an unexpected way must never leave the splash stuck: the
    // admin keeps their session and is asked to try again (the same screen as "offline").
    StartupOutcome outcome;
    try {
      outcome = await decision;
    } catch (_) {
      outcome = const StartupOutcome(StartupTarget.offline);
    }
    if (!mounted) return;
    if (widget.beforeNavigate != null) {
      await widget.beforeNavigate!(outcome);
      if (!mounted) return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => widget.pageFor(outcome)));
    widget.afterNavigate?.call(outcome);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GuideScaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: GuideMotion.of(context, const Duration(milliseconds: 260)),
          child: _waiting
              ? const KeyedSubtree(key: ValueKey('ghost'), child: StartupGhost())
              : KeyedSubtree(key: const ValueKey('splash'), child: _splash(context)),
        ),
      ),
    );
  }

  Widget _splash(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final reduced = GuideMotion.reduced(context);
    final logo = Container(
      width: 184,
      height: 184,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // A soft brass glow behind the animation (the Ink & Brass accent), light and dark.
        gradient: RadialGradient(colors: [g.brass.withValues(alpha: .20), g.brass.withValues(alpha: 0)]),
      ),
      child: SizedBox(
        width: 132,
        height: 132,
        child: Lottie.asset(
          'assets/emoji/splash_screen.json',
          repeat: !reduced,
          animate: !reduced,
        ),
      ),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            reduced
                ? logo
                : FadeTransition(
                    opacity: Tween<double>(begin: .55, end: 1).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                    ),
                    child: logo,
                  ),
            const SizedBox(height: 18),
            Text('FOLK Guides', textAlign: TextAlign.center, style: t.screenTitle.copyWith(fontSize: 34)),
            const SizedBox(height: 10),
            Text(
              "Now it's easy to check Sadhana daily",
              textAlign: TextAlign.center,
              style: t.body.copyWith(height: 1.4, color: g.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ghost of the app's own shape (page header, a block, then rows): what is shown when the
/// splash time is over and the startup decision is not ready yet.
class StartupGhost extends StatelessWidget {
  const StartupGhost({super.key});

  @override
  Widget build(BuildContext context) {
    return GuideGhostArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 28, GuideSpace.pagePadding, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            GuideGhostBar(width: 90, height: 11),
            SizedBox(height: 10),
            GuideGhostBar(width: 220, height: 30),
            SizedBox(height: 26),
            GuideGhostBlock(height: 120),
            SizedBox(height: 14),
            GuideGhostRow(),
            SizedBox(height: 10),
            GuideGhostRow(),
            SizedBox(height: 10),
            GuideGhostRow(),
          ],
        ),
      ),
    );
  }
}
