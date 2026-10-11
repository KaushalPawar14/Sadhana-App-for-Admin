import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// The notification small icon: Android draws it as a WHITE SILHOUETTE (only the alpha channel
// counts), so it must be a white glyph on a transparent background, in every density, wired
// into the manifest and the notification code, and kept by release shrinking. (The full-colour
// launcher icon used to be used, which became a plain white square.)
const _res = 'android/app/src/main/res';
const _densities = {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final d in _densities.entries) {
    testWidgets('ic_stat_notification ${d.key}: ${d.value} px, white on transparent, no colour', (tester) async {
      final file = File('$_res/drawable-${d.key}/ic_stat_notification.png');
      expect(file.existsSync(), isTrue);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final image = (await codec.getNextFrame()).image;
        expect([image.width, image.height], [d.value, d.value]);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
        var opaque = 0;
        var transparent = 0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          final a = bytes.getUint8(i + 3);
          if (a > 0) {
            // every visible pixel is pure white (the glyph's softness is in the alpha only)
            expect([bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2)], [255, 255, 255]);
          }
          if (a > 200) opaque++;
          if (a == 0) transparent++;
        }
        expect(opaque, greaterThan(d.value), reason: 'there is a glyph');
        expect(transparent, greaterThan(d.value * d.value ~/ 3), reason: 'and a transparent background');
        // the corners are transparent (no background square)
        for (final p in [0, (d.value - 1) * 4, d.value * (d.value - 1) * 4, (d.value * d.value - 1) * 4]) {
          expect(bytes.getUint8(p + 3), 0);
        }
      });
    });
  }

  test('the manifest uses it as the default notification icon, with the brand colour', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(m, contains('com.google.firebase.messaging.default_notification_icon'));
    expect(m, contains('@drawable/ic_stat_notification'));
    expect(m, contains('com.google.firebase.messaging.default_notification_color'));
    expect(m, contains('@color/notification_color'));
    expect(File('$_res/values/colors.xml').readAsStringSync().replaceAll(RegExp(r'\s+'), ' '),
        contains('<color name="notification_color">#A9812F</color>'));
  });

  test('release shrinking keeps the drawable (a keep rule)', () {
    final keep = File('$_res/raw/keep.xml').readAsStringSync();
    expect(keep, contains('@drawable/ic_stat_notification'));
  });

  test('every notification the app shows uses it (init and details), never the launcher icon as the small icon', () {
    for (final f in ['lib/Services/Notifications.dart', 'lib/Services/LocalNotification.dart']) {
      final src = File(f).readAsStringSync();
      expect(src, contains("AndroidInitializationSettings('@drawable/ic_stat_notification')"), reason: f);
      expect(src.contains("AndroidInitializationSettings('@mipmap/ic_launcher')"), isFalse, reason: f);
      expect(src, contains("icon: 'ic_stat_notification'"), reason: f);
      expect(src, contains('GuideColors.notificationAccent'), reason: f);
      expect(src, contains("DrawableResourceAndroidBitmap('@mipmap/ic_launcher')"), reason: 'the full-colour logo is the large icon: $f');
    }
  });
}
