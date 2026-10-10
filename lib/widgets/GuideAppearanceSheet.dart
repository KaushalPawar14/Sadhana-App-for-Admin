import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/GuideTheme.dart';
import '../theme/ThemeModeController.dart';

/// The Light / Dark / Auto choice, as a bottom sheet. The setting is stored on
/// this device only (see [ThemeModeController]); choosing one changes the theme
/// at once and never changes the tab or the screen behind the sheet.
Future<void> showGuideAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => const _AppearanceSheet(),
  );
}

class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeModeController>();
    final t = context.gText;
    final options = <(GuideThemeMode, IconData, String, String)>[
      (GuideThemeMode.light, Icons.light_mode_outlined, 'Light', 'Warm paper'),
      (GuideThemeMode.dark, Icons.dark_mode_outlined, 'Dark', 'Graphite'),
      (GuideThemeMode.auto, Icons.brightness_auto_outlined, 'Auto', 'Follows your phone'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: t.sectionTitle),
            const SizedBox(height: 12),
            for (final o in options)
              _OptionRow(
                icon: o.$2,
                title: o.$3,
                subtitle: o.$4,
                selected: controller.mode == o.$1,
                onTap: () => controller.setMode(o.$1),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: g.chipBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: g.text),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: t.cardTitle),
                      Text(subtitle, style: t.small),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_rounded, color: g.brass),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
