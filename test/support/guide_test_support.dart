import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysWorkspace.dart';
import 'package:folk_guide_app/theme/GuideTheme.dart';

/// Opens every closed history section of a student's board card that has lines (the card shows seven collapsible categories).
Future<void> openAllHistorySections(WidgetTester tester) async {
  for (final k in ['interactions', 'surrender', 'sadhana', 'books', 'trips', 'worries', 'doubts']) {
    final header = find.byKey(ValueKey('history-cat-header-$k'));
    if (header.evaluate().isEmpty || find.byKey(ValueKey('history-cat-lines-$k')).evaluate().isNotEmpty) continue;
    if (tester.widget<Text>(find.byKey(ValueKey('history-cat-count-$k'))).data == '0') continue;
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }
}

/// The text scales every new / changed widget is checked at.
const List<double> kScales = [1.0, 1.3, 1.6];

/// The app's real fonts, so text measures the way it does on a phone (the test
/// default font is much wider).
Future<void> loadGuideFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await load('Inter', [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]);
  await load('Fraunces', ['Fraunces-Medium.ttf', 'Fraunces-SemiBold.ttf']);
  await load('Satoshi', ['Satoshi-Regular.ttf', 'Satoshi-Medium.ttf', 'Satoshi-Bold.ttf']);
}

/// A 360 x 800 dp phone at [scale] text size.
void phone(WidgetTester tester, double scale, {Size size = const Size(360, 800), bool resetBoardMemory = true}) {
  // each test starts with a board that has never been shown (it remembers its last answers between visits)
  if (resetBoardMemory) FolkBoysWorkspace.debugResetBoardMemory();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// The widget in the real theme, light or dark, with "reduce animations" on by
/// default (so nothing is mid-animation when a test measures).
Widget guideHost(Widget child, {bool dark = false, bool reduce = true, List<NavigatorObserver> observers = const []}) => MaterialApp(
      navigatorObservers: observers,
      debugShowCheckedModeBanner: false,
      theme: GuideTheme.light,
      darkTheme: GuideTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: c!,
      ),
      home: child,
    );

/// No widget laid out wider than the screen or taller than needed.
void expectNoOverflow(WidgetTester tester, {String? reason}) {
  expect(tester.takeException(), isNull, reason: reason);
}

/// Writes a PNG of what is on screen (for looking at; never asserted). The output
/// folder is D:/tmp-fl/shots unless GUIDE_SHOTS is set.
Future<void> shot(WidgetTester tester, String name, {GlobalKey? key}) async {
  final dir = Directory(Platform.environment['GUIDE_SHOTS'] ?? 'D:/tmp-fl/shots');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary = (key?.currentContext?.findRenderObject() ??
        tester.binding.renderViews.first) as dynamic;
    ui.Image image;
    if (boundary is RenderRepaintBoundary) {
      image = await boundary.toImage(pixelRatio: 2);
    } else {
      // The root render view: capture its first layer.
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      image = await layer.toImage(Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio, pixelRatio: 2);
    }
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${dir.path}/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
