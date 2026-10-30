import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:folk_guide_app/Pages/GuideCalendarPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/AutoCalendar.dart';
import 'package:folk_guide_app/utils/CalendarData.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/PlanCalendar.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/PlanToday.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/EventAudiencePicker.dart';

import 'support/guide_test_support.dart';

/// THE CALENDAR SHOWS EVERYTHING THE GUIDE HAS TO DO, LIVE: the plan's tasks (Today = exactly Today's rows with the same ticks; This week on its days), every
/// meeting state, every book due date, follow-ups, trips, competitions, targets and the guide's own events; a day's list grouped like Today; a HOD's own
/// items or all guides; manual events for everyone, a category or named students.
///
/// "Today" is Fri 30 Oct 2026 (the plan's date).

Timestamp ts(int y, int m, int d, [int h = 12]) => Timestamp.fromDate(DateTime(y, m, d, h));
String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
Map<String, CalendarEvent> _byId(List<CalendarEvent> l) => {for (final e in l) e.id: e};

AdminProfile _profile(String id, String role) => AdminProfile.fromMap({
      'id': id,
      'displayName': 'Admin $id',
      'role': role,
      'teamGuide': '',
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [
        {'id': 'H', 'displayName': 'Hari', 'role': 'HOD', 'teamGuide': ''},
        {'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': ''},
      ],
    });

PlanPoint _pt(String kind, String title, {bool done = false, PlanGroup group = PlanGroup.followUp}) => PlanPoint(kind: kind, title: title, text: 'x', group: group, done: done);

PlanItem _card(String uid, String name, List<PlanPoint> points, {bool done = false, String calNote = ''}) => PlanItem(
      id: 'interaction:$uid:2026-10-30',
      kind: 'interaction',
      title: 'Interaction with $name',
      studentName: name,
      studentUid: uid,
      percent: 40,
      done: done,
      points: points,
      calNote: calNote,
      cardGroups: [for (final g in PlanGroup.values) if (points.any((p) => p.group == g)) g],
    );

PlanDoc _plan({List<PlanItem>? today, List<PlanItem> week = const [], List<PlanItem> targets = const []}) => PlanDoc(
      todayDate: '2026-10-30',
      todayItems: today ??
          [
            _card('u1', 'Ravi', [_pt('concern', 'Worry', group: PlanGroup.worry), _pt('bookDue', 'Book due', group: PlanGroup.other)], calNote: 'Exams 31 Dec–17 Jan'),
            _card('u2', 'Amit', [_pt('target_task', 'Chanting target', group: PlanGroup.target)]),
            _card('u3', 'Mohit', [_pt('doubt', 'Doubt', done: true)], done: true),
            const PlanItem(id: 'meeting:u9:2026-10-30', kind: 'meeting', title: 'Meet Harsh'),
          ],
      weekOf: '2026-10-26',
      intro: '',
      sections: [
        PlanSection(id: 'interactions', title: 'Interactions', items: week),
        PlanSection(id: 'targettasks', title: 'Target tasks', items: targets),
      ],
      generatedAt: DateTime.utc(2026, 10, 30, 4, 10),
      status: 'upToDate',
      changedAt: DateTime.utc(2026, 10, 30, 4, 10),
    );

PlanItem _week(String uid, String name, String day, {bool done = false}) => PlanItem(id: 'week:$uid', kind: 'weekStudent', title: name, studentName: name, studentUid: uid, scheduledFor: day, done: done);

class _PlanFeed extends PlanData {
  final controller = StreamController<PlanDoc?>.broadcast();
  @override
  Stream<PendingChanges> pending(String adminId) => const Stream.empty();
  @override
  Stream<PlanDoc?> plan(String adminId) => controller.stream;
  @override
  DateTime now() => DateTime.utc(2026, 10, 30, 4, 30);
}

class _Live implements CalendarData {
  _Live(this.manual);
  final List<CalendarEvent> manual;
  final controller = StreamController<List<CalendarEvent>>.broadcast();
  @override
  Future<List<CalendarEvent>> events(String guideId) async => manual;
  @override
  Future<List<CalendarTextBlock>> textBlocks(String guideId) async => const [];
  @override
  Stream<List<CalendarEvent>> automaticEvents(String guideId) => controller.stream;
}

