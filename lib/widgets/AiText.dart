import 'package:flutter/material.dart';

import '../utils/AiMarkdown.dart';

/// The ONE way the Guide app shows text written by the AI. `**bold**`, `*italic*`, bullet and numbered lists, headings and
/// line breaks appear as real formatting in the style the screen already uses (its font, size, colour, light or dark, and the
/// phone's text scale); no `*`, `#` or backtick is ever shown.
///
/// Plain text with no markup is drawn exactly as before (a `Text`, or a `SelectableText` when [selectable]), so a screen
/// that adopts this widget does not change for ordinary sentences.
///
/// Safe: nothing in the text is interactive. A link shows only its words; HTML is dropped (see `utils/AiMarkdown.dart`).
class AiText extends StatelessWidget {
  const AiText(
    this.text, {
    super.key,
    this.style,
    this.selectable = false,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;

  /// The screen's own style; the widget adds bold / italic / heading size on top of it.
  final TextStyle? style;

  /// Selectable and copyable, as the assistant's answers always were.
  final bool selectable;

  /// A card that shows a few lines only: lists then run on as `• one  • two` lines inside one text.
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final blocks = parseAiBlocks(text);
    if (blocks.isEmpty) return const SizedBox.shrink();

    // Plain sentence(s): exactly the widget the screen had before.
    if (blocks.length == 1 && blocks.first.kind == AiBlockKind.paragraph && blocks.first.spans.length == 1 && !blocks.first.spans.first.bold && !blocks.first.spans.first.italic) {
      final plain = blocks.first.text;
      return selectable
          ? SelectableText(plain, style: style, maxLines: maxLines, textAlign: textAlign)
          : Text(plain, style: style, maxLines: maxLines, overflow: overflow, textAlign: textAlign);
    }

    final Widget body;
    if (maxLines != null) {
      body = _rich(_flatSpans(blocks, base), base, maxLines: maxLines, overflow: overflow ?? TextOverflow.ellipsis);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < blocks.length; i++) _block(blocks[i], i, base),
        ],
      );
    }
    return selectable ? SelectionArea(child: body) : body;
  }

  Widget _rich(List<InlineSpan> spans, TextStyle base, {int? maxLines, TextOverflow? overflow}) {
    return Text.rich(
      TextSpan(children: spans, style: base),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }

  List<InlineSpan> _spans(List<AiSpan> spans, TextStyle base, {bool bold = false}) => [
        for (final s in spans)
          TextSpan(
            text: s.text,
            style: TextStyle(
              fontWeight: s.bold || bold ? FontWeight.w700 : null,
              fontStyle: s.italic ? FontStyle.italic : null,
            ),
          ),
      ];

  /// Everything as one run (for [maxLines]): list items become "• item" lines.
  List<InlineSpan> _flatSpans(List<AiBlock> blocks, TextStyle base) {
    final out = <InlineSpan>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) out.add(const TextSpan(text: '\n'));
      switch (b.kind) {
        case AiBlockKind.bullet:
          out.add(const TextSpan(text: '• '));
        case AiBlockKind.numbered:
          out.add(TextSpan(text: '${b.number}. '));
        case AiBlockKind.heading:
        case AiBlockKind.paragraph:
          break;
      }
      out.addAll(_spans(b.spans, base));
    }
    return out;
  }

  Widget _block(AiBlock b, int index, TextStyle base) {
    final fontSize = base.fontSize ?? 14;
    final top = index == 0 ? 0.0 : _gapBefore(b, index);
    switch (b.kind) {
      case AiBlockKind.paragraph:
        return Padding(
          padding: EdgeInsets.only(top: top),
          child: _rich(_spans(b.spans, base), base),
        );
      case AiBlockKind.heading:
        final scale = switch (b.level) { 1 => 1.2, 2 => 1.12, _ => 1.05 };
        final headingStyle = base.copyWith(fontSize: fontSize * scale, fontWeight: FontWeight.w700);
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : top + 2),
          child: _rich(_spans(b.spans, headingStyle), headingStyle),
        );
      case AiBlockKind.bullet:
      case AiBlockKind.numbered:
        final marker = b.kind == AiBlockKind.bullet ? '•' : '${b.number}.';
        return Padding(
          padding: EdgeInsets.only(top: top, left: 12.0 * b.level),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: b.kind == AiBlockKind.bullet ? fontSize * 1.1 : fontSize * 1.7),
                child: Text(marker, style: base),
              ),
              const SizedBox(width: 4),
              Expanded(child: _rich(_spans(b.spans, base), base)),
            ],
          ),
        );
    }
  }

  double _gapBefore(AiBlock b, int index) {
    if (b.gap) return 8;
    return b.kind == AiBlockKind.bullet || b.kind == AiBlockKind.numbered ? 3 : 4;
  }
}
