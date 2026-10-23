import 'package:flutter/material.dart';

import '../main.dart';
import '../Home/Calendar.dart';
import '../Pages/AssociationManager.dart';
import '../Pages/ExpeditionManager.dart';
import '../Pages/FlaggedMessages.dart';
import '../Pages/PriorityStudents.dart';
import '../Pages/StudentDoubtsPage.dart';
import '../Pages/StudentProfilePage.dart';
import '../Pages/CompoundGoalRoadmapPage.dart';
import '../Pages/SubmissionStatus.dart';
import '../Pages/GuideCalendarPage.dart';
import 'AdminProfile.dart';

/// Notification deep-linking — Master Task, 2026-09-10, Part 3.
///
/// The ONE place a notification's `data` payload turns into a real
/// navigation action, mirroring the Student app's own
/// `utils/NotificationRouter.dart` — same `dest` scheme, same
/// fail-safe-by-construction shape, reusing every destination screen's own
/// already-established constructor rather than a new parallel navigation
/// path (Part 3 item 5).
///
/// ⚠️ **Reuses `guideNavigatorKey` from `main.dart`** — this app has only
/// one `MaterialApp`/Navigator (unlike the Student app's nested pair), so
/// there is no ambiguity about which Navigator a deep link targets.
/// `currentState` is null before that `MaterialApp` has first built (a
/// notification tap arriving mid-launch) — routing bails out silently
/// rather than crashing or queuing an action against nothing.
///
/// ⚠️ **Fails safe by construction**: an unrecognised/missing `dest`, a
/// malformed payload, or any error while resolving a destination is caught
/// by the one try/catch wrapping the whole dispatch — the user is left on
/// whatever screen the app already opened to, never a broken page.
///
/// ⚠️ **Splash-race fix (Master Task, 2026-09-10 — Part 2).** This app's
/// SINGLE `MaterialApp`/`Navigator` (`guideNavigatorKey`) exists from the
/// very first frame — `SplashScreen` (`main.dart`) IS that `MaterialApp`'s
/// own `home:` — so, unlike the Student app, a notification's route was
/// never blocked by a missing Navigator. The real bug here was the
/// OPPOSITE ordering problem: `SplashScreen`'s own fixed
/// `Future.delayed(Duration(seconds: 4))` then calls
/// `Navigator.pushReplacement(...)` unconditionally — and since a
/// notification's route pushes successfully and immediately (right onto
/// this same, already-existing Navigator), BY THE TIME that 4-second timer
/// fires, the notification's destination page IS the current top route,
/// and `pushReplacement` evicts it in favour of `CurvedNavBar`/
/// `FolkGuideSelectionPage` — the user is navigated to the right page,
/// then thrown off it a few seconds later. Confirmed by reading the exact
/// timer and by `pushReplacement`'s own documented behaviour (replaces
/// whatever the calling Navigator's current top route is, not
/// specifically the route `SplashScreen` itself started as), not assumed.
///
/// Fixed with the same [_appReady]/[_pendingRoute] shape as the Student
/// app's router, but [markAppReady] is called from a different moment —
/// see that function's own doc comment for why.
bool _appReady = false;
Map<String, dynamic>? _pendingRoute;

/// Called exactly once, from `SplashScreen`'s own `Future.delayed`
/// callback in `main.dart`, immediately AFTER its `Navigator.
/// pushReplacement(...)` — the moment splash's own, one-time navigation
/// action has already happened and nothing further will ever come from
/// it to race against. A route queued while [_appReady] was still false
/// is applied right here, landing on top of whatever `pushReplacement`
/// just navigated to, instead of being evicted by it.
///
/// Distinguishes the three launch states (Part 2 item 2): a cold start
/// begins with [_appReady] false for up to that fixed splash duration, so
/// [routeNotification] queues; a background/foreground tap happens long
/// after this already ran once for the process, so it dispatches
/// immediately, exactly as if no splash existed — because for that launch
/// state, none is in the way. `SplashScreen` itself is only ever built
/// once per process (every later "go to the signed-in shell" transition
/// replaces routes via `pushAndRemoveUntil`, never rebuilds `SplashScreen`),
/// so this cannot fire twice or [_appReady] revert to false within one
/// running process.
///
/// Consumed exactly once (Part 2 item 4): [_pendingRoute] is read and
/// cleared to null in the same breath it is dispatched.
void markAppReady() {
  _appReady = true;
  final pending = _pendingRoute;
  _pendingRoute = null;
  if (pending != null) _dispatch(pending);
}

void routeNotification(Map<String, dynamic>? data) {
  // Routing diagnostics (matching the Student app's own, Part 1 item 2) —
  // real, on-device evidence for the payload/handler/router/navigator
  // checkpoints if this ever needs re-diagnosing.
  print('[notif-route] routeNotification called, data=$data, '
      'appReady=$_appReady');

  if (data == null || data.isEmpty) return;

  if (!_appReady) {
    // Cold start, still within the splash window — queue rather than let
    // splash's own upcoming `pushReplacement` evict it a moment later.
    // Overwrites any earlier still-pending value deliberately: there is
    // only ever one genuine "this is what launched the app" candidate.
    _pendingRoute = data;
    return;
  }

  _dispatch(data);
}

