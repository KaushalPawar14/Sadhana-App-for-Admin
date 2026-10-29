import 'package:flutter/material.dart';

import 'GuideColors.dart';

/// The assistant's SKY-BLUE look, built from the tokens in [GuideColors]: one place for the gradient, the glow and the contrast
/// rule, so the button, the page, the cards and the chips cannot drift apart.
extension AgentLook on GuideColors {
  /// The fill: pale sky blue at the top, a clear sky blue at the bottom (light, never dark).
  LinearGradient get agentGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [agentTop, agentMid, agentBottom],
        stops: const [0, .52, 1],
      );

  /// The same fill on a diagonal, for wide shapes (bubbles, buttons).
  LinearGradient get agentGradientWide => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [agentTop, agentMid, agentBottom],
        stops: const [0, .55, 1],
      );

  /// Black at [alpha]: the depth of the assistant's shadows and shading (kept here, with the other colours of its look).
  Color agentShade(double alpha) => Colors.black.withValues(alpha: alpha);

  /// A soft sky-blue glow under floating things.
  List<BoxShadow> get agentGlow => [
        BoxShadow(color: agentBottom.withValues(alpha: isDark ? .45 : .38), blurRadius: 18, offset: const Offset(0, 8)),
        BoxShadow(color: agentShade(isDark ? .5 : .22), blurRadius: 6, offset: const Offset(0, 3)),
      ];
}

/// WCAG contrast ratio of two opaque colours (1 to 21); text needs 4.5.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}
