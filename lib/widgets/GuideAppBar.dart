import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideSurface.dart';

/// The top bar of a screen that hands a Material-style `appBar:` to [GuideScaffold]:
/// the same look as [GuideTopBar] (a round back button, a serif title, round action
/// buttons, the page behind it) plus an optional [bottom] (a TabBar). Old `AppBar`
/// colour arguments are not accepted: the theme decides.
///
/// [danger] is the "N selected" bar of the multi-select delete mode: a danger-coloured
/// bar with light text.
class GuideAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GuideAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.danger = false,
    this.automaticallyImplyLeading = true,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final bool danger;
  final bool automaticallyImplyLeading;

  static const double _barHeight = GuideShape.touchTarget + 8;

  @override
  Size get preferredSize => Size.fromHeight(_barHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    final canPop = Navigator.of(context).canPop();
    final Widget? lead = leading ??
        (automaticallyImplyLeading && canPop
            ? GuideRoundButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              )
            : null);
    final fg = danger ? g.onPrimary : g.text;
    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding - 4, 8, GuideSpace.pagePadding - 4, 0),
      child: SizedBox(
        height: GuideShape.touchTarget,
        child: Row(
          children: [
            if (lead != null) lead,
            SizedBox(width: lead != null ? 8 : 4),
            Expanded(
              child: DefaultTextStyle(
                style: t.topBarTitle.copyWith(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title ?? const SizedBox.shrink(),
              ),
            ),
            for (final a in actions) a,
          ],
        ),
      ),
    );
    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(color: danger ? g.danger : null),
        child: IconTheme(
          data: IconThemeData(color: fg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bar,
              if (bottom != null) bottom!,
            ],
          ),
        ),
      ),
    );
  }
}
