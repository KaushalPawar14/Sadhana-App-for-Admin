import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/Residence.dart';

void main() {
  test('daily services exist for FOLK residents only', () {
    expect(hasDailyServices('Stay at FOLK'), isTrue);
    expect(hasDailyServices(''), isTrue, reason: 'no residence yet: nothing is hidden');
    expect(hasDailyServices('Stay at Hostel'), isFalse);
    expect(hasDailyServices('Stay at Localite'), isFalse);
    expect(hasDailyServices('  Stay at Hostel '), isFalse, reason: 'stray spaces do not matter');
  });
}
