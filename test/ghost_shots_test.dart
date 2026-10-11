import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/FolkBoysEntry.dart';
import 'package:folk_guide_app/Pages/GuideCalendarPage.dart';
import 'package:folk_guide_app/Pages/WeeklyPlanning.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/CalendarData.dart';
import 'package:folk_guide_app/utils/GoalData.dart';
import 'package:folk_guide_app/utils/HomeData.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:folk_guide_app/utils/WeekData.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'states_home_test.dart' show ManualHomeData, me;
import 'states_calendar_test.dart' show ManualCalendarData, hod;
import 'states_screens_test.dart' show ManualWeekData, ManualGoalData;
import 'screens_test.dart' show profile;
import 'support/guide_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGuideFonts();
    UnseenAggregates.debugDisable = true;
    SeenMarkers.debugDisable = true;
  });
  for (final dark in [false, true]) {
    final m = dark ? 'dark' : 'light';
    testWidgets('ghost shots $m', (tester) async {
      SharedPreferences.setMockInitialValues({'selected_guide': 'G'});
      phone(tester, 1.0);
      AdminProfileProvider.instance.debugSet(me());
      HomeData.instance = ManualHomeData();
      await tester.pumpWidget(guideHost(const Scaffold(body: FolkBoysEntryScreen(selectedGuide: 'G')), dark: dark, reduce: false));
      await tester.pump(const Duration(milliseconds: 900));
      await shot(tester, 'ghosts/home_$m');
      await tester.pumpWidget(const SizedBox());
      CalendarData.instance = ManualCalendarData();
      AdminProfileProvider.instance.debugSet(hod());
      await tester.pumpWidget(guideHost(const GuideCalendarPage(selectedGuide: 'G'), dark: dark, reduce: false));
      await tester.pump(const Duration(milliseconds: 900));
      await shot(tester, 'ghosts/calendar_$m');
      await tester.pumpWidget(const SizedBox());
      WeekData.instance = ManualWeekData();
      AdminProfileProvider.instance.debugSet(profile('GUIDE'));
      await tester.pumpWidget(guideHost(const WeeklyPlanningPage(), dark: dark, reduce: false));
      await tester.pump(const Duration(milliseconds: 900));
      await shot(tester, 'ghosts/week_$m');
      await tester.pumpWidget(const SizedBox());
      GoalData.instance = ManualGoalData();
      await tester.pumpWidget(guideHost(const GoalHomePage(guideId: 'G'), dark: dark, reduce: false));
      await tester.pump(const Duration(milliseconds: 900));
      await shot(tester, 'ghosts/targets_$m');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
