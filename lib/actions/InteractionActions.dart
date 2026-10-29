import 'package:cloud_firestore/cloud_firestore.dart';

import '../Services/GuideAi.dart';
import '../Services/HierarchyApi.dart';
import '../utils/GuideDb.dart';

/// Interactions — a guide's notes about a conversation with a student — as one
/// shared write, with no screen in it. `InteractionLoggerPage` and the AI agent
/// both call [saveInteraction], so a note the agent saves is the same record,
/// with the same notification and the same background analysis, as one typed by hand.

/// How the guide connected, in the order the screen offers them.
const List<String> kInteractionTypes = ['WhatsApp', 'Call', 'Live (in-person)'];

/// What [saveInteraction] managed.
class SavedInteraction {
  const SavedInteraction({required this.id});

  /// The new `interactionLogs` document. It stands complete: the AI analysis that
  /// follows happens on the server, afterwards, and nothing in it can lose the note.
  final String id;
}

/// Converts the in-memory summary (ISO date strings) into the Firestore shape
/// (Timestamps), keeping every other key as-is.
Map<String, dynamic> interactionDraftForFirestore(Map<String, dynamic> draft) {
  final out = Map<String, dynamic>.from(draft);
  out['interactionDateTime'] = tsFromIso(draft['interactionDateTime']);
  out['followUpDate'] = tsFromIso(draft['followUpDate']);
  return out;
}

Timestamp? tsFromIso(Object? value) {
  if (value is Timestamp) return value;
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  return parsed == null ? null : Timestamp.fromDate(parsed);
}

/// Tells the other admins who should know that an interaction was logged —
/// **the fact only**.
///
/// No interaction content, no themes, no LIT evidence, no student concerns go
/// into the payload. FCM notifications land outside the app on a lock screen, so
/// they get the same privacy boundary the raw notes already have. The server
/// decides who is told (and builds the message).
Future<void> notifyInteractionLogged(String studentUid) async {
  try {
    await HierarchyApi.instance.sendStudentNotification({
      'kind': 'interaction_logged',
      'studentUid': studentUid,
    });
  } catch (_) {
    // A failed notification must never undo a save that already landed.
  }
}

/// Saves the interaction — one write, nothing else for the guide to do.
///
/// The record is complete and live the moment the write lands: the guide's own choices
/// (how they connected, when, the follow-up date) are already in `approvedSummary`, so
/// every reader (the list, suggestions, weekly planning) can use it at once. The note itself
/// goes in `rawDictation` with `analysis: 'queued'`; the SERVER then analyses it in the
/// background (themes, concerns, commitments, a suggested next step...), silently fills in
/// `approvedSummary`, drops the notes, and makes new suggestions for the student — telling
/// the student's guide when they are ready. Nothing of that is shown or asked here, and a
/// failure of any of it can never lose what was written.
///
/// Only the first write can throw. Whoever should know that an interaction was logged is
/// told after it (the fact only).
///
/// When the guide REPORTED BACK on a planned interaction (through the assistant, the only way an interaction is recorded now), the same
/// document also carries what he answered per topic ([topicAnswers]: topic key, questions asked, answer, conclusion), the guide's reading
/// of his [willingness] (very_willing | willing | neutral | hesitant | unwilling) and whether it covered what was planned ([addressed]).
/// The server saves all of it in his history, ticks the plan item, takes the reasons off Interactions needed and adjusts his Surrender %.
Future<SavedInteraction> saveInteraction({
  required String guideId,
  required String studentUid,
  required String studentName,
  required String raw,
  String interactionType = '',
  required DateTime interactionDate,
  DateTime? followUpDate,
  List<Map<String, dynamic>> topicAnswers = const [],
  String? willingness,
  bool addressed = true,
}) async {
  final initialSummary = {
    'interactionType': interactionType,
    'interactionDateTime': Timestamp.fromDate(interactionDate),
    'durationMinutes': 0,
    'themes': <String>[],
    'studentConcerns': '',
    'personalRevelation': '',
    'commitmentsMade': '',
    'followUpDate':
        followUpDate == null ? null : Timestamp.fromDate(followUpDate),
    'abcdeEvidence': '',
    'possibleLitEvidence': '',
    'temporaryCircumstances': '',
    'recommendedNextAction': '',
    'recommendedReasoning': '',
    'extractionConfidence': 'low',
  };

  final docRef = await GuideDb.instance.collection('interactionLogs').add({
    'studentUid': studentUid,
    'studentName': studentName,
    'guideId': guideId,
    'interactionDate': Timestamp.fromDate(interactionDate),
    'rawDictation': raw,
    'approvedSummary': initialSummary,
    'extractedDraft': null,
    'status': 'approved',
    if (topicAnswers.isNotEmpty) 'topicAnswers': topicAnswers,
    if (willingness != null && willingness.isNotEmpty) 'willingness': willingness,
    'addressed': addressed,
    // the server's background analysis picks it up from here
    'analysis': 'queued',
    'createdAt': FieldValue.serverTimestamp(),
    'approvedAt': FieldValue.serverTimestamp(),
  });

  await notifyInteractionLogged(studentUid);
  return SavedInteraction(id: docRef.id);
}

