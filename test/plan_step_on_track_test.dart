import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/PlanData.dart';

// A book target's step whose book is not due yet is ON TRACK: "Ravi — 📖 Gita (1 → 2) · on track — due 30 Nov"; done or without a date it reads as before.

void main() {
  test('THE STEP WORDS: on track with the due date while the book is ahead; unchanged otherwise', () {
    const step = PlanStep(name: 'Ravi', from: 1, to: 2, book: 'Bhagavad-gita', due: '2026-11-30');
    expect(step.onTrack, isTrue);
    expect(step.words, 'Ravi — 📖 Bhagavad-gita (1 → 2) · on track — due 30 Nov');
    expect(const PlanStep(name: 'Ravi', from: 1, to: 2, book: 'Bhagavad-gita').words, 'Ravi — 📖 Bhagavad-gita (1 → 2)');
    expect(const PlanStep(name: 'Ravi', from: 8, to: 12).words, 'Ravi 8 → 12');
    const done = PlanStep(name: 'Ravi', from: 1, to: 2, book: 'Gita', due: '2026-11-30', done: true);
    expect(done.onTrack, isFalse);
    expect(done.words, 'Ravi — 📖 Gita (1 → 2)');
  });

  test('THE DOCUMENT: a step carries its due date from the plan', () {
    final doc = PlanDoc.fromMap({
      'today': {'date': '2026-10-30', 'items': []},
      'week': {'weekOf': '2026-10-26', 'sections': [
        {'id': 'targettasks', 'title': 'Target tasks', 'items': [
          {'id': 'weektarget:t1', 'kind': 'weekTask', 'title': 'Reading 4 by 31 Dec', 'steps': [
            {'name': 'Ravi', 'from': 1, 'to': 2, 'done': false, 'book': 'Bhagavad-gita', 'due': '2026-11-30'},
            {'name': 'Hari', 'from': 0, 'to': 1, 'done': false},
          ]},
        ]},
      ]},
    });
    final steps = doc.sections.firstWhere((s) => s.id == 'targettasks').items.single.steps;
    expect([steps[0].onTrack, steps[1].onTrack], [true, false]);
    expect(steps[0].dueShort, '30 Nov');
  });
}
