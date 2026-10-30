import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../agent/AgentController.dart';
import '../agent/TaskProgress.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideSurface.dart';

/// The progress card of one task of the assistant: a percentage that rises smoothly with the REAL steps (see [TaskProgress]),
/// a bar, and the steps themselves with the current one marked. On a failure it stops where it was and says why.
///
/// Cheap by design: only the number and the bar change while it runs, in their own repaint boundary, and the number updates from
/// a timer (about 30 times a second while it is moving, once a second while it waits for the guide) rather than from a frame
/// ticker, so a task that is waiting costs no frames at all.
class TaskProgressCard extends StatefulWidget {
  const TaskProgressCard({super.key, required this.entry, this.clock});

  final ProgressEntry entry;

  /// Where the time comes from (a monotonic duration); a test supplies its own. The app uses a stopwatch.
  @visibleForTesting
  final Duration Function()? clock;

  /// A clock for every card at once (tests that build the whole page); null in the app.
  @visibleForTesting
  static Duration Function()? testClock;

  @override
  State<TaskProgressCard> createState() => _TaskProgressCardState();
}

class _TaskProgressCardState extends State<TaskProgressCard> {
  final Stopwatch _watch = Stopwatch()..start();
  final ValueNotifier<int> _percent = ValueNotifier<int>(0);
  Timer? _timer;
  TaskStep? _stepShown;
  TaskOutcome? _outcomeShown;

  TaskProgress get _p => widget.entry.progress;
  Duration _now() => widget.clock?.call() ?? TaskProgressCard.testClock?.call() ?? _watch.elapsed;

  @override
  void initState() {
    super.initState();
    _percent.value = _p.percent;
    _stepShown = _p.step;
    _outcomeShown = _p.outcome;
    _run();
  }

  @override
  void didUpdateWidget(TaskProgressCard old) {
    super.didUpdateWidget(old);
    _run();
  }

  /// Keeps the timer going exactly while the task can still change.
  void _run() {
    if (!_p.active) {
      _timer?.cancel();
      _timer = null;
      _p.tick(_now());
      _percent.value = _p.percent;
      return;
    }
    final every = _p.step == TaskStep.confirming && _p.outcome == TaskOutcome.running ? const Duration(milliseconds: 1000) : const Duration(milliseconds: 33);
    if (_timer != null && _every == every) return;
    _timer?.cancel();
    _every = every;
    _timer = Timer.periodic(every, (_) => _onTick());
  }

  Duration? _every;

