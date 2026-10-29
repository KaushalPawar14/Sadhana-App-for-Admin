import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:folk_guide_app/Pages/AssociationManager.dart';
import 'package:folk_guide_app/Pages/ChantingChallengeManager.dart';
import 'package:folk_guide_app/Pages/ExpeditionManager.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/Pages/GuideCalendarPage.dart';
import 'package:folk_guide_app/Pages/InteractionLogger.dart';
import 'package:folk_guide_app/theme/GuideColors.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/AutoCalendar.dart';
import 'package:folk_guide_app/utils/CalendarData.dart';
import 'package:folk_guide_app/utils/CalendarQueries.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/widgets/GuideCalendar.dart';

import 'support/guide_test_support.dart';

/// The calendar's AUTOMATIC events: each kind appears with its source, moves when the source changes, goes when the source goes,
/// follows the viewer's scope, opens the screen that edits it, and never gets an edit dialog of its own. The manual events keep
/// working exactly as before (see calendar_test.dart).
///
/// "Today" in the data tests is Fri 30 Oct 2026.

final _now = DateTime(2026, 10, 30, 12);
Timestamp ts(int y, int m, int d, [int h = 12]) => Timestamp.fromDate(DateTime(y, m, d, h));

AdminProfile _profile(String id, String role, {String team = ''}) => AdminProfile.fromMap({
      'id': id,
      'displayName': 'Admin $id',
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [
        {'id': 'H', 'displayName': 'Hari', 'role': 'HOD', 'teamGuide': ''},
        {'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': ''},
        {'id': 'G2', 'displayName': 'Govinda', 'role': 'GUIDE', 'teamGuide': ''},
        {'id': 'M1', 'displayName': 'Madhava', 'role': 'MALE_ENABLER', 'teamGuide': 'G'},
        {'id': 'F1', 'displayName': 'Radha', 'role': 'FEMALE_ENABLER', 'teamGuide': ''},
      ],
    });

Map<String, Object?> _stamp(String guide, String team, [String gender = 'male']) => {'scopeGuide': guide, 'scopeTeam': team, 'scopeGender': gender};

