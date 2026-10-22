import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'priority_remove_test.dart' show open, settleLoad;
import 'support/guide_test_support.dart';

/// The automatic sadhana reasons, on the real Priority students screen: one
/// card per student listing every reason that is currently true, clearing by
/// itself when a reason stops being true.

/// `dd-MM-yyyy` for `n` days before yesterday — the window's most recent days.
String dayId(int n) {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day - 1 - n);
  String p(int x) => x.toString().padLeft(2, '0');
  return '${p(d.day)}-${p(d.month)}-${d.year}';
}

Map<String, dynamic> report({
  num rounds = 16,
  num reading = 30,
  String temple = '05:35',
  String sleep = '22:00',
}) =>
    {
      'chantRounds': rounds,
      'bookReading': reading,
      'templeEntry': temple,
      'sleepTiming': sleep,
      'finishTiming': '10:00',
    };

/// Files `days` for a FOLK student, most recent first.
Future<void> file(FakeFirebaseFirestore db, String name,
    List<Map<String, dynamic>?> days) async {
  for (var i = 0; i < days.length; i++) {
    final r = days[i];
    if (r == null) continue;
    await db
        .collection('sadhana-reports')
        .doc(name)
        .collection('dates')
        .doc(dayId(i))
        .set(r);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  testWidgets('three days under the commitment shows the reason on the card',
      (tester) async {
    await open(tester, 'H', seed: (db) async {
      // everyone else files properly, so only Arjun carries a value reason
      for (final n in ['Bhima Sen', 'Chaitanya Das', 'Dhruva Nair',
        'Gauri Devi']) {
        await file(db, n, [report(), report(), report()]);
      }
      await file(db, 'Arjun Kumar',
          [report(rounds: 4), report(rounds: 4), report(rounds: 4)]);
    });

    expect(find.text('Chanting under 16 rounds on 3 days'), findsOneWidget);
  });

  testWidgets('every current reason is listed on the SAME card',
      (tester) async {
    await open(tester, 'H', seed: (db) async {
      final bad = report(rounds: 2, temple: '08:00', sleep: '23:59');
      await file(db, 'Arjun Kumar', [bad, bad, bad]);
    });

    expect(find.text('Chanting under 16 rounds on 3 days'), findsOneWidget);
    expect(find.text('Reaching the temple late on 3 days'), findsOneWidget);
    expect(find.text('Sleeping late on 3 days'), findsOneWidget);
  });

  testWidgets('a reason that is no longer true is simply not there',
      (tester) async {
    await open(tester, 'H', seed: (db) async {
      // the most recent day is good again, so the run is broken
      await file(db, 'Arjun Kumar',
          [report(), report(rounds: 4), report(rounds: 4), report(rounds: 4)]);
    });

    expect(find.text('Chanting under 16 rounds on 3 days'), findsNothing);
  });

  testWidgets('two days is not yet a reason', (tester) async {
    await open(tester, 'H', seed: (db) async {
      await file(db, 'Arjun Kumar',
          [report(rounds: 4), report(rounds: 4), report()]);
    });
    expect(find.text('Chanting under 16 rounds on 3 days'), findsNothing);
  });

  testWidgets('a Hostel student is judged on wake-up, not temple entry',
      (tester) async {
    await open(tester, 'H', seed: (db) async {
      // Bhima Sen is 'Stay at Hostel' in the seeded world
      final late = {
        'chantRounds': 16, 'bookReading': 30,
        'wakeUpTime': '06:31', 'sleepTiming': '22:30', 'finishTiming': '10:00',
      };
      for (var i = 0; i < 3; i++) {
        await db.collection('hostel-sadhana').doc('Bhima Sen')
            .collection('dates').doc(dayId(i)).set(late);
      }
    });
    expect(find.text('Waking up late on 3 days'), findsOneWidget);
    expect(find.text('Reaching the temple late on 3 days'), findsNothing);
  });

  testWidgets('a guide sees reasons only for students in their own scope',
      (tester) async {
    await open(tester, 'F1', seed: (db) async {
      // a boy on G's team — a Female Enabler must not see his reasons
      await file(db, 'Arjun Kumar',
          [report(rounds: 2), report(rounds: 2), report(rounds: 2)]);
    });
    expect(find.text('Arjun Kumar'), findsNothing);
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('the reasons fit at text $scale, ${dark ? 'dark' : 'light'}',
          (tester) async {
        await open(tester, 'H', scale: scale, dark: dark, seed: (db) async {
          final bad = report(rounds: 2, temple: '08:00', sleep: '23:59');
          await file(db, 'Arjun Kumar', [bad, bad, bad]);
        });
        await settleLoad(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
