import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/AiMarkdown.dart';

/// Samples of what the AI really writes. The rule under test: no Markdown symbol is ever left in the words.
const samples = <String, String>{
  'bold': 'Ask **Arjun** about his *japa* this week.',
  'list': 'Try this:\n- **Call** him on Sunday\n- Share the **new book**\n  - the small one\n* Ask about sleep',
  'numbered': 'Steps:\n1. Open the **profile**\n2. Tap *Interactions*\n3) Save',
  'headings': '## Summary\nHe is doing well.\n\n### Next steps\n- Meet him',
  'code': 'Set the `target` to `16 rounds`.\n```\nsome code\n```',
  'links': 'See [the roadmap](https://example.com/x?a=1) or ![pic](http://e.com/a.png).',
  'html': 'Hello <b>there</b><br>second <script>alert(1)</script> line',
  'strike': 'This is ~~old~~ new and __strong__ and ***both***.',
  'unmatched': 'A stray ** mark and a lone * star and `tick.',
  'table': '| Day | Rounds |\n|---|---|\n| Mon | 16 |',
};

final marks = RegExp(r'[*`]|(?<![A-Za-z0-9])__|~~|^\s{0,3}#{1,6}\s|<\/?[a-z]');

void main() {
  group('no Markdown symbol is left', () {
    samples.forEach((name, raw) {
      test(name, () {
        final plain = plainAiText(raw);
        expect(marks.hasMatch(plain), isFalse, reason: 'plain: $plain');
        for (final b in parseAiBlocks(raw)) {
          expect(marks.hasMatch(b.text), isFalse, reason: 'block: ${b.text}');
        }
        expect(plain, isNotEmpty);
      });
    });
  });

  test('bold and italic become flags', () {
    final b = parseAiBlocks('Ask **Arjun** about his *japa* now').single;
    expect(b.spans, const [
      AiSpan('Ask '),
      AiSpan('Arjun', bold: true),
      AiSpan(' about his '),
      AiSpan('japa', italic: true),
      AiSpan(' now'),
    ]);
    final both = parseAiInline('***both***');
    expect(both.single, const AiSpan('both', bold: true, italic: true));
  });

  test('lists, numbers and headings are blocks', () {
    final blocks = parseAiBlocks('## Plan\nIntro line\n- one\n  - nested\n1. first\n2) second');
    expect(blocks.map((b) => b.kind), [AiBlockKind.heading, AiBlockKind.paragraph, AiBlockKind.bullet, AiBlockKind.bullet, AiBlockKind.numbered, AiBlockKind.numbered]);
    expect(blocks[0].level, 2);
    expect(blocks[0].spans.single.bold, isTrue);
    expect(blocks[3].level, 1);
    expect(blocks[5].number, 2);
  });

  test('plain text keeps list markers, paragraphs and line breaks', () {
    expect(plainAiText('Hello **there**\nsecond line\n\nNew paragraph'), 'Hello there\nsecond line\n\nNew paragraph');
    expect(plainAiText('- a\n- b'), '• a\n• b');
    expect(plainAiText('1. a\n2. b'), '1. a\n2. b');
    expect(plainAiText('## Title\ntext'), 'Title\ntext');
  });

  test('safe: a link keeps its words only, HTML is dropped, nothing is interpreted', () {
    final plain = plainAiText('Open [the roadmap](https://evil.example/steal?x=1) <a href="javascript:alert(1)">now</a> <script>x()</script>');
    expect(plain.contains('http'), isFalse);
    expect(plain.contains('javascript'), isFalse);
    expect(plain.contains('<'), isFalse);
    expect(plain.contains('the roadmap'), isTrue);
  });

  test('ordinary text is unchanged', () {
    expect(plainAiText('Hello there.'), 'Hello there.');
    expect(plainAiText('snake_case_name stays'), 'snake_case_name stays');
    expect(plainAiText('#1 priority today'), '#1 priority today');
    expect(plainAiText('Meet at 5:30 - see you'), 'Meet at 5:30 - see you');
  });

  test('empty and blank', () {
    expect(plainAiText(null), '');
    expect(plainAiText('  \n '), '');
    expect(parseAiBlocks(''), isEmpty);
  });

  test('escaped marks become the plain character', () {
    expect(plainAiText(r'Price \*not bold\*'), 'Price *not bold*');
  });
}
