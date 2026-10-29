import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/widgets/GuideGate.dart';

import 'support/guide_test_support.dart';

/// The sign-in / gate card keeps a card-like width (480 dp) on a computer and fills the width on a phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  Future<double> cardWidth(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(guideHost(const GuideGate(icon: Icons.login, title: 'FOLK Guides', message: 'Sign in', action: SizedBox(key: ValueKey('act'), height: 40))));
    await tester.pump();
    return tester.getSize(find.byKey(const ValueKey('act'))).width;
  }

  testWidgets('1440 wide: the card is 480 dp minus its 56 dp padding', (tester) async {
    expect(await cardWidth(tester, const Size(1440, 900)), 480 - 56);
  });

  testWidgets('phone: fills the width', (tester) async {
    expect(await cardWidth(tester, const Size(390, 800)), 390 - 56);
  });
}
