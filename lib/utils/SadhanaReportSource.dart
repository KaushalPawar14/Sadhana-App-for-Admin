import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'AdminProfile.dart';
import 'StudentScope.dart';
import 'GuideDb.dart';

/// Reads a student's sadhana report HISTORY from the collection of his CURRENT category ONLY. Mirrors the Student
/// app's own `utils/SadhanaReportSource.dart` (same rule, same reasoning); duplicated rather than shared, matching
/// this project's convention of no shared package between the two apps.
///
/// ---------------------------------------------------------------------------
/// ⚠️ Reports are CATEGORY-SEPARATED (product-owner decision; it replaces the earlier
/// "merge both collections so history survives a residence change" rule)
/// ---------------------------------------------------------------------------
/// A report lives in `sadhana-reports` (FOLK) or `hostel-sadhana` (Hostel / Localite) depending on the student's
/// category when he filed it. A student's data is read ONLY from the collection of his CURRENT category: his
/// calendar, graphs, the ABCDE activity card, "left to submit" and the priority signals. The other category's
/// reports are not read (those days show as not submitted, everything counts from zero). NOTHING is deleted or
/// moved, so when the category is switched back, that category's saved reports show again.
///
/// Every function takes the student's CURRENT `role` (or follows it live: [availableDatesStream] listens to the
/// student's profile), so a category change made here, or by another guide, takes effect without a restart.
const String kFolkReports = 'sadhana-reports';
const String kHostelReports = 'hostel-sadhana';

/// The report collection of a category, from the residence role: Hostel and Localite -> `hostel-sadhana`;
/// everyone else (FOLK, or no role) -> `sadhana-reports`.
String reportCollectionForRole(String? role) {
  final r = (role ?? '').trim();
  return r == 'Stay at Hostel' || r == 'Stay at Localite' ? kHostelReports : kFolkReports;
}

/// Lists a student's report dates in a way the security rules can prove: the
/// date documents carry server-stamped `scopeGuide` / `scopeTeam` /
/// `scopeGender`, so a non-HOD lists them through the viewer's own scope
/// queries (own team + unassigned of their gender) — nothing comes back for a
/// student outside their scope. Single-document reads need no such filter.
_ScopedDates _scopedDates(String collection, String studentName) =>
    _ScopedDates(_datesRef(collection, studentName));

class _ScopedDates {
  _ScopedDates(this._ref);
  final CollectionReference<Map<String, dynamic>> _ref;

  Future<QuerySnapshot<Map<String, dynamic>>> get() =>
      StudentScope.mergedGet(_queries());

  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots() =>
      StudentScope.mergedStream(_queries());

  List<Query<Map<String, dynamic>>> _queries() {
    final profile = AdminProfileProvider.current;
    if (profile == null) return [_ref];
    return StudentScope(profile).historyQueriesOn(_ref);
  }
}

CollectionReference<Map<String, dynamic>> _datesRef(
  String collection,
  String studentName,
) {
  return GuideDb.instance
      .collection(collection)
      .doc(studentName)
      .collection('dates');
}

/// Every date-doc for [studentName] in his CURRENT category's collection (one read).
Future<Map<String, Map<String, dynamic>>> fetchDateReports(
  String studentName,
  String? role,
) async {
  final out = <String, Map<String, dynamic>>{};
  if (studentName.isEmpty) return out;
  final snap = await _scopedDates(reportCollectionForRole(role), studentName).get();
  for (final doc in snap.docs) {
    out[doc.id] = doc.data();
  }
  return out;
}

/// One specific date's report from his CURRENT category's collection - null if he has none there (a report
/// filed under the other category does not count).
Future<Map<String, dynamic>?> fetchDateReport(
  String studentName,
  String dateId,
  String? role,
) async {
  if (studentName.isEmpty) return null;
  final doc = await _datesRef(reportCollectionForRole(role), studentName).doc(dateId).get();
  return doc.exists ? doc.data() : null;
}

/// Live "which dates have a report" set from his CURRENT category's collection, for the calendar's day-colouring.
/// With [studentUid] it FOLLOWS the student's profile: when his category changes (by this guide or another), the
/// stream switches to the new collection by itself. [role] is the role known now (used until the profile answers,
/// and for a student whose uid is not known). [snapshotsFor] / [roleStream] are for tests only.
Stream<Set<String>> availableDatesStream(
  String studentName, {
  String? role,
  String? studentUid,
  @visibleForTesting Stream<QuerySnapshot<Map<String, dynamic>>> Function(String collection)? snapshotsFor,
  @visibleForTesting Stream<String?>? roleStream,
}) {
  if (studentName.isEmpty) {
    return Stream<Set<String>>.value(<String>{});
  }
  late StreamController<Set<String>> controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? inner;
  StreamSubscription<String?>? roleSub;
  String? current;

  void listenCollection(String collection) {
    if (collection == current && inner != null) return;
    current = collection;
    inner?.cancel();
    inner = (snapshotsFor?.call(collection) ?? _scopedDates(collection, studentName).snapshots()).listen((snap) {
      controller.add(snap.docs.map((d) => d.id).toSet());
    }, onError: (Object error, StackTrace stackTrace) {
      controller.addError(error, stackTrace);
    });
  }

  controller = StreamController<Set<String>>.broadcast(
    onListen: () {
      listenCollection(reportCollectionForRole(role));
      final roles = roleStream ??
          (studentUid == null || studentUid.isEmpty
              ? null
              : GuideDb.instance
                  .collection('users')
                  .doc(studentUid)
                  .snapshots()
                  .map((s) => s.data()?['role']?.toString()));
      roleSub = roles?.listen((r) => listenCollection(reportCollectionForRole(r)), onError: (Object _) {});
    },
    onCancel: () {
      roleSub?.cancel();
      inner?.cancel();
      inner = null;
      current = null;
    },
  );
  return controller.stream;
}
