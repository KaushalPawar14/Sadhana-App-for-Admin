import 'package:flutter/material.dart';

/// The most recent loudness readings of the voice, 0 (silence) to 1 (loud), oldest first. A fixed number of bars: each new reading
/// pushes the oldest off the left. It notifies its listeners when a reading is added, and only the waveform listens, so a
/// recording repaints this one small strip and nothing else.
class VoiceLevelTrail extends ChangeNotifier {
  VoiceLevelTrail({this.bars = 32}) : _levels = List<double>.filled(bars, 0);

  final int bars;
  final List<double> _levels;

  List<double> get levels => _levels;

  void add(double level) {
    for (var i = 0; i < _levels.length - 1; i++) {
      _levels[i] = _levels[i + 1];
    }
    _levels[_levels.length - 1] = level.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Back to silence (a new recording, or a pause).
  void clear() {
    for (var i = 0; i < _levels.length; i++) {
      _levels[i] = 0;
    }
    notifyListeners();
  }

  /// The loudest reading in the trail: tests and the "is anything being heard" look use it.
  double get peak => _levels.fold(0.0, (a, b) => a > b ? a : b);
}

/// A live waveform of the voice while recording: a row of rounded bars that rise with the loudness and slide left as time goes by.
/// Painted from [trail] directly (nothing is rebuilt), in its own repaint boundary. A level is information, not decoration, so it
/// moves even with reduce-motion; only the bars' own easing is dropped there.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({super.key, required this.trail, required this.colour, this.height = 30, this.paused = false});

  final VoiceLevelTrail trail;
  final Color colour;
  final double height;

  /// Held: the bars rest at a flat low line.
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: paused ? 'Recording paused' : 'Recording; the waveform shows how loud your voice is',
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _WavePainter(trail, colour, paused)),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.trail, this.colour, this.paused) : super(repaint: trail);

  final VoiceLevelTrail trail;
  final Color colour;
  final bool paused;

  @override
  void paint(Canvas canvas, Size size) {
    final n = trail.bars;
    final slot = size.width / n;
    final bar = (slot * .56).clamp(2.0, 6.0);
    final minH = 3.0;
    for (var i = 0; i < n; i++) {
      final level = paused ? 0.0 : trail.levels[i];
      final h = minH + (size.height - minH) * level;
      final x = slot * i + (slot - bar) / 2;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, bar, h), Radius.circular(bar / 2));
      // newer bars (to the right) are stronger
      final fade = .35 + .65 * (i / (n - 1));
      canvas.drawRRect(rect, Paint()..color = colour.withValues(alpha: paused ? .3 : fade));
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.colour != colour || old.paused != paused;
}
