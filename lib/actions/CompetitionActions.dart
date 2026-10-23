import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../Services/HierarchyApi.dart';
import '../utils/AdminProfile.dart';
import '../utils/ChallengeRange.dart';
import '../utils/GuideDb.dart';
import '../utils/StudentScope.dart';

/// Chanting competitions, as shared writes with no screen in them: the Chanting
/// screen and the AI agent both create, close and delete through these.

/// What creating a competition came to.
class CreatedChallenge {
  const CreatedChallenge({
    required this.id,
    this.sent = 0,
    this.total = 0,
    this.notifyFailed = false,
  });

  final String id;

  /// Students the push reached, and the students it was meant for (those who have
  /// not muted competitions).
  final int sent;
  final int total;

  /// The competition IS saved; only telling the students failed.
  final bool notifyFailed;
}

/// Starts a competition over [start]..[end] (the same date twice is a single day)
/// and tells the students on the chosen rosters.
///
/// Who takes part: a HOD picks guides' rosters ([selectedGuideIds]; empty means
/// every student); a Guide's own roster and his Male Enablers'; anyone else their
/// own. The signed-in admin is [AdminProfileProvider.require].
///
/// The document is the one the screen always wrote: `targetDateKey`/`targetDate`
/// stay and now mean the LAST day, so the expiry sweep, the result window and any
/// Student app build older than ranges keep working untouched.
Future<CreatedChallenge> createChantingChallenge({
  required String name,
  required int targetRounds,
  required DateTime start,
  required DateTime end,
  Set<String> selectedGuideIds = const {},
}) async {
  final problem = challengeSpanProblem(start, end);
  if (problem != null) throw ArgumentError(problem);
  if (name.trim().isEmpty) throw ArgumentError('Give the challenge a name');
  if (targetRounds <= 0) throw ArgumentError('Target rounds must be a whole number');

  final profile = AdminProfileProvider.require();
  final guide = profile.id;
  final first = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);

  final ref = await GuideDb.instance.collection('chantingChallenges').add({
    'name': name.trim(),
    'targetRounds': targetRounds,
    'startDateKey': challengeDayKey(first),
    'startDate': Timestamp.fromDate(first),
    'endDateKey': challengeDayKey(last),
    'endDate': Timestamp.fromDate(last),
    'targetDateKey': challengeDayKey(last),
    'targetDate': Timestamp.fromDate(last),
    'guideId': guide,
    'createdBy': guide,
    'createdAt': FieldValue.serverTimestamp(),
    'status': 'active',
    // Seeded explicitly so the trigger's transaction always has a number to add to.
    'currentTotal': 0,
    // A report counts toward a challenge when the student's guideId is in
    // `guideIds` (functions/challenges.js), so a Guide's Male Enablers must be
    // listed next to him. A HOD keeps his picked guides / all.
    'guideIds': profile.isHod
        ? selectedGuideIds.toList()
        : profile.isGuide
            ? [guide, ...profile.myMaleEnablers.map((a) => a.id)]
            : [guide],
    if (profile.isHod && selectedGuideIds.isEmpty) 'allStudents': true,
  });

  // The challenge itself is saved; only the push can fail from here.
  try {
    final r = await HierarchyApi.instance.sendStudentNotification({
      'kind': 'chanting_challenge',
      'name': name.trim(),
      'targetRounds': targetRounds,
      'startDate': DateFormat('yyyy-MM-dd').format(first),
      'targetDate': DateFormat('yyyy-MM-dd').format(last),
      if (profile.isHod) 'ownerIds': selectedGuideIds.toList(),
    });
    return CreatedChallenge(
      id: ref.id,
      sent: (r['sent'] as num?)?.toInt() ?? 0,
      total: (r['total'] as num?)?.toInt() ?? 0,
    );
  } catch (_) {
    return CreatedChallenge(id: ref.id, notifyFailed: true);
  }
}

/// Closes an active competition early ('missed'), or reopens one ('active').
///
/// `achieved` is final: a target that was reached cannot be un-reached, so there is
/// no action for it. Reopening clears `closedAt` so the record does not claim two
/// contradictory things at once.
Future<void> setChallengeStatus(String challengeId, String status) async {
  if (status != 'active' && status != 'missed') {
    throw ArgumentError('A competition can be closed or reopened, nothing else.');
  }
  await GuideDb.instance.collection('chantingChallenges').doc(challengeId).update({
    'status': status,
    'closedAt':
        status == 'missed' ? FieldValue.serverTimestamp() : FieldValue.delete(),
  });
}

/// Permanently deletes a competition: the document itself (which carries
/// `summarySeenBy` as one of its own fields) AND every contribution to it — a
/// top-level collection, not a subcollection, so it needs its own query. Bounded by
/// one roster in practice, nowhere near the 500-write batch limit.
Future<void> deleteChantingChallenge(String challengeId) async {
  final contributions = await StudentScope.current().historyGet(
    'chantingChallengeContributions',
    extraEquals: {'challengeId': challengeId},
  );
  final batch = GuideDb.instance.batch();
  for (final doc in contributions.docs) {
    batch.delete(doc.reference);
  }
  batch.delete(GuideDb.instance.collection('chantingChallenges').doc(challengeId));
  await batch.commit();
}