  void _onTick() {
    final p = _p.tick(_now());
    if (p != _percent.value) _percent.value = p;
    // a step or the end changed: rebuild the parts that name them, and adjust the timer
    if (_p.step != _stepShown || _p.outcome != _outcomeShown) {
      _stepShown = _p.step;
      _outcomeShown = _p.outcome;
      if (mounted) setState(() {});
      _run();
    } else if (!_p.active) {
      _run();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _percent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final e = widget.entry;
    final p = _p;
    final failed = p.outcome == TaskOutcome.failed;
    final cancelled = p.outcome == TaskOutcome.cancelled;
    final finished = p.outcome == TaskOutcome.done && p.percent >= 100;
    final accent = failed ? g.danger : cancelled ? g.mutedText : finished ? g.success : g.agent;
    final label = failed
        ? 'Not done'
        : cancelled
            ? 'Cancelled'
            : finished
                ? (e.doneText ?? 'Done')
                : (p.step == TaskStep.confirming ? (e.waitingText ?? taskStepLabel(p.step)) : taskStepLabel(p.step));
    final compact = finished;

    final card = Container(
      key: const ValueKey('task-progress'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: g.surface,
        borderRadius: BorderRadius.circular(GuideShape.cardRadius),
        border: Border.all(color: accent.withValues(alpha: .55), width: 1.2),
        boxShadow: g.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(failed ? Icons.error_outline : cancelled ? Icons.block : finished ? Icons.check_circle : Icons.bolt_rounded, size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  key: const ValueKey('task-progress-label'),
                  style: t.cardTitleSmall.copyWith(color: failed || cancelled || finished ? accent : null),
                ),
              ),
              const SizedBox(width: 8),
              RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _percent,
                  builder: (context, value, _) => Text(
                    '$value%',
                    key: const ValueKey('task-progress-percent'),
                    style: t.cardTitle.copyWith(color: accent, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RepaintBoundary(
            child: _Bar(percent: _percent, accent: accent, active: !failed && !cancelled),
          ),
          if (failed && p.failure != null) ...[
            const SizedBox(height: 8),
            Text(_firstSentence(p.failure!), key: const ValueKey('task-progress-failure'), style: t.small.copyWith(color: g.danger, height: 1.4)),
          ] else if (cancelled) ...[
            const SizedBox(height: 8),
            Text(p.failure ?? 'Cancelled — nothing was changed.', style: t.small.copyWith(height: 1.4)),
          ] else if (!compact) ...[
            const SizedBox(height: 10),
            _Steps(current: p.step),
          ],
        ],
      ),
    );
    return GuideAnimatedSize(
      duration: GuideMotion.of(context, GuideMotion.expand),
      child: _Appear(child: card),
    );
  }
}

/// The reason in one sentence: the card says why it stopped; the full words (with any code) are in the message under it.
String _firstSentence(String reason) {
  final t = reason.replaceAll(RegExp(r'\s+'), ' ').trim();
  final m = RegExp(r'^(.+?[.!?])(\s|$)').firstMatch(t);
  final s = m == null ? t : m.group(1)!;
  return s.length > 140 ? '${s.substring(0, 139)}…' : s;
}

/// The bar: a sky-blue gradient fill over a soft track. The fill's width is the percentage itself (it is already smooth), so
/// there is no second animation on top of it.
class _Bar extends StatelessWidget {
  const _Bar({required this.percent, required this.accent, required this.active});

  final ValueListenable<int> percent;
  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return SizedBox(
      height: 9,
      width: double.infinity,
      // painted straight from the percentage: no widget is rebuilt and nothing is laid out while it moves
      child: CustomPaint(
        painter: _BarPainter(
          percent: percent,
          track: g.agentSoft.withValues(alpha: g.isDark ? .6 : 1),
          edge: g.border,
          colours: active ? [g.agentTop, g.agentMid, g.agentBottom] : [accent.withValues(alpha: .7), accent],
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.percent, required this.track, required this.edge, required this.colours}) : super(repaint: percent);

  final ValueListenable<int> percent;
  final Color track;
  final Color edge;
  final List<Color> colours;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.drawRRect(r, Paint()..color = track);
    canvas.drawRRect(
      r,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6,
    );
    final w = size.width * (percent.value / 100).clamp(0.0, 1.0);
    if (w <= 0) return;
    final fill = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), const Radius.circular(8));
    canvas.drawRRect(
      fill,
      Paint()..shader = LinearGradient(colors: colours).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.track != track || old.colours != colours || old.edge != edge;
}

/// The five steps with the current one marked: done ones ticked, the current one in sky blue, the rest quiet.
class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final TaskStep current;

  static const _shown = [TaskStep.understanding, TaskStep.finding, TaskStep.preparing, TaskStep.confirming, TaskStep.saving];
  static const _short = {
    TaskStep.understanding: 'Understand',
    TaskStep.finding: 'Find',
    TaskStep.preparing: 'Prepare',
    TaskStep.confirming: 'Confirm',
    TaskStep.saving: 'Save',
  };

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final s in _shown)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                s.index < current.index ? Icons.check_circle : s == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 14,
                color: s.index < current.index ? g.success : s == current ? g.agent : g.mutedText,
              ),
              const SizedBox(width: 4),
              Text(_short[s]!, style: t.caption.copyWith(color: s == current ? g.text : g.mutedText, fontWeight: s == current ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
      ],
    );
  }
}

/// Eases a card in the first time it is built (fade and a short rise). With reduce-motion it is simply there.
class _Appear extends StatelessWidget {
  const _Appear({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: GuideMotion.of(context, GuideMotion.expand),
      curve: GuideMotion.standard,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child)),
      child: child,
    );
  }
}
