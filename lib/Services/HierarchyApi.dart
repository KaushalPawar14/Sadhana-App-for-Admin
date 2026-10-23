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
    return AdminSummary.fromMap(Map<String, dynamic>.from(r['admin'] as Map));
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
    return AdminSummary.fromMap(Map<String, dynamic>.from(r['admin'] as Map));
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
    );
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

  /// Is this mobile number already on any user document? (Replaces the app's
  /// own `users where mobileNumber ==` query, which strict rules forbid.)
  /// `name` is the existing student's name when taken.
  Future<({bool taken, String name})> checkMobileTaken(String mobile) async {
    final r = await _call('checkMobileTaken', {'mobile': mobile});
    return (taken: r['taken'] == true, name: (r['name'] ?? '').toString());
  }

  /// Gemini runs on the server (the API key is no longer in the app).
  /// Returns the normalised draft map; throws [HierarchyException] with a
  /// message that is safe to show the guide.
  Future<Map<String, dynamic>> geminiExtractInteraction({
    required String rawText,
    required String studentName,
  }) async {
    final r = await _call('geminiExtractInteraction',
        {'rawText': rawText, 'studentName': studentName});
    final draft = r['draft'];
    if (draft is! Map) throw HierarchyException('internal', 'Gemini returned the wrong shape. Try Extract again.');
    return Map<String, dynamic>.from(draft);
  }

  /// Master 1 B — three to five suggestions, each with a why and a
  /// concrete next step. The two flat fields are still returned by the
  /// server (built from the first suggestion) so nothing that reads them
  /// breaks; new callers should read 'suggestions'.
  Future<Map<String, dynamic>> geminiSuggestNextAction({
    required String contextText,
    required String studentName,
  }) async {
    final r = await _call('geminiSuggestNextAction',
        {'contextText': contextText, 'studentName': studentName});
    final raw = r['suggestions'];
    return {
      'suggestions': raw is List
          ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : const <Map<String, dynamic>>[],
      'recommendedNextAction': (r['recommendedNextAction'] ?? '').toString(),
      'recommendedReasoning': (r['recommendedReasoning'] ?? '').toString(),
    };
  }

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
  /// A recorded voice note as clean English text (functions/voiceNote.js).
  ///
  /// The audio is sent once and not kept. [existingText] is whatever is already
  /// in the field, sent for context only (so names and terms match) and never
  /// returned. The result is the one field `text`; there is no raw transcript.
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
  });
  final int studentCount;
  final List<String> teamlessEnablers;
  final bool removed;
}
