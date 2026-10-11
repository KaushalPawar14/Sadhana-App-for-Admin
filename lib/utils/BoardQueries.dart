/// Trello-style boards — schema and every Firestore operation, in one place.
///
/// Phase 1 (built 2026-08-21). No UI in this file: the board screens call
/// these helpers, so **the entire write surface of the board feature is
/// auditable here** rather than scattered across widget callbacks.
///
/// ---------------------------------------------------------------------------
/// WRITE-BACK WHITELIST — the whole feature, enforced by this file
/// ---------------------------------------------------------------------------
/// A drag may write, and this file only ever writes:
///
///
///   Custom boards (`kBoardKindCustom`) -> `placements` ONLY.
///   Board C (`kBoardKindGuideAssignment`) -> `placements` ONLY, from this
///     file. The student's `guideId` is no longer written by the client at
///     all (hierarchy project): every assignment goes through the server
///     callable `HierarchyApi.instance.assignStudent`, which also files the
///     placement when given a board/column/order.
///
/// Board-level actions (not a drag): `createBoard`/`renameBoard`/
/// `deleteBoard`/[setBoardSharedWith] each touch only the `boards/{id}`
/// document itself (plus its own `columns`/`placements` subcollections for
/// creation/deletion) — never a student document.
///
/// ⚠️ **Rule 12 — why `sharedWith` is a new FIELD, not a new collection
/// (Phase 4).** A board can already be found by `ownerGuideId`; sharing is
/// the same relationship in reverse ("who else may open this board"), which
/// is naturally a property of the board document itself, not a separate
/// membership record — there is nothing to look up FROM the guide's side
/// that isn't already served by `allBoardsStream()` + filtering in Dart
/// (the same "unfiltered listener over a handful of documents" reasoning
/// [allBoardsStream] already documents for `ownerGuideId` applies identically
/// here). No new collection was considered seriously for this reason.
///
/// ⚠️ **The Book Reading board (`kind == 'bookReading'`) was REMOVED on
/// 2026-08-23.** It was a placements-only kanban, built because Step 0 found
/// no guide-assigned reading-stage field to drive it. It is superseded by a
/// read-only drill-down reached from the student list, which reads
/// `booksRead` directly instead of asking a guide to re-file what the student
/// already reported.
///
/// `booksRead` is no longer 100% student-submitted PROJECT-WIDE — as of the
/// Master Task's Part 4, `Home/FolkBoysWorkspace.dart` (a DIFFERENT file
/// from this one) writes to it when a guide assigns or finishes a book; see
/// that file's own doc comments for the exact field list. NOTHING IN THIS
/// FILE (`BoardQueries.dart` itself) writes, modifies or deletes
/// `booksRead`, still — that claim about this file is unchanged.
///
/// NOTHING in this file writes, modifies or deletes: `booksRead`,
/// `users.role`, `sadhana-reports/**`, `hostel-sadhana/**`,
/// `chantingChallenges*`, `scorecard`, `competition`, `litAssessments`, or any
/// other student profile field. The Board C header stat reads `users.role` and
/// never writes it.
///
/// Rule 14/15 note: a reassignment (server-side, `assignStudent`) changes ONLY the
/// student's assignment fields. It does
/// not move, copy, rewrite or delete any of that student's history. Rows
/// already stamped with the previous guide (`associations.guideId`,
/// `flaggedChatMessages.guideId`, `chantingChallengeContributions.guideId`)
/// deliberately stay put — the old guide keeps their record, and the new guide
/// starts fresh. The confirmation dialog says so in plain words before any
/// write happens.
///
/// ---------------------------------------------------------------------------
/// Firestore
/// ---------------------------------------------------------------------------
///   boards/{autoId}
///     kind          String   "guideAssignment" | "custom"
///                            (⚠️ "bookReading" retired 2026-08-23 — any
///                             surviving doc with that kind is ignored by
///                             `visibleBoards`, never listed, never opened)
///     ownerGuideId  String   the owning guide; "" for the one shared
///                            guideAssignment board
///     title         String
///     createdBy     String   guide name
///     createdAt     Timestamp
///     sharedWith    `List<String>` guide names this CUSTOM board has been
///                            shared with (Phase 4). Absent on boards
///                            created before this field existed — read as
///                            `[]`, never as an error. Meaningless on the
///                            `guideAssignment` board (its own HOD-only rule
///                            never consults this list at all).
///
///   boards/{boardId}/columns/{autoId}
///     title      String
///     order      int      0-based; a reorder rewrites only this field
///     colorValue int      an ARGB int
///     kind       String   "normal" | "unsorted" | "guide" | "unassigned"
///     guideId    String   set only when kind == "guide"
///
///   boards/{boardId}/placements/{studentUid}
///     studentUid  String   == the document id
///     columnId    String
///     order       int
///     movedBy     String   guide name
///     movedAt     Timestamp
///
/// ⚠️ **`placements` is keyed by `studentUid`**, so a student cannot be placed
/// twice on one board — it is impossible by construction rather than by a
/// uniqueness check, and a move is one `.set(merge)` instead of a
/// delete-then-add. These are new collections, so Rule 4's document-ID
/// strategy is not engaged; the choice was approved in Step 0.
///
/// ⚠️ **No student data is duplicated into a placement.** No name, no role, no
/// score, no reading data. Card faces read all of that live at render time.
///
/// ---------------------------------------------------------------------------
/// Where a card's column comes from — the two boards differ, deliberately
/// ---------------------------------------------------------------------------
///  * **Board C** derives column membership from `users.guideId` itself, NOT
///    from the placement. `guideId` is the authoritative field and it can be
///    changed from outside this feature (`Pages/Profile.dart`'s existing
///    "Assign to Me" button), so trusting a stored placement for membership
///    would let the board display a stale guide. The placement is still
///    written — the whitelist allows it — but it carries only intra-column
///    `order`.
///  * **Custom boards** derive membership from the placement's `columnId`,
///    defaulting to Unsorted. There is no authoritative field behind those
///    boards; the placement *is* the organiser.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'AdminProfile.dart';
import 'StudentScope.dart';
import 'GuideDb.dart';

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------

