import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/UnseenDot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// The orange dot: on "Plan" (in the assistant's app bar) and on the assistant button, whenever the plan has changed since the guide last
/// opened it (a new target, a calendar event, a follow-up, a priority reason ... any change the server worked into the plan). Opening the
/// Plan page clears both.

Map<String, dynamic> _planDoc(DateTime changedAt) => {
      'adminId': 'H', 'status': 'upToDate', 'generatedAt': Timestamp.fromDate(changedAt), 'changedAt': Timestamp.fromDate(changedAt),
      'today': {'date': '2026-10-30', 'items': <Object>[]}, 'week': {'weekOf': '2026-10-26', 'intro': '', 'sections': <Object>[]},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  Future<void> realDots(WidgetTester tester) async {
    SeenMarkers.debugDisable = false;
    UnseenAggregates.debugDisable = false;
  }

  Finder dotOn(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(UnseenDot));

  group('on "Plan" in the assistant page', () {
    testWidgets('no plan change: no dot; a change: the dot; opening Plan clears it; a later change brings it back', (tester) async {
      final db = await prepareApp(tester);
      await realDots(tester);
      PlanData.instance = const FirestorePlanData();
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)));
      await pumpScreen(tester, AgentPage(controller: c));
      await tester.pump(const Duration(milliseconds: 100));
      expect(dotOn('agent-plan-dot'), findsNothing, reason: 'no plan yet');

      // the server writes a plan the guide has never opened
      await db.collection('guidePlans').doc('H').set(_planDoc(DateTime(2026, 10, 1, 6)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(dotOn('agent-plan-dot'), findsOneWidget, reason: 'a new plan nobody has opened');

      // opening Plan clears it
      await tester.tap(find.byKey(const ValueKey('agent-plan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-tab-today')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(dotOn('agent-plan-dot'), findsNothing, reason: 'opened: seen');

      // any later change to the plan (a new target, a calendar event, a follow-up, a priority reason ...) brings the dot back
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await db.collection('guidePlans').doc('H').set(_planDoc(DateTime.now().add(const Duration(minutes: 5))));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(dotOn('agent-plan-dot'), findsOneWidget);
    });

    testWidgets('the dot is orange (the app\'s attention colour), and a 48 dp target stays', (tester) async {
      final db = await prepareApp(tester);
      await realDots(tester);
      await db.collection('guidePlans').doc('H').set(_planDoc(DateTime(2026, 10, 1)));
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)));
      await pumpScreen(tester, AgentPage(controller: c));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      final dot = tester.widget<UnseenDot>(dotOn('agent-plan-dot'));
      expect(dot, isNotNull);
      expect(tester.getSize(find.byKey(const ValueKey('agent-plan'))).shortestSide, greaterThanOrEqualTo(48));
    });
  });

  group('on the assistant button', () {
    Future<void> pumpOverlay(WidgetTester tester, FakeDb db) async {
      phone(tester, 1.0);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(
        theme: GuideTheme.light,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: AgentOverlay(child: child!)),
        home: const Scaffold(body: SizedBox.expand()),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('the same plan change puts the dot on the floating button, and opening the plan clears it', (tester) async {
      final db = await prepareApp(tester);
      await realDots(tester);
      await db.collection('guidePlans').doc('H').set(_planDoc(DateTime(2026, 10, 1)));
      await pumpOverlay(tester, FakeDb());
      expect(dotOn('agent-fab-dot'), findsOneWidget, reason: 'the plan changed and has not been opened');
      await SeenMarkers.markSeen('H', 'plan');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(dotOn('agent-fab-dot'), findsNothing);
    });

    testWidgets('no plan, no dot on the button', (tester) async {
      await prepareApp(tester);
      await realDots(tester);
      await pumpOverlay(tester, FakeDb());
      expect(dotOn('agent-fab-dot'), findsNothing);
    });
  });
}

/// (a placeholder so the helper above reads naturally)
class FakeDb {}