Future<void> _seed(FakeFirebaseFirestore db) async {
  Future<void> log(String id, String student, String guide, String team,
      {String gender = 'male', Timestamp? follow, Timestamp? when, Timestamp? made, String status = 'approved', String action = 'Call him'}) =>
      db.collection('interactionLogs').doc(id).set({
        'studentUid': 'u_$student', 'studentName': student, 'status': status, 'interactionType': 'Call',
        'interactionDate': when ?? ts(2026, 10, 20), 'createdAt': made ?? ts(2026, 10, 20),
        if (follow != null) 'approvedSummary': {'recommendedNextAction': action, 'followUpDate': follow},
        ..._stamp(guide, team, gender),
      });
  await log('l_own', 'Own', 'G', 'G', follow: ts(2026, 11, 2), action: 'Ask about japa');
  await log('l_team', 'TeamBoy', 'M1', 'G', follow: ts(2026, 11, 3));
  await log('l_other', 'OtherBoy', 'G2', 'G2', follow: ts(2026, 11, 4));
  await log('l_unboy', 'UnBoy', '', '', follow: ts(2026, 11, 5));
  await log('l_girl', 'Girl', 'F1', '', gender: 'female', follow: ts(2026, 11, 6));
  await log('l_pending', 'Pending', 'G', 'G', follow: ts(2026, 11, 7), status: 'pending');
  await log('l_plan', 'Planned', 'G', 'G', when: ts(2026, 11, 8), made: ts(2026, 10, 28));
  await log('l_logged_today', 'Today', 'G', 'G', when: ts(2026, 10, 30), made: ts(2026, 10, 30));

  Future<void> meet(String id, String student, String status, Timestamp date, String guide, String team, [String gender = 'male']) =>
      db.collection('associations').doc(id).set({
        'studentUid': 'u_$student', 'studentName': student, 'status': status, 'confirmedDate': date, 'preferredDate': date, ..._stamp(guide, team, gender),
      });
  await meet('a_conf', 'Bhima', 'confirmed', ts(2026, 11, 9), 'G', 'G');
  await meet('a_pend', 'Pend', 'pending', ts(2026, 11, 9), 'G', 'G');
  await meet('a_done', 'Done', 'completed', ts(2026, 11, 9), 'G', 'G');

  await db.collection('expeditions').doc('t_mine').set({'title': 'Mayapur', 'tripDate': ts(2026, 11, 20), 'endDate': ts(2026, 11, 23), 'createdBy': 'G', 'status': 'upcoming', 'archived': false});
  await db.collection('expeditions').doc('t_other').set({'title': 'Govinda trip', 'tripDate': ts(2026, 11, 21), 'endDate': ts(2026, 11, 21), 'createdBy': 'G2', 'status': 'upcoming', 'archived': false});
  await db.collection('expeditions').doc('t_old').set({'title': 'Archived', 'tripDate': ts(2026, 11, 21), 'endDate': ts(2026, 11, 21), 'createdBy': 'G', 'archived': true});

  await db.collection('chantingChallenges').doc('c_mine').set({'name': 'Diwali Push', 'startDate': ts(2026, 11, 1), 'endDate': ts(2026, 11, 5), 'guideId': 'G', 'status': 'active'});
  await db.collection('chantingChallenges').doc('c_other').set({'name': 'Other', 'startDate': ts(2026, 11, 1), 'endDate': ts(2026, 11, 5), 'guideId': 'G2', 'status': 'active'});
  await db.collection('chantingChallenges').doc('c_missed').set({'name': 'Missed', 'startDate': ts(2026, 11, 1), 'endDate': ts(2026, 11, 5), 'guideId': 'G', 'status': 'missed'});
  await db.collection('chantingChallenges').doc('c_keys').set({'name': 'Keys only', 'startDateKey': '10-11-2026', 'endDateKey': '12-11-2026', 'guideId': 'G', 'status': 'active'});

  await db.collection('guideTargets').doc('G').collection('targets').doc('tg1').set({
    'metric': 'chanting', 'status': 'active', 'endDate': ts(2026, 12, 20), 'currentPhase': 2, 'totalPhases': 4, 'studentCountGoal': 5, 'perStudentValueGoal': 16,
  });
  await db.collection('guideTargets').doc('G').collection('targets').doc('tg1').collection('phases').doc('2').set({
    'phaseNumber': 2, 'status': 'active', 'startedAt': ts(2026, 10, 27), 'tasks': [], 'weeklyHistory': [],
  });
  await db.collection('guideTargets').doc('G').collection('targets').doc('tg_done').set({'metric': 'books', 'status': 'completed', 'endDate': ts(2026, 12, 1), 'currentPhase': 1, 'totalPhases': 1});
  await db.collection('guideTargets').doc('G2').collection('targets').doc('tg2').set({'metric': 'books', 'status': 'active', 'endDate': ts(2026, 12, 21), 'currentPhase': 1, 'totalPhases': 2});
}

Future<List<CalendarEvent>> _first(Stream<List<CalendarEvent>> s) async {
  // the feed emits as each source answers; take the list once the sources have settled
  List<CalendarEvent> last = const [];
  final done = Completer<void>();
  final sub = s.listen((e) => last = e);
  await Future<void>.delayed(const Duration(milliseconds: 150));
  await sub.cancel();
  if (!done.isCompleted) done.complete();
  return last;
}

String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
Map<String, CalendarEvent> _byId(List<CalendarEvent> l) => {for (final e in l) e.id: e};

// ---------------------------------------------------------------------------------------------------------------------------------
// a widget-test calendar whose automatic events can change while it is open

