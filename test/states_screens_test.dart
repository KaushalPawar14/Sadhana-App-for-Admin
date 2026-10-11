import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/Pages/WeeklyPlanning.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/GoalData.dart';
import 'package:folk_guide_app/utils/WeekData.dart';
import 'package:folk_guide_app/widgets/GuideExpandable.dart';
import 'package:folk_guide_app/widgets/GuideGhost.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';

import 'screens_test.dart' show FakeWeekData, profile, target;
import 'support/fake_snapshots.dart';
import 'support/guide_test_support.dart';

/// Week data whose two streams are released by hand.
class ManualWeekData extends FakeWeekData {
  ManualWeekData() : super(targetList: const []);
  final logsC = StreamController<QuerySnapshot>.broadcast();
  final assocC = StreamController<QuerySnapshot>.broadcast();
  int logListens = 0;

  @override
  Stream<QuerySnapshot> interactionLogs() {
    logListens++;
    return logsC.stream;
  }

  @override
  Stream<QuerySnapshot> associations() => assocC.stream;
}

class ManualGoalData implements GoalData {
  final c = StreamController<List<CompoundTarget>>.broadcast();
  int listens = 0;
  @override
  Stream<List<CompoundTarget>> targets(String guideId) {
    listens++;
    return c.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() {
    WeekData.instance = const FirestoreWeekData();
    GoalData.instance = const FirestoreGoalData();
    AdminProfileProvider.instance.debugSet(null);
  });

  group('This Week', () {
    Future<ManualWeekData> open(WidgetTester tester, {double scale = 1.0}) async {
      phone(tester, scale);
      AdminProfileProvider.instance.debugSet(profile('GUIDE'));
      final data = ManualWeekData();
      WeekData.instance = data;
      await tester.pumpWidget(guideHost(const WeeklyPlanningPage(), reduce: false));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      return data;
    }

    testWidgets('loading: the hero is real, each waiting section is a ghost card; no spinner', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(GuideHeroPanel), findsOneWidget);
      // follow-ups and overdue are still waiting (the fakes answer the other two at once)
      expect(find.byType(GuideGhostOf), findsNWidgets(2));
      expect(GhostClock.instance.running, isTrue);
    });

    for (final scale in kScales) {
      testWidgets('a section ghost has the size of its card (text scale $scale)', (tester) async {
        final data = await open(tester, scale: scale);
        await tester.pump(const Duration(milliseconds: 600));
        final ghost = tester.getRect(find.byType(GuideGhostOf).first);
        data.logsC.add(FakeSnap([]));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(find.text('Follow-ups due'), findsOneWidget);
        final card = tester.getRect(find.byType(GuideExpandableCard).first);
        // the ghost's box carries the card's 12 dp top gap; its fill leaves it out
        expect(card.height + 12, closeTo(ghost.height, 0.5));
        expect(card.top, closeTo(ghost.top + 12, 0.5));
        expect(card.left, closeTo(ghost.left, 0.5));
        expect(card.width, closeTo(ghost.width, 0.5));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a failed section shows a frozen ghost, a message and Retry; Retry listens again', (tester) async {
      final data = await open(tester);
      data.logsC.addError('permission-denied');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Could not load this'), findsOneWidget);
      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.text('Nothing scheduled this week'), findsNothing, reason: 'a failure is not "nothing"');
      final before = data.logListens;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(data.logListens, greaterThan(before));
      data.logsC.add(FakeSnap([]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Follow-ups due'), findsOneWidget);
    });

    testWidgets('once everything has loaded no ticker remains', (tester) async {
      final data = await open(tester);
      data.logsC.add(FakeSnap([]));
      data.assocC.add(FakeSnap([]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // calendar context + targets are served by the (finished) fake futures/streams
      await tester.pumpAndSettle();
      expect(GhostClock.instance.running, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('Your targets', () {
    Future<ManualGoalData> open(WidgetTester tester, {double scale = 1.0}) async {
      phone(tester, scale);
      AdminProfileProvider.instance.debugSet(profile('GUIDE'));
      final data = ManualGoalData();
      GoalData.instance = data;
      await tester.pumpWidget(guideHost(const GoalHomePage(guideId: 'G'), reduce: false));
      await tester.pump(const Duration(milliseconds: 20));
      return data;
    }

    testWidgets('loading: two ghost cards, the pinned button stays real, no spinner', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(GuideGhostOf), findsNWidgets(2));
      expect(find.text('New target'), findsOneWidget);
    });

    for (final scale in kScales) {
      testWidgets('ghost -> cards: same top and height (text scale $scale)', (tester) async {
        final data = await open(tester, scale: scale);
        await tester.pump(const Duration(milliseconds: 300));
        final ghost = tester.getRect(find.byType(GuideGhostOf).first);
        data.c.add([target('chanting', 20, 16, 1, 8)]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final card = tester.getRect(find
            .descendant(of: find.byKey(const ValueKey('content')), matching: find.byType(Card).evaluate().isEmpty ? find.byType(Column) : find.byType(Card))
            .first);
        expect(card.top, closeTo(ghost.top, 14.5), reason: 'only the entry rise differs, never the layout');
        await tester.pumpAndSettle();
        expect(find.text('Chanting rounds'), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
        expect(GhostClock.instance.running, isFalse);
      });
    }

    testWidgets('no targets: a still ghost with the explanation', (tester) async {
      final data = await open(tester);
      data.c.add([]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('No active targets yet'), findsOneWidget);
      expect(GhostClock.instance.running, isFalse);
    });

    testWidgets('a failure: a frozen ghost, a short message and Retry', (tester) async {
      final data = await open(tester);
      data.c.addError('boom');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Could not load your targets'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      final before = data.listens;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(data.listens, greaterThan(before));
    });
  });
}
