import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/theme/ThemeModeController.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/data_range_provider.dart';
import 'package:provider/provider.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/SeenMarkers.dart';
import 'package:folk_guide_app/utils/UnseenAggregates.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'guide_test_support.dart';

/// Roles used by the all-screens sweep.
enum Who { hod, guide }

AdminProfile adminProfile(Who who) {
  final isHod = who == Who.hod;
  return AdminProfile.fromMap({
    'id': isHod ? 'H' : 'G',
    'displayName': isHod ? 'Harinam Das' : 'Gopal Das',
    'role': isHod ? 'HOD' : 'GUIDE',
    'teamGuide': '',
    'email': isHod ? 'h@x.org' : 'g@x.org',
    'notificationPrefs': {},
    'notificationTypes': [],
    'admins': [
      {'id': 'H', 'displayName': 'Harinam Das', 'role': 'HOD', 'teamGuide': ''},
      {'id': 'G', 'displayName': 'Gopal Das', 'role': 'GUIDE', 'teamGuide': ''},
      {'id': 'M1', 'displayName': 'Madhava Das', 'role': 'MALE_ENABLER', 'teamGuide': 'G'},
      {'id': 'F1', 'displayName': 'Radha Devi', 'role': 'FEMALE_ENABLER', 'teamGuide': ''},
    ],
  });
}

/// A realistic little database: students in every state, admins, calendar, meetings,
/// interactions. Enough for every screen to show real rows.
Future<FakeFirebaseFirestore> seededDb() async {
  final db = FakeFirebaseFirestore();
  final now = DateTime.now();

  Future<void> user(String uid, String name, {String role = 'Stay at FOLK', String gender = 'male', String guide = 'G', String team = 'G'}) =>
      db.collection('users').doc(uid).set({
        'name': name,
        'role': role,
        'gender': gender,
        'guideId': guide,
        'teamGuide': team,
        'email': '$uid@x.org',
        'mobileNumber': '98765 43210',
        'lifetimeRounds': 1200,
        'dob': Timestamp.fromDate(DateTime(2004, 5, 17)),
      });
  await user('s1', 'Arjun Kumar');
  await user('s2', 'Bhima Sen', role: 'Stay at Hostel');
  await user('s3', 'Chaitanya Das', role: 'Stay at Localite', guide: 'M1');
  await user('s4', 'Dhruva Nair', guide: '', team: '');
  await user('s5', 'Gauri Devi', gender: 'female', role: 'Stay at Hostel', guide: 'F1', team: '');
  await user('s6', 'A student with a really long name that needs to wrap or truncate nicely');

  for (final a in [
    ('H', 'Harinam Das', 'HOD'),
    ('G', 'Gopal Das', 'GUIDE'),
    ('M1', 'Madhava Das', 'MALE_ENABLER'),
    ('F1', 'Radha Devi', 'FEMALE_ENABLER'),
  ]) {
    await db.collection('adminUsers').doc(a.$1).set({
      'displayName': a.$2,
      'role': a.$3,
      'email': '${a.$1.toLowerCase()}@x.org',
      'teamGuide': a.$1 == 'M1' ? 'G' : '',
    });
  }

  await db.collection('associations').add({
    'studentUid': 's1',
    'studentName': 'Arjun Kumar',
    'guideId': 'G',
    'status': 'pending',
    'requestedBy': 'student',
    'preferredDate': Timestamp.fromDate(now.subtract(const Duration(days: 4))),
    'studentNotes': 'Would like to talk about my chanting',
    'scopeGuide': 'G',
    'scopeTeam': 'G',
  });
  await db.collection('associations').add({
    'studentUid': 's2',
    'studentName': 'Bhima Sen',
    'guideId': 'G',
    'status': 'confirmed',
    'preferredDate': Timestamp.fromDate(now.add(const Duration(days: 2))),
    'confirmedDate': Timestamp.fromDate(now.add(const Duration(days: 2))),
    'scopeGuide': 'G',
    'scopeTeam': 'G',
  });
  await db.collection('interactionLogs').add({
    'studentUid': 's1',
    'studentName': 'Arjun Kumar',
    'guideId': 'G',
    'status': 'approved',
    'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 3))),
    'approvedSummary': {
      'followUpDate': Timestamp.fromDate(now),
      'recommendedNextAction': 'Call about the retreat',
      'summary': 'Spoke about his routine.',
    },
    'scopeGuide': 'G',
    'scopeTeam': 'G',
  });
  await db.collection('calendarEvents').add({
    'title': 'Midterm exams',
    'eventDate': Timestamp.fromDate(DateTime(now.year, now.month, now.day).add(const Duration(days: 2))),
    'endDate': Timestamp.fromDate(DateTime(now.year, now.month, now.day).add(const Duration(days: 4))),
    'type': 'exam',
    'scope': 'mandatory',
    'note': '',
    'sourceTextBlockId': 'b1',
    'notifyOffsets': ['1w'],
  });
  for (final level in ['level-1', 'level-2', 'level-3']) {
    await db.collection('books').doc(level).set({
      'book_1': 'Bhagavad-gita As It Is',
      'book_2': 'Sri Isopanisad',
      'book_3': 'The Nectar of Instruction and a very long title that needs to wrap on two lines',
    });
    await db.collection('books').doc('${level}_links').set({'book_1': 'https://example.org/1', 'book_2': ''});
  }
  for (final level in ['FOLK-2', 'FOLK-4', 'FOLK-8']) {
    await db.collection('podcastModules').doc(level).set({
      'ep_1_title': 'Introduction',
      'ep_1_duration': '12:30',
      'ep_2_title': 'The first chapter',
      'ep_2_duration': '24:10',
    });
    await db.collection('podcastModules').doc('${level}_links').set({'ep_1_link': 'https://example.org/p1'});
  }
  final trip = await db.collection('expeditions').add({
    'title': 'Govardhan parikrama weekend',
    'location': 'Vrindavan',
    'tripDate': Timestamp.fromDate(now.add(const Duration(days: 20))),
    'maxParticipants': 30,
    'status': 'open',
  });
  await trip.collection('registrations').doc('s1').set({
    'studentName': 'Arjun Kumar',
    'registeredAt': Timestamp.fromDate(now),
    'hasReflected': true,
    'reflectionText': 'It was deeply moving.',
  });
  await db.collection('chantingChallenges').add({
    'name': 'Ekadashi 64 rounds',
    'targetRounds': 64,
    'targetDate': Timestamp.fromDate(now.add(const Duration(days: 5))),
    'targetDateKey': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    'status': 'active',
    'currentTotal': 40,
    'allStudents': true,
    'guideIds': ['G'],
    'createdBy': 'H',
  });
  await db.collection('serviceAssignments').add({
    'studentUid': 's1',
    'name': 'Arjun Kumar',
    'serviceNumber': 1,
    'status': 'assigned',
    'assignedByGuideId': 'G',
    'assignedAt': Timestamp.fromDate(now),
    'competence': 'not_yet',
  });
  await db.collection('litAssessments').add({
    'studentUid': 's1',
    'guideId': 'G',
    'assessedAt': Timestamp.fromDate(now),
    'I': 3,
    'L': 2,
    'T': 4,
    'confidence': 'medium',
    'evidence': 'Regular japa and class attendance',
  });
  final target = db.collection(kGuideTargetsCollection).doc('G').collection(kCompoundTargetsSubcollection).doc('t1');
  await target.set({
    'metric': 'chanting',
    'studentCountGoal': 10,
    'perStudentValueGoal': 16,
    'status': 'active',
    'currentPhase': 2,
    'totalPhases': 4,
    'createdAt': Timestamp.fromDate(now),
  });
  for (var n = 1; n <= 4; n++) {
    await target.collection(kCompoundPhasesSubcollection).doc('$n').set({
      'phaseNumber': n,
      'status': n == 2 ? 'active' : (n < 2 ? 'done' : 'upcoming'),
      'tasks': [
        {'type': 'roster', 'fromCount': 4 + n, 'toCount': 5 + n},
        {'type': 'value', 'fromLevel': n, 'toLevel': n + 2, 'studentUids': ['s1', 's2']},
      ],
    });
  }
  await db.collection('flaggedChatMessages').add({
    'studentUid': 's1',
    'studentName': 'Arjun Kumar',
    'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 5))),
    'text': 'I feel very low lately',
    'severity': 'acute',
    'scopeGuide': 'G',
    'scopeTeam': 'G',
  });
  return db;
}

