import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AssociationManager.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentGuideMe.dart';
import 'package:folk_guide_app/agent/AgentTypes.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

/// THE THREE WAYS TO ADD AN INTERACTION end in the SAME save (`saveInteraction`: one real `interactionLogs` record for THAT student, then ONE notification):
///   DO IT      the assistant saves it from the guide's words (agent_writes_all_test.dart);
///   GUIDE ME   ONE button, "Record interaction — Ravi", opens the form already for Ravi (no "which student?", no Open profile); with nobody named the form opens with a student picker;
///   BY HAND    the Associations page's "Add interaction" button: pick the student (search, his own scope), then the same form.
/// The form: student (pre-filled or picked), what happened (type or the mic), his willingness (optional), the topics to tick when the student has open ones on Today. Plain code: no AI to save.
/// What the server then does with the record (history line, Surrender %, ticks) is proved in functions/test/interactionSave.test.js.

class _Plan extends PlanData {
  _Plan(this.doc);
  final PlanDoc? doc;
  @override
  Stream<PlanDoc?> plan(String adminId) => Stream.value(doc);
}

PlanItem _card(String uid, String name, List<PlanPoint> points) => PlanItem(
      id: 'interaction:$uid:2026-10-30',
      kind: 'interaction',
      title: 'Interaction with $name',
      studentName: name,
      studentUid: uid,
      points: points,
      cardGroups: [PlanGroup.worry],
    );

PlanPoint _worry() => const PlanPoint(kind: 'concern', title: 'Worry', text: 'Sounded discouraged', group: PlanGroup.worry);
PlanPoint _slip() => const PlanPoint(kind: 'sadhana_slip', title: 'His sadhana', text: 'Waking up late', group: PlanGroup.followUp);

GuideButton _button({String uid = '', String name = '', String action = 'record_interaction'}) => GuideButton(action: action, label: 'Record interaction', line: 'Record the talk.', studentUid: uid, studentName: name);

/// A screen with one button that does what tapping a Guide-me button does.
Widget _host(GuideButton b) => Builder(builder: (context) => Scaffold(body: Center(child: ElevatedButton(key: const ValueKey('go'), onPressed: () => openGuideButton(context, b), child: const Text('go')))));

