import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentLogPage.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Pages/PriorityStudents.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/Services/VoiceRecorder.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/agent/AgentRoutes.dart';
import 'package:folk_guide_app/agent/AgentTypes.dart';
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// The assistant's page and button, as a guide meets them: the chat, the confirmation card (every
/// name and date, who is told, advice), the second confirmation for a deletion, "Take me there", the
/// mic, the HOD's log — at text size 1.0 / 1.3 / 1.6, light and dark, in the app's real fonts.

class _Mic implements VoiceRecorder {
  int starts = 0;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<VoiceClip?> stop() async => VoiceClip(bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'audio/mp4', seconds: 4);
  @override
  Future<void> cancel() async {}
}

Map<String, dynamic> _reply(String status, [Map<String, dynamic> more = const {}]) => {'sessionId': 'sess12345', 'status': status, ...more};

Map<String, dynamic> _action(String callId, String tool, Map<String, dynamic> args, {String title = 'Request a meeting with a student', List<Map<String, dynamic>> lines = const [], List<String> notifies = const [], bool dbl = false}) =>
    {'callId': callId, 'tool': tool, 'args': args, 'title': title, 'lines': lines, 'notifies': notifies, 'double': dbl};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  late List<Map<String, dynamic>> replies;
  late List<Map<String, dynamic>> requests;
  late List<Map<String, dynamic>> pushes;

  /// The controller, wired to a scripted server and the seeded app database.
  Future<AgentController> wire(WidgetTester tester, {Who who = Who.hod}) async {
    final db = await prepareApp(tester, who: who);
    replies = [];
    requests = [];
    pushes = [];
    HierarchyApi.useForTests((name, args) async {
      if (name == 'guideAgentTurn') {
        requests.add(args);
        return replies.removeAt(0);
      }
      if (name == 'sendStudentNotification') {
        pushes.add(args);
        return {'sent': 1, 'total': 1};
      }
      if (name == 'voiceToEnglishText') return {'text': 'Who has not filed today?'};
      return <String, dynamic>{};
    });
    final c = AgentController(env: AgentEnv(profile: adminProfile(who), db: db, clock: () => DateTime(2026, 10, 23, 12)));
    AgentSession.useForTests(c);
    addTearDown(() => AgentSession.useForTests(null));
    return c;
  }

  Future<void> open(WidgetTester tester, AgentController c, {double scale = 1.0, bool dark = false}) async {
    await pumpScreen(tester, AgentPage(controller: c), scale: scale, dark: dark);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('agent-input')), text);
    await tester.tap(find.byKey(const ValueKey('agent-send')));
    await tester.pump();
    // long enough for the list to finish scrolling to the newest entry (it builds lazily)
    await tester.pump(const Duration(milliseconds: 700));
  }

  final students = ['Arjun Kumar', 'Bhima Sen', 'Chaitanya Das', 'Dhruva Nair', 'Gauri Devi', 'Eknath Iyer'];

  Map<String, dynamic> bigProposal() => _reply('confirm', {
        'text': 'Nine of your boys have not filed for three days.',
        'proposal': {
          'id': 'p1', 'tainted': false,
          'headsUp': ['Request a meeting with a student: the student: \'Meeting Scheduled\'.'],
          'actions': [
            _action('c1', 'meeting_request', {'studentUid': 's1', 'date': '2026-10-26', 'time': '18:00'}, lines: [
              {'label': 'Student', 'value': 'Arjun Kumar', 'items': <String>[]},
              {'label': 'Date', 'value': 'Mon 26 Oct 2026', 'items': <String>[]},
              {'label': 'Time', 'value': '6:00 pm', 'items': <String>[]},
              {'label': 'Message to the student', 'value': 'Let us catch up about how the week has gone and what is making chanting hard just now.', 'items': <String>[]},
            ], notifies: ["the student: 'Meeting Scheduled'"]),
            _action('c2', 'priority_remove', {'studentUids': ['s1']}, title: 'Take students off your Priority list', lines: [
              {'label': 'Students', 'value': '6 — Arjun Kumar, Bhima Sen, Chaitanya Das…', 'items': students},
            ]),
          ],
        },
      });

  // -------------------------------------------------------------------------
  group('the page', () {
    for (final scale in kScales) {
      for (final dark in [false, true]) {
        final label = 'text ${scale}x, ${dark ? 'dark' : 'light'}';

        testWidgets('welcome, a long answer with buttons, and an error all fit at $label', (tester) async {
          final c = await wire(tester);
          await open(tester, c, scale: scale, dark: dark);
          expect(find.byKey(const ValueKey('agent-welcome')), findsOneWidget);
          expect(find.text('How can I help?'), findsOneWidget);
          expectNoOverflow(tester, reason: 'welcome');

          replies.add(_reply('message', {
            'text': 'To add a trip, open Analysis → ABCDE → Expeditions and tap New Trip. Fill in the title, the start and end dates and the place, '
                'and choose whether it is for boys or girls. Students on the roster will see it in their app straight away.',
            'links': [{'route': 'trips'}, {'route': 'student_profile', 'studentUid': 's1', 'studentName': 'Arjun Kumar'}],
          }));
          await say(tester, 'where do I add a trip?');
          expect(find.textContaining('open Analysis'), findsOneWidget);
          expect(find.text('Take me there: Expeditions'), findsOneWidget);
          expect(find.text("Take me there: Arjun Kumar's profile"), findsOneWidget);
          expectNoOverflow(tester, reason: 'answer');

          HierarchyApi.useForTests((n, a) async => throw HierarchyException('not-found', 'NOT_FOUND'));
          await say(tester, 'and again');
          expect(find.byKey(const ValueKey('agent-error')), findsOneWidget);
          expect(find.textContaining('not-found'), findsOneWidget, reason: 'the real reason');
          expectNoOverflow(tester, reason: 'error');
        });

        testWidgets('the confirmation card fits on a phone at $label, and its buttons can be reached', (tester) async {
          final c = await wire(tester);
          await open(tester, c, scale: scale, dark: dark);
          replies.add(bigProposal());
          await say(tester, 'meet my boys who missed three days');
          expect(find.byKey(const ValueKey('agent-confirm')), findsOneWidget);
          expect(find.byKey(const ValueKey('agent-cancel')), findsOneWidget);
          final confirm = tester.getRect(find.byKey(const ValueKey('agent-confirm')));
          final composerTop = tester.getTopLeft(find.byKey(const ValueKey('agent-input'))).dy;
          expect(confirm.bottom, lessThanOrEqualTo(composerTop), reason: 'the newest card is scrolled fully into view, clear of the box below');
          expectNoOverflow(tester, reason: 'card');
        });

        testWidgets('the confirmation card shows every name, date and who is told, at $label', (tester) async {
          final c = await wire(tester);
          await open(tester, c, scale: scale, dark: dark);
          // a tall screen, so the whole card is built at once and can be read top to bottom
          tester.view.physicalSize = const Size(360, 2600);
          replies.add(bigProposal());
          await say(tester, 'meet my boys who missed three days');

          expect(find.textContaining('Nine of your boys'), findsOneWidget);
          expect(find.byKey(const ValueKey('agent-proposal-p1')), findsOneWidget);
          expect(find.text("Here's what I'll do — please check"), findsOneWidget);
          expect(find.text('Arjun Kumar'), findsWidgets);
          expect(find.text('Mon 26 Oct 2026'), findsOneWidget);
          expect(find.text('6:00 pm'), findsOneWidget);
          expect(find.textContaining('Let us catch up about how the week'), findsOneWidget, reason: 'the whole message, not cut');
          for (final name in students) {
            expect(find.text(name), findsWidgets, reason: 'every name in a list is shown: $name');
          }
          expect(find.textContaining("Tells the student: 'Meeting Scheduled'"), findsOneWidget);
          expect(find.byKey(const ValueKey('agent-confirm')), findsOneWidget);
          expect(find.byKey(const ValueKey('agent-cancel')), findsOneWidget);
          expectNoOverflow(tester, reason: 'card');
        });
      }
    }

    testWidgets('a suggestion chip sends its words', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('message', {'text': 'Open Analysis → ABCDE → Expeditions.'}));
      await tester.tap(find.text('Where do I add a trip?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(requests.single['text'], 'Where do I add a trip?');
      expect(find.byKey(const ValueKey('agent-conversation')), findsOneWidget);
    });

    testWidgets('nothing happens while the card is showing; Confirm runs it, shows what was done, and tells the server', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('confirm', {
        'proposal': {
          'id': 'p2', 'tainted': false, 'headsUp': <String>[],
          'actions': [
            _action('c1', 'meeting_request', {'studentUid': 's1', 'date': '2026-10-26', 'time': '18:00'}, lines: [
              {'label': 'Student', 'value': 'Arjun Kumar', 'items': <String>[]},
            ]),
          ],
        },
      }));
      await say(tester, 'meet Arjun');
      expect((await GuideDb.instance.collection('associations').where('requestedBy', isEqualTo: 'guide').get()).docs, isEmpty);

      replies.add(_reply('message', {'text': 'Done — Arjun has been asked to meet on Monday at 6 pm.'}));
      await tester.tap(find.byKey(const ValueKey('agent-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect((await GuideDb.instance.collection('associations').where('requestedBy', isEqualTo: 'guide').get()).docs.length, 1);
      expect(find.textContaining('Meeting requested with Arjun Kumar'), findsOneWidget);
      expect(find.textContaining('Done — Arjun'), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-confirm')), findsNothing, reason: 'it cannot be confirmed twice');
      expect(requests.last['outcome'], 'executed');
      expectNoOverflow(tester);
    });

    testWidgets('Cancel changes nothing and says so', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(bigProposal());
      await say(tester, 'do it');
      replies.add(_reply('message', {'text': 'Okay, I have changed nothing.'}));
      await tester.tap(find.byKey(const ValueKey('agent-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Cancelled — nothing was changed'), findsOneWidget);
      expect(requests.last['outcome'], 'cancelled');
      expect((await GuideDb.instance.collection('associations').where('requestedBy', isEqualTo: 'guide').get()).docs, isEmpty);
    });

    testWidgets('a deletion asks a second time; "Keep it" leaves everything, "Yes, delete" does it', (tester) async {
      final c = await wire(tester);
      final flagged = (await GuideDb.instance.collection('flaggedChatMessages').get()).docs;
      expect(flagged, isNotEmpty);
      final id = flagged.first.id;
      await open(tester, c);
      replies.add(_reply('confirm', {
        'proposal': {
          'id': 'pd', 'tainted': false, 'headsUp': ['Delete flagged messages: this cannot be undone, so you will be asked twice.'],
          'actions': [
            _action('c1', 'flagged_delete', {'messageIds': [id]}, title: 'Delete flagged messages', dbl: true, lines: [
              {'label': 'Messages', 'value': 'Message from Arjun Kumar', 'items': <String>[]},
            ]),
          ],
        },
      }));
      await say(tester, 'delete the flagged message from Arjun');
      expect(find.text('This will delete — please check'), findsOneWidget);
      expect(find.text('Delete…'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('agent-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Delete for good?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agent-keep')));
      await tester.pumpAndSettle();
      expect((await GuideDb.instance.collection('flaggedChatMessages').doc(id).get()).exists, isTrue);
      expect(find.byKey(const ValueKey('agent-confirm')), findsOneWidget, reason: 'still waiting for the guide');

      replies.add(_reply('message', {'text': 'Deleted.'}));
      await tester.tap(find.byKey(const ValueKey('agent-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agent-delete-yes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect((await GuideDb.instance.collection('flaggedChatMessages').doc(id).get()).exists, isFalse);
      expect(requests.last['confirmations'], 2);
    });

    testWidgets('a change that fails is shown as failed, with the reason', (tester) async {
      final c = await wire(tester, who: Who.guide);
      await open(tester, c);
      replies.add(_reply('confirm', {
        'proposal': {
          'id': 'pf', 'tainted': false, 'headsUp': <String>[],
          // s5 is a girl: outside a Guide's scope
          'actions': [_action('c1', 'meeting_request', {'studentUid': 's5', 'date': '2026-10-26', 'time': '18:00'})],
        },
      }));
      await say(tester, 'meet Gauri');
      replies.add(_reply('message', {'text': "I couldn't find that student among your students."}));
      await tester.tap(find.byKey(const ValueKey('agent-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining("can't find that student among your students"), findsWidgets);
      expect((await GuideDb.instance.collection('associations').where('requestedBy', isEqualTo: 'guide').get()).docs, isEmpty);
    });

    testWidgets('"Take me there" opens the screen', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('message', {'text': 'Here it is.', 'links': [{'route': 'priority'}]}));
      await say(tester, 'show me priority students');
      await tester.tap(find.byKey(const ValueKey('agent-link-priority')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(PriorityStudentsPage), findsOneWidget);
    });

    testWidgets('a link for a student outside the scope opens nothing and says why', (tester) async {
      final c = await wire(tester, who: Who.guide);
      await open(tester, c);
      replies.add(_reply('message', {'text': 'Here.', 'links': [{'route': 'student_profile', 'studentUid': 's5', 'studentName': 'Gauri Devi'}]}));
      await say(tester, 'open Gauri');
      await tester.tap(find.byKey(const ValueKey('agent-link-student_profile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining("can't find that student among your students"), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // the snackbar goes
    });

    testWidgets('New chat clears the conversation', (tester) async {
      final c = await wire(tester);
      await open(tester, c);
      replies.add(_reply('message', {'text': 'hello there'}));
      await say(tester, 'hi');
      expect(find.text('hello there'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agent-new-chat')));
      await tester.pump();
      expect(find.text('hello there'), findsNothing);
      expect(find.byKey(const ValueKey('agent-welcome')), findsOneWidget);
    });

    testWidgets('only a HOD gets the log button', (tester) async {
      var c = await wire(tester, who: Who.hod);
      await open(tester, c);
      expect(find.byKey(const ValueKey('agent-log')), findsOneWidget);
      c = await wire(tester, who: Who.guide);
      await open(tester, c);
      expect(find.byKey(const ValueKey('agent-log')), findsNothing);
    });

    testWidgets('the mic puts clean text in the box for the guide to edit, and sends nothing by itself', (tester) async {
      final c = await wire(tester);
      final mic = _Mic();
      VoiceRecorder.useForTests(mic);
      addTearDown(() => VoiceRecorder.useForTests(null));
      await open(tester, c);
      await tester.tap(find.byKey(const ValueKey('voice-speak')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-done')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const ValueKey('agent-input')));
      expect(field.controller!.text, 'Who has not filed today?');
      expect(requests, isEmpty, reason: 'nothing is sent until the guide presses send');
    });
  });

  // -------------------------------------------------------------------------
  group('the HOD log', () {
    testWidgets('lists who asked, what was proposed, and what came of it', (tester) async {
      final db = await prepareApp(tester);
      await db.collection('agentActions').add({
        'adminId': 'G', 'adminName': 'Gopal Das', 'role': 'GUIDE', 'createdMs': DateTime(2026, 10, 23, 16).millisecondsSinceEpoch,
        'request': 'meet Arjun on Monday', 'status': 'executed', 'confirmations': 1,
        'actions': [{'callId': 'c1', 'tool': 'meeting_request', 'title': 'Request a meeting with a student', 'lines': [{'label': 'Student', 'value': 'Arjun Kumar'}]}],
        'results': [{'callId': 'c1', 'tool': 'meeting_request', 'ok': true}],
      });
      await db.collection('agentActions').add({
        'adminId': 'F1', 'adminName': 'Radha Devi', 'role': 'FEMALE_ENABLER', 'createdMs': DateTime(2026, 10, 23, 17).millisecondsSinceEpoch,
        'request': 'add an instrument', 'status': 'denied', 'actions': [{'tool': 'music_instrument_add', 'title': 'music_instrument_add'}],
        'note': 'not something this role can do in the app',
      });
      await db.collection('agentActions').add({
        'adminId': 'G', 'adminName': 'Gopal Das', 'role': 'GUIDE', 'createdMs': DateTime(2026, 10, 23, 15).millisecondsSinceEpoch,
        'request': 'delete flagged', 'status': 'executed', 'unconfirmedDelete': true, 'tainted': true,
        'actions': [{'callId': 'c1', 'tool': 'flagged_delete', 'title': 'Delete flagged messages', 'lines': []}],
        'results': [{'callId': 'c1', 'ok': false, 'error': 'not permitted'}],
      });
      await pumpScreen(tester, const AgentLogPage());
      await letDataArrive(tester);
      expect(find.text('Radha Devi (Female Enabler)'), findsOneWidget);
      expect(find.text('Refused: not allowed'), findsOneWidget);
      expect(find.text('Gopal Das (Guide)'), findsNWidgets(2));
      expect(find.text('Asked: "meet Arjun on Monday"'), findsOneWidget);
      expect(find.text('Student: Arjun Kumar'), findsOneWidget);
      expect(find.text('A deletion was reported without both confirmations.'), findsOneWidget);
      expect(find.text("Prepared after reading students' own words."), findsOneWidget);
      expect(find.text('not permitted'), findsOneWidget);
      // newest first
      final first = tester.getTopLeft(find.text('Radha Devi (Female Enabler)')).dy;
      final last = tester.getTopLeft(find.text('Asked: "delete flagged"')).dy;
      expect(first, lessThan(last));
      expectNoOverflow(tester);
    });

    for (final scale in kScales) {
      testWidgets('and fits at text ${scale}x', (tester) async {
        final db = await prepareApp(tester);
        await db.collection('agentActions').add({
          'adminId': 'G', 'adminName': 'A guide with a rather long display name', 'role': 'MALE_ENABLER', 'createdMs': DateTime(2026, 10, 23, 16).millisecondsSinceEpoch,
          'request': 'a very long request ' * 12, 'status': 'executed',
          'actions': [{'callId': 'c1', 'tool': 'x', 'title': 'Request a meeting with a student', 'lines': [{'label': 'Student', 'value': 'Arjun Kumar ' * 6}]}],
          'results': [{'callId': 'c1', 'ok': true}],
        });
        await pumpScreen(tester, const AgentLogPage(), scale: scale, dark: scale == 1.3);
        await letDataArrive(tester);
        expectNoOverflow(tester);
      });
    }

    testWidgets('an empty log says so', (tester) async {
      await prepareApp(tester);
      await pumpScreen(tester, const AgentLogPage());
      await letDataArrive(tester);
      expect(find.byKey(const ValueKey('agent-log-empty')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('the floating button', () {
    Future<void> pumpApp(WidgetTester tester, {bool signedIn = true, VoidCallback? onOpen, double scale = 1.0, bool dark = false, Size size = const Size(360, 800)}) async {
      await prepareApp(tester);
      if (!signedIn) AdminProfileProvider.instance.debugSet(null);
      phone(tester, scale, size: size);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(
        theme: GuideTheme.light,
        darkTheme: GuideTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => AgentOverlay(onOpen: onOpen, child: child!),
        home: const Scaffold(body: Center(child: Text('Some screen'))),
      ));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('is on screen when an admin is signed in, and absent before', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const ValueKey('agent-button')), findsOneWidget);
    });

    testWidgets('is not shown over the sign-in', (tester) async {
      await pumpApp(tester, signedIn: false);
      expect(find.byKey(const ValueKey('agent-button')), findsNothing);
    });

    testWidgets('tapping opens the assistant', (tester) async {
      var opened = 0;
      await pumpApp(tester, onOpen: () => opened++);
      await tester.tap(find.byKey(const ValueKey('agent-button')));
      expect(opened, 1);
    });

    testWidgets('starts bottom-right clear of the navigation, and stays fully on screen', (tester) async {
      await pumpApp(tester);
      final r = tester.getRect(find.byKey(const ValueKey('agent-button')));
      expect(r.width, kAgentButtonSize);
      expect(r.right, lessThanOrEqualTo(360));
      expect(r.bottom, lessThan(800));
      expect(r.left, greaterThan(180), reason: 'on the right');
      expect(r.top, greaterThan(400), reason: 'low down');
    });

    testWidgets('can be dragged, and remembers where it was left (as a fraction of the screen)', (tester) async {
      await pumpApp(tester);
      await tester.drag(find.byKey(const ValueKey('agent-button')), const Offset(-150, -300));
      await tester.pump();
      final moved = tester.getTopLeft(find.byKey(const ValueKey('agent-button')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('agent_button_dx_fraction'), closeTo(moved.dx / 360, .001));
      expect(prefs.getDouble('agent_button_dy_fraction'), closeTo(moved.dy / 800, .001));

      // a fresh start finds it there again
      await tester.pumpWidget(const SizedBox());
      SharedPreferences.setMockInitialValues({
        'agent_button_dx_fraction': prefs.getDouble('agent_button_dx_fraction')!,
        'agent_button_dy_fraction': prefs.getDouble('agent_button_dy_fraction')!,
      });
      await tester.pumpWidget(MaterialApp(
        theme: GuideTheme.light,
        builder: (context, child) => AgentOverlay(child: child!),
        home: const Scaffold(body: SizedBox()),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.byKey(const ValueKey('agent-button'))), moved);
    });

    testWidgets('can never be dragged off screen', (tester) async {
      await pumpApp(tester);
      await tester.drag(find.byKey(const ValueKey('agent-button')), const Offset(900, 2000));
      await tester.pump();
      var r = tester.getRect(find.byKey(const ValueKey('agent-button')));
      expect(r.right, lessThanOrEqualTo(360));
      expect(r.bottom, lessThanOrEqualTo(800));
      await tester.drag(find.byKey(const ValueKey('agent-button')), const Offset(-2000, -2000));
      await tester.pump();
      r = tester.getRect(find.byKey(const ValueKey('agent-button')));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.top, greaterThanOrEqualTo(0));
    });

    testWidgets("is the assistant's own colour, and not the Student app's", (tester) async {
      await pumpApp(tester);
      final g = GuideTheme.light.extension<GuideColors>()!;
      final dark = GuideTheme.dark.extension<GuideColors>()!;
      expect(g.agent, isNot(dark.agent), reason: 'tuned for each theme');
      for (final c in [g.agent, dark.agent, g.agentTop, g.agentMid, g.agentBottom]) {
        // the assistant is SAFFRON (red high, green middling, blue low); the Student app's is violet-to-teal and never fuchsia
        expect((c.r * 255).round(), greaterThan(140));
        expect((c.g * 255).round(), allOf(greaterThan(60), lessThan(215)));
        expect((c.b * 255).round(), lessThan(110));
      }
    });

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('is the same size and on screen at text ${scale}x, ${dark ? 'dark' : 'light'}', (tester) async {
          await pumpApp(tester, scale: scale, dark: dark, size: const Size(320, 640));
          final r = tester.getRect(find.byKey(const ValueKey('agent-button')));
          expect(r.width, kAgentButtonSize);
          expect(r.right, lessThanOrEqualTo(320));
          expect(r.bottom, lessThanOrEqualTo(640));
          expectNoOverflow(tester);
        });
      }
    }

    testWidgets("steps aside on the assistant's own page, and returns", (tester) async {
      await prepareApp(tester);
      phone(tester, 1.0);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(
        theme: GuideTheme.light,
        navigatorObservers: [AgentRouteVisibility.instance],
        builder: (context, child) => AgentOverlay(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('go'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(settings: const RouteSettings(name: kAgentRouteName), builder: (_) => const Scaffold(body: Text('assistant page')))),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('agent-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-button')), findsNothing, reason: 'offstage on the assistant page');
      Navigator.of(tester.element(find.text('assistant page'))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-button')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('Take me there', () {
    testWidgets('every route builds the page it names', (tester) async {
      await prepareApp(tester);
      final me = adminProfile(Who.hod);
      final ctx = AgentRouteContext(me, studentUid: 's1', studentName: 'Arjun Kumar', residence: 'Stay at FOLK');
      for (final e in kAgentRoutes.entries) {
        if (e.value.tab != null) {
          expect(e.value.page, isNull, reason: e.key);
          continue;
        }
        expect(e.value.page!(ctx), isA<Widget>(), reason: e.key);
      }
      expect(kAgentRoutes.keys.length, 25);
    });

    testWidgets('a route that opens a student refuses to without one', (tester) async {
      await prepareApp(tester);
      final problem = await openAgentLink(const AgentLink(route: 'student_profile'), env: AgentEnv(profile: adminProfile(Who.hod)));
      expect(problem, contains('which student'));
    });

    testWidgets('the labels read naturally', (tester) async {
      expect(agentLinkLabel(const AgentLink(route: 'trips')), 'Take me there: Expeditions');
      expect(agentLinkLabel(const AgentLink(route: 'student_profile', studentName: 'Arjun Kumar')), "Take me there: Arjun Kumar's profile");
      expect(agentLinkLabel(const AgentLink(route: 'doubts')), "Take me there: Students' doubts");
    });
  });
}
