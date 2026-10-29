import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PriorityHub.dart';
import 'package:folk_guide_app/Pages/StudentDoubtsPage.dart';
import 'package:folk_guide_app/main.dart' show guideNavigatorKey;
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/NotificationRouter.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/StudentDoubts.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/UnseenDot.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// STUDENTS' DOUBTS (Guide app): the third category in Priority students. A list of the doubts students sent to their
// guide (unanswered first, newest first, an orange dot on each unopened one), a dialog with the highlighted paragraph +
// the question + an answer field, Send saves the answer on the student's doubt; scope per role; the dot trail.

AdminProfile profile(String id, String role, {String team = ''}) => AdminProfile.fromMap({
      'id': id,
      'displayName': '$id Das',
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

final t1 = Timestamp.fromDate(DateTime(2026, 10, 1, 9));
final t2 = Timestamp.fromDate(DateTime(2026, 10, 2, 9));
final t3 = Timestamp.fromDate(DateTime(2026, 10, 3, 9));
final t4 = Timestamp.fromDate(DateTime(2026, 10, 4, 9));

Future<void> doubt(
  FakeFirebaseFirestore db,
  String id, {
  required String uid,
  required String name,
  String scopeGuide = 'G',
  String scopeTeam = 'G',
  String scopeGender = 'male',
  String mode = 'guide',
  String question = 'What does this mean?',
  Timestamp? askedAt,
  String? answer,
  String book = 'Bhagavad-gita As It Is',
  String text = 'eternal',
  String paragraph = 'The soul is eternal and never dies.',
}) =>
    db.collection('bookDoubts').doc(id).set({
      'uid': uid,
      'studentName': name,
      'bookKey': 'book_1',
      'level': 'level-1',
      'bookTitle': book,
      'chapterIndex': 1,
      'text': text,
      'paragraph': paragraph,
      'question': question,
      'mode': mode,
      'status': answer == null ? 'pending' : 'answered',
      'askRound': 1,
      'askedAt': askedAt ?? t1,
      'createdAt': askedAt ?? t1,
      'scopeGuide': scopeGuide,
      'scopeTeam': scopeTeam,
      'scopeGender': scopeGender,
      if (answer != null) ...{'answer': answer, 'answeredBy': 'guide', 'answeredByName': 'Harinam Das', 'answeredAt': t2},
    });

/// The world: G's own student, a Male Enabler M1's student (team G), an unassigned boy, another team's boy, an unassigned
/// girl, F1's girl. Plus an AI doubt that no guide sees.
Future<FakeFirebaseFirestore> world() async {
  final db = FakeFirebaseFirestore();
  await doubt(db, 'd1', uid: 's1', name: 'Arjun Kumar', question: 'Why is the soul eternal?', askedAt: t1);
  await doubt(db, 'd2', uid: 's2', name: 'Bhima Sen', scopeGuide: 'M1', scopeTeam: 'G', question: 'What is karma?', askedAt: t2);
  await doubt(db, 'd3', uid: 's3', name: 'Chaitanya Das', scopeGuide: '', scopeTeam: '', question: 'Who is the Lord?', askedAt: t3);
  await doubt(db, 'd4', uid: 's4', name: 'Dhruva Nair', scopeGuide: 'G2', scopeTeam: 'G2', question: 'Another team doubt', askedAt: t3);
  await doubt(db, 'd5', uid: 's5', name: 'Gauri Devi', scopeGuide: '', scopeTeam: '', scopeGender: 'female', question: 'An unassigned girl doubt', askedAt: t3);
  await doubt(db, 'd6', uid: 's6', name: 'Radha Das', scopeGuide: 'F1', scopeTeam: '', scopeGender: 'female', question: 'F1 girl doubt', askedAt: t3);
  await doubt(db, 'ai1', uid: 's1', name: 'Arjun Kumar', mode: 'ai', question: 'An AI doubt', askedAt: t4);
  return db;
}

Future<Set<String>> idsFor(FakeFirebaseFirestore db, AdminProfile p) async {
  GuideDb.useForTests(db);
  AdminProfileProvider.instance.debugSet(p);
  final list = await StudentDoubts.stream().firstWhere((_) => true);
  return {for (final d in list) d.id};
}

Future<void> settleLoad(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await letDataArrive(tester, frames: 6);
  }
}

Future<FakeFirebaseFirestore> openPage(WidgetTester tester, {FakeFirebaseFirestore? db, double scale = 1.0, bool dark = false, String? openId, bool realMarkers = false}) async {
  await prepareApp(tester, seeded: false);
  final fs = db ?? await world();
  GuideDb.useForTests(fs);
  if (realMarkers) SeenMarkers.debugDisable = false;
  StudentDoubts.debugDisable = false;
  await pumpScreen(tester, StudentDoubtsPage(openDoubtId: openId), scale: scale, dark: dark);
  await settleLoad(tester);
  return fs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
    SeenMarkers.debugDisable = false;
    StudentDoubts.debugDisable = false;
  });

  // ---------------------------------------------------------------------------------------------- the data
  group('the doubt', () {
    test('only a doubt sent to the guide, with a question, is one; the preview is short', () {
      expect(StudentDoubt.fromDoc('a', {'mode': 'ai', 'question': 'Q'}), isNull);
      expect(StudentDoubt.fromDoc('a', {'mode': 'guide', 'question': '  '}), isNull);
      final d = StudentDoubt.fromDoc('a', {'mode': 'guide', 'question': 'x' * 200, 'uid': 's1', 'studentName': ' Arjun ', 'status': 'answered', 'answer': 'A', 'askedAt': t1})!;
      expect(d.preview.length, 90);
      expect(d.preview.endsWith('…'), isTrue);
      expect(d.studentName, 'Arjun');
      expect(d.answered, isTrue);
      expect(StudentDoubt.fromDoc('a', {'mode': 'guide', 'question': 'Q', 'status': 'answered', 'answer': '   '})!.answered, isFalse);
      expect(StudentDoubt.fromDoc('a', {'mode': 'guide', 'question': 'Q'})!.studentName, 'A student');
    });

    test('newest first', () {
      StudentDoubt mk(String id, Timestamp at) => StudentDoubt.fromDoc(id, {'mode': 'guide', 'question': id, 'askedAt': at})!;
      final order = StudentDoubt.sorted([mk('old', t1), mk('new', t4), mk('mid', t2)]).map((d) => d.id).toList();
      expect(order, ['new', 'mid', 'old']);
    });

    test('only UNANSWERED doubts are listed: an answered one is never in the stream (the answer stays on the document)', () async {
      final db = await world();
      await doubt(db, 'done', uid: 's1', name: 'Arjun Kumar', question: 'Answered one', askedAt: t4, answer: 'Yes.');
      expect(await idsFor(db, profile('H', 'HOD')), {'d1', 'd2', 'd3', 'd4', 'd5', 'd6'});
      final kept = (await db.collection('bookDoubts').doc('done').get()).data()!;
      expect(kept['answer'], 'Yes.', reason: 'saved on the student doubt, so it stays in their Notes');
      expect(kept['status'], 'answered');
    });

    test('a dot: unanswered and not opened since asked; a re-ask after opening shows again; answered never', () {
      StudentDoubt mk({Timestamp? at, String? answer}) =>
          StudentDoubt.fromDoc('d', {'mode': 'guide', 'question': 'Q', 'askedAt': at, if (answer != null) ...{'status': 'answered', 'answer': answer}})!;
      expect(StudentDoubts.isUnseen(mk(at: t2), const {}), isTrue);
      expect(StudentDoubts.isUnseen(mk(at: t2), {'d': t3}), isFalse, reason: 'opened after it was asked');
      expect(StudentDoubts.isUnseen(mk(at: t4), {'d': t3}), isTrue, reason: 're-asked after it was opened');
      expect(StudentDoubts.isUnseen(mk(at: t2, answer: 'A'), const {}), isFalse, reason: 'answered');
      expect(StudentDoubts.isUnseen(mk(at: null), const {}), isTrue, reason: 'just sent: the server time has not landed');
    });
  });

  // ---------------------------------------------------------------------------------------------- scope
  group('each admin sees only the doubts of students they may see', () {
    test('HOD: every guide doubt (not the AI ones)', () async {
      expect(await idsFor(await world(), profile('H', 'HOD')), {'d1', 'd2', 'd3', 'd4', 'd5', 'd6'});
    });
    test('Guide G: his team and the unassigned boys - not another team, not the girls', () async {
      expect(await idsFor(await world(), profile('G', 'GUIDE')), {'d1', 'd2', 'd3'});
    });
    test('Male Enabler M1: own students and the unassigned boys', () async {
      expect(await idsFor(await world(), profile('M1', 'MALE_ENABLER', team: 'G')), {'d2', 'd3'});
    });
    test('Female Enabler F1: her own girls and the unassigned girls only', () async {
      expect(await idsFor(await world(), profile('F1', 'FEMALE_ENABLER')), {'d5', 'd6'});
    });
  });

  // ---------------------------------------------------------------------------------------------- the list
  group('the list', () {
    testWidgets('HOD: every waiting doubt, newest first; an answered one is not listed; the summary counts the waiting ones', (tester) async {
      final db = await world();
      await doubt(db, 'd7', uid: 's1', name: 'Arjun Kumar', question: 'Already answered one', askedAt: t4, answer: 'Yes.');
      await openPage(tester, db: db);
      tester.view.physicalSize = const Size(360, 4000); // tall enough that every card is built
      await letDataArrive(tester);
      expect(find.text("Students' doubts"), findsOneWidget);
      expect(find.text('6 doubts waiting for you'), findsOneWidget);
      double y(String id) => tester.getTopLeft(find.byKey(ValueKey('doubt-$id'))).dy;
      // newest first (d3 / d4 / d5 / d6 at t3 first, then d2 at t2, d1 at t1)
      expect(y('d2'), lessThan(y('d1')));
      expect(y('d3'), lessThan(y('d2')));
      expect(find.byKey(const ValueKey('doubt-d7')), findsNothing, reason: 'answered: not listed, although it is the newest');
    });

    testWidgets('a card: the student, a preview, the book and when, the status', (tester) async {
      await openPage(tester);
      final card = find.byKey(const ValueKey('doubt-d1'));
      await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: card, matching: find.text('Arjun Kumar')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Why is the soul eternal?')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Bhagavad-gita As It Is')), findsOneWidget);
    });

    testWidgets('Guide G: only his own scope is listed', (tester) async {
      final db = await world();
      await prepareApp(tester, who: Who.guide, seeded: false);
      GuideDb.useForTests(db);
      AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE'));
      await pumpScreen(tester, const StudentDoubtsPage());
      await settleLoad(tester);
      expect(find.text('3 doubts waiting for you'), findsOneWidget);
      expect(find.byKey(const ValueKey('doubt-d4')), findsNothing);
      expect(find.byKey(const ValueKey('doubt-d5')), findsNothing);
      expect(find.byKey(const ValueKey('doubt-ai1')), findsNothing);
    });

    testWidgets('no doubts: a plain message', (tester) async {
      await openPage(tester, db: FakeFirebaseFirestore());
      expect(find.byKey(const ValueKey('doubts-empty')), findsOneWidget);
    });

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('text $scale ${dark ? 'dark' : 'light'}: the list fits', (tester) async {
          await openPage(tester, scale: scale, dark: dark);
          expectNoOverflow(tester);
          await tester.scrollUntilVisible(find.byKey(const ValueKey('doubt-d1')), 200, scrollable: find.byType(Scrollable).first);
          final r = tester.getRect(find.byKey(const ValueKey('doubt-d1')));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
          expect(r.height, greaterThanOrEqualTo(48));
        });
      }
    }
  });

  // ---------------------------------------------------------------------------------------------- answering
  group('answering a doubt', () {
    testWidgets('tap: the paragraph with the passage highlighted, the question and an answer field; Send needs an answer', (tester) async {
      await openPage(tester);
      await tester.tap(find.byKey(const ValueKey('doubt-d3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('doubt-dialog')), findsOneWidget);
      expect(find.text('Chaitanya Das'), findsWidgets);
      expect(find.byKey(const ValueKey('doubt-question')), findsOneWidget);
      expect(find.text('Who is the Lord?'), findsWidgets);
      final passage = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('doubt-passage')), matching: find.byType(Text)));
      final spans = passage.textSpan!.toPlainText();
      expect(spans, 'The soul is eternal and never dies.');
      final marked = (passage.textSpan! as TextSpan).children!.whereType<TextSpan>().where((s) => s.style?.backgroundColor != null).map((s) => s.text).toList();
      expect(marked, ['eternal'], reason: 'the student\'s passage is the highlighted part');
      expect(find.byKey(const ValueKey('doubt-answer-field')), findsOneWidget);
      // empty: Send is disabled
      await tester.tap(find.byKey(const ValueKey('doubt-send')));
      await tester.pump();
      final snap = await GuideDb.instance.collection('bookDoubts').doc('d3').get();
      expect(snap.data()!['status'], 'pending', reason: 'nothing sent without an answer');
    });

    testWidgets('Send: the answer is saved on the student\'s doubt, marked answered, by this guide; the dialog closes', (tester) async {
      await openPage(tester);
      await tester.tap(find.byKey(const ValueKey('doubt-d3')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('doubt-answer-field')), '  The Lord is Krishna.  ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('doubt-send')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await letDataArrive(tester);
      final d = (await GuideDb.instance.collection('bookDoubts').doc('d3').get()).data()!;
      expect(d['status'], 'answered');
      expect(d['answer'], 'The Lord is Krishna.');
      expect(d['answeredBy'], 'guide');
      expect(d['answeredByName'], 'Harinam Das', reason: 'the answering admin\'s name (HOD in this harness)');
      expect(d['answeredAt'], isNotNull);
      expect(d['uid'], 's3', reason: 'the student\'s own fields are untouched');
      expect(d['question'], 'Who is the Lord?');
      expect(find.byKey(const ValueKey('doubt-dialog')), findsNothing);
      expect(find.text('Answer sent to Chaitanya Das'), findsOneWidget);
      expect(find.byKey(const ValueKey('doubt-d3')), findsNothing, reason: 'answered: it has left the list');
      expect(find.text('5 doubts waiting for you'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // the banner leaves
      await tester.pumpAndSettle();
    });

    test('the update writes exactly the fields the rules allow', () async {
      final db = await world();
      GuideDb.useForTests(db);
      await StudentDoubts.answer(doubtId: 'd1', text: 'Because.', me: profile('G', 'GUIDE'));
      final after = (await db.collection('bookDoubts').doc('d1').get()).data()!;
      final before = (await world()).collection('bookDoubts').doc('d1');
      final b = (await before.get()).data()!;
      final changed = {for (final k in after.keys) if (b[k] != after[k]) k};
      expect(changed, {'answer', 'answeredBy', 'answeredByName', 'answeredAt', 'status'});
      expect(() => StudentDoubts.answer(doubtId: 'd1', text: '  ', me: profile('G', 'GUIDE')), throwsArgumentError);
    });

    testWidgets('answering removes the doubt from the list at once and clears its dot; the answer stays saved on the doubt', (tester) async {
      await openPage(tester, realMarkers: true);
      tester.view.physicalSize = const Size(360, 4000);
      await letDataArrive(tester);
      expect(find.byKey(const ValueKey('doubt-dot-d3')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doubt-d3')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('doubt-answer-field')), 'The Lord is Krishna.');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('doubt-send')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await letDataArrive(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('doubt-d3')), findsNothing);
      expect(find.byKey(const ValueKey('doubt-dot-d3')), findsNothing);
      expect(find.text('5 doubts waiting for you'), findsOneWidget);
      final saved = (await GuideDb.instance.collection('bookDoubts').doc('d3').get()).data()!;
      expect(saved['answer'], 'The Lord is Krishna.', reason: 'still on the student doubt (their Notes)');
    });

    testWidgets('another admin answering a doubt removes it live from a list that is already open; the last one empties it', (tester) async {
      final db = FakeFirebaseFirestore();
      await doubt(db, 'a', uid: 's1', name: 'Arjun Kumar', question: 'First?', askedAt: t2);
      await doubt(db, 'b', uid: 's1', name: 'Arjun Kumar', question: 'Second?', askedAt: t1);
      await openPage(tester, db: db);
      expect(find.text('2 doubts waiting for you'), findsOneWidget);
      await db.collection('bookDoubts').doc('a').update({'status': 'answered', 'answer': 'By another admin', 'answeredBy': 'guide', 'answeredByName': 'G Das', 'answeredAt': t3});
      await settleLoad(tester);
      expect(find.byKey(const ValueKey('doubt-a')), findsNothing);
      expect(find.text('1 doubt waiting for you'), findsOneWidget);
      await db.collection('bookDoubts').doc('b').update({'status': 'answered', 'answer': 'Also answered', 'answeredBy': 'guide', 'answeredByName': 'G Das', 'answeredAt': t3});
      await settleLoad(tester);
      expect(find.byKey(const ValueKey('doubts-empty')), findsOneWidget);
    });

    testWidgets('a notification about a doubt that was already answered says so instead of opening it', (tester) async {
      final db = await world();
      await doubt(db, 'gone', uid: 's1', name: 'Arjun Kumar', question: 'Answered one', askedAt: t4, answer: 'Yes.');
      await openPage(tester, db: db, openId: 'gone');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('That doubt has already been answered'), findsOneWidget);
      expect(find.byKey(const ValueKey('doubt-dialog')), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('a failed send keeps the dialog and the typed answer, and says so', (tester) async {
      final db = await world();
      await openPage(tester, db: db);
      await db.collection('bookDoubts').doc('d3').delete(); // update on a missing document fails
      await tester.tap(find.byKey(const ValueKey('doubt-d3')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('doubt-answer-field')), 'My answer');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('doubt-send')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await letDataArrive(tester);
      expect(find.byKey(const ValueKey('doubt-send-error')), findsOneWidget);
      expect(find.text('My answer'), findsOneWidget);
    });

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('text $scale ${dark ? 'dark' : 'light'}: the dialog fits and Send is reachable', (tester) async {
          final db = await world();
          await doubt(db, 'd8', uid: 's1', name: 'Arjun Kumar', question: 'A longer question about the passage that wraps onto several lines when the text is large. ' * 2, askedAt: t4);
          await openPage(tester, db: db, scale: scale, dark: dark);
          await tester.tap(find.byKey(const ValueKey('doubt-d8')));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const ValueKey('doubt-answer-field')), 'ok');
          await tester.pump();
          expectNoOverflow(tester);
          final box = tester.getRect(find.byType(AlertDialog));
          expect(box.right, lessThanOrEqualTo(360));
          expect(box.bottom, lessThanOrEqualTo(800));
          await tester.ensureVisible(find.byKey(const ValueKey('doubt-send')));
          expect(tester.getRect(find.byKey(const ValueKey('doubt-send'))).height, greaterThanOrEqualTo(48));
        });
      }
    }

    testWidgets('a notification about one doubt opens it straight away', (tester) async {
      await openPage(tester, openId: 'd2');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('doubt-dialog')), findsOneWidget);
      expect(find.text('Bhima Sen'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------------------------- the dot trail
  group('the orange-dot trail: Analysis tab -> Priority students -> Students\' doubts -> each doubt', () {
    Future<List<bool>> collect(Stream<bool> s) async {
      final out = <bool>[];
      final sub = s.listen(out.add);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await sub.cancel();
      return out;
    }

    setUp(() {
      SeenMarkers.debugDisable = false;
      UnseenAggregates.debugDisable = false;
      StudentDoubts.debugDisable = false;
    });

    test('the aggregate (Analysis tab / Priority card / category row) shows while any doubt is waiting, per role', () async {
      final db = await world();
      GuideDb.useForTests(db);
      AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE'));
      expect((await collect(UnseenAggregates.studentDoubtsUnseen('G', false))).last, isTrue);
      AdminProfileProvider.instance.debugSet(profile('F1', 'FEMALE_ENABLER'));
      expect((await collect(UnseenAggregates.studentDoubtsUnseen('F1', false))).last, isTrue);
      // an admin with nothing in scope sees no dot
      AdminProfileProvider.instance.debugSet(profile('M9', 'MALE_ENABLER', team: 'G9'));
      final db2 = FakeFirebaseFirestore();
      await doubt(db2, 'x', uid: 's4', name: 'Dhruva', scopeGuide: 'G2', scopeTeam: 'G2');
      GuideDb.useForTests(db2);
      expect((await collect(UnseenAggregates.studentDoubtsUnseen('M9', false))).last, isFalse);
    });

    test('each doubt has its own dot; opening one clears only that one', () async {
      final db = await world();
      GuideDb.useForTests(db);
      AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE'));
      Future<Set<String>> ids() async {
        Set<String> last = {};
        final sub = StudentDoubts.unseenIds('G').listen((s) => last = s);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await sub.cancel();
        return last;
      }

      expect(await ids(), {'d1', 'd2', 'd3'});
      await db.collection('seenMarkers').doc('G').set({'studentDoubts': {'d1': t4}});
      expect(await ids(), {'d2', 'd3'});
    });

    test('it clears when the doubt is answered - and only then (or when opened); the push is not part of it', () async {
      final db = await world();
      GuideDb.useForTests(db);
      AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE'));
      Future<bool> any() async => (await collect(UnseenAggregates.studentDoubtsUnseen('G', false))).last;
      expect(await any(), isTrue);
      // nothing about notifications is stored or read: dismissing a push cannot change the answer
      await db.collection('bookDoubts').doc('d1').update({'status': 'answered', 'answer': 'A', 'answeredBy': 'guide'});
      expect(await any(), isTrue, reason: 'd2 and d3 are still waiting');
      await db.collection('bookDoubts').doc('d2').update({'status': 'answered', 'answer': 'A', 'answeredBy': 'guide'});
      await db.collection('bookDoubts').doc('d3').update({'status': 'answered', 'answer': 'A', 'answeredBy': 'guide'});
      expect(await any(), isFalse, reason: 'all answered');
    });

    test('opening them all clears the aggregate; a student asking again shows it again', () async {
      final db = await world();
      GuideDb.useForTests(db);
      AdminProfileProvider.instance.debugSet(profile('G', 'GUIDE'));
      Future<bool> any() async => (await collect(UnseenAggregates.studentDoubtsUnseen('G', false))).last;
      await db.collection('seenMarkers').doc('G').set({'studentDoubts': {'d1': t4, 'd2': t4, 'd3': t4}});
      expect(await any(), isFalse);
      await db.collection('bookDoubts').doc('d1').update({'askedAt': Timestamp.fromDate(DateTime(2026, 10, 9)), 'askRound': 2});
      expect(await any(), isTrue, reason: 're-asked after it was opened');
    });

    testWidgets('the list: a dot on each unopened doubt; opening one clears its dot (markers written)', (tester) async {
      await openPage(tester, realMarkers: true);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('doubt-d1')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const ValueKey('doubt-dot-d1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doubt-d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('doubt-close')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await letDataArrive(tester);
      final marker = (await GuideDb.instance.collection('seenMarkers').doc('H').get()).data()!;
      expect((marker['studentDoubts'] as Map).containsKey('d1'), isTrue);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('doubt-d1')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const ValueKey('doubt-dot-d1')), findsNothing, reason: 'its own dot is gone');
      expect(find.byKey(const ValueKey('doubt-dot-d2')).evaluate().length + find.byKey(const ValueKey('doubt-dot-d3')).evaluate().length, greaterThan(0), reason: 'the others still show theirs');
    });

    testWidgets('the Priority hub: a third row, "Students\' doubts", with a dot while a doubt waits; it opens the list', (tester) async {
      await prepareApp(tester, seeded: false);
      final db = await world();
      GuideDb.useForTests(db);
      SeenMarkers.debugDisable = false;
      UnseenAggregates.debugDisable = false;
      await pumpScreen(tester, const PriorityHubPage());
      await settleLoad(tester);
      expect(find.text("Students' doubts"), findsOneWidget);
      expect(find.text('Interactions needed'), findsWidgets);
      expect(find.text('Flagged messages'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('doubts-hub-dot')), matching: find.byType(UnseenDot)), findsOneWidget);
      await tester.tap(find.text("Students' doubts"));
      await tester.pumpAndSettle();
      expect(find.text('6 doubts waiting for you'), findsOneWidget);
    });

    testWidgets('the Priority hub: no dot when everything is answered', (tester) async {
      await prepareApp(tester, seeded: false);
      final db = FakeFirebaseFirestore();
      await doubt(db, 'd1', uid: 's1', name: 'Arjun', answer: 'Done');
      GuideDb.useForTests(db);
      SeenMarkers.debugDisable = false;
      UnseenAggregates.debugDisable = false;
      await pumpScreen(tester, const PriorityHubPage());
      await settleLoad(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('doubts-hub-dot')), matching: find.byType(UnseenDot)), findsNothing);
    });

    for (final scale in kScales) {
      testWidgets('text $scale: the hub with three rows fits', (tester) async {
        await prepareApp(tester, seeded: false);
        GuideDb.useForTests(await world());
        SeenMarkers.debugDisable = false;
        UnseenAggregates.debugDisable = false;
        await pumpScreen(tester, const PriorityHubPage(), scale: scale);
        await settleLoad(tester);
        expectNoOverflow(tester);
      });
    }
  });

  // ---------------------------------------------------------------------------------------------- the notification
  testWidgets('a "guide_doubts" notification opens the list (and that doubt when it names one)', (tester) async {
    await prepareApp(tester, seeded: false);
    GuideDb.useForTests(await world());
    StudentDoubts.debugDisable = true;
    phone(tester, 1.0);
    await tester.pumpWidget(MaterialApp(navigatorKey: guideNavigatorKey, home: const Scaffold(body: Text('home'))));
    markAppReady();
    routeNotification({'dest': 'guide_doubts', 'doubtId': 'd2', 'studentUid': 's2', 'studentName': 'Bhima Sen'});
    await tester.pump();
    await settleLoad(tester);
    expect(find.byType(StudentDoubtsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('doubt-dialog')), findsOneWidget);
    expect(find.text('What is karma?'), findsWidgets);
  });
}
