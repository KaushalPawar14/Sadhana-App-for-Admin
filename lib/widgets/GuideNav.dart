import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideSurface.dart';

class GuideNavItem {
  const GuideNavItem({
    required this.icon,
    required this.label,
    this.badge,
  });

  final IconData icon;
  final String label;

  /// An unseen dot drawn over the icon.
  final Widget? badge;
}

/// The floating pill navigation: 20 dp from the sides and the bottom, 68 dp tall,
/// fully rounded, a navy gradient (graphite in dark). The active item grows into a
/// brass pill with icon and label; the others show only their icon.
class GuideFloatingNav extends StatelessWidget {
  const GuideFloatingNav({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<GuideNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          GuideShape.navInset, 0, GuideShape.navInset, GuideShape.navInset + inset),
      child: RepaintBoundary(
        child: Container(
          height: GuideShape.navHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: g.navGradient,
            borderRadius: BorderRadius.circular(GuideShape.navRadius),
            border: Border.all(color: GuideColors.navBorder),
            boxShadow: const [
              BoxShadow(color: GuideColors.navShadow, blurRadius: 32, offset: Offset(0, 16)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                _NavButton(
                  item: items[i],
                  active: i == index,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.onTap});

  final GuideNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final color = active ? g.onPrimary : GuideColors.navInactive;
    final duration = GuideMotion.of(context, GuideMotion.navMorph);

    Widget icon = Icon(item.icon, size: 22, color: color);
    if (item.badge != null) {
      icon = Stack(clipBehavior: Clip.none, children: [
        icon,
        Positioned(right: -4, top: -3, child: item.badge!),
      ]);
    }

    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          curve: GuideMotion.standard,
          constraints: const BoxConstraints(
              minHeight: GuideShape.navItem, minWidth: GuideShape.navItem),
          padding: EdgeInsets.symmetric(horizontal: active ? 20 : 14),
          decoration: BoxDecoration(
            gradient: active ? g.primaryGradient : null,
            borderRadius: BorderRadius.circular(GuideShape.navItem / 2 + 4),
            boxShadow: active
                ? [BoxShadow(color: g.brassGlow, blurRadius: 14, offset: const Offset(0, 6))]
                : null,
          ),
          child: GuideAnimatedSize(
            duration: duration,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                if (active) ...[
                  const SizedBox(width: 8),
                  Text(item.label, maxLines: 1, style: t.navLabel.copyWith(color: color)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
