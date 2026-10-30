import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/Calendar.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentGuideMe.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

/// THE ASSISTANT'S "GUIDE ME" / "DO IT" TOGGLE: both modes labelled at the top of the page, remembered per admin (default Do it). Guide me sends the
/// request in guide mode with the students found by name, shows the answer with raised buttons that open the exact screen (and are saved with the chat),
/// and the phone changes nothing. Do it goes on as before.

class _Seen extends NavigatorObserver {
  final List<String?> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route.settings.name);
}

Future<(FakeFirebaseFirestore, AgentController, List<Map<String, dynamic>>)> _setup(WidgetTester tester, {List<Map<String, dynamic>>? replies, Who who = Who.guide}) async {
  final db = await prepareApp(tester, who: who);
  await db.collection('users').doc('ayush').set({'name': 'Ayush Shah', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at Hostel', 'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'});
  await db.collection('users').doc('amit').set({'name': 'Amit', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G', 'role': 'Stay at Hostel', 'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'});
  final requests = <Map<String, dynamic>>[];
  final queue = [...?replies];
  HierarchyApi.useForTests((name, args) async {
    if (name == 'guideAgentTurn') {
      requests.add(args);
      return queue.removeAt(0);
    }
    return <String, dynamic>{};
  });
  final c = AgentController(env: AgentEnv(profile: adminProfile(who), db: db, clock: () => DateTime(2026, 10, 30, 12)));
  AgentSession.useForTests(c);
  addTearDown(() => AgentSession.useForTests(null));
  return (db, c, requests);
}

Map<String, dynamic> _guideReply(List<Map<String, dynamic>> buttons) => {
      'sessionId': 'sess12345',
      'status': 'message',
      'text': buttons.map((b) => b['line']).join('\n'),
      'links': <Map<String, dynamic>>[],
      'buttons': buttons,
    };

Map<String, dynamic> _button(String action, String label, String uid, String name, String line, {String hint = ''}) => {'action': action, 'label': label, 'studentUid': uid, 'studentName': name, 'line': line, 'hint': hint};

Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() {
    HierarchyApi.useForTests(null);
    PlanData.instance = const FirestorePlanData();
  });

  group('who the request names', () {
    final all = {
      'a': {'name': 'Ayush Shah'},
      'b': {'name': 'Amit Kumar'},
      'c': {'name': 'Manan21'},
      'd': {'name': 'Radha Devi'},
    };
    test('an exact first name, a different case, a typo, a possessive; nobody when no name is there', () {
      List<String> ids(String t) => [for (final m in studentCandidates(all, t)) m['uid']!];
      expect(ids("mark AYUSH's book completed"), ['a']);
      expect(ids('give amit a new due date'), ['b']);
      expect(ids('call Aayush about his book'), ['a'], reason: 'one letter more');
      expect(ids('Ayus is keen'), ['a'], reason: 'part of the name');
      expect(ids('set manan commitment to 12'), ['c'], reason: 'a name with digits');
      expect(ids('what should I do today?'), isEmpty);
      expect(studentCandidates(all, 'ayush and amit and radha').length, 3);
    });
    test('at most 12, the exact ones first', () {
      final many = {for (var i = 0; i < 30; i++) 'u$i': {'name': 'Ravi Person$i'}};
      expect(studentCandidates(many, 'ravi').length, 12);
    });
  });

  testWidgets('THE TOGGLE: both modes labelled at the top of the page, "Do it" selected to begin with; the hint says what each does', (tester) async {
    final (_, c, _) = await _setup(tester);
    await pumpScreen(tester, AgentPage(controller: c));
    await tester.pump();
    expect(find.byKey(const ValueKey('agent-mode-toggle')), findsOneWidget);
    expect(find.text('Guide me'), findsOneWidget);
    expect(find.text('Do it'), findsOneWidget);
    expect(c.mode, AgentMode.doIt);
    expect(find.textContaining('I do it for you now'), findsOneWidget);
    // it sits above the conversation and the composer
    expect(tester.getTopLeft(find.byKey(const ValueKey('agent-mode-toggle'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('agent-input'))).dy));
    await tester.tap(find.byKey(const ValueKey('agent-mode-guide')));
    await tester.pump();
    expect(c.mode, AgentMode.guide);
    expect(find.textContaining('Nothing is changed'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('THE CHOICE IS REMEMBERED PER ADMIN: after a restart the same admin finds Guide me; another admin starts with Do it', (tester) async {
    final (_, c, _) = await _setup(tester);
    await c.setMode(AgentMode.guide);
    final again = AgentController(env: AgentEnv(profile: adminProfile(Who.guide)));
    await again.loadMode();
    expect(again.mode, AgentMode.guide);
    final other = AgentController(env: AgentEnv(profile: adminProfile(Who.hod)));
    await other.loadMode();
    expect(other.mode, AgentMode.doIt, reason: 'a different admin: the default');
    await c.setMode(AgentMode.doIt);
    final back = AgentController(env: AgentEnv(profile: adminProfile(Who.guide)));
    await back.loadMode();
    expect(back.mode, AgentMode.doIt);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('GUIDE ME: the request goes in guide mode with the students found by name; the answer has a raised button per instruction; the phone changes nothing', (tester) async {
    final (db, c, requests) = await _setup(tester, replies: [
      _guideReply([_button('update_book', 'Update book', 'ayush', 'Ayush Shah', "Open Ayush's book: mark it finished or set a new date.", hint: 'Gita'), _button('change_commitment', 'Change commitment', 'amit', 'Amit', "Set Amit's rounds and minutes.")]),
    ]);
    final usersBefore = (await db.collection('users').get()).docs.map((d) => d.data()).toList().toString();
    await pumpScreen(tester, AgentPage(controller: c));
    await tester.pump();
    await c.setMode(AgentMode.guide);
    await tester.enterText(find.byKey(const ValueKey('agent-input')), "finish Ayush's book and change Amit's commitment");
    await tester.tap(find.byKey(const ValueKey('agent-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(requests.single['mode'], 'guide');
    expect((requests.single['candidates'] as List).map((x) => (x as Map)['uid']).toSet(), {'ayush', 'amit'});
    expect(find.byKey(const ValueKey('agent-guide-btn-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-guide-btn-1')), findsOneWidget);
    expect(find.text('Update book · Ayush Shah'), findsOneWidget);
    expect(find.text('Change commitment · Amit'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-confirm')), findsNothing, reason: 'no card, nothing proposed');
    expect((await db.collection('users').get()).docs.map((d) => d.data()).toList().toString(), usersBefore, reason: 'nothing was changed');
    expect(requests.length, 1, reason: 'one call');
    await _finish(tester);
  });

  testWidgets('A GUIDE-ME BUTTON OPENS THE EXACT SCREEN for that student and changes nothing: Update book -> his Books, with the hinted book', (tester) async {
    final seen = _Seen();
    final (_, c, _) = await _setup(tester, replies: [_guideReply([_button('update_book', 'Update book', 'ayush', 'Ayush Shah', "Open Ayush's book.", hint: 'Gita')])]);
    PlanData.instance = ManualPlanData();
    await pumpScreen(tester, AgentPage(controller: c), observers: [seen]);
    await tester.pump();
    await c.setMode(AgentMode.guide);
    await tester.enterText(find.byKey(const ValueKey('agent-input')), "Ayush's book");
    await tester.tap(find.byKey(const ValueKey('agent-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const ValueKey('agent-guide-btn-0')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4)); // the plan lookup gives up; the place opens anyway
    await tester.pump(const Duration(milliseconds: 400));
    expect(seen.pushed.last, 'topic:updateBook');
    final page = tester.widget<CalendarPage>(find.byType(CalendarPage));
    expect([page.studentUid, page.startOnBooks], ['ayush', true], reason: 'his Books tab');
    expect(page.booksHint, contains('Find "Gita"'), reason: 'the book it named');
    await _finish(tester);
  });

  testWidgets('THE BUTTONS ARE SAVED WITH THE CHAT: opening the saved chat again shows them', (tester) async {
    final (db, c, _) = await _setup(tester);
    await db.collection('agentChats').doc('sessSaved1').set({'adminId': 'G', 'title': 'Ayush', 'questions': 1, 'questionLimit': 20, 'entryCount': 2, 'updatedMs': 1, 'createdMs': 1});
    await db.collection('agentChats').doc('sessSaved1').collection('entries').doc('0000000000').set({'kind': 'user', 'text': "Ayush's book"});
    await db.collection('agentChats').doc('sessSaved1').collection('entries').doc('0000000001').set({'kind': 'assistant', 'text': 'Open it.', 'links': [], 'buttons': [_button('update_book', 'Update book', 'ayush', 'Ayush Shah', 'Open it.')]});
    await c.openChat('sessSaved1');
    final a = c.entries.whereType<AssistantEntry>().single;
    expect(a.buttons.single.action, 'update_book');
    expect(a.buttons.single.studentName, 'Ayush Shah');
    await pumpScreen(tester, AgentPage(controller: c));
    await tester.pump();
    expect(find.byKey(const ValueKey('agent-guide-btn-0')), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('DO IT goes on as before: the request carries no guide mode', (tester) async {
    final (_, c, requests) = await _setup(tester, replies: [
      {'sessionId': 'sess12345', 'status': 'message', 'text': 'Done.', 'links': <Map<String, dynamic>>[]},
    ]);
    await pumpScreen(tester, AgentPage(controller: c));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('agent-input')), 'mark Ayush\'s book completed');
    await tester.tap(find.byKey(const ValueKey('agent-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(requests.single.containsKey('mode'), isFalse);
    expect(requests.single.containsKey('candidates'), isFalse);
    await _finish(tester);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on a phone and a website width: the toggle fits, 48 dp, both labels visible', (tester) async {
        final (_, c, _) = await _setup(tester);
        for (final size in [const Size(360, 800), const Size(1100, 900)]) {
          await pumpScreen(tester, AgentPage(controller: c), scale: scale, dark: dark, size: size);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$size');
          for (final k in ['agent-mode-guide', 'agent-mode-do']) {
            final r = tester.getRect(find.byKey(ValueKey(k)));
            expect(r.height, greaterThanOrEqualTo(48), reason: k);
            expect(r.right, lessThanOrEqualTo(size.width + .5), reason: k);
          }
        }
        await _finish(tester);
      });
    }
  }
}