const String kBoardsCollection = 'boards';
const String kColumnsSubcollection = 'columns';
const String kPlacementsSubcollection = 'placements';

const String kBoardKindGuideAssignment = 'guideAssignment';
const String kBoardKindCustom = 'custom';

/// The retired Book Reading board kind (removed 2026-08-23).
///
/// ⚠️ **Kept private, and ONLY to exclude such documents from the board list.**
/// Nothing creates this kind any more. It survives as a constant because a
/// handset still running the previous build would mint a fresh `bookReading`
/// board the next time its guide opens the board list, and without this filter
/// that document would surface as an unnamed zombie tile routed through the
/// generic custom-board branch. Deleting the one known document is not enough
/// on its own — old clients can write new ones.
const String _kRetiredBoardKindBookReading = 'bookReading';

const String kColumnKindNormal = 'normal';
const String kColumnKindUnsorted = 'unsorted';
const String kColumnKindGuide = 'guide';
const String kColumnKindUnassigned = 'unassigned';

/// Title of the permanent catch-all column on custom boards.
const String kUnsortedTitle = 'Unsorted';

/// Title of the permanent column on Board C for students with no guide.
const String kUnassignedTitle = 'Unassigned';

/// Default column colours, cycled when seeding.
const List<int> kColumnPalette = [
  0xFF00695C,
  0xFF1565C0,
  0xFF6A1B9A,
  0xFFEF6C00,
  0xFF2E7D32,
  0xFFAD1457,
];

// -----------------------------------------------------------------------------
// Models — thin views over a snapshot, holding no student data
// -----------------------------------------------------------------------------

class BoardDoc {
  final String id;
  final String kind;
  final String ownerGuideId;
  final String title;

  /// Guides this board has been explicitly shared with — Phase 4. Empty for
  /// every board created before this field existed and for the shared
  /// `guideAssignment` board, which was never gated by this list at all
  /// (`ownerGuideId` is `""` for it and `isGuideAssignment` short-circuits
  /// both [visibleBoards] and [canEditBoard] before this list is ever
  /// consulted). See [BoardQueries.dart]'s own header for the Rule 12
  /// justification for this field.
  final List<String> sharedWith;

  const BoardDoc({
    required this.id,
    required this.kind,
    required this.ownerGuideId,
    required this.title,
    this.sharedWith = const [],
  });

