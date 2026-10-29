import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/GoalData.dart';
import 'package:folk_guide_app/widgets/GuideGhost.dart';

import 'screens_test.dart' show profile, target;
import 'support/guide_test_support.dart';

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
    GoalData.instance = const FirestoreGoalData();
    AdminProfileProvider.instance.debugSet(null);
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