/// Wires the seams every screen needs, returns the database.
Future<FakeFirebaseFirestore> prepareApp(WidgetTester tester, {Who who = Who.hod, bool seeded = true}) async {
  SharedPreferences.setMockInitialValues({'selected_guide': who == Who.hod ? 'H' : 'G'});
  final db = seeded ? await seededDb() : FakeFirebaseFirestore();
  GuideDb.useForTests(db);
  AdminProfileProvider.instance.debugSet(adminProfile(who));
  SeenMarkers.debugDisable = true;
  UnseenAggregates.debugDisable = true;
  HierarchyApi.useForTests((name, args) async => <String, dynamic>{});
  addTearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
    SeenMarkers.debugDisable = false;
    UnseenAggregates.debugDisable = false;
    HierarchyApi.useForTests(null);
  });
  return db;
}

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  double scale = 1.0,
  bool dark = false,
  bool reduce = true,
  bool resetBoardMemory = true,
}) async {
  phone(tester, scale, resetBoardMemory: resetBoardMemory);
  SharedPreferences.setMockInitialValues({
    'selected_guide': 'H',
    ThemeModeController.prefsKey: dark ? 'dark' : 'light',
  });
  final theme = await ThemeModeController.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeModeController>.value(value: theme),
        ChangeNotifierProvider<ColorProvider>(create: (_) => ColorProvider(controller: theme)),
        ChangeNotifierProvider<AdminProfileProvider>.value(value: AdminProfileProvider.instance),
        ChangeNotifierProvider<DateRangeProvider>(create: (_) => DateRangeProvider()),
      ],
      child: guideHost(screen, dark: dark, reduce: reduce),
    ),
  );
}

/// Lets streams and futures deliver, a frame at a time.
Future<void> letDataArrive(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}
