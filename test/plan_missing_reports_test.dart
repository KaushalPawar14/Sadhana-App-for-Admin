import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/GuideButtons.dart';

import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

/// The Plan's third tab, MISSING REPORTS: students with no daily report for 5+ days (or never), a note on top, ONE button per student (Ignore, with a
/// confirmation), the reason the guide told the AI under his name. Not an interaction.

class _FakePlanData extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PendingChanges> pending(String adminId) => const Stream.empty();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => DateTime.utc(2026, 10, 30, 4, 30);
}

const _missing = [
  MissingReport(studentUid: 'm0', studentName: 'Never Neel', label: 'Never reported'),
  MissingReport(studentUid: 'm8', studentName: 'Eight Eshan', label: 'No report for 8 days', days: 8, reason: 'His phone broke'),
  MissingReport(studentUid: 'm5', studentName: 'Five Farid', label: 'No report for 5 days', days: 5),
];

Future<_FakePlanData> _open(WidgetTester tester, {bool dark = false, double scale = 1.0, List<MissingReport> missing = _missing, bool tab = true}) async {
  phone(tester, scale, size: const Size(360, 1400));
  AdminProfileProvider.instance.debugSet(AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []}));
  final data = _FakePlanData();
  PlanData.instance = data;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(guideHost(const PlanPage(), dark: dark));
  data.controller.add(planDoc(left: 0, missing: missing));
  await tester.pump();
  await tester.pump();
  if (tab) {
    await tester.tap(find.byKey(const ValueKey('plan-tab-missing')));
    await tester.pumpAndSettle();
  }
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDown(() => HierarchyApi.useForTests(null));
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  testWidgets('THE THIRD TAB: "MISSING REPORTS (3)" beside Today and This week; the note on top; one card per student with "No report for N days" / "Never reported"', (tester) async {
    await _open(tester, tab: false);
    expect(find.byKey(const ValueKey('plan-tab-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-tab-week')), findsOneWidget);
    expect(find.text('MISSING REPORTS (3)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-tab-missing')));
    await tester.pumpAndSettle();
    expect(find.text('You can ask him the reason — tell the AI what he said. Otherwise, ignore.'), findsOneWidget);
    for (final m in _missing) {
      expect(find.byKey(ValueKey('plan-missing-${m.studentUid}')), findsOneWidget, reason: m.studentName);
      expect(tester.widget<Text>(find.byKey(ValueKey('plan-missing-label-${m.studentUid}'))).data, m.label);
    }
    // it is not the interactions: none of Today's batch card is here
    expect(find.byKey(const ValueKey('plan-batch')), findsNothing);
    expect(find.text('Never reported'), findsOneWidget);
    expect(find.text('No report for 8 days'), findsOneWidget);
  });

  testWidgets('THE REASON the guide told the AI shows under his name; a student with none shows no reason line', (tester) async {
    await _open(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-missing-reason-m8'))).data, 'Reason: His phone broke');
    expect(find.byKey(const ValueKey('plan-missing-reason-m5')), findsNothing);
  });

  testWidgets('ONE BUTTON per student: "Ignore" and nothing else (no tick box, no other button) inside any card', (tester) async {
    await _open(tester);
    for (final m in _missing) {
      final card = find.byKey(ValueKey('plan-missing-${m.studentUid}'));
      expect(find.descendant(of: card, matching: find.byType(GuideSecondaryButton)), findsOneWidget, reason: m.studentName);
      final others = find.descendant(of: card, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton || w is Checkbox || w is Switch || w is IconButton || w is FloatingActionButton || w is GuidePrimaryButton));
      expect(others, findsNothing, reason: '${m.studentName}: no other button of any kind');
      expect(find.descendant(of: card, matching: find.text('Ignore')), findsOneWidget);
    }
  });

  testWidgets('IGNORE asks first: Cancel does nothing; Confirm tells the server (report_ignore) and the student leaves the tab at once; the others stay', (tester) async {
    final calls = <Map<String, dynamic>>[];
    HierarchyApi.useForTests((name, data) async {
      if (name == 'studentGuideNote') calls.add(data);
      return {'ok': true, 'message': 'Ignoring Eight Eshan\'s daily reports.'};
    });
    await _open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('plan-ignore-m8')));
    await tester.tap(find.byKey(const ValueKey('plan-ignore-m8')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-ignore-title')), findsOneWidget);
    expect(find.textContaining('counts 0'), findsOneWidget, reason: 'the dialog says what ignoring does');
    await tester.tap(find.byKey(const ValueKey('plan-ignore-cancel')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty, reason: 'cancelled: nothing sent');
    expect(find.byKey(const ValueKey('plan-missing-m8')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-ignore-m8')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-ignore-confirm')));
    await tester.pumpAndSettle();
    expect(calls, [
      {'studentUid': 'm8', 'kind': 'report_ignore'}
    ]);
    expect(find.byKey(const ValueKey('plan-missing-m8')), findsNothing, reason: 'gone at once');
    expect(find.byKey(const ValueKey('plan-missing-m5')), findsOneWidget);
    expect(find.text('MISSING REPORTS (2)'), findsOneWidget, reason: 'the count follows');
  });

  testWidgets('a failed Ignore says so and the student stays in the tab', (tester) async {
    HierarchyApi.useForTests((name, data) async => throw HierarchyException('not-found', 'I can\'t find that student among your students.'));
    await _open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('plan-ignore-m5')));
    await tester.tap(find.byKey(const ValueKey('plan-ignore-m5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-ignore-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('I can\'t find that student among your students.'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-missing-m5')), findsOneWidget);
  });

  testWidgets('a student leaves the tab when the server\'s new plan no longer lists him (he reported again, or was ignored)', (tester) async {
    final data = await _open(tester);
    data.controller.add(planDoc(left: 0, missing: const [MissingReport(studentUid: 'm0', studentName: 'Never Neel', label: 'Never reported')]));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('plan-missing-m8')), findsNothing);
    expect(find.byKey(const ValueKey('plan-missing-m0')), findsOneWidget);
  });

  testWidgets('NOBODY MISSING: a calm line, no cards', (tester) async {
    await _open(tester, missing: const []);
    expect(find.byKey(const ValueKey('plan-missing-empty')), findsOneWidget);
    expect(find.text('MISSING REPORTS (0)'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: three tabs and the cards fit, the button is 44 dp or more', (tester) async {
        await _open(tester, dark: dark, scale: scale, tab: false);
        expect(tester.takeException(), isNull);
        final tabs = ['plan-tab-today', 'plan-tab-week', 'plan-tab-missing'].map((k) => tester.getRect(find.byKey(ValueKey(k)))).toList();
        for (final r in tabs) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360.5));
          expect(r.height, greaterThanOrEqualTo(48));
        }
        await tester.tap(find.byKey(const ValueKey('plan-tab-missing')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byKey(const ValueKey('plan-missing-m8')));
        expect(card.right, lessThanOrEqualTo(360.5));
        expect(tester.getSize(find.byKey(const ValueKey('plan-ignore-m8'))).height, greaterThanOrEqualTo(44));
      });
    }
  }
}
