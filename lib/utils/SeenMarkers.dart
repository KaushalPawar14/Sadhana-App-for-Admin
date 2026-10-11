import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'GuideDb.dart';

/// Per-viewer "have I seen this yet" markers — Master Task 2026-09-10,
/// Part 6.
///
/// ONE new collection, `seenMarkers/{viewerId}` (Rule 12 justification):
/// one document per viewer, holding a last-seen `Timestamp` per feature —
/// a flat field for most features, or a nested `{subKey: Timestamp}` map
/// for the few features scoped to one sub-entity (a specific student's
/// thread, a specific goal target) rather than the whole feature, so
/// opening one sub-entity never marks every other sub-entity of that same
/// feature seen. Chosen over a `seen`/`seenBy` flag on every content
/// document itself (the alternative the task raised) because that would
/// mean writing to shared, often student-submitted, documents on every
/// single view — expensive at scale, and a Rule 14/15 risk (touching
/// content a student or another guide owns just because someone looked at
/// it). A per-viewer document is the opposite: exactly one small document
/// per viewer, written to ONLY by that viewer, about only their own
/// "what have I looked at" state.
///
/// `viewerId` reuses whatever identity this app already keys an admin by —
/// the admin id (`AdminProfile.id`, also the `adminUsers` doc id) every
/// screen in this app already carries. Nothing here depends on a role: a
/// marker is always the signed-in admin's own document. There is no per-guide Firebase Auth identity in this
/// app (see `utils/GuideRoster.dart`'s own header comment) — inventing one
/// just for this feature would be a second, parallel identity concept,
/// not a reuse of the first (Rule 1).
class SeenMarkers {
  /// Tests only: nothing is written (no Firestore).
  @visibleForTesting
  static bool debugDisable = false;

  static CollectionReference<Map<String, dynamic>> get _col => GuideDb.instance.collection('seenMarkers');

  /// A flat, whole-feature cursor — `seenMarkers/{viewerId}.{featureKey}`.
  ///
  /// ⚠️ Call ONCE per feature and hoist the returned `Stream` to a field
  /// (`initState`, never `build()`) — this wraps a live `snapshots()`
  /// listener, the exact same rule every other Firestore stream in these
  /// apps already follows since the size/performance audit.
  static Stream<Timestamp?> seenAt(String viewerId, String featureKey) {
    if (viewerId.isEmpty) return Stream.value(null);
    return _col
        .doc(viewerId)
        .snapshots()
        .map((doc) => doc.data()?[featureKey] as Timestamp?);
  }

  static Future<void> markSeen(String viewerId, String featureKey) async {
    if (viewerId.isEmpty || debugDisable) return;
    await _col.doc(viewerId).set({
      featureKey: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// The per-sub-entity variant — `seenMarkers/{viewerId}.{featureKey}.
  /// {subKey}` — for a feature where "seen" means opening one specific
  /// sub-entity (one student's comment thread, one goal target's page,
  /// one student's book panel), not the feature as a whole.
  static Stream<Timestamp?> seenAtSub(
      String viewerId, String featureKey, String subKey) {
    if (viewerId.isEmpty || subKey.isEmpty) return Stream.value(null);
    return _col.doc(viewerId).snapshots().map((doc) {
      final feature = doc.data()?[featureKey];
      if (feature is Map) return feature[subKey] as Timestamp?;
      return null;
    });
  }

  static Future<void> markSeenSub(
      String viewerId, String featureKey, String subKey) async {
    if (viewerId.isEmpty || subKey.isEmpty || debugDisable) return;
    await _col.doc(viewerId).set({
      featureKey: {subKey: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  }

  /// The whole `{subKey: Timestamp}` map for one per-sub-entity feature —
  /// used by an AGGREGATE badge (e.g. a hub tile asking "is ANY sub-entity
  /// of this feature unseen") that needs every sub-entity's own cursor at
  /// once, not just one specific [subKey]'s.
  static Stream<Map<String, Timestamp>> subCursors(
      String viewerId, String featureKey) {
    if (viewerId.isEmpty) return Stream.value(const {});
    return _col.doc(viewerId).snapshots().map((doc) {
      final feature = doc.data()?[featureKey];
      if (feature is! Map) return const {};
      final out = <String, Timestamp>{};
      feature.forEach((k, v) {
        if (v is Timestamp) out[k.toString()] = v;
      });
      return out;
    });
  }

  /// Per-BOOK seen markers for book commitments:
  /// `seenMarkers/{viewerId}.bookCommitmentBooks.{studentUid}.{bookDocId}` (a separate
  /// field, so the older per-student cursor `bookCommitments.{uid}` keeps working
  /// beside it: it means "seen up to" for everything older).
  static const String bookKey = 'bookCommitmentBooks';

  static Future<void> markSeenBooks(
      String viewerId, String studentUid, Iterable<String> bookDocIds) async {
    final ids = bookDocIds.where((e) => e.isNotEmpty).toList();
    if (viewerId.isEmpty || studentUid.isEmpty || ids.isEmpty || debugDisable) return;
    await _col.doc(viewerId).set({
      bookKey: {
        studentUid: {for (final id in ids) id: FieldValue.serverTimestamp()},
      },
    }, SetOptions(merge: true));
  }

  /// `{studentUid: {bookDocId: seenAt}}` for every book this viewer has seen.
  static Stream<Map<String, Map<String, Timestamp>>> bookCursors(String viewerId) {
    if (viewerId.isEmpty) return Stream.value(const {});
    return _col.doc(viewerId).snapshots().map((doc) {
      final feature = doc.data()?[bookKey];
      if (feature is! Map) return const <String, Map<String, Timestamp>>{};
      final out = <String, Map<String, Timestamp>>{};
      feature.forEach((uid, books) {
        if (books is! Map) return;
        final m = <String, Timestamp>{};
        books.forEach((id, v) {
          if (v is Timestamp) m[id.toString()] = v;
        });
        out[uid.toString()] = m;
      });
      return out;
    });
  }

  /// Combines a "latest real activity" stream with a "last seen" stream
  /// into one "is this currently unseen" boolean stream — the single
  /// primitive every feature's own unseen-stream is built from, kept in
  /// exactly one place rather than re-implemented per feature.
  ///
  /// No new package dependency added for this (no `rxdart`, no `package:
  /// async`'s `StreamZip`) — a small hand-rolled combinator is enough for
  /// two inputs and keeps this file self-contained.
  ///
  /// ⚠️ Same hoisting rule as [seenAt]: call ONCE per feature with two
  /// ALREADY-HOISTED input streams, and store the single `Stream<bool>`
  /// this returns in a field. Calling it fresh inside `build()` would
  /// re-subscribe to both inputs on every rebuild — exactly the bug this
  /// whole file's design is trying to avoid.
  static Stream<bool> unseenFrom(
      Stream<Timestamp?> latestActivity, Stream<Timestamp?> lastSeen) {
    late StreamController<bool> controller;
    Timestamp? latest;
    Timestamp? seen;
    var gotLatest = false;
    var gotSeen = false;
    StreamSubscription? subA, subB;

    void emit() {
      if (!gotLatest || !gotSeen) return;
      final isUnseen =
          latest != null && (seen == null || latest!.compareTo(seen!) > 0);
      controller.add(isUnseen);
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        subA = latestActivity.listen((v) {
          latest = v;
          gotLatest = true;
          emit();
        });
        subB = lastSeen.listen((v) {
          seen = v;
          gotSeen = true;
          emit();
        });
      },
      onCancel: () {
        subA?.cancel();
        subB?.cancel();
      },
    );
    return controller.stream;
  }
}
