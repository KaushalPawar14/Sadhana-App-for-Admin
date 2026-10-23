import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/SadhanaTiers.dart';

/// The Guide app's tier tables, pinned to the SAME shared vectors the server's
/// own tests and the Student app's tests read.
///
/// `test/fixtures/scoring_vectors.json` is a byte-identical copy of
/// `functions/test/scoring_vectors.json`. A tier changed on the server and not
/// ported here fails this file, so the server, the Student app and the Guide app
/// cannot disagree about which tier a day reached.

Map<String, dynamic> vectors() => jsonDecode(
        File('test/fixtures/scoring_vectors.json').readAsStringSync())
    as Map<String, dynamic>;

void near(num a, num b, [String? reason]) =>
    expect(a, closeTo(b, 1e-6), reason: reason);

void main() {
  test('every tier boundary of every multiplier matches the server', () {
    final tiers = vectors()['tiers'] as Map<String, dynamic>;
    final fns = <String, double Function(Object?)>{
      'japa': japaMultiplier,
      'sleepFolk': folkSleepMultiplier,
      'temple': templeMultiplier,
      'wakeup': wakeupMultiplier,
      'sleepHostel': hostelSleepMultiplier,
    };
    // A new tier list on the server has to be ported here, not silently ignored.
    expect(tiers.keys.toSet(), fns.keys.toSet(),
        reason: 'a tier list exists on the server that this app does not know');
    for (final e in tiers.entries) {
      for (final c in e.value as List) {
        near(fns[e.key]!(c[0]), (c[1] as num).toDouble(),
            '${e.key} at ${c[0]}');
      }
    }
  });

  test('a missing or unreadable time is 1.0 — never a penalty, never a bonus',
      () {
    for (final v in [null, '', '   ', 'nonsense', '25:00', '12:60', '0:99']) {
      near(japaMultiplier(v), 1.0, 'japa for ${v.toString()}');
      near(templeMultiplier(v), 1.0, 'temple for ${v.toString()}');
      near(wakeupMultiplier(v), 1.0, 'wakeup for ${v.toString()}');
      near(folkSleepMultiplier(v), 1.0, 'folk sleep for ${v.toString()}');
      near(hostelSleepMultiplier(v), 1.0, 'hostel sleep for ${v.toString()}');
    }
  });

  test('both clock formats parse the same', () {
    expect(minutesOf('05:35'), 5 * 60 + 35);
    expect(minutesOf('5:35'), 5 * 60 + 35);
    expect(minutesOf('5:35 AM'), 5 * 60 + 35);
    expect(minutesOf('10:00 PM'), 22 * 60);
    expect(minutesOf('12:00 AM'), 0);
    expect(minutesOf('12:00 PM'), 12 * 60);
    near(templeMultiplier('5:35 AM'), 1.5);
    near(templeMultiplier('05:35'), 1.5);
  });

  test('a sleep time before noon is after midnight, and counts as 11:59 PM',
      () {
    expect(sleepMinutes('01:00'), 23 * 60 + 59);
    expect(sleepMinutes('11:59'), 23 * 60 + 59);
    expect(sleepMinutes('12:00'), 12 * 60);
    near(folkSleepMultiplier('00:30'), 1.0);
    near(hostelSleepMultiplier('00:15'), 1.0);
  });

  test('the tier rows are the real numbers, in order', () {
    for (final t in ScoreTier.values) {
      final rows = tierRows(t);
      expect(rows.length, 3, reason: '$t');
      expect(rows.map((r) => r.multiplier).toList(), [1.5, 1.25, 1.15],
          reason: '$t');
      // limits ascend, so the first match wins correctly
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i].limit, greaterThan(rows[i - 1].limit), reason: '$t');
      }
    }
  });

  test('the 1.15 threshold Priority students uses is the lowest real tier', () {
    for (final t in ScoreTier.values) {
      expect(tierRows(t).last.multiplier, kMinimumGoodTier, reason: '$t');
    }
  });

  test('clockText reads back the tier limits', () {
    expect(clockText(5 * 60 + 35), '5:35 AM');
    expect(clockText(22 * 60), '10:00 PM');
    expect(clockText(0), '12:00 AM');
    expect(clockText(12 * 60), '12:00 PM');
  });
}
