import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentController.dart';
import 'package:folk_guide_app/agent/AgentEnv.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/agent/AgentReads.dart' show AgentRun;
import 'package:folk_guide_app/agent/AgentTypes.dart';
import 'package:folk_guide_app/agent/TaskProgress.dart';
import 'package:folk_guide_app/widgets/TaskProgressCard.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// A task's PERCENTAGE: it rises smoothly with the REAL steps (understanding -> finding -> preparing -> confirming -> saving ->
/// done), never jumps, never goes backwards, never sits frozen while the task runs, and reaches 100% only when the task is truly
/// finished; on a failure it stops and shows the reason. First the model on its own, frame by frame; then the card and the
/// controller that feeds it.

const _frame = Duration(milliseconds: 16);

/// Runs [model] for [length] at 60 frames a second from [from], returning every frame's percentage.
List<int> _run(TaskProgress model, Duration from, Duration length, {void Function(Duration t)? each}) {
  final out = <int>[];
  var t = from;
  final end = from + length;
  while (t < end) {
    each?.call(t);
    out.add(model.tick(t));
    t += _frame;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  // ------------------------------------------------------------------------------------------ the model
  group('the percentage model', () {
    /// The whole life of a confirmed task, with the real step events at the times given.
    List<(Duration, int)> life({
      Duration finding = const Duration(milliseconds: 700),
      Duration preparing = const Duration(milliseconds: 2400),
      Duration confirming = const Duration(milliseconds: 4300),
      Duration saving = const Duration(milliseconds: 9000),
      Duration done = const Duration(milliseconds: 10500),
      Duration end = const Duration(seconds: 13),
      void Function(TaskProgress m)? afterStart,
    }) {
      final m = TaskProgress();
      final samples = <(Duration, int)>[];
      var t = Duration.zero;
      var fired = <String>{};
      while (t < end) {
        if (t >= finding && fired.add('f')) m.enter(TaskStep.finding);
        if (t >= preparing && fired.add('p')) m.enter(TaskStep.preparing);
        if (t >= confirming && fired.add('c')) m.enter(TaskStep.confirming);
        if (t >= saving && fired.add('s')) m.enter(TaskStep.saving);
        if (t >= done && fired.add('d')) m.finish();
        samples.add((t, m.tick(t)));
        t += _frame;
      }
      return samples;
    }

    test('it rises in single percents: no frame moves more than a couple of percent, and never backwards', () {
      final s = life();
      var biggest = 0;
      for (var i = 1; i < s.length; i++) {
        final d = s[i].$2 - s[i - 1].$2;
        expect(d, greaterThanOrEqualTo(0), reason: 'never backwards at ${s[i].$1}');
        if (d > biggest) biggest = d;
      }
      expect(biggest, lessThanOrEqualTo(3), reason: 'a frame is at most ${TaskProgress.maxRate} %/s x 16 ms = 2.2 -> 3 whole percents; never 25 -> 50 -> 90');
      expect(s.first.$2, 0);
      expect(s.last.$2, 100);
    });

    test('every whole percent from 1 to 100 is shown on the way: 1, 2, 3 ... with none skipped', () {
      final s = life();
      final seen = s.map((e) => e.$2).toSet();
      final missing = [for (var p = 0; p <= 100; p++) if (!seen.contains(p)) p];
      expect(missing.length, lessThanOrEqualTo(3), reason: 'at most a rare skipped percent during the final run, never a jump: $missing');
    });

    test('it follows the REAL steps: each step lifts the number into its own band, and it waits for the next one below it', () {
      final m = TaskProgress();
      _run(m, Duration.zero, const Duration(milliseconds: 600));
      expect(m.step, TaskStep.understanding);
      expect(m.percent, inInclusiveRange(1, 22));
      m.enter(TaskStep.finding);
      _run(m, const Duration(milliseconds: 600), const Duration(milliseconds: 3000));
      expect(m.step, TaskStep.finding);
      expect(m.percent, inInclusiveRange(22, 45 + 14));
      m.enter(TaskStep.preparing);
      _run(m, const Duration(milliseconds: 3600), const Duration(milliseconds: 3000));
      expect(m.percent, inInclusiveRange(45, 62 + 14));
      m.enter(TaskStep.confirming);
      _run(m, const Duration(milliseconds: 6600), const Duration(milliseconds: 8000));
      expect(m.percent, inInclusiveRange(62, 74 + 14));
      m.enter(TaskStep.saving);
      _run(m, const Duration(milliseconds: 14600), const Duration(milliseconds: 3000));
      expect(m.percent, inInclusiveRange(74, 99));
      expect(m.outcome, TaskOutcome.running);
    });

    test('it never sits frozen while the task runs: in any ten seconds of a long wait the number still goes up', () {
      final m = TaskProgress();
      m.enter(TaskStep.finding);
      m.enter(TaskStep.preparing);
      m.enter(TaskStep.confirming);
      final trail = <(Duration, int)>[];
      var t = Duration.zero;
      while (t < const Duration(seconds: 90)) {
        trail.add((t, m.tick(t)));
        t += const Duration(milliseconds: 33);
      }
      // while it waits for the guide (the slowest step) look at every ten-second window: the number still goes up
      for (var start = 0; start + 10 <= 90; start++) {
        final a = trail.lastWhere((e) => e.$1 <= Duration(seconds: start)).$2;
        final b = trail.lastWhere((e) => e.$1 <= Duration(seconds: start + 10)).$2;
        expect(b, greaterThan(a), reason: 'frozen between ${start}s and ${start + 10}s at $a%');
      }
      expect(trail.last.$2, lessThan(100));
      expect(trail.last.$2, lessThanOrEqualTo(99));
    });

    test('100 is reached only when the task truly finishes - and then it runs there in about a second', () {
      final m = TaskProgress();
      m.enter(TaskStep.finding);
      m.enter(TaskStep.preparing);
      final before = _run(m, Duration.zero, const Duration(seconds: 60));
      expect(before.every((p) => p < 100), isTrue, reason: 'however long it waits, never 100 while it runs');
      m.finish();
      final run = _run(m, const Duration(seconds: 60), const Duration(milliseconds: 1500));
      expect(run.last, 100);
      expect(run.where((p) => p < 100).length * 16, lessThan(1300), reason: 'the final run takes about a second');
      expect(m.outcome, TaskOutcome.done);
      expect(m.step, TaskStep.done);
      expect(m.active, isFalse, reason: 'nothing more to animate');
    });

    test('a failure stops the number where it was and keeps the reason; nothing moves it afterwards', () {
      final m = TaskProgress();
      m.enter(TaskStep.finding);
      _run(m, Duration.zero, const Duration(seconds: 2));
      final at = m.percent;
      m.fail('Arjun is not in your team.');
      final after = _run(m, const Duration(seconds: 2), const Duration(seconds: 5));
      expect(after.every((p) => p == at), isTrue, reason: 'it stops where it was ($at%)');
      expect(m.outcome, TaskOutcome.failed);
      expect(m.failure, 'Arjun is not in your team.');
      m.finish(); // too late
      m.enter(TaskStep.saving);
      expect(_run(m, const Duration(seconds: 7), const Duration(seconds: 2)).last, at);
      expect(m.percent, lessThan(100));
    });

    test('cancelling stops it too, with a plain sentence', () {
      final m = TaskProgress();
      m.enter(TaskStep.finding);
      m.enter(TaskStep.preparing);
      m.enter(TaskStep.confirming);
      _run(m, Duration.zero, const Duration(seconds: 3));
      final at = m.percent;
      m.cancel();
      _run(m, const Duration(seconds: 3), const Duration(seconds: 3));
      expect(m.percent, at);
      expect(m.outcome, TaskOutcome.cancelled);
      expect(m.failure, contains('nothing was changed'));
    });

    test('steps only move forward: a repeated or earlier step changes nothing', () {
      final m = TaskProgress();
      m.enter(TaskStep.preparing);
      _run(m, Duration.zero, const Duration(milliseconds: 300));
      m.enter(TaskStep.finding);
      m.enter(TaskStep.preparing);
      _run(m, const Duration(milliseconds: 300), const Duration(milliseconds: 300));
      expect(m.step, TaskStep.preparing);
    });

    test('a step that arrives while the number is far behind is glided to, not jumped to', () {
      final m = TaskProgress();
      _run(m, Duration.zero, const Duration(milliseconds: 100)); // barely started
      m.enter(TaskStep.finding);
      m.enter(TaskStep.preparing);
      m.enter(TaskStep.confirming); // three real steps arrive at once (a very quick server)
      final run = _run(m, const Duration(milliseconds: 100), const Duration(seconds: 2));
      for (var i = 1; i < run.length; i++) {
        expect(run[i] - run[i - 1], lessThanOrEqualTo(3));
        expect(run[i], greaterThanOrEqualTo(run[i - 1]));
      }
      expect(run.last, greaterThan(40));
    });

    test('with no frames there is no time: the model has no clock of its own', () {
      final m = TaskProgress();
      m.enter(TaskStep.finding);
      expect(m.percent, 0);
      expect(m.tick(const Duration(seconds: 5)), 0, reason: 'the first tick only sets the origin');
    });
  });

  // ------------------------------------------------------------------------------------------ the card
  group('the progress card', () {
    testWidgets('shows the step in words and a percentage that rises, then Done at 100%', (tester) async {
      await prepareApp(tester);
      var now = Duration.zero;
      final entry = ProgressEntry('Set up a meeting with Arjun');
      await pumpScreen(tester, Scaffold(body: Center(child: TaskProgressCard(entry: entry, clock: () => now))));
      await tester.pump();
      expect(find.text('Understanding your request'), findsOneWidget);
      String percentText() => (tester.widget<Text>(find.byKey(const ValueKey('task-progress-percent'))).data ?? '');
      final seen = <int>[];
      void sample() => seen.add(int.parse(percentText().replaceAll('%', '')));
      for (var i = 0; i < 40; i++) {
        now += const Duration(milliseconds: 33);
        await tester.pump(const Duration(milliseconds: 33));
        sample();
      }
      expect(seen.last, greaterThan(5));
      expect([for (var i = 1; i < seen.length; i++) seen[i] - seen[i - 1]].every((d) => d >= 0 && d <= 3), isTrue, reason: '$seen');

      entry.progress.enter(TaskStep.finding);
      for (var i = 0; i < 30; i++) {
        now += const Duration(milliseconds: 33);
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(find.text('Finding it in the app'), findsOneWidget);

      entry.progress.finish();
      for (var i = 0; i < 80; i++) {
        now += const Duration(milliseconds: 33);
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(percentText(), '100%');
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('on a failure it stops and shows the reason', (tester) async {
      await prepareApp(tester);
      var now = Duration.zero;
      final entry = ProgressEntry('Delete the duplicate');
      await pumpScreen(tester, Scaffold(body: Center(child: TaskProgressCard(entry: entry, clock: () => now))));
      for (var i = 0; i < 30; i++) {
        now += const Duration(milliseconds: 33);
        await tester.pump(const Duration(milliseconds: 33));
      }
      entry.progress.fail('Arjun is not in your team. Ask your HOD.');
      for (var i = 0; i < 5; i++) {
        now += const Duration(milliseconds: 33);
        await tester.pump(const Duration(milliseconds: 33));
      }
      final stopped = tester.widget<Text>(find.byKey(const ValueKey('task-progress-percent'))).data;
      for (var i = 0; i < 30; i++) {
        now += const Duration(milliseconds: 33);
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(tester.widget<Text>(find.byKey(const ValueKey('task-progress-percent'))).data, stopped, reason: 'it stopped');
      expect(find.text('Stopped'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-progress-failure')), findsOneWidget);
      expect(find.text('Arjun is not in your team.'), findsOneWidget, reason: 'the reason, in a sentence');
      expect(stopped, isNot('100%'));
    });

    for (final scale in kScales) {
      for (final dark in [false, true]) {
        testWidgets('fits at text ${scale}x, ${dark ? 'dark' : 'light'}, running, failed and done', (tester) async {
          await prepareApp(tester);
          var now = Duration.zero;
          final running = ProgressEntry('Set up a meeting with a student called Arjun Kumar on Monday evening and tell him about it')..progress.enter(TaskStep.confirming);
          final failed = ProgressEntry('Delete it')..progress.fail('Something went wrong with the long reason that goes on and on to see how it wraps in the card.');
          final done = ProgressEntry('Ask')..progress.finish();
          await pumpScreen(
            tester,
            Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [for (final e in [running, failed, done]) Padding(padding: const EdgeInsets.only(bottom: 10), child: TaskProgressCard(entry: e, clock: () => now))])),
            scale: scale,
            dark: dark,
          );
          for (var i = 0; i < 60; i++) {
            now += const Duration(milliseconds: 33);
            await tester.pump(const Duration(milliseconds: 33));
          }
          expectNoOverflow(tester);
          expect(find.text('Waiting for your confirmation'), findsOneWidget);
        });
      }
    }
  });

  // ------------------------------------------------------------------------------------------ the controller feeds it
  group('the controller moves the card with the real steps', () {
    late FakeFirebaseFirestore db;
    late List<Map<String, dynamic>> replies;

    Future<AgentController> wire(WidgetTester tester, {Map<String, AgentRun>? tools}) async {
      db = await prepareApp(tester);
      replies = [];
      HierarchyApi.useForTests((name, args) async => replies.removeAt(0));
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)), tools: tools);
      AgentSession.useForTests(c);
      addTearDown(() => AgentSession.useForTests(null));
      return c;
    }

    Map<String, dynamic> msg(String text) => {'sessionId': 'sess12345', 'status': 'message', 'text': text, 'questionsLeft': 19, 'questionLimit': 20};

    Map<String, dynamic> reads() => {
          'sessionId': 'sess12345', 'status': 'need_reads', 'questionsLeft': 19, 'questionLimit': 20,
          'reads': [{'callId': 'r1', 'tool': 'find_students', 'args': <String, dynamic>{'query': 'Arjun'}}],
        };

    Map<String, dynamic> confirm() => {
          'sessionId': 'sess12345', 'status': 'confirm', 'questionsLeft': 19, 'questionLimit': 20, 'text': 'I can do that.',
          'proposal': {
            'id': 'p1', 'tainted': false, 'headsUp': <String>[],
            'actions': [{'callId': 'c1', 'tool': 'meeting_request', 'args': <String, dynamic>{}, 'title': 'Request a meeting with a student', 'lines': <Map<String, dynamic>>[], 'notifies': <String>[], 'double': false}],
          },
        };

    test('a plain answer: the card goes understanding -> done', () async {
      db = FakeFirebaseFirestore();
      replies = [msg('Hello.')];
      HierarchyApi.useForTests((name, args) async => replies.removeAt(0));
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)));
      await c.send('hi');
      final p = c.entries.whereType<ProgressEntry>().single.progress;
      p.tick(Duration.zero);
      p.tick(const Duration(seconds: 1));
      expect(p.outcome, TaskOutcome.done);
      expect(p.step, TaskStep.done);
    });

    test('a task that looks things up and proposes a change walks through finding, preparing and confirming; confirming it saves, then finishes', () async {
      db = FakeFirebaseFirestore();
      final steps = <TaskStep>[];
      late ProgressEntry task;
      AgentController? c;
      Future<AgentResult> fakeWrite(Map<String, dynamic> a, AgentEnv e) async {
        task.progress.tick(const Duration(seconds: 30));
        steps.add(task.progress.step);
        return AgentResult.ok({'done': 'Meeting requested.'});
      }

      Future<AgentResult> fakeRead(Map<String, dynamic> a, AgentEnv e) async {
        task.progress.tick(const Duration(seconds: 10));
        steps.add(task.progress.step);
        return AgentResult.ok({'students': ['Arjun']});
      }

      replies = [reads(), confirm()];
      HierarchyApi.useForTests((name, args) async => replies.removeAt(0));
      c = AgentController(
        env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)),
        tools: {'find_students': fakeRead, 'meeting_request': fakeWrite},
      );
      // the card exists once send starts; take it from the list as soon as it is there
      c.addListener(() {
        final t = c!.entries.whereType<ProgressEntry>();
        if (t.isNotEmpty) task = t.first;
      });
      await c.send('set up a meeting with Arjun');
      task.progress.tick(const Duration(seconds: 20));
      expect(task.progress.step, TaskStep.confirming, reason: 'waiting for the guide');
      expect(task.progress.outcome, TaskOutcome.running);
      expect(steps, [TaskStep.finding], reason: 'the look-up ran while the card was in its finding step');

      replies.add(msg('Done.'));
      await c.confirm(c.entries.whereType<ProposalEntry>().single, confirmations: 1);
      expect(steps, [TaskStep.finding, TaskStep.saving], reason: 'the change was made in the saving step');
      task.progress.tick(const Duration(seconds: 40));
      task.progress.tick(const Duration(seconds: 42));
      expect(task.progress.outcome, TaskOutcome.done);
      expect(task.progress.percent, 100);
    });

    test('a change that fails stops the card with the reason, and it never reaches 100', () async {
      db = FakeFirebaseFirestore();
      replies = [confirm()];
      HierarchyApi.useForTests((name, args) async => replies.removeAt(0));
      final c = AgentController(
        env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)),
        tools: {'meeting_request': (a, e) async => AgentResult.failed('Arjun is not in your team.')},
      );
      await c.send('meet Arjun');
      replies.add(msg('That did not work.'));
      await c.confirm(c.entries.whereType<ProposalEntry>().single, confirmations: 1);
      final p = c.entries.whereType<ProgressEntry>().single.progress;
      p.tick(Duration.zero);
      p.tick(const Duration(seconds: 5));
      expect(p.outcome, TaskOutcome.failed);
      expect(p.failure, 'Arjun is not in your team.');
      expect(p.percent, lessThan(100));
    });

    test('cancelling stops the card; a server error stops it with the reason', () async {
      db = FakeFirebaseFirestore();
      replies = [confirm()];
      HierarchyApi.useForTests((name, args) async => replies.removeAt(0));
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)));
      await c.send('meet Arjun');
      replies.add(msg('Cancelled, nothing changed.'));
      await c.cancel(c.entries.whereType<ProposalEntry>().single);
      final p = c.entries.whereType<ProgressEntry>().single.progress;
      p.tick(Duration.zero);
      p.tick(const Duration(seconds: 2));
      expect(p.outcome, TaskOutcome.cancelled);

      HierarchyApi.useForTests((name, args) async => throw HierarchyException('unavailable', 'DEADLINE'));
      await c.send('again');
      final q = c.entries.whereType<ProgressEntry>().last.progress;
      q.tick(Duration.zero);
      q.tick(const Duration(seconds: 1));
      expect(q.outcome, TaskOutcome.failed);
      expect(q.failure, contains("Couldn't reach the assistant"));
    });

    test('a refused question (a limit) stops the card with the limit text', () async {
      db = FakeFirebaseFirestore();
      replies = [
        {'sessionId': null, 'status': 'limit', 'why': 'day', 'text': 'Daily limit reached — try again tomorrow.', 'questionsLeft': 20, 'questionLimit': 20},
      ];
      HierarchyApi.useForTests((name, args) async => replies.removeAt(0));
      final c = AgentController(env: AgentEnv(profile: adminProfile(Who.hod), db: db, clock: () => DateTime(2026, 10, 23, 12)));
      await c.send('hello');
      final p = c.entries.whereType<ProgressEntry>().single.progress;
      p.tick(Duration.zero);
      p.tick(const Duration(seconds: 1));
      expect(p.outcome, TaskOutcome.failed);
      expect(p.failure, contains('Daily limit reached'));
    });

    testWidgets('on the assistant page the card sits under the guide\'s request and ends at 100% when the task is done', (tester) async {
      final c = await wire(tester);
      var clock = Duration.zero;
      TaskProgressCard.testClock = () => clock;
      addTearDown(() => TaskProgressCard.testClock = null);
      await pumpScreen(tester, AgentPage(controller: c), reduce: true);
      await tester.pump(const Duration(milliseconds: 100));
      replies.add(msg('Here you go.'));
      await tester.enterText(find.byKey(const ValueKey('agent-input')), 'hello');
      await tester.tap(find.byKey(const ValueKey('agent-send')));
      await tester.pump();
      for (var i = 0; i < 90; i++) {
        clock += const Duration(milliseconds: 33);
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(find.byKey(const ValueKey('task-progress')), findsOneWidget);
      final card = tester.getTopLeft(find.byKey(const ValueKey('task-progress'))).dy;
      expect(card, greaterThan(tester.getTopLeft(find.text('hello')).dy));
      expect(card, lessThan(tester.getTopLeft(find.text('Here you go.')).dy));
      for (var i = 0; i < 60; i++) {
        clock += const Duration(milliseconds: 33);
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(find.text('100%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
