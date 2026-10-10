import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';

/// The student group a boy belongs to (FOLK / Hostel / Localite), from his `role`
/// field (the residence: "Stay at FOLK" / "Stay at Hostel" / "Stay at Localite").
/// Null when the residence is not one of the three.
GuideGroup? guideGroupOf(String? role) {
  final r = (role ?? '').toLowerCase();
  if (r.contains('folk')) return GuideGroup.folk;
  if (r.contains('hostel')) return GuideGroup.hostel;
  if (r.contains('local')) return GuideGroup.localite;
  return null;
}

String guideGroupLabel(GuideGroup g) => switch (g) {
      GuideGroup.folk => 'FOLK',
      GuideGroup.hostel => 'Hostel',
      GuideGroup.localite => 'Localite',
    };

/// A labelled pill for a group: padding 2x8, radius 8, 11 px / 600 (the legend
/// uses [legend] for 3x10 and 12 px).
class GuideGroupPill extends StatelessWidget {
  const GuideGroupPill({super.key, required this.group, this.legend = false});

  final GuideGroup group;
  final bool legend;

  @override
  Widget build(BuildContext context) {
    final c = context.g.group(group);
    final t = context.gText;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: legend ? 10 : 8, vertical: legend ? 3 : 2),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        guideGroupLabel(group),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (legend ? t.pillLegend : t.pill).copyWith(color: c.foreground),
      ),
    );
  }
}

/// A coloured avatar circle with the initial (34 dp, initial 15 / 700). A boy with
/// no recognised group gets the neutral chip colour.
class GuideGroupAvatar extends StatelessWidget {
  const GuideGroupAvatar({super.key, required this.name, this.group, this.size = 34});

  final String name;
  final GuideGroup? group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final c = group == null ? null : g.group(group!);
    final initial = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c?.background ?? g.chipBackground,
      ),
      child: Text(
        initial,
        style: context.gText.bodyStrong.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: c?.foreground ?? g.mutedText,
        ),
      ),
    );
  }
}

/// The small count badge in a column header or a card header: white-ish chip, 1 px
/// border, radius 10, 12 px / 600.
class GuideCountBadge extends StatelessWidget {
  const GuideCountBadge(this.count, {super.key, this.tinted});

  final int count;

  /// A tint behind the number (an icon tile in This Week); null = surface.
  final Color? tinted;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tinted ?? g.surface,
        border: Border.all(color: g.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$count',
          style: context.gText.bodyStrong.copyWith(fontSize: 12)),
    );
  }
}
