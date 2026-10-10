import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A function Firebase Messaging calls from native code must be top-level AND carry
// @pragma('vm:entry-point'), or a release (AOT) build removes it and background /
// closed-app notifications fail ("To closurize ... from native code, it must be
// annotated"). Both of the Guide app's registrations are checked.
void main() {
  test('handleBG is a top-level function with the entry-point pragma (no instance-method copy)', () {
    final src = File('lib/Services/Notifications.dart').readAsStringSync();
    final at = src.indexOf('Future<void> handleBG(RemoteMessage message) async {');
    expect(at, greaterThan(0));
    expect(src.lastIndexOf('\n', at) + 1, at, reason: 'declared at column 0');
    expect(at, lessThan(src.indexOf('class FirebaseCM')));
    expect(src.substring(0, at).trimRight(), endsWith("@pragma('vm:entry-point')"));
    expect(src.contains('  Future<void> handleBG('), isFalse);
  });

  test('every background-message registration names an annotated top-level function', () {
    var found = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r'onBackgroundMessage\(\s*(\w+)').allMatches(src)) {
        found++;
        final name = m.group(1)!;
        final decl = RegExp(r'^(?:Future<void>|void) ' + name + r'\(', multiLine: true).firstMatch(src);
        expect(decl, isNotNull, reason: '$name in ${f.path} is not a top-level function');
        expect(src.substring(0, decl!.start).trimRight(), endsWith("@pragma('vm:entry-point')"),
            reason: '$name in ${f.path} is not annotated');
      }
    }
    expect(found, 2, reason: 'main.dart and Services/Notifications.dart');
  });
}
