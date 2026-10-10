import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Pages/StudentComments.dart';
import '../Pages/StudentProfilePage.dart';
import '../Services/Notifications.dart';
import '../utils/BoardQueries.dart';
import '../utils/BookProgressData.dart';
import '../utils/ColorProvider.dart';
import '../utils/GuideRoster.dart';
import '../utils/SeenMarkers.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentDeletion.dart';
import '../utils/UnseenFeatureBadge.dart';
import 'Calendar.dart';

/// FOLK Boys board workspace — the board CANVAS reached by tapping the one
/// tile on `FolkBoysEntry.dart` (the middle "FOLK Boys" tab's own top-level
/// screen, `utils/BottomNavBar.dart`). Replaces `Home/MainPage.dart`'s old
/// two-tile `DashboardScreen`, `Home/Dashboard.dart` ("All Boys Sadhana"),
/// `Pages/BoysProfile.dart` + `Pages/Profile.dart` ("Boys Profile"), and the
/// old `Pages/BoardsHome.dart`/`Pages/BoardView.dart` board feature. See
/// `AllBoysSadhana_BoyProfile_Inventory.md` for the full map of what each of
/// those did and what still needs a new home in later phases.
///
/// ---------------------------------------------------------------------------
/// Guide resolution / FCM registration live in `FolkBoysEntry.dart`, not here
/// ---------------------------------------------------------------------------
/// That plumbing — resolving the guide, redirecting to
/// `FolkGuideSelectionPage` if none, and re-registering the FCM token into
/// `adminUsers/{guide}.fcmToken` (which `Pages/InteractionLogger.dart`'s
/// HOD-notify path depends on) — runs in `FolkBoysEntryScreen.initState`, on
/// TAB ENTRY, before this workspace is ever pushed. This widget is therefore
/// only ever constructed with an already-resolved, non-empty `selectedGuide`.
///
/// ---------------------------------------------------------------------------
/// Layout — REAL side-by-side columns (revert task)
/// ---------------------------------------------------------------------------
/// A prior task replaced this with a row of tap-to-switch column "chips"
/// showing one column at a time. **Rejected by the product owner and
/// reverted.** The canvas is back to a horizontally-scrolling row of
/// columns, each with its own vertically-scrolling card list — the same
/// shape the original hand-rolled `BoardView.dart` always used.
///
/// ---------------------------------------------------------------------------
/// Visibility — deliberately widened this task, column-scoped not query-scoped
/// ---------------------------------------------------------------------------
/// ⚠️ **Changed from the previous rule, on the product owner's explicit,
/// informed decision — not a bug fix.** Previously a non-HOD guide's card
/// query was scoped to `guideId == <their own id>`, which structurally could
/// never include an unassigned student — Unassigned was, correctly per that
/// rule, empty for them. The new rule:
///  * HOD: every guide column + Unassigned (unchanged).
///  * Any other guide: ONLY their own guide column + Unassigned — no other
///    guide's column at all, not even read-only.
///  * Unassigned is visible to literally everyone.
///
/// [_usersQuery] is now unconditionally unfiltered for every viewer — see its
/// own doc comment for why a single equality filter cannot express "mine OR
/// absent", and why fetching unfiltered (not a compound `Filter.or`, not two
/// merged queries) was chosen, given this app's real, documented history of
/// `FAILED_PRECONDITION` errors on compound queries. Privacy is enforced by
/// [_visibleColumns] — which COLUMNS render — not by which documents are
/// fetched.
///
/// ---------------------------------------------------------------------------
/// The mandatory board — reuses `utils/BoardQueries.dart` verbatim (Rule 1)
/// ---------------------------------------------------------------------------
/// Columns = guides (`reconcileGuideColumns`, unchanged), cards = students
/// assembled live from `users` at render time — never duplicated into a
/// placement, same principle the old feature already got right.
///
/// ⚠️ **Reassignment is no longer HOD-only** (product owner's explicit
/// decision) — see [_handleDrop]'s own doc comment for the full permission
/// model: HOD may move anyone anywhere; any other guide may only claim from
/// Unassigned into their own column, or release their own student back to
/// Unassigned. `BoardQueries.canEditBoard`'s `guideAssignment` branch is
/// UNCHANGED (still HOD-only for this board kind) — it governs the generic
/// board-list/open-for-editing check used by [_openBoardSwitcher] and
/// custom boards (Phase 4), not this board's own drag permission, which has
/// its own, narrower rule. [_ensureBoard] runs
/// for any viewer, HOD or not (unlike the old `BoardsHome.dart`, which only
/// bootstrapped it from the HOD's device), since this board is the only view
/// of this whole tab — otherwise a guide who opens the app before the HOD
/// ever has would see an empty screen forever. Idempotent
/// (`_ensuring`/`_ensured` guard, plus `ensureGuideAssignmentBoard` itself
/// no-ops if the board already exists).
///
/// Unassigned column is ALWAYS visible, unconditionally, to everyone — 15 of
/// 17 real students have no `guideId` at all, making it the single most
/// important column on the board.
///
/// ---------------------------------------------------------------------------
/// Card face
/// ---------------------------------------------------------------------------
/// Name + THREE action icons — left-to-right: calendar, comment, profile —
/// plus an expand chevron. All three are wired: calendar (pushes the
/// existing, UNCHANGED `CalendarPage`), comment (opens the existing,
/// UNCHANGED `showStudentCommentsDialog`) and profile (opens
/// `Pages/StudentProfilePage.dart`). Tapping the card body (not an icon)
/// expands it into real book progress + the chanting commitment — see
/// [_expandedDetail].
///
/// ⚠️ **The fourth ("scoring") placeholder icon was REMOVED this task.** It
/// was a Phase 1 stand-in (`Icons.bar_chart`, `onTap: null`) for a scoring
/// destination that was never built as its own page — `StudentProfilePage`
/// grew to carry both real score cards instead (Phase 4/5), leaving the
/// placeholder pure dead weight that rendered permanently greyed and read as
/// a broken button rather than an inert one. Removed rather than left inert,
/// since there is no longer any real destination it was ever a stand-in for.
///
/// ⚠️ **Residence tint (Phase 2, Part 2)**: each card is lightly tinted by
/// `role` — see [_residenceTint] for the exact colours and why they were
/// chosen, and [_residenceLegend] for the one-line legend that replaced the
/// removed diagnostic banner's position at the top of the board.
///
/// ⚠️ **Confirmed consequence of the comment icon's unchanged access rule
/// (Phase 2, Part 4)**: `showStudentCommentsDialog`'s own `_canAccess`
/// (`Pages/StudentComments.dart`) is HOD-always / guide-only-on-their-own
/// student, tested against `studentGuideId`. For an unassigned student that
/// value is `""`, which fails `studentGuideId.isNotEmpty` — so a non-HOD
/// guide who taps Comments on an Unassigned card (now visible to them since
/// this file's earlier visibility change) sees that dialog's own "This
/// student is not assigned to you" lock state, not an error. This is a real,
/// user-facing consequence of two separately-made decisions (wider board
/// visibility, unchanged comment scoping) that were never reconciled against
/// each other until now — flagged here rather than silently accepted, but
/// NOT changed, since `StudentComments.dart`'s own access rule was explicitly
/// out of scope for this task ("Preserve its exact `_canAccess` permission
/// gate").
///
/// ⚠️ The "Move to guide" menu and the on-screen gesture debug overlay that
/// existed briefly in the chip-layout attempt have both been REMOVED
/// entirely per the product owner's explicit rejection — reassignment
/// happens by dragging a card onto a column, full stop (see [_handleDrop]
/// for who is now allowed to drag what).
///
/// ---------------------------------------------------------------------------
/// Drag — real investigation into "was a package ever used", this task
/// ---------------------------------------------------------------------------
/// The product owner stated drag previously worked using a Flutter package.
/// Checked for real, not assumed: `pubspec.yaml` (both apps) and
/// `pubspec.lock` (both apps) contain no drag/board/kanban package, ever;
/// every `import 'package:...'` across every file in both apps' `lib/`
/// directories was enumerated and contains no such package either; and this
/// project's own `CLAUDE_PROGRESS.md` explicitly documents, from when the
/// board was first built, that `appflowy_board` was evaluated and DECLINED
/// (dual AGPL-3.0/MPL-2.0 licence, 28 months stale at the time) and that the
/// board was "Built instead on Flutter's own `LongPressDraggable`/
/// `DragTarget`." No prior working package-based implementation exists
/// anywhere in this repository's history to restore. Flutter's own
/// `ReorderableListView` was also checked — it robustly solves drag
/// WITHIN one list (and does have the correctly-designed internal arena
/// handling and edge auto-scroll the product owner may be thinking of), but
/// it does not natively support dragging an item OUT of one list and INTO a
/// different one, which is this board's actual requirement — so it cannot
/// be dropped in as a replacement here.
///
/// **Attempt #4 (a dedicated drag handle, grounded in
/// `ReorderableDragStartListener`'s own documented pattern) was built, then
/// REMOVED this task at the product owner's explicit request — whole-card
/// long-press is back.** The reason: a real device diagnostic this task
/// showed `guide="FOLK" isHod=false`, and [_handleDrop] began with a blanket
/// `if (!_isHod) return;` — meaning every one of attempts 2 through 4 was
/// being silently swallowed by the PERMISSION gate before any gesture code
/// ran at all, on the one device that was actually testing this. The real
/// fix this task is the permission model in [_handleDrop] (a non-HOD guide
/// may now claim/release), not another gesture change. Kept from attempt
/// #4 regardless, because it was grounded in real Flutter source, not
/// premise-dependent on the handle: `_scrollLocked` arms in `onDragStarted`
/// (after the drag has already won the arena), never on pointer-down —
/// direct inspection of `Scrollable`/`ScrollPosition` source showed
/// `NeverScrollableScrollPhysics` never withdraws a Scrollable's recognizer
/// from the arena, so locking pre-emptively could never have helped. If
/// whole-card long-press still loses the arena on a real device once the
/// permission fix is confirmed, the most likely remaining cause is genuine
/// finger jitter past `kTouchSlop` during the hold on a large tap surface —
/// a real, named risk, not silently ignored, but intentionally not
/// addressed with a fifth speculative gesture change until the permission
/// fix itself is device-tested.
///
/// ---------------------------------------------------------------------------
/// (Historical) the diagnostic banner that found the real root cause
/// ---------------------------------------------------------------------------
/// A temporary on-screen banner lived in [_board] for two tasks, printing the
/// resolved `_guide`, `_isHod`, and live bucketing counts. It is what actually
/// surfaced this file's real bug: on the real test device it read
/// `guide="FOLK" isHod=false`, proving the drag gesture was never the
/// problem — the old blanket `if (!_isHod) return;` permission gate was.
/// **Removed this task** (Phase 2, Part 1) now that the permission model is
/// confirmed working on a real device — `_lastDropStatus`/`_recordDropStatus`
/// and the banner `Container` are gone; nothing about `_handleDrop`'s actual
/// behaviour changed when they were removed, only the status-reporting calls
/// came out.
class FolkBoysWorkspace extends StatefulWidget {
  /// Already resolved by `FolkBoysEntryScreen` before this widget is ever
  /// pushed — never null/empty here.
  final String selectedGuide;

  const FolkBoysWorkspace({super.key, required this.selectedGuide});

  @override
  State<FolkBoysWorkspace> createState() => _FolkBoysWorkspaceState();
}

/// What kind of move `_handleDrop` is actually performing — drives the
/// confirmation dialog's wording, per this task's explicit instruction that
/// a guide releasing their own student still needs the same visibility /
/// notification warning an HOD reassignment gets, worded for what actually
/// happened.
enum _MoveKind { hodReassign, claim, release }

/// A student, as the board needs them. Assembled at render time from
/// `users`; never persisted into a placement — same principle
/// `utils/BoardQueries.dart` already documents for the old feature.
class _Boy {
  final String uid;
  final String name;
  final String role;
  final String guideId;

  /// Manually-added ("offline roster") student — no auth account yet,
  /// recorded by a guide. See `utils/ManualStudents.dart`'s own header.
  /// Part 5, this task: badged on the card face (`_cardBody`) so a guide
  /// can always tell a guide-entered student from an app-registered one.
  final bool isManualEntry;

  const _Boy({
    required this.uid,
    required this.name,
    required this.role,
    required this.guideId,
    this.isManualEntry = false,
  });
}

class _FolkBoysWorkspaceState extends State<FolkBoysWorkspace> {
  /// History: 300 -> 340 (fourth/profile icon added, Phase 3) -> 365 (icons
  /// enlarged 30x30 -> 34x34 + 3px gaps added, to investigate a dull/
  /// unresponsive-icon report) -> **328, this task** (the scoring placeholder
  /// icon removed, back down to three icons).
  ///
  /// Computed directly from the 365 figure's own accounting rather than
  /// re-derived from scratch: 365 = 340 baseline + `4*(34-30)=16px` (icon
  /// growth) + `3*3=9px` (three gaps between four icons). Removing one icon
  /// removes its own 34px box AND one of the three gaps (four icons have
  /// three gaps between them; three icons have only two) —
  /// `365 - 34 - 3 = 328`. Sanity-checked against the row's own fixed
  /// content: avatar(30) + spacing(8) + 3 icons(3*34=102) + 2 gaps(2*3=6) +
  /// chevron(~20-24) ≈ 170px fixed, leaving ≈118px for the name inside a
  /// 328px column (minus ~40px of padding/border) — comfortably more room
  /// than the four-icon layouts ever had, not less.
  ///
  /// ⚠️ **Scroll comfort, by construction (Rule 7 — no device run):** a
  /// narrower column means a LARGER slice of the next column peeks in on
  /// small phones than either the 340 or 365 steps had — the opposite
  /// direction of the tightening those two steps kept flagging. This
  /// specifically undoes the flagged narrowing from wider layouts, per this
  /// task's own stated intent (helps smaller phones), though the actual
  /// on-screen result is still Rule-7-unverified.
  static const double _columnWidth = 328;

  final ScrollController _hController = ScrollController();

  static const double _edgeZone = 76;
  static const double _maxScrollStep = 14;
  DragUpdateDetails? _lastDragDetails;
  bool _autoScrolling = false;

