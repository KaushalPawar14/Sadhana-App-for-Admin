import 'package:flutter/material.dart';

import '../Home/Calendar.dart';
import '../Pages/AbcdeHub.dart';
import '../Pages/AdminManager.dart';
import '../Pages/AssociationManager.dart';
import '../Pages/BookLinkManager.dart';
import '../Pages/ChantingChallengeManager.dart';
import '../Pages/ExpeditionManager.dart';
import '../Pages/FlaggedMessages.dart';
import '../Pages/GoalHomePage.dart';
import '../Pages/GuideCalendarPage.dart';
import '../Pages/InteractionLogger.dart';
import '../Pages/Leaderboard.dart';
import '../Pages/MusicCurriculumPage.dart';
import '../Pages/NotificationSettings.dart';
import '../Pages/OverdueAssociations.dart';
import '../Pages/PlanPage.dart';
import '../Pages/PriorityStudents.dart';
import '../Pages/ServiceBank.dart';
import '../Pages/StudentDoubtsPage.dart';
import '../Pages/StudentMusicPage.dart';
import '../Pages/StudentProfilePage.dart';
import '../Pages/SubmissionStatus.dart';
import '../Pages/WeeklyPlanning.dart';
import '../main.dart' show guideNavigatorKey;
import '../utils/AdminProfile.dart';
import '../utils/BottomNavBar.dart';
import 'AgentEnv.dart';
import 'AgentTypes.dart';

/// "Take me there": where each button the agent offers goes.
///
/// The server only ever offers a route that is in `functions/agentCatalog.js`, with a student the
/// phone itself handed it; this table is the other half. `functions/test/agentRoutes.test.js` fails
/// if a route here is not a catalogued screen, or a catalogued screen has no route here — so a button
/// the agent can offer always opens something real.
///
/// A route that opens a student looks the student up through [AgentEnv.student] first, so a button
/// can never open someone outside the guide's scope.

/// What a route needs to build its page.
class AgentRouteContext {
  const AgentRouteContext(this.me, {this.studentUid = '', this.studentName = '', this.residence = ''});

  final AdminProfile me;
  final String studentUid;
  final String studentName;
  final String residence;
}

class AgentRoute {
  const AgentRoute({this.page, this.tab, this.needsStudent = false});

  /// The page to push, or null for a tab.
  final Widget Function(AgentRouteContext c)? page;

  /// Which bottom tab to show (0 Home, 1 Analysis, 2 Tasks), instead of a page.
  final int? tab;

  /// The route opens one student, so the link must carry one.
  final bool needsStudent;
}

final Map<String, AgentRoute> kAgentRoutes = {
  'home': const AgentRoute(tab: 0),
  'analysis': const AgentRoute(tab: 1),
  'tasks': const AgentRoute(tab: 2),
  'student_profile': AgentRoute(needsStudent: true, page: (c) => StudentProfilePage(studentUid: c.studentUid)),
  'student_reports': AgentRoute(
    needsStudent: true,
    page: (c) => CalendarPage(username: c.studentName, role: c.residence, studentUid: c.studentUid),
  ),
  'student_music': AgentRoute(needsStudent: true, page: (c) => StudentMusicPage(studentUid: c.studentUid, studentName: c.studentName)),
  'associations': AgentRoute(page: (c) => const AssociationManagerPage()),
  'interactions': AgentRoute(needsStudent: true, page: (c) => InteractionLoggerPage(studentUid: c.studentUid, studentName: c.studentName)),
  'overdue_associations': AgentRoute(page: (c) => const OverdueAssociationsPage()),
  'abcde': AgentRoute(page: (c) => const AbcdeHubPage()),
  'book_links': AgentRoute(page: (c) => const BookLinkManagerPage()),
  'competitions': AgentRoute(page: (c) => const ChantingChallengeManagerPage()),
  'service_bank': AgentRoute(page: (c) => const ServiceBankPage()),
  'trips': AgentRoute(page: (c) => const ExpeditionManagerPage()),
  'priority': AgentRoute(page: (c) => const PriorityStudentsPage()),
  'doubts': AgentRoute(page: (c) => const StudentDoubtsPage()),
  'flagged': AgentRoute(page: (c) => const FlaggedMessagesPage()),
  'week_planning': AgentRoute(page: (c) => const WeeklyPlanningPage()),
  'targets': AgentRoute(page: (c) => GoalHomePage(guideId: c.me.id)),
  'leaderboard': AgentRoute(page: (c) => const LeaderboardPage()),
  'guide_calendar': AgentRoute(page: (c) => GuideCalendarPage(selectedGuide: c.me.id)),
  'plan': AgentRoute(page: (c) => const PlanPage()),
  'submissions': AgentRoute(page: (c) => const SubmissionStatusPage()),
  'notifications': AgentRoute(page: (c) => const NotificationSettingsPage()),
  'admins': AgentRoute(page: (c) => const AdminManagerPage()),
  'music': AgentRoute(page: (c) => const MusicCurriculumPage()),
};

/// What the button says: the screen, and the student if it opens one.
String agentLinkLabel(AgentLink link) {
  final names = const {
    'home': 'Home', 'analysis': 'Analysis', 'tasks': 'Tasks', 'student_profile': 'profile', 'student_reports': 'sadhana reports',
    'student_music': 'music progress', 'associations': 'Meetings', 'interactions': 'interactions', 'overdue_associations': 'Overdue meetings',
    'abcde': 'ABCDE', 'book_links': 'Book links', 'competitions': 'Chanting competitions', 'service_bank': 'Devotional service',
    'trips': 'Expeditions', 'priority': 'Priority students', 'doubts': "Students' doubts", 'flagged': 'Flagged messages',
    'week_planning': 'Week planning', 'targets': 'Targets', 'leaderboard': 'Leaderboard', 'guide_calendar': 'Your calendar', 'plan': 'Your plan',
    'submissions': 'Submissions', 'notifications': 'Notifications', 'admins': 'Admins', 'music': 'Music curriculum',
  };
  final base = names[link.route] ?? link.route;
  final who = (link.studentName ?? '').trim();
  return who.isEmpty ? 'Take me there: $base' : "Take me there: $who's $base";
}

/// Opens a route the agent offered. Returns an explanation if it could not (never throws).
Future<String?> openAgentLink(AgentLink link, {AgentEnv? env, NavigatorState? navigator}) async {
  final route = kAgentRoutes[link.route];
  if (route == null) return "I can't open that screen.";
  final e = env ?? AgentEnv();
  if (route.needsStudent && (link.studentUid ?? '').isEmpty) {
    return 'I need to know which student; ask me again with their name.';
  }
  final nav = navigator ?? guideNavigatorKey.currentState;
  if (nav == null) return "I can't open that screen right now.";

  if (route.tab != null) {
    nav.popUntil((r) => r.isFirst);
    GuideTabRequest.show(route.tab!);
    return null;
  }

  var ctx = AgentRouteContext(e.me);
  if (route.needsStudent) {
    final uid = link.studentUid ?? '';
    if (uid.isEmpty) return "I need to know which student; ask me again with their name.";
    try {
      final s = await e.student(uid);
      ctx = AgentRouteContext(e.me, studentUid: uid, studentName: (s['name'] ?? '').toString(), residence: (s['role'] ?? '').toString());
    } on AgentFailure catch (f) {
      return f.message;
    }
  }
  nav.push(MaterialPageRoute(builder: (_) => route.page!(ctx)));
  return null;
}
