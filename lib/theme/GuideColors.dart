import 'package:flutter/material.dart';

/// The one place every colour of the "Ink & Brass" design lives.
///
/// Values come from design/guides/pages/*.html (HTML wins over the PNGs) and
/// design/guides/README.md Part 3. Screens read them through `context.g`
/// (see GuideTheme.dart); no screen declares a colour of its own.
@immutable
class GuideColors extends ThemeExtension<GuideColors> {
  const GuideColors({
    required this.isDark,
    required this.pageBackground,
    required this.pageFadeTop,
    required this.pageFadeMid,
    required this.surface,
    required this.border,
    required this.cardShadow,
    required this.columnSurface,
    required this.columnSurfaceFolk,
    required this.columnSurfaceUnassigned,
    required this.text,
    required this.mutedText,
    required this.chipBackground,
    required this.progressTrack,
    required this.brass,
    required this.primaryGradient,
    required this.onPrimary,
    required this.brassGlow,
    required this.navGradient,
    required this.groupFolk,
    required this.groupHostel,
    required this.groupLocalite,
    required this.eventMandatory,
    required this.eventPersonal,
    required this.eventExam,
    required this.eventFestival,
    required this.eventProgram,
    required this.eventOther,
    required this.bandExam,
    required this.bandFestival,
    required this.bandProgram,
    required this.ghostFill,
    required this.danger,
    required this.success,
    required this.warning,
    required this.attention,
    required this.scrim,
  });

  final bool isDark;

  // Page.
  final Color pageBackground;
  final Color pageFadeTop; // alpha at 0 px
  final Color pageFadeMid; // alpha at 170 px (0 at 360 px)

  // Cards and surfaces.
  final Color surface;
  final Color border;
  final List<BoxShadow> cardShadow;
  final Color columnSurface;
  final Color columnSurfaceFolk; // the faint top tint of the FOLK column
  final Color columnSurfaceUnassigned; // ... and of the Unassigned column

  // Text.
  final Color text;
  final Color mutedText;
  final Color chipBackground;
  final Color progressTrack;

  // Brass accent and the primary gradient.
  final Color brass;
  final LinearGradient primaryGradient;
  final Color onPrimary;
  final Color brassGlow;

  // Navigation bar.
  final LinearGradient navGradient;

  // Student groups.
  final GuideGroupColors groupFolk;
  final GuideGroupColors groupHostel;
  final GuideGroupColors groupLocalite;

  // Calendar events (dots) and the bands behind multi-day ranges.
  final Color eventMandatory;
  final Color eventPersonal;
  final Color eventExam;
  final Color eventFestival;
  final Color eventProgram;
  final Color eventOther;
  final Color bandExam;
  final Color bandFestival;
  final Color bandProgram;

  // Loading placeholders.
  final Color ghostFill;

  // Status colours (used sparingly: errors, success, attention).
  final Color danger;
  final Color success;
  final Color warning;

  // The small dot that says there is something new (unseen content).
  final Color attention;

  // Behind modal sheets and dialogs.
  final Color scrim;

