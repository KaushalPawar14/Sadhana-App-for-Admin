import 'dart:math' as math;

/// The real steps a task of the assistant goes through, in order.
enum TaskStep { understanding, finding, preparing, confirming, saving, done }

enum TaskOutcome { running, done, failed, cancelled }

/// The words of each step, as the guide reads them.
String taskStepLabel(TaskStep s) => switch (s) {
      TaskStep.understanding => 'Understanding your request',
      TaskStep.finding => 'Finding it in the app',
      TaskStep.preparing => 'Preparing the change',
      TaskStep.confirming => 'Waiting for your confirmation',
      TaskStep.saving => 'Saving',
      TaskStep.done => 'Done',
    };

/// A task's PERCENTAGE: it rises smoothly and continuously (1%, 2%, 3% ... never 25 -> 50 -> 90), is driven by the REAL step the
/// task is in, never sits frozen while the task runs, never goes backwards, and reaches 100% only when the task is truly
/// finished. If the task fails (or is cancelled) it stops where it was.
///
/// How: every step owns a band of the bar. While a step lasts, a target creeps through its band and approaches the top of it
/// without ever reaching it (so a step that takes long keeps moving, slowly); the number shown eases toward the target, at a
/// pace that is never zero while it is behind. When a real step event arrives, the target jumps to the next band, and the number
/// simply glides up to it, a percent at a time. Finishing sends the target to 100 and the number runs there quickly.
///
/// Time comes only from [tick]: the caller feeds it the frame times, so the model has no clock of its own and is exactly
/// reproducible in a test. Real events ([enter], [finish], [fail], [cancel]) are noted and applied at the next tick.
class TaskProgress {
  /// The share of the bar each step owns: from, to (percent).
  static const Map<TaskStep, (double, double)> bands = {
    TaskStep.understanding: (0, 22),
    TaskStep.finding: (22, 45),
    TaskStep.preparing: (45, 62),
    TaskStep.confirming: (62, 74),
    TaskStep.saving: (74, 96),
  };

  /// How long a step takes to cover about two thirds of its band, in seconds (the waiting for the guide is slow on purpose).
  static const Map<TaskStep, double> _tau = {
    TaskStep.understanding: 2.2,
    TaskStep.finding: 1.6,
    TaskStep.preparing: 1.8,
    TaskStep.confirming: 18,
    TaskStep.saving: 1.5,
  };

  /// Once a step has lasted longer than it should, the target keeps creeping at this many percent a second (one percent every
  /// eight seconds or so) ...
  static const double creepRate = .12;

  /// ... up to this many percent beyond the top of the step's band.
  static const double creepMax = 14;

  /// The slowest the number may rise while it is behind its target (percent a second): it never stalls.
  static const double minRate = 5;

  /// The fastest it may rise (percent a second): even finishing is a run, not a jump.
  static const double maxRate = 140;

  TaskStep _step = TaskStep.understanding;
  TaskOutcome _outcome = TaskOutcome.running;
  String? _failure;

  TaskStep? _pendingStep;
  TaskOutcome? _pendingOutcome;
  String? _pendingFailure;

  Duration? _stepStart;
  Duration? _last;
  double _shown = 0;
  int _percent = 0;

  TaskStep get step => _step;
  TaskOutcome get outcome => _outcome;

  /// Why the task failed or stopped, in words, when it did.
  String? get failure => _failure;

  /// The percentage as last computed by [tick].
  int get percent => _percent;

  /// Still going: its number may still change.
  bool get active => _outcome == TaskOutcome.running || (_outcome == TaskOutcome.done && _percent < 100) || _pendingOutcome != null;

  /// A real step began. Steps only move forward; a repeat or an earlier one is ignored.
  void enter(TaskStep s) {
    if (_outcome != TaskOutcome.running) return;
    final from = _pendingStep ?? _step;
    if (s.index > from.index && s != TaskStep.done) _pendingStep = s;
  }

  /// The task truly finished.
  void finish() {
    if (_outcome != TaskOutcome.running || _pendingOutcome != null) return; // the first ending wins
    _pendingOutcome = TaskOutcome.done;
  }

  /// The task failed: the number stops where it is and [reason] is shown.
  void fail(String reason) {
    if (_outcome != TaskOutcome.running || _pendingOutcome != null) return;
    _pendingOutcome = TaskOutcome.failed;
    _pendingFailure = reason;
  }

  /// The guide cancelled: the number stops where it is.
  void cancel() {
    if (_outcome != TaskOutcome.running || _pendingOutcome != null) return;
    _pendingOutcome = TaskOutcome.cancelled;
    _pendingFailure = 'Cancelled — nothing was changed.';
  }

  /// Advances to the frame time [t] (a monotonic time, such as a ticker's elapsed) and returns the percentage to show.
  int tick(Duration t) {
    final last = _last ?? t;
    _stepStart ??= t;
    final dt = math.max(0, (t - last).inMicroseconds) / 1e6;
    _last = t;

    final nextOutcome = _pendingOutcome;
    if (nextOutcome != null && _outcome == TaskOutcome.running) {
      _pendingOutcome = null;
      _outcome = nextOutcome;
      _failure = _pendingFailure;
      if (nextOutcome == TaskOutcome.done) _step = TaskStep.done;
    }
    final nextStep = _pendingStep;
    if (nextStep != null && _outcome == TaskOutcome.running) {
      _pendingStep = null;
      _step = nextStep;
      _stepStart = t;
    }

    if (_outcome == TaskOutcome.failed || _outcome == TaskOutcome.cancelled) return _percent; // stopped where it was

    final double target;
    if (_outcome == TaskOutcome.done) {
      target = 100;
    } else {
      final band = bands[_step]!;
      final inStep = math.max(0, (t - _stepStart!).inMicroseconds) / 1e6;
      final tau = _tau[_step]!;
      // Inside its band the target approaches the top of it; and a step that lasts long keeps creeping a little further (never
      // more than [creepMax] over the band), so a long wait is slow, never frozen.
      final creep = math.min(creepMax, creepRate * math.max(0, inStep - tau));
      target = band.$1 + (band.$2 - band.$1) * (1 - math.exp(-inStep / tau)) + creep;
    }

    if (_shown < target) {
      // ease toward the target, but never slower than minRate (no stall) nor faster than maxRate (no jump)
      final eased = (target - _shown) * (1 - math.exp(-dt / .3));
      final step = eased.clamp(minRate * dt, maxRate * dt);
      _shown = math.min(target, _shown + step);
    }
    var p = _shown.floor();
    if (_outcome == TaskOutcome.done) {
      if (_shown >= 99.999) {
        _shown = 100;
        p = 100;
      } else {
        p = math.min(p, 99); // 100 only when it truly arrives
      }
    } else {
      p = math.min(p, 99);
    }
    if (p > _percent) _percent = p; // never backwards
    return _percent;
  }
}
