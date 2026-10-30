import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/CompoundGoalProgressPage.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('A TARGET PAGE HAS A DELETE BUTTON IN ITS APP BAR; IT ASKS FIRST AND CANCEL KEEPS EVERYTHING', (tester) async {
    await prepareApp(tester);
    await pumpScreen(tester, const CompoundGoalProgressPage(guideId: 'G', targetId: 't1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('target-delete')), findsOneWidget, reason: 'the button is in the app bar');
    await tester.tap(find.byKey(const ValueKey('target-delete')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Delete this target?'), findsOneWidget, reason: 'it asks first');
    expect(find.byKey(const ValueKey('confirm-delete-target')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Delete this target?'), findsNothing);
    expect(find.byType(CompoundGoalProgressPage), findsOneWidget, reason: 'cancel changes nothing');
  });
}
