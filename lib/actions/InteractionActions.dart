import 'package:cloud_firestore/cloud_firestore.dart';

import '../Services/GeminiService.dart';
import '../Services/HierarchyApi.dart';
import '../utils/GuideDb.dart';

/// Interactions — a guide's notes about a conversation with a student — as one
/// shared write, with no screen in it. `InteractionLoggerPage` and the AI agent
/// both call [saveInteraction], so a note the agent saves is the same record,
/// with the same notification and the same AI extraction, as one typed by hand.

/// How the guide connected, in the order the screen offers them.
const List<String> kInteractionTypes = ['WhatsApp', 'Call', 'Live (in-person)'];

/// What [saveInteraction] managed.
class SavedInteraction {
  const SavedInteraction({
    required this.id,
    this.extractionError,
    this.litPrefill = '',
  });

  /// The new `interactionLogs` document. It stands complete even if everything
  /// after the first write failed.
  final String id;

  /// Why the AI could not fill in the details, or null if it did. The note is
  /// saved either way; this only decides which message the guide sees.
  final String? extractionError;

  /// What the AI noticed that might be worth a LIT reading, to pre-fill it.
  final String litPrefill;
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

/// Persists the complete record BEFORE calling the AI, so an API failure can
/// never lose what the guide wrote, and so the interaction is already fully
/// saved — no draft, no approval — the instant the first write succeeds.
///
/// Then tells whoever should know, then asks the AI to fill in the details.
/// Only the first write can throw; once it has landed, nothing after it can lose
/// the note.
///
/// [extract] is the AI call, swappable in tests; the app never sets it.
Future<SavedInteraction> saveInteraction({
  required String guideId,
  required String studentUid,
  required String studentName,
  required String raw,
  required String interactionType,
  required DateTime interactionDate,
  DateTime? followUpDate,
  Future<Map<String, dynamic>> Function(String rawText, String studentName)? extract,
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
    'createdAt': FieldValue.serverTimestamp(),
    'approvedAt': FieldValue.serverTimestamp(),
  });

  // The record is durably saved and already complete — every downstream reader
  // (the list, HolisticSuggestion, WeeklyPlanning) can use it from this point on
  // even if everything below fails. Notified now, not after extraction, so this
  // is at least as reliable as the old approve-gated notification, never less.
  await notifyInteractionLogged(studentUid);

  String? extractionError;
  var litPrefill = '';
  try {
    final draft = await (extract ??
        (r, n) => GeminiService().extractInteraction(rawText: r, studentName: n))(
      raw,
      studentName,
    );
    // The guide's own selections are authoritative — the AI's guesses for these
    // keys are discarded, never used to silently override what the guide picked.
    draft['interactionType'] = interactionType;
    draft['interactionDateTime'] = interactionDate.toIso8601String();
    if (followUpDate != null) {
      draft['followUpDate'] = followUpDate.toIso8601String();
    }
    litPrefill = (draft['possibleLitEvidence'] ?? '').toString();

    await docRef.update({
      'approvedSummary': interactionDraftForFirestore(draft),
      'rawDictation': FieldValue.delete(),
    });
  } on GeminiException catch (e) {
    extractionError = e.message;
  } catch (e) {
    extractionError = 'Extraction failed: $e';
  }
  // On failure, the doc saved above already stands as the complete record;
  // rawDictation is left in place (not deleted) so the guide can retry from the
  // entry's Edit screen via Re-extract.

  return SavedInteraction(
    id: docRef.id,
    extractionError: extractionError,
    litPrefill: litPrefill,
  );
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

/// Runs the AI over an interaction's original dictation again and saves the result.
///
/// The guide's own choices (how they connected, when, the follow-up date) stay
/// authoritative over the AI's guesses, exactly as in the first save. Throws
/// [GeminiException] with a message the guide can read if the AI cannot; the
/// original dictation is only deleted once the new details are saved.
///
/// @return the details that were saved
Future<Map<String, dynamic>> reExtractInteraction(
  String docId, {
  required String rawDictation,
  required String studentName,
  String? interactionType,
  DateTime? interactionDateTime,
  DateTime? followUpDate,
  Future<Map<String, dynamic>> Function(String rawText, String studentName)? extract,
}) async {
  final draft = await (extract ??
      (r, n) => GeminiService().extractInteraction(rawText: r, studentName: n))(
    rawDictation,
    studentName,
  );
  draft['interactionType'] = interactionType ?? draft['interactionType'];
  draft['interactionDateTime'] =
      interactionDateTime?.toIso8601String() ?? draft['interactionDateTime'];
  if (followUpDate != null) {
    draft['followUpDate'] = followUpDate.toIso8601String();
  }

  final forFirestore = interactionDraftForFirestore(draft);
  await GuideDb.instance.collection('interactionLogs').doc(docId).update({
    'approvedSummary': forFirestore,
    'rawDictation': FieldValue.delete(),
  });
  return forFirestore;
}
