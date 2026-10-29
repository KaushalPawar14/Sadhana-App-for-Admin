import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'priority_remove_test.dart' show need, needs, open, settleLoad;
import 'support/guide_test_support.dart';

/// INTERACTIONS NEEDED (it was "Priority students"), on the real screen: one card per student listing every reason, from the FOUR sources
/// only — the guide's targets, three days of sadhana, a doubt or a worry in his AI chat, a surrender step. The server writes the list
/// (`interactionNeeds/{uid}`, from the same data the plans use); a student with no reasons is simply not there.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  testWidgets('each source shows its reason on the student\'s card; all on the SAME card', (tester) async {
    await open(tester, 'H', defaultNeeds: false, seed: (db) async {
      await needs(db, 's1', [
        need('concern', 'concern_m1', 'Sounded discouraged or worried in his AI chat'),
        need('doubt', 'doubt_d1', 'Unanswered doubt in Bhagavad Gita'),
        need('sadhana', 'sadhana_slip', 'Not fulfilling his commitments for 3 days: chanting under 16 rounds on 3 days'),
        need('target', 'target_chanting_t1', 'Chanting target: at 12 rounds, the phase asks for 14'),
        need('surrender', 'surrender_thr_1', 'Surrender crossed 40% (up)'),
      ]);
    });
    for (final t in [
      'Sounded discouraged or worried in his AI chat',
      'Unanswered doubt in Bhagavad Gita',
      'Not fulfilling his commitments for 3 days: chanting under 16 rounds on 3 days',
      'Chanting target: at 12 rounds, the phase asks for 14',
      'Surrender crossed 40% (up)',
    ]) {
      await tester.scrollUntilVisible(find.text(t), 100, scrollable: find.byType(Scrollable).first);
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('5 reasons'), findsOneWidget);
    expect(find.text('1 need an interaction'), findsOneWidget);
  });

  testWidgets('nothing else puts a student here: no need, no card (not stale contact, a missing report, an overdue meeting, a low LIT axis)', (tester) async {
    await open(tester, 'H', defaultNeeds: false, seed: (db) async {
      // the seeded world has no interactions, an overdue request, no reports: none of it is a reason
      await needs(db, 's2', [need('surrender', 'surrender_thr_2', 'Surrender crossed 30% (down)')]);
    });
    expect(find.text('Bhima Sen'), findsOneWidget);
    expect(find.text('Arjun Kumar'), findsNothing);
    expect(find.text('Never logged an interaction'), findsNothing);
    expect(find.text('1 need an interaction'), findsOneWidget);
  });

  testWidgets('a student whose needs are all dealt with is simply not there; an empty list says so', (tester) async {
    await open(tester, 'H', defaultNeeds: false, seed: (db) async {
      await needs(db, 's1', []);
    });
    expect(find.text('Arjun Kumar'), findsNothing);
    expect(find.text('Nobody needs an interaction'), findsOneWidget);
    expect(find.text('No interaction is needed right now'), findsOneWidget);
  });

  testWidgets('a guide sees reasons only for students in their own scope', (tester) async {
    await open(tester, 'F1', defaultNeeds: false, seed: (db) async {
      await needs(db, 's1', [need('sadhana', 'sadhana_slip', 'Not fulfilling his commitments for 3 days')]);
      await needs(db, 's5', [need('doubt', 'doubt_d9', 'Unanswered doubt in Gita')]);
    });
    expect(find.text('Arjun Kumar'), findsNothing, reason: 'a boy on G\'s team: a Female Enabler must not see his reasons');
    expect(find.text('Gauri Devi'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('the reasons fit at text $scale, ${dark ? 'dark' : 'light'}', (tester) async {
        await open(tester, 'H', scale: scale, dark: dark, defaultNeeds: false, seed: (db) async {
          await needs(db, 's1', [
            need('concern', 'concern_m1', 'Sounded discouraged or worried in his AI chat'),
            need('sadhana', 'sadhana_slip', 'Not fulfilling his commitments for 3 days: chanting under 16 rounds on 3 days'),
            need('surrender', 'surrender_thr_1', 'Surrender crossed 40% and 3 days in a row fulfilling all his commitments (up)'),
          ]);
        });
        await settleLoad(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
