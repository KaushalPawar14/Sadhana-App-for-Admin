/// Student notification preferences, as seen from the Guide app.
///
/// Students choose what they want to hear about on their own Notifications
/// screen, which writes `users/{uid}.notificationPrefs` — a map of
/// `{notificationType: bool}`. Every guide-triggered send to a student has to
/// respect it, so this is the one place that reads it.
///
/// ⚠️ **Absent means ON, and an error also means ON.** Both are written as
/// `!= false`, never `== true`. Two separate reasons:
///
///  * Every student who predates the preferences screen has no
///    `notificationPrefs` field at all. An `== true` test would silently
///    unsubscribe the entire existing cohort the moment this shipped.
///  * If the lookup itself fails — offline, a permission error, a name that
///    does not resolve — the send proceeds. A broken preference read must never
///    silence a notification a student never asked to lose. This mirrors the
///    reasoning already applied to the Cloud Functions frequency cap, where a
///    failed throttle lookup allows the send rather than blocking it.
///
/// ⚠️ Note the deliberate asymmetry with `functions/index.js`: there, a
/// `notification` document that resolves to no user is **skipped**, because an
/// unresolvable identity is not a student at all ("Unknown User"). Here, an
/// unresolvable *name* still sends, because the caller already knows it is
/// addressing a real student — it just could not read their preference.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// The exact Firestore keys. Kept as constants so a typo cannot silently
/// create a second, always-on preference that no screen can turn off.
class StudentNotificationPref {
  static const String sadhanaReminderMorning = 'sadhanaReminderMorning';
  static const String sadhanaReminderMidday = 'sadhanaReminderMidday';
  static const String associationUpdates = 'associationUpdates';
  static const String chantingChallenge = 'chantingChallenge';
  static const String guideManualReminder = 'guideManualReminder';
}

/// Reads one preference out of an already-loaded `users/{uid}` document.
///
/// Use this when the caller is already iterating `users` — it costs no read.
bool studentWantsFromData(Map<String, dynamic>? userData, String key) {
  final prefs = userData?['notificationPrefs'];
  if (prefs is! Map) return true;
  return prefs[key] != false;
}

/// Reads one preference for a student identified by uid. One document read.
Future<bool> studentWantsByUid(String uid, String key) async {
  if (uid.trim().isEmpty) return true;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid.trim())
        .get();
    return studentWantsFromData(doc.data(), key);
  } catch (_) {
    return true; // a failed read must not silence a notification
  }
}

/// Reads one preference for a student identified by display name.
///
/// Needed because several send paths in this app are name-keyed —
/// `notification/{studentName}` — while preferences live on the uid-keyed user
/// document. One equality query bridges the two.
///
/// ⚠️ The name is **trimmed** before matching. Live data contains
/// `notification` document ids with trailing spaces, and an untrimmed query
/// would silently match nothing and fall through to "send".
Future<bool> studentWantsByName(String studentName, String key) async {
  final name = studentName.trim();
  if (name.isEmpty) return true;

  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('name', isEqualTo: name)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return true; // unresolvable name -> still send
    return studentWantsFromData(snap.docs.first.data(), key);
  } catch (_) {
    return true;
  }
}
