import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'AdminProfile.dart';
import 'StudentScope.dart';

/// Reads a student's sadhana report HISTORY across both residence-scoped
/// collections, merged by date — Master Task 2026-09-11, "Read reports from
/// both collections so history survives a residence change." Mirrors the
/// Student app's own `utils/SadhanaReportSource.dart` exactly (same
/// contract, same reasoning — see that file's own header); duplicated here
/// rather than shared, matching this project's established convention of no
/// shared package between the two apps.
///
/// ---------------------------------------------------------------------------
/// Why this exists
/// ---------------------------------------------------------------------------
/// A report lives in `sadhana-reports` (FOLK) or `hostel-sadhana` (Hostel /
/// Localite) depending on the student's residence AT THE TIME they submitted
/// it. Switching residence later (`Pages/StudentProfilePage.dart`) never
/// moves any existing report (Rule 14/15) — it only changes which collection
/// FUTURE reports land in. A read that picks ONE collection based on the
/// student's CURRENT role therefore silently loses every report filed under
/// the other one. Every place in this app that reads a student's report
/// HISTORY (as opposed to checking only today's own date, which still only
/// ever needs today's own current-role collection to WRITE, but is safe and
/// correct to check across both here too) must read BOTH and merge. This
/// file is the ONE place that merge logic lives.
///
/// ---------------------------------------------------------------------------
/// ⚠️ One report per date, never summed
/// ---------------------------------------------------------------------------
/// A student can only ever have submitted ONE report for a given calendar
/// day — whichever collection matched their role at the time. So a given
/// date-doc-id can only genuinely exist in ONE of these two collections for
/// one student. Every function below merges BY DATE — at most one document
/// per date — and never sums or combines two collections' values for the
/// same date. If a date-id is ever somehow present in both (a data anomaly),
/// `sadhana-reports` wins and the `hostel-sadhana` copy for that date is
/// dropped entirely, never merged field-by-field.
///
/// ---------------------------------------------------------------------------
/// Field differences are expected
/// ---------------------------------------------------------------------------
/// A FOLK-era day's document carries different fields (temple entry, daily
/// services) than a Hostel/Localite-era one (wake-up time). Callers already
/// read fields defensively rather than assuming a fixed shape, and continue
/// to — this file returns each date's document exactly as stored.
const List<String> kSadhanaReportCollections = [
  'sadhana-reports',
  'hostel-sadhana',
];

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
  return FirebaseFirestore.instance
      .collection(collection)
      .doc(studentName)
      .collection('dates');
}

/// Every date-doc for [studentName] across both collections, merged so at
/// most one document exists per date. Two reads total, regardless of how
/// much history exists (Part 3 item 4).
Future<Map<String, Map<String, dynamic>>> fetchMergedDateReports(
  String studentName,
) async {
  final merged = <String, Map<String, dynamic>>{};
  if (studentName.isEmpty) return merged;
  for (final collection in kSadhanaReportCollections) {
    final snap = await _scopedDates(collection, studentName).get();
    for (final doc in snap.docs) {
      merged.putIfAbsent(doc.id, () => doc.data());
    }
  }
  return merged;
}

/// One specific date's report, checked across both collections — null if
/// neither has it. Never sums or combines two documents for the same date:
/// at most one collection can genuinely have it, so the first hit is
/// returned as-is.
Future<Map<String, dynamic>?> fetchMergedDateReport(
  String studentName,
  String dateId,
) async {
  if (studentName.isEmpty) return null;
  for (final collection in kSadhanaReportCollections) {
    final doc = await _datesRef(collection, studentName).doc(dateId).get();
    if (doc.exists) return doc.data();
  }
  return null;
}

/// Live "which dates have a report" set, combined from both collections'
/// own `.snapshots()` streams — for calendar day-colouring, where a
/// one-shot read would miss a report arriving while the screen stays open.
/// A plain set union: a student's own date-doc only ever lives in one of
/// the two collections, so there is nothing to reconcile between them.
Stream<Set<String>> mergedAvailableDatesStream(String studentName) {
  late StreamController<Set<String>> controller;
  final latest = <String, Set<String>>{};
  final subs = <StreamSubscription>[];

  void emit() {
    if (latest.length < kSadhanaReportCollections.length) return;
    controller.add(latest.values.expand((s) => s).toSet());
  }

  controller = StreamController<Set<String>>.broadcast(
    onListen: () {
      for (final collection in kSadhanaReportCollections) {
        subs.add(
          _scopedDates(collection, studentName).snapshots().listen((snap) {
            latest[collection] = snap.docs.map((d) => d.id).toSet();
            emit();
          }),
        );
      }
    },
    onCancel: () {
      for (final s in subs) {
        s.cancel();
      }
    },
  );

  if (studentName.isEmpty) {
    return Stream<Set<String>>.value(<String>{});
  }
  return controller.stream;
}
