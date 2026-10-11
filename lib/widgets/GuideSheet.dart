import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';

/// Just the grab handle (for a sheet that lays out its own title).
class GuideSheetHandle extends StatelessWidget {
  const GuideSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: context.g.border,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// The top of every bottom sheet: the 42 x 4 grab handle, then a serif title (and an
/// optional muted line under it). One definition instead of a hand-drawn handle and a
/// bold title in each sheet.
class GuideSheetHeader extends StatelessWidget {
  const GuideSheetHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuideSheetHandle(),
        const SizedBox(height: 18),
        Text(title, style: t.sectionTitle),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: t.small),
        ],
      ],
    );
  }
}
