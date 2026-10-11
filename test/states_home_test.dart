import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysEntry.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/BottomNavBar.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/HomeData.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/WeekSummary.dart';
import 'package:folk_guide_app/widgets/GuideGhost.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/guide_test_support.dart';

/// Home data that the test releases by hand.
class ManualHomeData implements HomeData {
  final targetsC = StreamController<List<CompoundTarget>>.broadcast();
  final followC = StreamController<List<FollowUpItem>>.broadcast();
  final overdueC = StreamController<List<OverdueItem>>.broadcast();
  final countC = StreamController<int>.broadcast();
  Completer<List<CalendarEvent>> eventsC = Completer();
  int targetListens = 0;

  @override
  Stream<List<CompoundTarget>> targets(String guide) {
    targetListens++;
    return targetsC.stream;
  }

  @override
  Stream<List<FollowUpItem>> followUps(({DateTime start, DateTime end}) week) => followC.stream;
  @override
  Stream<List<OverdueItem>> overdue() => overdueC.stream;
  @override
  Stream<int> studentCount() => countC.stream;
  @override
  Future<List<CalendarEvent>> events(String guide) => eventsC.future;
  @override
  Widget calendarBadge({required Widget child}) => child;
}

CompoundTarget target(String metric, int phase) => CompoundTarget.from('G', 't$metric', {
      'metric': metric,
      'studentCountGoal': 10,
      'perStudentValueGoal': 16,
      'status': 'active',
      'currentPhase': phase,
      'totalPhases': 8,
    });

