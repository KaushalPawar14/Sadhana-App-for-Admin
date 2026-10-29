import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/GoalHomePage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GoalCompoundQueries.dart';
import 'package:folk_guide_app/utils/GoalData.dart';

import 'support/guide_test_support.dart';

/// A target whose AI plan could not be generated is a visible DRAFT ("waiting for AI plan") with the REAL reason; it is retried by the server, and
/// the guide can retry or delete it. The limit message names the target in the way.

class _Targets implements GoalData {
  _Targets(this.list);
  final List<CompoundTarget> list;
  @override
  Stream<List<CompoundTarget>> targets(String guideId) => Stream.value(list);
}

CompoundTarget _t(String status, {int phases = 0, String reason = '', String metric = 'chanting'}) => CompoundTarget.from('G', 't-$status', {
      'metric': metric,
      'studentCountGoal': 5,
      'perStudentValueGoal': 16,
      'status': status,
      'currentPhase': phases == 0 ? 0 : 1,
      'totalPhases': phases,
      if (reason.isNotEmpty) 'draftReason': reason,
    });

AdminProfile _me() => AdminProfile.fromMap({'id': 'G', 'displayName': 'Gopal', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org', 'notificationPrefs': {}, 'notificationTypes': [], 'admins': []});

Future<void> _open(WidgetTester tester, List<CompoundTarget> list, {double scale = 1.0, bool dark = false}) async {
  phone(tester, scale);
  AdminProfileProvider.instance.debugSet(_me());
  GoalData.instance = _Targets(list);
  await tester.pumpWidget(guideHost(const GoalHomePage(guideId: 'G'), dark: dark));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() {
    GoalData.instance = const FirestoreGoalData();
    AdminProfileProvider.instance.debugSet(null);
  });

  test('a draft is a target that is not active; its reason is read from the document', () {
    final d = _t('draft', reason: 'The AI service has no credit left (OpenAI billing).');
    expect(d.isDraft, isTrue);
    expect(d.isActive, isFalse, reason: 'a draft never counts toward the one-per-type limit');
    expect(d.draftReason, contains('no credit left'));
    expect(_t('active', phases: 4).isDraft, isFalse);
  });

  test('the REAL reason is shown, never a generic line: the server sentence as it is; the code only when the server said nothing', () {
    expect(planFailureReason(FirebaseFunctionsException(code: 'failed-precondition', message: 'The AI service has no credit left (OpenAI billing). Add credit and the plan is generated automatically.')),
        'The AI service has no credit left (OpenAI billing). Add credit and the plan is generated automatically.');
    expect(planFailureReason(FirebaseFunctionsException(code: 'internal', message: 'INTERNAL')), contains('(internal)'));
    expect(planFailureReason(Exception('socket closed')), 'socket closed');
  });

  test('the limit sentence names the target (what it is, until when) and says what to do', () {
    final t = CompoundTarget.from('G', 'x', {'metric': 'chanting', 'studentCountGoal': 5, 'perStudentValueGoal': 16, 'status': 'active', 'endDate': Timestamp20.at(2026, 12, 20), 'totalPhases': 4});
    final m = limitMessageFor(t);
    expect(m, startsWith('You already have a chanting target (5 students at 16'));
    expect(m, contains('ends 20 Dec 2026'));
    expect(m, endsWith('Open it or delete it first.'));
    expect(limitMessageFor(_t('active', phases: 3, metric: 'books')), startsWith('You already have a book reading target ('));
  });

  testWidgets('the Targets screen shows a DRAFT: "Draft — waiting for AI plan", the real reason, the automatic retry, a Retry button and Delete', (tester) async {
    await _open(tester, [_t('draft', reason: 'The AI service has no credit left (OpenAI billing). Add credit and the plan is generated automatically.'), _t('active', phases: 4, metric: 'books')]);
    expect(find.byKey(const ValueKey('draft-title')), findsOneWidget);
    expect(find.text('Draft — waiting for AI plan'), findsOneWidget);
    expect(find.textContaining('no credit left (OpenAI billing)'), findsOneWidget);
    expect(find.textContaining('generated automatically as soon as the AI is available again'), findsOneWidget);
    expect(find.text('Retry plan generation'), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-target')), findsNWidgets(2), reason: 'every target can be deleted, a draft too');
    expect(find.text('Phase 1 of 4'), findsOneWidget, reason: 'the active one is unchanged');
  });

  testWidgets('every target that counts toward the limit is shown (an active one with no plan too, with its retry)', (tester) async {
    await _open(tester, [_t('active')]);
    expect(find.text("No plan yet — generation didn't complete"), findsOneWidget);
    expect(find.text('Retry plan generation'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _open(tester, [_t('completed', phases: 3), _t('abandoned', phases: 3)]);
    await tester.pumpAndSettle();
    expect(find.textContaining('No active targets yet'), findsOneWidget, reason: 'history (completed, abandoned) is not listed as a target in the way');
  });

  for (final dark in [false, true]) {
    for (final scale in kScales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale on 360 dp: the draft card fits', (tester) async {
        await _open(tester, [_t('draft', reason: 'The AI service has no credit left (OpenAI billing). Add credit and the plan is generated automatically.')], scale: scale, dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.text('Retry plan generation'), findsOneWidget);
      });
    }
  }
}

/// A Firestore timestamp for a plain date (kept out of the test body).
class Timestamp20 {
  static Object at(int y, int m, int d) => Timestamp.fromDate(DateTime(y, m, d));
}
