import 'package:flutter/material.dart';

import 'GuideColors.dart';
import 'GuideTokens.dart';

/// The type scale of the Guide app: Fraunces for titles and numbers, Inter for
/// everything else. Sizes from the README: screen title 34 · top-bar title 22 ·
/// section title 19 · card title 15-16 · body 14 · small 12-13 · label 11
/// (UPPERCASE at the call site, letter-spacing 0.12em, 600).
@immutable
class GuideTypography {
  const GuideTypography(this.colors);

  final GuideColors colors;

  TextStyle _heading(double size, Color color,
      {FontWeight weight = FontWeight.w500, double? height}) {
    return TextStyle(
      fontFamily: GuideFonts.heading,
      fontFamilyFallback: GuideFonts.fallback,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: size * -.01,
      height: height,
      color: color,
    );
  }

  TextStyle _body(double size, Color color,
      {FontWeight weight = FontWeight.w400, double? height}) {
    return TextStyle(
      fontFamily: GuideFonts.body,
      fontFamilyFallback: GuideFonts.fallback,
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
    );
  }

  // Serif.
  TextStyle get greeting => _heading(38, colors.text, height: 1.1);
  TextStyle get screenTitle => _heading(34, colors.text, height: 1.1);
  TextStyle get topBarTitle => _heading(22, colors.text);
  TextStyle get sectionTitle => _heading(19, colors.text);
  TextStyle get columnTitle => _heading(18, colors.text);
  TextStyle get heroNumber =>
      _heading(34, GuideColors.heroText, height: 1);
  TextStyle get stat => _heading(28, colors.text, height: 1);
  TextStyle get letterTile => _heading(22, GuideColors.onPastel, weight: FontWeight.w600);

  // Sans.
  TextStyle get cardTitle => _body(15, colors.text, weight: FontWeight.w600);
  TextStyle get cardTitleSmall => _body(14, colors.text, weight: FontWeight.w600);
  TextStyle get body => _body(14, colors.text);
  TextStyle get bodyStrong => _body(14, colors.text, weight: FontWeight.w600);
  TextStyle get small => _body(13, colors.mutedText);
  TextStyle get caption => _body(12, colors.mutedText);
  TextStyle get button => _body(15, colors.onPrimary, weight: FontWeight.w600);
  TextStyle get buttonSecondary => _body(14, colors.text, weight: FontWeight.w600);
  TextStyle get navLabel => _body(13, colors.onPrimary, weight: FontWeight.w600);
  TextStyle get pill => _body(11, colors.text, weight: FontWeight.w600, height: 1.3);
  TextStyle get pillLegend => _body(12, colors.text, weight: FontWeight.w600, height: 1.3);

  // Text on pastel widgets (always #14192B / #565B6C).
  TextStyle get onPastelTitle =>
      _body(15, GuideColors.onPastel, weight: FontWeight.w600);
  TextStyle get onPastelBody =>
      _body(14, GuideColors.onPastel, weight: FontWeight.w600);
  TextStyle get onPastelSmall => _body(12, GuideColors.onPastelMuted);

  // Text on the navy hero card.
  TextStyle get heroLabel => TextStyle(
        fontFamily: GuideFonts.body,
        fontFamilyFallback: GuideFonts.fallback,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 11 * .12,
        color: GuideColors.heroLabel,
      );
  TextStyle get heroCaption => _body(12, GuideColors.heroMuted);

  // Callers render the text upper-case; this is the style only.
  TextStyle get label => TextStyle(
        fontFamily: GuideFonts.body,
        fontFamilyFallback: GuideFonts.fallback,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 11 * .12,
        color: colors.mutedText,
      );
}
