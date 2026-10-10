import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

// Design tokens that are not colours. Values: design/guides/README.md Part 3-4 and
// design/guides/pages/*.html.

abstract final class GuideFonts {
  /// Titles and numbers (Fraunces 500 / 600, letter-spacing -0.01em).
  static const String heading = 'Fraunces';

  /// UI and data (Inter 400 / 500 / 600 / 700).
  static const String body = 'Inter';

  /// Used for glyphs the two families do not carry (Devanagari names).
  static const List<String> fallback = ['Satoshi'];
}

abstract final class GuideShape {
  static const double cardRadius = 18;
  static const double tileRadius = 18;
  static const double heroRadius = 22;
  static const double columnRadius = 20;
  static const double chipRadius = 8;
  static const double smallChipRadius = 10;
  static const double iconTileRadius = 12;
  static const double inputRadius = 14;
  static const double dialogRadius = 22;
  static const double sheetRadius = 24;

  static const double roundButton = 40; // top-bar round icon buttons
  static const double touchTarget = 48;
  static const double primaryButtonHeight = 50; // 46-54
  static const double secondaryButtonHeight = 42;

  static const double navHeight = 68;
  static const double navRadius = 34;
  static const double navInset = 20;
  static const double navItem = 48;
}

abstract final class GuideSpace {
  static const double pagePadding = 20;
  static const double cardGap = 12;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  /// Room under a scrolling tab page for the floating navigation bar (plus the
  /// system inset below it).
  static double navClearanceOf(BuildContext context) =>
      GuideShape.navHeight +
      GuideShape.navInset +
      24 +
      MediaQuery.viewPaddingOf(context).bottom;
}

abstract final class GuideMotion {
  static const Duration press = Duration(milliseconds: 130);
  static const double pressScale = 0.97;
  static const Duration entry = Duration(milliseconds: 300);
  static const Duration entryStagger = Duration(milliseconds: 50);
  static const double entryOffset = 14;
  static const Duration navMorph = Duration(milliseconds: 250);
  static const Duration theme = Duration(milliseconds: 300);
  static const Duration expand = Duration(milliseconds: 250);
  static const Duration ghostCrossFade = Duration(milliseconds: 250);
  static const Duration countUp = Duration(milliseconds: 600);
  static const Duration progressFill = Duration(milliseconds: 400);
  static const Curve standard = Curves.easeInOutCubic;
  static const Curve out = Curves.easeOutCubic;

  // The one place the "reduce animations" setting is read. Above the app's
  // MaterialApp there is no MediaQuery yet, so it falls back to the platform.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ??
      PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  static Duration of(BuildContext context, Duration base) =>
      reduced(context) ? Duration.zero : base;
}

/// Sizes of the board (README Part 4, 2-3).
abstract final class GuideBoardTokens {
  static const double columnWidth = 330;
  static const double columnGap = 12;
  static const double peek = 28; // the next column peeks this much
  static const double cardHeight = 60;
}
