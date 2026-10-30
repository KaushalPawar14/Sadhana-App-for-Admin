import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentLogPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/theme/AgentLook.dart' show contrastRatio;
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/AiCostPanel.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// THE HOD'S COST VIEW COVERS THE STUDENT APP (student chat, daily messages, web answers), the last seven days, and CREDIT TOP-UPS: each top-up
/// (date, $, ₹), the estimated credit left = top-ups − tracked spend, a warning at 20% left, the days left at the current rate. HOD only (the
/// server's callables and rules check; the page is only ever built for a HOD).

final DateTime _now = DateTime.now();
final String _month = istMonth(_now);
final String _today = istDay(_now);
final String _twoDaysAgo = istDay(_now.subtract(const Duration(days: 2)));

Future<void> _seed(FakeFirebaseFirestore db) async {
  Future<void> sum(String id, String name, String role, Map<String, num> types, {String scope = 'guide'}) => db.collection('aiUsageSummary').doc('${_month}_$id').set({
        'month': _month, 'adminId': id, 'adminName': name, 'role': role, 'scope': scope, 'total': types.values.fold<num>(0, (a, b) => a + b),
        for (final e in types.entries) 't_${e.key}': e.value,
      });
  await sum('G1', 'Gopal Das', 'GUIDE', {'assistant': 150, 'plans': 150});
  await sum('G2', 'Govinda', 'GUIDE', {'assistant': 120, 'plans': 80});
  await sum('student-app', 'Student app', 'STUDENT_APP', {'studentChat': 25, 'studentDaily': 10, 'studentWeb': 5}, scope: 'student');
  await db.collection('aiUsageDays').doc(_today).set({'day': _today, 'month': _month, 'total': 52.5, 's_total': 40, 'a_G1': 9.0, 'a_G2': 3.5, 'a_student-app': 40});
  await db.collection('aiUsageDays').doc(_twoDaysAgo).set({'day': _twoDaysAgo, 'month': _month, 'total': 20, 'a_G1': 20});
  await db.collection('aiBudget').doc('current').set({'monthlyInr': 1000});
  await db.collection('agentActions').doc('e1').set({'adminId': 'G1', 'adminName': 'Gopal Das', 'role': 'GUIDE', 'createdMs': DateTime.now().millisecondsSinceEpoch, 'request': 'meet Arjun', 'status': 'executed', 'actions': <Object>[]});
}

Map<String, dynamic> _credit({
  bool has = true,
  double left = 340,
  double leftUsd = 3.86,
  double pct = .77,
  bool low = false,
  bool out = false,
  int? days = 3,
  double perDay = 100,
  List<Map<String, dynamic>>? topups,
}) =>
    {
      'hasTopups': has,
      'topups': topups ?? [{'id': 't1', 'date': '2026-10-30', 'usd': 5, 'inr': 440}],
      'topupInr': 440, 'topupUsd': 5, 'spentInr': 440 - left, 'spentUsd': 5 - leftUsd, 'remainingInr': left, 'remainingUsd': leftUsd,
      'leftPct': pct, 'low': low, 'out': out, 'perDayInr': perDay, 'daysLeft': days, 'usdInr': 88,
    };

class _Calls {
  final List<(String, Map<String, dynamic>)> log = [];
  int get credit => log.where((c) => c.$1 == 'aiCreditView').length;
  List<Map<String, dynamic>> of(String name) => [for (final c in log) if (c.$1 == name) c.$2];
}

