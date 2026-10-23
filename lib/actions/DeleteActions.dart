import '../utils/AdminProfile.dart';
import '../utils/GuideDb.dart';
import '../utils/StudentScope.dart';

/// Deleting records a guide has selected, as shared logic with no dialog in it: the screens'
/// "Delete selected" and the AI agent both delete through [deleteRecords], each asking its own
/// permission question first.

/// What a delete came to.
class DeleteOutcome {
  const DeleteOutcome({this.deleted = const {}, this.denied = 0, this.failed = 0});

  /// Ids confirmed gone (including ones that were already gone: the end state wanted is true).
  final Set<String> deleted;

  /// Records this admin may not delete: left alone.
  final int denied;

  /// Records the delete did not take on.
  final int failed;

  bool get clean => denied == 0 && failed == 0;
}

/// Deletes [ids] from [collection], one by one: each record is read, [canDelete] is asked about
/// it, it is deleted, and only counted once it is confirmed gone — verify, don't assume.
Future<DeleteOutcome> deleteRecords({
  required String collection,
  required Set<String> ids,
  required Future<bool> Function(Map<String, dynamic> data) canDelete,
}) async {
  final firestore = GuideDb.instance;
  final deleted = <String>{};
  var denied = 0;
  var failed = 0;

  await Future.wait(ids.map((id) async {
    try {
      final ref = firestore.collection(collection).doc(id);
      final snap = await ref.get();

      if (!snap.exists) {
        // Already gone (e.g. deleted elsewhere a moment earlier) — the end state the caller
        // wanted is already true.
        deleted.add(id);
        return;
      }

      if (!await canDelete(snap.data() as Map<String, dynamic>)) {
        denied++;
        return;
      }

      await ref.delete();

      final recheck = await ref.get();
      if (recheck.exists) {
        failed++;
        return;
      }
      deleted.add(id);
    } catch (_) {
      failed++;
    }
  }));

  return DeleteOutcome(deleted: deleted, denied: denied, failed: failed);
}

/// Whether [me] may delete a record stamped with the server's scope fields (a meeting, a flagged
/// message): a HOD anything; anyone else only a record about a student they may manage
/// ([StudentScope.canManage]). A record not yet stamped falls back to its own `guideId` being the
/// signed-in admin.
bool canDeleteStamped(Map<String, dynamic> data, AdminProfile me) {
  if (me.isHod) return true;
  if (!data.containsKey('scopeGuide')) {
    return (data['guideId'] ?? '').toString() == me.id;
  }
  return StudentScope(me).canManage(StudentRef(
    uid: (data['studentUid'] ?? '').toString(),
    guideId: (data['scopeGuide'] ?? '').toString(),
    teamGuide: (data['scopeTeam'] ?? '').toString(),
    gender: (data['scopeGender'] ?? '').toString(),
  ));
}

/// Whether [me] may delete a record about the student [ref] (an interaction log): a HOD anything;
/// anyone else only about a student they may manage.
bool canDeleteForStudent(StudentRef? ref, AdminProfile me) {
  if (me.isHod) return true;
  if (ref == null) return false; // fails closed while unresolved
  return StudentScope(me).canManage(ref);
}
