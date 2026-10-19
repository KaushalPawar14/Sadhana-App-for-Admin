import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/CompetitionScore.dart';

// The score breakdown of a student (the Scores tab): points per item and the average
// multipliers, read from the competition document the server writes (new point system).
Map<String, dynamic> folkDoc() => {
      'category': 'folk',
      'weekly.total_score': 337.5,
      'weekly.days_count': 2,
      'weekly.bhagavatam_class': 100,
      'weekly.daily_service': 50,
      'weekly.chanting_rounds': 112.5,
      'weekly.book_reading': 50,
      'weekly.extra_lecture': 25,
      'weekly.temple_multiplier': 2.5,
      'weekly.japa_multiplier': 2.4,
      'weekly.sleeping_multiplier': 2.0,
      'weekly.wakeup_multiplier': 0,
      'monthly.total_score': 900,
      'monthly.days_count': 4,
      'monthly.temple_multiplier': 5.0,
      'monthly.japa_multiplier': 4.6,
      'monthly.sleeping_multiplier': 4.0,
    };

String line(({String label, String value}) l) => '${l.label} ${l.value}';

void main() {
  test('FOLK: every item, and the average multipliers (sum / days)', () {
    final t = CompetitionTotals.fromData(folkDoc());
    expect(t.hostelLocalite, false);
    expect(t.weeklyTotalScore, 337.5);
    expect(t.weekly.itemLines(hostelLocalite: false).map(line).toList(),
        ['SB class 100.0', 'Services 50.0', 'Chanting 112.5', 'Reading 50.0', 'Extra lecture 25.0']);
    expect(t.weekly.multiplierLines(hostelLocalite: false).map(line).toList(),
        ['Temple 1.25', 'Japa 1.20', 'Sleep 1.00']);
    expect(t.monthly.multiplierLines(hostelLocalite: false).map(line).toList(),
        ['Temple 1.25', 'Japa 1.15', 'Sleep 1.00']);
  });

  test('the items add up to the total (what the server wrote)', () {
    final w = CompetitionTotals.fromData(folkDoc()).weekly;
    expect(w.sbClass + w.service + w.chanting + w.reading + w.extraLecture, w.total);
  });

  test('Hostel & Localite: wake-up instead of temple; no services or extra lecture', () {
    final t = CompetitionTotals.fromData({
      'category': 'hostel_localite',
      'weekly.total_score': 100,
      'weekly.days_count': 2,
      'weekly.bhagavatam_class': 40,
      'weekly.chanting_rounds': 40,
      'weekly.book_reading': 20,
      'weekly.wakeup_multiplier': 2.3,
      'weekly.japa_multiplier': 2.0,
      'weekly.sleeping_multiplier': 2.5,
      'weekly.temple_multiplier': 9, // never shown for H&L
    });
    expect(t.hostelLocalite, true);
    expect(t.weekly.itemLines(hostelLocalite: true).map(line).toList(),
        ['SB class 40.0', 'Chanting 40.0', 'Reading 20.0']);
    expect(t.weekly.multiplierLines(hostelLocalite: true).map(line).toList(),
        ['Wake-up 1.15', 'Japa 1.00', 'Sleep 1.25']);
  });

  test('no days / an empty or unusual document: 1.00 multipliers and zero items, never a crash', () {
    final t = CompetitionTotals.fromData({'weekly.total_score': 'x', 'weekly.days_count': null});
    expect(t.weeklyTotalScore, 0);
    expect(t.weekly.multiplierLines(hostelLocalite: false).map(line).toList(),
        ['Temple 1.00', 'Japa 1.00', 'Sleep 1.00']);
    expect(t.weekly.itemLines(hostelLocalite: false).first.value, '0.0');
    expect(CompetitionTotals.fromSnapshotData(null), isNull);
  });
}
