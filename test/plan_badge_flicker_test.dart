import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/PlanPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/PlanData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';

import 'support/guide_test_support.dart';
import 'support/plan_fakes.dart';

// NO FLICKER ON THE "NEW" BADGE AND THE ORANGE DOT.
//
// The two things seen: (a) tapping a Home plan widget flashed the orange dot for a split second although nothing was new; (b) after opening the "N new"
// list and coming back, the count stayed for about a second and then went.
//
// THE CAUSE: the admin's "seen" marker is written with the server's own time. Until the server answers, the admin's OWN screen reads that field as EMPTY
// (a pending server timestamp has no value yet), and EMPTY means "never seen": the dot lit up and the count came back, for the round trip, and went when the
// server answered. A first frame from the old local cache did the same (an old "unseen" before the live answer).
//
// THE FIX: (1) a pending write of the admin's own seen-field reads as "seen everything" and a stale cache is not shown (SeenMarkers); (2) looking (the list,
// the Plan page) clears the badge and the dots at once, here, and the save to the server goes on behind (PlanData.looked / leftPlan); (3) nothing is shown
// until the live value is known.

/// Friday 30 Oct 2026, 10:00.
DateTime _t(int minute) => DateTime(2026, 10, 30, 10, minute);

PendingChanges _changes(List<String> texts, {int minute = 0, List<String> uids = const []}) => PendingChanges([
      for (var i = 0; i < texts.length; i++) PendingChange(type: 'doubt', text: texts[i], studentUid: i < uids.length ? uids[i] : '', at: _t(minute + i)),
    ]);

/// A [PlanData] whose server side the test drives by hand: the pending list, the "seen" cursor, and a save that can be slow, never answer, or fail.
class _Fake extends PlanData {
  final pendingC = StreamController<PendingChanges>.broadcast();
  final seenC = StreamController<DateTime?>.broadcast();
  final planC = StreamController<PlanDoc?>.broadcast();
  final saves = <String>[];

  /// null: the save succeeds at once; a Completer: it waits for the test (a slow network, never answering); [failSave]: it throws (offline).
  Completer<void>? hold;
  bool failSave = false;

  // like Firestore: a new listener gets the current value first, then the changes
  PendingChanges? _lastPending;
  DateTime? _lastSeen;
  var _seenKnown = false;
  void setPending(PendingChanges p) {
    _lastPending = p;
    pendingC.add(p);
  }

  void setSeen(DateTime? v) {
    _lastSeen = v;
    _seenKnown = true;
    seenC.add(v);
  }

  @override
  Stream<PendingChanges> pending(String adminId) async* {
    if (_lastPending != null) yield _lastPending!;
    yield* pendingC.stream;
  }

  @override
  Stream<DateTime?> seenAt(String adminId) async* {
    if (_seenKnown) yield _lastSeen;
    yield* seenC.stream;
  }
  @override
  Stream<PlanDoc?> plan(String adminId) => planC.stream;
  @override
  Future<void> markPlanSeen(String adminId) async {
    saves.add(adminId);
    if (failSave) throw StateError('offline');
    if (hold != null) await hold!.future;
  }

  DateTime clock = _t(30);
  @override
  DateTime now() => clock;
}