CalendarEvent _auto(String id, String source, DateTime start, String title, {String guideId = '', String section = '', bool done = false, String studentUid = '', String studentName = ''}) =>
    autoCalendarEvent(id: id, source: source, start: start, title: title, guideId: guideId, section: section, done: done, studentUid: studentUid, studentName: studentName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    CalendarData.instance = const FirestoreCalendarData();
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  group('the plan on the calendar', () {
    test('TODAY IN THE CALENDAR = TODAY\'S PLAN: the same rows on today\'s date, with the same ticks and blocks', () {
      final plan = _plan();
      final events = planCalendarEvents(plan);
      final today = events.where((e) => e.id.startsWith('plan_today_')).toList();
      expect(today.length, 4, reason: 'Ravi, Amit, Mohit and the meeting: exactly the 4 tasks of Today');
      expect(today.every((e) => _day(e.eventDate) == '2026-10-30'), isTrue);
      final by = _byId(today);
      expect(by['plan_today_interaction:u1:2026-10-30']!.title, 'Ravi — Worry, Book due');
      expect(by['plan_today_interaction:u1:2026-10-30']!.section, 'followups', reason: 'his most important block: the worry');
      expect(by['plan_today_interaction:u2:2026-10-30']!.section, 'targets');
      expect(by['plan_today_interaction:u3:2026-10-30']!.done, isTrue, reason: 'the same tick as Today');
      expect(by['plan_today_interaction:u1:2026-10-30']!.done, isFalse);
      expect(by['plan_today_meeting:u9:2026-10-30']!.section, 'others');
      expect(by['plan_today_interaction:u1:2026-10-30']!.note, 'Exams 31 Dec–17 Jan', reason: 'the calendar note of the item');
      expect(today.where((e) => e.done).length, TodayView.of(plan).done, reason: 'the counts agree');
    });

    test('THIS WEEK: each planned interaction on its day (done ones ticked); a day already in Today is not drawn twice; a target line is a band over the week', () {
      final plan = _plan(week: [_week('u1', 'Ravi', '2026-10-30'), _week('u4', 'Kiran', '2026-10-31', done: true), _week('u5', 'Dev', '2026-11-02')], targets: [
        const PlanItem(id: 'weektarget:t1', kind: 'weekTask', title: 'Chanting 16 by 30 Nov', steps: [PlanStep(name: 'Testing', from: 12, to: 16), PlanStep(name: 'Amit', from: 8, to: 12)]),
        const PlanItem(id: 'target_task:G:roster', kind: 'weekTask', title: 'Bring students 2 → 5'),
      ]);
      final by = _byId(planCalendarEvents(plan));
      expect(by.containsKey('plan_week_u1_2026-10-30'), isFalse, reason: 'Ravi is one of Today\'s tasks already');
      expect(_day(by['plan_week_u4_2026-10-31']!.eventDate), '2026-10-31');
      expect(by['plan_week_u4_2026-10-31']!.done, isTrue);
      expect(_day(by['plan_week_u5_2026-11-02']!.eventDate), '2026-11-02');
      final band = by['plan_target_weektarget:t1']!;
      expect([_day(band.eventDate), _day(band.effectiveEndDate), band.isMultiDay], ['2026-10-26', '2026-11-01', true], reason: 'Mon to Sun of this week');
      expect(band.note, 'Testing 12 → 16, Amit 8 → 12');
      expect(by.containsKey('plan_target_target_task:G:roster'), isTrue, reason: 'roster tasks live here, in the week');
      expect(by['plan_target_weektarget:t1']!.section, 'targets');
    });

    test('no plan, no events', () => expect(planCalendarEvents(null), isEmpty));

    test('groups: Follow-ups, Target tasks, Other tasks, Meetings, Events', () {
      String g(String source, {String section = ''}) => calendarGroupOf(_auto('x', source, DateTime(2026, 10, 30), 't', section: section));
      expect([g(kSourcePlan, section: 'followups'), g(kSourcePlan, section: 'targets'), g(kSourcePlan, section: 'others'), g(kSourceBook), g(kSourceMeeting), g(kSourceFollowUp), g(kSourceTarget), g(kSourceTrip)],
          ['followups', 'targets', 'others', 'others', 'meetings', 'followups', 'targets', 'events']);
      expect(kCalendarGroups.map((x) => x.$2), ['Follow-ups', 'Target tasks', 'Other tasks', 'Meetings', 'Events']);
    });
  });

  group('the feed, live', () {
    late FakeFirebaseFirestore db;
    late _PlanFeed plan;
    setUp(() {
      db = FakeFirebaseFirestore();
      GuideDb.useForTests(db);
      plan = _PlanFeed();
      PlanData.instance = plan;
    });
    tearDown(() {
      GuideDb.useForTests(null);
      PlanData.instance = const FirestorePlanData();
      AdminProfileProvider.instance.debugSet(null);
    });

    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 120));

    test('EVERY BOOK\'S DUE DATE is on the calendar with the student\'s name; a finished book is not; a new date moves it; a new book appears - all by itself', () async {
      await db.collection('users').doc('s1').set({'name': 'Ayush Shah', 'guideId': 'G', 'teamGuide': 'G', 'gender': 'male', 'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'});
      const stamps = {'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'};
      await db.collection('booksRead').doc('s1_l1_b1').set({'uid': 's1', 'bookTitle': 'Gita', 'commitmentDate': '2026-11-10', ...stamps});
      await db.collection('booksRead').doc('s1_l1_b2').set({'uid': 's1', 'bookTitle': 'Done book', 'commitmentDate': '2026-11-11', 'endDate': '2026-10-01', ...stamps});
      final p = _profile('G', 'GUIDE');
      AdminProfileProvider.instance.debugSet(p);
      var latest = <CalendarEvent>[];
      final sub = AutoCalendarFeed(p, clock: () => DateTime(2026, 10, 30, 12)).events().listen((e) => latest = e);
      await tick();
      final b = _byId(latest)['book_s1_l1_b1']!;
      expect([_day(b.eventDate), b.title, b.note, b.source], ['2026-11-10', 'Book due: Ayush Shah', 'Gita', kSourceBook]);
      expect(_byId(latest).containsKey('book_s1_l1_b2'), isFalse, reason: 'finished');
      await db.collection('booksRead').doc('s1_l1_b1').update({'commitmentDate': '2026-11-20'});
      await tick();
      expect(_day(_byId(latest)['book_s1_l1_b1']!.eventDate), '2026-11-20', reason: 'a new date moves it (a student changing it in his app)');
      await db.collection('booksRead').doc('s1_l1_b1').update({'endDate': '2026-10-30'});
      await tick();
      expect(_byId(latest).containsKey('book_s1_l1_b1'), isFalse, reason: 'finished: gone');
      await sub.cancel();
    });

    test('THE PLAN IS LIVE ON THE CALENDAR: a tick, a new task or a changed week arrives without any Refresh', () async {
      final p = _profile('G', 'GUIDE');
      AdminProfileProvider.instance.debugSet(p);
      var latest = <CalendarEvent>[];
      final sub = AutoCalendarFeed(p, clock: () => DateTime(2026, 10, 30, 12)).events().listen((e) => latest = e);
      plan.controller.add(_plan());
      await tick();
      expect(_byId(latest)['plan_today_interaction:u1:2026-10-30']!.done, isFalse);
      // the report is made: Ravi's task is ticked in the plan -> the calendar follows at once
      plan.controller.add(_plan(today: [_card('u1', 'Ravi', [_pt('concern', 'Worry', done: true)], done: true)]));
      await tick();
      expect(_byId(latest)['plan_today_interaction:u1:2026-10-30']!.done, isTrue);
      expect(latest.where((e) => e.id.startsWith('plan_today_')).length, 1);
      // a new interaction planned for Monday
      plan.controller.add(_plan(today: [], week: [_week('u7', 'Gopi', '2026-11-02')]));
      await tick();
      expect(_day(_byId(latest)['plan_week_u7_2026-11-02']!.eventDate), '2026-11-02');
      await sub.cancel();
    });

    test('A MEETING: confirming moves a request to its day; completing ticks it, with no Refresh', () async {
      const stamps = {'scopeGuide': 'G', 'scopeTeam': 'G', 'scopeGender': 'male'};
      await db.collection('associations').doc('a1').set({'studentUid': 's1', 'studentName': 'Ravi', 'status': 'pending', 'preferredDate': ts(2026, 11, 3), 'confirmedDate': null, ...stamps});
      final p = _profile('G', 'GUIDE');
      AdminProfileProvider.instance.debugSet(p);
      var latest = <CalendarEvent>[];
      final sub = AutoCalendarFeed(p, clock: () => DateTime(2026, 10, 30, 12)).events().listen((e) => latest = e);
      await tick();
      expect(_byId(latest)['meeting_a1']!.title, 'Meeting request: Ravi');
      await db.collection('associations').doc('a1').update({'status': 'confirmed', 'confirmedDate': ts(2026, 11, 5)});
      await tick();
      expect([_byId(latest)['meeting_a1']!.title, _day(_byId(latest)['meeting_a1']!.eventDate)], ['Meeting: Ravi', '2026-11-05']);
      await db.collection('associations').doc('a1').update({'status': 'completed'});
      await tick();
      expect(_byId(latest)['meeting_a1']!.done, isTrue);
      await sub.cancel();
    });
  });

  group('the day list', () {
    Future<_Live> open(WidgetTester tester, {List<CalendarEvent> manual = const [], double scale = 1.0, bool dark = false, String role = 'GUIDE', String id = 'G', Size size = const Size(360, 1700)}) async {
      phone(tester, scale, size: size);
      AdminProfileProvider.instance.debugSet(_profile(id, role));
      final data = _Live(manual);
      CalendarData.instance = data;
      await tester.pumpWidget(ChangeNotifierProvider<ColorProvider>(create: (_) => ColorProvider(), child: guideHost(GuideCalendarPage(selectedGuide: id), dark: dark)));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      return data;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    List<CalendarEvent> mix() => [
          _auto('plan_a', kSourcePlan, today, 'Ravi — Worry', section: 'followups', studentUid: 'u1', studentName: 'Ravi'),
          _auto('plan_b', kSourcePlan, today, 'Amit — Chanting target', section: 'targets', studentUid: 'u2', studentName: 'Amit'),
          _auto('plan_c', kSourcePlan, today, 'Mohit — Doubt', section: 'followups', done: true, studentUid: 'u3', studentName: 'Mohit'),
          _auto('book_x', kSourceBook, today, 'Book due: Ayush', section: 'others', studentUid: 'u4', studentName: 'Ayush'),
          _auto('meeting_m', kSourceMeeting, today, 'Meeting: Harsh', studentUid: 'u5', studentName: 'Harsh'),
          _auto('trip_t', kSourceTrip, today, 'Trip: Mayapur'),
        ];

    testWidgets('TAPPING A DAY LISTS EVERYTHING, grouped like Today: Follow-ups, Target tasks, Other tasks, Meetings, Events; the done ones ticked and last', (tester) async {
      final data = await open(tester);
      data.controller.add(mix());
      await tester.pump();
      await tester.pump();
      final y = ['followups', 'targets', 'others', 'meetings', 'events'].map((g) => tester.getTopLeft(find.byKey(ValueKey('cal-group-$g'))).dy).toList();
      expect(y, [...y]..sort(), reason: 'the groups in order');
      expect(find.descendant(of: find.byKey(const ValueKey('cal-group-followups')), matching: find.text('Follow-ups (2)')), findsOneWidget);
      expect(find.byKey(const ValueKey('cal-done-plan_c')), findsOneWidget, reason: 'a done task shows its tick');
      expect(tester.getTopLeft(find.text('Ravi — Worry')).dy, lessThan(tester.getTopLeft(find.text('Mohit — Doubt')).dy), reason: 'still to do first, done last');
      expect(tester.widget<Text>(find.text('Mohit — Doubt')).style!.decoration, TextDecoration.lineThrough);
      for (final t in ['Amit — Chanting target', 'Book due: Ayush', 'Meeting: Harsh', 'Trip: Mayapur']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('A HOD sees his OWN items first and ALL GUIDES on request; a Guide has no such switch', (tester) async {
      final data = await open(tester, role: 'HOD', id: 'H');
      data.controller.add([...mix(), _auto('book_other', kSourceBook, today, 'Book due: Other guide\'s boy', guideId: 'G', section: 'others'), _auto('trip_h', kSourceTrip, today, 'Trip: HOD trip', guideId: 'H')]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('cal-all-guides')), findsOneWidget);
      expect(find.text('Book due: Other guide\'s boy'), findsNothing, reason: 'another guide\'s item: only under All guides');
      expect(find.text('Trip: HOD trip'), findsOneWidget, reason: 'his own');
      expect(find.text('Ravi — Worry'), findsOneWidget, reason: 'his own plan');
      await tester.tap(find.byKey(const ValueKey('cal-all-guides')));
      await tester.pump();
      expect(find.text('Book due: Other guide\'s boy'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cal-only-mine')));
      await tester.pump();
      expect(find.text('Book due: Other guide\'s boy'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final g = await open(tester);
      g.controller.add(mix());
      await tester.pump();
      expect(find.byKey(const ValueKey('cal-all-guides')), findsNothing);
    });

    testWidgets('EACH ROW OPENS ITS SCREEN (a student task: his profile; a book: his Books; a meeting: that association; a trip is read-only)', (tester) async {
      expect(autoEventPage(_auto('p', kSourcePlan, today, 't', studentUid: 'u1', studentName: 'Ravi')), isNotNull);
      expect(autoEventPage(_auto('p', kSourcePlan, today, 't')), isNotNull, reason: 'a task with no student opens the Plan');
      expect(autoEventPage(_auto('b', kSourceBook, today, 't', studentUid: 'u4', studentName: 'Ayush')), isNotNull);
      expect(autoEventPage(_auto('m', kSourceMeeting, today, 't', studentUid: 'u5')), isNotNull);
      expect(autoEventPage(_auto('t', kSourceTrip, today, 't')), isNotNull);
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on a phone and a website width: the grouped list fits', (tester) async {
          for (final size in [const Size(360, 2400), const Size(1100, 1800)]) {
            await tester.pumpWidget(const SizedBox());
            final data = await open(tester, scale: scale, dark: dark, size: size);
            data.controller.add(mix());
            await tester.pump();
            await tester.pump();
            expect(tester.takeException(), isNull, reason: '$size');
          }
        });
      }
    }
  });

  group('manual events for everyone, a category or named students', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      db = FakeFirebaseFirestore();
      GuideDb.useForTests(db);
    });
    tearDown(() => GuideDb.useForTests(null));

    test('a new event is saved with who it is for (empty = everyone); the model reads it back and says it', () async {
      await saveTextBlockWithEvents(
        rawText: 'Exams 31 Dec - 17 Jan',
        submittedBy: 'G',
        submittedByIsHod: false,
        scope: kScopePersonal,
        ownerGuideId: 'G',
        parsedEvents: [
          ParsedCalendarEvent(date: DateTime(2026, 12, 31), endDate: DateTime(2027, 1, 17), type: 'exam', title: 'Exams', note: '', forCategories: ['hostel'], forStudents: ['s9']),
          ParsedCalendarEvent(date: DateTime(2026, 11, 2), type: 'festival', title: 'Janmashtami', note: ''),
        ],
      );
      final docs = (await db.collection('calendarEvents').get()).docs;
      final exam = docs.firstWhere((d) => d.data()['title'] == 'Exams');
      expect([exam.data()['forCategories'], exam.data()['forStudents']], [['hostel'], ['s9']]);
      final fest = docs.firstWhere((d) => d.data()['title'] == 'Janmashtami');
      expect([fest.data()['forCategories'], fest.data()['forStudents']], [<Object?>[], <Object?>[]]);
      expect(CalendarEvent.fromDoc(exam).audienceLabel, 'For Hostel, 1 student');
      expect(CalendarEvent.fromDoc(fest).audienceLabel, 'For everyone');
    });

    test('editing an event changes who it is for; leaving it out leaves it as it was', () async {
      final ref = await db.collection('calendarEvents').add({'eventDate': ts(2026, 12, 1), 'type': 'exam', 'title': 'E', 'note': '', 'scope': kScopePersonal, 'ownerGuideId': 'G', 'forCategories': ['folk'], 'forStudents': <String>[]});
      await editEvent(eventId: ref.id, eventDate: DateTime(2026, 12, 1), type: 'exam', title: 'E', note: '', editedBy: 'G', actingIsHod: false, notifyOffsets: const ['oneWeekBefore'], forCategories: ['hostel'], forStudents: ['s1']);
      var d = (await ref.get()).data()!;
      expect([d['forCategories'], d['forStudents']], [['hostel'], ['s1']]);
      await editEvent(eventId: ref.id, eventDate: DateTime(2026, 12, 2), type: 'exam', title: 'E', note: '', editedBy: 'G', actingIsHod: false, notifyOffsets: const ['oneWeekBefore']);
      d = (await ref.get()).data()!;
      expect([d['forCategories'], d['forStudents']], [['hostel'], ['s1']], reason: 'not given: unchanged');
    });

    testWidgets('PICKER: a category, then specific students from the list', (tester) async {
      var cats = <String>[];
      var studs = <String>[];
      phone(tester, 1.0);
      await tester.pumpWidget(guideHost(Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => EventAudiencePicker(
            categories: cats,
            students: studs,
            loadStudents: () async => {'s1': 'Ayush Shah', 's2': 'Amit'},
            onChanged: (c, s) => setState(() {
              cats = c;
              studs = s;
            }),
          ),
        ),
      )));
      await tester.tap(find.byKey(const ValueKey('audience-hostel')));
      await tester.pump();
      expect(cats, ['hostel']);
      await tester.tap(find.byKey(const ValueKey('audience-specific')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audience-student-s2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-students-ok')));
      await tester.pumpAndSettle();
      expect(studs, ['s2']);
      expect(find.textContaining('(1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audience-everyone')));
      await tester.pump();
      expect([cats, studs], [<String>[], <String>[]], reason: 'Everyone clears both');
    });
  });
}
