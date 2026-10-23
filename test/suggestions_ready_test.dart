import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:folk_guide_app/Pages/InteractionLogger.dart';
import 'package:folk_guide_app/Pages/StudentProfilePage.dart';
import 'package:folk_guide_app/main.dart' show guideNavigatorKey;
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:folk_guide_app/theme/ThemeModeController.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/data_range_provider.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/NotificationRouter.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/SuggestionsReady.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/UnseenDot.dart';

import 'board_test.dart' show openBoard, FakeBoardData;
import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// "NEW SUGGESTIONS READY" — what the guide sees after saving an interaction (nothing but "Interaction saved"), the
// server's suggestions arriving by themselves, and the orange dot trail that leads to them:
//   bottom bar Home tab → FOLK Boys board entry → the profile (person) icon on that student's card → the label under the
//   picture on the student's profile. It clears only when the suggestions are opened, never because a push was swiped away.

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

Future<void> suggestions(FakeFirebaseFirestore db, String uid, String guide, String team, String gender,
    {String by = 'auto', Timestamp? at}) {
  return db.collection('holisticSuggestions').doc(uid).set({
    'studentUid': uid,
    'studentName': uid,
    'generatedBy': by,
    'generatedAt': at ?? t2,
    'suggestions': [
      {'action': 'Call him', 'why': 'No meeting in 6 weeks.', 'next': 'Phone him Sunday.'},
      {'action': 'Offer a book', 'why': 'No book started.', 'next': 'Bring Chapter 1.'},
      {'action': 'Meet in person', 'why': 'Exams are over.', 'next': 'Propose Saturday 5pm.'},
    ],
    'scopeGuide': guide,
    'scopeTeam': team,
    'scopeGender': gender,
  });
}

Future<FakeFirebaseFirestore> world() async {
  final db = FakeFirebaseFirestore();
  Future<void> user(String uid, String name, String guide, String team, String gender) =>
      db.collection('users').doc(uid).set({'name': name, 'guideId': guide, 'teamGuide': team, 'gender': gender, 'role': 'Stay at FOLK'});
  await user('s1', 'Arjun', 'G', 'G', 'male'); // G's own
  await user('s2', 'Bhima', 'M1', 'G', 'male'); // a Male Enabler of G's team
  await user('s3', 'Chaitanya', '', '', 'male'); // unassigned male
  await user('s4', 'Dhruva', 'G2', 'G2', 'male'); // another team
  await user('s5', 'Gauri', '', '', 'female'); // unassigned female
  await suggestions(db, 's1', 'G', 'G', 'male');
  await suggestions(db, 's2', 'M1', 'G', 'male');
  await suggestions(db, 's3', '', '', 'male');
  await suggestions(db, 's4', 'G2', 'G2', 'male');
  await suggestions(db, 's5', '', '', 'female');
  return db;
}

Future<Set<String>> unseen(String viewer) =>
    UnseenAggregates.suggestionsReadyUnseenUids(viewer).firstWhere((_) => true).timeout(const Duration(seconds: 5));

