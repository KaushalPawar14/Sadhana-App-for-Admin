import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/BookReadReport.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';

import 'support/guide_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() => AdminProfileProvider.instance.debugSet(null));

  // ------------------------------------------------------ report summary banner
  group('GuideSummaryBanner (Submissions, Priority students, Flagged messages, Overdue)', () {
    const banner = GuideSummaryBanner(
      tone: GuideTone.bad,
      icon: Icons.flag_outlined,
      title: '128 needing attention across every single guide',
      lines: [
        '14 pastoral notes below for the students of the whole department',
        'Your students · A guide with a rather long display name',
      ],
      emphasis: '9 needing urgent attention',
    );

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: nothing overflows or is clipped', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(guideHost(
            const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: banner)),
            dark: dark,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          final r = tester.getRect(find.byType(GuideSummaryBanner));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
          expect(find.textContaining('9 needing urgent attention'), findsOneWidget);
        });
      }
    }

    testWidgets('all three tones render', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(const Scaffold(
        body: Column(children: [
          GuideSummaryBanner(tone: GuideTone.good, icon: Icons.check_circle_outline, title: 'Nobody flagged'),
          GuideSummaryBanner(tone: GuideTone.warn, icon: Icons.flag_outlined, title: '3 need attention'),
          GuideSummaryBanner(tone: GuideTone.bad, icon: Icons.event_busy_outlined, title: '2 overdue'),
        ]),
      )));
      await tester.pump();
      expect(find.byType(GuideSummaryBanner), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------ Books read (HOD only)
  group('Books read', () {
    for (final scale in kScales) {
      testWidgets('a non-HOD sees the HOD-only message, text scale $scale', (tester) async {
        phone(tester, scale);
        AdminProfileProvider.instance.debugSet(null);
        await tester.pumpWidget(guideHost(const BookReadingScreen()));
        await tester.pump();
        expect(find.text('This report is only available to the HOD.'), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing); // nothing to pop in a test host
        expect(tester.takeException(), isNull);
      });
    }
  });

  // --------------------------------------------------------------- design rules
  group('design rules (lib/)', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    String rel(File f) => f.path.replaceAll('\\', '/');
    bool isTheme(File f) => rel(f).startsWith('lib/theme/');

    /// The lines of [f] that are code, not comments.
    List<MapEntry<int, String>> code(File f) {
      final out = <MapEntry<int, String>>[];
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final t = lines[i].trimLeft();
        if (t.startsWith('//')) continue;
        out.add(MapEntry(i, lines[i]));
      }
      return out;
    }

    test('no LayoutBuilder anywhere', () {
      final hits = <String>[];
      for (final f in files) {
        for (final l in code(f)) {
          if (RegExp(r'\bLayoutBuilder\b').hasMatch(l.value)) hits.add('${rel(f)}:${l.key + 1}');
        }
      }
      expect(hits, isEmpty);
    });

    test('no BackdropFilter anywhere', () {
      final hits = <String>[];
      for (final f in files) {
        for (final l in code(f)) {
          if (RegExp(r'\bBackdropFilter\b').hasMatch(l.value)) hits.add('${rel(f)}:${l.key + 1}');
        }
      }
      expect(hits, isEmpty);
    });

    test('colour literals live in the theme (documented exceptions only)', () {
      // Each exception is a colour that is not ours to theme.
      const allowed = <String, String>{
        'lib/widgets/GuideGate.dart': "Google's brand blue on the sign-in button",
        'lib/utils/Snackbar.dart': 'the snackbar shadow; its tones map the colour a caller passes',
        'lib/Pages/WeeklyPlanning.dart': 'a hairline on the navy hero panel',
        'lib/widgets/GuideBoard.dart': 'the lifted shadow of a card being dragged (same in both themes, per the design)',
        'lib/widgets/GuideTiles.dart': 'the progress track on a pastel tile (same in both themes, per the design)',
      };
      final hits = <String>[];
      for (final f in files) {
        if (isTheme(f) || allowed.containsKey(rel(f))) continue;
        for (final l in code(f)) {
          if (RegExp(r'\bColor\(0x[0-9A-Fa-f]+\)').hasMatch(l.value)) hits.add('${rel(f)}:${l.key + 1}');
        }
      }
      expect(hits, isEmpty);
    });

    test('Material named colours appear only as snackbar tones, or in documented exceptions', () {
      final named = RegExp(r'\bColors\.(red|green|blue|orange|grey|teal|purple|amber|indigo|pink|yellow|brown|cyan|lime)\b');
      // Medal colours and the follow-up flag are meanings, not theme choices.
      const allowedLines = <String>[
        'Colors.brown.shade400',
        'Colors.yellow',
        'colour: Colors.brown',
      ];
      final hits = <String>[];
      for (final f in files) {
        if (isTheme(f) || rel(f).startsWith('lib/widgets/')) continue;
        final all = f.readAsLinesSync();
        for (final l in code(f)) {
          if (!named.hasMatch(l.value)) continue;
          if (allowedLines.any(l.value.contains)) continue;
          // A snackbar tone: the colour is an argument of a showSnackbar(...) call.
          final from = (l.key - 8).clamp(0, all.length - 1);
          final window = all.sublist(from, l.key + 1).join('\n');
          if (window.contains('showSnackbar(')) continue;
          hits.add('${rel(f)}:${l.key + 1}  ${l.value.trim()}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('no raised shadows with a black colour outside the theme', () {
      final hits = <String>[];
      for (final f in files) {
        if (isTheme(f)) continue;
        for (final l in code(f)) {
          if (RegExp(r'Colors\.black\b').hasMatch(l.value)) hits.add('${rel(f)}:${l.key + 1}');
        }
      }
      expect(hits, isEmpty);
    });

    test('fonts are bundled: Fraunces and Inter files and licences', () {
      for (final p in [
        'assets/fonts/Fraunces-Medium.ttf',
        'assets/fonts/Fraunces-SemiBold.ttf',
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Inter-Bold.ttf',
      ]) {
        expect(File(p).existsSync(), isTrue, reason: p);
      }
    });
  });
}
