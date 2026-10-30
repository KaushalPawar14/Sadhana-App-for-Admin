import 'package:cloud_functions/cloud_functions.dart';

import '../utils/AdminProfile.dart';

/// A failed hierarchy callable, with the server's own message (already worded
/// for people: "Only the HOD can remove an admin.").
class HierarchyException implements Exception {
  HierarchyException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

typedef CallableInvoker = Future<Map<String, dynamic>> Function(
    String name, Map<String, dynamic> data);

/// Thin wrappers over the Cloud Functions added in the hierarchy backend
/// (functions/hierarchy.js, guideSends.js). Every authority check happens on the
/// server; the app only builds the request and shows the answer.
///
/// Region asia-south1, like every other function this app calls.
class HierarchyApi {
  HierarchyApi(this._invoke);

  /// The real thing.
  static HierarchyApi instance = HierarchyApi(_defaultInvoke);

  /// Swaps the transport in tests.
  static void useForTests(CallableInvoker? invoker) =>
      instance = HierarchyApi(invoker ?? _defaultInvoke);

  final CallableInvoker _invoke;

  static Future<Map<String, dynamic>> _defaultInvoke(
      String name, Map<String, dynamic> data) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable(name)
          .call<dynamic>(data);
      final raw = result.data;
      return raw is Map ? _deepMap(raw) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw HierarchyException(e.code, e.message ?? 'Something went wrong.');
    }
  }

  static Map<String, dynamic> _deepMap(Map raw) => {
        for (final e in raw.entries) e.key.toString(): _deep(e.value),
      };

  static dynamic _deep(dynamic v) {
    if (v is Map) return _deepMap(v);
    if (v is List) return v.map(_deep).toList();
    return v;
  }

  Future<Map<String, dynamic>> _call(String name,
      [Map<String, dynamic> data = const {}]) async {
    try {
      return await _invoke(name, data);
    } on HierarchyException {
      rethrow;
    } on FirebaseFunctionsException catch (e) {
      throw HierarchyException(e.code, e.message ?? 'Something went wrong.');
    }
  }

  /// A server function by name (the assistant's Undo of a change the server made).
  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> data = const {}]) => _call(name, data);

  /// The signed-in admin's profile, or null when the account is not a
  /// registered admin (or nobody is signed in).
  Future<AdminProfile?> getAdminProfile() async {
    try {
      return AdminProfile.fromMap(await _call('getAdminProfile'));
    } on HierarchyException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        return null;
      }
      rethrow;
    }
  }

  Future<List<AdminSummary>> listAdmins() async {
    final r = await _call('listAdmins');
    return [
      for (final a in (r['admins'] as List? ?? const []))
        if (a is Map) AdminSummary.fromMap(Map<String, dynamic>.from(a)),
    ];
  }

  /// `name` becomes the permanent admin id; `displayName` is the human name the
  /// Student app shows. `teamGuide` only matters when a HOD adds a Male Enabler.
  Future<AdminSummary> addAdmin({
    required String name,
    required String email,
    required AdminRole role,
    String? displayName,
    String? teamGuide,
  }) async {
    final r = await _call('addAdmin', {
      'name': name,
      'email': email,
      'role': role.wire,
      if (displayName != null && displayName.trim().isNotEmpty)
        'displayName': displayName.trim(),
      if (teamGuide != null) 'teamGuide': teamGuide,
    });
    return AdminSummary.fromMap({...Map<String, dynamic>.from(r['admin'] as Map), 'boardColumn': r['boardColumn']});
  }

  Future<AdminSummary> updateAdmin({
    required String id,
    String? email,
    String? displayName,
    AdminRole? role,
    String? teamGuide,
  }) async {
    final r = await _call('updateAdmin', {
      'id': id,
      if (email != null) 'email': email,
      if (displayName != null) 'displayName': displayName,
      if (role != null) 'role': role.wire,
      if (teamGuide != null) 'teamGuide': teamGuide,
    });
    return AdminSummary.fromMap({...Map<String, dynamic>.from(r['admin'] as Map), 'boardColumn': r['boardColumn']});
  }

  /// With [dryRun] nothing changes; the result says how many students would
  /// become Unassigned ("Are you sure? N students will become Unassigned").
  Future<RemoveAdminResult> removeAdmin(String id,
      {bool dryRun = false}) async {
    final r = await _call('removeAdmin', {'id': id, 'dryRun': dryRun});
    return RemoveAdminResult(
      studentCount: (r['studentCount'] as num?)?.toInt() ?? 0,
      teamlessEnablers:
          [for (final x in (r['teamlessEnablers'] as List? ?? const [])) '$x'],
      removed: r['removed'] == true,
      boardColumn: r['boardColumn']?.toString(),
      cardsMoved: (r['cardsMoved'] as num?)?.toInt() ?? 0,
    );
  }

  /// The guide corrected an item of their Today / This week plan in chat: [mode] `remove`, `call` (a call instead) or `other_day`
  /// (with [newDate], `yyyy-MM-dd`). The server stores it, remembers [constraint] / [noteText] about the student, and regenerates the
  /// plan at once. Returns the sentence to show.
  Future<String> planCorrection({
    required String itemId,
    required String mode,
    String? newDate,
    String reason = '',
    String? constraint,
    String? noteText,
  }) async {
    final r = await _call('planCorrection', {
      'itemId': itemId,
      'mode': mode,
      if (newDate != null) 'newDate': newDate,
      'reason': reason,
      if (constraint != null) 'constraint': constraint,
      if (noteText != null) 'noteText': noteText,
    });
    return (r['message'] ?? 'Done.').toString();
  }

  /// What the guide told the assistant about a student: a note ([kind] `note`, with [text]), or whether he could ever come to FOLK
  /// (`not_folk` / `folk_open`). The server remembers it for the plans, adds a line to his history, and regenerates the plan at once.
  Future<String> studentGuideNote({required String studentUid, required String kind, String? text}) async {
    final r = await _call('studentGuideNote', {'studentUid': studentUid, 'kind': kind, if (text != null && text.trim().isNotEmpty) 'text': text});
    return (r['message'] ?? 'Done.').toString();
  }

  Future<void> setTeamGuide(String id, String teamGuide) =>
      _call('setTeamGuide', {'id': id, 'teamGuide': teamGuide});

  /// Assign / move / release a student ([toGuideId] '' = release to
  /// Unassigned). The optional board fields also move the card on the Guide
  /// Assignment board, as the old client-side `reassignGuide` did.
  Future<void> assignStudent({
    required String studentId,
    required String toGuideId,
    String? boardId,
    String? columnId,
    int? order,
  }) =>
      _call('assignStudent', {
        'studentId': studentId,
        'toGuideId': toGuideId,
        if (boardId != null) 'boardId': boardId,
        if (columnId != null) 'columnId': columnId,
        if (order != null) 'order': order,
      });

  Future<void> saveNotificationPrefs({
    required Map<String, bool> groups,
    required Map<String, bool> types,
  }) =>
      _call('saveNotificationPrefs', {'groups': groups, 'types': types});

  /// The guide's number of students in a day's batch (1 to 12); the server works the plan out again at once.
  /// Returns the number it was before (the server says), so a change can be undone.
  Future<int> savePlanSettings({required int dailyBatch}) async {
    final r = await _call('savePlanSettings', {'dailyBatch': dailyBatch});
    return r['previous'] is num ? (r['previous'] as num).round() : 4;
  }

  /// The Refresh button at the top of the Plan page: the AI writes the questions again and the plan is worked out afresh. A guide refreshes only
  /// his own plan; a HOD may refresh every guide's ([all]). Once per 2 minutes: then `ok` is false and `retryInSec` says how long is left.
  /// While the month's AI budget is used up the server refuses with its own clear sentence (a [HierarchyException]).
  Future<({bool ok, int retryInSec})> refreshPlan({bool all = false}) async {
    final r = await _call('refreshPlan', {if (all) 'all': true});
    return (ok: r['ok'] != false, retryInSec: r['retryInSec'] is num ? (r['retryInSec'] as num).round() : 0);
  }

  /// The admin opened the app: the FIRST call of the day makes the server write the AI questions for Today's students (his batch, and whoever joined it);
  /// every other call that day, and a day he never opens the app, costs nothing. Never throws: the plan simply stays as it is.
  Future<void> openPlan() async {
    try {
      await _call('refreshPlan', {'open': true});
    } catch (_) {
      // nothing to tell the guide: the plan is still there, with the plain questions
    }
  }

  /// The monthly budget (₹) of the guides' AI (HOD only; the server checks).
  Future<void> setAiBudget({required double monthlyInr}) => _call('setAiBudget', {'monthlyInr': monthlyInr});

  /// Resumes the guides' AI for the rest of this month after the budget was used up (HOD only; the server checks).
  Future<void> resumeAiForMonth() => _call('resumeAiForMonth');

  /// A top-up of the OpenAI account: the [date] (`yyyy-MM-dd`), the amount in US$ and in ₹ ([inr] left out: worked out from the rate). HOD only.
  Future<void> addAiTopup({required String date, required double usd, double? inr}) => _call('addAiTopup', {'date': date, 'usd': usd, if (inr != null) 'inr': inr});

  /// Removes a top-up entered by mistake (HOD only).
  Future<void> deleteAiTopup(String id) => _call('deleteAiTopup', {'id': id});

  /// The estimated remaining credit = the top-ups minus everything the AI has cost since the first one (guides and students), with the days left at
  /// the current rate (HOD only; the server works it out).
  Future<Map<String, dynamic>> aiCreditView() => _call('aiCreditView');

  /// Is this mobile number already on any user document? (Replaces the app's
  /// own `users where mobileNumber ==` query, which strict rules forbid.)
  /// `name` is the existing student's name when taken.
  Future<({bool taken, String name})> checkMobileTaken(String mobile) async {
    final r = await _call('checkMobileTaken', {'mobile': mobile});
    return (taken: r['taken'] == true, name: (r['name'] ?? '').toString());
  }

  /// New suggestions for a student, made now by the server (OpenAI) and stored for the profile to read.
  /// Returns how many; throws [HierarchyException] with a message that is safe to show the guide.

  /// Runs the AI analysis again over an interaction whose original notes are still stored; the
  /// server saves the result.
  Future<void> analyseInteraction(String interactionId) =>
      _call('analyseInteraction', {'logId': interactionId});

  /// Deletes a trip and every registration for it (the trip's creator, or a HOD; the server checks).
  /// Used for an active trip and for a History card alike. Nothing else is touched.
  Future<({bool deleted, int registrationsDeleted})> deleteExpedition(String tripId) async {
    final r = await _call('deleteExpedition', {'tripId': tripId});
    final n = r['registrationsDeleted'];
    return (deleted: r['deleted'] == true, registrationsDeleted: n is num ? n.toInt() : 0);
  }

  Future<void> registerAdminToken(String token) =>
      _call('registerAdminToken', {'token': token});

  Future<void> clearAdminToken(String token) =>
      _call('clearAdminToken', {'token': token});

  /// Every push the app used to send itself (with a key in the APK) goes
  /// through here now. `kind` is one of: book_assigned, association_update,
  /// chanting_challenge, submission_nudge, interaction_logged.
  Future<Map<String, dynamic>> sendStudentNotification(
          Map<String, dynamic> data) =>
      _call('sendStudentNotification', data);
  /// One step of the AI agent's conversation (functions/guideAgent.js): a message from the guide,
  /// the phone's answers to reads it asked for, or what happened to a change it proposed. The
  /// reply says what comes next (see lib/agent/AgentTypes.dart).
  Future<Map<String, dynamic>> guideAgentTurn(Map<String, dynamic> data) =>
      _call('guideAgentTurn', data);
  /// A recorded voice note as clean English text (functions/voiceNote.js).
  ///
  /// The audio is sent once and not kept. [existingText] is whatever is already
  /// in the field, sent for context only (so names and terms match) and never
  /// returned. The result is the one field `text`; there is no raw transcript.
  /// Tells the server a recording is about to arrive, so the sign-in and the function are already warm when the guide presses
  /// Done and the first seconds of the wait are not spent waking them up. Does nothing else; a failure is ignored.
  Future<void> warmVoice() async {
    try {
      await _call('voiceToEnglishText', {'warm': true});
    } catch (_) {/* only a head start */}
  }

  Future<String> voiceToEnglishText({
    required String audioBase64,
    required String mimeType,
    required int durationSeconds,
    required String purpose,
    String studentName = '',
    String existingText = '',
  }) async {
    final r = await _call('voiceToEnglishText', {
      'audioBase64': audioBase64,
      'mimeType': mimeType,
      'durationSeconds': durationSeconds,
      'purpose': purpose,
      if (studentName.isNotEmpty) 'studentName': studentName,
      if (existingText.trim().isNotEmpty) 'existingText': existingText,
    });
    return (r['text'] ?? '').toString();
  }
}

class RemoveAdminResult {
  const RemoveAdminResult({
    required this.studentCount,
    required this.teamlessEnablers,
    required this.removed,
    this.boardColumn,
    this.cardsMoved = 0,
  });
  final int studentCount;
  final List<String> teamlessEnablers;
  final bool removed;

  /// What the server did to the admin's column on the FOLK Boys board: `removed`, `unchanged` (they had none), `no-board`, `failed`.
  final String? boardColumn;

  /// How many cards filed in that column moved to the Unassigned column.
  final int cardsMoved;
}