/// The app's providers around a MaterialApp that owns the app-wide navigator key, as a notification needs.
Future<void> pumpKeyedApp(WidgetTester tester) async {
  phone(tester, 1.0);
  SharedPreferences.setMockInitialValues({'selected_guide': 'H', ThemeModeController.prefsKey: 'light'});
  final theme = await ThemeModeController.load();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeModeController>.value(value: theme),
      ChangeNotifierProvider<ColorProvider>(create: (_) => ColorProvider(controller: theme)),
      ChangeNotifierProvider<AdminProfileProvider>.value(value: AdminProfileProvider.instance),
      ChangeNotifierProvider<DateRangeProvider>(create: (_) => DateRangeProvider()),
    ],
    child: MaterialApp(
      navigatorKey: guideNavigatorKey,
      theme: GuideTheme.light,
      home: const Scaffold(body: Text('home')),
    ),
  ));
}

Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await letDataArrive(tester, frames: 6);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  tearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  Future<void> as(FakeFirebaseFirestore db, AdminProfile p) async {
    GuideDb.useForTests(db);
    AdminProfileProvider.instance.debugSet(p);
  }

  // ------------------------------------------------------------------------------------------- the rule
  group('when the label shows', () {
    test('only for suggestions the server made by itself and the admin has not opened since', () {
      Map<String, dynamic> d({String by = 'auto', Timestamp? at}) => {'generatedBy': by, 'generatedAt': at ?? t2};
      expect(SuggestionsReady.isUnseen(d(), null), isTrue);
      expect(SuggestionsReady.isUnseen(d(), t1), isTrue);
      expect(SuggestionsReady.isUnseen(d(), t2), isFalse, reason: 'opened at that time');
      expect(SuggestionsReady.isUnseen(d(), t3), isFalse);
      expect(SuggestionsReady.isUnseen(d(by: 'G'), null), isFalse, reason: "a refresh the guide asked for: they are looking");
      expect(SuggestionsReady.isUnseen({'generatedBy': 'auto'}, null), isFalse, reason: 'no time yet');
      expect(SuggestionsReady.isUnseen(null, null), isFalse);
    });
  });

  // ------------------------------------------------------------------------------------------- the trail's data, per role
  group('the trail follows the suggestions themselves, in each role\'s own scope', () {
    test('HOD: every student on the board', () async {
      await as(await world(), profile('H', 'HOD'));
      expect(await unseen('H'), {'s1', 's2', 's3', 's4', 's5'});
    });

    test('Guide G: his team and the unassigned boys - never another team or the girls', () async {
      await as(await world(), profile('G', 'GUIDE'));
      expect(await unseen('G'), {'s1', 's2', 's3'});
    });

    test('Male Enabler M1: own students and the unassigned boys', () async {
      await as(await world(), profile('M1', 'MALE_ENABLER', team: 'G'));
      expect(await unseen('M1'), {'s2', 's3'});
    });

    test('Female Enabler F1: the unassigned girls', () async {
      await as(await world(), profile('F1', 'FEMALE_ENABLER'));
      expect(await unseen('F1'), {'s5'});
    });
  });

  group('it clears when the suggestions are opened - and only for that student', () {
    test('opening one student\'s suggestions clears that student only', () async {
      final db = await world();
      await as(db, profile('H', 'HOD'));
      await db.collection('seenMarkers').doc('H').set({
        SuggestionsReady.featureKey: {'s1': t3},
      });
      expect(await unseen('H'), {'s2', 's3', 's4', 's5'});
    });

    test('a newer batch after the marker lights it again', () async {
      final db = await world();
      await as(db, profile('G', 'GUIDE'));
      await db.collection('seenMarkers').doc('G').set({
        SuggestionsReady.featureKey: {'s1': t3, 's2': t3, 's3': t3},
      });
      expect(await unseen('G'), isEmpty);
      await suggestions(db, 's1', 'G', 'G', 'male', at: t4);
      expect(await unseen('G'), {'s1'});
    });

    test('a refresh the guide asked for never lights it', () async {
      final db = await world();
      await as(db, profile('G', 'GUIDE'));
      await suggestions(db, 's1', 'G', 'G', 'male', by: 'G', at: t4);
      expect(await unseen('G'), {'s2', 's3'});
    });

    test('swiping the notification away changes nothing: the dot follows the suggestions, not the push', () async {
      final db = await world();
      await as(db, profile('G', 'GUIDE'));
      // nothing in the data records a push at all
      expect(await unseen('G'), {'s1', 's2', 's3'});
      expect(await unseen('G'), {'s1', 's2', 's3'}, reason: 'still there');
    });

    test('everything opened: the Home tab and board entry dot is off', () async {
      final db = await world();
      await as(db, profile('G', 'GUIDE'));
      expect(await UnseenAggregates.suggestionsReadyRosterUnseen('G', false).firstWhere((_) => true), isTrue);
      await db.collection('seenMarkers').doc('G').set({
        SuggestionsReady.featureKey: {'s1': t3, 's2': t3, 's3': t3},
      });
      expect(await UnseenAggregates.suggestionsReadyRosterUnseen('G', false).firstWhere((_) => true), isFalse);
    });
  });

  // ------------------------------------------------------------------------------------------- the board card
  group('the board card: the profile icon carries the dot', () {
    UnseenBadge badgeOfProfileIcon(WidgetTester tester, String card) {
      final icon = find.byTooltip('Profile');
      final all = tester.widgetList<UnseenBadge>(find.ancestor(of: icon, matching: find.byType(UnseenBadge))).toList();
      expect(all, isNotEmpty);
      return all.first;
    }

    testWidgets('only the student with unopened suggestions shows it, and it clears live', (tester) async {
      final fake = FakeBoardData(
        users: {
          'sg1': {'name': 'Arjun Kumar', 'role': 'Stay at FOLK', 'gender': 'male', 'guideId': 'G', 'teamGuide': 'G'},
        },
      )..suggestionsUnseen = {'sg1'};
      await openBoard(tester, data: fake);
      await tester.pump(const Duration(milliseconds: 50));
      expect(badgeOfProfileIcon(tester, 'Arjun Kumar').show, isTrue);

      fake.suggestionsC.add(<String>{});
      await tester.pump(const Duration(milliseconds: 50));
      expect(badgeOfProfileIcon(tester, 'Arjun Kumar').show, isFalse);
    });

    testWidgets('a student whose suggestions are already opened has no dot', (tester) async {
      await openBoard(tester);
      expect(badgeOfProfileIcon(tester, 'Arjun Kumar').show, isFalse);
    });
  });

  // ------------------------------------------------------------------------------------------- the profile
  group('the profile: the label under the picture, cleared only by opening the suggestions', () {
    Future<FakeFirebaseFirestore> open(WidgetTester tester, {String by = 'auto', double scale = 1.0, bool dark = false, bool focus = false}) async {
      await prepareApp(tester);
      final db = GuideDb.instance as FakeFirebaseFirestore;
      await suggestions(db, 's1', 'G', 'G', 'male', by: by);
      SeenMarkers.debugDisable = false;
      UnseenAggregates.debugDisable = false;
      await pumpScreen(tester, StudentProfilePage(studentUid: 's1', focusSuggestions: focus), scale: scale, dark: dark);
      await settle(tester);
      return db;
    }

    testWidgets('the label is under the picture while the suggestions are new', (tester) async {
      await open(tester);
      expect(find.text(SuggestionsReady.label), findsWidgets);
      expect(find.byType(UnseenDot), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refresh the guide asked for shows no label', (tester) async {
      await open(tester, by: 'H');
      expect(find.text(SuggestionsReady.label), findsNothing);
    });

    testWidgets('tapping the label brings the suggestions up, and once they have been on screen the label is gone for good', (tester) async {
      final db = await open(tester);
      await tester.tap(find.text(SuggestionsReady.label).first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1500)); // on screen for a moment
      await settle(tester);
      final marker = (await db.collection('seenMarkers').doc('H').get()).data();
      expect(marker?[SuggestionsReady.featureKey]?['s1'], isNotNull, reason: 'opened: the marker is written');
      expect(find.text(SuggestionsReady.label), findsNothing, reason: 'the trail is cleared everywhere');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the suggestions are not marked opened while they are off screen', (tester) async {
      final db = await open(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      final marker = (await db.collection('seenMarkers').doc('H').get()).data();
      expect(marker?[SuggestionsReady.featureKey], isNull, reason: 'only opening them clears the dot');
      expect(find.text(SuggestionsReady.label), findsWidgets);
    });

    testWidgets('opened from the notification: the page scrolls to the suggestions and they count as opened', (tester) async {
      final db = await open(tester, focus: true);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1500));
      await settle(tester);
      final marker = (await db.collection('seenMarkers').doc('H').get()).data();
      expect(marker?[SuggestionsReady.featureKey]?['s1'], isNotNull);
      expect(find.text('Call him'), findsOneWidget, reason: 'the suggestions are on screen');
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('the label fits - ${dark ? 'dark' : 'light'}, text x$scale', (tester) async {
          await open(tester, scale: scale, dark: dark);
          expect(find.text(SuggestionsReady.label), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(SuggestionsReady.label).first);
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
        });
      }
    }
  });

  // ------------------------------------------------------------------------------------------- the notification
  testWidgets('a "guide_suggestions" notification opens that student\'s profile at the suggestions', (tester) async {
    await prepareApp(tester);
    final db = GuideDb.instance as FakeFirebaseFirestore;
    await suggestions(db, 's1', 'G', 'G', 'male');
    await pumpKeyedApp(tester);
    markAppReady();
    routeNotification({'dest': 'guide_suggestions', 'studentUid': 's1', 'studentName': 'Arjun Kumar'});
    await tester.pump();
    await settle(tester);
    final page = tester.widget<StudentProfilePage>(find.byType(StudentProfilePage));
    expect(page.studentUid, 's1');
    expect(page.focusSuggestions, isTrue);
    expect(find.text('Call him'), findsOneWidget);
  });

  testWidgets('a "guide_suggestions" notification with no student is ignored, never a broken page', (tester) async {
    await prepareApp(tester);
    await pumpKeyedApp(tester);
    markAppReady();
    routeNotification({'dest': 'guide_suggestions'});
    await tester.pump();
    expect(find.byType(StudentProfilePage), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  // ------------------------------------------------------------------------------------------- saving an interaction: no steps
  group('saving an interaction shows nothing but "Interaction saved"', () {
    Future<FakeFirebaseFirestore> openLogger(WidgetTester tester, {double scale = 1.0, bool dark = false, List<String>? calls}) async {
      final db = await prepareApp(tester);
      await pumpScreen(tester, const InteractionLoggerPage(studentUid: 's1', studentName: 'Arjun Kumar'), scale: scale, dark: dark);
      await settle(tester, rounds: 3);
      return db;
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('New'));
      await tester.pump();
      await letDataArrive(tester, frames: 12);
    }

    testWidgets('type, tap Save: the sheet closes, "Interaction saved", no extracted fields, no review, no LIT offer', (tester) async {
      final db = await openLogger(tester);
      await openSheet(tester);
      expect(find.text('Save'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Met after the evening program. Exams next week.');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await settle(tester, rounds: 2);
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Interaction saved'), findsOneWidget);
      for (final shown in ['Add LIT assessment?', 'Re-extract', 'Extraction', 'Approve', 'Review', 'Could not auto-fill', 'themes', 'Themes']) {
        expect(find.textContaining(shown), findsNothing, reason: '"$shown" must not appear');
      }
      expect(find.text('Save'), findsNothing, reason: 'the sheet closed');
      final logs = (await db.collection('interactionLogs').where('rawDictation', isEqualTo: 'Met after the evening program. Exams next week.').get()).docs;
      expect(logs.length, 1);
      expect(logs.single.data()['analysis'], 'queued', reason: 'the server takes it from here');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('how they connected is optional: Save works without choosing it', (tester) async {
      final db = await openLogger(tester);
      await openSheet(tester);
      await tester.enterText(find.byType(TextField).first, 'Quick chat.');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await settle(tester, rounds: 2);
      final summary = (await db.collection('interactionLogs').where('rawDictation', isEqualTo: 'Quick chat.').get()).docs.single.data()['approvedSummary'] as Map;
      expect(summary['interactionType'], '');
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('an empty note is not saved, and says why', (tester) async {
      final db = await openLogger(tester);
      final before = (await db.collection('interactionLogs').get()).docs.length;
      await openSheet(tester);
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Type what was discussed first'), findsOneWidget);
      expect((await db.collection('interactionLogs').get()).docs.length, before);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('the fields are clear the next time the sheet opens', (tester) async {
      await openLogger(tester);
      await openSheet(tester);
      await tester.enterText(find.byType(TextField).first, 'First note');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await settle(tester, rounds: 2);
      await tester.pump(const Duration(seconds: 6));
      await openSheet(tester);
      expect(find.text('First note'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
      await tester.pump(const Duration(seconds: 6));
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('the sheet fits - ${dark ? 'dark' : 'light'}, text x$scale', (tester) async {
          await openLogger(tester, scale: scale, dark: dark);
          await openSheet(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Save'), findsOneWidget);
          expect(tester.getRect(find.text('Save')).bottom, lessThanOrEqualTo(800), reason: 'Save is on screen, not below the fold');
          await tester.enterText(find.byType(TextField).first, 'A longer note about the meeting that wraps over a few lines on a phone screen.');
          await tester.tap(find.text('Save'));
          await tester.pump();
          await settle(tester, rounds: 2);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 6));
        });
      }
    }
  });
}
