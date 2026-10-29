import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/Responsive.dart';
import 'GuideNav.dart' show GuideNavItem;

/// THE SIDE NAVIGATION of the Guide app on a computer (a window at least [kDesktopMin] wide): the three tabs down the left, the assistant's
/// toggle under them. It replaces the floating pill at the bottom, which only phones and tablets keep. Every item is a 48 dp row with a
/// hover highlight and a pointer cursor; the active one is the brass pill, as in the phone's navigation.
class GuideSideNav extends StatelessWidget {
  const GuideSideNav({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
    required this.assistant,
    required this.assistantOpen,
    required this.onAssistant,
    this.title = 'FOLK Guides',
  });

  final List<GuideNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  /// The assistant's entry (a toggle: it opens the side panel).
  final GuideNavItem assistant;
  final bool assistantOpen;
  final VoidCallback onAssistant;
  final String title;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return Container(
      key: const ValueKey('side-nav'),
      width: kSideNavWidth,
      decoration: BoxDecoration(
        color: g.surface,
        border: Border(right: BorderSide(color: g.mutedText.withValues(alpha: .18))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 22, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 22),
                child: Text(title, style: t.screenTitle.copyWith(fontSize: 22)),
              ),
              for (var i = 0; i < items.length; i++)
                _SideItem(key: ValueKey('side-nav-$i'), item: items[i], active: i == index, onTap: () => onTap(i)),
              const SizedBox(height: 14),
              Divider(color: g.mutedText.withValues(alpha: .2), height: 1),
              const SizedBox(height: 14),
              _SideItem(key: const ValueKey('side-nav-assistant'), item: assistant, active: assistantOpen, onTap: onAssistant),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('Press Enter to send, Shift+Enter for a new line, Esc to close.', style: t.caption),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  const _SideItem({super.key, required this.item, required this.active, required this.onTap});

  final GuideNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final active = widget.active;
    final fg = active ? g.onPrimary : g.text;
    Widget icon = Icon(widget.item.icon, size: 22, color: fg);
    if (widget.item.badge != null) {
      icon = Stack(clipBehavior: Clip.none, children: [icon, Positioned(right: -4, top: -3, child: widget.item.badge!)]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          selected: active,
          label: widget.item.label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: active ? g.primaryGradient : null,
                color: !active && _hover ? g.chipBackground : null,
                borderRadius: BorderRadius.circular(14),
                boxShadow: active ? [BoxShadow(color: g.brassGlow, blurRadius: 14, offset: const Offset(0, 6))] : null,
              ),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong.copyWith(color: fg))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
