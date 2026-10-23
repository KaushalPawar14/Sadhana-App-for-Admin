import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/widgets/GuideBoardMotion.dart';

/// The FOLK Boys board's columns rendered as a red error box:
///
///   'hasSize': RenderBox was not laid out: RenderFractionalTranslation#… NEEDS-LAYOUT
///   BOTTOM OVERFLOWED BY 99343 PIXELS
///
/// `RenderFractionalTranslation` is what Flutter's own page transitions put around a
/// page (`SlideTransition`) — the board is wrapped in one the moment a profile is pushed
/// over it, and again unwrapped on the way back (the phone's back gesture too).
/// `GuideHeaderParallax` asked "where am I on screen?" (`localToGlobal`) while it BUILT,
/// and that walks up through every ancestor, including a transition wrapper that has
/// just been created and not laid out yet — whose transform needs its size. So the
/// header threw, in every column at once.
///
/// The header now measures against its own scrollable only, which sits inside the board
/// and is always laid out, and can never be taken down by a wrapper above it.
void main() {
  Widget board(ScrollController scroll, {required Widget Function(Widget) wrap}) {
    final columns = SizedBox(
      key: const ValueKey('board'),
      height: 300,
      child: SingleChildScrollView(
        controller: scroll,
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < 6; i++)
            SizedBox(
              width: 300,
              child: Column(children: [
                GuideHeaderParallax(scroll: scroll, columnWidth: 300, child: Text('Header $i')),
                const SizedBox(height: 40),
              ]),
            ),
        ]),
      ),
    );
    return MaterialApp(home: Scaffold(body: wrap(columns)));
  }

  testWidgets('a page transition appearing around the board in the same frame as a scroll does not break the headers', (tester) async {
    final scroll = ScrollController();
    final anim = AnimationController(vsync: tester, duration: const Duration(milliseconds: 300));
    addTearDown(() {
      anim.dispose();
      scroll.dispose();
    });

    final boardKey = GlobalKey();
    var wrapped = false;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, set) {
          rebuild = set;
          final inner = SizedBox(
            key: boardKey,
            height: 300,
            child: SingleChildScrollView(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < 6; i++)
                  SizedBox(
                    width: 300,
                    child: GuideHeaderParallax(scroll: scroll, columnWidth: 300, child: Text('Header $i')),
                  ),
              ]),
            ),
          );
          return wrapped
              ? SlideTransition(
                  position: Tween<Offset>(begin: Offset.zero, end: const Offset(-.25, 0)).animate(anim),
                  child: inner,
                )
              : inner;
        }),
      ),
    ));
    expect(find.text('Header 0'), findsOneWidget);

    // The route is pushed (a transition wraps the board) and the saved scroll position
    // is restored in the same frame — what the phone does when a profile opens.
    rebuild(() => wrapped = true);
    scroll.jumpTo(150);
    await tester.pump();
    anim.forward();
    await tester.pump(const Duration(milliseconds: 100));
    scroll.jumpTo(300);
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
    expect(find.text('Header 3'), findsWidgets);

    // …and unwrapped again on the way back.
    rebuild(() => wrapped = false);
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('headers still drift with the scroll, and sit still at rest', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(board(scroll, wrap: (c) => c));
    final rest = tester.getTopLeft(find.text('Header 1')).dx;

    scroll.jumpTo(150);
    await tester.pump();
    final scrolled = tester.getTopLeft(find.text('Header 1')).dx;
    // The column moved 150 left; the header moved a little MORE than that (parallax)
    // but by no more than the 8 dp it is allowed.
    final extra = (rest - 150) - scrolled;
    expect(extra.abs(), lessThanOrEqualTo(GuideHeaderParallax.maxShift));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the real route transitions: push a page over the board, pop it, with every scroll position in between', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      theme: ThemeData(platform: TargetPlatform.android),
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: SingleChildScrollView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < 6; i++)
                SizedBox(
                  width: 300,
                  child: GuideHeaderParallax(scroll: scroll, columnWidth: 300, child: Text('Header $i')),
                ),
            ]),
          ),
        ),
      ),
    ));

    for (final offset in [0.0, 120.0, 600.0, 1500.0]) {
      scroll.jumpTo(offset);
      await tester.pump();
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Profile'))));
      // The scroll position is restored/changed during the transition's first frames.
      await tester.pump();
      scroll.jumpTo(offset == 0 ? 90 : 0);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);

      nav.currentState!.pop();
      await tester.pump();
      scroll.jumpTo(offset);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at scroll offset $offset');
      expect(find.byType(ErrorWidget), findsNothing);
    }
  });

  testWidgets("the phone's predictive back gesture: drag it, let go, drag it again and cancel — with the board scrolling underneath", (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        }),
      ),
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: SingleChildScrollView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < 6; i++)
                SizedBox(
                  width: 300,
                  child: GuideHeaderParallax(scroll: scroll, columnWidth: 300, child: Text('Header $i')),
                ),
            ]),
          ),
        ),
      ),
    ));

    // What Android's back gesture really sends: a platform message on 'flutter/backgesture'.
    Future<void> gesture(String method, [Map<String, Object?>? args]) async {
      final done = Completer<void>();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/backgesture',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) => done.complete(),
      );
      await done.future;
    }

    Map<String, Object?> at(double progress) => {
          'touchOffset': <Object?>[10.0, 400.0],
          'progress': progress,
          'swipeEdge': 0,
        };

    for (final commit in [true, false]) {
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Profile'))));
      await tester.pumpAndSettle();

      await gesture('startBackGesture', at(0));
      await tester.pump();
      for (final p in [.1, .3, .6]) {
        await gesture('updateBackGestureProgress', at(p));
        scroll.jumpTo(p * 500);
        await tester.pump(const Duration(milliseconds: 16));
      }
      if (commit) {
        await gesture('commitBackGesture');
      } else {
        await gesture('cancelBackGesture');
      }
      scroll.jumpTo(40);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: commit ? 'committed' : 'cancelled');
      expect(find.byType(ErrorWidget), findsNothing);
      if (!commit) nav.currentState!.pop();
      await tester.pumpAndSettle();
    }
    expect(find.text('Profile'), findsNothing);
  });
}
