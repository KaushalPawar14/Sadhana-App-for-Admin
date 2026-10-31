import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/Calendar.dart';
import 'package:folk_guide_app/Pages/AssociationManager.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/Pages/StudentDoubtsPage.dart';
import 'package:folk_guide_app/Pages/StudentProfilePage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/PlanTopicActions.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/RecordInteractionDialog.dart';
import 'package:folk_guide_app/widgets/VoiceNoteButton.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

/// TODAY'S ACTION BUTTONS: one button per open topic, opening the exact place for the exact student; it never ticks; "Record interaction" is a plain
/// form (topics, notes, mic, willingness, commitment) whose save writes the same records as the AI path, with no AI pass.

class _FakePlanData extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PendingChanges> pending(String adminId) => const Stream.empty();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => DateTime.utc(2026, 10, 30, 4, 30);
}

PlanPoint pt(String kind, String title, String text, {PlanGroup group = PlanGroup.followUp, bool done = false, String bookId = '', String assocId = '', String doubtId = '', String metric = ''}) =>
    PlanPoint(kind: kind, title: title, text: text, group: group, done: done, bookId: bookId, assocId: assocId, doubtId: doubtId, metric: metric);

PlanItem card(String uid, String name, List<PlanPoint> points, {bool done = false}) => PlanItem(
      id: 'interaction:$uid:2026-10-30',
      kind: 'interaction',
      title: 'Interaction with $name',
      studentName: name,
      studentUid: uid,
      done: done,
      points: points,
      cardGroups: [for (final g in PlanGroup.values) if (points.any((p) => p.group == g)) g],
    );

final _topics = <PlanPoint>[
  pt('concern', 'Worry', 'Sounded discouraged', group: PlanGroup.worry),
  pt('doubt', 'Doubt', 'Unanswered doubt in the Gita', doubtId: 'd1'),
  pt('bookDue', 'Book due', 'Gita (due Fri 30 Oct). Has he finished it?', group: PlanGroup.other, bookId: 's1_level-1_k'),
  pt('meeting', 'Meeting', 'Meeting with him today', group: PlanGroup.other, assocId: 'a1'),
  pt('target_task', 'Chanting target', 'Chanting: 12 → 16', group: PlanGroup.target, metric: 'chanting'),
  pt('target_task', 'Book target', 'Books: 2 → 3', group: PlanGroup.target, metric: 'books'),
  pt('target_task', 'FOLK target', 'FOLK: 4 → 5', group: PlanGroup.target, metric: 'folk'),
  pt('surrender', 'Surrender step', 'Surrender 40%'),
  pt('sadhana_slip', 'His sadhana', 'Waking up late'),
  pt('target_chanting', 'Chanting target', 'Talk about it', group: PlanGroup.target),
  pt('target_books', 'Book target', 'Talk about it', group: PlanGroup.target),
  pt('target_folk', 'FOLK target', 'Talk about it', group: PlanGroup.target),
  pt('meeting_request', 'Meeting', 'He asked to meet', group: PlanGroup.other, assocId: 'a2'),
];

Future<_FakePlanData> _open(WidgetTester tester, PlanDoc doc, {List<NavigatorObserver> observers = const []}) async {
  AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []}));
  final data = _FakePlanData();
  PlanData.instance = data;
  await pumpScreen(tester, const PlanPage(), size: const Size(360, 4000), observers: observers);
  data.controller.add(doc);
  await tester.pump();
  await tester.pump();
  // the blocks are open; a tap on a row shows its topics (and their buttons)
  final rows = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('plan-row-') && !(w.key! as ValueKey<String>).value.startsWith('plan-row-body-'));
  final n = rows.evaluate().length;
  for (var i = 0; i < n; i++) {
    await tester.tap(rows.at(i));
    await tester.pumpAndSettle();
  }
  return data;
}

/// The interactions saved by the guide's form (the seeded database already holds others).
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _manual(FakeFirebaseFirestore db) async => (await db.collection('interactionLogs').where('source', isEqualTo: 'guide_form').get()).docs;

/// Lets the "recorded" snackbar go, then takes the tree down (no timer is left running).
Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