Future<_Calls> _open(WidgetTester tester, {Map<String, dynamic>? credit, double scale = 1.0, bool dark = false}) async {
  await tester.pumpWidget(const SizedBox()); // a fresh page every time (the credit is read when it opens)
  final calls = _Calls();
  var current = credit ?? _credit();
  final db = await prepareApp(tester);
  HierarchyApi.useForTests((name, data) async {
    calls.log.add((name, data));
    if (name == 'aiCreditView') return current;
    if (name == 'addAiTopup') {
      current = _credit(topups: [
        {'id': 't2', 'date': data['date'], 'usd': data['usd'], 'inr': data['inr'] ?? (data['usd'] as num) * 88},
        {'id': 't1', 'date': '2026-10-30', 'usd': 5, 'inr': 440},
      ]);
    }
    if (name == 'deleteAiTopup') current = _credit(has: false, topups: []);
    return {'ok': true};
  });
  await _seed(db);
  await pumpScreen(tester, const AgentLogPage(), scale: scale, dark: dark, size: const Size(360, 6000));
  await letDataArrive(tester, frames: 20);
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDown(() => HierarchyApi.useForTests(null));

  testWidgets('THE STUDENT APP IS IN THE VIEW: its three kinds of AI, its total and the all-spending total; the guide budget counts only the guides', (tester) async {
    await _open(tester);
    expect(find.textContaining('₹500 of ₹1000 (50%)'), findsOneWidget, reason: 'the guides only: the student app is not in the budget');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-cost-student-total'))).data, 'Student app: ₹40.00');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-cost-grand-total'))).data, 'All AI spending: ₹540');
    for (final e in {'studentChat': '₹25.00', 'studentDaily': '₹10.00', 'studentWeb': '₹5.00'}.entries) {
      expect(find.descendant(of: find.byKey(ValueKey('ai-cost-type-${e.key}')), matching: find.text(e.value)), findsOneWidget, reason: e.key);
    }
    expect(find.text('Student chat'), findsOneWidget);
    expect(find.text('Daily messages'), findsOneWidget);
    expect(find.text('Web answers'), findsOneWidget);
    // the guides list has the guides, not the student app
    expect(find.byKey(const ValueKey('ai-cost-guide-G1')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cost-guide-student-app')), findsNothing);
    // the guide types are unchanged
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cost-type-assistant')), matching: find.text('₹270')), findsOneWidget);
  });

  testWidgets('TODAY and the LAST 7 DAYS: today shows the guides / students split; each day with spending is listed with its total', (tester) async {
    await _open(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-cost-today'))).data, 'Today: ₹52.50 (guides ₹12.50, students ₹40.00)');
    expect(find.byKey(ValueKey('ai-cost-day-$_today')), findsOneWidget);
    expect(find.byKey(ValueKey('ai-cost-day-$_twoDaysAgo')), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('ai-cost-day-$_today')), matching: find.text('₹52.50')), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('ai-cost-day-$_today')), matching: find.textContaining('students ₹40.00')), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('ai-cost-day-$_twoDaysAgo')), matching: find.text('₹20.00')), findsOneWidget);
  });

  testWidgets('FILTER BY GUIDE hides the student section and the student share of the days', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('ai-cost-guide')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gopal Das').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-cost-student-total')), findsNothing);
    expect(find.byKey(const ValueKey('ai-cost-type-studentChat')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-cost-today'))).data, 'Today (this guide): ₹9.00');
  });

  testWidgets('THE CREDIT: estimated credit left in rupees and dollars, the bar, the arithmetic and the days left at the current rate', (tester) async {
    final calls = await _open(tester);
    expect(calls.credit, greaterThanOrEqualTo(1));
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-credit-left'))).data, 'Estimated credit left: ₹340 (\$3.86)');
    expect(find.byKey(const ValueKey('ai-credit-bar')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-credit-math'))).data, 'Top-ups ₹440 (\$5.00) − spent ₹100 (\$1.14)');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-credit-days'))).data, 'At the current rate (₹100 a day), about 3 days left.');
    expect(find.byKey(const ValueKey('ai-credit-low')), findsNothing);
    expect(find.byKey(const ValueKey('ai-credit-out')), findsNothing);
    expect(find.text('2026-10-30   \$5.00   ₹440'), findsOneWidget, reason: 'the top-up list');
  });

  testWidgets('WARNING at 20% left, and when the credit is gone; no estimate of days when nothing has been spent', (tester) async {
    await _open(tester, credit: _credit(left: 80, leftUsd: .9, pct: .18, low: true, days: 1));
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-credit-low'))).data, 'Only 18% of the credit is left. Top up soon.');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-credit-days'))).data, 'At the current rate (₹100 a day), about 1 day left.');
    await _open(tester, credit: _credit(left: -20, leftUsd: -.2, pct: 0, low: true, out: true, days: 0));
    expect(find.byKey(const ValueKey('ai-credit-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-credit-low')), findsNothing, reason: 'the stronger message replaces it');
    await _open(tester, credit: _credit(days: null, perDay: 0));
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-credit-days'))).data, 'No spending lately, so no estimate of the days left.');
  });

  testWidgets('NO TOP-UP YET: a plain line and the Add button', (tester) async {
    await _open(tester, credit: _credit(has: false, topups: []));
    expect(find.byKey(const ValueKey('ai-credit-none')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-credit-left')), findsNothing);
    expect(find.byKey(const ValueKey('ai-topup-add')), findsOneWidget);
  });

  testWidgets('ADD A TOP-UP: date, dollars and rupees go to the server (₹ left empty is not sent) and the estimate is read again', (tester) async {
    final calls = await _open(tester);
    final before = calls.credit;
    await tester.ensureVisible(find.byKey(const ValueKey('ai-topup-add')));
    await tester.tap(find.byKey(const ValueKey('ai-topup-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ai-topup-date')), '2026-10-31');
    await tester.enterText(find.byKey(const ValueKey('ai-topup-usd')), '10');
    await tester.enterText(find.byKey(const ValueKey('ai-topup-inr')), '905.5');
    await tester.tap(find.byKey(const ValueKey('ai-topup-save')));
    await tester.pumpAndSettle();
    expect(calls.of('addAiTopup'), [
      {'date': '2026-10-31', 'usd': 10.0, 'inr': 905.5}
    ]);
    expect(calls.credit, greaterThan(before), reason: 'the estimate was read again');
    expect(find.text('2026-10-31   \$10.00   ₹906'), findsOneWidget, reason: 'the new top-up is in the list');
    // ₹ left empty: only the dollars are sent
    await tester.ensureVisible(find.byKey(const ValueKey('ai-topup-add')));
    await tester.tap(find.byKey(const ValueKey('ai-topup-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ai-topup-usd')), '5');
    await tester.tap(find.byKey(const ValueKey('ai-topup-save')));
    await tester.pumpAndSettle();
    expect(calls.of('addAiTopup').last.containsKey('inr'), isFalse);
    // no dollars: nothing is sent
    final n = calls.of('addAiTopup').length;
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars(); // the earlier 'Top-up saved' notes
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('ai-topup-add')));
    await tester.tap(find.byKey(const ValueKey('ai-topup-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-topup-save')));
    await tester.pumpAndSettle();
    expect(calls.of('addAiTopup').length, n);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Enter the amount in US dollars.'), findsOneWidget);
  });

  testWidgets('REMOVING a top-up asks first; Cancel does nothing; Remove tells the server and the list is read again', (tester) async {
    final calls = await _open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('ai-topup-delete-t1')));
    await tester.tap(find.byKey(const ValueKey('ai-topup-delete-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Remove this top-up?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls.of('deleteAiTopup'), isEmpty);
    await tester.tap(find.byKey(const ValueKey('ai-topup-delete-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-topup-delete-confirm')));
    await tester.pumpAndSettle();
    expect(calls.of('deleteAiTopup'), [
      {'id': 't1'}
    ]);
    expect(find.byKey(const ValueKey('ai-credit-none')), findsOneWidget);
  });

  testWidgets('a failed server call says so (the estimate cannot be worked out)', (tester) async {
    final db = await prepareApp(tester);
    HierarchyApi.useForTests((name, data) async => name == 'aiCreditView' ? throw HierarchyException('internal', 'x') : {'ok': true});
    await _seed(db);
    await pumpScreen(tester, const AgentLogPage(), size: const Size(360, 6000));
    await letDataArrive(tester, frames: 20);
    expect(find.byKey(const ValueKey('ai-credit-error')), findsOneWidget);
  });

  test('THE WARNING IS LEGIBLE: the red warning text has at least 4.5:1 on the card in light and dark', () {
    expect(contrastRatio(GuideColors.light.danger, GuideColors.light.surface), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(GuideColors.dark.danger, GuideColors.dark.surface), greaterThanOrEqualTo(4.5));
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: the cost view and the credit card fit; the remove button is 48 dp', (tester) async {
        await _open(tester, dark: dark, scale: scale, credit: _credit(low: true, left: 80, pct: .18));
        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byKey(const ValueKey('ai-credit-panel')));
        expect(card.right, lessThanOrEqualTo(360.5));
        final del = tester.getSize(find.byKey(const ValueKey('ai-topup-delete-t1')));
        expect(del.height, greaterThanOrEqualTo(48));
        expect(del.width, greaterThanOrEqualTo(48));
      });
    }
  }
}