/// Saves what a guide changed on an interaction's detail screen: the whole
/// summary (as the screen holds it, dates as ISO strings) and the interaction
/// date. A null date removes the field, as the screen always did.
Future<void> saveInteractionEdits(
  String docId, {
  required Map<String, dynamic> summary,
  required DateTime? interactionDate,
}) async {
  await GuideDb.instance.collection('interactionLogs').doc(docId).update({
    'approvedSummary': interactionDraftForFirestore(summary),
    'status': 'approved',
    'interactionDate': interactionDate == null
        ? FieldValue.delete()
        : Timestamp.fromDate(interactionDate),
  });
}

/// Changes only the named fields of an interaction's summary, keeping the rest.
///
/// What the AI agent uses to edit an interaction without having to hold the whole
/// summary: it reads the document, lays [changes] over its `approvedSummary`, and
/// saves the result through [saveInteractionEdits] — the very write the detail
/// screen makes. Date fields in [changes] may be ISO strings.
///
/// @return the merged summary that was saved
Future<Map<String, dynamic>> editInteractionFields(
  String docId, {
  required Map<String, dynamic> changes,
  DateTime? interactionDate,
}) async {
  final ref = GuideDb.instance.collection('interactionLogs').doc(docId);
  final snap = await ref.get();
  final data = snap.data();
  if (data == null) throw StateError('That interaction no longer exists.');

  final current = Map<String, dynamic>.from(
      (data['approvedSummary'] as Map?)?.cast<String, dynamic>() ?? const {});
  // The screen holds dates as ISO strings; do the same so one code path handles both.
  for (final k in const ['interactionDateTime', 'followUpDate']) {
    final v = current[k];
    if (v is Timestamp) current[k] = v.toDate().toIso8601String();
  }
  final merged = {...current, ...changes};

  final existingDate = data['interactionDate'];
  final when = interactionDate ??
      (existingDate is Timestamp ? existingDate.toDate() : null);
  await saveInteractionEdits(docId, summary: merged, interactionDate: when);
  return merged;
}

/// Runs the AI analysis again over an interaction whose original notes are still stored.
///
/// The SERVER does it and saves the result — the guide's own choices (how they connected,
/// when, the follow-up date) stay authoritative over the AI's guesses, exactly as in the first
/// analysis — and the original notes are only dropped once the new details are saved. Throws
/// [AiException] with a message the guide can read if the AI cannot. The caller reloads the
/// record to see the result.
Future<void> reExtractInteraction(String docId, {GuideAi? ai}) =>
    (ai ?? GuideAi()).reanalyse(docId);

/// Removes the FOLLOW-UP from an interaction: its follow-up date, so it leaves the "Follow-ups" lists and the dots. The
/// interaction itself, its notes and its suggested next action stay. The one write the "Remove follow-up" button and the
/// AI assistant share; the rules allow it for an interaction of a student in the admin's scope.
Future<void> removeInteractionFollowUp(String docId) async {
  await GuideDb.instance
      .collection('interactionLogs')
      .doc(docId)
      .update({'approvedSummary.followUpDate': FieldValue.delete()});
}
