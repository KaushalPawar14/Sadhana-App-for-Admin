/// AI text arrives with a little Markdown in it (`**bold**`, `*italic*`, `- bullets`, `1. steps`, `## headings`, backticks).
/// The guide must never see those symbols. This file turns such text into [AiBlock]s (what `AiText` draws) or into clean
/// plain text (what goes into an editable field).
///
/// SAFE BY CONSTRUCTION: the result is only text and two flags (bold, italic). A link keeps its words and drops its address,
/// HTML tags are removed, code is kept as ordinary text; nothing here can open, run or fetch anything.
library;

enum AiBlockKind { paragraph, bullet, numbered, heading }

/// A run of text with one style.
class AiSpan {
  const AiSpan(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;

  @override
  bool operator ==(Object other) => other is AiSpan && other.text == text && other.bold == bold && other.italic == italic;

  @override
  int get hashCode => Object.hash(text, bold, italic);

  @override
  String toString() => '${bold ? 'B' : ''}${italic ? 'I' : ''}"$text"';
}

/// One paragraph, list item or heading.
class AiBlock {
  const AiBlock(this.kind, this.spans, {this.level = 0, this.number = 0, this.gap = false});

  final AiBlockKind kind;
  final List<AiSpan> spans;

  /// Heading: 1-6. List item: nesting depth (0 = top).
  final int level;

  /// Numbered item: its number as written.
  final int number;

  /// A blank line came before this block.
  final bool gap;

  String get text => spans.map((s) => s.text).join();

  @override
  String toString() => '$kind(level $level, #$number, gap $gap): $spans';
}

final RegExp _fence = RegExp(r'^\s*(```|~~~)');
final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$');
final RegExp _headingMark = RegExp(r'^\s{0,3}(#{1,6})\s');
final RegExp _bullet = RegExp(r'^(\s*)[-*+•●▪‣]\s+(.*)$');
final RegExp _numbered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
final RegExp _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
final RegExp _quote = RegExp(r'^\s{0,3}>\s?');
final RegExp _tableSeparator = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');
final RegExp _htmlBreak = RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false);
final RegExp _htmlTag = RegExp(r'</?[a-zA-Z][^<>]*>');

/// Splits [raw] into blocks. Never throws; empty or blank text gives no blocks.
List<AiBlock> parseAiBlocks(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll(_htmlBreak, '\n').replaceAll(_htmlTag, '');
  final blocks = <AiBlock>[];
  var gap = false;
  var inFence = false;

  void paragraph(String line) {
    final spans = parseAiInline(line);
    if (spans.isEmpty) return;
    // Lines of one paragraph stay on their own lines (the AI uses single line breaks on purpose).
    if (!gap && blocks.isNotEmpty && blocks.last.kind == AiBlockKind.paragraph) {
      final last = blocks.removeLast();
      blocks.add(AiBlock(AiBlockKind.paragraph, _merge([...last.spans, const AiSpan('\n'), ...spans]), gap: last.gap));
    } else {
      blocks.add(AiBlock(AiBlockKind.paragraph, spans, gap: gap && blocks.isNotEmpty));
    }
    gap = false;
  }

  for (var line in text.split('\n')) {
    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      if (line.trim().isNotEmpty) paragraph(line.trim());
      continue;
    }
    if (line.trim().isEmpty) {
      gap = true;
      continue;
    }
    line = line.replaceFirst(_quote, '');
    if (_rule.hasMatch(line)) {
      gap = true;
      continue;
    }
    final h = _heading.firstMatch(line);
    if (h != null) {
      final spans = parseAiInline(h.group(1)!);
      if (spans.isNotEmpty) {
        final level = _headingMark.firstMatch(line)!.group(1)!.length;
        blocks.add(AiBlock(AiBlockKind.heading, [for (final s in spans) AiSpan(s.text, bold: true, italic: s.italic)], level: level, gap: gap && blocks.isNotEmpty));
        gap = false;
      }
      continue;
    }
    final n = _numbered.firstMatch(line);
    if (n != null) {
      final spans = parseAiInline(n.group(3)!);
      if (spans.isNotEmpty) {
        blocks.add(AiBlock(AiBlockKind.numbered, spans, level: n.group(1)!.length >= 2 ? 1 : 0, number: int.parse(n.group(2)!), gap: gap && blocks.isNotEmpty));
        gap = false;
      }
      continue;
    }
    final b = _bullet.firstMatch(line);
    if (b != null) {
      final spans = parseAiInline(b.group(2)!);
      if (spans.isNotEmpty) {
        blocks.add(AiBlock(AiBlockKind.bullet, spans, level: b.group(1)!.length >= 2 ? 1 : 0, gap: gap && blocks.isNotEmpty));
        gap = false;
      }
      continue;
    }
    if (line.trimLeft().startsWith('|')) {
      if (_tableSeparator.hasMatch(line)) continue;
      final cells = line.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
      if (cells.isEmpty) continue;
      paragraph(cells.join('  ·  '));
      continue;
    }
    paragraph(line.trim());
  }
  return blocks;
}

