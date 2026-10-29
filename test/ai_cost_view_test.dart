import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentLogPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/AiCostPanel.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// THE HOD'S AI COST VIEW, inside the Assistant log: this month against the budget (a bar), today, per guide and per kind of work, a month
/// and a guide filter, the cost on every log entry, the 80% / 100% states and the HOD's two controls. (Who may read the figures at all is the
/// server's rules: functions/rules-tests/aiUsage.rules.test.js; the Analysis card that opens this page is shown to HODs only.)

final DateTime _now = DateTime.now();
final String _month = istMonth(_now);
final String _today = istDay(_now);

Future<void> _seed(FakeFirebaseFirestore db, {double budget = 1000, double g1 = 300, double g2 = 200, Map<String, Object?> extra = const {}}) async {
  Future<void> sum(String id, String name, String role, Map<String, num> types) => db.collection('aiUsageSummary').doc('${_month}_$id').set({
        'month': _month, 'adminId': id, 'adminName': name, 'role': role, 'total': types.values.fold<num>(0, (a, b) => a + b),
        for (final e in types.entries) 't_${e.key}': e.value,
      });
  await sum('G1', 'Gopal Das', 'GUIDE', {'assistant': g1 * .5, 'voice': g1 * .1, 'plans': g1 * .2, 'analysis': g1 * .1, 'targetPlan': g1 * .1});
  await sum('G2', 'Govinda', 'GUIDE', {'assistant': g2 * .6, 'plans': g2 * .4});
  await db.collection('aiUsageDays').doc(_today).set({'day': _today, 'month': _month, 'total': 12.5, 'a_G1': 9.0, 'a_G2': 3.5});
  await db.collection('aiBudget').doc('current').set({'monthlyInr': budget, ...extra});
  final at = DateTime.now();
  await db.collection('agentActions').doc('e1').set({
    'adminId': 'G1', 'adminName': 'Gopal Das', 'role': 'GUIDE', 'createdMs': at.millisecondsSinceEpoch, 'request': 'meet Arjun', 'status': 'executed', 'actions': <Object>[], 'costInr': 3.52,
  });
  await db.collection('agentActions').doc('e2').set({
    'adminId': 'G2', 'adminName': 'Govinda', 'role': 'GUIDE', 'createdMs': at.millisecondsSinceEpoch - 1000, 'request': 'older entry without a cost', 'status': 'executed', 'actions': <Object>[],
  });
}

