import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';
import 'system_back_test.dart' show keyboardUp, openIt, pumpHost, systemBack;

/// The control for system_back_test.dart: the pattern the interactions screen used to have, run through the
/// same harness, MUST fail with "used after being disposed" - so a green system_back_test means something.
/// It lives in its own file because the build error it provokes leaves the widget tree of that test unusable.

/// What the interactions screen used to do: the controller belongs to the screen, and is disposed the moment the
/// sheet's future completes - while the sheet is still sliding away.
class _OldPatternPage extends StatelessWidget {
  const _OldPatternPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final controller = TextEditingController();
              await showModalBottomSheet<void>(
                context: context,
                builder: (_) => Padding(padding: const EdgeInsets.all(20), child: TextField(controller: controller)),
              );
              controller.dispose();
            },
            child: const Text('Sheet'),
          ),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  testWidgets('control: the harness DOES catch the old pattern (controller disposed when the sheet completes)', (tester) async {
    await prepareApp(tester);
    await pumpHost(tester, () => const _OldPatternPage());
    await openIt(tester);
    await tester.tap(find.text('Sheet'));
    await tester.pump();
    await letDataArrive(tester, frames: 8);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await keyboardUp(tester);
    final original = FlutterError.onError;
    final seen = <String>[];
    FlutterError.onError = (details) => seen.add(details.exceptionAsString());
    addTearDown(() => FlutterError.onError = original);
    await systemBack(tester, keyboardUp: true);
    expect(seen, isNotEmpty, reason: 'the old pattern must fail here, or this file proves nothing');
    expect(seen.any((e) => e.contains('TextEditingController was used after being disposed')), isTrue, reason: seen.join(' | '));
  });
}