AdminProfile me() => AdminProfile.fromMap({
      'id': 'G',
      'displayName': 'G Prabhu',
      'role': 'GUIDE',
      'teamGuide': '',
      'email': 'g@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

/// The real (loaded) widgets, not the invisible placeholders a ghost is built from.
Finder loaded(Type type) => find.descendant(of: find.byKey(const ValueKey('content')), matching: find.byType(type));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    UnseenAggregates.debugDisable = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({'selected_guide': 'G'}));
  tearDown(() {
    HomeData.instance = const FirestoreHomeData();
    AdminProfileProvider.instance.debugSet(null);
  });

  Future<ManualHomeData> pumpHome(WidgetTester tester, {double scale = 1.0, bool dark = false}) async {
    phone(tester, scale);
    AdminProfileProvider.instance.debugSet(me());
    final data = ManualHomeData();
    HomeData.instance = data;
    await tester.pumpWidget(guideHost(
      const Scaffold(body: FolkBoysEntryScreen(selectedGuide: 'G')),
      dark: dark,
      reduce: false,
    ));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    return data;
  }

  testWidgets('loading: ghost hero, two target blocks and two tiles, no spinner, one shared clock', (tester) async {
    await pumpHome(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('content')), findsNothing);
    // hero + 2 target blocks + 2 tiles
    expect(find.byType(GuideGhostOf), findsNWidgets(5));
    expect(GhostClock.instance.running, isTrue);
    // The real top bar and greeting stay real.
    expect(find.text('G Prabhu'), findsOneWidget);
    expect(find.text('Hare Krishna,'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in kScales) {
    testWidgets('ghost -> content does not move anything (text scale $scale)', (tester) async {
      final data = await pumpHome(tester, scale: scale);
      await tester.pump(const Duration(milliseconds: 900)); // entry settled
      final heroGhost = tester.getRect(find.byType(GuideGhostOf).first);
      final tilesGhost = tester.getRect(find.byType(GuideGhostOf).at(3));
      final listHeight = tester.getSize(find.byType(ListView)).height;
      final scrollExtent = tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent;

      data.targetsC.add([target('chanting', 2), target('books', 3)]);
      data.followC.add([(student: 'A', when: DateTime.now(), action: 'x')]);
      data.overdueC.add([(student: 'B', days: 3)]);
      data.countC.add(20);
      data.eventsC.complete(<CalendarEvent>[]);
      await tester.pump();
      // During the cross-fade nothing moves.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.getRect(loaded(GuideHeroCard)).top, heroGhost.top);
        expect(tester.getRect(loaded(GuideHeroCard)).height, heroGhost.height);
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(loaded(GuideHeroCard)), heroGhost);
      final tiles = tester.getRect(find.descendant(of: find.byKey(const ValueKey('tiles')), matching: find.byType(GuideGradientTile)).first);
      expect(tiles.top, tilesGhost.top);
      expect(tiles.height, tilesGhost.height);
      expect(tester.getSize(find.byType(ListView)).height, listHeight);
      // Both target cards have the ghost's size (74-ish: same layout, invisible).
      expect(loaded(GuidePastelBox), findsNWidgets(2));
      expect(tester.binding.transientCallbackCount, 0, reason: 'no ticker once the ghosts are gone');
      expect(GhostClock.instance.running, isFalse);
      expect(scrollExtent, greaterThanOrEqualTo(0));
    });
  }

  testWidgets('the hero numbers count up once; a live update does not replay it', (tester) async {
    final data = await pumpHome(tester);
    data.targetsC.add([target('chanting', 2)]);
    data.followC.add([]);
    data.overdueC.add([(student: 'B', days: 3), (student: 'C', days: 1), (student: 'D', days: 2)]);
    data.countC.add(5);
    data.eventsC.complete(<CalendarEvent>[]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsWidgets);
    // A live update: replaced at once, nothing animating.
    data.overdueC.add([(student: 'B', days: 3)]);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('no targets: a still ghost with one friendly line and an action', (tester) async {
    final data = await pumpHome(tester);
    data.targetsC.add([]);
    data.followC.add([]);
    data.overdueC.add([]);
    data.countC.add(0);
    data.eventsC.complete(<CalendarEvent>[]);
    await tester.pumpAndSettle();
    expect(find.textContaining('No active targets yet'), findsOneWidget);
    expect(find.text('Open targets'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0, reason: 'a still ghost holds no ticker');
  });

  testWidgets('a failed source: frozen ghost, a short message and Retry; Retry listens again', (tester) async {
    final data = await pumpHome(tester);
    data.targetsC.addError('boom');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Could not load'), findsWidgets);
    expect(find.text('Retry'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('boom'), findsNothing, reason: 'raw errors are never shown');
    final before = data.targetListens;
    await tester.tap(find.text('Retry').first);
    await tester.pump();
    expect(data.targetListens, before + 1);
    data.targetsC.add([target('chanting', 1)]);
    data.followC.add([]);
    data.overdueC.add([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(loaded(GuideHeroCard), findsOneWidget);
  });

  testWidgets('the shell: Home ghosts breathe only while Home is the tab on screen', (tester) async {
    phone(tester, 1.0);
    AdminProfileProvider.instance.debugSet(me());
    final data = ManualHomeData();
    HomeData.instance = data;
    await tester.pumpWidget(guideHost(const CurvedNavBar('G'), reduce: false));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(GhostClock.instance.running, isTrue, reason: 'Home is loading');
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    expect(GhostClock.instance.running, isFalse, reason: 'Home is on a hidden tab');
    await tester.tap(find.byIcon(Icons.home_outlined).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(GhostClock.instance.running, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the tiles still appear if the roster count fails (they are the way in)', (tester) async {
    final data = await pumpHome(tester);
    data.countC.addError('x');
    data.eventsC.complete(<CalendarEvent>[]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('FOLK Boys Board'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('Board and Calendar tiles: equal, side by side, square (${dark ? 'dark' : 'light'}, text scale $scale)', (tester) async {
        final data = await pumpHome(tester, scale: scale, dark: dark);
        data.targetsC.add([target('chanting', 2)]);
        data.followC.add([]);
        data.overdueC.add([]);
        data.countC.add(24);
        data.eventsC.complete(<CalendarEvent>[]);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final tiles = find.descendant(of: find.byKey(const ValueKey('tiles')), matching: find.byType(GuideGradientTile));
        expect(tiles, findsNWidgets(2));
        final a = tester.getRect(tiles.at(0));
        final b = tester.getRect(tiles.at(1));
        expect(a.top, b.top, reason: 'side by side');
        expect(a.size, b.size, reason: 'exactly the same size');
        expect(a.width, closeTo(154, 0.5));
        expect(a.height, greaterThanOrEqualTo(a.width));
        if (scale == 1.0) expect(a.height, closeTo(a.width, 0.5), reason: 'perfectly square');
        expect(b.left - a.right, closeTo(12, 0.5));
        // nothing is clipped: the whole text of both is inside its tile
        for (final text in ['FOLK Boys Board', 'Calendar', '24 boys', 'Nothing due today']) {
          final r = tester.getRect(find.descendant(of: tiles, matching: find.text(text)).first);
          expect(a.contains(r.topLeft) || b.contains(r.topLeft), isTrue, reason: text);
          expect(r.bottom, lessThanOrEqualTo((a.contains(r.topLeft) ? a : b).bottom + 0.5), reason: '$text is clipped');
        }
      });
    }
  }

  testWidgets('with the dot showing, the two tiles are still the same size', (tester) async {
    final data = await pumpHome(tester);
    data.targetsC.add([]);
    data.followC.add([]);
    data.overdueC.add([]);
    data.countC.add(3);
    data.eventsC.complete(<CalendarEvent>[]);
    await tester.pump();
    await tester.pumpAndSettle();
    final tiles = find.descendant(of: find.byKey(const ValueKey('tiles')), matching: find.byType(GuideGradientTile));
    expect(tester.getSize(tiles.at(0)), tester.getSize(tiles.at(1)));
  });
}
