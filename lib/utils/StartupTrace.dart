import 'package:flutter/foundation.dart';

/// Startup timestamps: milliseconds since `main()` began, printed as `[startup] +NNNms label`
/// (`adb logcat -s flutter | grep startup`). One cheap line per step, in every build, so the real
/// time from launch to the first screen can be read off a device. Nothing here changes behaviour.
class StartupTrace {
  StartupTrace._();

  static final Stopwatch _clock = Stopwatch();
  static final Map<String, int> marks = <String, int>{};

  /// Starts the clock (the first line of `main()`).
  static void start() {
    _clock
      ..reset()
      ..start();
    marks.clear();
    mark('main() entered');
  }

  static void mark(String label) {
    final ms = _clock.elapsedMilliseconds;
    marks[label] = ms;
    debugPrint('[startup] +${ms}ms $label');
  }
}
