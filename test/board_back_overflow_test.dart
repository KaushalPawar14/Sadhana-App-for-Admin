import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_test.dart' show openBoard;
import 'support/guide_test_support.dart';

/// Bug: coming back to the FOLK Boys board with the PHONE's back button paints
/// the board cards with overflow stripes; the app bar arrow is fine.
///
/// The difference is Android's predictive back, which renders the outgoing page
/// SCALED DOWN during the gesture — the board is briefly laid out in a smaller
/// box than it was built for. Anything that only just fits at full size
/// overflows there.
///
/// These tests lay the board out at the sizes that transition passes through,
/// and assert it never overflows at any of them.

/// Every exception Flutter recorded, as text.
String? overflowIn(WidgetTester tester) {
  final e = tester.takeException();
  if (e == null) return null;
  return e.toString();
}

/// Shrinks the viewport the way a predictive-back transition does, and lays out
/// again at that size.
Future<void> shrinkTo(WidgetTester tester, double factor,
    {Size from = const Size(360, 800)}) async {
  tester.view.physicalSize = Size(from.width * factor, from.height * factor);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  // The scales a predictive-back gesture passes through: it eases the outgoing
  // page down to roughly 90%, and a slow drag renders every step on the way.
  const backScales = [1.0, 0.97, 0.94, 0.90, 0.85];

  for (final scale in backScales) {
    testWidgets('the board does not overflow at ${(scale * 100).round()}% '
        '(predictive back)', (tester) async {
      await openBoard(tester, books: {
        'sg1': {
          'level-1_book_1': {'endDate': '2026-01-01'},
          'level-1_book_2': {'startDate': '2026-03-01', 'isCurrentBook': true},
        },
      });
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Level 1'));
      await tester.pumpAndSettle();
      expect(overflowIn(tester), isNull, reason: 'before shrinking');

      await shrinkTo(tester, scale);
      final err = overflowIn(tester);
      expect(err, isNull,
          reason: 'board overflowed at ${(scale * 100).round()}%: $err');
    });
  }

  testWidgets('a collapsed board survives the same shrink', (tester) async {
    await openBoard(tester);
    for (final scale in backScales) {
      await shrinkTo(tester, scale);
      expect(overflowIn(tester), isNull,
          reason: 'collapsed board at ${(scale * 100).round()}%');
    }
  });

  // Text scale makes everything taller and wider; the transition still must not
  // overflow, in either theme.
  for (final dark in [false, true]) {
    for (final textScale in kScales) {
      testWidgets('expanded board, text $textScale, '
          '${dark ? 'dark' : 'light'}, shrunk to 90%', (tester) async {
        await openBoard(tester, scale: textScale, dark: dark, books: {
          'sg1': {
            'level-1_book_1': {'endDate': '2026-01-01'},
            'level-1_book_3': {'startDate': '2026-03-01', 'isCurrentBook': true},
          },
        });
        await tester.tap(find.text('Arjun Kumar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Level 1'));
        await tester.pumpAndSettle();
        expect(overflowIn(tester), isNull, reason: 'before shrinking');

        await shrinkTo(tester, 0.90);
        final err = overflowIn(tester);
        expect(err, isNull, reason: 'overflow at 90%: $err');
      });
    }
  }

  // A very narrow phone is the same class of problem, permanently rather than
  // for the length of a gesture.
  testWidgets('a narrow phone (320 dp) does not overflow either',
      (tester) async {
    await openBoard(tester, size: const Size(320, 700), books: {
      'sg1': {
        'level-1_book_1': {'endDate': '2026-01-01'},
      },
    });
    await tester.tap(find.text('Arjun Kumar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Level 1'));
    await tester.pumpAndSettle();
    expect(overflowIn(tester), isNull);
  });

  // The screens reached FROM the board are laid out at the same reduced
  // sizes on the way out, so each is checked the same way.
  for (final screen in ['Calendar', 'Profile', 'Comments']) {
    testWidgets('the board behind the $screen icon survives the shrink',
        (tester) async {
      await openBoard(tester, scale: 1.6, books: {
        'sg1': {
          'level-1_book_1': {'endDate': '2026-01-01'},
        },
      });
      await tester.tap(find.text('Arjun Kumar'));
      await tester.pumpAndSettle();
      // the row of quick icons is the one that overflowed
      expect(find.byTooltip(screen), findsWidgets,
          reason: '$screen icon is on the card');
      for (final scale in [1.0, 0.94, 0.90, 0.85]) {
        await shrinkTo(tester, scale);
        final err = overflowIn(tester);
        expect(err, isNull,
            reason: '$screen row overflowed at ${(scale * 100).round()}%: $err');
      }
    });
  }

  testWidgets('a long group label ellipsises instead of overflowing',
      (tester) async {
    await openBoard(tester, scale: 1.6, size: const Size(320, 700));
    await tester.tap(find.text('Arjun Kumar'));
    await tester.pumpAndSettle();
    await shrinkTo(tester, 0.85, from: const Size(320, 700));
    expect(overflowIn(tester), isNull);
  });
}