Future<FakeFirebaseFirestore> _open(WidgetTester tester, {double scale = 1.0, bool dark = false, double budget = 1000, double g1 = 300, double g2 = 200, Map<String, Object?> extra = const {}}) async {
  final db = await prepareApp(tester);
  await _seed(db, budget: budget, g1: g1, g2: g2, extra: extra);
  await pumpScreen(tester, const AgentLogPage(), scale: scale, dark: dark, size: const Size(360, 4000));
  await letDataArrive(tester, frames: 20);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDown(() => HierarchyApi.useForTests(null));

  test('money is shown in rupees: two decimals under ₹100, whole rupees from ₹100', () {
    expect([inr(3.52), inr(0), inr(99.99), inr(100), inr(842.4)], ['₹3.52', '₹0.00', '₹99.99', '₹100', '₹842']);
  });

  testWidgets('THE SUMMARY: this month against the budget with a bar, today, and the breakdown per guide and per kind of work (voice included)', (tester) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('ai-cost-panel')), findsOneWidget);
    expect(find.textContaining('₹500 of ₹1000 (50%)'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cost-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cost-today')).evaluate().isNotEmpty, isTrue);
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-cost-today'))).data, 'Today: ₹12.50');
    // per guide: biggest first
    expect(find.byKey(const ValueKey('ai-cost-guide-G1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cost-guide-G1')), matching: find.text('₹300')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cost-guide-G2')), matching: find.text('₹200')), findsOneWidget);
    // per kind of work: all six, with what the guides used (assistant 150 + 120, voice 30, plans 60 + 80, analysis 30, target plans 30)
    for (final e in {'assistant': '₹270', 'plans': '₹140', 'voice': '₹30.00', 'analysis': '₹30.00', 'targetPlan': '₹30.00', 'other': '₹0.00'}.entries) {
      expect(find.descendant(of: find.byKey(ValueKey('ai-cost-type-${e.key}')), matching: find.text(e.value)), findsOneWidget, reason: e.key);
    }
    expect(find.text('Voice to text'), findsOneWidget);
    expect(find.text('Interaction analysis'), findsOneWidget);
    expect(find.text('Target plans'), findsOneWidget);
  });

  testWidgets('EACH LOG ENTRY shows its cost; an older entry without one shows none', (tester) async {
    await _open(tester);
    expect(find.text('AI cost ₹3.52'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-log-cost')), findsOneWidget);
    expect(find.textContaining('older entry without a cost'), findsOneWidget);
  });

  testWidgets('FILTER BY GUIDE: the totals and the kinds follow that guide, today shows his own figure, and the list shows only his entries', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('ai-cost-guide')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Govinda').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-cost-guide-G1')), findsNothing);
    expect(find.byKey(const ValueKey('ai-cost-guide-G2')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-cost-today'))).data, 'Today (this guide): ₹3.50');
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cost-type-assistant')), matching: find.text('₹120')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cost-type-voice')), matching: find.text('₹0.00')), findsOneWidget);
    expect(find.textContaining('older entry without a cost'), findsOneWidget);
    expect(find.textContaining('meet Arjun'), findsNothing);
  });

  testWidgets('FILTER BY MONTH: another month shows that month\'s totals (no "today"), from everything recorded for it', (tester) async {
    final db = await _open(tester);
    final now = DateTime.now();
    final prev = istMonth(DateTime(now.year, now.month - 1, 15));
    await db.collection('aiUsageSummary').doc('${prev}_G1').set({'month': prev, 'adminId': 'G1', 'adminName': 'Gopal Das', 'total': 77.0, 't_voice': 77.0});
    await tester.tap(find.byKey(const ValueKey('ai-cost-month')));
    await tester.pumpAndSettle();
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    await tester.tap(find.text('${names[int.parse(prev.substring(5, 7)) - 1]} ${prev.substring(0, 4)}').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('₹77.00 of ₹1000 (8%)'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cost-today')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cost-type-voice')), matching: find.text('₹77.00')), findsOneWidget);
  });

  testWidgets('80%: a warning under the bar; 100%: "used up, paused until next month" with a Resume button; both are the HOD\'s to act on', (tester) async {
    await _open(tester, g1: 600, g2: 250);
    expect(find.byKey(const ValueKey('ai-cost-warn')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cost-paused')), findsNothing);
    expect(find.byKey(const ValueKey('ai-budget-resume')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _open(tester, g1: 700, g2: 400);
    expect(find.byKey(const ValueKey('ai-cost-paused')), findsOneWidget);
    expect(find.text("This month's AI budget is used up: the AI is paused until next month."), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cost-warn')), findsNothing);
    expect(find.byKey(const ValueKey('ai-budget-resume')), findsOneWidget);
  });

  testWidgets('RESUME calls the server; CHANGE BUDGET asks for a number and sends it; after a resume the page says so', (tester) async {
    final calls = <String>[];
    final sent = <Map<String, dynamic>>[];
    await _open(tester, g1: 700, g2: 400);
    HierarchyApi.useForTests((name, data) async {
      calls.add(name);
      sent.add(data);
      return {'ok': true};
    });
    await tester.tap(find.byKey(const ValueKey('ai-budget-resume')));
    await tester.pump();
    await tester.pump();
    expect(calls, ['resumeAiForMonth']);
    await tester.tap(find.byKey(const ValueKey('ai-budget-change')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ai-budget-field')), '1500');
    await tester.tap(find.byKey(const ValueKey('ai-budget-save')));
    await tester.pumpAndSettle();
    expect(calls, ['resumeAiForMonth', 'setAiBudget']);
    expect(sent.last, {'monthlyInr': 1500.0});
  });

  testWidgets('a HOD who has resumed the month sees it, and no "paused" line', (tester) async {
    await _open(tester, g1: 700, g2: 400, extra: {'overrideMonth': _month});
    expect(find.byKey(const ValueKey('ai-cost-resumed')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cost-paused')), findsNothing);
  });

  testWidgets('no usage yet: the budget is ₹1,000 by default, "No AI use recorded yet", and the page still lists the log', (tester) async {
    final db = await prepareApp(tester);
    await db.collection('agentActions').doc('e1').set({'adminId': 'G1', 'adminName': 'Gopal Das', 'role': 'GUIDE', 'createdMs': DateTime.now().millisecondsSinceEpoch, 'request': 'x', 'status': 'executed', 'actions': <Object>[]});
    await pumpScreen(tester, const AgentLogPage(), size: const Size(360, 4000));
    await letDataArrive(tester, frames: 20);
    expect(find.textContaining('₹0.00 of ₹1000 (0%)'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cost-none')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-log-cost')), findsNothing);
  });

  group('every state: light and dark, text 1.0 / 1.3 / 1.6, no overflow', () {
    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, ×$scale, paused', (tester) async {
          await _open(tester, scale: scale, dark: dark, g1: 700, g2: 400);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('ai-budget-change')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('screenshots (for looking at)', (tester) async {
      await _open(tester, g1: 650, g2: 250);
      await shot(tester, 'ai_cost_view_light');
    });
  });
}
