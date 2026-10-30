import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/theme/AgentLook.dart' show contrastRatio;
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/utils/PlanTopicActions.dart';
import 'package:folk_guide_app/widgets/Guide3dButton.dart';

import 'support/guide_test_support.dart';

/// THE 3D ACTION BUTTON: a raised button (soft gradient, a glossy top highlight, a solid edge and a soft shadow), pressing it moves the face down and
/// shrinks the shadows, 48 dp at least, the label readable (at least 4.5:1) in light and dark; disabled is flat and clearly different.

Future<void> _pump(WidgetTester tester, Widget button, {bool dark = false, double scale = 1.0, Size size = const Size(360, 400)}) async {
  phone(tester, scale, size: size);
  await tester.pumpWidget(guideHost(Scaffold(body: Center(child: button)), dark: dark, reduce: false));
  await tester.pump();
}

BoxDecoration _face(WidgetTester tester) => tester.widget<AnimatedContainer>(find.byKey(const ValueKey('btn3d-face'))).decoration! as BoxDecoration;
double _sink(WidgetTester tester) => tester.widget<AnimatedContainer>(find.byKey(const ValueKey('btn3d-face'))).transform!.getTranslation().y;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  testWidgets('LOOK: a gradient face from the assistant sky blue, a glossy highlight, a solid edge AND a soft shadow, rounded', (tester) async {
    await _pump(tester, Guide3dButton(label: 'Record interaction', onPressed: () {}));
    final d = _face(tester);
    expect(d.gradient, isA<LinearGradient>());
    expect((d.gradient! as LinearGradient).colors.length, 3, reason: 'top, middle, bottom of the face');
    expect(d.borderRadius, isNotNull);
    expect(d.boxShadow!.length, 2, reason: 'the edge under the face and the soft drop shadow');
    expect(d.boxShadow!.first.blurRadius, 0, reason: 'the edge is solid: the "thickness"');
    expect(d.boxShadow!.last.blurRadius, greaterThan(0));
    expect(find.byKey(const ValueKey('btn3d-gloss')), findsOneWidget);
    expect(find.text('Record interaction'), findsOneWidget);
  });

  testWidgets('PRESS ANIMATION: while pressed the face moves DOWN and the shadows shrink; released, it comes back; the layout never moves', (tester) async {
    await _pump(tester, Guide3dButton(label: 'Update book', onPressed: () {}));
    final box = tester.getRect(find.byType(Guide3dButton));
    final rest = _face(tester);
    expect(_sink(tester), 0);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Update book')));
    await tester.pump(const Duration(milliseconds: 150));
    final down = _face(tester);
    expect(_sink(tester), Guide3dButton.sink, reason: 'it sinks onto its edge');
    expect(down.boxShadow!.first.offset.dy, lessThan(rest.boxShadow!.first.offset.dy), reason: 'the edge shrinks');
    expect(down.boxShadow!.last.offset.dy, lessThan(rest.boxShadow!.last.offset.dy), reason: 'the drop shadow shrinks');
    expect(down.boxShadow!.last.blurRadius, lessThan(rest.boxShadow!.last.blurRadius));
    expect(tester.getRect(find.byType(Guide3dButton)), box, reason: 'no layout jump');
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_sink(tester), 0);
  });

  testWidgets('A TAP CALLS onPressed once; it opens things, it never ticks anything itself', (tester) async {
    var n = 0;
    await _pump(tester, Guide3dButton(label: 'Open meeting', onPressed: () => n++));
    await tester.tap(find.text('Open meeting'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(n, 1);
  });

  testWidgets('DISABLED: flat and clearly different (no gradient, no gloss, no shadow, muted label), and a tap does nothing', (tester) async {
    var n = 0;
    await _pump(tester, const Guide3dButton(label: 'Assign book', onPressed: null));
    final d = _face(tester);
    expect(d.gradient, isNull);
    expect(d.boxShadow, isEmpty);
    expect(find.byKey(const ValueKey('btn3d-gloss')), findsNothing);
    await tester.tap(find.text('Assign book'), warnIfMissed: false);
    expect(n, 0);
    final g = Theme.of(tester.element(find.byType(Guide3dButton))).extension<GuideColors>()!;
    expect(tester.widget<Text>(find.text('Assign book')).style!.color, g.mutedText);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale: 48 dp at least, the label contrast is at least 4.5:1 on every stop of the gradient, no overflow with the longest label', (tester) async {
        await _pump(tester, SizedBox(width: 160, child: Guide3dButton(label: kTopicActionLabels[TopicAction.changeCommitment]!, onPressed: () {})), dark: dark, scale: scale);
        expect(tester.takeException(), isNull);
        final r = tester.getRect(find.byType(Guide3dButton));
        expect(r.height, greaterThanOrEqualTo(48));
        final g = Theme.of(tester.element(find.byType(Guide3dButton))).extension<GuideColors>()!;
        final label = tester.widget<Text>(find.text('Change commitment')).style!.color!;
        for (final stop in (_face(tester).gradient! as LinearGradient).colors) {
          expect(contrastRatio(label, stop), greaterThanOrEqualTo(4.5), reason: 'label on $stop');
        }
        expect(label, g.onAgent);
        expect(contrastRatio(g.mutedText, g.chipBackground), greaterThanOrEqualTo(3.0), reason: 'disabled stays readable');
      });
    }
  }

  testWidgets('EVERY ACTION LABEL fits on a phone width, and each of the seven is a raised button', (tester) async {
    await _pump(
      tester,
      SingleChildScrollView(child: Column(children: [for (final a in TopicAction.values) Guide3dButton(label: kTopicActionLabels[a]!, onPressed: () {})])),
      size: const Size(320, 900),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Guide3dButton), findsNWidgets(7));
  });
}
