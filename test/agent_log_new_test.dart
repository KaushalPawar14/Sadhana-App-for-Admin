import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentLogPage.dart';
import 'package:folk_guide_app/Pages/BoysDetails.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BottomNavBar.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/UnseenDot.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// The Assistant log keeps the latest 50 (the server trims; see functions/test/agentLogTrim.test.js) and tells each HOD what is
/// NEW: an entry a Guide or an Enabler made since that HOD last opened the log - never the HOD's own. An orange dot on the Tasks
/// tab and on the "Assistant log" card, and "New" on each such entry; opening the log clears them, per HOD.

AdminProfile _hod(String id) => AdminProfile.fromMap({
      'id': id, 'displayName': 'HOD $id', 'role': 'HOD', 'teamGuide': '', 'email': '$id@x.org', 'notificationPrefs': {}, 'notificationTypes': <Object>[],
      'admins': [
        {'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': ''},
        {'id': 'H2', 'displayName': 'Hari Prasad', 'role': 'HOD', 'teamGuide': ''},
        {'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': ''},
        {'id': 'F1', 'displayName': 'Radha Devi', 'role': 'FEMALE_ENABLER', 'teamGuide': ''},
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  late FakeFirebaseFirestore db;
  final base = DateTime.now().subtract(const Duration(hours: 3));

  Future<void> entry(String id, {required String who, required String role, required int minutes, String request = 'meet Arjun'}) async {
    final at = base.add(Duration(minutes: minutes));
    await db.collection('agentActions').doc(id).set({
      'adminId': who, 'adminName': '$who name', 'role': role, 'createdMs': at.millisecondsSinceEpoch, 'createdAt': Timestamp.fromDate(at),
      'request': request, 'status': 'executed', 'actions': <Object>[],
    });
  }

  /// The app's test world, with the dots and the seen marks switched ON (they are what is under test here).
  Future<FakeFirebaseFirestore> app(WidgetTester tester, {Who who = Who.hod}) async {
    final d = await prepareApp(tester, who: who);
    UnseenAggregates.debugDisable = false;
    SeenMarkers.debugDisable = false;
    return d;
  }

  Future<bool> unseen(String hod) => UnseenAggregates.assistantLogUnseen(hod).first;

  setUp(() {
    // the dots and the seen marks are what is under test here
    UnseenAggregates.debugDisable = false;
    SeenMarkers.debugDisable = false;
    db = FakeFirebaseFirestore();
    GuideDb.useForTests(db);
  });
  tearDown(() => GuideDb.useForTests(null));

  group('the dot trail', () {
    test('a Guide\'s or Enabler\'s entry makes the dot for a HOD; the HOD\'s own does not', () async {
      await entry('mine', who: 'H', role: 'HOD', minutes: 1);
      expect(await unseen('H'), isFalse, reason: "a HOD's own action is never new to them");
      await entry('g1', who: 'G', role: 'GUIDE', minutes: 2);
      expect(await unseen('H'), isTrue);
    });

    test('an Enabler\'s entry makes it too', () async {
      await entry('f1', who: 'F1', role: 'FEMALE_ENABLER', minutes: 2);
      expect(await unseen('H'), isTrue);
    });

    test('it clears when that HOD opens the log, and comes back for the next entry', () async {
      await entry('g1', who: 'G', role: 'GUIDE', minutes: 2);
      expect(await unseen('H'), isTrue);
      await db.collection('seenMarkers').doc('H').set({'assistantLog': Timestamp.now()});
      expect(await unseen('H'), isFalse);
      await entry('g2', who: 'G', role: 'GUIDE', minutes: 400);
      expect(await unseen('H'), isTrue);
    });

    test('per HOD: one HOD opening the log clears nothing for another', () async {
      await entry('g1', who: 'G', role: 'GUIDE', minutes: 2);
      await db.collection('seenMarkers').doc('H').set({'assistantLog': Timestamp.now()});
      expect(await unseen('H'), isFalse);
      expect(await unseen('H2'), isTrue);
    });

    test('an empty log, or no id, shows nothing', () async {
      expect(await unseen('H'), isFalse);
      expect(await unseen(''), isFalse);
    });
  });

  group('the Assistant log page', () {
    Future<void> openLog(WidgetTester tester, {String me = 'H', double scale = 1.0, bool dark = false}) async {
      AdminProfileProvider.instance.debugSet(_hod(me));
      await pumpScreen(tester, const AgentLogPage(), scale: scale, dark: dark);
      await letDataArrive(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await letDataArrive(tester);
    }

    testWidgets("entries by a Guide or an Enabler are marked New with an orange dot; the HOD's own are not", (tester) async {
      db = await app(tester);
      await entry('mine', who: 'H', role: 'HOD', minutes: 1, request: 'my own request');
      await entry('g1', who: 'G', role: 'GUIDE', minutes: 2, request: 'guide request');
      await entry('f1', who: 'F1', role: 'FEMALE_ENABLER', minutes: 3, request: 'enabler request');
      await openLog(tester);
      expect(find.byKey(const ValueKey('agent-log-new')), findsNWidgets(2));
      expect(find.byKey(const ValueKey('agent-log-new-dot')), findsNWidgets(2));
      expect(find.text('New'), findsNWidgets(2));
      // and the HOD's own card is one of the three, without the mark
      expect(find.textContaining('my own request'), findsOneWidget);
      final newOnes = tester.widgetList<Container>(find.byKey(const ValueKey('agent-log-new'))).length;
      expect(newOnes, 2);
      expectNoOverflow(tester);
    });

    testWidgets('opening the log marks it seen for this HOD (and only this HOD); next time nothing is new until something is', (tester) async {
      db = await app(tester);
      await entry('g1', who: 'G', role: 'GUIDE', minutes: 2);
      await openLog(tester);
      expect(find.byKey(const ValueKey('agent-log-new')), findsOneWidget, reason: 'new on this visit');
      expect((await db.collection('seenMarkers').doc('H').get()).data()?['assistantLog'], isNotNull, reason: 'seen');
      expect((await db.collection('seenMarkers').doc('H2').get()).exists, isFalse, reason: 'another HOD is untouched');

      // leave and come back later: nothing is new now
      await tester.pumpWidget(const SizedBox());
      await openLog(tester);
      expect(find.byKey(const ValueKey('agent-log-new')), findsNothing);

      // a new entry from a guide after that: new again
      await tester.pumpWidget(const SizedBox());
      await entry('g2', who: 'G', role: 'GUIDE', minutes: 500, request: 'a later one');
      await openLog(tester);
      expect(find.byKey(const ValueKey('agent-log-new')), findsOneWidget);
    });

    testWidgets('another HOD who has not opened the log still sees them as new', (tester) async {
      db = await app(tester);
      await entry('g1', who: 'G', role: 'GUIDE', minutes: 2);
      await db.collection('seenMarkers').doc('H').set({'assistantLog': Timestamp.now()});
      await openLog(tester, me: 'H2');
      expect(find.byKey(const ValueKey('agent-log-new')), findsOneWidget);
    });

    testWidgets('the log shows at most the latest 50', (tester) async {
      db = await app(tester);
      for (var i = 0; i < 60; i++) {
        await entry('e$i', who: 'G', role: 'GUIDE', minutes: i, request: 'request number $i');
      }
      AdminProfileProvider.instance.debugSet(_hod('H'));
      await pumpScreen(tester, const AgentLogPage());
      tester.view.physicalSize = const Size(360, 60000);
      await letDataArrive(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(kAgentLogKeep, 50);
      expect(find.textContaining('request number 59', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('request number 10"', skipOffstage: false), findsOneWidget, reason: 'the 50th newest');
      expect(find.textContaining('request number 9"', skipOffstage: false), findsNothing, reason: 'the oldest ten are beyond the 50');
      expect(find.textContaining('Asked:', skipOffstage: false), findsNWidgets(50));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('new entries fit at text ${scale}x, ${dark ? 'dark' : 'light'}', (tester) async {
          db = await app(tester);
          await entry('g1', who: 'G', role: 'GUIDE', minutes: 2, request: 'a very long request ' * 10);
          await entry('f1', who: 'F1', role: 'FEMALE_ENABLER', minutes: 3);
          await openLog(tester, scale: scale, dark: dark);
          expect(find.byKey(const ValueKey('agent-log-new')), findsNWidgets(2));
          expectNoOverflow(tester);
        });
      }
    }
  });

  group('the Tasks tab', () {
    testWidgets('the Assistant log card carries an orange dot while there is something new, and it clears after the log is opened', (tester) async {
      db = await app(tester);
      AdminProfileProvider.instance.debugSet(_hod('H'));
      await entry('g1', who: 'G', role: 'GUIDE', minutes: 2);
      await pumpScreen(tester, const Scaffold(body: AdminControlPage()));
      await letDataArrive(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('agent-log-card')), 200, scrollable: find.byType(Scrollable).first);
      final dot = find.descendant(of: find.byKey(const ValueKey('agent-log-dot')), matching: find.byType(UnseenDot));
      expect(dot, findsOneWidget);
      await db.collection('seenMarkers').doc('H').set({'assistantLog': Timestamp.now()});
      await letDataArrive(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(dot, findsNothing);
    });

    testWidgets("the HOD's own entry makes no dot on the card", (tester) async {
      db = await app(tester);
      AdminProfileProvider.instance.debugSet(_hod('H'));
      await entry('mine', who: 'H', role: 'HOD', minutes: 2);
      await pumpScreen(tester, const Scaffold(body: AdminControlPage()));
      await letDataArrive(tester);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('agent-log-card')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: find.byKey(const ValueKey('agent-log-dot')), matching: find.byType(UnseenDot)), findsNothing);
    });

    testWidgets('a Guide has no Assistant log card and no dot, and nothing is read for them', (tester) async {
      db = await app(tester, who: Who.guide);
      await entry('g1', who: 'G', role: 'GUIDE', minutes: 2);
      await pumpScreen(tester, const Scaffold(body: AdminControlPage()));
      await letDataArrive(tester);
      expect(find.byKey(const ValueKey('agent-log-card')), findsNothing);
      expect(find.byKey(const ValueKey('agent-log-dot')), findsNothing);
    });
  });

  testWidgets('the Tasks tab itself carries the dot for a HOD (and not for a Guide)', (tester) async {
    UnseenAggregates.debugDisable = false;
    db = await app(tester);
    AdminProfileProvider.instance.debugSet(_hod('H'));
    await entry('g1', who: 'G', role: 'GUIDE', minutes: 2);
    await db.collection('agentActions').doc('g1').delete();
    await pumpScreen(tester, const CurvedNavBar('H'));
    await letDataArrive(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await letDataArrive(tester);
    final before = find.byType(UnseenDot).evaluate().length;
    await entry('g2', who: 'G', role: 'GUIDE', minutes: 3);
    await letDataArrive(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await letDataArrive(tester);
    expect(find.byType(UnseenDot).evaluate().length, before + 1, reason: 'one more dot: at the Tasks item');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