void _dispatch(Map<String, dynamic> data) {
  final dest = (data['dest'] ?? '').toString();
  if (dest.isEmpty) return;

  final navState = guideNavigatorKey.currentState;
  if (navState == null) return;

  String str(String key) => (data[key] ?? '').toString();

  try {
    switch (dest) {
      case 'guide_student_reports':
        final studentUid = str('studentUid');
        final studentName = str('studentName');
        if (studentName.isEmpty) return;
        navState.push(MaterialPageRoute(
          builder: (_) => CalendarPage(
            username: studentName,
            role: str('role'),
            studentUid: studentUid.isEmpty ? null : studentUid,
          ),
        ));
        break;

      case 'guide_calendar':
        final guideId = str('guideId');
        if (guideId.isEmpty) return;
        navState.push(MaterialPageRoute(
          builder: (_) => GuideCalendarPage(selectedGuide: guideId),
        ));
        break;

      case 'guide_association':
        final id = str('highlightAssociationId');
        navState.push(MaterialPageRoute(
          builder: (_) => AssociationManagerPage(
            highlightAssociationId: id.isEmpty ? null : id,
          ),
        ));
        break;

      case 'guide_expedition':
        // `ExpeditionManagerPage` has no highlight-one-trip parameter
        // today (unlike `AssociationManagerPage`) — see
        // `functions/reminders.js`'s own note on `upcomingTripReminder`.
        // Opens the plain list; a real improvement over the home screen,
        // just not pinpointed to one trip.
        navState.push(MaterialPageRoute(
          builder: (_) => const ExpeditionManagerPage(),
        ));
        break;

      case 'guide_goal_target':
        final guideId = str('guideId');
        final targetId = str('targetId');
        if (guideId.isEmpty || targetId.isEmpty) return;
        // This notification is sent TO the owning admin about their OWN
        // target (`onCompoundProposalWritten` in `functions/goals.js`
        // notifies `event.params.guideId`) — the review (HOD) view is only
        // for a HOD opening someone else's target, decided by role, never
        // by a special id.
        final me = AdminProfileProvider.current;
        final reviewing = me != null && me.isHod && me.id != guideId;
        navState.push(MaterialPageRoute(
          builder: (_) => CompoundGoalRoadmapPage(
            guideId: guideId,
            targetId: targetId,
            isHod: reviewing,
            hodUid: reviewing ? me.id : null,
          ),
        ));
        break;

      case 'guide_flagged_transcript':
        final studentUid = str('studentUid');
        final studentName = str('studentName');
        final messageId = str('messageId');
        if (studentUid.isEmpty || studentName.isEmpty) return;
        navState.push(MaterialPageRoute(
          builder: (_) => StudentChatTranscriptPage(
            studentUid: studentUid,
            studentName: studentName,
            messageId: messageId,
          ),
        ));
        break;

      case 'guide_doubts':
        // A student sent a doubt: the list, opening that doubt when the payload names it.
        final doubtId = str('doubtId');
        navState.push(MaterialPageRoute(
          builder: (_) => StudentDoubtsPage(openDoubtId: doubtId.isEmpty ? null : doubtId),
        ));
        break;

      case 'guide_suggestions':
        // New suggestions are ready for a student: that student's profile, at the suggestions.
        final studentUid = str('studentUid');
        if (studentUid.isEmpty) return;
        navState.push(MaterialPageRoute(
          builder: (_) => StudentProfilePage(studentUid: studentUid, focusSuggestions: true),
        ));
        break;

      case 'guide_priority':
        // The nightly check found a NEW reason a student needs attention.
        // The list itself is the right place to land: the card there shows
        // EVERY reason that is currently true, not only the one that fired.
        navState.push(MaterialPageRoute(
          builder: (_) => const PriorityStudentsPage(),
        ));
        break;

      case 'guide_submission_status':
        navState.push(MaterialPageRoute(
          builder: (_) => const SubmissionStatusPage(),
        ));
        break;

      case 'guide_home':
        // Several students/records aggregated into one digest — no
        // single screen is more relevant than wherever the app already
        // opens to. Pops back to that root rather than pushing a new,
        // duplicate copy of the app's own shell.
        navState.popUntil((route) => route.isFirst);
        break;

      // Any `dest` this app does not recognise (a value only the Student
      // app's router knows about, a future value this build predates, or
      // a genuinely malformed payload) — Part 3 item 4's "unknown
      // destination" case. No-op, same as an empty `dest` above.
      default:
        break;
    }
  } catch (_) {
    // See this file's own header — any failure here fails safe.
  }
}
