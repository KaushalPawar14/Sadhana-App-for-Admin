import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'all_screens_test.dart' show screens;
import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// A debugging aid (not part of the suite's meaning): pumps ONE screen named by the
/// SCREEN environment variable and prints every Flutter error with its widget chain.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  final name = Platform.environment['SCREEN'];
  if (name == null) return;
  final scale = double.tryParse(Platform.environment['SCALE'] ?? '') ?? 1.0;
  final dark = Platform.environment['DARK'] == '1';

  testWidgets('debug $name', (tester) async {
    await prepareApp(tester);
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = old);
    await pumpScreen(tester, screens[name]!(), scale: scale, dark: dark, reduce: false);
    await tester.pump(const Duration(milliseconds: 30));
    await letDataArrive(tester);
    await tester.pump(const Duration(seconds: 7));
    for (final e in errors) {
      debugPrint('=== ${e.exceptionAsString()}');
      debugPrint(e.informationCollector?.call().map((n) => n.toString()).join('\n') ?? '');
      debugPrint(e.stack.toString().split('\n').where((l) => l.contains('/lib/') || l.contains('lib\\')).take(6).join('\n'));
    }
    debugPrint('ERRORS: ${errors.length}');
  });
}