  factory BoardDoc.from(String id, Map<String, dynamic> data) => BoardDoc(
        id: id,
        kind: (data['kind'] ?? '').toString(),
        ownerGuideId: (data['ownerGuideId'] ?? '').toString(),
        title: (data['title'] ?? '').toString(),
        // Absent on every board created before Phase 4 — reads as "shared
        // with nobody", not an error.
        sharedWith: (data['sharedWith'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  bool get isGuideAssignment => kind == kBoardKindGuideAssignment;

  /// A leftover board from the retired Book Reading kanban. See
  /// [_kRetiredBoardKindBookReading] — these are filtered out of the list.
  bool get isRetiredBookReading =>
      kind == _kRetiredBoardKindBookReading;

  bool isOwnedBy(String guide) => ownerGuideId == guide;

  bool isSharedWith(String guide) => sharedWith.contains(guide);
}

class BoardColumn {
  final String id;
  final String title;
  final int order;
  final int colorValue;
  final String kind;
  final String guideId;

  const BoardColumn({
    required this.id,
    required this.title,
    required this.order,
    required this.colorValue,
    required this.kind,
    required this.guideId,
  });

  factory BoardColumn.from(String id, Map<String, dynamic> data) => BoardColumn(
        id: id,
        title: (data['title'] ?? '').toString(),
        order: data['order'] is num ? (data['order'] as num).toInt() : 0,
        colorValue: data['colorValue'] is num
            ? (data['colorValue'] as num).toInt()
            : kColumnPalette.first,
        kind: (data['kind'] ?? kColumnKindNormal).toString(),
        guideId: (data['guideId'] ?? '').toString(),
      );

  /// Columns that exist structurally and can never be deleted or renamed.
  bool get isPermanent =>
      kind == kColumnKindUnsorted || kind == kColumnKindUnassigned;

  /// Board C's per-guide columns. Phase 1 ships no delete for these at all
  /// (approved decision 6) — a guide column exists because a guide exists, and
  /// guide removal is a separate future feature.
  bool get isGuideColumn => kind == kColumnKindGuide;

  bool get isEditable => !isPermanent && !isGuideColumn;
}

// -----------------------------------------------------------------------------
// Reads
// -----------------------------------------------------------------------------

CollectionReference<Map<String, dynamic>> _boards() =>
    GuideDb.instance.collection(kBoardsCollection);

CollectionReference<Map<String, dynamic>> columnsRef(String boardId) =>
    _boards().doc(boardId).collection(kColumnsSubcollection);

CollectionReference<Map<String, dynamic>> placementsRef(String boardId) =>
    _boards().doc(boardId).collection(kPlacementsSubcollection);

/// Every board this admin may open: the shared guideAssignment board (HOD only),
/// boards this admin owns, and boards shared with them (equality / array-contains
/// queries, merged). The security rules allow exactly these reads; visibility is
/// then refined in Dart by [visibleBoards] (the guideAssignment board is hidden
/// from a non-HOD).
Stream<List<BoardDoc>> allBoardsStream() {
  final profile = AdminProfileProvider.current;
  final boards = _boards();
  final queries = <Query<Map<String, dynamic>>>[
    // The shared Guide Assignment board is HOD-only (the rules refuse the query
    // to anyone else), so only the HOD asks for it.
    if (profile != null && profile.isHod)
      boards.where('kind', isEqualTo: kBoardKindGuideAssignment),
    if (profile != null) ...[
      boards.where('ownerGuideId', isEqualTo: profile.id),
      boards.where('sharedWith', arrayContains: profile.id),
    ],
  ];
  return StudentScope.mergedStream(queries).map((snap) =>
      snap.docs.map((d) => BoardDoc.from(d.id, d.data())).toList());
}

/// The boards this guide may open, in display order.
///
/// ⚠️ **The guideAssignment board is absent — not disabled — for a non-HOD.**
/// It is filtered out of the list entirely, so there is no tile to grey out and
/// nothing to tap. Matches the `if (_isHod)` idiom in `BoysDetails.dart`.
///
/// ⚠️ **Custom-board visibility changed in Phase 4, now that explicit sharing
/// exists — a deliberate tightening, not a bug.** Before sharing existed, the
/// HOD saw every guide's custom board (read-only), because there was no other
/// way for the HOD to ever see one at all. Now that a board can be
/// deliberately shared, the previous blanket visibility means a guide's
/// private working board is visible to the HOD whether they wanted that or
/// not — arguably not what "private" should mean once there is a real
/// alternative. **Recommendation implemented here: the HOD is treated like
/// any other guide for CUSTOM boards** — own boards + boards explicitly
/// shared with the HOD, nothing more. The `guideAssignment` board is
/// UNCHANGED: still HOD-only, still absent (not disabled) for anyone else,
/// still gated by the same `isHod` check on the branch above, completely
/// unaffected by this change. Flagged here as a real behaviour change worth
/// the product owner's attention, not decided silently.
List<BoardDoc> visibleBoards({
  required List<BoardDoc> all,
  required String guide,
  required bool isHod,
}) {
  final out = <BoardDoc>[];

  for (final b in all) {
    // Retired kind — never listed, whoever is looking. A stale document
    // written by an old client must not resurface as a tile.
    if (b.isRetiredBookReading) continue;

    if (b.isGuideAssignment) {
      if (isHod) out.add(b);
      continue;
    }
    // Custom board: own boards, or boards explicitly shared with this
    // viewer — the SAME rule for the HOD as for any other guide (Phase 4).
    if (b.isOwnedBy(guide) || b.isSharedWith(guide)) out.add(b);
  }

  out.sort((a, b) {
    // Guide Assignment first, then custom boards by owner and title.
    int rank(BoardDoc x) => x.isGuideAssignment ? 0 : 1;
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final o = a.ownerGuideId.compareTo(b.ownerGuideId);
    if (o != 0) return o;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

  return out;
}

/// True when this guide may drag/edit on [board] — day-to-day editing:
/// moving cards, renaming the board, and column CRUD.
///
/// The HOD has full read/write on the guideAssignment board. For a custom
/// board, the owner AND anyone it has been explicitly shared with get FULL
/// control (Phase 4, product owner's explicit decision) — this specifically
/// enables the HOD to build a board for a guide and hand it over as a real
/// working tool, not a read-only view. A board neither owned by nor shared
/// with this guide is read-only to them (and, per [visibleBoards], is not
/// even listed for them at all unless they are the HOD viewing the one
/// exempt `guideAssignment` board).
///
/// ⚠️ **Deleting or re-sharing the board itself is NOT covered by this
/// function — see [isBoardOwner].** A shared-with collaborator gets full
/// day-to-day editing rights but not those two actions; the product owner's
/// own instruction reasoned that destroying (or redistributing access to)
/// someone else's board should stay with whoever created it.
bool canEditBoard({
  required BoardDoc board,
  required String guide,
  required bool isHod,
}) {
  if (board.isGuideAssignment) return isHod;
  return board.isOwnedBy(guide) || board.isSharedWith(guide);
}

/// True only for the board's actual creator — the narrower gate for
/// deleting the board or changing who it is shared with. See
/// [canEditBoard]'s own doc comment for why these two actions are NOT part
/// of the broader day-to-day edit right shared-with guides otherwise get.
bool isBoardOwner({required BoardDoc board, required String guide}) =>
    board.isOwnedBy(guide);

Stream<List<BoardColumn>> columnsStream(String boardId) {
  // Sorted in Dart, so no index is needed alongside any future filter — the
  // same shape every query in this project uses.
  return columnsRef(boardId).snapshots().map((snap) {
    final list =
        snap.docs.map((d) => BoardColumn.from(d.id, d.data())).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  });
}

Stream<QuerySnapshot<Map<String, dynamic>>> placementsStream(String boardId) =>
    placementsRef(boardId).snapshots();

// -----------------------------------------------------------------------------
// Board lifecycle
// -----------------------------------------------------------------------------

/// Creates a board and seeds its columns. Returns the new board id.
Future<String> createBoard({
  required String kind,
  required String ownerGuideId,
  required String title,
  required String createdBy,
  required List<String> seedColumnTitles,
  bool withUnsorted = true,
}) async {
  final ref = await _boards().add({
    'kind': kind,
    'ownerGuideId': ownerGuideId,
    'title': title,
    'createdBy': createdBy,
    'createdAt': FieldValue.serverTimestamp(),
    'sharedWith': <String>[],
  });

  final batch = GuideDb.instance.batch();
  var order = 0;

  if (withUnsorted) {
    batch.set(columnsRef(ref.id).doc(), {
      'title': kUnsortedTitle,
      'order': order++,
      'colorValue': 0xFF616161,
      'kind': kColumnKindUnsorted,
      'guideId': '',
    });
  }

  for (final t in seedColumnTitles) {
    batch.set(columnsRef(ref.id).doc(), {
      'title': t,
      'order': order,
      'colorValue': kColumnPalette[order % kColumnPalette.length],
      'kind': kColumnKindNormal,
      'guideId': '',
    });
    order++;
  }

  await batch.commit();
  return ref.id;
}

/// Creates the single shared Guide Assignment board if it does not exist.
///
/// HOD-only caller. Seeds just the permanent "Unassigned" column — the
/// per-guide columns are reconciled from the live roster by
/// [reconcileGuideColumns], never authored by hand.
Future<void> ensureGuideAssignmentBoard({
  required List<BoardDoc> all,
  required String hodGuide,
}) async {
  if (all.any((b) => b.isGuideAssignment)) return;

  final ref = await _boards().add({
    'kind': kBoardKindGuideAssignment,
    'ownerGuideId': '',
    'title': 'Guide Assignment',
    'createdBy': hodGuide,
    'createdAt': FieldValue.serverTimestamp(),
  });

  await columnsRef(ref.id).doc().set({
    'title': kUnassignedTitle,
    'order': 9999, // Always last, however many guides are added.
    'colorValue': 0xFF757575,
    'kind': kColumnKindUnassigned,
    'guideId': '',
  });
}

Future<void> renameBoard(String boardId, String title) =>
    _boards().doc(boardId).update({'title': title});

/// Replaces the board's whole `sharedWith` list — Phase 4. The caller
/// already gathers the intended final list (a set of checkboxes against
/// the admin list of the loaded `AdminProfile`), so this is a single overwrite, not an
/// add/remove pair — simpler, and there is no ordering or per-entry
/// metadata to preserve.
///
/// ⚠️ Owner-only by convention at the call site (`isBoardOwner`) — this
/// function itself does not re-check, matching every other write in this
/// file (the whitelist is enforced by what each function touches, not by a
/// permission check inside it).
Future<void> setBoardSharedWith({
  required String boardId,
  required List<String> sharedWith,
}) =>
    _boards().doc(boardId).update({'sharedWith': sharedWith});

/// Deletes a board and everything under it.
///
/// Firestore does not cascade, so the two subcollections are removed
/// explicitly — otherwise the columns and placements would be orphaned and
/// invisible forever. Only ever touches this board's own documents; no student
/// data is involved anywhere in this call.
Future<void> deleteBoard(String boardId) async {
  final cols = await columnsRef(boardId).get();
  final places = await placementsRef(boardId).get();

  final batch = GuideDb.instance.batch();
  for (final d in cols.docs) {
    batch.delete(d.reference);
  }
  for (final d in places.docs) {
    batch.delete(d.reference);
  }
  batch.delete(_boards().doc(boardId));
  await batch.commit();
}

// -----------------------------------------------------------------------------
// Column lifecycle
// -----------------------------------------------------------------------------

Future<void> addColumn({
  required String boardId,
  required String title,
  required int order,
}) {
  return columnsRef(boardId).add({
    'title': title,
    'order': order,
    'colorValue': kColumnPalette[order % kColumnPalette.length],
    'kind': kColumnKindNormal,
    'guideId': '',
  });
}

Future<void> renameColumn(String boardId, String columnId, String title) =>
    columnsRef(boardId).doc(columnId).update({'title': title});

Future<void> recolourColumn(String boardId, String columnId, int colorValue) =>
    columnsRef(boardId).doc(columnId).update({'colorValue': colorValue});

/// Persists a whole reordering at once. Writes only the `order` field.
Future<void> reorderColumns({
  required String boardId,
  required List<BoardColumn> inNewOrder,
}) async {
  final batch = GuideDb.instance.batch();
  for (var i = 0; i < inNewOrder.length; i++) {
    final c = inNewOrder[i];
    // The permanent Unassigned column keeps its sentinel order so it stays
    // last no matter what else moves.
    if (c.kind == kColumnKindUnassigned) continue;
    batch.update(columnsRef(boardId).doc(c.id), {'order': i});
  }
  await batch.commit();
}

/// Deletes a column, moving any cards in it to the Unsorted column.
///
/// **Behaviour chosen: reassign to Unsorted, never orphan, never block.**
/// A placement on a custom board is only the guide's own
/// opinion about where a boy sits, and Unsorted is already the well-defined
/// "no opinion yet" state — so deleting a stage should not force the guide to
/// hand-move ten cards first. Cards land in Unsorted, which always exists and
/// is itself undeletable, so no card can ever be left pointing at a column
/// that is gone. The alternative (block until empty) was rejected here as
/// busywork; it *is* the rule on Board C, where a column means something
/// entirely different.
///
/// ⚠️ Writes only `placements.columnId` and deletes the column document. No
/// student data is touched.
Future<void> deleteColumnMovingCardsToUnsorted({
  required String boardId,
  required String columnId,
  required String unsortedColumnId,
  required String movedBy,
}) async {
  final affected = await placementsRef(boardId)
      .where('columnId', isEqualTo: columnId)
      .get();

  final batch = GuideDb.instance.batch();
  for (final d in affected.docs) {
    batch.update(d.reference, {
      'columnId': unsortedColumnId,
      'movedBy': movedBy,
      'movedAt': FieldValue.serverTimestamp(),
    });
  }
  batch.delete(columnsRef(boardId).doc(columnId));
  await batch.commit();
}

/// Deletes a column AND every placement pointing to it — outright, not
/// relocated. **Used only by boards with no Unsorted column to fall back
/// to.** [deleteColumnMovingCardsToUnsorted] above is UNCHANGED and remains
/// the mandatory board's own function (that board legitimately has a
/// permanent Unsorted-kind column, so relocation still makes sense there).
/// This is a separate function, not a parameter on the existing one, so
/// neither caller can accidentally drift the other's behaviour.
///
/// ⚠️ **Only ever touches THIS board's own `placements` subcollection and
/// its own `columns` subcollection — never a student document.** A deleted
/// placement removes the student from THIS board's organisation only; the
/// student's own `users/{uid}` document, and any placement they have on a
/// DIFFERENT board, are both untouched.
Future<void> deleteColumnDeletingPlacements({
  required String boardId,
  required String columnId,
}) async {
  final affected = await placementsRef(boardId)
      .where('columnId', isEqualTo: columnId)
      .get();

  final batch = GuideDb.instance.batch();
  for (final d in affected.docs) {
    batch.delete(d.reference);
  }
  batch.delete(columnsRef(boardId).doc(columnId));
  await batch.commit();
}

/// How many cards sit in a column right now, from an already-loaded snapshot.
int cardsInColumn(QuerySnapshot<Map<String, dynamic>>? placements,
    String columnId) {
  if (placements == null) return 0;
  return placements.docs
      .where((d) => (d.data()['columnId'] ?? '').toString() == columnId)
      .length;
}

// -----------------------------------------------------------------------------
// Board C — guide columns reconciled from the live roster
// -----------------------------------------------------------------------------

/// Makes the board's guide columns match the live roster.
///
/// Creates a column for any guide that does not have one. **Never deletes** —
/// Phase 1 ships no column-delete on this board at all (approved decision 6),
/// and Step 0 established that the three seed guides cannot be removed from
/// the roster anyway, so a delete here would be misleading.
///
/// This is what makes "a column exists because a guide exists" true by
/// construction rather than by convention.
Future<void> reconcileGuideColumns({
  required String boardId,
  required List<String> roster,
  required List<BoardColumn> existing,
}) async {
  final have = existing
      .where((c) => c.isGuideColumn)
      .map((c) => c.guideId)
      .toSet();

  final missing = roster.where((g) => !have.contains(g)).toList();
  if (missing.isEmpty) return;

  final batch = GuideDb.instance.batch();
  var order = existing
      .where((c) => c.kind != kColumnKindUnassigned)
      .fold<int>(-1, (max, c) => c.order > max ? c.order : max);

  for (final g in missing) {
    order++;
    batch.set(columnsRef(boardId).doc(), {
      'title': g,
      'order': order,
      'colorValue': kColumnPalette[order % kColumnPalette.length],
      'kind': kColumnKindGuide,
      'guideId': g,
    });
  }
  await batch.commit();
}

// -----------------------------------------------------------------------------
// Placement writes — the only writes a drag performs
// -----------------------------------------------------------------------------

/// Moves a card on a custom board.
///
/// ⚠️ **This is the entire write.** One `placements/{studentUid}` document.
/// Nothing else in Firestore changes — in particular `booksRead` is not
/// touched, because every field in it is student-submitted.
Future<void> movePlacement({
  required String boardId,
  required String studentUid,
  required String columnId,
  required int order,
  required String movedBy,
}) {
  return placementsRef(boardId).doc(studentUid).set({
    'studentUid': studentUid,
    'columnId': columnId,
    'order': order,
    'movedBy': movedBy,
    'movedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

// A guide reassignment is NOT a client write any more (hierarchy project): the
// old `reassignGuide` (a direct `users.guideId` update) was removed. Every
// assignment / release goes through `HierarchyApi.instance.assignStudent`
// (the server checks authority and gender, writes `guideId`/`teamGuide`, and —
// when `boardId`/`columnId`/`order` are passed — also files the card's
// placement on this board). `movePlacement` above stays for non-assignment
// card moves on custom boards.


// -----------------------------------------------------------------------------
// Residence header stat — READ-ONLY
// -----------------------------------------------------------------------------

/// The three live values of `users/{uid}.role`.
///
/// ⚠️ **Localites** (Master Task, 2026-09-03) behave EXACTLY like Hostel
/// residents everywhere except the board's own label/tint — including
/// writing to `hostel-sadhana` — but they are their OWN distinct role value,
/// never conflated with `kRoleHostel`, so this board (and the legend/header
/// summary that read it) can tell the two apart, which is the entire reason
/// this role exists.
const String kRoleFolk = 'Stay at FOLK';
const String kRoleHostel = 'Stay at Hostel';
const String kRoleLocalite = 'Stay at Localite';

/// FOLK / hostel / localite / unknown split for one guide column.
///
/// ⚠️ **Positive test on every side**, matching `Home/Dashboard.dart:239-243`
/// — the very screen this board is attached to — and the handoff's documented
/// preference. A student whose role is blank or misspelled is counted as
/// `unknown`, never silently swept into FOLK. Step 0 found the codebase
/// genuinely disagrees on blank roles (`Calendar.dart:421` and
/// `submissionReminders.js:77` treat blank as FOLK; `submissionReminders.js
/// :143` and `Dashboard.dart` treat it as neither), so this picks the same
/// side as the screen it lives on and surfaces the remainder rather than
/// hiding it.
///
/// ⚠️ **READ-ONLY.** The board never writes `users.role`.
class ResidenceSplit {
  final int folk;
  final int hostel;
  final int localite;
  final int unknown;

  const ResidenceSplit(
      {required this.folk,
      required this.hostel,
      required this.localite,
      required this.unknown});

  int get total => folk + hostel + localite + unknown;

  /// Reads so that the parts always visibly sum to the whole — an unknown
  /// count is shown rather than left as an unexplained gap.
  String get label => labelFor(female: false);

  /// Same, worded for the females lane ("girls") when [female] is true.
  String labelFor({required bool female}) {
    final one = female ? 'girl' : 'boy';
    final many = female ? 'girls' : 'boys';
    final who = total == 1 ? '1 $one' : '$total $many';
    if (total == 0) return 'No $many';
    final base = '$who — $folk FOLK / $hostel Hostel / $localite Localite';
    if (unknown == 0) return base;
    return '$base / $unknown no role';
  }
}

ResidenceSplit residenceSplit(Iterable<String> roles) {
  var folk = 0;
  var hostel = 0;
  var localite = 0;
  var unknown = 0;
  for (final r in roles) {
    if (r == kRoleFolk) {
      folk++;
    } else if (r == kRoleHostel) {
      hostel++;
    } else if (r == kRoleLocalite) {
      localite++;
    } else {
      unknown++;
    }
  }
  return ResidenceSplit(
      folk: folk, hostel: hostel, localite: localite, unknown: unknown);
}
