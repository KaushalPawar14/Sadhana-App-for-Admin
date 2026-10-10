import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'GuideColors.dart';
import 'GuideTokens.dart';
import 'GuideTypography.dart';

/// The Material theme of the whole app, built from the Ink & Brass tokens.
///
/// Every screen inherits it: app bars, cards, dialogs, sheets, inputs, buttons,
/// chips, switches and snack bars all follow the palette without a screen
/// declaring a colour. The new components (`lib/widgets/Guide*.dart`) read the
/// `GuideColors` extension through `context.g`.
abstract final class GuideTheme {
  static final ThemeData light = _build(GuideColors.light, Brightness.light);
  static final ThemeData dark = _build(GuideColors.dark, Brightness.dark);

  static ThemeData _build(GuideColors g, Brightness brightness) {
    final t = GuideTypography(g);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: g.brass,
      onPrimary: g.onPrimary,
      secondary: g.isDark ? g.text : const Color(0xFF1B2A4A),
      onSecondary: g.isDark ? g.pageBackground : Colors.white,
      error: g.danger,
      onError: Colors.white,
      surface: g.surface,
      onSurface: g.text,
      onSurfaceVariant: g.mutedText,
      outline: g.border,
      outlineVariant: g.border,
      surfaceContainerLowest: g.pageBackground,
      surfaceContainerLow: g.surface,
      surfaceContainer: g.surface,
      surfaceContainerHigh: g.chipBackground,
      surfaceContainerHighest: g.chipBackground,
      shadow: Colors.black,
      scrim: g.scrim,
      primaryContainer: g.chipBackground,
      onPrimaryContainer: g.text,
      secondaryContainer: g.chipBackground,
      onSecondaryContainer: g.text,
    );