  /// True only while a drag is actually in progress (set in
  /// `_dragHandle`'s `onDragStarted`, cleared on end/cancel/complete) — used
  /// to freeze both ancestor `ListView`s' user-driven scrolling so they
  /// don't fight the finger while a card is being dragged across columns.
  ///
  /// History: four attempts at making a card actually drag on a real device.
  ///  1. `InkWell`-wrapped tap-to-expand inside `LongPressDraggable.child` —
  ///     cards never lifted. `InkWell`'s own tap recognizer consumed the
  ///     pointer before the drag recognizer's delay ever elapsed.
  ///  2. Replaced `InkWell` with a plain `GestureDetector` — correct on its
  ///     own terms, still failed. This board's horizontal `ListView` of
  ///     columns and each column's own vertical `ListView` are BOTH
  ///     ancestors of a card's `LongPressDraggable`; either one's own
  ///     drag-to-scroll recognizer can win the arena from a few pixels of
  ///     incidental movement during the long-press hold, before the 500ms
  ///     delay elapses.
  ///  3. Locked both ancestor Scrollables to `NeverScrollableScrollPhysics`
  ///     on pointer-DOWN, hoping to remove them from the arena before the
  ///     drag recognizer had to compete. **This premise was wrong.** Direct
  ///     inspection of Flutter's own `Scrollable`/`ScrollPosition` source
  ///     this task shows a Scrollable's drag recognizer is created based on
  ///     `setCanDrag` (driven by whether there is scrollable content), not
  ///     by `physics` — `NeverScrollableScrollPhysics` only makes an
  ///     already-won drag a no-op, it never withdraws the Scrollable from
  ///     arena competition. The lock could not have been what made drag work
  ///     or fail.
  ///  4. **This fix** — per [_dragHandle]'s own doc comment, drag is now
  ///     isolated to a small dedicated handle icon (matching how Flutter's
  ///     own `ReorderableDragStartListener` is documented to be used), which
  ///     removes the card's tap recognizer from the arena entirely and gives
  ///     a small, low-jitter target instead of the whole card face. This
  ///     field's lock is now armed correctly too — only once the drag has
  ///     already been won (`onDragStarted`), which is the actual purpose
  ///     `ReorderableListView` itself uses a physics-lock for: freezing the
  ///     list under an in-progress drag, not trying to pre-emptively win a
  ///     contest physics cannot influence.
  bool _scrollLocked = false;

  bool _ensuring = false;
  bool _ensured = false;
  bool _reconciling = false;

  /// Which board is showing — Phase 4. `null` means the mandatory
  /// `guideAssignment` board (`_board()`, entirely UNCHANGED this task). A
  /// non-null value is a custom board's id, rendered by [_customBoardBody]
  /// instead — a completely separate code path that never touches
  /// `_board()`, `_canvas()`, `_columnTile()`, `_handleDrop()`,
  /// `_usersQuery()` or `_visibleColumns()`.
  String? _activeBoardId;

  /// Which student cards are expanded.
  final Set<String> _expandedUids = {};

  /// Which of a card's three level sub-dropdowns are expanded, keyed
  /// `"${uid}_$level"` (Phase 2, Part 3).
  final Set<String> _expandedLevels = {};

  /// The book config (`books/level-1..3` + link availability) — the SAME
  /// three documents `Pages/BooksProgress.dart` reads, loaded via the shared
  /// `loadBooksConfig()` (see `utils/BookProgressData.dart`'s header for why
  /// this is a shared file, not a second copy). It is identical for every
  /// student, so it is fetched at most ONCE for this whole board (lazily, on
  /// the first card any guide expands — see [_booksSection]), never
  /// per-student and never for a card that stays collapsed.
  Future<BooksConfig>? _booksConfigFuture;

  String get _guide => widget.selectedGuide;

  /// ⚠️ **Normalised comparison.** A live Firestore + code trace this session
  /// found that [_usersQuery] was never actually the reason Unassigned
  /// looked empty for the HOD (that query is now unconditional — see its own
  /// doc comment); the trim/lower-case normalisation here is kept regardless
  /// because it is a genuine, if narrower, hardening: `_guide` ultimately
  /// comes from `SharedPreferences['selected_guide']`
  /// (`Services/UpdateFCM.dart`), and a stale value saved with different
  /// casing or incidental whitespace by an older build would otherwise fail
  /// a bare `==` against the literal constant [kHodGuideId] silently and
  /// permanently. What normalisation CANNOT fix is a device genuinely, and
  /// correctly, signed in as a different guide (e.g. testing as `AMHD`) —
  /// that is not a bug, it is [_isHod] doing exactly what it should. The
  /// temporary diagnostic banner in [_board] exists to tell the two apart on
  /// a real device.
  bool get _isHod =>
      _guide.trim().toLowerCase() == kHodGuideId.trim().toLowerCase();

  @override
  void dispose() {
    _hController.dispose();
    super.dispose();
  }

  /// ⚠️ **Deliberately unfiltered for every viewer, HOD or not — a visibility
  /// rule change, not a bug fix.** The product owner explicitly widened
  /// column visibility this task: a regular guide now sees their own column
  /// **plus Unassigned** (previously they saw only their own students and
  /// Unassigned was structurally unreachable for them). A single
  /// `.where('guideId', isEqualTo: _guide)` equality filter cannot express
  /// "mine OR absent" — Firestore has no "field does not exist" filter, and
  /// the real data confirms `guideId` is absent (not `null`, not `""`) on
  /// every unassigned student, so an `isEqualTo: null`/`isEqualTo: ''`
  /// filter would not match them either.
  ///
  /// The real options were: (a) fetch unfiltered and bucket in Dart, (b) two
  /// separate queries merged client-side, (c) a Firestore `Filter.or`
  /// compound query. (a) is what this file now does, because: the roster is
  /// 17 students total (Step 0's own real-data probe) — there is no scale
  /// concern; a single unfiltered `.get()`/`.snapshots()` needs **no
  /// composite index at all**, which matters in this codebase specifically —
  /// `FOLK_HANDOFF.md` records a real `FAILED_PRECONDITION` from a prior
  /// compound query, and every other query in this app deliberately stays to
  /// one equality filter or none for exactly that reason; a `Filter.or`
  /// here would very likely hit the same wall. **Privacy is now enforced by
  /// which COLUMNS are rendered** (see [_visibleColumns]), not by which
  /// documents are fetched — consistent with this app's existing trust
  /// model (`utils/GuideRoster.dart`'s own header: "Firestore security rules
  /// are still the only thing that could actually enforce" any of this;
  /// there were none in source before this change and there are none after).
  Query<Map<String, dynamic>> _usersQuery() =>
      FirebaseFirestore.instance.collection('users');

  /// The new visibility rule (this task, deliberate product decision):
  ///  * HOD: every guide column + Unassigned.
  ///  * Any other guide: ONLY their own guide column + Unassigned. No other
  ///    guide's column, even read-only — it is not rendered at all.
  ///  * Unassigned is visible to literally everyone.
  List<BoardColumn> _visibleColumns(List<BoardColumn> all) {
    if (_isHod) return all;
    return all
        .where((c) =>
            c.kind == kColumnKindUnassigned ||
            (c.isGuideColumn && c.guideId == _guide))
        .toList();
  }

  Future<void> _ensureBoard(List<BoardDoc> all, String guide) async {
    if (_ensuring || _ensured) return;
    _ensuring = true;
    try {
      // Deliberately unconditional, not HOD-gated — see this file's header.
      await ensureGuideAssignmentBoard(all: all, hodGuide: guide);
      _ensured = true;
    } catch (_) {
      // Next rebuild retries.
    }
    _ensuring = false;
  }

  // ---------------------------------------------------------------------------
  // Edge auto-scroll — ported unchanged from the old BoardView.dart. Needed
  // again now that columns are genuinely side-by-side and a card may need to
  // travel to an off-screen column.
  // ---------------------------------------------------------------------------

  void _onDragUpdate(DragUpdateDetails details) {
    _lastDragDetails = details;
    if (!_autoScrolling) _tickEdgeScroll();
  }

  void _tickEdgeScroll() {
    final details = _lastDragDetails;
    if (details == null || !_hController.hasClients || !mounted) {
      _autoScrolling = false;
      return;
    }

    final width = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;

    double delta = 0;
    if (x < _edgeZone) {
      delta = -_maxScrollStep * ((_edgeZone - x) / _edgeZone).clamp(0.0, 1.0);
    } else if (x > width - _edgeZone) {
      delta = _maxScrollStep *
          ((x - (width - _edgeZone)) / _edgeZone).clamp(0.0, 1.0);
    }

    if (delta == 0) {
      _autoScrolling = false;
      return;
    }

    _autoScrolling = true;
    final max = _hController.position.maxScrollExtent;
    final target = (_hController.offset + delta).clamp(0.0, max);
    if (target != _hController.offset) {
      _hController.jumpTo(target);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _tickEdgeScroll());
  }

  void _stopEdgeScroll() {
    _lastDragDetails = null;
    _autoScrolling = false;
  }

  // ---------------------------------------------------------------------------
  // Scroll lock — see `_scrollLocked`'s own doc comment for the full history.
  // ---------------------------------------------------------------------------

  void _lockScroll() {
    if (!_scrollLocked && mounted) setState(() => _scrollLocked = true);
  }

  void _unlockScroll() {
    if (_scrollLocked && mounted) setState(() => _scrollLocked = false);
  }

  // ---------------------------------------------------------------------------
  // Reassignment — the ONE write path. Ported from the old BoardView.dart's
  // guide-assignment branch.
  // ---------------------------------------------------------------------------

  /// ⚠️ **Permission model — changed this task, on the product owner's
  /// explicit decision.** Previously HOD-only, full stop. Now:
  ///  * HOD: may move any student between any two columns — unchanged.
  ///  * Any other guide: may CLAIM (move a student from Unassigned into
  ///    their own column) or RELEASE (move their own student back to
  ///    Unassigned). Any other move — including into or out of a DIFFERENT
  ///    guide's column — is rejected.
  ///
  /// ⚠️ **This check is enforced here regardless of what the UI already
  /// prevents, and that enforcement is real, not decorative.**
  /// [_visibleColumns] means a non-HOD guide never even sees a `DragTarget`
  /// for another guide's column, so in the ACTUAL running UI this method can
  /// only ever be reached with a claim, a release, or an HOD move — but that
  /// is a client-side UI restriction, exactly like every other permission in
  /// this app (`utils/GuideRoster.dart`'s own header: there is no real
  /// authentication and no Firestore security rule backing any of this).
  /// Nothing stops a modified client from calling this method directly with
  /// an arbitrary target, so the rule is re-checked here as the actual
  /// authority, not assumed from what the widget tree happens to offer.
  Future<void> _handleDrop({
    required String boardId,
    required _Boy boy,
    required BoardColumn target,
    required int orderInTarget,
  }) async {
    final oldGuide = boy.guideId.trim();
    final newGuide =
        target.kind == kColumnKindUnassigned ? null : target.guideId;
    final normalisedOld = oldGuide.isEmpty ? null : oldGuide;

    if (normalisedOld == newGuide) return;

    final _MoveKind moveKind;
    if (_isHod) {
      moveKind = _MoveKind.hodReassign;
    } else {
      final isClaim = normalisedOld == null && newGuide == _guide;
      final isRelease = normalisedOld == _guide && newGuide == null;
      if (!isClaim && !isRelease) return;
      moveKind = isClaim ? _MoveKind.claim : _MoveKind.release;
    }

    final confirmed = await _confirmReassignment(
      boy: boy,
      fromGuide: normalisedOld,
      toGuide: newGuide,
      moveKind: moveKind,
    );
    if (confirmed != true) return;

    try {
      await reassignGuide(
        boardId: boardId,
        studentUid: boy.uid,
        newGuideId: newGuide,
        columnId: target.id,
        order: orderInTarget,
        movedBy: _guide,
      );
      if (!mounted) return;
      showSnackbar(
        context,
        newGuide == null
            ? "${boy.name} is now unassigned"
            : "${boy.name} reassigned to $newGuide",
        Colors.green,
        Icons.check_circle,
      );
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not reassign", Colors.red, Icons.error);
    }
  }