Future<(FakeFirebaseFirestore, List<Map<String, dynamic>>)> _setup(WidgetTester tester, {PlanDoc? plan}) async {
  final db = await prepareApp(tester, who: Who.guide);
  final calls = <Map<String, dynamic>>[];
  HierarchyApi.useForTests((name, args) async {
    calls.add({'_call': name, ...args});
    return <String, dynamic>{};
  });
  PlanData.instance = _Plan(plan);
  addTearDown(() => PlanData.instance = const FirestorePlanData());
  return (db, calls);
}

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _saved(FakeFirebaseFirestore db) async => (await db.collection('interactionLogs').where('source', isEqualTo: 'guide_form').get()).docs;

Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  group('GUIDE ME: the Record interaction button', () {
    testWidgets('with the student named: the form opens ALREADY for him (his name in the title, no picker, no "which student?" message)', (tester) async {
      final (db, calls) = await _setup(tester, plan: planDoc(today: [_card('s1', 'Arjun Kumar', [_worry(), _slip()])], left: 0));
      await pumpScreen(tester, _host(_button(uid: 's1', name: 'Arjun Kumar')));
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('rec-title'))).data, 'Record interaction · Arjun Kumar');
      expect(find.byKey(const ValueKey('rec-student-search')), findsNothing, reason: 'he is already chosen');
      expect(find.textContaining('Tell me which student'), findsNothing);
      expect(find.byKey(const ValueKey('rec-topic-0')), findsOneWidget, reason: 'his open Today topics are offered');
      // type what happened and save: ONE record for Arjun and ONE notification
      await tester.enterText(find.byKey(const ValueKey('rec-notes')), 'He is keen and will chant 12 rounds.');
      await tester.tap(find.byKey(const ValueKey('rec-save')));
      await tester.pumpAndSettle();
      final logs = await _saved(db);
      expect(logs.length, 1);
      final d = logs.single.data();
      expect([d['studentUid'], d['studentName'], d['status'], d['rawDictation'], d['willingness'], d['analysis']], ['s1', 'Arjun Kumar', 'approved', 'He is keen and will chant 12 rounds.', 'neutral', 'done']);
      expect((d['topicAnswers'] as List).map((x) => x['topic']).toList(), ['concern', 'sadhana_slip']);
      expect(calls.where((c) => c['_call'] == 'sendStudentNotification' && c['kind'] == 'interaction_logged').toList(), [
        {'_call': 'sendStudentNotification', 'kind': 'interaction_logged', 'studentUid': 's1'},
      ], reason: 'told once, after the record exists');
      await _finish(tester);
    });

    testWidgets('with NOBODY named: the form opens with a student picker, not a snackbar; picking him fills the title and the topics; Save is off until a student is chosen', (tester) async {
      final (db, calls) = await _setup(tester, plan: planDoc(today: [_card('s2', 'Bhima Sen', [_worry()])], left: 0));
      await pumpScreen(tester, _host(_button()));
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tell me which student'), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('rec-title'))).data, 'Record interaction');
      expect(find.byKey(const ValueKey('rec-student-search')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('rec-save'))).onPressed, isNull, reason: 'no student yet');
      await tester.tap(find.byKey(const ValueKey('rec-student-s2')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('rec-title'))).data, 'Record interaction · Bhima Sen');
      expect(find.byKey(const ValueKey('rec-student-search')), findsNothing);
      expect(find.byKey(const ValueKey('rec-topic-0')), findsOneWidget, reason: 'his open topic from Today');
      await tester.enterText(find.byKey(const ValueKey('rec-notes')), 'Met him after class.');
      await tester.tap(find.byKey(const ValueKey('rec-save')));
      await tester.pumpAndSettle();
      final logs = await _saved(db);
      expect([logs.single.data()['studentUid'], logs.single.data()['studentName']], ['s2', 'Bhima Sen']);
      expect(calls.where((c) => c['kind'] == 'interaction_logged').length, 1);
      await _finish(tester);
    });

    testWidgets('a button that is NOT about recording an interaction and names nobody still says to tell the assistant which student', (tester) async {
      await _setup(tester);
      await pumpScreen(tester, _host(_button(action: 'update_book')));
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pump();
      expect(find.textContaining('Tell me which student'), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-title')), findsNothing);
      await _finish(tester);
    });
  });

  group('ASSOCIATIONS: the Add interaction button', () {
    Future<(FakeFirebaseFirestore, List<Map<String, dynamic>>)> openAssociations(WidgetTester tester, {PlanDoc? plan, double scale = 1.0, bool dark = false, Size size = const Size(360, 800)}) async {
      final r = await _setup(tester, plan: plan);
      await pumpScreen(tester, const AssociationManagerPage(), scale: scale, dark: dark, size: size);
      await tester.pumpAndSettle();
      return r;
    }

    testWidgets('it is there beside New Meeting; it opens the form with a search box and ONLY the guide\'s own students (not another guide\'s girl); typing narrows the list', (tester) async {
      await openAssociations(tester);
      expect(find.byKey(const ValueKey('assoc-add-interaction')), findsOneWidget);
      expect(find.text('New Meeting'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assoc-add-interaction')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-student-search')), findsOneWidget);
      for (final uid in ['s1', 's2', 's6']) {
        expect(find.byKey(ValueKey('rec-student-$uid')), findsOneWidget, reason: uid);
      }
      expect(find.byKey(const ValueKey('rec-student-s5')), findsNothing, reason: 'Gauri Devi is a girl of a Female Enabler: not his student');
      await tester.enterText(find.byKey(const ValueKey('rec-student-search')), 'bhi');
      await tester.pump();
      expect(find.byKey(const ValueKey('rec-student-s2')), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-student-s1')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('rec-student-search')), 'zzz');
      await tester.pump();
      expect(find.byKey(const ValueKey('rec-students-none')), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('pick a student, write what happened, choose his willingness, Save: ONE record for him and ONE notification; the form closes and says so', (tester) async {
      final (db, calls) = await openAssociations(tester);
      await tester.tap(find.byKey(const ValueKey('assoc-add-interaction')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-student-s1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-topic-0')), findsNothing, reason: 'nothing open on Today for him: no topics to tick, and that is fine');
      await tester.enterText(find.byKey(const ValueKey('rec-notes')), 'He was open about his struggles.');
      await tester.tap(find.byKey(const ValueKey('rec-will-less')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rec-save')));
      await tester.pumpAndSettle();
      final logs = await _saved(db);
      expect(logs.length, 1);
      final d = logs.single.data();
      expect([d['studentUid'], d['studentName'], d['source'], d['willingness'], d['addressed'], d['rawDictation']], ['s1', 'Arjun Kumar', 'guide_form', 'hesitant', true, 'He was open about his struggles.']);
      expect(d['topicAnswers'] ?? const [], isEmpty);
      expect(calls.where((c) => c['kind'] == 'interaction_logged').toList(), [
        {'_call': 'sendStudentNotification', 'kind': 'interaction_logged', 'studentUid': 's1'},
      ]);
      expect(find.byKey(const ValueKey('rec-title')), findsNothing, reason: 'the form closed');
      expect(find.text('Interaction with Arjun Kumar recorded'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('a student with open topics on Today: they are offered, all ticked; the interaction covers what stays ticked', (tester) async {
      final (db, _) = await openAssociations(tester, plan: planDoc(today: [_card('s1', 'Arjun Kumar', [_worry(), _slip()])], left: 0));
      await tester.tap(find.byKey(const ValueKey('assoc-add-interaction')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-student-s1')));
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('rec-topic-0'))).value, true);
      await tester.tap(find.byKey(const ValueKey('rec-topic-1'))); // he did not talk about his sadhana
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rec-save')));
      await tester.pumpAndSettle();
      final d = (await _saved(db)).single.data();
      expect((d['topicAnswers'] as List).map((x) => x['topic']).toList(), ['concern'], reason: 'only what he ticked');
      await _finish(tester);
    });

    testWidgets('Change student: back to the picker; the choice made before is dropped, nothing is saved by it', (tester) async {
      final (db, _) = await openAssociations(tester);
      await tester.tap(find.byKey(const ValueKey('assoc-add-interaction')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-student-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-student-change')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-student-search')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('rec-save'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('rec-student-s2')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('rec-title'))).data, 'Record interaction · Bhima Sen');
      expect(await _saved(db), isEmpty);
      await _finish(tester);
    });

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 1.6]) {
        for (final wide in [false, true]) {
          testWidgets('${wide ? 'website 1280' : 'phone 360'}, ${dark ? 'dark' : 'light'}, text scale $scale: the two buttons and the picker fit; the buttons are 48 dp targets', (tester) async {
            await openAssociations(tester, dark: dark, scale: scale, size: wide ? const Size(1280, 900) : const Size(360, 800));
            expect(tester.takeException(), isNull);
            final add = tester.getSize(find.byKey(const ValueKey('assoc-add-interaction')));
            expect(add.height, greaterThanOrEqualTo(48));
            await tester.tap(find.byKey(const ValueKey('assoc-add-interaction')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'the picker at this size');
            await tester.tap(find.byKey(const ValueKey('rec-student-s1')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'the form at this size');
            await _finish(tester);
          });
        }
      }
    }
  });

  group('THE FORM', () {
    testWidgets('his willingness is OPTIONAL: it starts at "same" as the Today form always did; tapping the chosen one again leaves it out and the record then carries none', (tester) async {
      final (db, _) = await _setup(tester);
      await pumpScreen(tester, _host(_button(uid: 's1', name: 'Arjun Kumar')));
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-will-same')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('rec-notes')), 'A short call.');
      await tester.tap(find.byKey(const ValueKey('rec-save')));
      await tester.pumpAndSettle();
      expect((await _saved(db)).single.data().containsKey('willingness'), false);
      await _finish(tester);
    });

    testWidgets('a failed load of the students says so in words and the form can still be cancelled', (tester) async {
      await _setup(tester);
      AdminProfileProvider.instance.debugSet(null); // no profile: the student list cannot be worked out
      await pumpScreen(tester, _host(_button()));
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-students-error')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-title')), findsNothing);
      await _finish(tester);
    });
  });
}
