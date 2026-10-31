import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/PlanTopicActions.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

// ONE TOPIC PER BOOK, linked to the book target. The server words it (functions/test/bookTopics.test.js); here: what the guide sees and which buttons it has.

class _Fake extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
}

AdminProfile _me() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

PlanItem card(List<PlanPoint> points) => PlanItem(id: 'student:s1:2026-10-30', kind: 'student', title: 'Ravi', studentName: 'Ravi', studentUid: 's1', points: points, cardGroups: const [PlanGroup.target]);

Future<void> _open(WidgetTester tester, PlanItem c) async {
  AdminProfileProvider.instance.debugSet(_me());
  final data = _Fake();
  PlanData.instance = data;
  await pumpScreen(tester, const PlanPage(), size: const Size(360, 3000));
  data.controller.add(planDoc(today: [c], left: 0));
  await tester.pump();
  await tester.pump();
  await tester.tap(find.byKey(ValueKey('plan-row-${c.id}')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  test('a book target step names the book in This week and the calendar: "Ravi — 📖 Bhagavad-gita (1 → 2)"; a step without a book keeps its numbers', () {
    expect(const PlanStep(name: 'Ravi', from: 1, to: 2, book: 'Bhagavad-gita').words, 'Ravi — 📖 Bhagavad-gita (1 → 2)');
    expect(const PlanStep(name: 'Testing', from: 12, to: 16).words, 'Testing 12 → 16');
    final doc = PlanDoc.fromMap({
      'today': {'date': '2026-10-30', 'items': []},
      'week': {
        'weekOf': '2026-10-26',
        'sections': [
          {
            'id': 'targettasks',
            'title': 'Target tasks',
            'items': [
              {
                'id': 'weektarget:tg1',
                'kind': 'weekTask',
                'title': 'Reading 4 by 31 Dec',
                'steps': [
                  {'name': 'Ravi', 'from': 1, 'to': 2, 'book': 'Bhagavad-gita'},
                  {'name': 'Hari', 'from': 0, 'to': 1},
                ],
              }
            ],
          }
        ],
      },
    });
    final steps = doc.sections.firstWhere((s) => s.id == 'targettasks').items.single.steps;
    expect(steps.map((s) => s.words), ['Ravi — 📖 Bhagavad-gita (1 → 2)', 'Hari 0 → 1']);
  });

  testWidgets('THE BOOK TOPIC: its title, the target line, and BOTH buttons: Update book and Later', (tester) async {
    await prepareApp(tester);
    final c = card(const [
      PlanPoint(
        id: 'book_due:s1:b1',
        kind: 'bookDue',
        group: PlanGroup.other,
        bookId: 'b1',
        bookTitle: 'Bhagavad-gita',
        title: '📖 Bhagavad-gita — overdue by 2 days',
        text: 'Counts for your book target (1 of 4). It was due Wed 28 Oct. Has he finished it? If not, when will he finish? Set a new date.',
      ),
    ]);
    await _open(tester, c);
    expect(find.text('📖 Bhagavad-gita — overdue by 2 days'), findsWidgets);
    expect(find.textContaining('Counts for your book target (1 of 4).'), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('plan-action-${c.id}-0')), matching: find.text('Update book')), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('plan-later-${c.id}-0')), matching: find.text('Later')), findsOneWidget);
    expect(topicActionOf(c.points.first), TopicAction.updateBook);
    expect(laterKeyOf(c.points.first), 'bookDue:b1');
  });

  testWidgets('"📖 Assign a book": the Assign book button and Later; one topic, nothing else about the book', (tester) async {
    await prepareApp(tester);
    final c = card(const [
      PlanPoint(
        id: 'book_next:s1',
        kind: 'target_books',
        group: PlanGroup.target,
        metric: 'books',
        title: '📖 Assign next book',
        text: 'Counts for your book target (2 of 4). He has no current book: assign one, with a finish-by date.',
      ),
    ]);
    await _open(tester, c);
    expect(find.text('📖 Assign next book'), findsWidgets);
    expect(find.descendant(of: find.byKey(ValueKey('plan-action-${c.id}-0')), matching: find.text('Assign book')), findsOneWidget);
    expect(find.byKey(ValueKey('plan-later-${c.id}-0')), findsOneWidget);
    expect(find.byKey(ValueKey('plan-action-${c.id}-1')), findsNothing, reason: 'one topic');
    expect(laterKeyOf(c.points.first), 'target:books');
  });
}
