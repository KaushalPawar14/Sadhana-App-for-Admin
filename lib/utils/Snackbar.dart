import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';

/// The app's one message banner (a top overlay, gone after three seconds).
///
/// [bg] is the colour the caller has always passed to say what kind of message it
/// is; it picks a TONE from the palette instead of being painted as-is:
/// red = problem, green = done, orange / yellow / amber = heads-up, anything else
/// = neutral. The banner itself is a surface card with a tinted icon tile, so it
/// reads the same in light and dark.
void showSnackbar(BuildContext context, String text, Color bg, IconData icon) {
  final OverlayState overlayState = Overlay.of(context);
  late final OverlayEntry overlayEntry;
  overlayEntry = OverlayEntry(
    builder: (context) {
      final g = context.g;
      final t = context.gText;
      final tone = _toneFor(g, bg);
      return Positioned(
        top: MediaQuery.of(context).viewPadding.top + 16, // below the status bar
        left: 16,
        right: 16,
        child: Semantics(
          liveRegion: true,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: g.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tone.withValues(alpha: .55)),
                boxShadow: const [
                  BoxShadow(color: Color(0x2E14192B), blurRadius: 24, offset: Offset(0, 8)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 20, color: tone),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text, style: t.bodyStrong)),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  overlayState.insert(overlayEntry);

  // Remove the overlay after a delay.
  Future.delayed(const Duration(seconds: 3), () {
    if (overlayEntry.mounted) overlayEntry.remove();
  });
}

Color _toneFor(GuideColors g, Color bg) {
  final hue = HSLColor.fromColor(bg);
  if (hue.saturation < .15) return g.mutedText;
  final h = hue.hue;
  if (h < 20 || h >= 330) return g.danger; // red, pink
  if (h < 70) return g.warning; // orange, amber, yellow
  if (h < 170) return g.success; // green
  return g.brass; // blue, indigo, purple: neutral accent
}