    final textTheme = TextTheme(
      displayLarge: t.screenTitle,
      displayMedium: t.screenTitle,
      displaySmall: t.topBarTitle,
      headlineLarge: t.screenTitle,
      headlineMedium: t.topBarTitle,
      headlineSmall: t.sectionTitle,
      titleLarge: t.topBarTitle,
      titleMedium: t.cardTitle,
      titleSmall: t.cardTitleSmall,
      bodyLarge: t.body,
      bodyMedium: t.body,
      bodySmall: t.small,
      labelLarge: t.bodyStrong,
      labelMedium: t.small,
      labelSmall: t.caption,
    );

    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
    OutlinedBorder rr(double r) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: GuideFonts.body,
      fontFamilyFallback: GuideFonts.fallback,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: g.pageBackground,
      canvasColor: g.surface,
      cardColor: g.surface,
      dividerColor: g.border,
      disabledColor: g.mutedText.withValues(alpha: .5),
      hintColor: g.mutedText,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[g],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: g.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: t.topBarTitle,
        iconTheme: IconThemeData(color: g.text),
        actionsIconTheme: IconThemeData(color: g.text),
        systemOverlayStyle: g.isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: g.pageBackground,
                systemNavigationBarIconBrightness: Brightness.light)
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: g.pageBackground,
                systemNavigationBarIconBrightness: Brightness.dark),
      ),
      cardTheme: CardThemeData(
        color: g.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GuideShape.cardRadius),
          side: BorderSide(color: g.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: g.mutedText,
        textColor: g.text,
        titleTextStyle: t.bodyStrong,
        subtitleTextStyle: t.small,
        minVerticalPadding: 8,
      ),
      dividerTheme: DividerThemeData(color: g.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: g.text),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: g.text,
          minimumSize: const Size(GuideShape.touchTarget, GuideShape.touchTarget),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: g.brass,
          foregroundColor: g.onPrimary,
          disabledBackgroundColor: g.chipBackground,
          disabledForegroundColor: g.mutedText,
          elevation: 0,
          shadowColor: g.brassGlow,
          minimumSize: const Size(64, GuideShape.primaryButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: pill,
          textStyle: t.button,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: g.brass,
          foregroundColor: g.onPrimary,
          disabledBackgroundColor: g.chipBackground,
          disabledForegroundColor: g.mutedText,
          minimumSize: const Size(64, GuideShape.primaryButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: pill,
          textStyle: t.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: g.text,
          side: BorderSide(color: g.border),
          minimumSize: const Size(64, GuideShape.secondaryButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: pill,
          textStyle: t.buttonSecondary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: g.brass,
          minimumSize: const Size(48, GuideShape.touchTarget),
          shape: pill,
          textStyle: t.buttonSecondary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: g.brass,
        foregroundColor: g.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: pill,
        extendedTextStyle: t.button,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: g.surface,
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: t.small,
        labelStyle: t.small,
        floatingLabelStyle: t.small.copyWith(color: g.brass),
        helperStyle: t.caption,
        errorStyle: t.caption.copyWith(color: g.danger),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GuideShape.inputRadius),
          borderSide: BorderSide(color: g.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GuideShape.inputRadius),
          borderSide: BorderSide(color: g.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GuideShape.inputRadius),
          borderSide: BorderSide(color: g.brass, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GuideShape.inputRadius),
          borderSide: BorderSide(color: g.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GuideShape.inputRadius),
          borderSide: BorderSide(color: g.danger, width: 1.5),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: g.brass,
        selectionColor: g.brass.withValues(alpha: .3),
        selectionHandleColor: g.brass,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: g.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GuideShape.dialogRadius),
          side: BorderSide(color: g.border),
        ),
        titleTextStyle: t.sectionTitle,
        contentTextStyle: t.body,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: g.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: g.surface,
        elevation: 0,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(GuideShape.sheetRadius)),
          side: BorderSide(color: g.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: g.isDark ? g.chipBackground : const Color(0xFF1B2A4A),
        contentTextStyle: t.body.copyWith(color: GuideColors.heroText),
        actionTextColor: const Color(0xFFE3C071),
        shape: rr(14),
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: g.chipBackground,
        selectedColor: g.brass.withValues(alpha: .18),
        disabledColor: g.chipBackground,
        labelStyle: t.small.copyWith(color: g.text),
        secondaryLabelStyle: t.small.copyWith(color: g.text),
        side: BorderSide(color: g.border),
        shape: rr(GuideShape.chipRadius + 2),
        checkmarkColor: g.brass,
        iconTheme: IconThemeData(color: g.mutedText, size: 18),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? g.onPrimary : g.mutedText),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? g.brass : g.chipBackground),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.transparent : g.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? g.brass : Colors.transparent),
        checkColor: WidgetStatePropertyAll(g.onPrimary),
        side: BorderSide(color: g.mutedText, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? g.brass : g.mutedText),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: g.brass,
        linearTrackColor: g.progressTrack,
        circularTrackColor: g.progressTrack,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: g.brass,
        inactiveTrackColor: g.progressTrack,
        thumbColor: g.brass,
        overlayColor: g.brass.withValues(alpha: .15),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: g.text,
        unselectedLabelColor: g.mutedText,
        labelStyle: t.bodyStrong,
        unselectedLabelStyle: t.body,
        indicatorColor: g.brass,
        dividerColor: g.border,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: g.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: g.border),
        ),
        textStyle: t.body,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: t.body,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(g.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: g.border))),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: g.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: g.surface,
        headerForegroundColor: g.text,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GuideShape.dialogRadius)),
        dayStyle: t.body,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: g.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GuideShape.dialogRadius)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: g.isDark ? g.chipBackground : const Color(0xFF1B2A4A),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: t.caption.copyWith(color: GuideColors.heroText),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: g.mutedText,
        collapsedIconColor: g.mutedText,
        textColor: g.text,
        collapsedTextColor: g.text,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? g.brass.withValues(alpha: .18)
                  : Colors.transparent),
          foregroundColor: WidgetStatePropertyAll(g.text),
          side: WidgetStatePropertyAll(BorderSide(color: g.border)),
          textStyle: WidgetStatePropertyAll(t.buttonSecondary),
        ),
      ),
    );
  }
}

extension GuideThemeContext on BuildContext {
  /// The palette of the current theme.
  GuideColors get g => Theme.of(this).extension<GuideColors>() ?? GuideColors.light;

  /// The type scale for the current palette.
  GuideTypography get gText => GuideTypography(g);
}
