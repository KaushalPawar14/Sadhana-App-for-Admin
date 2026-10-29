import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AdminManager.dart';
import 'package:folk_guide_app/Pages/AssociationManager.dart';
import 'package:folk_guide_app/Pages/BoysDetails.dart';
import 'package:folk_guide_app/Pages/ChantingChallengeManager.dart';
import 'package:folk_guide_app/Pages/ExpeditionManager.dart';
import 'package:folk_guide_app/Pages/GuideCalendarPage.dart';
import 'package:folk_guide_app/Pages/StudentProfilePage.dart';
import 'package:folk_guide_app/widgets/GuideAppearanceSheet.dart';
import 'package:folk_guide_app/widgets/GuideDialog.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// The dialogs and bottom sheets reachable with one tap from a screen: opened for real,
/// light and dark at 360 dp, text scale 1.0 and 1.6 - nothing overflows, nothing is
/// clipped, every button is at least 48 dp tall.
class _Case {
  const _Case(this.name, this.screen, this.tap, {this.expectDialog = true, this.byIcon});
  final String name;
  final Widget Function() screen;
  final String? tap;
  final bool expectDialog;
  final IconData? byIcon;
}

final cases = <_Case>[
  _Case('add_admin', () => const AdminManagerPage(), 'Add admin'),
  _Case('add_student', () => const Scaffold(body: AdminControlPage()), 'Add student'),
  _Case('new_meeting_sheet', () => const AssociationManagerPage(), 'New Meeting', expectDialog: false),
  _Case('new_challenge', () => const ChantingChallengeManagerPage(), 'New Challenge', expectDialog: false),
  _Case('new_trip', () => const ExpeditionManagerPage(), 'New Trip', expectDialog: false),
  _Case('add_event_text', () => const GuideCalendarPage(selectedGuide: 'G'), 'Add text', expectDialog: false),
  _Case('residence_sheet', () => const StudentProfilePage(studentUid: 's1'), null, expectDialog: false, byIcon: Icons.edit_outlined),
  _Case('appearance_sheet', () => Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showGuideAppearanceSheet(c), child: const Text('Open appearance'))))), 'Open appearance', expectDialog: false),
  _Case('confirm_dialog', () => Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showDialog<void>(context: c, builder: (_) => GuideDialog(title: const Text('Remove this admin?'), content: const Text('Their students become Unassigned and they can no longer sign in. This cannot be undone, so please check the name before you continue with a long enough sentence to wrap.'), actions: [TextButton(onPressed: () {}, child: const Text('Cancel')), TextButton(onPressed: () {}, child: const Text('Remove admin'))])), child: const Text('Open dialog'))))), 'Open dialog'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  for (final c in cases) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('${c.name} · ${dark ? 'dark' : 'light'} · ×$scale', (tester) async {
          await prepareApp(tester);
          await pumpScreen(tester, c.screen(), scale: scale, dark: dark);
          await letDataArrive(tester);
          final target = c.tap != null
              ? find.text(c.tap!).first
              : find.byIcon(c.byIcon!).first;
          await tester.ensureVisible(target);
          await tester.tap(target, warnIfMissed: false);
          await tester.pump();
          await letDataArrive(tester, frames: 8);
          expect(tester.takeException(), isNull, reason: 'opening');
          if (c.expectDialog) expect(find.byType(GuideDialog), findsOneWidget);
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull, reason: 'open');
          if (scale == 1.0) await shot(tester, 'dialogs/${c.name}_${dark ? 'dark' : 'light'}');
          // every real button inside is at least 48 dp tall
          for (final b in find.byType(TextButton).evaluate().map((e) => e.widget)) {
            final r = tester.getRect(find.byWidget(b));
            expect(r.height, greaterThanOrEqualTo(47.5), reason: 'a TextButton is shorter than 48 dp');
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 8));
        });
      }
    }
  }
}
