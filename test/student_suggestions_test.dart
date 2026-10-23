import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/StudentSuggestions.dart';

/// Master 1 B — the guide gets 3–5 suggestions, each with a why and a
/// concrete next step, and only when he asks for them.
///
/// The server drops anything that cannot say what to do and what the first
/// step is. These cover the other half: what the app does with a document
/// that is malformed, or that was written before any of this existed.

void main() {
  Map<String, dynamic> s(String action, String why, String next) =>
      {'action': action, 'why': why, 'next': next};

  group('parsing a generated set', () {
    test('three suggestions come through in order', () {
      final list = parseSuggestions([
        s('Invite him to Sunday', 'no meetings yet', 'Ask him Friday for 5pm'),
        s('Assign book 2', 'book 1 done in May', 'Hand it over at the programme'),
        s('Raise rounds to 4', 'steady on 2', 'Agree 4 from Monday'),
      ]);
      expect(list.length, 3);
      expect(list.first.action, 'Invite him to Sunday');
      expect(list.last.next, 'Agree 4 from Monday');
    });

    test('whitespace is trimmed off every field', () {
      final one = parseSuggestions([s('  Call him  ', '  because  ', '  Tuesday 7pm  ')]);
      expect(one.single.action, 'Call him');
      expect(one.single.why, 'because');
      expect(one.single.next, 'Tuesday 7pm');
    });

    test('a suggestion with no first step is dropped, not shown blank', () {
      final list = parseSuggestions([
        s('Encourage him', 'he seems low', '   '),
        s('Call him', 'no contact in 3 weeks', 'Ring him Tuesday evening'),
      ]);
      expect(list.length, 1, reason: 'a bullet with no step is not a suggestion');
      expect(list.single.action, 'Call him');
    });

    test('a suggestion with no action is dropped too', () {
      expect(parseSuggestions([s('', 'why', 'next')]), isEmpty);
    });

    test('a missing why is kept — the step still stands on its own', () {
      final list = parseSuggestions([
        {'action': 'Call him', 'next': 'Ring him Tuesday'},
      ]);
      expect(list.single.why, '');
      expect(list.single.action, 'Call him');
    });

    test('junk of any shape yields nothing rather than throwing', () {
      expect(parseSuggestions(null), isEmpty);
      expect(parseSuggestions('a string'), isEmpty);
      expect(parseSuggestions([null, 'x', 42, <String, dynamic>{}]), isEmpty);
    });

    test('a suggestion survives being written to Firestore and read back', () {
      final one = parseSuggestions([s('Call him', 'why', 'Tuesday 7pm')]).single;
      final round = StudentSuggestion.from(one.toMap());
      expect(round!.action, 'Call him');
      expect(round.next, 'Tuesday 7pm');
    });
  });

  group('what the card shows', () {
    test('a freshly generated document shows its whole set', () {
      final list = suggestionsOf({
        'suggestions': [
          s('A', 'w', 'n1'),
          s('B', 'w', 'n2'),
          s('C', 'w', 'n3'),
        ],
        'recommendedNextAction': 'A',
      });
      expect(list.length, 3);
    });

    test('a document written before this change still shows something', () {
      // A guide who has not pressed Refresh since the upgrade must not be
      // shown an empty card where his last suggestion used to be.
      final list = suggestionsOf({
        'recommendedNextAction': 'Call him this week',
        'recommendedReasoning': 'no contact in a month',
      });
      expect(list.length, 1);
      expect(list.single.action, 'Call him this week');
      expect(list.single.why, 'no contact in a month');
      expect(list.single.next, 'Call him this week',
          reason: 'the old shape had no separate step; the action was it');
    });

    test('the new list wins over the legacy field when both are present', () {
      final list = suggestionsOf({
        'suggestions': [s('New A', 'w', 'n'), s('New B', 'w', 'n'), s('New C', 'w', 'n')],
        'recommendedNextAction': 'Old single action',
      });
      expect(list.length, 3);
      expect(list.first.action, 'New A');
    });

    test('a student never generated for shows nothing at all', () {
      expect(suggestionsOf(null), isEmpty);
      expect(suggestionsOf(<String, dynamic>{}), isEmpty);
      expect(suggestionsOf({'recommendedNextAction': '   '}), isEmpty);
    });

    test('an empty list falls back rather than showing a blank card', () {
      final list = suggestionsOf({
        'suggestions': <dynamic>[],
        'recommendedNextAction': 'Call him',
      });
      expect(list.single.action, 'Call him');
    });
  });
}
