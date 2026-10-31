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
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/widgets/GuideGhost.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

/// Home data that the test releases by hand.
class ManualHomeData implements HomeData {
  final targetsC = StreamController<List<CompoundTarget>>.broadcast();
  /// The guide's plan (Home's two plan widgets read it); [pumpHome] and the ghost shots install it as PlanData.instance.
  final plan = ManualPlanData();
  final countC = StreamController<int>.broadcast();
  Completer<List<CalendarEvent>> eventsC = Completer();
  int targetListens = 0;

  @override
  Stream<List<CompoundTarget>> targets(String guide) {
    targetListens++;
    return targetsC.stream;
  }

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
/// THIS WEEK, the real card (not the ghost's placeholder of it).
final Finder loadedWeek = find.descendant(of: find.byKey(const ValueKey('content')), matching: find.byKey(const ValueKey('home-this-week')));
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
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  Future<ManualHomeData> pumpHome(WidgetTester tester, {double scale = 1.0, bool dark = false}) async {
    // tall, so the whole Home (the targets card is three tiles and a button now) is built and measured
    phone(tester, scale, size: const Size(360, 3000));
    AdminProfileProvider.instance.debugSet(me());
    final data = ManualHomeData();
    HomeData.instance = data;
    PlanData.instance = data.plan;
    await tester.pumpWidget(guideHost(
      const Scaffold(body: FolkBoysEntryScreen(selectedGuide: 'G')),
      dark: dark,
      reduce: false,
    ));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    return data;
  }

  testWidgets('loading: ghost hero, the tasks card, one targets card and two tiles, no spinner, one shared clock', (tester) async {
    await pumpHome(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('content')), findsNothing);
    // hero + today's tasks + the targets card + 2 tiles
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
      final todayGhost = tester.getRect(find.byType(GuideGhostOf).at(1));
      final tilesGhost = tester.getRect(find.byType(GuideGhostOf).at(3));
      final listHeight = tester.getSize(find.byType(ListView)).height;
      final scrollExtent = tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent;

      data.targetsC.add([target('chanting', 2), target('books', 3)]);
      data.plan.c.add(planDoc(left: 3, today: [interactionItem('u1', 'Ravi', ['sadhana'])]));
      data.countC.add(20);
      data.eventsC.complete(<CalendarEvent>[]);
      await tester.pump();
      // During the cross-fade nothing moves.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.getRect(loadedWeek).top, heroGhost.top);
        expect(tester.getRect(loadedWeek).height, heroGhost.height);
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(loadedWeek), heroGhost);
      expect(tester.getRect(find.byKey(const ValueKey('home-today-tasks'))), todayGhost, reason: "today's tasks card has the ghost's size and place");
      // the tiles keep their size; they sit under the targets card, whose height depends on the message it shows (one line when both
      // targets are set, two when one is missing), so their top may differ from the ghost's by that difference only
      final tiles = tester.getRect(find.descendant(of: find.byKey(const ValueKey('tiles')), matching: find.byType(GuideGradientTile)).first);
      expect(tiles.height, closeTo(tilesGhost.height, .01));
      expect((tiles.top - tilesGhost.top).abs(), lessThan(60));
      expect(tester.getSize(find.byType(ListView)).height, listHeight);
      // the Targets widget is the third tile of the row
      expect(find.byKey(const ValueKey('home-targets-tile')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0, reason: 'no ticker once the ghosts are gone');
      expect(GhostClock.instance.running, isFalse);
      expect(scrollExtent, greaterThanOrEqualTo(0));
    });
  }

  testWidgets('the hero numbers count up once; a live update does not replay it', (tester) async {
    final data = await pumpHome(tester);
    data.targetsC.add([target('chanting', 2)]);
    data.plan.c.add(planDoc(left: 7));
    data.countC.add(5);
    data.eventsC.complete(<CalendarEvent>[]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsWidgets);
    // A live update: replaced at once, nothing animating.
    data.plan.c.add(planDoc(left: 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('5'), findsWidgets);
  });

  testWidgets('no targets: a still ghost with one friendly line and an action', (tester) async {
    final data = await pumpHome(tester);
    data.targetsC.add([]);
    data.plan.c.add(planDoc());
    data.countC.add(0);
    data.eventsC.complete(<CalendarEvent>[]);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('home-targets-tile')), matching: find.text('None set')), findsOneWidget, reason: 'the Targets widget says so');
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
    data.plan.c.add(planDoc());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(loadedWeek, findsOneWidget);
  });

  testWidgets('the shell: Home ghosts breathe only while Home is the tab on screen', (tester) async {
    phone(tester, 1.0);
    AdminProfileProvider.instance.debugSet(me());
    final data = ManualHomeData();
    HomeData.instance = data;
    PlanData.instance = data.plan;
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
      testWidgets('Board, Calendar and Targets tiles: ONE row, equal, square (${dark ? 'dark' : 'light'}, text scale $scale)', (tester) async {
        final data = await pumpHome(tester, scale: scale, dark: dark);
        data.targetsC.add([target('chanting', 2)]);
        data.plan.c.add(planDoc());
        data.countC.add(24);
        data.eventsC.complete(<CalendarEvent>[]);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final tiles = find.descendant(of: find.byKey(const ValueKey('tiles')), matching: find.byType(GuideGradientTile));
        expect(tiles, findsNWidgets(3));
        final a = tester.getRect(tiles.at(0));
        final b = tester.getRect(tiles.at(1));
        final c = tester.getRect(tiles.at(2));
        expect([a.top, b.top], [c.top, c.top], reason: 'ONE row');
        for (final r in [a, b]) {
          expect(r.width, closeTo(c.width, 0.01), reason: 'exactly the same size and style');
          expect(r.height, closeTo(c.height, 0.01), reason: 'exactly the same size and style');
        }
        expect(a.width, closeTo((360 - 40 - 24) / 3, 0.5));
        expect(a.height, greaterThanOrEqualTo(a.width));
        expect(b.left - a.right, closeTo(12, 0.5));
        expect(c.left - b.right, closeTo(12, 0.5));
        // nothing is clipped: the whole text of both is inside its tile
        for (final text in ['FOLK Boys Board', 'Calendar', '24 boys', 'Nothing due today', 'Targets', '1 active']) {
          final r = tester.getRect(find.descendant(of: tiles, matching: find.text(text)).first);
          final home = [a, b, c].firstWhere((x) => x.contains(r.topLeft), orElse: () => Rect.zero);
          expect(home, isNot(Rect.zero), reason: text);
          expect(r.bottom, lessThanOrEqualTo(home.bottom + 0.5), reason: '$text is clipped');
        }
      });
    }
  }

  testWidgets('with the dot showing, the three tiles are still the same size', (tester) async {
    final data = await pumpHome(tester);
    data.targetsC.add([]);
    data.plan.c.add(planDoc());
    data.countC.add(3);
    data.eventsC.complete(<CalendarEvent>[]);
    await tester.pump();
    await tester.pumpAndSettle();
    final tiles = find.descendant(of: find.byKey(const ValueKey('tiles')), matching: find.byType(GuideGradientTile));
    for (var i = 1; i < 3; i++) {
      expect(tester.getSize(tiles.at(i)).width, closeTo(tester.getSize(tiles.at(0)).width, 0.01));
      expect(tester.getSize(tiles.at(i)).height, closeTo(tester.getSize(tiles.at(0)).height, 0.01));
    }
  });
}