class _LiveCalendarData implements CalendarData {
  _LiveCalendarData(this.manual);
  final List<CalendarEvent> manual;
  final controller = StreamController<List<CalendarEvent>>.broadcast();
  @override
  Future<List<CalendarEvent>> events(String guideId) async => manual;
  @override
  Future<List<CalendarTextBlock>> textBlocks(String guideId) async => const [];
  @override
  Stream<List<CalendarEvent>> automaticEvents(String guideId) => controller.stream;
}

CalendarEvent _auto(String id, String source, DateTime start, String title, {DateTime? end, String studentUid = '', String studentName = '', String guideId = 'G'}) => CalendarEvent(
      id: id,
      eventDate: start,
      endDate: end,
      type: 'other',
      title: title,
      note: '',
      sourceTextBlockId: '',
      scope: 'personal',
      ownerGuideId: null,
      notifyOffsets: const [],
      source: source,
      refId: id,
      studentUid: studentUid,
      studentName: studentName,
      guideId: guideId,
    );

final _today = DateTime.now();
final _off = _today.day > 14 ? 0 : 14;
DateTime _d(int day) => DateTime(_today.year, _today.month, day + _off);

Finder _cell(DateTime day) => find.byWidgetPredicate((w) => w is GuideDayCell && isSameCalendarDay(w.day, day) && !w.outside);