/// Inline styling of one line: `**bold**`, `*italic*`, `_italic_`, `***both***`; links keep their words; code and
/// strike-through lose their marks. Stray marks are dropped, so no `*` or backtick is ever left on screen.
List<AiSpan> parseAiInline(String raw) {
  final out = <AiSpan>[];
  _inline(_protectEscapes(raw), false, false, out, 0);
  final merged = _merge([for (final s in out) AiSpan(_restoreEscapes(s.text), bold: s.bold, italic: s.italic)]);
  // Trim the ends so a block never starts or ends with a space.
  if (merged.isNotEmpty) {
    final first = merged.first;
    merged[0] = AiSpan(first.text.replaceFirst(RegExp(r'^[ \t]+'), ''), bold: first.bold, italic: first.italic);
    final last = merged.last;
    merged[merged.length - 1] = AiSpan(last.text.replaceFirst(RegExp(r'[ \t]+$'), ''), bold: last.bold, italic: last.italic);
  }
  return merged.where((s) => s.text.isNotEmpty).toList();
}

class _Rule {
  const _Rule(this.pattern, this.bold, this.italic, this.group, {this.format = true});

  final RegExp pattern;
  final bool bold;
  final bool italic;
  final int group;

  /// false: the inner text is kept but never parsed again (code).
  final bool format;
}

final List<_Rule> _rules = [
  _Rule(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), false, false, 1),
  _Rule(RegExp(r'\[([^\]]+)\]\([^)]*\)'), false, false, 1),
  _Rule(RegExp(r'`+([^`]+)`+'), false, false, 1, format: false),
  _Rule(RegExp(r'\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*'), true, true, 1),
  _Rule(RegExp(r'\*\*(?=\S)(.+?)(?<=\S)\*\*'), true, false, 1),
  _Rule(RegExp(r'(?<!\w)__(?=\S)(.+?)(?<=\S)__(?!\w)'), true, false, 1),
  _Rule(RegExp(r'~~(?=\S)(.+?)(?<=\S)~~'), false, false, 1),
  _Rule(RegExp(r'(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])'), false, true, 1),
  _Rule(RegExp(r'(?<![\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?!\w)'), false, true, 1),
];

void _inline(String s, bool bold, bool italic, List<AiSpan> out, int depth) {
  if (s.isEmpty) return;
  if (depth > 8) {
    out.add(AiSpan(_dropMarks(s), bold: bold, italic: italic));
    return;
  }
  Match? best;
  _Rule? bestRule;
  for (final r in _rules) {
    final m = r.pattern.firstMatch(s);
    if (m != null && (best == null || m.start < best.start)) {
      best = m;
      bestRule = r;
    }
  }
  if (best == null || bestRule == null) {
    out.add(AiSpan(_dropMarks(s), bold: bold, italic: italic));
    return;
  }
  if (best.start > 0) out.add(AiSpan(_dropMarks(s.substring(0, best.start)), bold: bold, italic: italic));
  final inner = best.group(bestRule.group) ?? '';
  if (bestRule.format) {
    _inline(inner, bold || bestRule.bold, italic || bestRule.italic, out, depth + 1);
  } else {
    out.add(AiSpan(inner, bold: bold, italic: italic));
  }
  _inline(s.substring(best.end), bold, italic, out, depth + 1);
}

const String _escapable = r'\`*_{}[]()#+-.!~>|';

/// A backslash then a mark is a literal character: hidden from the pairing rules as a private-use character until the
/// text is final.
String _protectEscapes(String s) => s.replaceAllMapped(
      RegExp(r'\\([\\`*_{}\[\]()#+\-.!~>|])'),
      (m) => String.fromCharCode(0xE000 + _escapable.indexOf(m.group(1)!)),
    );

String _restoreEscapes(String s) => s.replaceAllMapped(
      RegExp('[\\uE000-\\uE020]'),
      (m) => _escapable[m.group(0)!.codeUnitAt(0) - 0xE000],
    );

/// Marks that did not pair up are removed.
String _dropMarks(String s) {
  return s
      .replaceAll(RegExp(r'\*+'), '')
      .replaceAll('`', '')
      .replaceAll('~~', '')
      .replaceAll(RegExp(r'(?<![A-Za-z0-9])__+|__+(?![A-Za-z0-9])'), '');
}

List<AiSpan> _merge(List<AiSpan> spans) {
  final out = <AiSpan>[];
  for (final s in spans) {
    if (s.text.isEmpty) continue;
    if (out.isNotEmpty && out.last.bold == s.bold && out.last.italic == s.italic) {
      out[out.length - 1] = AiSpan(out.last.text + s.text, bold: s.bold, italic: s.italic);
    } else {
      out.add(s);
    }
  }
  return out;
}

/// Clean plain text: the words of [raw] with every Markdown symbol removed. Lists keep a visible marker (`• ` and `1. `),
/// paragraphs keep their blank lines. For editable fields (voice note, interaction text) and anywhere only a `String` fits.
String plainAiText(String? raw) {
  final blocks = parseAiBlocks(raw);
  if (blocks.isEmpty) return '';
  final b = StringBuffer();
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (i > 0) b.write(block.gap || block.kind == AiBlockKind.heading ? '\n\n' : '\n');
    final indent = block.level > 0 && block.kind != AiBlockKind.heading ? '  ' * block.level : '';
    switch (block.kind) {
      case AiBlockKind.bullet:
        b.write('$indent• ${block.text}');
      case AiBlockKind.numbered:
        b.write('$indent${block.number}. ${block.text}');
      case AiBlockKind.heading:
      case AiBlockKind.paragraph:
        b.write(block.text);
    }
  }
  return b.toString();
}

/// Does [raw] contain anything the widget would draw differently from the plain string?
bool hasAiMarkup(String? raw) {
  final blocks = parseAiBlocks(raw);
  if (blocks.length != 1) return blocks.isNotEmpty;
  final b = blocks.first;
  return b.kind != AiBlockKind.paragraph || b.spans.length != 1 || b.spans.first.bold || b.spans.first.italic || b.text != raw!.trim();
}
