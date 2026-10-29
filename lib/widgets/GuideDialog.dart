import 'package:flutter/material.dart';
import '../utils/Responsive.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';

/// The app's dialog: the theme's card (surface, 22 dp radius, hairline), a serif title,
/// 15 dp body text and pill actions. Unlike a bare AlertDialog it always scrolls when
/// the text is large or the keyboard is up, so nothing is ever clipped; actions sit in a
/// row that wraps onto two lines instead of overflowing, each at least 48 dp.
class GuideDialog extends StatelessWidget {
  const GuideDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.icon,
    this.contentPadding,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: GuideSpace.pagePadding, vertical: 24),
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final Widget? icon;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return AlertDialog(
      scrollable: true,
      icon: icon,
      title: title,
      content: content == null
          ? null
          : DefaultTextStyle.merge(style: t.body.copyWith(height: 1.45), child: context.isWide ? SelectionArea(child: content!) : content!),
      contentPadding: contentPadding ?? const EdgeInsets.fromLTRB(24, 12, 24, 8),
      actions: actions,
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowDirection: VerticalDirection.down,
      insetPadding: insetPadding,
      // On a computer a dialog keeps a sensible width and its text can be selected; on a phone it is exactly what it was.
      constraints: context.isWide ? const BoxConstraints(minWidth: 380, maxWidth: kDialogMaxWidth) : null,
    );
  }
}
