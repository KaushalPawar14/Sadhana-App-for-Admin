import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';

/// Master 1 A4 — a books task has to be something the guide can go and do.
///
/// "Move Ravi and Amit from 1 to 2 books" is true but useless: it does not
/// say which book, or whether there even is one open. The server works that
/// out per student; these are the lines it turns into.

void main() {
  // -------------------------------------------------------------------------
  // the wording
  // -------------------------------------------------------------------------
  group('what the guide reads', () {
    test('a student with a book open is asked to finish that book', () {
      const a = BookAction(uid: 'u1', action: BookAction.finish, bookTitle: 'Bhagavad Gita');
      expect(a.describe('Ravi'), 'Ravi: finish Bhagavad Gita');
      expect(a.describe('Ravi', byDay: 'Sunday'), 'Ravi: finish Bhagavad Gita by Sunday');
    });

    test('a student with no book open needs the next one assigned', () {
      const a = BookAction(uid: 'u2', action: BookAction.start);
      expect(a.describe('Amit'), 'Assign the next book to Amit');
    });

    test('a deadline is never attached to "assign" — there is nothing due yet', () {
      const a = BookAction(uid: 'u2', action: BookAction.start);
      expect(a.describe('Amit', byDay: 'Sunday'), isNot(contains('Sunday')));
    });

    test('a name that could not be resolved still reads as a person', () {
      const a = BookAction(uid: 'u3', action: BookAction.finish, bookTitle: 'Gita');
      expect(a.describe(null), 'A student: finish Gita');
      expect(a.describe('  '), 'A student: finish Gita');
    });

    test('a book with no title is still a sentence, not a blank', () {
      const a = BookAction(uid: 'u4', action: BookAction.finish);
      expect(a.describe('Ravi'), 'Ravi: finish their current book');
    });
  });

  // -------------------------------------------------------------------------
  // the deadline
  // -------------------------------------------------------------------------
  group('the day it is due', () {
    // Monday morning's sweep judges the phase, so Sunday is the real
    // deadline — said plainly on the days where "Sunday" would confuse.
    test('most of the week it is simply Sunday', () {
      for (final d in [
        DateTime(2026, 10, 19), // Monday
        DateTime(2026, 10, 21), // Wednesday
        DateTime(2026, 10, 23), // Friday
      ]) {
        expect(phaseDueDayLabel(d), 'Sunday', reason: 'on ${d.weekday}');
      }
    });

    test('on Saturday it is tomorrow, on Sunday it is today', () {
      expect(phaseDueDayLabel(DateTime(2026, 10, 24)), 'tomorrow');
      expect(phaseDueDayLabel(DateTime(2026, 10, 25)), 'today');
    });
  });

  // -------------------------------------------------------------------------
  // reading what the server wrote
  // -------------------------------------------------------------------------
  group('parsing', () {
    test('a well-formed action round-trips', () {
      final a = BookAction.from({
        'uid': 'u1',
        'action': 'finish',
        'bookTitle': 'Gita',
      });
      expect(a, isNotNull);
      expect(a!.uid, 'u1');
      expect(a.action, BookAction.finish);
      expect(a.bookTitle, 'Gita');
      expect(a.toMap()['action'], 'finish');
    });

    test('a null or empty title becomes null, not the string "null"', () {
      expect(BookAction.from({'uid': 'u', 'action': 'start', 'bookTitle': null})!.bookTitle, isNull);
      expect(BookAction.from({'uid': 'u', 'action': 'start', 'bookTitle': '  '})!.bookTitle, isNull);
    });

    test('junk is dropped rather than rendered', () {
      expect(BookAction.from(null), isNull);
      expect(BookAction.from('nope'), isNull);
      expect(BookAction.from({'uid': '', 'action': 'finish'}), isNull);
      expect(BookAction.from({'uid': 'u', 'action': 'explode'}), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // the task that carries them
  // -------------------------------------------------------------------------
  group('on the task', () {
    test('a books task carries one action per student', () {
      final t = CompoundTask.from({
        'type': 'value',
        'fromLevel': 1,
        'toLevel': 2,
        'studentUids': ['a', 'b'],
        'bookActions': [
          {'uid': 'a', 'action': 'finish', 'bookTitle': 'Gita'},
          {'uid': 'b', 'action': 'start', 'bookTitle': null},
        ],
      });
      expect(t!.bookActions.length, 2);
      expect(t.bookActions[0].describe('Ravi', byDay: 'Sunday'),
          'Ravi: finish Gita by Sunday');
      expect(t.bookActions[1].describe('Amit'), 'Assign the next book to Amit');
    });

    test('a plan made before this existed simply has none', () {
      final t = CompoundTask.from({
        'type': 'value',
        'fromLevel': 1,
        'toLevel': 2,
        'studentUids': ['a'],
      });
      expect(t!.bookActions, isEmpty);
      expect(t.describe('books'), contains('from 1 to 2 books'));
      expect(t.toMap().containsKey('bookActions'), isFalse,
          reason: 'nothing added to a doc that never had it');
    });

    test('a chanting task is unaffected', () {
      final t = CompoundTask.from({
        'type': 'value',
        'fromLevel': 2,
        'toLevel': 4,
        'studentUids': ['a'],
      });
      expect(t!.bookActions, isEmpty);
      expect(t.describe('rounds', {'a': 'Ravi'}), 'Move Ravi from 2 to 4 rounds');
    });

    test('actions survive a write back to Firestore', () {
      const t = CompoundTask(
        type: kTaskTypeValue,
        fromLevel: 1,
        toLevel: 2,
        studentUids: ['a'],
        bookActions: [BookAction(uid: 'a', action: BookAction.finish, bookTitle: 'Gita')],
      );
      final round = CompoundTask.from(t.toMap());
      expect(round!.bookActions.single.bookTitle, 'Gita');
    });
  });
}
