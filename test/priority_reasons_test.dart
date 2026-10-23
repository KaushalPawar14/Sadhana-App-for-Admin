import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/PriorityReasons.dart';

/// The reason rules: each needs three consecutive days, own category only, form
/// values only. The tier judgements come from `SadhanaTiers`, which
/// `sadhana_tiers_test.dart` pins to the server's shared vectors.

final _today = DateTime(2026, 10, 22);

/// A window of [n] days, most recent first, built from [reports] (index 0 is
/// today). A null entry is a day with no report.
List<ReportDay> window(List<Map<String, dynamic>?> reports) => [
      for (var i = 0; i < reports.length; i++)
        ReportDay(_today.subtract(Duration(days: i)), reports[i]),
    ];

/// A FOLK day that is fine on every count.
Map<String, dynamic> goodFolk({
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

/// A Hostel & Localite day that is fine on every count.
Map<String, dynamic> goodHostel({
  num rounds = 16,
  num reading = 30,
  String wake = '05:30',
  String sleep = '22:30',
}) =>
    {
      'chantRounds': rounds,
      'bookReading': reading,
      'wakeUpTime': wake,
      'sleepTiming': sleep,
      'finishTiming': '10:00',
    };

List<String> keysOf(List<PriorityReason> r) => r.map((x) => x.key).toList();

List<PriorityReason> folk(List<Map<String, dynamic>?> days,
        {int chant = 16, int reading = 30}) =>
    priorityReasonsFor(
        days: window(days),
        role: 'Stay at FOLK',
        chantCommitment: chant,
        readingCommitment: reading);

List<PriorityReason> hostel(List<Map<String, dynamic>?> days,
        {int chant = 16, int reading = 30}) =>
    priorityReasonsFor(
        days: window(days),
        role: 'Stay at Hostel',
        chantCommitment: chant,
        readingCommitment: reading);

void main() {
  test('a student doing everything well has no reasons', () {
    expect(folk([goodFolk(), goodFolk(), goodFolk(), goodFolk()]), isEmpty);
    expect(hostel([goodHostel(), goodHostel(), goodHostel()]), isEmpty);
  });

  // -------------------------------------------------------------------------
  // no report
  // -------------------------------------------------------------------------
  test('three days with no report is a reason, two is not', () {
    expect(keysOf(folk([null, null, goodFolk(), goodFolk()])), isEmpty);
    expect(keysOf(folk([null, null, null, goodFolk()])), contains('no_report'));
  });

  test('it names the day of the last report', () {
    final r = folk([null, null, null, goodFolk()]);
    expect(r.single.text, 'No report since 19 Oct');
  });

  test('a student who never filed at all says so', () {
    final r = folk([null, null, null, null]);
    expect(r.single.text, 'No report in the last 4 days');
  });

  test('the run must be the MOST RECENT days — an old gap does not count', () {
    expect(
        keysOf(folk(
            [goodFolk(), null, null, null, goodFolk()])),
        isEmpty);
  });

  // -------------------------------------------------------------------------
  // chanting
  // -------------------------------------------------------------------------
  test('three reported days under the commitment', () {
    final low = goodFolk(rounds: 8);
    expect(keysOf(folk([low, low, goodFolk()])), isEmpty);
    expect(keysOf(folk([low, low, low])), contains('chanting_below'));
  });

  test('the sentence names the commitment', () {
    final low = goodFolk(rounds: 4);
    expect(folk([low, low, low], chant: 12).first.text,
        'Chanting under 12 rounds on 3 days');
  });

  test('no commitment on file falls back to the standard 16', () {
    final low = goodFolk(rounds: 10);
    expect(folk([low, low, low], chant: 0).first.text,
        'Chanting under 16 rounds on 3 days');
  });

  test('exactly the commitment is not under it', () {
    final at = goodFolk(rounds: 16);
    expect(keysOf(folk([at, at, at])), isEmpty);
  });

  test('UNFILED days do not break the run of reported days', () {
    // the three most recent FILED days are all low, with a gap between them
    final low = goodFolk(rounds: 2);
    expect(keysOf(folk([low, null, low, low])), contains('chanting_below'));
  });

  // -------------------------------------------------------------------------
  // reading
  // -------------------------------------------------------------------------
  test('three reported days under the reading commitment', () {
    final low = goodFolk(reading: 5);
    expect(keysOf(folk([low, low, low])), contains('reading_below'));
  });

  test('a reading commitment of 0 skips the reason entirely', () {
    final none = goodFolk(reading: 0);
    expect(keysOf(folk([none, none, none], reading: 0)),
        isNot(contains('reading_below')));
  });

  // -------------------------------------------------------------------------
  // the morning: temple (FOLK) vs wake-up (Hostel & Localite)
  // -------------------------------------------------------------------------
  test('FOLK is judged on temple entry, below the 1.15 tier', () {
    // 06:00 is exactly 1.15 — still good
    final onTier = goodFolk(temple: '06:00');
    expect(keysOf(folk([onTier, onTier, onTier])), isEmpty);
    // 06:01 falls to 1.0
    final late = goodFolk(temple: '06:01');
    expect(folk([late, late, late]).first.text,
        'Reaching the temple late on 3 days');
  });

  test('Hostel & Localite is judged on wake-up, not temple entry', () {
    final late = goodHostel(wake: '06:31');
    expect(hostel([late, late, late]).first.text, 'Waking up late on 3 days');
    // a stray temple time on a hostel form is ignored
    final strayTemple = {...goodHostel(), 'templeEntry': '09:00'};
    expect(keysOf(hostel([strayTemple, strayTemple, strayTemple])), isEmpty);
  });

  // -------------------------------------------------------------------------
  // sleep
  // -------------------------------------------------------------------------
  test('sleep uses the right table for the form', () {
    // 23:00 is the 1.15 boundary for FOLK, and still 1.25 for hostel
    final folkEdge = goodFolk(sleep: '23:01');
    expect(keysOf(folk([folkEdge, folkEdge, folkEdge])),
        contains('sleep_late'));
    final hostelSame = goodHostel(sleep: '23:01');
    expect(keysOf(hostel([hostelSame, hostelSame, hostelSame])),
        isNot(contains('sleep_late')));
  });

  test('after midnight counts as 11:59 PM, which is late for both', () {
    final f = goodFolk(sleep: '00:30');
    final h = goodHostel(sleep: '00:30');
    expect(keysOf(folk([f, f, f])), contains('sleep_late'));
    expect(keysOf(hostel([h, h, h])), contains('sleep_late'));
  });

  // -------------------------------------------------------------------------
  // several at once, and clearing
  // -------------------------------------------------------------------------
  test('every reason that is true is listed, on ONE result', () {
    final bad = goodFolk(
        rounds: 2, reading: 1, temple: '08:00', sleep: '23:59');
    final keys = keysOf(folk([bad, bad, bad]));
    expect(keys, containsAll(
        ['chanting_below', 'reading_below', 'morning_late', 'sleep_late']));
    expect(keys, isNot(contains('no_report')));
  });

  test('a reason stops being returned the moment it stops being true', () {
    final low = goodFolk(rounds: 2);
    expect(keysOf(folk([low, low, low])), contains('chanting_below'));
    // one good day at the front breaks the run
    expect(keysOf(folk([goodFolk(), low, low, low])), isEmpty);
  });

  test('a missing value is not a failure — only a real number under target is',
      () {
    final noRounds = {...goodFolk()}..remove('chantRounds');
    expect(keysOf(folk([noRounds, noRounds, noRounds])),
        isNot(contains('chanting_below')));
  });

  test('an empty window gives nothing', () {
    expect(priorityReasonsFor(
            days: const [],
            role: 'Stay at FOLK',
            chantCommitment: 16,
            readingCommitment: 30),
        isEmpty);
  });

  test('fewer than three filed days cannot raise a value reason', () {
    final low = goodFolk(rounds: 1);
    expect(keysOf(folk([low, low])), isEmpty);
  });

  test('the reason keys are stable — the server stores them', () {
    expect(PriorityReasonKind.values.map((k) => k.key).toList(), [
      'no_report',
      'chanting_below',
      'reading_below',
      'morning_late',
      'sleep_late',
    ]);
    for (final k in PriorityReasonKind.values) {
      expect(PriorityReasonKindX.fromKey(k.key), k);
    }
    expect(PriorityReasonKindX.fromKey('something_else'), isNull);
  });

  test('the residence decides the form', () {
    expect(isHostelForm('Stay at Hostel'), isTrue);
    expect(isHostelForm('Stay at Localite'), isTrue);
    expect(isHostelForm('Stay at FOLK'), isFalse);
    expect(isHostelForm(null), isFalse);
    expect(isHostelForm(''), isFalse);
  });
}
