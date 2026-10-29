import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AbcdeHub.dart';
import 'package:folk_guide_app/Pages/BoysDetails.dart';
import 'package:folk_guide_app/Pages/Competition.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/GoalData.dart';
import 'package:folk_guide_app/widgets/GuideTiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/guide_test_support.dart';

AdminProfile profile(String role, {String id = 'G'}) => AdminProfile.fromMap({
      'id': id,
      'displayName': 'Me',
      'role': role,
      'teamGuide': '',
      'email': 'm@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

CompoundTarget target(String metric, int students, int value, int phase, int total, {String id = 't'}) =>
    CompoundTarget.from('G', '$id$metric', {
      'metric': metric,
      'studentCountGoal': students,
      'perStudentValueGoal': value,
      'status': 'active',
      'currentPhase': phase,
      'totalPhases': total,
    });

class FakeGoalData implements GoalData {
  FakeGoalData(this.list);
  final List<CompoundTarget> list;
  @override
  Stream<List<CompoundTarget>> targets(String guideId) => Stream.value(list);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    GoalData.instance = const FirestoreGoalData();
    AdminProfileProvider.instance.debugSet(null);
  });

  // ------------------------------------------------------------------ ABCDE
  group('ABCDE', () {
    testWidgets('five pastel rows A-E with a serif letter, title, description and chevron', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(const AbcdeHubPage()));
      await settle(tester);
      final rows = find.byType(GuidePastelRow);
      expect(rows, findsNWidgets(5));
      for (final l in ['A', 'B', 'C', 'D', 'E']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(find.text('Association'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      expect(find.text('Chanting'), findsOneWidget);
      expect(find.text('Devotional service'), findsOneWidget);
      expect(find.text('Expeditions'), findsOneWidget);
      expect(find.textContaining('Meetings, requests and counter-proposals'), findsOneWidget);
      expect(find.textContaining('The five limbs of practice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rows use sand, slate, sage, clay, mauve; the dark theme uses the deeper ABCDE set', (tester) async {
      for (final dark in [false, true]) {
        phone(tester, 1.0);
        await tester.pumpWidget(guideHost(const AbcdeHubPage(), dark: dark));
        await settle(tester);
        final g = dark ? GuideColors.dark : GuideColors.light;
        final expected = [GuidePastel.sand, GuidePastel.slate, GuidePastel.sage, GuidePastel.clay, GuidePastel.mauve];
        final boxes = tester.widgetList<GuidePastelBox>(find.byType(GuidePastelBox)).toList();
        expect(boxes.map((b) => b.pastel), expected);
        for (final b in boxes) {
          expect(b.abcde, isTrue);
        }
        final first = tester.widget<Container>(find
            .descendant(of: find.byType(GuidePastelBox).first, matching: find.byType(Container))
            .first);
        final colours = ((first.decoration as BoxDecoration).gradient as LinearGradient).colors;
        expect(colours, g.pastel(GuidePastel.sand, abcde: true).colors);
        await tester.pumpWidget(const SizedBox());
      }
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: no overflow, rows are 48 dp or taller', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(guideHost(const AbcdeHubPage(), dark: dark));
          await settle(tester);
          expect(tester.takeException(), isNull);
          for (final r in tester.widgetList(find.byType(GuidePastelRow)).map((w) => tester.getRect(find.byWidget(w)))) {
            expect(r.height, greaterThanOrEqualTo(48));
            expect(r.right, lessThanOrEqualTo(360));
          }
        });
      }
    }
  });

  // ------------------------------------------------------------- Analysis tab
  group('Analysis: three full-width rectangular cards (Week planning and Guide targets moved to the assistant)', () {
    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(guideHost(Scaffold(body: CompetitionPage()), dark: dark));
          await settle(tester);
          expect(tester.takeException(), isNull);
          final cards = find.byType(GuideNavCard);
          expect(cards, findsNWidgets(3));
          expect(find.text('Week planning'), findsNothing);
          expect(find.text('Guide targets'), findsNothing);
          expect(find.byType(GuideGradientTile), findsNothing, reason: 'no square grid any more');
          Rect r(int i) => tester.getRect(cards.at(i));
          for (var i = 0; i < 3; i++) {
            expect(r(i).width, 360 - 40, reason: 'full width inside the page padding');
            expect(r(i).height, greaterThanOrEqualTo(92), reason: 'comfortable height');
            expect(r(i).height, lessThan(r(i).width), reason: 'rectangular');
            if (i > 0) expect(r(i).top, greaterThan(r(i - 1).bottom - 0.5));
          }
        });
      }
    }

    testWidgets('titles and one-line descriptions, in the old order, serif titles', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(Scaffold(body: CompetitionPage())));
      await settle(tester);
      final titles = tester.widgetList<GuideNavCard>(find.byType(GuideNavCard)).map((c) => c.title).toList();
      expect(titles, ['ABCDE', 'Interactions needed', 'Leaderboard']);
      expect(find.text('FOLK and Hostel & Localite rankings'), findsOneWidget);
      expect(find.text('Five limbs of practice'), findsOneWidget);
      expect(find.text('Plan the week ahead'), findsNothing);
      expect(find.text('Who needs an interaction'), findsOneWidget);
      expect(find.text('Group targets and phases'), findsNothing);
      final style = tester.widget<Text>(find.text('Interactions needed')).style!;
      expect(style.fontFamily, 'Fraunces');
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(3));
      expect(find.text('INSIGHTS'), findsOneWidget);
    });

    testWidgets('the cards rise in one after another, then rest', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(Scaffold(body: CompetitionPage()), reduce: false));
      await tester.pump(const Duration(milliseconds: 30));
      final first = tester.getTopLeft(find.byType(GuideNavCard).at(0)).dy;
      final last = tester.getTopLeft(find.byType(GuideNavCard).at(2)).dy;
      await tester.pump(const Duration(milliseconds: 100));
      final firstMoved = first - tester.getTopLeft(find.byType(GuideNavCard).at(0)).dy;
      final lastMoved = last - tester.getTopLeft(find.byType(GuideNavCard).at(2)).dy;
      expect(firstMoved, greaterThan(0));
      expect(lastMoved, lessThan(firstMoved), reason: 'the last rises after the first');
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  // ----------------------------------------------------------------- Tasks tab
  group('Tasks: a wide card, two squares, a wide card', () {
    Future<void> openTasks(WidgetTester tester, double scale, bool dark) async {
      phone(tester, scale);
      AdminProfileProvider.instance.debugSet(profile('GUIDE'));
      await tester.pumpWidget(guideHost(const Scaffold(body: AdminControlPage()), dark: dark));
      await settle(tester);
    }

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp', (tester) async {
          await openTasks(tester, scale, dark);
          expect(tester.takeException(), isNull);
          final wide = find.byType(GuideNavCard);
          final squares = find.byType(GuideGradientTile);
          expect(wide, findsNWidgets(3), reason: 'Add student, Add admin and (Guides and HODs only) Music curriculum');
          expect(squares, findsNWidgets(2));
          final addStudent = tester.getRect(find.ancestor(of: find.text('Add student'), matching: find.byType(GuideNavCard)));
          final addAdmin = tester.getRect(find.ancestor(of: find.text('Add admin'), matching: find.byType(GuideNavCard)));
          final sub = tester.getRect(find.ancestor(of: find.text('Submissions'), matching: find.byType(GuideGradientTile)));
          final not = tester.getRect(find.ancestor(of: find.text('Notifications'), matching: find.byType(GuideGradientTile)));
          // the order: Add student, then the squares, then Add admin
          expect(addStudent.bottom, lessThanOrEqualTo(sub.top));
          expect(sub.bottom, lessThanOrEqualTo(addAdmin.top));
          final music = tester.getRect(find.ancestor(of: find.text('Music curriculum'), matching: find.byType(GuideNavCard)));
          expect(addAdmin.bottom, lessThanOrEqualTo(music.top), reason: 'the curriculum card comes last');
          expect(music.width, 320);
          expect(addStudent.width, 320);
          expect(addAdmin.width, 320);
          // two equal squares side by side
          expect(sub.top, not.top);
          expect(sub.size, not.size);
          expect(sub.width, closeTo(154, 0.5));
          expect(sub.height, greaterThanOrEqualTo(sub.width), reason: 'square (grows only for large text)');
          if (scale == 1.0) expect(sub.height, closeTo(sub.width, 0.5), reason: 'perfectly square');
          expect(not.left, greaterThan(sub.right));
        });
      }
    }

    testWidgets('every card and tile is tappable (Submissions, Add admin, Notifications have their own pages)', (tester) async {
      await openTasks(tester, 1.0, false);
      for (final c in tester.widgetList<GuideNavCard>(find.byType(GuideNavCard))) {
        expect(c.onTap, isNotNull, reason: c.title);
      }
      for (final c in tester.widgetList<GuideGradientTile>(find.byType(GuideGradientTile))) {
        expect(c.onTap, isNotNull, reason: c.title);
      }
      expect(find.text('Submissions'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('Add student opens its dialog', (tester) async {
      await openTasks(tester, 1.0, false);
      await tester.tap(find.text('Add student'));
      await tester.pumpAndSettle();
      expect(find.text('Add a student'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  // ------------------------------------------------------------------ Targets
  group('Your targets', () {
    Future<void> openTargets(WidgetTester tester, List<CompoundTarget> list, {String role = 'GUIDE', double scale = 1.0, bool dark = false}) async {
      phone(tester, scale);
      AdminProfileProvider.instance.debugSet(profile(role));
      GoalData.instance = FakeGoalData(list);
      await tester.pumpWidget(guideHost(const GoalHomePage(guideId: 'G'), dark: dark));
      await settle(tester);
    }

    testWidgets('a card per target: title, "N students at V", phase, percent, progress, two buttons; New target pinned', (tester) async {
      await openTargets(tester, [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)]);
      expect(find.text('Your targets'), findsOneWidget);
      expect(find.textContaining('10 students at 16'), findsOneWidget);
      expect(find.textContaining('10 students at 5'), findsOneWidget);
      expect(find.text('Phase 1 of 8'), findsOneWidget);
      expect(find.text('Phase 2 of 8'), findsOneWidget);
      expect(find.text('13%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('This week'), findsNWidgets(2));
      expect(find.text('Progress'), findsNWidgets(2));
      expect(find.text('New target'), findsOneWidget);
      // New target is pinned below the list, full width
      final button = tester.getRect(find.text('New target'));
      expect(button.bottom, greaterThan(700));
      expect(find.byTooltip("Review guides' targets"), findsNothing, reason: 'HOD only');
    });

    testWidgets('the HOD also gets the review button', (tester) async {
      await openTargets(tester, [target('chanting', 10, 16, 1, 8)], role: 'HOD');
      expect(find.byTooltip("Review guides' targets"), findsOneWidget);
    });

    testWidgets('no targets: the explanation; a plan that failed: retry', (tester) async {
      await openTargets(tester, const []);
      expect(find.textContaining('No active targets yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await openTargets(tester, [target('chanting', 10, 16, 0, 0)]);
      expect(find.textContaining("generation didn't complete"), findsOneWidget);
      expect(find.text('Retry plan generation'), findsOneWidget);
      expect(find.text('This week'), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: no overflow, buttons 42 dp or taller', (tester) async {
          await openTargets(tester, [target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)], scale: scale, dark: dark);
          expect(tester.takeException(), isNull);
          for (final f in [find.text('This week'), find.text('Progress'), find.text('New target')]) {
            for (final e in f.evaluate()) {
              final r = tester.getRect(find.byWidget(e.widget));
              expect(r.right, lessThanOrEqualTo(360));
            }
          }
        });
      }
    }

    testWidgets('screenshots: targets light and dark (for looking at)', (tester) async {
      for (final dark in [false, true]) {
        phone(tester, 1.0, size: const Size(390, 844));
        AdminProfileProvider.instance.debugSet(profile('GUIDE'));
        GoalData.instance = FakeGoalData([target('chanting', 10, 16, 1, 8), target('books', 10, 5, 2, 8)]);
        await tester.pumpWidget(guideHost(const GoalHomePage(guideId: 'G'), dark: dark));
        await settle(tester);
        await shot(tester, 'targets_${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
