import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/WeeklyMilestoneDashboard.dart';
import 'package:folk_guide_app/Pages/StudentJourneyProfile.dart';

void main() {
  testWidgets('weekly plan clearly labels synthetic data', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WeeklyMilestoneDashboard(guideName: 'Subala Sundar Das'),
      ),
    );

    expect(find.textContaining('Subala Sundar Das'), findsWidgets);
    expect(find.textContaining('representative'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Students to focus on'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Students to focus on'), findsOneWidget);
  });

  testWidgets('student profile keeps LIT private and ABCDE separate', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudentJourneyProfilePage(
          studentName: 'Aarav P.',
          cohort: 'SVNIT · First year',
        ),
      ),
    );

    expect(find.text('Private LIT assessment'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ABCDE journey'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ABCDE journey'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Why this guidance'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Why this guidance'), findsOneWidget);
  });
}