  // ---------------------------------------------------------------- constants
  // The same in light and dark (README: "Hero card gradient (same in BOTH themes)").
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B2A4A), Color(0xFF2C4170)],
  );
  static const Color heroText = Color(0xFFF4F1EA);
  static const Color heroMuted = Color(0xB8F4F1EA); // rgba(244,241,234,.72)
  static const Color heroLabel = Color(0xFFE3C071);
  static const Color heroDivider = Color(0x29F4F1EA); // .16
  static const Color heroShadow = Color(0x381B2A4A); // rgba(27,42,74,.22)
  static const List<Color> heroRings = [
    Color(0x38E3C071), // .22
    Color(0x29E3C071), // .16
    Color(0x1AE3C071), // .10
  ];

  // Text on the pastel widgets, in both themes.
  static const Color onPastel = Color(0xFF14192B);
  static const Color onPastelMuted = Color(0xFF565B6C);
  static const Color pastelBorder = Color(0x0D14192B); // rgba(20,25,43,.05)
  static const Color pastelIconTile = Color(0x9EFFFFFF); // rgba(255,255,255,.62)
  static const Color pastelAccent = Color(0xFFA9812F); // brass icons on a pastel widget (light brass in both themes)

  // Navigation bar text.
  static const Color navInactive = Color(0x9EF4F1EA); // rgba(244,241,234,.62)
  static const Color navBorder = Color(0x14FFFFFF); // .08
  static const Color navShadow = Color(0x4D0A0F23); // rgba(10,15,35,.30)

  /// A pastel widget (same in light and dark; ABCDE has its own darker dark set).
  LinearGradient pastel(GuidePastel p, {bool abcde = false}) {
    final dark = isDark && abcde;
    final c = dark ? _pastelDark[p]! : _pastelLight[p]!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: c,
    );
  }

  static const Map<GuidePastel, List<Color>> _pastelLight = {
    GuidePastel.sand: [Color(0xFFFBF1D9), Color(0xFFF0DDB0)],
    GuidePastel.slate: [Color(0xFFE8EEF8), Color(0xFFCBD8EE)],
    GuidePastel.sage: [Color(0xFFE8F3EB), Color(0xFFCFE4D5)],
    GuidePastel.clay: [Color(0xFFF8E9E2), Color(0xFFEBCBBE)],
    GuidePastel.mauve: [Color(0xFFEFEBF6), Color(0xFFD9D1EC)],
  };
  static const Map<GuidePastel, List<Color>> _pastelDark = {
    GuidePastel.sand: [Color(0xFFE2D4A9), Color(0xFFD0B67B)],
    GuidePastel.slate: [Color(0xFFCAD3E4), Color(0xFFAABCD9)],
    GuidePastel.sage: [Color(0xFFCBD9CF), Color(0xFFAEC8B6)],
    GuidePastel.clay: [Color(0xFFDDCBC4), Color(0xFFCCAA9D)],
    GuidePastel.mauve: [Color(0xFFD3CEDE), Color(0xFFBAB1D2)],
  };

  GuideGroupColors group(GuideGroup g) => switch (g) {
        GuideGroup.folk => groupFolk,
        GuideGroup.hostel => groupHostel,
        GuideGroup.localite => groupLocalite,
      };

  /// The faint top tint of a board column: green for the FOLK column, cool for
  /// Unassigned, the plain column surface for every other column.
  Color columnTint(GuideColumnTone tone) => switch (tone) {
        GuideColumnTone.folk => columnSurfaceFolk,
        GuideColumnTone.unassigned => columnSurfaceUnassigned,
        GuideColumnTone.plain => columnSurface,
      };

  Color eventColor(GuideEventType t) => switch (t) {
        GuideEventType.mandatory => eventMandatory,
        GuideEventType.personal => eventPersonal,
        GuideEventType.exam => eventExam,
        GuideEventType.festival => eventFestival,
        GuideEventType.program => eventProgram,
        GuideEventType.other => eventOther,
      };

  /// The soft band behind a multi-day range, or null (mandatory / personal /
  /// other: a dot only).
  Color? eventBand(GuideEventType t) => switch (t) {
        GuideEventType.exam => bandExam,
        GuideEventType.festival => bandFestival,
        GuideEventType.program => bandProgram,
        _ => null,
      };

  // ------------------------------------------------------------------ themes
  static const light = GuideColors(
    isDark: false,
    pageBackground: Color(0xFFF6F4EF),
    pageFadeTop: Color(0x2BA9812F), // .17
    pageFadeMid: Color(0x12A9812F), // .07
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE4E0D6),
    cardShadow: [
      BoxShadow(color: Color(0x0A14192B), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x0F14192B), blurRadius: 26, offset: Offset(0, 10)),
    ],
    columnSurface: Color(0xFFEFEBE1),
    columnSurfaceFolk: Color(0xFFE1EEE5),
    columnSurfaceUnassigned: Color(0xFFE2E9F4),
    text: Color(0xFF14192B),
    mutedText: Color(0xFF6A6F80),
    chipBackground: Color(0xFFEFEBE1),
    progressTrack: Color(0x1714192B), // .09
    brass: Color(0xFFA9812F),
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD3AA52), Color(0xFFA9812F)],
    ),
    onPrimary: Color(0xFFFFFFFF),
    brassGlow: Color(0x59A9812F), // .35
    navGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1B2A4A), Color(0xFF27396A)],
    ),
    groupFolk: GuideGroupColors(Color(0xFFDDEEE3), Color(0xFF1F6B49)),
    groupHostel: GuideGroupColors(Color(0xFFE4E3F4), Color(0xFF4B4F9C)),
    groupLocalite: GuideGroupColors(Color(0xFFF4DFD6), Color(0xFF9A4526)),
    eventMandatory: Color(0xFF1B2A4A),
    eventPersonal: Color(0xFFA9812F),
    eventExam: Color(0xFFB23A3A),
    eventFestival: Color(0xFF5B5FA8),
    eventProgram: Color(0xFF2F7D5B),
    eventOther: Color(0xFF6A6F80),
    bandExam: Color(0x2BB23A3A), // .17
    bandFestival: Color(0x265B5FA8), // .15
    bandProgram: Color(0x332F7D5B), // .20
    ghostFill: Color(0x1314192B), // .075
    danger: Color(0xFFB23A3A),
    success: Color(0xFF2F7D5B),
    warning: Color(0xFFA9812F),
    attention: Color(0xFFF57C00),
    scrim: Color(0x8014192B),
  );

  static const dark = GuideColors(
    isDark: true,
    pageBackground: Color(0xFF141519),
    pageFadeTop: Color(0x16FFFFFF), // .085
    pageFadeMid: Color(0x09FFFFFF), // .035
    surface: Color(0xFF1D1F25),
    border: Color(0xFF2B2E36),
    cardShadow: [],
    columnSurface: Color(0xFF191A1F),
    columnSurfaceFolk: Color(0xFF232A26),
    columnSurfaceUnassigned: Color(0xFF25272F),
    text: Color(0xFFECE9E1),
    mutedText: Color(0xFF8E93A1),
    chipBackground: Color(0xFF272A31),
    progressTrack: Color(0x1AFFFFFF), // .10
    brass: Color(0xFFC9A24A),
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFDDB75F), Color(0xFFB88A2E)],
    ),
    onPrimary: Color(0xFF1B1405),
    brassGlow: Color(0x59A9812F),
    navGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2A2D35), Color(0xFF1D1F25)],
    ),
    groupFolk: GuideGroupColors(Color(0xFF1F3A2E), Color(0xFF7ED3A8)),
    groupHostel: GuideGroupColors(Color(0xFF2A2C4A), Color(0xFFA9AEF0)),
    groupLocalite: GuideGroupColors(Color(0xFF43271D), Color(0xFFF0A98A)),
    eventMandatory: Color(0xFFECE9E1),
    eventPersonal: Color(0xFFC9A24A),
    eventExam: Color(0xFFE06B6B),
    eventFestival: Color(0xFF8A8FD6),
    eventProgram: Color(0xFF4FB38A),
    eventOther: Color(0xFF8E93A1),
    bandExam: Color(0x42E06B6B), // .26
    bandFestival: Color(0x428A8FD6),
    bandProgram: Color(0x424FB38A),
    ghostFill: Color(0x13FFFFFF), // .075
    danger: Color(0xFFE06B6B),
    success: Color(0xFF4FB38A),
    warning: Color(0xFFC9A24A),
    attention: Color(0xFFFFA43D),
    scrim: Color(0xB3000000),
  );

  @override
  GuideColors copyWith() => this;

  @override
  GuideColors lerp(ThemeExtension<GuideColors>? other, double t) {
    if (other is! GuideColors) return this;
    // The two palettes are switched, not blended: a cross-fade of every field
    // would need the lists and gradients lerped too, and Material's own
    // AnimatedTheme already cross-fades the colours Material draws.
    return t < .5 ? this : other;
  }
}

enum GuidePastel { sand, slate, sage, clay, mauve }

enum GuideGroup { folk, hostel, localite }

enum GuideColumnTone { folk, unassigned, plain }

enum GuideEventType { mandatory, personal, exam, festival, program, other }

@immutable
class GuideGroupColors {
  const GuideGroupColors(this.background, this.foreground);
  final Color background;
  final Color foreground;
}
