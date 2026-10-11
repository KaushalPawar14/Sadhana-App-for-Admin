import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/GuideCalendarPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/CalendarData.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/GuideCalendar.dart';
import 'package:folk_guide_app/widgets/GuideGhost.dart';
import 'package:folk_guide_app/widgets/GuideSurface.dart';
import 'package:table_calendar/table_calendar.dart';

import 'support/guide_test_support.dart';

class ManualCalendarData implements CalendarData {
  Completer<List<CalendarEvent>> eventsC = Completer();
  int loads = 0;
  @override
  Future<List<CalendarEvent>> events(String guideId) {
    loads++;
    return eventsC.future;
  }

  @override
  Future<List<CalendarTextBlock>> textBlocks(String guideId) async => const [];
}

CalendarEvent ev(String id, DateTime start, String title, {DateTime? end, String type = 'other'}) => CalendarEvent(
      id: id,
      eventDate: start,
      endDate: end,
      type: type,
      title: title,
      note: '',
      sourceTextBlockId: 'b1',
      scope: 'mandatory',
      ownerGuideId: null,
      notifyOffsets: const [],
    );

AdminProfile hod() => AdminProfile.fromMap({
      'id': 'H',
      'displayName': 'Me',
      'role': 'HOD',
      'teamGuide': '',
      'email': 'm@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

final today = DateTime.now();
final _off = today.day > 14 ? 0 : 14;
DateTime d(int day) => DateTime(today.year, today.month, day + _off);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() => SeenMarkers.debugDisable = false);
  tearDown(() => AdminProfileProvider.instance.debugSet(null));

  Future<ManualCalendarData> open(WidgetTester tester, {double scale = 1.0}) async {
    phone(tester, scale);
    AdminProfileProvider.instance.debugSet(hod());
    final data = ManualCalendarData();
    CalendarData.instance = data;
    await tester.pumpWidget(guideHost(const GuideCalendarPage(selectedGuide: 'G'), reduce: false));
    await tester.pump(const Duration(milliseconds: 30));
    return data;
  }

  testWidgets('loading: the legend stays real; the month and the list are ghosts; no spinner', (tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Mandatory'), findsOneWidget);
    expect(find.byType(GuideGhostOf), findsNWidgets(1 + 3));
    expect(GhostClock.instance.running, isTrue);
    expect(find.byType(GuideFab), findsOneWidget, reason: 'the add button stays real');
  });

  for (final scale in kScales) {
    testWidgets('ghost -> month: the card does not move or change size (text scale $scale)', (tester) async {
      final data = await open(tester, scale: scale);
      await tester.pump(const Duration(milliseconds: 300));
      final ghost = tester.getRect(find.byType(GuideGhostOf).first);
      data.eventsC.complete([ev('e', d(7), 'Exam', end: d(9), type: 'exam')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // The month card (a GuideCard holding the calendar) is where the ghost was.
      final cards = find.ancestor(of: find.byType(TableCalendar<CalendarEvent>), matching: find.byType(GuideCard));
      final loaded = tester.getRect(cards.last);
      expect(loaded.top, ghost.top);
      expect(loaded.height, ghost.height);
      expect(loaded.width, ghost.width);
      await tester.pumpAndSettle();
      expect(tester.getRect(cards.last), ghost);
      expect(tester.binding.transientCallbackCount, 0);
      expect(GhostClock.instance.running, isFalse);
    });
  }

  testWidgets('a failed load: frozen ghost, a short message and Retry that loads again', (tester) async {
    final data = await open(tester);
    data.eventsC.completeError('boom');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Could not load the calendar'), findsWidgets);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(GhostClock.instance.running, isFalse, reason: 'frozen');
    data.eventsC = Completer();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(data.loads, 2);
    data.eventsC.complete([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(TableCalendar<CalendarEvent>), findsOneWidget);
    await tester.pump(const Duration(seconds: 8)); // the error snackbar goes away
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a band grows in from its first day; selecting a date scales the circle in; both leave no ticker', (tester) async {
    final data = await open(tester);
    data.eventsC.complete([ev('prog', d(10), 'Retreat', end: d(13), type: 'program')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60)); // the cards are built under the cross-fade
    expect(find.byType(GuideBandGrow), findsWidgets);
    // 40 ms into the grow: not yet full width.
    final growing = tester.widgetList<FractionallySizedBox>(find.descendant(
        of: find.byType(GuideBandGrow), matching: find.byType(FractionallySizedBox)));
    expect(growing, isNotEmpty);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.descendant(of: find.byType(GuideBandGrow), matching: find.byType(FractionallySizedBox)), findsNothing);

    // select another day: the circle pops
    await tester.tap(find.byWidgetPredicate((w) => w is GuideDayCell && w.day.day == d(20).day && !w.outside).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.descendant(of: find.byType(GuideSelectPop), matching: find.byType(ScaleTransition)), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(GuideSelectPop), matching: find.byType(ScaleTransition)), findsNothing);
  });

  testWidgets('the month slides when changed; with reduced motion it changes at once', (tester) async {
    final data = await open(tester);
    data.eventsC.complete([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'sliding');
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('the selected day\'s events rise in, staggered; the day heading changes', (tester) async {
    final data = await open(tester);
    final day = DateTime(today.year, today.month, today.day);
    data.eventsC.complete([ev('a', day, 'First thing'), ev('b', day, 'Second thing')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('First thing'), findsOneWidget);
    expect(find.text('Second thing'), findsOneWidget);
    final y1 = tester.getTopLeft(find.text('First thing')).dy;
    final y2 = tester.getTopLeft(find.text('Second thing')).dy;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('First thing')).dy, lessThanOrEqualTo(y1));
    expect(tester.getTopLeft(find.text('Second thing')).dy, lessThanOrEqualTo(y2));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
