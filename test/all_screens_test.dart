import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Home/Calendar.dart';
import 'package:folk_guide_app/Pages/AdminRegisterUserPage.dart';
import 'package:folk_guide_app/Pages/AllGraph.dart';
import 'package:folk_guide_app/Pages/CompoundTaskEditorPage.dart';
import 'package:folk_guide_app/Pages/GuideSignIn.dart';
import 'package:folk_guide_app/Pages/AbcdeHub.dart';
import 'package:folk_guide_app/Pages/AdminManager.dart';
import 'package:folk_guide_app/Pages/AssociationManager.dart';
import 'package:folk_guide_app/Pages/BookLinkManager.dart';
import 'package:folk_guide_app/Pages/BookReadReport.dart';
import 'package:folk_guide_app/Pages/BooksProgress.dart';
import 'package:folk_guide_app/Pages/BoysDetails.dart';
import 'package:folk_guide_app/Pages/ChantingChallengeManager.dart';
import 'package:folk_guide_app/Pages/Competition.dart';
import 'package:folk_guide_app/Pages/CompoundGoalHodReview.dart';
import 'package:folk_guide_app/Pages/CompoundGoalProgressPage.dart';
import 'package:folk_guide_app/Pages/CompoundGoalRoadmapPage.dart';
import 'package:folk_guide_app/Pages/ExpeditionManager.dart';
import 'package:folk_guide_app/Pages/FlaggedMessages.dart';
import 'package:folk_guide_app/Pages/ForceUpdateScreen.dart';
import 'package:folk_guide_app/Pages/GoalSetup.dart';
import 'package:folk_guide_app/Pages/GoalWeeklyPhasePage.dart';
import 'package:folk_guide_app/Pages/GuideCalendarPage.dart';
import 'package:folk_guide_app/Pages/InteractionLogger.dart';
import 'package:folk_guide_app/Pages/NonPlayInstallScreen.dart';
import 'package:folk_guide_app/Pages/NotificationSettings.dart';
import 'package:folk_guide_app/Pages/OverdueAssociations.dart';
import 'package:folk_guide_app/Pages/PodcastLinkManager.dart';
import 'package:folk_guide_app/Pages/PriorityHub.dart';
import 'package:folk_guide_app/Pages/PriorityStudents.dart';
import 'package:folk_guide_app/Pages/ServiceBank.dart';
import 'package:folk_guide_app/Pages/StudentProfilePage.dart';
import 'package:folk_guide_app/Pages/SubmissionStatus.dart';

import 'package:folk_guide_app/widgets/GuideGhost.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// Every screen of the app, pumped for real (an in-memory Firestore with a seeded
/// roster): light and dark at 360 dp, text scale 1.0 and 1.6, first as ghosts, then with
/// its data. No exception (an overflow is one), no spinner, no raw error text.
final Map<String, Widget Function()> screens = {
  'student_calendar': () => CalendarPage(username: 'Arjun Kumar', role: 'Stay at FOLK'),
  'abcde_hub': () => const AbcdeHubPage(),
  'admin_manager': () => const AdminManagerPage(),
  'association_manager': () => const AssociationManagerPage(),
  'book_link_manager': () => const BookLinkManagerPage(),
  'book_read_report': () => const BookReadingScreen(),
  'book_read_detail': () => StudentDetailScreen(student: 'Arjun Kumar'),
  'books_progress': () => const BooksProgressPage(studentUid: 's1', studentName: 'Arjun Kumar'),
  'tasks_tab': () => const Scaffold(body: AdminControlPage()),
  'analysis_tab': () => Scaffold(body: CompetitionPage()),
  'chanting_challenges': () => const ChantingChallengeManagerPage(),
  'hod_review': () => const CompoundGoalHodReview(hodUid: 'H'),
  'goal_progress': () => const CompoundGoalProgressPage(guideId: 'G', targetId: 't1'),
  'goal_roadmap': () => const CompoundGoalRoadmapPage(guideId: 'G', targetId: 't1', isHod: true, hodUid: 'H'),
  'expeditions': () => const ExpeditionManagerPage(),
  'flagged_messages': () => const FlaggedMessagesPage(),
  'goal_setup': () => const CompoundGoalSetupPage(guideId: 'G'),
  'goal_weekly_phase': () => const GoalWeeklyPhasePage(guideId: 'G', targetId: 't1'),
  'guide_calendar': () => const GuideCalendarPage(selectedGuide: 'G'),
  'interaction_logger': () => const InteractionLoggerPage(studentUid: 's1', studentName: 'Arjun Kumar'),
  'notification_settings': () => const NotificationSettingsPage(),
  'overdue_associations': () => const OverdueAssociationsPage(),
  'podcast_link_manager': () => const PodcastLinkManagerPage(),
  'priority_hub': () => const PriorityHubPage(),
  'priority_students': () => const PriorityStudentsPage(),
  'service_bank': () => const ServiceBankPage(),
  'student_profile': () => const StudentProfilePage(studentUid: 's1'),
  'submission_status': () => const SubmissionStatusPage(),
  'all_graph': () => const AllGraph(username: 'Arjun Kumar', role: 'Stay at FOLK'),
  'challenge_contributions': () => const ChallengeContributionsPage(challengeId: 'c1', challengeName: 'Ekadashi 64 rounds', target: 64, total: 40),
  'compound_task_editor': () => const CompoundTaskEditorPage(guideId: 'G', targetId: 't1', isHod: true, hodUid: 'H'),
  'chat_transcript': () => const StudentChatTranscriptPage(studentUid: 's1', studentName: 'Arjun Kumar', messageId: 'm1', flaggedCreatedAt: null),
  'interaction_detail': () => const InteractionDetailPage(docId: 'd1', studentName: 'Arjun Kumar'),
  'sign_in': () => const GuideSignInPage(),
  'admin_register_user': () => const AdminRegisterUserPage(),
  'force_update': () => const ForceUpdateScreen(),
  'non_play_install': () => const NonPlayInstallScreen(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);

  for (final e in screens.entries) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('${e.key} · ${dark ? 'dark' : 'light'} · ×$scale', (tester) async {
          await prepareApp(tester);
          await pumpScreen(tester, e.value(), scale: scale, dark: dark, reduce: false);
          // 1. the first frames: ghosts (or the data already there), never a spinner
          await tester.pump(const Duration(milliseconds: 30));
          expect(tester.takeException(), isNull, reason: 'first frame');
          expect(find.byType(CircularProgressIndicator), findsNothing);
          // 2. the data arrives
          await letDataArrive(tester);
          expect(tester.takeException(), isNull, reason: 'with data');
          expect(find.byType(CircularProgressIndicator), findsNothing);
          // 3. everything has settled (snackbars, animations)
          await tester.pump(const Duration(seconds: 6));
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull, reason: 'settled');
          // nothing is still loading: no breathing ghost and no running ticker
          expect(GhostClock.instance.running, isFalse, reason: 'a ghost is still breathing after the data arrived');
          expect(tester.binding.transientCallbackCount, 0, reason: 'a ticker is still running');
          if (scale == 1.0) await shot(tester, 'screens/${e.key}_${dark ? 'dark' : 'light'}');
          // leave: let any polling timer of the screen run out
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
        });
      }
    }
  }
}