class _Seen extends NavigatorObserver {
  final List<String?> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route.settings.name);
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

  group('which button each topic gets', () {
    test('the seven buttons, by topic', () {
      expect(topicActionOf(_topics[2]), TopicAction.updateBook);
      expect(topicActionOf(_topics[1]), TopicAction.answerDoubt);
      expect(topicActionOf(_topics[3]), TopicAction.openMeeting);
      expect(topicActionOf(_topics[12]), TopicAction.openMeeting);
      expect(topicActionOf(_topics[4]), TopicAction.changeCommitment);
      expect(topicActionOf(_topics[9]), TopicAction.changeCommitment);
      expect(topicActionOf(_topics[5]), TopicAction.assignBook);
      expect(topicActionOf(_topics[10]), TopicAction.assignBook);
      expect(topicActionOf(_topics[6]), TopicAction.openProfile);
      expect(topicActionOf(_topics[11]), TopicAction.openProfile);
      for (final i in [0, 7, 8]) {
        expect(topicActionOf(_topics[i]), TopicAction.recordInteraction, reason: _topics[i].kind);
      }
      expect({for (final a in TopicAction.values) kTopicActionLabels[a]}, {'Update book', 'Assign book', 'Change commitment', 'Open profile', 'Answer doubt', 'Open meeting', 'Record interaction', 'Set LIT'});
    });

    test('the Record-interaction topics of a card are its OPEN interaction topics only (not the doubt, the book, the meeting, the target steps, nor a done one)', () {
      final c = card('s1', 'Ravi', [..._topics, pt('concern', 'Worry', 'old', done: true)]);
      expect(recordTopicsOf(c).map((p) => p.kind).toList(), ['concern', 'surrender', 'sadhana_slip']);
    });

    test('each button opens the right place for the right student', () {
      final c = card('s1', 'Ravi', _topics);
      final book = topicDestinationOf(c, _topics[2])!;
      expect(book.name, 'topic:updateBook');
      final cal = book.page as CalendarPage;
      expect([cal.studentUid, cal.username, cal.startOnBooks, cal.focusBookDocId], ['s1', 'Ravi', true, 's1_level-1_k'], reason: 'his Books, that book selected');
      final assign = topicDestinationOf(c, _topics[5])!;
      expect(assign.name, 'topic:assignBook');
      expect([(assign.page as CalendarPage).studentUid, (assign.page as CalendarPage).startOnBooks, (assign.page as CalendarPage).openAllBookLevels], ['s1', true, true], reason: 'his Books on the assign flow');
      expect((topicDestinationOf(c, _topics[6])!.page as StudentProfilePage).studentUid, 's1');
      expect((topicDestinationOf(c, _topics[1])!.page as StudentDoubtsPage).openDoubtId, 'd1');
      expect((topicDestinationOf(c, _topics[3])!.page as AssociationManagerPage).highlightAssociationId, 'a1');
      expect(topicDestinationOf(c, _topics[4]), isNull, reason: 'the commitments button opens a dialog');
      expect(topicDestinationOf(c, _topics[0]), isNull, reason: 'Record interaction opens a dialog');
    });
  });

  group('on the Today card', () {
    testWidgets('every OPEN topic has its button with its label; a done topic has none; This week has none', (tester) async {
      final c = card('s1', 'Ravi', [_topics[0], _topics[1], pt('surrender', 'Surrender step', 'x', done: true)]);
      await _open(tester, planDoc(today: [c], left: 0));
      expect(find.byKey(ValueKey('plan-action-${c.id}-0')), findsOneWidget);
      expect(find.descendant(of: find.byKey(ValueKey('plan-action-${c.id}-0')), matching: find.text('Record interaction')), findsOneWidget);
      expect(find.descendant(of: find.byKey(ValueKey('plan-action-${c.id}-1')), matching: find.text('Answer doubt')), findsOneWidget);
      expect(find.byKey(ValueKey('plan-action-${c.id}-2')), findsNothing, reason: 'it is done');
      expect(tester.getSize(find.byKey(ValueKey('plan-action-${c.id}-0'))).height, greaterThanOrEqualTo(48));
    });

    testWidgets('AN OVERDUE BOOK: the "Overdue book" topic shows the title, the old due date and the question, with the Update book button; ticked once finished or re-dated (no button)', (tester) async {
      final open = pt('bookDue', 'Overdue book', 'Bhagavad-gita, due Wed 28 Oct. Overdue by 2 days — has he finished it? If not, when will he finish? Set a new date.', group: PlanGroup.other, bookId: 's1_level-1_k');
      final c = card('s1', 'Ravi', [open]);
      await _open(tester, planDoc(today: [c], left: 0));
      expect(tester.widget<Text>(find.byKey(ValueKey('plan-point-title-${c.id}-0'))).data, 'Overdue book', reason: 'the topic, and its chip on the row');
      expect(find.textContaining('Overdue by 2 days — has he finished it? If not, when will he finish? Set a new date.'), findsOneWidget);
      expect(find.textContaining('due Wed 28 Oct'), findsOneWidget);
      expect(find.descendant(of: find.byKey(ValueKey('plan-action-${c.id}-0')), matching: find.text('Update book')), findsOneWidget);
      expect(topicActionOf(open), TopicAction.updateBook);
      final done = card('s1', 'Ravi', [pt('bookDue', 'Overdue book', 'Bhagavad-gita, due Wed 28 Oct. Overdue by 2 days — has he finished it?', group: PlanGroup.other, bookId: 's1_level-1_k', done: true)]);
      await _open(tester, planDoc(today: [done], left: 0));
      expect(find.byKey(ValueKey('plan-action-${done.id}-0')), findsNothing, reason: 'done: ticked, no button');
    });

    testWidgets('a button OPENS the place and NEVER TICKS: the topic and the counts are unchanged', (tester) async {
      await prepareApp(tester);
      final seen = _Seen();
      final c = card('s1', 'Ravi', [_topics[1], _topics[3]]);
      await _open(tester, planDoc(today: [c], left: 0), observers: [seen]);
      final before = find.textContaining('Done 0').evaluate().length;
      await tester.tap(find.byKey(ValueKey('plan-action-${c.id}-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(seen.pushed.last, 'topic:openMeeting', reason: 'the meeting button opened the meeting page');
      expect(find.textContaining('Done 0').evaluate().length, before, reason: 'nothing ticked by the button');
      expect(find.byKey(ValueKey('plan-point-tick-${c.id}-1')), findsNothing);
    });

    PlanPoint lateMeeting({bool done = false}) => const PlanPoint(
        id: 'meeting:a1', kind: 'meeting', group: PlanGroup.other, title: 'Meeting on Thu 29 Oct — not marked completed', assocId: 'a1', late: true,
        text: 'Meeting on Thu 29 Oct (Thu 29 Oct, 5:00 PM) — not marked completed. Was it held? Mark it Completed, with your notes, or Cancelled.');

    testWidgets('A CONFIRMED MEETING NEVER MARKED: its topic has TWO buttons, Completed and Cancelled (48 dp); a normal meeting keeps its one button; a done one has none', (tester) async {
      await prepareApp(tester);
      final c = card('s1', 'Ravi', [lateMeeting(), _topics[3]]);
      await _open(tester, planDoc(today: [c], left: 0));
      expect(find.textContaining('not marked completed').evaluate().length, greaterThan(0));
      for (final k in ['completed', 'cancelled']) {
        expect(find.byKey(ValueKey('plan-meeting-$k-${c.id}-0')), findsOneWidget, reason: k);
        expect(tester.getSize(find.byKey(ValueKey('plan-meeting-$k-${c.id}-0'))).height, greaterThanOrEqualTo(48));
      }
      expect(find.descendant(of: find.byKey(ValueKey('plan-meeting-completed-${c.id}-0')), matching: find.text('Completed')), findsOneWidget);
      expect(find.descendant(of: find.byKey(ValueKey('plan-meeting-cancelled-${c.id}-0')), matching: find.text('Cancelled')), findsOneWidget);
      expect(find.byKey(ValueKey('plan-action-${c.id}-0')), findsNothing, reason: 'not the single Open meeting button');
      expect(find.byKey(ValueKey('plan-action-${c.id}-1')), findsOneWidget, reason: 'the meeting of today keeps its Open meeting button');
      expect(isUnmarkedMeeting(lateMeeting()), isTrue);
      final done = card('s1', 'Ravi', [const PlanPoint(id: 'meeting:a1', kind: 'meeting', group: PlanGroup.other, title: 'x', text: 'y', assocId: 'a1', late: true, done: true)]);
      await _open(tester, planDoc(today: [done], left: 0));
      expect(find.byKey(ValueKey('plan-meeting-completed-${done.id}-0')), findsNothing);
      expect(find.byKey(ValueKey('plan-meeting-cancelled-${done.id}-0')), findsNothing);
    });

    testWidgets('"Completed" asks for the notes and completes the meeting (status completed, the notes of the guide saved); the topic ticks when the server sends it done', (tester) async {
      final db = await prepareApp(tester);
      await db.collection('associations').doc('a1').set({'studentUid': 's1', 'studentName': 'Ravi', 'status': 'confirmed', 'requestedBy': 'student'});
      await db.collection('users').doc('s1').set({'name': 'Ravi', 'commitmentRounds': 12, 'readingCommitmentMinutes': 30, 'guideId': 'G', 'teamGuide': 'G', 'gender': 'male'});
      final c = card('s1', 'Ravi', [lateMeeting()]);
      await _open(tester, planDoc(today: [c], left: 0));
      await tester.tap(find.byKey(ValueKey('plan-meeting-completed-${c.id}-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-meeting-completed-title')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('plan-meeting-notes')), 'Spoke about his japa');
      await tester.tap(find.byKey(const ValueKey('plan-meeting-completed-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect((await db.collection('associations').doc('a1').get()).data()!['status'], 'completed');
      expect((await db.collection('associationGuideNotes').doc('a1').get()).data()?.values.join(' ') ?? '', contains('Spoke about his japa'));
      expect(find.byKey(ValueKey('plan-point-tick-${c.id}-0')), findsNothing, reason: 'the app does not tick: the server does');
      await _finish(tester);
    });

    testWidgets('"Cancelled" asks first (Keep it changes nothing), then deletes the meeting', (tester) async {
      final db = await prepareApp(tester);
      await db.collection('associations').doc('a1').set({'studentUid': 's1', 'studentName': 'Ravi', 'status': 'confirmed', 'requestedBy': 'student'});
      final c = card('s1', 'Ravi', [lateMeeting()]);
      await _open(tester, planDoc(today: [c], left: 0));
      await tester.tap(find.byKey(ValueKey('plan-meeting-cancelled-${c.id}-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-meeting-cancelled-no')));
      await tester.pumpAndSettle();
      expect((await db.collection('associations').doc('a1').get()).exists, isTrue, reason: 'Keep it: nothing changed');
      await tester.tap(find.byKey(ValueKey('plan-meeting-cancelled-${c.id}-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-meeting-cancelled-yes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect((await db.collection('associations').doc('a1').get()).exists, isFalse, reason: 'cancelled: deleted');
      await _finish(tester);
    });

    testWidgets('"Record interaction" opens the form with the student and the open topics ticked; the topic stays unticked until the SERVER sends it done', (tester) async {
      final db = await prepareApp(tester);
      final c = card('s1', 'Ravi', [_topics[0], _topics[7], _topics[1]]);
      final data = await _open(tester, planDoc(today: [c], left: 0));
      await tester.tap(find.byKey(ValueKey('plan-action-${c.id}-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('rec-title')), findsOneWidget);
      expect(find.textContaining('Ravi'), findsWidgets);
      expect(find.byKey(const ValueKey('rec-topic-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-topic-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-topic-2')), findsNothing, reason: 'the doubt is answered with its own button');
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('rec-topic-0'))).value, true);
      await tester.tap(find.byKey(const ValueKey('rec-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(await _manual(db), hasLength(1), reason: 'the real record is saved');
      expect(find.byKey(ValueKey('plan-point-tick-${c.id}-0')), findsNothing, reason: 'the app does not tick: the plan ticks it when the server has the record');
      // the server's plan arrives with the topics done
      data.controller.add(planDoc(today: [card('s1', 'Ravi', [pt('concern', 'Worry', 'Sounded discouraged', group: PlanGroup.worry, done: true), pt('surrender', 'Surrender step', 'Surrender 40%', done: true), _topics[1]])], left: 0));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(ValueKey('plan-point-tick-${c.id}-0')), findsOneWidget);
      await _finish(tester);
    });
  });

  group('the Record-interaction form', () {
    final topics = [_topics[0], _topics[7], _topics[8]];
    Future<FakeFirebaseFirestore> open(WidgetTester tester) async {
      final db = await prepareApp(tester);
      await db.collection('users').doc('s1').set({'name': 'Ravi', 'commitmentRounds': 12, 'readingCommitmentMinutes': 30, 'guideId': 'G', 'teamGuide': 'G', 'gender': 'male'});
      AdminProfileProvider.instance.debugSet(adminProfile(Who.guide));
      await pumpScreen(
        tester,
        Builder(builder: (context) => Scaffold(body: Center(child: ElevatedButton(key: const ValueKey('go'), onPressed: () => showDialog<bool>(context: context, builder: (_) => RecordInteractionDialog(studentUid: 's1', studentName: 'Ravi', topics: topics)), child: const Text('go'))))),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      return db;
    }

    testWidgets('topics ticked, notes, willingness "more" and a new commitment -> ONE interaction by the guide\'s form: no AI queued, covered topics only', (tester) async {
      final db = await open(tester);
      await tester.tap(find.byKey(const ValueKey('rec-topic-1'))); // untick Surrender step
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('rec-notes')), 'He was low because of exams.');
      await tester.tap(find.byKey(const ValueKey('rec-will-more')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rec-commit-toggle')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('rec-rounds')), '16');
      await tester.tap(find.byKey(const ValueKey('rec-save')));
      await tester.pumpAndSettle();
      final logs = await _manual(db);
      expect(logs.length, 1);
      final d = logs.single.data();
      expect([d['studentUid'], d['source'], d['analysis'], d['status'], d['addressed']], ['s1', 'guide_form', 'done', 'approved', true]);
      expect(d.containsKey('preAnalysis'), false, reason: 'no AI');
      expect(d['rawDictation'], 'He was low because of exams.');
      expect(d['willingness'], 'willing');
      expect(d['interactionType'] ?? d['approvedSummary']['interactionType'], 'Call');
      expect((d['topicAnswers'] as List).map((x) => x['topic']).toList(), ['concern', 'sadhana_slip'], reason: 'only what he ticked');
      final u = (await db.collection('users').doc('s1').get()).data()!;
      expect(u['commitmentRounds'], 16, reason: 'the new commitment');
      expect(u['readingCommitmentMinutes'], 30, reason: 'the number he did not type stays');
      await _finish(tester);
    });

    testWidgets('willingness: more / same / less map to willing / neutral / hesitant; "same" is the start', (tester) async {
      expect([for (final w in Willingness.values) w.wire], ['willing', 'neutral', 'hesitant']);
      final db = await open(tester);
      await tester.tap(find.byKey(const ValueKey('rec-will-less')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rec-save')));
      await tester.pumpAndSettle();
      expect((await _manual(db)).single.data()['willingness'], 'hesitant');
      await _finish(tester);
    });

    testWidgets('the mic is there and the words it turns up land in the notes', (tester) async {
      await open(tester);
      final mic = tester.widget<VoiceNoteButton>(find.byType(VoiceNoteButton));
      mic.onText('He said he will chant sixteen.');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('rec-notes'))).controller!.text, 'He said he will chant sixteen.');
      mic.onText('And read more.');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('rec-notes'))).controller!.text, 'He said he will chant sixteen. And read more.');
    });

    testWidgets('NOTHING TICKS WITHOUT A SAVE: with no topic ticked Save is off; Cancel writes nothing', (tester) async {
      final db = await open(tester);
      for (final i in [0, 1, 2]) {
        await tester.tap(find.byKey(ValueKey('rec-topic-$i')));
        await tester.pump();
      }
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('rec-save'))).onPressed, isNull, reason: 'an interaction with no topic would close them all');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await _manual(db), isEmpty);
    });

    testWidgets('a bad commitment is refused with a sentence and nothing is saved', (tester) async {
      final db = await open(tester);
      await tester.tap(find.byKey(const ValueKey('rec-commit-toggle')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('rec-reading')), '5000');
      await tester.tap(find.byKey(const ValueKey('rec-save')));
      await tester.pump();
      expect(find.byKey(const ValueKey('rec-error')), findsOneWidget);
      expect(await _manual(db), isEmpty);
    });
  });
}
