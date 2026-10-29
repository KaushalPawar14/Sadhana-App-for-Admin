import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/Responsive.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';

import 'all_screens_test.dart' show screens;
import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// COMPACT DESKTOP SIZES: EVERY screen of the app at 1280, 1440 and 1920 wide (the website). Square tiles keep a tile size and flow into a grid,
/// cards and lists keep a comfortable width, and nothing stretches across the window. The phone is checked by the rest of the suite
/// (`all_screens_test`, `screens_test` ...), which this change leaves exactly as it was.

const _sizes = [Size(1280, 800), Size(1440, 900), Size(1920, 1080)];

/// Screens that are meant to fill the window (a board) or are not content pages.
const _skip = {'force_update', 'non_play_install'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  for (final size in _sizes) {
    for (final e in screens.entries) {
      if (_skip.contains(e.key)) continue;
      testWidgets('${e.key} · ${size.width.toInt()} wide', (tester) async {
        await prepareApp(tester);
        await pumpScreen(tester, e.value(), reduce: false);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pump(const Duration(milliseconds: 30));
        await letDataArrive(tester);
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: 'no overflow or error');
        // a tile is a tile: never stretched across the window
        for (final tile in tester.widgetList(find.byType(GuideGradientTile))) {
          final r = tester.getRect(find.byWidget(tile));
          expect(r.width, lessThanOrEqualTo(kTileMaxSide + 1), reason: 'a square tile is at most $kTileMaxSide wide (was ${r.width})');
          expect(r.height, lessThanOrEqualTo(kTileMaxSide + 60), reason: 'and no taller than a tile (was ${r.height})');
        }
        // cards stay at the content width (they never exceed the reading column)
        for (final card in tester.widgetList(find.byType(GuideNavCard))) {
          expect(tester.getRect(find.byWidget(card)).width, lessThanOrEqualTo(kContentMaxWidth + 1));
        }
        // nothing is laid out wider than the content column, except what is meant to use the window
        final rows = tester.widgetList(find.byType(GuideHeroCard));
        for (final hero in rows) {
          expect(tester.getRect(find.byWidget(hero)).width, lessThanOrEqualTo(kContentMaxWidth + 1));
        }
        if (size.width == 1440) await shot(tester, 'desktop/${e.key}_1440');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }

  group('the tab screens in the shell', () {
    for (final size in _sizes) {
      testWidgets('${size.width.toInt()} wide: Home tiles are tile-sized and sit side by side; Tasks and Analysis cards flow in a grid', (tester) async {
        await prepareApp(tester);
        await pumpScreen(tester, Scaffold(body: ContentWidth(child: screens['tasks_tab']!())));
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pump(const Duration(milliseconds: 300));
        await letDataArrive(tester);
        final tiles = tester.widgetList(find.byType(GuideGradientTile)).map((t) => tester.getRect(find.byWidget(t))).toList();
        expect(tiles.length, 2);
        for (final r in tiles) {
          expect(r.width, kTileMaxSide);
          expect(r.height, greaterThanOrEqualTo(kTileMaxSide));
          expect(r.height, lessThan(kTileMaxSide + 40));
        }
        expect((tiles[0].top - tiles[1].top).abs(), lessThan(1), reason: 'side by side');
        final cards = tester.widgetList(find.byType(GuideNavCard)).map((c) => tester.getRect(find.byWidget(c))).toList();
        expect(cards.length, greaterThanOrEqualTo(2));
        for (final r in cards) {
          expect(r.width, kCardGridWidth);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a phone and a tablet keep the full-width tiles and cards exactly as before', (tester) async {
      for (final size in const [Size(360, 800), Size(800, 1000)]) {
        await prepareApp(tester);
        await pumpScreen(tester, screens['tasks_tab']!());
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pump(const Duration(milliseconds: 300));
        await letDataArrive(tester);
        final side = (size.width - 2 * 20 - 12) / 2; // pagePadding 20, cardGap 12
        final tile = tester.getRect(find.byType(GuideGradientTile).first);
        if (size.width < kTabletMin) {
          expect(tile.width, closeTo(side, 3), reason: 'phone: half the row, exactly as before');
          expect(tester.getRect(find.byType(GuideNavCard).first).width, closeTo(size.width - 40, 3));
        } else {
          expect(tile.width, lessThanOrEqualTo(kTileMaxSide + 1), reason: 'a tablet-sized window also keeps tiles tile-sized');
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