/// Counts what a stream shows, frame by frame.
class _Watch {
  _Watch(Stream<NewChanges> s) {
    sub = s.listen((c) => counts.add(c.count));
  }
  late final StreamSubscription<NewChanges> sub;
  final counts = <int>[];
  int? get last => counts.isEmpty ? null : counts.last;
  Future<void> close() => sub.cancel();
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

AdminProfile _me() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    SeenMarkers.debugDisable = true;
  });
  tearDownAll(() {
    SeenMarkers.debugDisable = false;
    PlanData.instance = const FirestorePlanData();
    AdminProfileProvider.instance.debugSet(null);
  });

  group('THE SEEN-FIELD: what the admin\'s own screen reads while the server has not answered yet', () {
    test('a pending write of his own seen-field reads as "seen everything", never as empty ("never seen")', () {
      final at = Timestamp.fromDate(_t(5));
      expect(SeenMarkers.seenValue(at, pending: false), at);
      expect(SeenMarkers.seenValue(at, pending: true), at, reason: 'a value that is there is the value');
      expect(SeenMarkers.seenValue(null, pending: true), SeenMarkers.everythingSeen, reason: 'the pending server timestamp is empty locally: it is NOT "never seen"');
      expect(SeenMarkers.seenValue(null, pending: false), isNull, reason: 'really never seen');
      expect(SeenMarkers.everythingSeen.compareTo(Timestamp.fromDate(DateTime(2100))) > 0, isTrue);
    });

    test('only a LIVE snapshot counts: from the server, or carrying his own pending write; an old cache alone is not shown', () {
      expect(SeenMarkers.isLive(fromCache: false, hasPendingWrites: false), isTrue);
      expect(SeenMarkers.isLive(fromCache: true, hasPendingWrites: true), isTrue, reason: 'offline, after his own tap');
      expect(SeenMarkers.isLive(fromCache: true, hasPendingWrites: false), isFalse, reason: 'the stale first frame');
    });

    test('THE DOT: seen after the latest change = no dot; his own tap (the pending echo) never lights it; the answer does not either; a real new change does', () async {
      final latest = StreamController<Timestamp?>.broadcast();
      final seen = StreamController<Timestamp?>.broadcast();
      final shown = <bool>[];
      final sub = SeenMarkers.unseenFrom(latest.stream, seen.stream).listen(shown.add);
      latest.add(Timestamp.fromDate(_t(1)));
      await _settle();
      expect(shown, isEmpty, reason: 'nothing is shown until BOTH are known (no stale first frame)');
      seen.add(SeenMarkers.seenValue(Timestamp.fromDate(_t(2)), pending: false));
      await _settle();
      expect(shown, [false], reason: 'nothing new: no dot');
      // he taps the Home plan widget: the page writes "seen"; his own screen first reads the field as pending (empty) ...
      seen.add(SeenMarkers.seenValue(null, pending: true));
      await _settle();
      // ... and then the server's time arrives
      seen.add(SeenMarkers.seenValue(Timestamp.fromDate(_t(3)), pending: false));
      await _settle();
      expect(shown.every((v) => !v), isTrue, reason: 'no flash: the dot never lit up, not even for a frame (${shown.length} frames)');
      // a REAL new change still lights it
      latest.add(Timestamp.fromDate(_t(9)));
      await _settle();
      expect(shown.last, isTrue);
      // and what the old code did, for the record: reading the pending field as empty = "never seen" = the flash
      final flash = <bool>[];
      final s2 = StreamController<Timestamp?>.broadcast();
      final sub2 = SeenMarkers.unseenFrom(latest.stream, s2.stream).listen(flash.add);
      s2.add(Timestamp.fromDate(_t(10)));
      await _settle();
      latest.add(Timestamp.fromDate(_t(9)));
      await _settle();
      s2.add(null);
      await _settle();
      expect(flash.last, isTrue, reason: 'the empty read is what made the dot flash');
      await sub.cancel();
      await sub2.cancel();
    });
  });

  group('THE COUNT: looking clears it at once, whatever the network does', () {
    test('nothing is emitted until the list AND the cursor are known: no stale first frame, no zero-then-count', () async {
      final d = _Fake();
      final w = _Watch(d.newChanges('G'));
      d.setPending(_changes(['a', 'b']));
      await _settle();
      expect(w.counts, isEmpty, reason: 'the cursor is not known yet');
      d.setSeen(_t(-5));
      await _settle();
      expect(w.counts, [2], reason: 'the first thing shown is the live count');
      await w.close();
    });

    test('the badge clears the moment he looks, and stays clear while the save is slow, never answers, or fails (offline)', () async {
      for (final mode in ['fast', 'slow', 'never', 'offline']) {
        final d = _Fake();
        if (mode == 'slow' || mode == 'never') d.hold = Completer<void>();
        if (mode == 'offline') d.failSave = true;
        final w = _Watch(d.newChanges('G'));
        d.setSeen(_t(-5));
        d.setPending(_changes(['New doubt: Testing', 'Book finished: Ayush']));
        await _settle();
        expect(w.last, 2, reason: mode);
        d.looked('G');
        await _settle();
        expect(w.last, 0, reason: '$mode: cleared at once, before any answer from the server');
        expect(d.saves, ['G'], reason: '$mode: and saved in the background');
        // the server's own cursor catches up (or not): the count never comes back
        d.setSeen(null); // the pending echo read as empty
        await _settle();
        expect(w.last, 0, reason: '$mode: a stale or empty echo does not bring the count back');
        d.setSeen(_t(40));
        await _settle();
        expect(w.last, 0, reason: mode);
        expect(w.counts.skip(1).every((c) => c == 0), isTrue, reason: '$mode: no frame between shows a count again: ${w.counts}');
        if (d.hold != null) d.hold!.complete();
        await _settle();
        await w.close();
      }
    });

    test('a change that arrives AFTER he looked is new again; the ones he looked at stay seen', () async {
      final d = _Fake();
      final w = _Watch(d.newChanges('G'));
      d.setSeen(_t(-5));
      d.setPending(_changes(['a', 'b']));
      await _settle();
      d.looked('G');
      await _settle();
      expect(w.last, 0);
      d.setPending(_changes(['a', 'b', 'c'])); // c is stamped after b
      await _settle();
      expect(w.last, 1, reason: 'real new changes still appear normally');
      d.looked('G');
      await _settle();
      expect(w.last, 0);
      await w.close();
    });

    test('a change stamped BEFORE his own clock still counts correctly: only the server\'s stamps are compared, never the phone\'s time', () async {
      final d = _Fake()..clock = DateTime(2026, 10, 30, 9, 0); // a phone clock an hour slow
      final w = _Watch(d.newChanges('G'));
      d.setSeen(_t(-5));
      d.setPending(_changes(['a', 'b']));
      await _settle();
      d.looked('G');
      await _settle();
      expect(w.last, 0, reason: 'cleared whatever the phone clock says');
      await w.close();
    });

    test('the Plan page keeps its "New" tags and bar while he is on it (the cursor from before the look); leaving clears them, and the badge outside was clear all along', () async {
      final d = _Fake();
      final outside = _Watch(d.newChanges('G'));
      final page = _Watch(d.newChanges('G', forPage: true));
      d.setSeen(_t(-5));
      d.setPending(_changes(['a', 'b'], uids: ['u1', 'u2']));
      await _settle();
      expect(outside.last, 2);
      expect(page.last, 2);
      d.looked('G', save: false); // the page opens
      await _settle();
      expect(d.saves, isEmpty, reason: 'opening the page saves nothing yet: his tags keep the server\'s cursor');
      expect(outside.last, 0, reason: 'the Home badge is clear the moment the page is open');
      expect(page.last, 2, reason: 'the page still shows what is new');
      d.setSeen(_t(40));
      await _settle();
      expect(page.last, 2, reason: 'even when the server moves the cursor while he is here');
      d.setPending(_changes(['a', 'b', 'c'], uids: ['u1', 'u2', 'u3']));
      await _settle();
      expect(page.last, 3, reason: 'a change that arrives while he is on the page shows on it');
      d.leftPlan('G');
      await _settle();
      expect(d.saves, ['G'], reason: 'leaving saves "seen"');
      expect(outside.last, 0);
      // the next visit: no tags, no badge
      final next = _Watch(d.newChanges('G', forPage: true));
      await _settle();
      expect(next.last, 0, reason: 'a fresh visit has nothing new');
      await outside.close();
      await page.close();
      await next.close();
    });

    test('a look at the LIST on Home, then the Plan page: the page still tags what the list showed', () async {
      final d = _Fake();
      final outside = _Watch(d.newChanges('G'));
      d.setSeen(_t(-5));
      d.setPending(_changes(['a', 'b'], uids: ['u1', 'u2']));
      await _settle();
      d.looked('G'); // the list on Home
      await _settle();
      expect(outside.last, 0);
      final page = _Watch(d.newChanges('G', forPage: true));
      await _settle();
      expect(page.last, 2, reason: 'the rows keep their "New" tag on this visit');
      d.leftPlan('G');
      d.setSeen(_t(40)); // the server's answer to the save
      final again = _Watch(d.newChanges('G', forPage: true));
      await _settle();
      expect(again.last, 0);
      await outside.close();
      await page.close();
      await again.close();
    });
  });

  group('THE PLAN PAGE on screen', () {
    Future<_Fake> open(WidgetTester tester) async {
      phone(tester, 1.0);
      AdminProfileProvider.instance.debugSet(_me());
      final d = _Fake();
      PlanData.instance = d;
      await tester.pumpWidget(guideHost(const PlanPage()));
      d.planC.add(planDoc(left: 0));
      d.setSeen(_t(-5));
      d.setPending(_changes(['New doubt: Testing', 'Book finished: Ayush']));
      await tester.pump();
      await tester.pump();
      return d;
    }

    testWidgets('opening the page does not flash anything: the bar shows the live count, the page saved nothing yet', (tester) async {
      final d = await open(tester);
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('plan-refresh-badge')), matching: find.byType(Text))).data, '2');
      expect(d.saves, isEmpty);
    });

    testWidgets('a tap on the badge: the list opens and the bar says "Nothing new" AT ONCE, with the save still hanging (slow network)', (tester) async {
      final d = await open(tester);
      d.hold = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('plan-pending-line')));
      await tester.pump();
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing, reason: 'cleared in the very next frame');
      expect(find.byKey(const ValueKey('plan-pending-ok')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('2 new'), findsOneWidget, reason: 'the list still shows what he looked at');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing, reason: 'back from the list: still clear');
      expect(d.saves, ['G']);
      // the server catches up with an empty echo, then the real time: never a count in between
      d.setSeen(null);
      await tester.pump();
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing);
      d.setSeen(_t(40));
      await tester.pump();
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing);
      d.hold!.complete();
      await tester.pump();
    });

    testWidgets('a new change arriving after the list was looked at shows on the bar again (real new changes still appear)', (tester) async {
      final d = await open(tester);
      await tester.tap(find.byKey(const ValueKey('plan-pending-line')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing);
      d.setPending(_changes(['New doubt: Testing', 'Book finished: Ayush', 'New worry: Ravi']));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('plan-refresh-badge')), matching: find.byType(Text))).data, '1');
    });

    testWidgets('the save failing (offline) changes nothing on screen and throws nothing', (tester) async {
      final d = await open(tester);
      d.failSave = true;
      await tester.tap(find.byKey(const ValueKey('plan-pending-line')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-refresh-badge')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
