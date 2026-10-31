import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// THE PLANS UPDATE THEMSELVES: there is no Refresh button anywhere (guide or HOD), no "Refresh all guides", and no refresh limit or countdown. The page keeps
// "Updated <time>"; the badge counts what is NEW (see plan_page_test.dart).

void main() {
  final files = [
    for (final e in Directory('lib').listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e,
  ];

  test('no Refresh button, no "Refresh all guides", no refresh limit or countdown anywhere in the app', () {
    const banned = [
      'Refresh all guides',
      "label: 'Refresh'",
      'kPlanRefreshGap',
      "'plan-refresh'",
      "'plan-refresh-all'",
      "'plan-refresh-wait'",
      "'plan-refresh-error'",
      'You can refresh again',
      'HierarchyApi.instance.refreshPlan',
      'Tap Refresh',
    ];
    final found = <String>[];
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final b in banned) {
        if (text.contains(b)) found.add('${f.path}: $b');
      }
    }
    expect(found, isEmpty, reason: 'the plan updates by itself: no refresh UI may be left');
  });

  test('the Plan page keeps "Updated <time>", counts what is NEW, clears the badge at once when the admin LOOKS (opens the page or the list) and again when he LEAVES', () {
    final plan = File('lib/Pages/PlanPage.dart').readAsStringSync();
    expect(plan, contains("return 'Updated \$stamp';"));
    expect(plan, contains('PlanData.instance.newChanges(_me, forPage: true)'));
    // looking (opening the page, opening the list) clears the badge at once, locally; leaving does it once more for what arrived meanwhile
    final dispose = plan.substring(plan.indexOf('void dispose()'), plan.indexOf('Widget build(BuildContext context)'));
    expect(dispose, contains('PlanData.instance.leftPlan(_me)'));
    final init = plan.substring(plan.indexOf('void initState()'), plan.indexOf('void dispose()'));
    expect(init, contains('PlanData.instance.looked(_me, save: false)'));
  });
}
