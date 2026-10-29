import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/GuideCalendarPage.dart';
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/CalendarData.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/GuideCalendar.dart';
import 'package:intl/intl.dart';

import 'support/guide_test_support.dart';

class FakeCalendarData implements CalendarData {
  FakeCalendarData(this.eventList, [this.blocks = const []]);
  final List<CalendarEvent> eventList;
  final List<CalendarTextBlock> blocks;
  @override
  Future<List<CalendarEvent>> events(String guideId) async => eventList;
  @override
  Future<List<CalendarTextBlock>> textBlocks(String guideId) async => blocks;
  @override
  Stream<List<CalendarEvent>> automaticEvents(String guideId) => Stream.value(const <CalendarEvent>[]);
}

CalendarEvent ev(String id, DateTime start, String title,
        {DateTime? end, String type = 'other', String scope = 'personal', String note = ''}) =>
    CalendarEvent(
      id: id,
      eventDate: start,
      endDate: end,
      type: type,
      title: title,
      note: note,
      sourceTextBlockId: 'b1',
      scope: scope,
      ownerGuideId: scope == 'personal' ? 'G' : null,
      notifyOffsets: const ['1w'],
    );

AdminProfile profile(String role) => AdminProfile.fromMap({
      'id': role == 'HOD' ? 'H' : 'G',
      'displayName': 'Me',
      'role': role,
      'teamGuide': '',
      'email': 'm@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

/// Dates in the visible month, in the half of it that does not hold today (so
/// "Today" never replaces a date heading): days 1-13 are shifted by 14 when today
/// falls in the first half of the month.
final today = DateTime.now();
final _off = today.day > 14 ? 0 : 14;
DateTime d(int day) => DateTime(today.year, today.month, day + _off);
String dn(int day) => '${d(day).day}';

List<CalendarEvent> sample() => [
      ev('exam', d(7), 'Midterm exams', end: d(9), type: 'exam', scope: 'mandatory'),
      ev('prog', d(10), 'Retreat programme', end: d(13), type: 'program', scope: 'mandatory'),
      ev('rev', d(11), 'Guide review', end: d(12)),
      ev('team', d(11), 'Team meeting', scope: 'mandatory'),
      ev('solo', d(2), 'Own errand'),
      // five on one day: only three dots and a "+"
      for (var i = 0; i < 5; i++) ev('m$i', d(5), 'Busy $i'),
    ];

Future<void> openCalendar(
  WidgetTester tester, {
  List<CalendarEvent>? events,
  String role = 'GUIDE',
  double scale = 1.0,
  bool dark = false,
}) async {
  phone(tester, scale);
  AdminProfileProvider.instance.debugSet(profile(role));
  CalendarData.instance = FakeCalendarData(events ?? sample());
  await tester.pumpWidget(guideHost(const GuideCalendarPage(selectedGuide: 'G'), dark: dark));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Finder cellOf(DateTime day) => find.byWidgetPredicate(
    (w) => w is GuideDayCell && isSameCalendarDay(w.day, day) && !w.outside);

Finder dotsIn(Finder cell) => find.descendant(
    of: cell,
    matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints == const BoxConstraints.tightFor(width: 5, height: 5)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    CalendarData.instance = const FirestoreCalendarData();
    AdminProfileProvider.instance.debugSet(null);
  });

  testWidgets('the month: title, weekdays, legend, floating add button, history button', (tester) async {
    await openCalendar(tester);
    expect(find.text(DateFormat('MMMM yyyy').format(today)), findsOneWidget);
    for (final w in ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']) {
      expect(find.text(w), findsOneWidget, reason: w);
    }
    for (final l in ['Mandatory', 'Personal', 'Exam', 'Festival', 'Program']) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    expect(find.text('Add text'), findsOneWidget);
    expect(find.byTooltip('Text history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every event of a day gets its own dot in its own colour', (tester) async {
    await openCalendar(tester);
    // 11th: programme + review + team meeting = 3 dots, in 3 colours
    final cell = cellOf(d(11));
    final dots = dotsIn(cell);
    expect(dots, findsNWidgets(3));
    final g = GuideColors.light;
    final colours = [
      for (final e in tester.widgetList<Container>(dots)) (e.decoration as BoxDecoration).color,
    ];
    expect(colours, containsAll([g.eventProgram, g.eventPersonal, g.eventMandatory]));
    // a single-event day has one dot; a day with nothing has none
    expect(dotsIn(cellOf(d(2))), findsOneWidget);
    expect(dotsIn(cellOf(d(1))), findsNothing);
  });

  testWidgets('at most three dots, then a "+" (a day with five events)', (tester) async {
    await openCalendar(tester);
    final cell = cellOf(d(5));
    expect(dotsIn(cell), findsNWidgets(3));
    expect(find.descendant(of: cell, matching: find.text('+')), findsOneWidget);
    expect(find.descendant(of: cellOf(d(11)), matching: find.text('+')), findsNothing);
  });

  testWidgets('a multi-day exam / programme is a soft band: rounded at the ends, flat in the middle', (tester) async {
    await openCalendar(tester);
    final g = GuideColors.light;
    BoxDecoration? bandOf(DateTime day, Color tint) {
      for (final c in tester.widgetList<Container>(find.descendant(of: cellOf(day), matching: find.byType(Container)))) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.color == tint && dec.shape == BoxShape.rectangle) return dec;
      }
      return null;
    }

    final start = bandOf(d(7), g.bandExam)!;
    final middle = bandOf(d(8), g.bandExam)!;
    final end = bandOf(d(9), g.bandExam)!;
    BorderRadius r(BoxDecoration b) => b.borderRadius! as BorderRadius;
    expect(r(start).topLeft.x, greaterThan(0), reason: 'rounded at the start');
    expect(r(start).topRight.x, 0, reason: 'flat towards the next day');
    expect(r(middle).topLeft.x, 0);
    expect(r(middle).topRight.x, 0);
    expect(r(end).topRight.x, greaterThan(0), reason: 'rounded at the end');
    // a one-day event has no band
    expect(bandOf(d(2), g.bandExam), isNull);
    // the programme band is green
    expect(bandOf(d(10), g.bandProgram), isNotNull);
    // a plain "other" range (the guide review) is dots only: no band
    expect(find.descendant(of: cellOf(d(12)), matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == g.eventPersonal && (w.decoration as BoxDecoration).shape == BoxShape.rectangle)), findsNothing);
  });

  testWidgets('the selected date is a brass-gradient circle; its events are listed with type and range', (tester) async {
    await openCalendar(tester);
    await tester.tap(find.descendant(of: cellOf(d(11)), matching: find.text(dn(11))));
    await tester.pump();
    await tester.pump();
    final circle = tester.widget<Container>(find
        .descendant(of: cellOf(d(11)), matching: find.byType(Container))
        .evaluate()
        .map((e) => find.byWidget(e.widget))
        .firstWhere((f) {
      final w = tester.widget<Container>(f);
      return w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient != null;
    }));
    expect((circle.decoration as BoxDecoration).shape, BoxShape.circle);
    final weekday = DateFormat('EEE, dd MMM').format(d(11));
    expect(find.text(weekday), findsOneWidget);
    expect(find.text('3 events'), findsOneWidget);
    expect(find.text('Retreat programme'), findsOneWidget);
    String dd(DateTime x) => DateFormat('dd').format(x);
    expect(find.textContaining('Program · ${dd(d(10))} – ${dd(d(13))}'), findsOneWidget);
    expect(find.text('Guide review'), findsOneWidget);
    expect(find.textContaining('Personal · ${dd(d(11))} – ${dd(d(12))}'), findsOneWidget);
    expect(find.text('Team meeting'), findsOneWidget);
    expect(find.textContaining('Mandatory · '), findsOneWidget);
  });

  testWidgets('a day with nothing shows a friendly line', (tester) async {
    await openCalendar(tester);
    await tester.tap(find.descendant(of: cellOf(d(1)), matching: find.text(dn(1))));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nothing due'), findsOneWidget);
  });

  testWidgets('a Guide edits a personal event; a mandatory one is read-only (HOD only)', (tester) async {
    await openCalendar(tester);
    await tester.tap(find.descendant(of: cellOf(d(11)), matching: find.text(dn(11))));
    await tester.pump();
    await tester.pump();
    // personal -> tappable (opens the edit dialog)
    await tester.ensureVisible(find.text('Guide review'));
    await tester.pump();
    await tester.tap(find.text('Guide review'));
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // mandatory -> nothing opens for a Guide
    await tester.tap(find.text('Team meeting'));
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsNothing);
  });

  testWidgets('the HOD may edit a mandatory event', (tester) async {
    await openCalendar(tester, role: 'HOD');
    await tester.tap(find.descendant(of: cellOf(d(11)), matching: find.text(dn(11))));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Team meeting'));
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);
  });

  testWidgets('a Guide without a shared calendar is told so (and can still add his own)', (tester) async {
    await openCalendar(tester);
    expect(find.textContaining("Your HOD hasn't set up the shared calendar yet"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await openCalendar(tester, role: 'HOD');
    expect(find.textContaining("Your HOD hasn't set up"), findsNothing);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: no overflow, rows stay compact', (tester) async {
        await openCalendar(tester, scale: scale, dark: dark);
        expect(tester.takeException(), isNull);
        final cell = tester.getRect(cellOf(d(11)));
        expect(cell.width, lessThanOrEqualTo(360 / 7 + .5));
        // a week row: compact at 1.0 (54-56 dp), growing only with the text size
        expect(cell.height, lessThanOrEqualTo(56.0 * scale + 12));
        expect(cell.height, greaterThanOrEqualTo(54));
        // the date circle holds its number
        final number = tester.getRect(find.descendant(of: cellOf(d(11)), matching: find.text(dn(11))));
        expect(number.width, lessThanOrEqualTo(cell.width));
        // the legend wraps rather than overflows
        final legend = tester.getRect(find.byType(GuideCalendarLegend));
        expect(legend.right, lessThanOrEqualTo(360));
        // the add button stays on screen and is a 48 dp target
        final fab = tester.getRect(find.text('Add text'));
        expect(fab.bottom, lessThanOrEqualTo(800));
        await tester.scrollUntilVisible(find.text('Today'), 200, scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('50 events in a month do not break the layout', (tester) async {
    final many = [
      for (var i = 1; i <= 13; i++) ev('a$i', d(i), 'Event $i'),
      for (var i = 1; i <= 13; i++) ev('b$i', d(i), 'Second $i', scope: 'mandatory'),
      for (var i = 1; i <= 24; i++) ev('c$i', d(1 + i % 13), 'Extra $i'),
    ];
    await openCalendar(tester, events: many);
    expect(tester.takeException(), isNull);
    await tester.tap(find.descendant(of: cellOf(d(5)), matching: find.text(dn(5))));
    await tester.pump();
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+ events$').hasMatch(w.data ?? '')), findsOneWidget);
  });

  testWidgets('screenshots: calendar light and dark (for looking at)', (tester) async {
    for (final dark in [false, true]) {
      phone(tester, 1.0, size: const Size(390, 844));
      AdminProfileProvider.instance.debugSet(profile('HOD'));
      CalendarData.instance = FakeCalendarData(sample());
      await tester.pumpWidget(guideHost(const GuideCalendarPage(selectedGuide: 'G'), dark: dark));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.tap(find.descendant(of: cellOf(d(11)), matching: find.text(dn(11))));
      await tester.pump();
      await tester.pump();
      await shot(tester, 'calendar_${dark ? 'dark' : 'light'}');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
