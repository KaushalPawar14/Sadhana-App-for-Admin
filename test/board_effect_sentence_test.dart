import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/agent/AgentWrites2.dart' show boardColumnSentence;

/// What the assistant says about the FOLK Boys board after adding, changing or removing an admin.
void main() {
  test('each effect is a plain sentence', () {
    expect(boardColumnSentence('created'), ' Their column on the FOLK Boys board was created.');
    expect(boardColumnSentence('updated'), ' Their column on the FOLK Boys board was updated.');
    expect(boardColumnSentence('removed'), ' Their column on the FOLK Boys board was removed.');
    expect(boardColumnSentence('removed', cardsMoved: 1), contains('(1 card moved to Unassigned)'));
    expect(boardColumnSentence('removed', cardsMoved: 4), contains('(4 cards moved to Unassigned)'));
    expect(boardColumnSentence('unchanged'), contains('needed no change'));
    expect(boardColumnSentence('no-board'), contains('has not been opened yet'));
    expect(boardColumnSentence('failed'), contains('corrected automatically'));
  });

  test('an answer that says nothing about the board adds nothing', () {
    expect(boardColumnSentence(null), '');
    expect(boardColumnSentence('something new'), '');
  });
}