  /// The reassignment guard — body wording (name, from/to rows, the amber
  /// warning) reused unchanged from the old `BoardView.dart._confirmReassignment`
  /// per the product owner's explicit instruction ("it already correctly
  /// warns about visibility and notification routing"), including for a
  /// non-HOD's own claim/release — that warning is just as true when a guide
  /// is moving their own student. Only the title and the action button now
  /// vary with [moveKind], so the dialog says what is actually happening.
  Future<bool?> _confirmReassignment({
    required _Boy boy,
    required String? fromGuide,
    required String? toGuide,
    required _MoveKind moveKind,
  }) {
    final from = fromGuide ?? "no guide (Unassigned)";
    final to = toGuide ?? "no guide (Unassigned)";

    final String title;
    final String actionLabel;
    switch (moveKind) {
      case _MoveKind.claim:
        title = "Claim this boy?";
        actionLabel = "Claim";
        break;
      case _MoveKind.release:
        title = "Release this boy?";
        actionLabel = "Release";
        break;
      case _MoveKind.hodReassign:
        title = "Reassign this boy?";
        actionLabel = "Reassign";
        break;
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                boy.name,
                style:
                    const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _fromToRow("Currently with", from, Colors.grey.shade700),
              const SizedBox(height: 6),
              _fromToRow("Moving to", to, const Color(0xFF00695C)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Text(
                  "This changes who can see his private information and who "
                  "receives his notifications from now on.\n\n"
                  "His existing history stays with $from — past associations, "
                  "flagged messages, LIT assessments and interaction logs do "
                  "NOT transfer. Nothing already recorded is moved, copied or "
                  "deleted.",
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00695C)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionLabel, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _fromToRow(String label, String value, Color colour) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: colour),
          ),
        ),
      ],
    );
  }

  _Boy? _findBoy(List<_Boy> boys, String uid) {
    for (final b in boys) {
      if (b.uid == uid) return b;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Drag-to-delete — this task. Extends the existing drag, does not touch it.
  // ---------------------------------------------------------------------------

  /// ⚠️ **Does not modify `LongPressDraggable`, `onDragStarted`,
  /// `_lockScroll`/`_unlockScroll`, or anything about the drag that took five
  /// rounds to get working.** This target is just another `DragTarget<String>`
  /// — the same generic type every column already uses — reading the SAME
  /// `_scrollLocked` flag those columns' physics already reads, purely to
  /// decide whether to render at all. `_scrollLocked` is already true for
  /// exactly the span the task wants ("appears on drag start, disappears on
  /// drag end") because that is precisely what it already means — no new
  /// state was added to make this work.
  Widget _trashTarget({required List<_Boy> allBoys}) {
    if (!_scrollLocked) return const SizedBox.shrink();

    return DragTarget<String>(
      // Accept the hover for everyone — the real permission check happens on
      // drop, in `_handleDeleteDrop`, exactly like reassignment's own
      // `_handleDrop`. Rejecting the hover here would only hide the refusal
      // message, not add real enforcement — see `_handleDeleteDrop`'s own
      // doc comment for why the check is repeated there as the actual
      // authority.
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final boy = _findBoy(allBoys, details.data);
        if (boy == null) return;
        _handleDeleteDrop(boy);
      },
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: hovering ? Colors.red.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering ? Colors.red.shade400 : Colors.grey.shade300,
              width: hovering ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_forever,
                  color: hovering ? Colors.red.shade700 : Colors.grey.shade500),
              const SizedBox(width: 8),
              Text(
                hovering
                    ? "Release to delete permanently"
                    : "Drop here to delete permanently",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color:
                      hovering ? Colors.red.shade700 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// ⚠️ **Permission model — deliberately re-checked here, not trusted from
  /// the UI.** HOD may delete anyone. A non-HOD guide may delete only a
  /// student currently assigned to them — an unassigned student
  /// (`boy.guideId` empty) or another guide's student both fail this check
  /// and are refused with a clear reason, never silently ignored. This is
  /// client-side only, exactly like `_handleDrop`'s own reassignment
  /// permission and every other rule in this app (no Firestore security
  /// rules exist in source) — stated plainly, not implied.
  Future<void> _handleDeleteDrop(_Boy boy) async {
    if (!_isHod && boy.guideId != _guide) {
      if (!mounted) return;
      showSnackbar(
        context,
        boy.guideId.isEmpty
            ? "${boy.name} is unassigned — only the HOD can delete an "
                "unassigned student."
            : "${boy.name} is not your student — only the HOD or their own "
                "guide can delete them.",
        Colors.red,
        Icons.block,
      );
      return;
    }

    final confirmed = await _confirmPermanentDelete(boy);
    if (confirmed != true) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // guideId/isHod no longer passed (Master Task, 2026-09-14) — the
    // Cloud Function derives the caller's own identity server-side now,
    // from their locked, email-resolved adminUsers record.
    final result = await deleteStudentEverywhere(uid: boy.uid, name: boy.name);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close the spinner
    await _showDeletionResult(boy: boy, result: result);
  }

  /// A single normal dialog, no name-typing required — states the deletion
  /// is permanent and, as of Master Task 2026-09-14, that it now also
  /// removes the student's sign-in (Firebase Authentication) account —
  /// `utils/StudentDeletion.dart`'s own header covers the ordering and what
  /// happens if that half specifically fails.
  Future<bool?> _confirmPermanentDelete(_Boy boy) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete this boy permanently?"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                boy.name,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  "This permanently deletes ALL of ${boy.name}'s data — "
                  "sadhana reports, scores, book progress, LIT assessments, "
                  "interaction logs, comments, friends and everything else "
                  "recorded about him across this app — AND his sign-in "
                  "account (Firebase Authentication). This CANNOT be "
                  "undone. If he returns, he will need to register again "
                  "from scratch.",
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete permanently",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Reports exactly what happened — a name-collision refusal, a full
  /// success naming what was removed, or a partial failure naming precisely
  /// which steps failed so nothing is silently swallowed. Every step in
  /// `deleteStudentEverywhere` is idempotent, so retrying after a partial
  /// failure is always safe — stated here so a guide seeing a partial
  /// failure knows retry is the right next action, not something riskier.
  Future<void> _showDeletionResult({
    required _Boy boy,
    required StudentDeletionResult result,
  }) {
    if (result.refused) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Deletion refused"),
          content: Text(result.refusalReason ??
              "Could not verify this deletion is safe to run."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
          ],
        ),
      );
    }

    final failed = result.steps.where((s) => s.failed).toList();
    final removed = result.steps
        .where((s) => !s.failed && (s.removedCount ?? 0) > 0)
        .toList();
    // Master Task, 2026-09-14, Part 2.4 — the Auth-deletion outcome is a
    // real, verifiable result too, not folded silently into "removed"/
    // "failed" above (it isn't a Firestore step) and never hidden even on
    // an otherwise-complete success.
    final authFailedSoftly = result.authResult?.failed ?? false;

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          failed.isEmpty && !authFailedSoftly
              ? "${boy.name} deleted"
              : "Deletion partly failed",
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(builder: (_) {
                final auth = result.authResult;
                if (auth == null) return const SizedBox.shrink();
                final String line;
                final Color color;
                if (auth.deleted) {
                  line = "Sign-in account (Firebase Authentication): removed";
                  color = Colors.black87;
                } else if (auth.hadNoAuthAccount) {
                  line = "Sign-in account: none existed (manual entry, or "
                      "already removed)";
                  color = Colors.black87;
                } else {
                  line = "⚠️ Sign-in account could NOT be removed: "
                      "${auth.error}. His data has still been deleted below "
                      "— if he signs in again, he will be treated as a new "
                      "registration.";
                  color = Colors.red.shade700;
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(line,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: color)),
                );
              }),
              if (removed.isNotEmpty) ...[
                const Text("Removed:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...removed.map((s) => Text(
                    "• ${s.label} (${s.removedCount})",
                    style: const TextStyle(fontSize: 12.5))),
                const SizedBox(height: 10),
              ],
              if (failed.isNotEmpty) ...[
                Text(
                  "Failed — safe to retry, nothing here is destructive "
                  "twice:",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red.shade700),
                ),
                const SizedBox(height: 4),
                ...failed.map((s) => Text(
                      "• ${s.label}: ${s.error}",
                      style:
                          TextStyle(fontSize: 12.5, color: Colors.red.shade700),
                    )),
                const SizedBox(height: 10),
              ],
              const Divider(),
              const SizedBox(height: 4),
              Text(
                "Not automatically cleaned up (see the deletion feature's "
                "own documentation for why):",
                style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              ...result.notFullyScrubbed.map((s) => Text(
                    "• $s",
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Residence colours — Phase 2, Part 2.
  // ---------------------------------------------------------------------------

  /// Card tint by residence. `null` (rendered as plain white, today's exact
  /// appearance) for a missing or unexpected `role` — never a crash, and the
  /// card itself is never hidden, only left untinted. Matches
  /// `BoardQueries.residenceSplit`'s own "unknown, never guessed" rule for
  /// the same field.
  ///
  /// ⚠️ **Colour choice**: both are Material `shade50` — the palette's
  /// lightest, lowest-saturation step, already used elsewhere in this app for
  /// exactly this "sits behind text, must not fight it" role. FOLK keeps
  /// `Colors.teal.shade50` — teal is this board's own established brand
  /// colour, `Color(0xFF00695C)`, used throughout this file's dialogs/FAB and
  /// the first entry in `BoardQueries.kColumnPalette`.
  ///
  /// ⚠️ **Hostel changed this task (Phase 3, Part 1) from blue to purple**,
  /// per the product owner's explicit request, in the family of this app's
  /// real brand purple `Color(0xFF6647B8)` — confirmed to actually exist
  /// elsewhere in this codebase (`Students/.../BookPageList.dart:844`, the
  /// Student app's own book-reader accent), not invented for this task.
  /// `Colors.deepPurple.shade50` is used rather than a hand-picked hex: a
  /// same-lightness comparison against `Colors.teal.shade50` (~12% brand
  /// colour blended into white) applied to `0xFF6647B8` at that same ~12%
  /// blend works out to `Color(0xFFEDE9F6)` — matching Material's real
  /// `Colors.deepPurple.shade50` (`0xFFEDE7F6`) to within rounding. So the
  /// named Material swatch already IS the correctly-blended light shade of
  /// this app's actual brand purple, not just a same-family approximation.
  ///
  /// ⚠️ **Localite added Master Task 2026-09-03** — `Colors.red.shade50`,
  /// the same "lightest, lowest-saturation Material step" rule as the other
  /// two, in the one hue neither FOLK (teal) nor Hostel (purple) already
  /// uses, per the product owner's explicit "red tint" request. Contrast
  /// against this card's own body text colour (`Colors.black87`, unchanged
  /// by this task) computed with the real WCAG relative-luminance formula,
  /// not estimated: `#FFEBEE` (red.shade50) behind `black87` is **14.30:1**
  /// — comfortably clear of WCAG AA's 4.5:1 for normal text, and in the same
  /// range as the other two computed the same way (teal.shade50 14.14:1,
  /// deepPurple.shade50 13.57:1). All three are effectively
  /// indistinguishable in practice, exactly the "soft, low-saturation, sits
  /// behind text" property the other two were already chosen for.
  Color? _residenceTint(String role) {
    if (role == kRoleFolk) return Colors.teal.shade50;
    if (role == kRoleHostel) return Colors.deepPurple.shade50;
    if (role == kRoleLocalite) return Colors.red.shade50;
    return null;
  }

  /// A single-line legend, replacing the removed diagnostic banner's
  /// position so the board does not gain vertical clutter (Phase 2, Part 2
  /// item 3).
  ///
  /// ⚠️ **Theme check, by construction, since the app cannot be run (Rule
  /// 7):** this legend sits directly on the `Scaffold`'s own
  /// `colorProvider.color` background, which DOES flip between white and
  /// `black87` with the theme toggle — unlike the student cards themselves,
  /// which are already hardcoded `Colors.white` regardless of theme (a
  /// pre-existing choice, unchanged by this task). So the legend's own
  /// swatch outlines and text use `colorProvider.secondColor` (black in
  /// light mode, white in dark mode — the same pair every AppBar/title in
  /// this file already uses), while the swatch FILLS stay the fixed pastel
  /// tints, exactly matching the fixed-white cards they describe. The card
  /// tints themselves need no dark-mode variant precisely because the cards
  /// they sit on never leave a white background — confirmed by reading the
  /// code, not by a device run.
  Widget _residenceLegend(ColorProvider colorProvider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: Row(
        children: [
          _legendSwatch(
            colorProvider,
            fill: Colors.teal.shade50,
            outline: Colors.teal.shade300,
            label: "FOLK",
          ),
          const SizedBox(width: 16),
          _legendSwatch(
            colorProvider,
            fill: Colors.deepPurple.shade50,
            outline: Colors.deepPurple.shade300,
            label: "Hostel",
          ),
          const SizedBox(width: 16),
          _legendSwatch(
            colorProvider,
            fill: Colors.red.shade50,
            outline: Colors.red.shade300,
            label: "Localite",
          ),
        ],
      ),
    );
  }

  Widget _legendSwatch(
    ColorProvider colorProvider, {
    required Color fill,
    required Color outline,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: outline),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colorProvider.secondColor.withOpacity(.7),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// ⚠️ **Phase 4 — this method now decides mandatory-vs-custom, but does
  /// not change how the mandatory board itself renders at all.** The
  /// `_activeBoardId == null` branch calls `_board(colorProvider, guide)`
  /// exactly as before, byte-for-byte unchanged. A non-null id routes to
  /// [_customBoardBody] instead — a fully separate rendering path. The extra
  /// `allBoardsStream()` listener here (alongside the one `_board()` and
  /// `_customBoardBody()` each already open internally) only drives the
  /// AppBar's title/share-icon; it is not plumbed into either board's own
  /// internals.
  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        final guide = _guide;
        return StreamBuilder<List<BoardDoc>>(
          stream: allBoardsStream(),
          builder: (context, boardsSnap) {
            final allBoards = boardsSnap.data ?? const <BoardDoc>[];
            BoardDoc? activeCustomBoard;
            if (_activeBoardId != null) {
              for (final b in allBoards) {
                if (b.id == _activeBoardId) {
                  activeCustomBoard = b;
                  break;
                }
              }
              // The active board vanished (deleted, or no longer shared with
              // this viewer) — fall back to the mandatory board rather than
              // rendering a dead reference. Scheduled for after this frame,
              // since `setState` cannot run during `build`.
              if (activeCustomBoard == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _activeBoardId != null) {
                    setState(() => _activeBoardId = null);
                  }
                });
              }
            }

            final title = activeCustomBoard == null
                ? "FOLK Boys"
                : (activeCustomBoard.title.isEmpty
                    ? "(untitled)"
                    : activeCustomBoard.title);

            // Share is owner-only — see `isBoardOwner`'s own doc comment for
            // why this is a narrower gate than day-to-day editing.
            final canShare = activeCustomBoard != null &&
                isBoardOwner(board: activeCustomBoard, guide: guide);

            return Scaffold(
              backgroundColor: colorProvider.color,
              // A normal back button: this is a PUSHED page (from
              // `FolkBoysEntryScreen`'s tile), not a bare tab body. `AppBar`
              // supplies the back arrow automatically since
              // `Navigator.canPop(context)` is true here.
              appBar: AppBar(
                elevation: 0,
                backgroundColor: colorProvider.color,
                iconTheme: IconThemeData(color: colorProvider.secondColor),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorProvider.secondColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  if (canShare)
                    IconButton(
                      tooltip: "Share board",
                      icon: Icon(Icons.person_add_alt_1,
                          color: colorProvider.secondColor),
                      onPressed: () =>
                          _shareCustomBoard(activeCustomBoard!, guide),
                    ),
                  // Rename/delete — owner-only (`canShare` is already
                  // `isBoardOwner`, the same narrower gate — see that
                  // function's own doc comment for why these two actions
                  // don't extend to a shared-with collaborator).
                  if (canShare)
                    PopupMenuButton<String>(
                      tooltip: "Board options",
                      icon: Icon(Icons.more_vert,
                          color: colorProvider.secondColor),
                      onSelected: (v) {
                        switch (v) {
                          case 'rename':
                            _renameCustomBoard(activeCustomBoard!);
                          case 'delete':
                            _deleteCustomBoard(activeCustomBoard!, guide);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'rename', child: Text("Rename board")),
                        PopupMenuItem(
                            value: 'delete', child: Text("Delete board")),
                      ],
                    ),
                  // ⚠️ The "Submission status" (fact_check) icon that stood
                  // here (Phase 5, Part 2) was REMOVED this task: it's still
                  // reachable via Folk Analysis -> "Week Planning" ->
                  // "Not submitted today" -> "Open Submission Status"
                  // (`Pages/WeeklyPlanning.dart:325-328`, confirmed live
                  // before removing this icon), and the matching "Semester
                  // goal" flag icon was already removed the task before
                  // this one for the same reason (Guide Targets got its own
                  // permanent tile on the Folk Analysis tab). Removing this
                  // one too de-clutters the AppBar further and avoids a
                  // second, redundant path to a screen already reachable
                  // elsewhere.
                  IconButton(
                    tooltip: "Switch board",
                    icon:
                        Icon(Icons.view_list, color: colorProvider.secondColor),
                    onPressed: () => _openBoardSwitcher(guide),
                  ),
                  // "New board" — moved here from a bottom FAB (which sat
                  // over student cards, overlapping the last row of the
                  // board) into the AppBar as a plain action icon,
                  // matching every other board-management action already
                  // here. No FAB anywhere in this Scaffold anymore.
                  IconButton(
                    tooltip: "New board",
                    icon: Icon(Icons.add, color: colorProvider.secondColor),
                    onPressed: () => _createBoard(guide),
                  ),
                ],
              ),
              body: guide.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          "No guide selected on this device.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colorProvider.secondColor),
                        ),
                      ),
                    )
                  // ⚠️ The `GoalProgressBar` strip that stood here (Phase 5,
                  // Part 2) was REMOVED this task — redundant with the
                  // "Guide Targets" tile on the Folk Analysis tab
                  // (`Pages/Competition.dart`), which is the real navigation
                  // entry point for the same feature. Reverted to calling
                  // `_board`/`_customBoardBody` directly, exactly as before
                  // Phase 5 wrapped this call site — neither method itself
                  // was ever touched.
                  : (_activeBoardId == null
                      ? _board(colorProvider, guide)
                      : _customBoardBody(
                          colorProvider, guide, _activeBoardId!)),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // "New board" + "your boards" (custom-board CRUD/columns/sharing itself is
  // a later phase; this is only creation + open, reusing the old, working
  // flow verbatim per Rule 1)
  // ---------------------------------------------------------------------------

  /// Same prompt-dialog shape as the old `BoardsHome.dart._promptForText`.
  Future<String?> _promptForText({
    required String title,
    required String hint,
    required String initial,
    required String action,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  /// ⚠️ **One prompt, nothing else — this task's Part 1.** A fresh custom
  /// board with NO columns at all, not even Unsorted: `seedColumnTitles`
  /// was already empty before this task, but the OLD call left
  /// `withUnsorted` at its default (`true`), so a board was never actually
  /// blank — it silently got one Unsorted column every time. `withUnsorted:
  /// false` here is the real fix; `seedColumnTitles: const []` is
  /// unchanged, confirming nothing downstream still auto-creates a column
  /// for a custom board.
  ///
  /// On success, navigates straight to the new board (`setState` on
  /// [_activeBoardId] using the id `createBoard` returns) rather than just
  /// showing a snackbar and leaving the viewer wherever they were — the
  /// blank board's own empty state (see `_customCanvas`) is what tells them
  /// what to do next.
  Future<void> _createBoard(String guide) async {
    if (guide.isEmpty) return;

    final title = await _promptForText(
      title: "New board",
      hint: "e.g. Ekadashi outreach",
      initial: '',
      action: "Create",
    );
    if (title == null || title.trim().isEmpty) return;

    try {
      final boardId = await createBoard(
        kind: kBoardKindCustom,
        ownerGuideId: guide,
        title: title.trim(),
        createdBy: guide,
        seedColumnTitles: const [],
        withUnsorted: false,
      );
      if (!mounted) return;
      setState(() => _activeBoardId = boardId);
      showSnackbar(context, "Board created", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
          context, "Could not create the board", Colors.red, Icons.error);
    }
  }

  /// ⚠️ **Phase 4 — replaces the old "Your boards" list that pushed
  /// `BoardViewPage`.** That page is scheduled for Phase 6 deletion and,
  /// per this task's explicit instruction, custom boards now render in THIS
  /// same workspace UI instead. Tapping an entry sets [_activeBoardId] and
  /// pops the sheet — no `Navigator.push` anywhere in this method.
  ///
  /// Lists the mandatory board (HOD only, matching `_board()`'s own
  /// existing HOD gate — a non-HOD never sees an entry for it here either)
  /// plus every custom board `visibleBoards()` returns for this viewer —
  /// own boards and boards explicitly shared with them (Phase 4's
  /// visibility change, see `BoardQueries.visibleBoards`'s own doc comment).
  void _openBoardSwitcher(String guide) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return StreamBuilder<List<BoardDoc>>(
              stream: allBoardsStream(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                // ⚠️ The mandatory board's own tile is found directly from
                // the UNFILTERED list, not from `visibleBoards()` — that
                // function's `isGuideAssignment` branch is HOD-only by
                // design (see its own doc comment), which is correct for
                // deciding whether a generic "boards you own" list should
                // list it, but wrong here: EVERY viewer, HOD or not, must be
                // able to switch back to the mandatory board from inside a
                // custom board, since `_activeBoardId == null` (the
                // mandatory board) is this workspace's own default state for
                // everyone, not an HOD-exclusive destination. The mandatory
                // board's real access control lives entirely inside
                // `_board()` itself (`_usersQuery()`/`_visibleColumns()`),
                // untouched by this list.
                final mandatory =
                    snap.data!.where((b) => b.isGuideAssignment).toList();
                final custom = visibleBoards(
                  all: snap.data!,
                  guide: guide,
                  isHod: _isHod,
                ).where((b) => !b.isGuideAssignment).toList();

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Text(
                      "Boards",
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    ...mandatory.map((b) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: _activeBoardId == null
                              ? Colors.teal.shade50
                              : null,
                          child: ListTile(
                            leading: const Icon(Icons.groups_outlined),
                            title: const Text("Guide Assignment"),
                            subtitle: const Text("The mandatory board"),
                            trailing: _activeBoardId == null
                                ? const Icon(Icons.check, color: Colors.teal)
                                : null,
                            onTap: () {
                              setState(() => _activeBoardId = null);
                              Navigator.pop(sheetContext);
                            },
                          ),
                        )),
                    const SizedBox(height: 8),
                    Text(
                      "Custom boards",
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 6),
                    if (custom.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          "No custom boards yet — tap \"New board\" to "
                          "create one.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    else
                      ...custom.map((b) {
                        final selected = _activeBoardId == b.id;
                        final owned = b.isOwnedBy(guide);
                        final subtitle = owned
                            ? (b.sharedWith.isEmpty
                                ? "Yours"
                                : "Yours · shared with ${b.sharedWith.join(', ')}")
                            : "Shared by ${b.ownerGuideId}";
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: selected ? Colors.teal.shade50 : null,
                          child: ListTile(
                            leading: const Icon(Icons.dashboard_outlined),
                            title:
                                Text(b.title.isEmpty ? "(untitled)" : b.title),
                            subtitle: Text(subtitle),
                            trailing: selected
                                ? const Icon(Icons.check, color: Colors.teal)
                                : null,
                            onTap: () {
                              setState(() => _activeBoardId = b.id);
                              Navigator.pop(sheetContext);
                            },
                          ),
                        );
                      }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Custom board management — Phase 4. Board-level actions (share, rename,
  // delete) and column-level actions, all reusing `utils/BoardQueries.dart`'s
  // existing write functions unchanged. The interaction design (menu-based
  // reorder rather than a header-drag gesture, confirm-before-delete wording)
  // is carried over from the old `Pages/BoardView.dart`, which already built
  // and reasoned through this exact UX — reused as a pattern since that
  // file's methods are private and cannot be imported directly (same
  // situation `utils/BookProgressData.dart` solved by extraction; here the
  // pieces are widget-level UI glue, not shared business logic, so following
  // the same design inline is the Rule 1-consistent choice, matching how
  // `Pages/StudentProfilePage.dart` copied `DobCard`/`infoCard`).
  // ---------------------------------------------------------------------------

  /// Per-person sharing (Phase 4, Part 4). Lists real guides from
  /// `guideRosterStream()` (reused unchanged) as checkboxes, preselected with
  /// the board's current `sharedWith`. A single overwrite on Save via
  /// `setBoardSharedWith` — owner-only, matching [isBoardOwner]; this method
  /// is only ever reachable from the AppBar's share icon, which is itself
  /// only shown when `isBoardOwner` is true (see `build()`).
  Future<void> _shareCustomBoard(BoardDoc board, String guide) async {
    final roster = await guideRosterStream().first.catchError((_) => <String>[]);
    if (!mounted) return;

    final selected = Set<String>.from(board.sharedWith);
    // A board can never be shared with its own owner — that guide already
    // has full access by ownership, and including them would be meaningless.
    final choices = roster.where((g) => g != guide).toList();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Share this board"),
          content: SizedBox(
            width: double.maxFinite,
            child: choices.isEmpty
                ? const Text("No other guides exist yet to share with.")
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          "Anyone checked gets full control of this board — "
                          "they can move cards, add/rename/delete columns, "
                          "and rename the board itself, the same as you. "
                          "They cannot delete the board or change who it is "
                          "shared with — that stays with you.",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                      ...choices.map((g) => CheckboxListTile(
                            value: selected.contains(g),
                            title: Text(g),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selected.add(g);
                              } else {
                                selected.remove(g);
                              }
                            }),
                          )),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    try {
      await setBoardSharedWith(
          boardId: board.id, sharedWith: selected.toList());
      if (!mounted) return;
      showSnackbar(context, "Sharing updated", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
          context, "Could not update sharing", Colors.red, Icons.error);
    }
  }

  Future<void> _renameCustomBoard(BoardDoc board) async {
    final title = await _promptForText(
      title: "Rename board",
      hint: '',
      initial: board.title,
      action: "Save",
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      await renameBoard(board.id, title.trim());
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not rename", Colors.red, Icons.error);
    }
  }

  /// ⚠️ **Owner-only, re-checked here rather than trusted from the UI** —
  /// same reasoning as every other permission gate in this file: this is
  /// client-side only. A shared-with guide has full day-to-day editing
  /// rights (Part 4 item 4) but NOT this action — see [isBoardOwner]'s own
  /// doc comment for the product owner's stated reasoning.
  Future<void> _deleteCustomBoard(BoardDoc board, String guide) async {
    if (!isBoardOwner(board: board, guide: guide)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete this board?"),
        content: Text(
          "\"${board.title.isEmpty ? '(untitled)' : board.title}\" and all "
          "its columns will be removed. No student record is touched — this "
          "only deletes the board's own organisation.",
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await deleteBoard(board.id);
      if (_activeBoardId == board.id && mounted) {
        setState(() => _activeBoardId = null);
      }
      if (!mounted) return;
      showSnackbar(context, "Board deleted", Colors.deepOrange, Icons.delete);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not delete the board", Colors.red, Icons.error);
    }
  }

  // ---------------------------------------------------------------------------
  // Custom board — column management (add/rename/recolour/reorder/delete),
  // ported as a pattern from the old `Pages/BoardView.dart`, which already
  // built and reasoned through this exact interaction design.
  // ---------------------------------------------------------------------------

  Future<void> _addCustomColumn(String boardId, List<BoardColumn> columns) async {
    final title = await _promptForText(
      title: "New column",
      hint: '',
      initial: '',
      action: "Add",
    );
    if (title == null || title.trim().isEmpty) return;

    final nextOrder = columns
            .where((c) => c.kind != kColumnKindUnassigned)
            .fold<int>(-1, (m, c) => c.order > m ? c.order : m) +
        1;

    try {
      await addColumn(boardId: boardId, title: title.trim(), order: nextOrder);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
          context, "Could not add the column", Colors.red, Icons.error);
    }
  }

  Future<void> _renameCustomColumn(String boardId, BoardColumn column) async {
    final title = await _promptForText(
      title: "Rename column",
      hint: '',
      initial: column.title,
      action: "Save",
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      await renameColumn(boardId, column.id, title.trim());
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not rename", Colors.red, Icons.error);
    }
  }

  /// Menu action, not a header-drag gesture — same reasoning
  /// `Pages/BoardView.dart._shiftColumn` already documented: on a board that
  /// is itself a horizontal scroller, whose cards already claim long-press
  /// for reassignment/placement drag, a THIRD competing gesture would be
  /// unpredictable, and per Rule 7 is exactly the kind of thing that cannot
  /// be verified without running the app. Two explicit taps always do what
  /// they say.
  Future<void> _shiftCustomColumn(
    String boardId,
    List<BoardColumn> columns,
    BoardColumn column,
    int direction,
  ) async {
    final movable =
        columns.where((c) => c.kind != kColumnKindUnassigned).toList();
    final index = movable.indexWhere((c) => c.id == column.id);
    final target = index + direction;
    if (index < 0 || target < 0 || target >= movable.length) return;

    final reordered = List<BoardColumn>.from(movable);
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);

    try {
      await reorderColumns(boardId: boardId, inNewOrder: reordered);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not reorder", Colors.red, Icons.error);
    }
  }

  Future<void> _recolourCustomColumn(String boardId, BoardColumn column) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Column colour"),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: kColumnPalette
              .map((value) => InkWell(
                    onTap: () => Navigator.pop(ctx, value),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(value),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: column.colorValue == value
                              ? Colors.black87
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );

    if (picked == null) return;
    try {
      await recolourColumn(boardId, column.id, picked);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not recolour", Colors.red, Icons.error);
    }
  }

  /// Cards move to Unsorted first — confirmed and preserved from
  /// `Pages/BoardView.dart`/`deleteColumnMovingCardsToUnsorted`'s own
  /// documented reasoning: a placement is only the guide's own opinion about
  /// where a boy sits, so deleting a stage should not force hand-moving
  /// cards first, and Unsorted (permanent, undeletable) is already the
  /// well-defined "no opinion yet" state.
  /// ⚠️ **No Unsorted fallback — this task's Part 2.** Custom boards no
  /// longer have an Unsorted column to relocate cards to, so deleting a
  /// column removes its cards FROM THIS BOARD outright: their placement
  /// documents are deleted, not moved. `deleteColumnMovingCardsToUnsorted`
  /// (`utils/BoardQueries.dart`) is UNCHANGED and remains the mandatory
  /// board's own function — see `_deleteColumn`'s doc comment there (this
  /// custom-board method calls [deleteColumnDeletingPlacements] instead, a
  /// completely separate function). The confirmation dialog says explicitly
  /// that only the BOARD's organisation is affected, never a student
  /// record, so nobody reads "delete" here as deleting a boy.
  Future<void> _deleteCustomColumn({
    required String boardId,
    required BoardColumn column,
    required List<BoardColumn> columns,
    required int cardCount,
    required String guide,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete this list?"),
        content: Text(
          cardCount == 0
              ? "\"${column.title}\" is empty and will be removed."
              : "\"${column.title}\" holds $cardCount "
                  "${cardCount == 1 ? 'boy' : 'boys'}. "
                  "${cardCount == 1 ? 'He' : 'They'} will be removed from "
                  "THIS BOARD only — this does not delete any student, and "
                  "does not affect any other board they may be on.",
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await deleteColumnDeletingPlacements(
        boardId: boardId,
        columnId: column.id,
      );
      if (!mounted) return;
      showSnackbar(context, "List deleted", Colors.deepOrange, Icons.delete);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not delete", Colors.red, Icons.error);
    }
  }

  /// Removes ONE student from this board only. Deletes exactly one document
  /// — `boards/{boardId}/placements/{studentUid}` — via `placementsRef`
  /// (already exported by `utils/BoardQueries.dart`, reused unchanged). The
  /// student's own `users/{uid}` document, and any placement they have on a
  /// DIFFERENT board, are both untouched — stated explicitly in the dialog
  /// so nobody reads this as deleting the boy himself.
  Future<void> _confirmRemoveFromBoard({
    required String boardId,
    required _Boy boy,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Remove ${boy.name} from this board?"),
        content: const Text(
          "This only removes him from THIS board's organisation. His "
          "record, and any other board he's on, are not touched.",
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await placementsRef(boardId).doc(boy.uid).delete();
      if (!mounted) return;
      showSnackbar(
          context, "${boy.name} removed from this board", Colors.deepOrange,
          Icons.remove_circle_outline);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not remove", Colors.red, Icons.error);
    }
  }

  /// The missing capability this task fills — Part 3. Lists every student
  /// [_customBoardEligible] allows for this viewer, EXCLUDING anyone
  /// already placed on this board (Part 3.3 — offering an already-placed
  /// student again would just invite a confusing duplicate selection, since
  /// they already have exactly one placement per board by construction).
  /// Multi-select via checkboxes; "Add" writes one `movePlacement` per
  /// selected student (Part 3.4 — the exact same write path a drag already
  /// uses, not a new one), ordered after the column's current cards.
  void _openAddStudentsPicker({
    required String boardId,
    required BoardColumn column,
    required String guide,
    required int currentCardCount,
  }) {
    final selected = <String>{};

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      FirebaseFirestore.instance.collection('users').snapshots(),
                  builder: (context, userSnap) {
                    if (!userSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: placementsStream(boardId),
                      builder: (context, placeSnap) {
                        final placedUids = (placeSnap.data?.docs ?? [])
                            .map((d) => d.id)
                            .toSet();

                        final candidates = <_Boy>[];
                        for (final doc in userSnap.data!.docs) {
                          if (placedUids.contains(doc.id)) continue;
                          final data = doc.data();
                          final name = (data['name'] ?? '').toString().trim();
                          if (name.isEmpty) continue;
                          final boy = _Boy(
                            uid: doc.id,
                            name: name,
                            role: (data['role'] ?? '').toString(),
                            guideId:
                                (data['guideId'] ?? '').toString().trim(),
                            isManualEntry: data['isManualEntry'] == true,
                          );
                          if (!_customBoardEligible(
                            studentGuideId: boy.guideId,
                            viewerGuide: guide,
                            viewerIsHod: _isHod,
                          )) {
                            continue;
                          }
                          candidates.add(boy);
                        }
                        candidates.sort((a, b) => a.name.compareTo(b.name));

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Center(
                                    child: Container(
                                      width: 42,
                                      height: 4,
                                      margin: const EdgeInsets.only(bottom: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    "Add students to \"${column.title}\"",
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: candidates.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          "No eligible students left to add — "
                                          "either everyone eligible is "
                                          "already on this board, or you have "
                                          "no students of your own yet.",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.grey.shade600),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: scrollController,
                                      itemCount: candidates.length,
                                      itemBuilder: (context, i) {
                                        final boy = candidates[i];
                                        final isSelected =
                                            selected.contains(boy.uid);
                                        return CheckboxListTile(
                                          value: isSelected,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          title: Text(boy.name),
                                          subtitle: boy.isManualEntry
                                              ? Text(
                                                  "Guide-entered · not registered",
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color:
                                                        Colors.orange.shade800,
                                                  ),
                                                )
                                              : null,
                                          onChanged: (v) =>
                                              setSheetState(() {
                                            if (v == true) {
                                              selected.add(boy.uid);
                                            } else {
                                              selected.remove(boy.uid);
                                            }
                                          }),
                                        );
                                      },
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: selected.isEmpty
                                      ? null
                                      : () async {
                                          final uids = selected.toList();
                                          Navigator.pop(sheetContext);
                                          await _addStudentsToColumn(
                                            boardId: boardId,
                                            columnId: column.id,
                                            uids: uids,
                                            startOrder: currentCardCount,
                                            guide: guide,
                                          );
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00695C),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text("Add (${selected.length})"),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  /// Writes one `movePlacement` per selected student — the exact same write
  /// path `_handlePlacementDrop` uses for a drag, reused rather than a new
  /// one, per this task's Part 3.4.
  Future<void> _addStudentsToColumn({
    required String boardId,
    required String columnId,
    required List<String> uids,
    required int startOrder,
    required String guide,
  }) async {
    try {
      for (var i = 0; i < uids.length; i++) {
        await movePlacement(
          boardId: boardId,
          studentUid: uids[i],
          columnId: columnId,
          order: startOrder + i,
          movedBy: guide,
        );
      }
      if (!mounted) return;
      showSnackbar(
        context,
        uids.length == 1
            ? "1 student added"
            : "${uids.length} students added",
        Colors.green,
        Icons.check_circle,
      );
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
          context, "Could not add students", Colors.red, Icons.error);
    }
  }

  Widget _board(ColorProvider colorProvider, String guide) {
    return StreamBuilder<List<BoardDoc>>(
      stream: allBoardsStream(),
      builder: (context, boardsSnap) {
        if (!boardsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = boardsSnap.data!;
        _ensureBoard(all, guide);

        BoardDoc? board;
        for (final b in all) {
          if (b.isGuideAssignment) {
            board = b;
            break;
          }
        }
        if (board == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final boardId = board.id;

        return StreamBuilder<List<BoardColumn>>(
          stream: columnsStream(boardId),
          builder: (context, colSnap) {
            if (!colSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final columns = colSnap.data!;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // ⚠️ THE Unassigned bucketing bug lived here — see
              // `_usersQuery()`/`_isHod`'s own doc comments. When `_isHod`
              // resolves correctly, this returns the FULL, unfiltered
              // `users` collection for the HOD, which is required for
              // `byUnassigned` below to ever contain anything at all — a
              // guide-scoped query can never include a student who isn't
              // assigned to anyone, by construction, regardless of how the
              // Unassigned COLUMN's own visibility is handled.
              stream: _usersQuery().snapshots(),
              builder: (context, userSnap) {
                if (!userSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final boys = <_Boy>[];
                for (final doc in userSnap.data!.docs) {
                  final data = doc.data();
                  final name = (data['name'] ?? '').toString().trim();
                  if (name.isEmpty) continue;
                  boys.add(_Boy(
                    uid: doc.id,
                    name: name,
                    role: (data['role'] ?? '').toString(),
                    guideId: (data['guideId'] ?? '').toString().trim(),
                    isManualEntry: data['isManualEntry'] == true,
                  ));
                }

                return StreamBuilder<List<String>>(
                  // `guideRosterStream()` itself is now adminUsers-only —
                  // `GuideRoster.dart`'s hardcoded seed fallback was removed
                  // entirely, so this board never needed its own private
                  // copy of that read (Rule 1 — one definition, not two
                  // that could drift).
                  stream: guideRosterStream(),
                  builder: (context, rosterSnap) {
                    if (!rosterSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final roster = rosterSnap.data!;

                    // Keeps "a column exists because a guide exists" true by
                    // construction. Never deletes — same rule the old board
                    // shipped with.
                    if (!_reconciling) {
                      _reconciling = true;
                      reconcileGuideColumns(
                        boardId: boardId,
                        roster: roster,
                        existing: columns,
                      ).whenComplete(() => _reconciling = false);
                    }

                    // Every student with no guideId at all (missing field OR
                    // empty/whitespace-only string, both normalised to ''
                    // above) lands here — ALWAYS shown, to everyone,
                    // unconditionally (Part 1 of the prior task, kept).
                    final byUnassigned =
                        boys.where((b) => b.guideId.isEmpty).toList();

                    // New visibility rule this task — see [_visibleColumns].
                    final visibleColumns = _visibleColumns(columns);

                    return Column(
                      children: [
                        // Replaces the removed diagnostic banner's position —
                        // see [_residenceLegend]'s own doc comment.
                        _residenceLegend(colorProvider),
                        // Drag-to-delete target — see [_trashTarget]'s own
                        // doc comment. Only rendered while a card is actually
                        // being dragged.
                        _trashTarget(allBoys: boys),
                        Expanded(
                          child: _canvas(
                            colorProvider: colorProvider,
                            boardId: boardId,
                            columns: visibleColumns,
                            allBoys: boys,
                            columnBoys: (column) {
                              if (column.kind == kColumnKindUnassigned) {
                                return byUnassigned;
                              }
                              if (column.isGuideColumn) {
                                return boys
                                    .where((b) => b.guideId == column.guideId)
                                    .toList();
                              }
                              return const <_Boy>[];
                            },
                            headerExtra: (column) {
                              if (!column.isGuideColumn &&
                                  column.kind != kColumnKindUnassigned) {
                                return null;
                              }
                              final list = column.kind == kColumnKindUnassigned
                                  ? byUnassigned
                                  : boys.where(
                                      (b) => b.guideId == column.guideId);
                              return residenceSplit(list.map((b) => b.role))
                                  .label;
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Custom board rendering — Phase 4. A completely separate path from
  // `_board()`/`_canvas()`/`_columnTile()` above: nothing in this section is
  // called by the mandatory board, and nothing above is called by this
  // section. The only things shared between the two are the CARD FACE
  // functions (`_studentCard`, `_cardBody`, `_cardIcon`, `_expandedDetail`,
  // `_residenceTint`) — reused completely unchanged, which is what makes
  // "identical card face everywhere" true by construction rather than by
  // convention.
  // ---------------------------------------------------------------------------

  /// ⚠️ **Card eligibility follows the VIEWER, not the board's owner — Part 2
  /// item 5 / Part 4 item 5.** A guide's custom board may contain only
  /// students CURRENTLY assigned to that guide; the HOD's board may contain
  /// any student. When a board is shared, this check runs against whoever is
  /// LOOKING at it right now, not whoever created it — so a guide opening an
  /// HOD-built board shared with them can only newly place their OWN
  /// students, exactly as if it were their own board.
  ///
  /// ⚠️ **Students the HOD already placed who are NOT the viewing guide's own
  /// stay visible.** `users` is fetched unfiltered here (17 real students —
  /// no scale concern, matching the mandatory board's own reasoning for an
  /// unfiltered query) and a student is INCLUDED in this board's working set
  /// if EITHER they are eligible to the current viewer OR they already have
  /// a placement document on this specific board — the union, not just
  /// eligibility alone. This is deliberate: eligibility gates who can be
  /// newly placed (by controlling who ever appears in the default Unsorted
  /// bucket), but it must never retroactively hide a card the HOD
  /// deliberately put there before this guide was invited to help. Confirmed
  /// explicitly per the task's own instruction to state this choice.
  bool _customBoardEligible({
    required String studentGuideId,
    required String viewerGuide,
    required bool viewerIsHod,
  }) {
    if (viewerIsHod) return true;
    return studentGuideId == viewerGuide;
  }

  /// ⚠️ **Writes ONLY to `placements`, via `movePlacement` — never
  /// `reassignGuide`.** Confirmed by construction: the only Firestore-facing
  /// call in this function's entire body is `movePlacement`. There is no
  /// code path from any custom-board `DragTarget` into `reassignGuide` or
  /// `_handleDrop` — this function exists specifically so there never could
  /// be one.
  Future<void> _handlePlacementDrop({
    required String boardId,
    required bool canEdit,
    required _Boy boy,
    required BoardColumn target,
    required int orderInTarget,
    required String guide,
  }) async {
    if (!canEdit) return;
    try {
      await movePlacement(
        boardId: boardId,
        studentUid: boy.uid,
        columnId: target.id,
        order: orderInTarget,
        movedBy: guide,
      );
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not move", Colors.red, Icons.error);
    }
  }

  Widget _customBoardBody(
    ColorProvider colorProvider,
    String guide,
    String boardId,
  ) {
    return StreamBuilder<List<BoardDoc>>(
      stream: allBoardsStream(),
      builder: (context, boardsSnap) {
        if (!boardsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        BoardDoc? board;
        for (final b in boardsSnap.data!) {
          if (b.id == boardId) {
            board = b;
            break;
          }
        }
        if (board == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final canEdit = canEditBoard(board: board, guide: guide, isHod: _isHod);

        return StreamBuilder<List<BoardColumn>>(
          stream: columnsStream(boardId),
          builder: (context, colSnap) {
            if (!colSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final columns = colSnap.data!;

            // ⚠️ **No Unsorted fallback any more (this task, Part 2).** A
            // custom board has no permanent catch-all column at all now —
            // the ONLY way a student ever appears on this board is an
            // explicit placement document (via the "add students" picker,
            // see [_openAddStudentsPicker]). [_customBoardEligible] is
            // therefore no longer consulted for RENDERING at all — it
            // still gates who the picker offers (Part 3.2), but a student
            // already placed here stays visible regardless of later
            // eligibility changes, which is a simpler and more consistent
            // rule than the previous "eligible OR already placed" union
            // this replaced.
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: placementsStream(boardId),
              builder: (context, placeSnap) {
                final placementColumnByUid = <String, String>{};
                if (placeSnap.hasData) {
                  for (final d in placeSnap.data!.docs) {
                    placementColumnByUid[d.id] =
                        (d.data()['columnId'] ?? '').toString();
                  }
                }

                if (placementColumnByUid.isEmpty) {
                  // Nobody has ever been placed here — skip the `users`
                  // read entirely, matching the blank-board empty state.
                  return _customCanvas(
                    colorProvider: colorProvider,
                    boardId: boardId,
                    guide: guide,
                    canEdit: canEdit,
                    columns: columns,
                    allBoys: const [],
                    columnBoys: (_) => const [],
                    columnCardCount: (column) =>
                        cardsInColumn(placeSnap.data, column.id),
                  );
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      FirebaseFirestore.instance.collection('users').snapshots(),
                  builder: (context, userSnap) {
                    if (!userSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final boys = <_Boy>[];
                    for (final doc in userSnap.data!.docs) {
                      // Only students actually placed on THIS board — see
                      // this method's own note above.
                      if (!placementColumnByUid.containsKey(doc.id)) continue;
                      final data = doc.data();
                      final name = (data['name'] ?? '').toString().trim();
                      if (name.isEmpty) continue;
                      boys.add(_Boy(
                        uid: doc.id,
                        name: name,
                        role: (data['role'] ?? '').toString(),
                        guideId: (data['guideId'] ?? '').toString().trim(),
                      ));
                    }

                    return _customCanvas(
                      colorProvider: colorProvider,
                      boardId: boardId,
                      guide: guide,
                      canEdit: canEdit,
                      columns: columns,
                      allBoys: boys,
                      // A placement pointing at a column that no longer
                      // exists (should not happen — deleting a column now
                      // deletes its own placements too, see
                      // `deleteColumnDeletingPlacements`) simply matches no
                      // column here and renders nowhere, rather than
                      // silently reappearing in a fallback bucket that no
                      // longer exists.
                      columnBoys: (column) => boys
                          .where((b) => placementColumnByUid[b.uid] == column.id)
                          .toList(),
                      columnCardCount: (column) =>
                          cardsInColumn(placeSnap.data, column.id),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  /// ⚠️ **Blank-board empty state — this task's Part 1.3.** A brand-new
  /// custom board has zero columns (no Unsorted, no seed) — without an
  /// explicit affordance the board would just look broken, so an empty
  /// `columns` list gets a dedicated centred prompt instead of silently
  /// falling through to just the small "Add a list" tile at the far left,
  /// which would be easy to miss on first open.
  Widget _customCanvas({
    required ColorProvider colorProvider,
    required String boardId,
    required String guide,
    required bool canEdit,
    required List<BoardColumn> columns,
    required List<_Boy> allBoys,
    required List<_Boy> Function(BoardColumn) columnBoys,
    required int Function(BoardColumn) columnCardCount,
  }) {
    if (columns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.view_column_outlined,
                  size: 46, color: Colors.grey.shade400),
              const SizedBox(height: 14),
              Text(
                "This board is empty",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorProvider.secondColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Add a list to start organising students.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              if (canEdit) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _addCustomColumn(boardId, columns),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Add a list"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00695C),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: _hController,
      scrollDirection: Axis.horizontal,
      physics: _scrollLocked ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      children: [
        for (final column in columns)
          _customColumnTile(
            boardId: boardId,
            guide: guide,
            canEdit: canEdit,
            column: column,
            columns: columns,
            allBoys: allBoys,
            boys: columnBoys(column),
            cardCount: columnCardCount(column),
          ),
        if (canEdit)
          Container(
            width: 150,
            margin: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => _addCustomColumn(boardId, columns),
              borderRadius: BorderRadius.circular(16),
              child: DottedBorderBox(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: Colors.grey.shade600),
                    const SizedBox(height: 6),
                    Text(
                      "Add a list",
                      style:
                          TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _customColumnTile({
    required String boardId,
    required String guide,
    required bool canEdit,
    required BoardColumn column,
    required List<BoardColumn> columns,
    required List<_Boy> allBoys,
    required List<_Boy> boys,
    required int cardCount,
  }) {
    final colour = Color(column.colorValue);

    return DragTarget<String>(
      // Read-only viewers, and drops of a student already in this column,
      // are both rejected here — `canEdit` is re-checked again inside
      // `_handlePlacementDrop` as the real authority, matching every other
      // permission gate in this file.
      onWillAcceptWithDetails: (details) {
        if (!canEdit) return false;
        return !boys.any((b) => b.uid == details.data);
      },
      onAcceptWithDetails: (details) {
        final boy = _findBoy(allBoys, details.data);
        if (boy == null) return;
        _handlePlacementDrop(
          boardId: boardId,
          canEdit: canEdit,
          boy: boy,
          target: column,
          orderInTarget: boys.length,
          guide: guide,
        );
      },
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;

        return Container(
          width: _columnWidth,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: hovering ? colour.withOpacity(.10) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hovering ? colour : colour.withOpacity(.28),
              width: hovering ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _customColumnHeader(
                boardId: boardId,
                guide: guide,
                canEdit: canEdit,
                column: column,
                columns: columns,
                colour: colour,
                count: boys.length,
                cardCount: cardCount,
              ),
              const Divider(height: 1),
              Expanded(
                child: boys.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            hovering ? "Drop here" : "Empty",
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: _scrollLocked
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                        itemCount: boys.length,
                        // ⚠️ **Part 3.5 — remove one student from this
                        // board.** `_studentCard` itself is reused
                        // completely UNCHANGED (its own `LongPressDraggable`
                        // already claims long-press for the drag this task
                        // must not touch) — a competing long-press or a menu
                        // added INSIDE that card would risk exactly the
                        // gesture-arena conflict this project spent five
                        // rounds fixing. Instead, a small "×" badge is
                        // overlaid from the OUTSIDE via `Stack`, as a SIBLING
                        // of the card rather than a descendant of its own
                        // `LongPressDraggable`/`GestureDetector` — Flutter
                        // resolves its tap independently, with no shared
                        // ancestor to compete in the same arena. Custom-board
                        // only: the mandatory board's own `_columnTile` (a
                        // separate, untouched code path) never renders this.
                        itemBuilder: (context, i) => canEdit
                            ? Stack(
                                children: [
                                  _studentCard(boy: boys[i], colour: colour),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => _confirmRemoveFromBoard(
                                        boardId: boardId,
                                        boy: boys[i],
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(.15),
                                              blurRadius: 3,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.close,
                                          size: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : _studentCard(boy: boys[i], colour: colour),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Same visual shape as the mandatory board's `_columnHeader`, plus an
  /// "add students" icon (Part 3.1 — the missing capability, this task) and
  /// a column menu when [canEdit] — `column.isEditable` is effectively
  /// always true here now that no custom-board column is ever permanent
  /// (Unsorted no longer exists on these boards at all, per this task's
  /// Part 2), but the check is kept for defensiveness and reuse of the same
  /// `BoardColumn.isEditable` the mandatory board also relies on.
  Widget _customColumnHeader({
    required String boardId,
    required String guide,
    required bool canEdit,
    required BoardColumn column,
    required List<BoardColumn> columns,
    required Color colour,
    required int count,
    required int cardCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      child: Row(
        children: [
          Container(width: 4, height: 30, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    column.title.isEmpty ? "(untitled)" : column.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colour,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colour.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "$count",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colour,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (canEdit)
            IconButton(
              tooltip: "Add students",
              icon: Icon(Icons.person_add_alt_1,
                  size: 18, color: Colors.grey.shade600),
              onPressed: () => _openAddStudentsPicker(
                boardId: boardId,
                column: column,
                guide: guide,
                currentCardCount: cardCount,
              ),
            ),
          if (canEdit && column.isEditable)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade600),
              onSelected: (v) {
                switch (v) {
                  case 'rename':
                    _renameCustomColumn(boardId, column);
                  case 'colour':
                    _recolourCustomColumn(boardId, column);
                  case 'left':
                    _shiftCustomColumn(boardId, columns, column, -1);
                  case 'right':
                    _shiftCustomColumn(boardId, columns, column, 1);
                  case 'delete':
                    _deleteCustomColumn(
                      boardId: boardId,
                      column: column,
                      columns: columns,
                      cardCount: cardCount,
                      guide: guide,
                    );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text("Rename")),
                PopupMenuItem(value: 'colour', child: Text("Change colour")),
                PopupMenuItem(value: 'left', child: Text("Move left")),
                PopupMenuItem(value: 'right', child: Text("Move right")),
                PopupMenuItem(value: 'delete', child: Text("Delete")),
              ],
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Canvas — REAL side-by-side columns, restored. A horizontally-scrolling
  // row of columns, each with its own vertically-scrolling card list.
  // ---------------------------------------------------------------------------

  Widget _canvas({
    required ColorProvider colorProvider,
    required String boardId,
    required List<BoardColumn> columns,
    required List<_Boy> allBoys,
    required List<_Boy> Function(BoardColumn) columnBoys,
    required String? Function(BoardColumn) headerExtra,
  }) {
    if (columns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.view_column_outlined,
                  size: 46, color: Colors.grey.shade400),
              const SizedBox(height: 14),
              Text(
                "Setting up guide columns…",
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorProvider.secondColor),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _hController,
      scrollDirection: Axis.horizontal,
      // Drag fix — `null` (not `AlwaysScrollableScrollPhysics()`) when
      // unlocked, so the default platform scroll feel is unchanged. See
      // `_scrollLocked`'s doc comment for the full history.
      physics: _scrollLocked ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      itemCount: columns.length,
      itemBuilder: (context, index) {
        final column = columns[index];
        return _columnTile(
          boardId: boardId,
          column: column,
          allBoys: allBoys,
          boys: columnBoys(column),
          headerExtra: headerExtra(column),
        );
      },
    );
  }

  Widget _columnTile({
    required String boardId,
    required BoardColumn column,
    required List<_Boy> allBoys,
    required List<_Boy> boys,
    required String? headerExtra,
  }) {
    final colour = Color(column.colorValue);

    return DragTarget<String>(
      // ⚠️ No `_isHod` gate here any more — a non-HOD guide is now allowed
      // to drop, per this task's permission change. This is safe only
      // because [_visibleColumns] already means a non-HOD never even sees a
      // `DragTarget` for any column other than Unassigned and their own, so
      // every drop that reaches here is structurally a claim or a release.
      // The real, authoritative gate is still `_handleDrop`'s own
      // permission check below — see its doc comment for why that
      // enforcement is repeated there rather than trusted to the UI alone.
      onWillAcceptWithDetails: (details) {
        return !boys.any((b) => b.uid == details.data);
      },
      onAcceptWithDetails: (details) {
        final boy = _findBoy(allBoys, details.data);
        if (boy == null) return;
        _handleDrop(
          boardId: boardId,
          boy: boy,
          target: column,
          orderInTarget: boys.length,
        );
      },
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;

        return Container(
          width: _columnWidth,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: hovering ? colour.withOpacity(.10) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hovering ? colour : colour.withOpacity(.28),
              width: hovering ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _columnHeader(column: column, colour: colour, count: boys.length, headerExtra: headerExtra),
              const Divider(height: 1),
              Expanded(
                child: boys.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            hovering ? "Drop here" : "Empty",
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    : ListView.builder(
                        // Same drag fix as the outer horizontal list — this
                        // column's own vertical scroll is ALSO an ancestor
                        // of every card's `LongPressDraggable` and competes
                        // in the exact same way.
                        physics: _scrollLocked
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                        itemCount: boys.length,
                        itemBuilder: (context, i) =>
                            _studentCard(boy: boys[i], colour: colour),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _columnHeader({
    required BoardColumn column,
    required Color colour,
    required int count,
    required String? headerExtra,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      child: Row(
        children: [
          Container(width: 4, height: 30, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        column.title.isEmpty ? "(untitled)" : column.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colour,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: colour.withOpacity(.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "$count",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colour,
                        ),
                      ),
                    ),
                  ],
                ),
                if (headerExtra != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    headerExtra,
                    style:
                        TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ⚠️ **Drag attempt #5 — back to whole-card `LongPressDraggable`, per the
  /// product owner's explicit rejection of the handle icon.** Attempt #4's
  /// handle isolation is REMOVED — the diagnostic banner's real device
  /// result (`guide="FOLK" isHod=false`) showed every prior drag attempt was
  /// being silently rejected by `_handleDrop`'s blanket `if (!_isHod)
  /// return;` before ANY gesture code ran, which means attempts 2-4 were
  /// never actually exercised end-to-end on a device that could reach a
  /// write. The permission fix (see `_handleDrop`) is the real, evidenced
  /// change this task; the whole-card gesture is restored on the strength of
  /// that finding, not because the handle-isolation reasoning (attempt #4's
  /// own doc comment, now removed with the handle) was wrong — it may simply
  /// have never been the blocker. **Kept from attempt #4**: `_scrollLocked`
  /// arms in `onDragStarted` (after the drag has already won the arena), not
  /// on pointer-down — that correction was grounded in direct inspection of
  /// Flutter's `Scrollable`/`ScrollPosition` source (`NeverScrollableScrollPhysics`
  /// never withdraws a Scrollable's recognizer from the arena; it only makes
  /// an already-won drag a no-op) and holds regardless of what triggers the
  /// drag.
  ///
  /// If this still doesn't work on a real device, the most likely remaining
  /// cause — per Flutter's own documented arena behaviour, not a new
  /// invented theory — is genuine finger jitter past `kTouchSlop` during the
  /// 500ms hold on a card face large enough to invite more incidental
  /// movement than a small handle would have. That is a real, named risk,
  /// not a silent one; it is not addressed here because the task's own
  /// instruction is to test the permission fix first rather than layer on
  /// another speculative gesture change.
  Widget _studentCard({required _Boy boy, required Color colour}) {
    final cardBody = _cardBody(boy: boy, colour: colour);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: LongPressDraggable<String>(
        data: boy.uid,
        onDragStarted: _lockScroll,
        onDragUpdate: _onDragUpdate,
        onDragEnd: (_) {
          _stopEdgeScroll();
          _unlockScroll();
        },
        onDraggableCanceled: (_, __) {
          _stopEdgeScroll();
          _unlockScroll();
        },
        onDragCompleted: () {
          _stopEdgeScroll();
          _unlockScroll();
        },
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: .92,
            child: SizedBox(
              width: _columnWidth - 20,
              child:
                  _cardBody(boy: boy, colour: colour, forceCollapsed: true),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .35, child: cardBody),
        child: cardBody,
      ),
    );
  }

  Widget _cardBody({
    required _Boy boy,
    required Color colour,
    bool forceCollapsed = false,
  }) {
    final expanded = !forceCollapsed && _expandedUids.contains(boy.uid);

    return Container(
      decoration: BoxDecoration(
        color: _residenceTint(boy.role) ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      // Plain GestureDetector, NOT InkWell — see this file's header for the
      // full drag-history diagnosis.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: forceCollapsed
            ? null
            : () => setState(() {
                  if (expanded) {
                    _expandedUids.remove(boy.uid);
                  } else {
                    _expandedUids.add(boy.uid);
                  }
                }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colour.withOpacity(.12),
                    ),
                    child: Center(
                      child: Text(
                        boy.name.isNotEmpty ? boy.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: colour,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      boy.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  // Left-to-right: calendar, comment, profile — i.e.
                  // right-to-left: profile, comment, calendar — all three
                  // wired. The scoring placeholder icon (bar-chart,
                  // `onTap: null`) was removed this task: it was a Phase 1
                  // stand-in for a scoring destination that no longer exists
                  // separately — `StudentProfilePage` (the profile icon)
                  // already carries both score cards, so the placeholder was
                  // pure redundant dead weight that rendered greyed and read
                  // as broken. A small gap between icons (added last task)
                  // gives each `IconButton` clear space from its neighbour,
                  // reducing the chance a slightly off-centre tap lands on
                  // the wrong control.
                  _cardIcon(
                    icon: Icons.calendar_month,
                    tooltip: "Calendar",
                    onTap: forceCollapsed
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CalendarPage(
                                  username: boy.name,
                                  role: boy.role,
                                  studentUid: boy.uid,
                                ),
                              ),
                            ),
                  ),
                  const SizedBox(width: 3),
                  // Wired this task (Phase 2, Part 4) — reuses
                  // `showStudentCommentsDialog` unchanged, including its own
                  // internal `_canAccess` gate (HOD always; a guide only on
                  // their own current student). Deliberately NOT
                  // pre-checked here: duplicating that gate would be a
                  // second copy of the same rule that could drift, and the
                  // dialog already renders the correct "not yours" / "no
                  // guide selected" states on its own when access fails —
                  // see this file's header for the specific consequence for
                  // an unassigned student.
                  // Master Task 2026-09-10, Part 6 — per-student thread:
                  // unseen means a message posted (by the OTHER party — HOD
                  // or the assigned guide) since THIS viewer last opened
                  // THIS student's thread, so one student's new message
                  // never lights up every other student's icon too.
                  UnseenFeatureBadge(
                    featureKey: 'studentComments',
                    subKey: boy.uid,
                    timestampField: 'createdAt',
                    latestQuery: (_) => FirebaseFirestore.instance
                        .collection('studentComments')
                        .doc(boy.uid)
                        .collection('messages')
                        .snapshots(),
                    child: _cardIcon(
                      icon: Icons.forum_outlined,
                      tooltip: "Comments",
                      onTap: forceCollapsed
                          ? null
                          : () => showStudentCommentsDialog(
                                context: context,
                                studentUid: boy.uid,
                                studentName: boy.name,
                                studentGuideId: boy.guideId,
                              ).then((_) {
                                SeenMarkers.markSeenSub(
                                    _guide, 'studentComments', boy.uid);
                              }),
                    ),
                  ),
                  const SizedBox(width: 3),
                  // Profile icon (added Phase 3, Part 3) — opens
                  // `StudentProfilePage`, the replacement for the old
                  // `Pages/Profile.dart`. Now the last of three icons — the
                  // fourth (scoring placeholder) that used to sit before
                  // Calendar was removed this task.
                  _cardIcon(
                    icon: Icons.person_outline,
                    tooltip: "Profile",
                    onTap: forceCollapsed
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    StudentProfilePage(studentUid: boy.uid),
                              ),
                            ),
                  ),
                  if (!forceCollapsed)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Colors.grey.shade500,
                    ),
                ],
              ),
              // Manually-added student badge — Part 5, this task. Not
              // optional per the task's own instruction: a roadmap phase can
              // now be completed on guide-entered numbers alone, so this
              // must always be visible, never hidden behind a tap.
              if (boy.isManualEntry) _manualEntryBadge(),
              if (expanded) ...[
                const Divider(height: 18),
                _expandedDetail(boy: boy),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// ⚠️ **Phase 2, Part 3 — reuses `utils/BookProgressData.dart` exactly
  /// (extracted from `Pages/BooksProgress.dart` this task, see that file's
  /// header), not a reimplementation.** Only built for a card that is
  /// currently expanded — this method is called from exactly one call site,
  /// inside `_cardBody`'s `if (expanded)` branch — so a collapsed card never
  /// runs any of these reads. This is the performance answer the task asked
  /// for: with N cards on a board, at most one `FutureBuilder`/`StreamBuilder`
  /// pair per EXPANDED card exists at any time, never N of them; collapsing a
  /// card removes its subtree (and Firestore listener) from the tree
  /// entirely via the normal `setState` rebuild in `_cardBody`'s `onTap`.
  ///
  /// The book CONFIG (`books/level-1..3` + link availability) is identical
  /// for every student, so [_booksConfigFuture] is created once, lazily, on
  /// whichever card is expanded first, and reused for every card after that
  /// — one config read for the whole board session, not one per student.
  /// The per-student pieces (`booksRead` progress, `commitmentRounds`) are
  /// fetched fresh per expanded card, exactly matching how
  /// `BooksProgressPage` itself only ever loads them for the one student it
  /// was opened for.
  Widget _expandedDetail({required _Boy boy}) {
    _booksConfigFuture ??= loadBooksConfig();
    // Master Task 2026-09-10, Part 6 — expanding this student's own card is
    // "seen" for their book commitments (per-student, so one student's
    // update never marks a different student's own panel seen). Fire-and-
    // forget, no UI here — this file's board internals (drag, drop,
    // permissions, `_usersQuery`, `_visibleColumns`) are unchanged.
    SeenMarkers.markSeenSub(_guide, 'bookCommitments', boy.uid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chanting commitment — Part 5. Same field, same "absent or 0 both
        // mean unset" rule as `BooksProgress.dart`'s own banner
        // (`loadChantingCommitment`), just laid out to fit inside a card
        // instead of a full-width screen banner.
        FutureBuilder<int?>(
          future: loadChantingCommitment(boy.uid),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            return _commitmentRow(snap.data);
          },
        ),
        const SizedBox(height: 8),
        FutureBuilder<BooksConfig>(
          future: _booksConfigFuture,
          builder: (context, configSnap) {
            if (configSnap.hasError) {
              return Text(
                "Could not load the book list.",
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              );
            }
            if (!configSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final config = configSnap.data!;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // Same single equality filter `BooksProgress.dart` uses — no
              // composite index needed, and legacy name-keyed `booksRead`
              // documents (no `uid` field) are excluded by construction.
              stream: FirebaseFirestore.instance
                  .collection('booksRead')
                  .where('uid', isEqualTo: boy.uid)
                  .snapshots(),
              builder: (context, progressSnap) {
                if (!progressSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                // Keyed "{level}_{bookKey}" — same shape as
                // `BooksProgress.dart`'s own `entries` map.
                final entries = <String, Map<String, dynamic>>{};
                for (final doc in progressSnap.data!.docs) {
                  final data = doc.data();
                  final level = (data['level'] ?? '').toString();
                  final key = (data['bookKey'] ?? '').toString();
                  if (level.isEmpty || key.isEmpty) continue;
                  entries['${level}_$key'] = data;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: kBookLevels
                      .map((level) => _levelDropdown(
                            boy: boy,
                            level: level,
                            config: config,
                            entries: entries,
                          ))
                      .toList(),
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// Compact version of `BooksProgress.dart`'s own commitment banner — same
  /// icon, same wording, same "grey when unset" rule, just without that
  /// screen's full-width bordered container (there is no room for one inside
  /// a board card).
  Widget _commitmentRow(int? commitment) {
    return Row(
      children: [
        Icon(
          Icons.local_fire_department,
          size: 15,
          color: commitment == null
              ? Colors.grey.shade400
              : Colors.deepOrange.shade400,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            commitment == null
                ? "No chanting commitment set"
                : "Committed to $commitment rounds/day",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: commitment == null
                  ? Colors.grey.shade500
                  : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  /// One of the three level sub-dropdowns. Collapsed by default — only the
  /// finished/reading counts show until tapped, exactly like
  /// `BooksProgress.dart`'s own `_levelHeader` summary line.
  ///
  /// A plain `GestureDetector`, not `InkWell` — matching this file's own
  /// established convention (see `_cardBody`'s header note) for anything
  /// nested inside the draggable card, even though a same-type nested tap
  /// (this level header vs. the outer card's own tap-to-expand) resolves
  /// deterministically in Flutter and was never the actual source of this
  /// file's drag conflicts — consistency with the existing idiom costs
  /// nothing here.
  ///
  /// Revert task (2026-08-30), Part 5 — books are reordered for display
  /// ONLY (never rewritten, never re-keyed): completed first, then current
  /// books (even out of hierarchy order — Part 2 item 4 makes multiple
  /// concurrently current expected, not a bug), then the rest in hierarchy
  /// order. The "$finished of N finished" count line is unaffected by this
  /// reorder — it counts the same `books` list either way.
  Widget _levelDropdown({
    required _Boy boy,
    required String level,
    required BooksConfig config,
    required Map<String, Map<String, dynamic>> entries,
  }) {
    final books = config.byLevel[level] ?? const <BookConfigEntry>[];

    var finished = 0;
    var reading = 0;
    final completedBooks = <BookConfigEntry>[];
    final currentBooks = <BookConfigEntry>[];
    final restBooks = <BookConfigEntry>[];
    for (final b in books) {
      final s = statusForBookEntry(entries['${b.level}_${b.key}']);
      if (s == BookStatus.finished) {
        finished++;
        completedBooks.add(b);
      } else if (s == BookStatus.readingNow) {
        reading++;
        currentBooks.add(b);
      } else {
        restBooks.add(b);
      }
    }
    final displayOrder = [...completedBooks, ...currentBooks, ...restBooks];

    final levelKey = '${boy.uid}_$level';
    final open = _expandedLevels.contains(levelKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            if (open) {
              _expandedLevels.remove(levelKey);
            } else {
              _expandedLevels.add(levelKey);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 3),
                Text(
                  kBookLevelLabels[level] ?? level,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    books.isEmpty
                        ? "no books configured"
                        : "$finished of ${books.length} finished"
                            "${reading > 0 ? ' · $reading reading' : ''}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 19, bottom: 4),
            child: books.isEmpty
                ? Text(
                    "No books configured for this level.",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: displayOrder
                        .map((b) => _bookStatusRow(
                            boy: boy,
                            book: b,
                            status:
                                statusForBookEntry(entries['${b.level}_${b.key}']),
                            entry: entries['${b.level}_${b.key}']))
                        .toList(),
                  ),
          ),
      ],
    );
  }

  /// One book, compact single line. Same status colour/icon as
  /// `BooksProgress.dart`'s own `_bookRow` (via the shared `bookStatusStyle`)
  /// — green finished, grey not started, amber "reading now". The status
  /// LABEL text, the "No file"/"Notes" badges, and the bordered card
  /// styling from that screen's fuller row are dropped here — there is no
  /// room for them inside a level dropdown nested inside a board card, and
  /// the icon colour alone already carries the same three states.
  ///
  /// Revert task (2026-08-30), Part 3/5 — now TAPPABLE (a real behaviour
  /// change from the prior "not tappable" state): tapping an unfinished
  /// book opens the guide-assign dialog. Shows the student's own
  /// `commitmentDate` and who set it (Part 5 item 2's "current books with
  /// their commitment dates... show who set it"), replacing the removed
  /// automatic-deadline/extension display entirely.
  ///
  /// Task, 2026-09-15 — the row's own separate "Mark finished" tick
  /// (`IconButton`, `Icons.check_circle_outline`) is REMOVED: it duplicated
  /// the "Mark as completed" action already inside the tap-the-title assign
  /// dialog ([_openAssignBookDialog]), and cost every row extra height for
  /// no longer reason. Tapping the title (for any non-finished book) is now
  /// the ONLY way to mark a book finished from this card —
  /// [_confirmMarkBookFinished] itself is unchanged and still called from
  /// that dialog.
  Widget _bookStatusRow({
    required _Boy boy,
    required BookConfigEntry book,
    required BookStatus status,
    required Map<String, dynamic>? entry,
  }) {
    final (colour, icon, _) = bookStatusStyle(status);
    final isCurrent = status == BookStatus.readingNow;
    final isFinished = status == BookStatus.finished;
    final commitmentDate = (entry?['commitmentDate'] as String?)?.trim();
    final commitmentSetBy = (entry?['commitmentSetBy'] as String?)?.trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isFinished
          ? null
          : () => _openAssignBookDialog(boy: boy, book: book, entry: entry),
      child: Padding(
        // Task, 2026-09-15 — tightened from `vertical: 3` now that the
        // "Mark finished" icon button (which forced a 28-logical-pixel
        // minimum row height) is gone; rows are shorter on their own
        // merits now, so less padding keeps them from looking too sparse.
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 13, color: colour),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title.isEmpty ? "(untitled)" : book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: status == BookStatus.notStarted
                          ? Colors.grey.shade600
                          : Colors.black87,
                    ),
                  ),
                  // Part 5 item 2 — current book's commitment date + who
                  // set it. Never shown for a finished book (no
                  // `commitmentDate` display makes sense once done) or a
                  // not-started one (nothing has been committed yet).
                  if (isCurrent && commitmentDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        commitmentSetBy == 'guide'
                            ? "Due $commitmentDate (set by guide)"
                            : "Due $commitmentDate (set by student)",
                        style: TextStyle(
                            fontSize: 9.5, color: Colors.grey.shade500),
                      ),
                    ),
                ],
              ),
            ),
            // The separate "Mark finished" tick button that used to live
            // here was removed (task, 2026-09-15) — redundant with the
            // "Mark as completed" action already inside the tap-the-title
            // assign dialog ([_openAssignBookDialog]), and the row's own
            // chevron below already signals the whole row is tappable.
            if (!isFinished)
              Icon(Icons.chevron_right, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  /// Master Task Part 4 item 1 — confirms, then marks a book finished in
  /// ONE write: `endDate = today`, `isCurrentBook = false` and (Part 2 of
  /// the challenge/book-completion/deep-linking task) `endedBy = 'guide'`
  /// together, so there is no intermediate state where any one of them is
  /// set and not the others. This is the ONLY place in the Guide app that
  /// writes `endDate`/`endedBy` — every other field this app's `booksRead`
  /// writes touch is listed in [_openAssignBookDialog]'s own doc comment;
  /// `madeNotes` is never touched here or there (Rule 14/15 — that field
  /// is the student's own self-report about their notes, not something a
  /// guide's "the book is done" action has any business overwriting).
  ///
  /// Reached from two places, unchanged from each other: the board's own
  /// book-list "Mark finished" icon ([_bookStatusRow]), and — added this
  /// task — the "Mark as completed" action inside [_openAssignBookDialog]
  /// itself, which simply calls this SAME function rather than
  /// duplicating its write.
  ///
  /// Master Task 2026-09-10, Part 5 — now callable for a book that was
  /// NEVER started (`entry` is null, or has no `startDate` yet): the SAME
  /// one write also sets `startDate = today` in that case, alongside
  /// `endDate = today`, so a never-started book that is marked complete
  /// gets a real (equal) start and end date rather than an `endDate` with
  /// no `startDate` at all. A book that already has a `startDate` keeps
  /// it untouched — this never overwrites a real start date the student
  /// (or a prior guide assignment) already recorded. `isCurrentBook:
  /// false` in every case means a finished book is never `isCurrentBook`,
  /// satisfied by construction regardless of which path led here.
  Future<void> _confirmMarkBookFinished({
    required _Boy boy,
    required BookConfigEntry book,
    required Map<String, dynamic>? entry,
  }) async {
    final hasStarted =
        ((entry?['startDate'] as String?)?.trim().isNotEmpty ?? false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Mark this book finished?"),
        content: Text(
          hasStarted
              ? "${book.title.isEmpty ? '(untitled)' : book.title} will no "
                  "longer be ${boy.name}'s current book."
              : "${book.title.isEmpty ? '(untitled)' : book.title} was "
                  "never started by ${boy.name}. Marking it finished sets "
                  "today as both its start and end date, and it will not "
                  "become their current book.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Mark finished",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final today = DateTime.now().toIso8601String().split('T')[0];

    try {
      await FirebaseFirestore.instance
          .collection('booksRead')
          .doc('${boy.uid}_${book.level}_${book.key}')
          .set({
        'uid': boy.uid,
        'level': book.level,
        'bookKey': book.key,
        'bookTitle': book.title,
        'endDate': today,
        'isCurrentBook': false,
        // Master Task Part 2 item 3 — read by the Student app
        // (`BookPageList.dart`) to show "Marked complete by your guide"
        // instead of leaving a student wondering why a book they never
        // finished themselves shows as completed.
        'endedBy': 'guide',
        // Part 5 item 2 — only for a book with no prior `startDate`; an
        // already-started book keeps its real start date untouched.
        if (!hasStarted) 'startDate': today,
      }, SetOptions(merge: true));

      if (!mounted) return;
      showSnackbar(context, "Book marked finished", Colors.green,
          Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
          context, "Could not update the book", Colors.red, Icons.error);
    }
  }

  /// Part 3 — the guide assigns a book. Tapping any unfinished book in the
  /// dropdown above opens this: title + date picker, confirm writes the
  /// commitment and notifies the student (item 2), naming who set the date
  /// (item 4) so [_bookStatusRow] above can show it. Master Task Part 4
  /// item 2 — also writes `startDate = today` (the day of assignment,
  /// distinct from `commitmentDate`, the future due-date the guide just
  /// picked), so the book is a real current book by the same definition
  /// [statusForBookEntry] already uses.
  ///
  /// A finished book (`isFinished` in the caller) never reaches this
  /// dialog at all — its `onTap` is null — so there is no path here that
  /// could ever write `isCurrentBook: true` onto a book that has an
  /// `endDate`; the "finished is never current" invariant holds by
  /// construction, not by a runtime check inside this function.
  ///
  /// Rule 14/15 — the complete set of `booksRead` fields this Guide app
  /// EVER writes, across this function and [_confirmMarkBookFinished]:
  /// `uid`, `level`, `bookKey`, `bookTitle`, `isCurrentBook`, `startDate`,
  /// `endDate`, `endedBy`, `commitmentDate`, `commitmentSetAt`,
  /// `commitmentSetBy`.
  /// `madeNotes` — the student's own self-report about taking notes — is
  /// NEVER written by either function; it is exclusively student-authored
  /// (`Students/.../BookPageList.dart`) and this app only ever reads it
  /// (`BooksProgress.dart`).
  /// Master Task Part 2 (book-completion from the assign dialog) — added
  /// the "Mark as completed" action. `showDialog`'s type widened from
  /// `DateTime` to `Object` so the same dialog can pop either a picked
  /// `DateTime` (assign) or the sentinel string `'mark_finished'`
  /// (complete) through the one `confirmed` result — resolved by the
  /// caller below AFTER this dialog's own route has fully closed, exactly
  /// like every other multi-step dialog flow in this file (e.g.
  /// `_openAddStudentDialog`'s own snackbar-after-pop pattern), so there is
  /// no nested-dialog transition for the confirm step that follows.
  ///
  /// Master Task 2026-09-10, Part 5 item 1 — the "Mark as completed"
  /// action used to be gated to the CURRENT book only (a since-removed
  /// `isCurrent` parameter); it is now offered unconditionally, since this
  /// whole dialog only ever opens for a non-finished book to begin with
  /// (see the row's own `onTap: isFinished ? null : ...` gate) — current
  /// and never-started books both reach here, and both can now be marked
  /// complete from it.
  Future<void> _openAssignBookDialog({
    required _Boy boy,
    required BookConfigEntry book,
    required Map<String, dynamic>? entry,
  }) async {
    DateTime? picked = DateTime.now();

    final confirmed = await showDialog<Object>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Assign this book"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title.isEmpty ? "(untitled)" : book.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Choose a commitment date. This book becomes "
                    "${boy.name}'s current book, and they'll be notified.",
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () async {
                      final result = await showDatePicker(
                        context: dialogContext,
                        initialDate: picked ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (result != null) {
                        setDialogState(() => picked = result);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 10),
                          Text(
                            picked == null
                                ? "Tap to choose a date"
                                : picked!.toIso8601String().split('T')[0],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Part 2 item 1 — originally only offered for the
                  // student's CURRENT book. Master Task 2026-09-10, Part 5
                  // item 1 widens this to ANY book reaching this dialog
                  // (this dialog only ever opens for a non-finished book —
                  // see the row's own `onTap: isFinished ? null : ...`
                  // gate — so a not-yet-started book can be marked
                  // complete here too, not only a current one).
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(dialogContext, 'mark_finished'),
                      icon: const Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.green),
                      label: const Text(
                        "Mark as completed",
                        style: TextStyle(color: Colors.green),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.green.shade300),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: picked == null
                      ? null
                      : () => Navigator.pop(dialogContext, picked),
                  child: const Text("Assign"),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;

    // Part 2 item 2 — reuses `_confirmMarkBookFinished` verbatim (its own
    // confirmation dialog, its own single `endDate`+`isCurrentBook` write)
    // rather than a second implementation of "mark finished" here.
    if (confirmed == 'mark_finished') {
      await _confirmMarkBookFinished(boy: boy, book: book, entry: entry);
      return;
    }

    if (confirmed is! DateTime) return;

    final commitmentDate = confirmed.toIso8601String().split('T')[0];
    // Master Task Part 4 item 2 — the day the guide ASSIGNS the book, not
    // the commitment/due date the guide just picked (which the student
    // reads as a future deadline, `commitmentDate` above). Same
    // `yyyy-MM-dd` string format the student app's own `startDate` already
    // uses (`Students/.../BookPageList.dart`'s `picked.toIso8601String()
    // .split('T')[0]`), so both write paths agree on the field's shape.
    final startDate = DateTime.now().toIso8601String().split('T')[0];

    try {
      // A transaction, so the doc is read at the moment of writing: a book
      // that is already completed (an end date, or marked finished by the
      // student or a guide) is never made the student's CURRENT book.
      final bookRef = FirebaseFirestore.instance
          .collection('booksRead')
          .doc('${boy.uid}_${book.level}_${book.key}');
      final assigned = await FirebaseFirestore.instance
          .runTransaction<bool>((tx) async {
        final latest = (await tx.get(bookRef)).data();
        final endDate = latest?['endDate'];
        final endedBy = latest?['endedBy'];
        final completed =
            (endDate != null && endDate.toString().trim().isNotEmpty) ||
                latest?['finishedViaButton'] == true ||
                (endedBy != null && endedBy.toString().trim().isNotEmpty);
        if (completed) return false;
        tx.set(
            bookRef,
            {
              'uid': boy.uid,
              'level': book.level,
              'bookKey': book.key,
              'bookTitle': book.title,
              'isCurrentBook': true,
              'startDate': startDate,
              'commitmentDate': commitmentDate,
              'commitmentSetAt': FieldValue.serverTimestamp(),
              'commitmentSetBy': 'guide',
            },
            SetOptions(merge: true));
        return true;
      });

      if (!assigned) {
        if (!mounted) return;
        showSnackbar(
            context,
            "This book is already completed, so it cannot be assigned as a current book",
            Colors.orange,
            Icons.info);
        return;
      }

      await _notifyStudentOfBookAssignment(
        studentName: boy.name,
        bookTitle: book.title,
        commitmentDate: commitmentDate,
      );

      if (!mounted) return;
      showSnackbar(context, "Book assigned", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not assign the book", Colors.red, Icons.error);
    }
  }

  /// Part 3 item 2 — reuses the SAME FCM pattern every other guide-to-
  /// student notification in this app already uses
  /// (`notification/{studentName}.FCMToken` -> `FirebaseCM().sendTokenNotification`,
  /// e.g. `AssociationManager`'s own student notify) — no new send path.
  Future<void> _notifyStudentOfBookAssignment({
    required String studentName,
    required String bookTitle,
    required String commitmentDate,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('notification')
          .doc(studentName)
          .get();
      final token = doc.data()?['FCMToken'];

      if (token is String && token.isNotEmpty) {
        await FirebaseCM().sendTokenNotification(
          token,
          "New book assigned 📖",
          "Your guide assigned \"$bookTitle\" — commit to finish by "
              "$commitmentDate.",
        );
      }
    } catch (_) {
      // A failed notification must never undo the assignment write, which
      // has already landed by the time this runs.
    }
  }

  /// ⚠️ **Investigated this task: the product owner reported the fourth
  /// (profile) icon looking dull and not opening `StudentProfilePage`.**
  /// Direct, byte-level comparison of this icon's `onTap` against the
  /// Comments icon (confirmed working) found them structurally IDENTICAL:
  /// `onTap: forceCollapsed ? null : () => Navigator.push(...)`, same as
  /// Comments' own `onTap: forceCollapsed ? null : () =>
  /// showStudentCommentsDialog(...)`. `forceCollapsed` is `false` for every
  /// on-board card (`_studentCard` calls `_cardBody(boy:, colour:)` with no
  /// `forceCollapsed` argument at all — only the drag `feedback:` preview
  /// passes `true`), so the profile icon's `onTap` is genuinely non-null on
  /// the real board, exactly like Comments. There is also no `_isHod` check,
  /// no `boy.guideId` comparison, and no other permission condition anywhere
  /// in `_cardBody`'s icon row — the hypothesis that a HOD-only gate is
  /// silently disabling it for a non-HOD viewer (like the reporting device,
  /// signed in as FOLK) does not hold up under direct code inspection.
  /// Colour is identical too: every icon shares this one `_cardIcon` helper,
  /// so "dull" vs "active" can only ever come from `onPressed` being null vs
  /// not — which, per the above, is not the case here.
  ///
  /// **No logic defect was found in the wiring, colour, or permission
  /// gating.** The one real, verifiable gap this investigation did find:
  /// each icon's actual tappable box was 30x30 logical pixels — below
  /// Material's own documented minimum touch target (48x48dp), and small
  /// enough on a real phone that a tap landing even slightly off-centre
  /// could miss the `IconButton` and land on the card's own tap-to-expand
  /// `GestureDetector` instead, which silently does something different
  /// (toggle expand) with no obvious visual feedback — a real mechanism that
  /// could plausibly produce exactly "looks the same, does nothing" on a
  /// real device, independent of any code-logic bug. Widened to 34x34 here
  /// (`_columnWidth` widened to match — see its own doc comment) as a
  /// genuine, defensible improvement to tap reliability for all four icons
  /// equally, not a confirmed fix for a confirmed cause — stated plainly
  /// rather than claimed as "should work now."
  /// Part 5 — always visible, never behind a tap or the expand toggle. A
  /// small, unmistakably distinct label rather than a subtle tint (the same
  /// judgement already made for FOLK/Hostel residence, deliberately not
  /// repeated here): a roadmap phase can now complete on guide-entered
  /// numbers alone, and that must read as different from a real submission
  /// at a glance, not merely on close inspection.
  Widget _manualEntryBadge() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_note, size: 11, color: Colors.orange.shade800),
                const SizedBox(width: 3),
                Text(
                  "Guide-entered · not registered",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        color: Colors.grey.shade700,
        disabledColor: Colors.grey.shade300,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DottedBorderBox — copied verbatim from Pages/BoardView.dart (Phase 5,
// Part 4). `BoardView.dart` is scheduled for full deletion in Phase 6; this
// was the one live cross-cluster dependency this file had on it (grep-
// confirmed every other reference to that file from here was doc-comment
// prose, not code). `BoardView.dart` keeps its own copy until Phase 6
// deletes that whole file — same "temporary duplicate for one phase"
// pattern already used for `DobCard` in `Pages/StudentProfilePage.dart`.
// -----------------------------------------------------------------------------

class DottedBorderBox extends StatelessWidget {
  final Widget child;

  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: child,
    );
  }
}