Future<_LiveCalendarData> _open(WidgetTester tester, {List<CalendarEvent> manual = const [], double scale = 1.0, bool dark = false}) async {
  phone(tester, scale);
  AdminProfileProvider.instance.debugSet(_profile('G', 'GUIDE'));
  final data = _LiveCalendarData(manual);
  CalendarData.instance = data;
  await tester.pumpWidget(ChangeNotifierProvider<ColorProvider>(
    create: (_) => ColorProvider(),
    child: guideHost(const GuideCalendarPage(selectedGuide: 'G'), dark: dark),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  return data;
}

Future<void> _pickDay(WidgetTester tester, DateTime day) async {
  await tester.tap(find.descendant(of: _cell(day), matching: find.text('${day.day}')));
  await tester.pump();
  await tester.pump();
}

List<CalendarEvent> _everyKind() => [
      _auto('target_G_tg1', kSourceTarget, _d(3), 'Target deadline: chanting'),
      _auto('followUp_l1', kSourceFollowUp, _d(4), 'Follow-up: Mananjit', studentUid: 'u1', studentName: 'Mananjit'),
      _auto('interaction_i1', kSourceInteraction, _d(5), 'Interaction: Arjun', studentUid: 'u2', studentName: 'Arjun'),
      _auto('meeting_a1', kSourceMeeting, _d(6), 'Meeting: Bhima', studentUid: 'u3', studentName: 'Bhima'),
      _auto('trip_t1', kSourceTrip, _d(8), 'Trip: Mayapur', end: _d(10)),
      _auto('competition_c1', kSourceCompetition, _d(9), 'Competition: Diwali Push', end: _d(12)),
    ];

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

  group('the feed: every source, live, by scope', () {
    late FakeFirebaseFirestore db;
    setUp(() async {
      db = FakeFirebaseFirestore();
      GuideDb.useForTests(db);
      await _seed(db);
    });
    tearDown(() {
      GuideDb.useForTests(null);
      AdminProfileProvider.instance.debugSet(null);
    });

    Future<Map<String, CalendarEvent>> feedFor(AdminProfile p) async {
      AdminProfileProvider.instance.debugSet(p);
      return _byId(await _first(AutoCalendarFeed(p, clock: () => _now).events()));
    }

    test('a Guide: follow-ups, planned interaction, confirmed meeting, trip, competitions, target deadline and phase end — each from its source', () async {
      final e = await feedFor(_profile('G', 'GUIDE'));
      expect(e.keys.toSet(), {
        'followUp_l_own', 'followUp_l_team', 'followUp_l_unboy', // own, his Male Enabler's, the unassigned boys'
        'interaction_l_plan',
        'meeting_a_conf',
        'trip_t_mine',
        'competition_c_mine', 'competition_c_keys',
        'target_G_tg1', 'phase_G_tg1_2',
      });
      expect(_day(e['followUp_l_own']!.eventDate), '2026-11-02');
      expect(e['followUp_l_own']!.title, 'Follow-up: Own');
      expect(e['followUp_l_own']!.note, 'Ask about japa');
      expect(e['followUp_l_own']!.source, kSourceFollowUp);
      expect(e['followUp_l_own']!.isAutomatic, isTrue);
      expect(_day(e['interaction_l_plan']!.eventDate), '2026-11-08');
      expect(_day(e['meeting_a_conf']!.eventDate), '2026-11-09');
      // ranges
      expect(e['trip_t_mine']!.isMultiDay, isTrue);
      expect([_day(e['trip_t_mine']!.eventDate), _day(e['trip_t_mine']!.effectiveEndDate)], ['2026-11-20', '2026-11-23']);
      expect([_day(e['competition_c_mine']!.eventDate), _day(e['competition_c_mine']!.effectiveEndDate)], ['2026-11-01', '2026-11-05']);
      expect([_day(e['competition_c_keys']!.eventDate), _day(e['competition_c_keys']!.effectiveEndDate)], ['2026-11-10', '2026-11-12'], reason: 'dd-MM-yyyy keys are read too');
      // target: the deadline, and the running phase's end (a phase runs a week from 27 Oct -> 2 Nov)
      expect(_day(e['target_G_tg1']!.eventDate), '2026-12-20');
      expect(e['target_G_tg1']!.title, 'Target deadline: chanting');
      expect(_day(e['phase_G_tg1_2']!.eventDate), '2026-11-02');
      expect(e['phase_G_tg1_2']!.title, 'Phase 2 ends: chanting');
    });

    test('what is not an event: a pending follow-up, an interaction logged today, a pending / completed meeting, an archived trip, a missed competition, a finished target', () async {
      final e = await feedFor(_profile('G', 'GUIDE'));
      for (final id in ['followUp_l_pending', 'interaction_l_logged_today', 'meeting_a_pend', 'meeting_a_done', 'trip_t_old', 'competition_c_missed', 'target_G_tg_done']) {
        expect(e.containsKey(id), isFalse, reason: id);
      }
    });

    test('scope: a Guide never sees another Guide\'s student, trip, competition or target', () async {
      final e = await feedFor(_profile('G', 'GUIDE'));
      expect(e.keys.any((k) => k.contains('l_other') || k.contains('t_other') || k.contains('c_other') || k.contains('tg2')), isFalse);
      expect(e.keys.any((k) => k.contains('l_girl')), isFalse, reason: 'a Guide does not see the girls');
    });

    test('scope: the HOD sees all of it', () async {
      final e = await feedFor(_profile('H', 'HOD'));
      expect(e.keys, containsAll([
        'followUp_l_own', 'followUp_l_team', 'followUp_l_other', 'followUp_l_unboy', 'followUp_l_girl',
        'trip_t_mine', 'trip_t_other', 'competition_c_mine', 'competition_c_other', 'target_G_tg1', 'target_G2_tg2',
      ]));
    });

    test('scope: a Male Enabler sees his own and the unassigned boys\', not the Guide\'s own', () async {
      final e = await feedFor(_profile('M1', 'MALE_ENABLER', team: 'G'));
      expect(e.keys.where((k) => k.startsWith('followUp_')).toSet(), {'followUp_l_team', 'followUp_l_unboy'});
      expect(e.keys.any((k) => k.startsWith('trip_') || k.startsWith('competition_') || k.startsWith('target_')), isFalse, reason: 'those are the Guide\'s own');
    });

    test('scope: a Female Enabler sees the girls only', () async {
      final e = await feedFor(_profile('F1', 'FEMALE_ENABLER'));
      expect(e.keys.where((k) => k.startsWith('followUp_')).toSet(), {'followUp_l_girl'});
    });

    test('LIVE: a follow-up that moves, appears or is removed changes the calendar by itself', () async {
      final p = _profile('G', 'GUIDE');
      AdminProfileProvider.instance.debugSet(p);
      List<CalendarEvent> latest = const [];
      final sub = AutoCalendarFeed(p, clock: () => _now).events().listen((e) => latest = e);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(_day(_byId(latest)['followUp_l_own']!.eventDate), '2026-11-02');

      // moved
      await db.collection('interactionLogs').doc('l_own').update({'approvedSummary.followUpDate': ts(2026, 11, 12)});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(_day(_byId(latest)['followUp_l_own']!.eventDate), '2026-11-12');

      // appears (a new follow-up) and disappears (the follow-up removed: the date cleared)
      await db.collection('interactionLogs').doc('l_new').set({
        'studentUid': 'u_new', 'studentName': 'New', 'status': 'approved', 'approvedSummary': {'followUpDate': ts(2026, 11, 15)}, ..._stamp('G', 'G'),
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(_byId(latest).containsKey('followUp_l_new'), isTrue);
      await db.collection('interactionLogs').doc('l_own').update({'approvedSummary.followUpDate': null});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(_byId(latest).containsKey('followUp_l_own'), isFalse);

      // a trip deleted, a target's deadline moved, a competition ended, a meeting completed
      await db.collection('expeditions').doc('t_mine').delete();
      await db.collection('guideTargets').doc('G').collection('targets').doc('tg1').update({'endDate': ts(2027, 1, 5)});
      await db.collection('chantingChallenges').doc('c_mine').update({'status': 'achieved'});
      await db.collection('associations').doc('a_conf').update({'status': 'completed'});
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final e = _byId(latest);
      expect(e.containsKey('trip_t_mine'), isFalse);
      expect(_day(e['target_G_tg1']!.eventDate), '2027-01-05');
      expect(e.containsKey('competition_c_mine'), isFalse);
      expect(e.containsKey('meeting_a_conf'), isFalse);

      // a phase that ends earlier than a short deadline is capped at the deadline
      await db.collection('guideTargets').doc('G').collection('targets').doc('tg1').update({'endDate': ts(2026, 10, 30)});
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(_day(_byId(latest)['phase_G_tg1_2']!.eventDate), '2026-10-30');
      await sub.cancel();
    });

    test('a source that cannot be read costs only itself', () async {
      // an admin with no profile admins list and no data of a kind: nothing throws, the rest shows
      final p = _profile('G', 'GUIDE');
      AdminProfileProvider.instance.debugSet(p);
      await db.collection('expeditions').doc('t_mine').delete();
      final e = _byId(await _first(AutoCalendarFeed(p, clock: () => _now).events()));
      expect(e.containsKey('followUp_l_own'), isTrue);
      expect(e.containsKey('trip_t_mine'), isFalse);
    });
  });

  group('tap-through: each kind opens the screen where its item is edited', () {
    test('every automatic kind has a screen; a manual event has none (its own dialog edits it)', () {
      expect(autoEventPage(_auto('a', kSourceTarget, _d(1), 't', guideId: 'G')), isA<GoalHomePage>());
      expect(autoEventPage(_auto('a', kSourcePhase, _d(1), 't', guideId: 'G')), isA<GoalHomePage>());
      expect(autoEventPage(_auto('a', kSourceFollowUp, _d(1), 't', studentUid: 'u1', studentName: 'S')), isA<InteractionLoggerPage>());
      expect(autoEventPage(_auto('a', kSourceInteraction, _d(1), 't', studentUid: 'u1', studentName: 'S')), isA<InteractionLoggerPage>());
      expect(autoEventPage(_auto('a', kSourceMeeting, _d(1), 't')), isA<AssociationManagerPage>());
      expect(autoEventPage(_auto('a', kSourceTrip, _d(1), 't')), isA<ExpeditionManagerPage>());
      expect(autoEventPage(_auto('a', kSourceCompetition, _d(1), 't')), isA<ChantingChallengeManagerPage>());
      expect(autoEventPage(_auto('a', kSourceFollowUp, _d(1), 't')), isNull, reason: 'a follow-up with no student cannot open one');
      final manual = CalendarEvent(
          id: 'm', eventDate: _d(1), endDate: null, type: 'exam', title: 'Exams', note: '', sourceTextBlockId: 'b', scope: 'personal', ownerGuideId: 'G', notifyOffsets: const []);
      expect(manual.isAutomatic, isFalse);
      expect(autoEventPage(manual), isNull);
    });
  });

  group('the calendar screen', () {
    testWidgets('every kind shows on its day with its own colour, in the strips that already existed', (tester) async {
      final data = await _open(tester);
      data.controller.add(_everyKind());
      await tester.pump();
      await tester.pump();
      final g = GuideColors.light;
      Color dotOf(DateTime day) {
        final dots = find.descendant(
            of: _cell(day),
            matching: find.byWidgetPredicate((w) => w is Container && w.constraints == const BoxConstraints.tightFor(width: 5, height: 5)));
        return (tester.widget<Container>(dots.first).decoration as BoxDecoration).color!;
      }

      expect(dotOf(_d(3)), g.eventTarget);
      expect(dotOf(_d(4)), g.eventFollowUp);
      expect(dotOf(_d(5)), g.eventInteraction);
      expect(dotOf(_d(6)), g.eventMeeting);
      expect(dotOf(_d(8)), g.eventTrip);
      expect(dotOf(_d(12)), g.eventCompetition);
      // the two ranges also draw their band behind the days (3 days of trip, 4 of competition)
      Finder bandsIn(DateTime day) => find.descendant(of: _cell(day), matching: find.byType(GuideBandGrow));
      expect(bandsIn(_d(8)), findsOneWidget);
      expect(bandsIn(_d(9)), findsNWidgets(2), reason: 'trip and competition overlap on the 9th');
      expect(bandsIn(_d(10)), findsNWidgets(2));
      expect(bandsIn(_d(11)), findsOneWidget, reason: 'only the competition continues');
      expect(bandsIn(_d(13)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a day lists its automatic events with the kind and the date; a range reads "start – end"', (tester) async {
      final data = await _open(tester);
      data.controller.add(_everyKind());
      await tester.pump();
      await _pickDay(tester, _d(4));
      expect(find.text('Follow-up: Mananjit'), findsOneWidget);
      expect(find.textContaining('Follow-up ·'), findsOneWidget);
      await _pickDay(tester, _d(9));
      expect(find.text('Trip: Mayapur'), findsOneWidget, reason: 'any day inside the range lists it');
      expect(find.text('Competition: Diwali Push'), findsOneWidget);
      expect(find.textContaining('Trip ·'), findsOneWidget);
    });

    testWidgets('LIVE: when the source changes the calendar changes — a follow-up moves, then goes', (tester) async {
      final data = await _open(tester);
      data.controller.add([_auto('followUp_l1', kSourceFollowUp, _d(4), 'Follow-up: Mananjit', studentUid: 'u1', studentName: 'Mananjit')]);
      await tester.pump();
      await _pickDay(tester, _d(4));
      expect(find.text('Follow-up: Mananjit'), findsOneWidget);

      data.controller.add([_auto('followUp_l1', kSourceFollowUp, _d(6), 'Follow-up: Mananjit', studentUid: 'u1', studentName: 'Mananjit')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Follow-up: Mananjit'), findsNothing, reason: 'no longer on the 4th');
      await _pickDay(tester, _d(6));
      expect(find.text('Follow-up: Mananjit'), findsOneWidget);

      data.controller.add(const []);
      await tester.pump();
      await tester.pump();
      expect(find.text('Follow-up: Mananjit'), findsNothing);
      expect(find.text('Nothing due'), findsOneWidget);
    });

    testWidgets('automatic events are read-only here: a tap opens the screen, never the edit dialog', (tester) async {
      GuideDb.useForTests(FakeFirebaseFirestore());
      addTearDown(() => GuideDb.useForTests(null));
      final data = await _open(tester);
      data.controller.add([_auto('followUp_l1', kSourceFollowUp, _d(6), 'Follow-up: Bhima', studentUid: 'u3', studentName: 'Bhima')]);
      await tester.pump();
      await _pickDay(tester, _d(6));
      await tester.ensureVisible(find.text('Follow-up: Bhima'));
      await tester.pump();
      // the page under test pushes onto the host's navigator
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      expect(nav.canPop(), isFalse);
      await tester.tap(find.text('Follow-up: Bhima'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Edit event'), findsNothing, reason: 'there is no edit dialog for an automatic event');
      expect(nav.canPop(), isTrue, reason: 'a screen opened');
      expect(find.byType(InteractionLoggerPage), findsOneWidget, reason: "the interaction's own screen");
    });

    testWidgets('manual events are still editable beside the automatic ones', (tester) async {
      final manual = CalendarEvent(
          id: 'm1', eventDate: _d(7), endDate: _d(8), type: 'exam', title: 'Exams', note: '', sourceTextBlockId: 'b1', scope: 'personal', ownerGuideId: 'G', notifyOffsets: const ['oneWeekBefore']);
      final data = await _open(tester, manual: [manual]);
      data.controller.add(_everyKind());
      await tester.pump();
      await _pickDay(tester, _d(7));
      await tester.ensureVisible(find.text('Exams'));
      await tester.pump();
      await tester.tap(find.text('Exams'));
      await tester.pumpAndSettle();
      expect(find.text('Edit event'), findsOneWidget);
    });

    testWidgets('the legend names every kind', (tester) async {
      await _open(tester);
      for (final l in ['Target', 'Follow-up', 'Interaction', 'Meeting', 'Trip', 'Competition']) {
        expect(find.descendant(of: find.byType(GuideCalendarLegend), matching: find.text(l)), findsOneWidget, reason: l);
      }
    });

    for (final dark in [false, true]) {
      for (final scale in kScales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: every kind, no overflow', (tester) async {
          final data = await _open(tester, scale: scale, dark: dark);
          data.controller.add([
            ..._everyKind(),
            for (var i = 0; i < 6; i++) _auto('followUp_x$i', kSourceFollowUp, _d(9), 'Follow-up: A long student name number $i', studentUid: 'u$i', studentName: 'S$i'),
          ]);
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
          final legend = tester.getRect(find.byType(GuideCalendarLegend));
          expect(legend.right, lessThanOrEqualTo(360));
          final cell = tester.getRect(_cell(_d(9)));
          expect(cell.width, lessThanOrEqualTo(360 / 7 + .5));
          await _pickDay(tester, _d(9));
          await tester.scrollUntilVisible(find.text('Competition: Diwali Push'), 200, scrollable: find.byType(Scrollable).first);
          expect(tester.takeException(), isNull);
          // a day with many events: only three dots and a "+"
          final dots = find.descendant(
              of: _cell(_d(9)), matching: find.byWidgetPredicate((w) => w is Container && w.constraints == const BoxConstraints.tightFor(width: 5, height: 5)));
          expect(dots, findsNWidgets(3));
        });
      }
    }

    testWidgets('screenshots: automatic events, light and dark (for looking at)', (tester) async {
      for (final dark in [false, true]) {
        final data = await _open(tester, dark: dark);
        data.controller.add(_everyKind());
        await tester.pump();
        await _pickDay(tester, _d(9));
        await shot(tester, 'calendar_auto_${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
