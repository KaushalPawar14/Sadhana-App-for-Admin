import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../Pages/StudentComments.dart';
import '../Pages/StudentProfilePage.dart';
import '../Services/HierarchyApi.dart';
import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../actions/BookActions.dart';
import '../utils/BoardData.dart';
import '../utils/BoardQueries.dart';
import '../utils/BookProgressData.dart';
import '../utils/SeenMarkers.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentDeletion.dart';
import '../utils/StudentScope.dart';
import '../utils/UnseenDot.dart';
import '../widgets/GuideBoard.dart';
import '../widgets/GuideBoardGhost.dart';
import '../widgets/GuideBoardMotion.dart';
import '../widgets/GuideGhost.dart';
import '../widgets/GuideReveal.dart';
import '../widgets/GuideSheet.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideChips.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import 'Calendar.dart';
import '../widgets/GuideDialog.dart';

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
/// Visibility — role-based admin hierarchy (Master 2, Part A.2)
/// ---------------------------------------------------------------------------
/// The board's students come from `StudentScope.current().studentsStream()`
/// (HOD: unfiltered; everyone else: only the students the security rules let
/// them read), and the COLUMNS follow the viewer's role, in two gender lanes
/// (males, then females) so a female student is never shown in a male column
/// and vice versa:
///  * HOD: every admin's column (Guides, Male Enablers, other HODs in the
///    males lane; Female Enablers in the females lane) + Unassigned (males)
///    + Unassigned (females).
///  * Guide: his own column + one column per Male Enabler on his team +
///    Unassigned (males).
///  * Male Enabler: his own column + Unassigned (males).
///  * Female Enabler: her own column + Unassigned (females).
/// Every reassignment goes through `HierarchyApi.assignStudent` (the server
/// re-checks authority); [_handleDrop] blocks cross-gender and out-of-scope
/// drops in the UI first, with a snackbar saying why.
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
/// its own, narrower rule. [_ensureBoard] runs for the HOD only: the security rules let only
/// the HOD read or create the shared board, so a Guide or an Enabler never waits for it - their
/// lanes come from their profile and the students they may read ([_board]), with an in-memory
/// Unassigned column ([kUnassignedLocalColumn]). Idempotent (`_ensuring`/`_ensured` guard, plus
/// `ensureGuideAssignmentBoard` itself no-ops if the board already exists).
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

  /// Forgets what the board remembers between visits (tests).
  @visibleForTesting
  static void debugResetBoardMemory() => _FolkBoysWorkspaceState._resetBoardMemory();

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

  /// The student's name EXACTLY as stored on `users` (not trimmed). Every name-keyed
  /// collection (sadhana reports, scorecard, competition) is keyed by this exact string,
  /// because the Student app writes it that way. A name with a stray space ("Dhiraj Kumar ")
  /// looked up by the trimmed [name] opened an empty folder: the guide saw an all-red
  /// calendar while the student's own calendar was all green. Use [reportKey] for lookups,
  /// [name] only for display and sorting.
  final String reportKey;
  final String role;
  final String guideId;

  /// The owning Guide of this student's team (`users.teamGuide`) and the
  /// student's gender ('male' | 'female' | '' when unknown) — both as stored
  /// on the `users` document; only read here, never written (assignment goes
  /// through `HierarchyApi.assignStudent`).
  final String teamGuide;
  final String gender;

  /// Manually-added ("offline roster") student — no auth account yet,
  /// recorded by a guide. See `utils/ManualStudents.dart`'s own header.
  /// Part 5, this task: badged on the card face (`_cardBody`) so a guide
  /// can always tell a guide-entered student from an app-registered one.
  final bool isManualEntry;

  const _Boy({
    required this.uid,
    required this.name,
    String? reportKey,
    required this.role,
    required this.guideId,
    this.teamGuide = '',
    this.gender = '',
    this.isManualEntry = false,
  }) : reportKey = reportKey ?? name;

  /// Which lane the board shows him in: a student whose gender is not
  /// explicitly 'female' is shown in the males lane.
  bool get isFemale => gender == 'female';
  String get lane => isFemale ? 'female' : 'male';

  StudentRef get ref => StudentRef(
      uid: uid, guideId: guideId, teamGuide: teamGuide, gender: gender);

  /// Assembles a card from a `users` document; null for a nameless document.
  static _Boy? fromUser(String uid, Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final ref = StudentRef.fromUser(uid, data);
    return _Boy(
      uid: uid,
      name: name,
      reportKey: (data['name'] ?? '').toString(),
      role: (data['role'] ?? '').toString(),
      guideId: ref.guideId,
      teamGuide: ref.teamGuide,
      gender: ref.gender,
      isManualEntry: data['isManualEntry'] == true,
    );
  }
}

/// One rendered column of the Guide Assignment board: a stored (or, when the
/// stored document does not exist yet, synthesised) [BoardColumn] shown in a
/// gender [lane]. The Unassigned column is shown once per visible lane.
class _LaneColumn {
  final BoardColumn column;

  /// 'male' | 'female' — the only students this column ever shows or accepts.
  final String lane;

  /// Display title (an admin's display name, or "Unassigned").
  final String title;

  /// The column's admin (null for Unassigned).
  final AdminSummary? admin;

  const _LaneColumn({
    required this.column,
    required this.lane,
    required this.title,
    required this.admin,
  });

  bool get isUnassigned => column.kind == kColumnKindUnassigned;

  /// The `guideId` a student dropped here ends up with ('' = Unassigned).
  String get targetGuideId => isUnassigned ? '' : column.guideId;

  bool holds(_Boy b) =>
      b.lane == lane && (isUnassigned ? b.guideId.isEmpty : b.guideId == column.guideId);
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
  /// The width of a board column on this screen: 330 dp where the screen allows
  /// it, narrower on a small phone so the next column always peeks 28 dp (the
  /// "swipe for more" hint). Set from [build].
  double _colW = GuideBoardTokens.columnWidth;

  static double _columnWidthFor(double screenWidth) =>
      (screenWidth - GuideSpace.pagePadding - GuideBoardTokens.columnGap - GuideBoardTokens.peek)
          .clamp(260.0, GuideBoardTokens.columnWidth);

  /// How many books a level lists before "Show N more".
  static const int _booksShown = 5;

  /// Levels (keyed `uid_level`) whose whole book list is showing.
  final Set<String> _allBooksShown = {};

  /// Where the columns were scrolled to the last time (kept for the whole app session, so even a board that
  /// is built again starts exactly where it was).
  static double _lastHorizontalOffset = 0;

  late final ScrollController _hController =
      ScrollController(initialScrollOffset: _lastHorizontalOffset)
        ..addListener(() {
          if (_hController.hasClients) _lastHorizontalOffset = _hController.offset;
        });

  // ---------------------------------------------------------------------------
  // The board never starts over (no blink when a page opened from it is closed)
  // ---------------------------------------------------------------------------
  //
  // Every stream below used to be created inside `build`, so any rebuild of the board (and the board
  // rebuilds whenever anything under it changes) dropped its listeners and opened new ones, and a board
  // built afresh started from the loading ghost again. Now:
  //  * a stream is created ONCE per slot (and again only when its key changes: another board);
  //  * the last answer of each slot is kept for the whole session ([_lastData]) and is the first thing a
  //    new listener shows, so the ghost appears only on the very first load of the app session; a refresh
  //    updates the cards in place;
  //  * the "reveal" fade plays once per session, not on every return ([_everRevealed]);
  //  * each column's vertical scroll is stored under the column's own key (PageStorage).
  final Map<String, ({Object key, Object stream})> _streams = {};

  /// The last answer of every slot, per signed-in admin (an admin never sees another's).
  static final Map<String, Object?> _lastData = {};
  static bool _everRevealed = false;

  static void _resetBoardMemory() {
    _lastData.clear();
    _everRevealed = false;
    _lastHorizontalOffset = 0;
  }

  Widget _live<T>({
    required String slot,
    String key = '',
    required Stream<T> Function() stream,
    required AsyncWidgetBuilder<T> builder,
  }) {
    final memo = _streams[slot];
    final Stream<T> s;
    if (memo != null && memo.key == key) {
      s = memo.stream as Stream<T>;
    } else {
      s = stream();
      _streams[slot] = (key: key, stream: s);
    }
    final cacheKey = '${AdminProfileProvider.current?.id ?? ''}|$slot|$key';
    return StreamBuilder<T>(
      stream: s,
      initialData: _lastData[cacheKey] as T?,
      builder: (context, snap) {
        if (snap.hasData) _lastData[cacheKey] = snap.data;
        return builder(context, snap);
      },
    );
  }

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
  bool _ensureFailed = false;
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

  /// Whether the signed-in admin is a HOD — read from the loaded admin
  /// profile (several HODs may exist; no admin id is special).
  bool get _isHod => AdminProfileProvider.viewerIsHod;

  /// Students whose book commitment (set by a guide) this admin has not seen: their cards
  /// show a dot, so what the Home tile's dot counts can always be found and opened.
  final ValueNotifier<Map<String, Set<String>>> _commitmentUnseen =
      ValueNotifier<Map<String, Set<String>>>(const {});
  StreamSubscription<Map<String, Set<String>>>? _commitmentSub;

  /// Students whose NEW suggestions (made by the server after an interaction) are not opened yet: the
  /// profile icon of each one's card shows a dot, and the profile itself says "New suggestions ready".
  final ValueNotifier<Set<String>> _suggestionsUnseen = ValueNotifier<Set<String>>(const {});
  StreamSubscription<Set<String>>? _suggestionsSub;

  /// Books already sent to be marked seen (so a rebuild never writes twice).
  final Set<String> _sentSeen = {};
  final Map<String, Timer> _seenTimers = {};

  /// How long an unseen book stays marked after its row is on screen: long enough to notice.
  static const Duration _seenDelay = Duration(milliseconds: 1500);

  String _bookDocId(_Boy boy, BookConfigEntry b) => '${boy.uid}_${b.level}_${b.key}';

  /// The book is seen now (tapped, or its row has been on screen for a moment).
  void _markBookSeen(_Boy boy, String bookDocId) {
    if (!(_commitmentUnseen.value[boy.uid]?.contains(bookDocId) ?? false)) return;
    if (!_sentSeen.add(bookDocId)) return;
    _seenTimers.remove(bookDocId)?.cancel();
    BoardData.instance.markBooksSeen(_guide, boy.uid, [bookDocId]);
  }

  /// These books' rows are on screen (their level is open): mark each seen shortly after.
  void _scheduleSeen(_Boy boy, String level, Iterable<String> bookDocIds) {
    final unseen = _commitmentUnseen.value[boy.uid];
    if (unseen == null) return;
    for (final id in bookDocIds) {
      if (!unseen.contains(id) || _sentSeen.contains(id) || _seenTimers.containsKey(id)) continue;
      _seenTimers[id] = Timer(_seenDelay, () {
        _seenTimers.remove(id);
        // Still on screen? (the card and the level are still open)
        if (!mounted ||
            !_expandedUids.contains(boy.uid) ||
            !_expandedLevels.contains('${boy.uid}_$level')) {
          return;
        }
        _markBookSeen(boy, id);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _commitmentSub = BoardData.instance.unseenCommitments(_guide).listen(
      (uids) => _commitmentUnseen.value = uids,
      onError: (_) {},
    );
    _suggestionsSub = BoardData.instance.unseenSuggestions(_guide).listen(
      (uids) => _suggestionsUnseen.value = uids,
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _commitmentSub?.cancel();
    _suggestionsSub?.cancel();
    _suggestionsUnseen.dispose();
    for (final t in _seenTimers.values) {
      t.cancel();
    }
    _commitmentUnseen.dispose();
    _hController.dispose();
    super.dispose();
  }

  /// The students this viewer may see: `StudentScope`'s merged, rules-provable
  /// queries (HOD: the unfiltered collection; Guide: his team + unassigned
  /// males; Male Enabler: own + unassigned males; Female Enabler: own +
  /// unassigned females). Never the whole `users` collection for a non-HOD.
  /// Sorted/bucketed in memory by the callers (no `orderBy`, no index).
  Stream<QuerySnapshot<Map<String, dynamic>>> _studentsStream() =>
      BoardData.instance.students();

  /// Human name of an admin id (falls back to the id itself).
  String _adminName(String id) =>
      id.isEmpty ? "" : (AdminProfileProvider.require().adminById(id)?.displayName ?? id);

  /// The admins whose columns this viewer sees on the board:
  ///  * HOD: every admin the profile lists (incl. other HODs).
  ///  * Guide: himself + his Male Enablers.
  ///  * Male / Female Enabler: herself/himself only.
  List<AdminSummary> _boardAdmins(AdminProfile p) {
    if (p.isHod) return p.admins;
    final me = p.adminById(p.id) ??
        AdminSummary(
          id: p.id,
          displayName: p.displayName,
          role: p.role,
          teamGuide: p.teamGuide,
        );
    return [me, if (p.isGuide) ...p.myMaleEnablers];
  }

  /// The board's columns for this viewer, in two gender lanes (males, then
  /// females) — see this file's header. One column per visible admin (taken
  /// from the stored `guide` columns; synthesised in memory when an admin's
  /// column document has not been created yet, so a new admin shows up at
  /// once) plus the Unassigned column of every lane the viewer may see (HOD:
  /// both; anyone else: only his/her own gender's lane). The viewer's own
  /// column comes first in its lane, the rest in stored order.
  List<_LaneColumn> _visibleColumns(List<BoardColumn> all) {
    final p = AdminProfileProvider.require();
    final byGuide = <String, BoardColumn>{};
    BoardColumn? unassigned;
    for (final c in all) {
      if (c.kind == kColumnKindUnassigned) {
        unassigned ??= c;
      } else if (c.isGuideColumn) {
        byGuide.putIfAbsent(c.guideId, () => c);
      }
    }

    final admins = _boardAdmins(p);
    final out = <_LaneColumn>[];
    for (final lane in const ['male', 'female']) {
      final inLane = admins.where((a) => a.role.gender == lane).toList()
        ..sort((a, b) {
          if (a.id == p.id) return b.id == p.id ? 0 : -1;
          if (b.id == p.id) return 1;
          final o = (byGuide[a.id]?.order ?? 1 << 20)
              .compareTo(byGuide[b.id]?.order ?? 1 << 20);
          return o != 0
              ? o
              : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
      for (var i = 0; i < inLane.length; i++) {
        final a = inLane[i];
        out.add(_LaneColumn(
          column: byGuide[a.id] ??
              BoardColumn(
                id: '',
                title: a.id,
                order: 1 << 20,
                colorValue: kColumnPalette[i % kColumnPalette.length],
                kind: kColumnKindGuide,
                guideId: a.id,
              ),
          lane: lane,
          title: a.displayName,
          admin: a,
        ));
      }
      if (unassigned != null && (p.isHod || p.gender == lane)) {
        out.add(_LaneColumn(
          column: unassigned,
          lane: lane,
          title: p.isHod
              ? "$kUnassignedTitle (${lane == 'male' ? 'males' : 'females'})"
              : kUnassignedTitle,
          admin: null,
        ));
      }
    }
    return out;
  }

  /// Creates the shared Guide Assignment board when it does not exist yet. HOD ONLY: the
  /// security rules let only the HOD read or create that board, so for anyone else this
  /// could never succeed (and the board never waits for it, see [_board]). A failure is
  /// remembered so the board can say so with Retry instead of breathing forever.
  Future<void> _ensureBoard(List<BoardDoc> all, String guide) async {
    if (_ensuring || _ensured || _ensureFailed) return;
    _ensuring = true;
    try {
      await BoardData.instance.ensureGuideBoard(all: all, hodGuide: guide);
      _ensured = true;
    } catch (_) {
      _ensureFailed = true;
      if (mounted) setState(() {});
    }
    _ensuring = false;
  }

  /// How long the board waits for a first answer before it stops breathing and offers Retry.
  static const Duration _firstAnswerWithin = Duration(seconds: 20);

  /// [source] with a limit on the FIRST event only (a quiet snapshot stream is normal
  /// afterwards): when nothing arrives in time it errors, so the board shows Retry.
  Stream<T> _within<T>(Stream<T> source) {
    StreamSubscription<T>? sub;
    Timer? timer;
    late final StreamController<T> out;
    out = StreamController<T>(
      onListen: () {
        timer = Timer(_firstAnswerWithin, () {
          if (!out.isClosed) out.addError(TimeoutException('no first answer', _firstAnswerWithin));
        });
        sub = source.listen(
          (e) {
            timer?.cancel();
            out.add(e);
          },
          onError: (Object error, StackTrace st) {
            timer?.cancel();
            out.addError(error, st);
          },
          onDone: () {
            timer?.cancel();
            out.close();
          },
        );
      },
      onCancel: () {
        timer?.cancel();
        return sub?.cancel();
      },
    );
    return out.stream;
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

  /// ⚠️ **Permission model — role-based (Master 2, Part A.2).**
  ///  * Gender always applies: a female student can only be dropped on a
  ///    Female Enabler's column or the females' Unassigned, a male student
  ///    never on a Female Enabler's column.
  ///  * HOD: may move anyone anywhere (subject to the gender rule).
  ///  * Guide: may move students within his team (himself + his Male
  ///    Enablers), claim an unassigned male for HIMSELF, and release his OWN
  ///    students to Unassigned (not his Male Enablers' students).
  ///  * Male Enabler: may claim an unassigned male for himself and release
  ///    his own students.
  ///  * Female Enabler: may claim an unassigned female for herself and
  ///    release her own students.
  ///
  /// ⚠️ **Re-checked here regardless of what the UI offers** (`_columnTile`
  /// accepts every hover so a refusal can be EXPLAINED instead of the card
  /// silently bouncing back). A blocked move never reaches the server — a
  /// snackbar says why. The server (`assignStudent`) enforces the same rules
  /// again; if it still refuses, its own message is shown.
  Future<void> _handleDrop({
    required String boardId,
    required _Boy boy,
    required _LaneColumn target,
    required int orderInTarget,
  }) async {
    _markSettle(boy.uid);
    final p = AdminProfileProvider.require();
    final oldGuide = boy.guideId.trim();
    final newGuide = target.targetGuideId;

    // Gender first — also for an unassigned -> unassigned drop in the other
    // lane, which would otherwise look like a harmless no-op.
    if (boy.lane != target.lane) {
      _blockedMove(boy.isFemale
          ? "${boy.name} is a female student — she can only be placed with a "
              "Female Enabler or in Unassigned (females)."
          : "${boy.name} is a male student — he cannot be placed with a "
              "Female Enabler.");
      return;
    }

    if (oldGuide == newGuide) return;

    final reason = _moveBlockedReason(p, boy, oldGuide, newGuide);
    if (reason != null) {
      _blockedMove(reason);
      return;
    }

    final _MoveKind moveKind;
    if (p.isHod) {
      moveKind = _MoveKind.hodReassign;
    } else if (oldGuide.isEmpty && newGuide == p.id) {
      moveKind = _MoveKind.claim;
    } else if (oldGuide == p.id && newGuide.isEmpty) {
      moveKind = _MoveKind.release;
    } else {
      moveKind = _MoveKind.hodReassign; // a Guide moving within his team
    }

    final confirmed = await _confirmReassignment(
      boy: boy,
      fromGuide: oldGuide.isEmpty ? null : _adminName(oldGuide),
      toGuide: newGuide.isEmpty ? null : _adminName(newGuide),
      moveKind: moveKind,
    );
    if (confirmed != true) return;

    try {
      await HierarchyApi.instance.assignStudent(
        studentId: boy.uid,
        toGuideId: newGuide,
        // A column that does not exist as a document yet (just-added admin)
        // is not sent — the assignment itself still goes through.
        boardId: target.column.id.isEmpty ? null : boardId,
        columnId: target.column.id.isEmpty ? null : target.column.id,
        order: target.column.id.isEmpty ? null : orderInTarget,
      );
      if (!mounted) return;
      showSnackbar(
        context,
        newGuide.isEmpty
            ? "${boy.name} is now unassigned"
            : "${boy.name} reassigned to ${_adminName(newGuide)}",
        Colors.green,
        Icons.check_circle,
      );
    } on HierarchyException catch (e) {
      if (!mounted) return;
      showSnackbar(context, e.message, Colors.red, Icons.error);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not reassign", Colors.red, Icons.error);
    }
  }

  void _blockedMove(String message) {
    if (!mounted) return;
    showSnackbar(context, message, Colors.orange.shade800, Icons.block);
  }

  /// Why [p] may not move [boy] from [oldGuide] to [newGuide] ('' =
  /// Unassigned), or null when the move is allowed. The gender rule has
  /// already been applied by the caller. Mirrors the server's rule.
  String? _moveBlockedReason(
      AdminProfile p, _Boy boy, String oldGuide, String newGuide) {
    if (p.isHod) return null;
    if (!StudentScope(p).canManage(boy.ref)) {
      return "${boy.name} is not one of your students.";
    }

    final claimOnlyYourself = oldGuide.isEmpty && newGuide != p.id
        ? "You can only claim an unassigned student for yourself."
        : null;

    if (p.isGuide) {
      final team = <String>{p.id, ...p.myMaleEnablers.map((a) => a.id)};
      if (oldGuide.isEmpty) return claimOnlyYourself;
      if (!team.contains(oldGuide)) {
        return "${boy.name} is not on your team.";
      }
      if (newGuide.isEmpty) {
        return oldGuide == p.id
            ? null
            : "${boy.name} is ${_adminName(oldGuide)}'s student — only "
                "${_adminName(oldGuide)} or the HOD can release him.";
      }
      return team.contains(newGuide)
          ? null
          : "You can only move students within your team.";
    }

    // Male / Female Enabler.
    if (oldGuide.isEmpty) return claimOnlyYourself;
    if (oldGuide == p.id) {
      return newGuide.isEmpty
          ? null
          : "You can only release your own students to Unassigned.";
    }
    return "${boy.name} is not your student.";
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
      builder: (ctx) => GuideDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(boy.name, style: ctx.gText.cardTitle),
              const SizedBox(height: 12),
              _fromToRow(ctx, "Currently with", from),
              const SizedBox(height: 6),
              _fromToRow(ctx, "Moving to", to, emphasised: true),
              const SizedBox(height: 14),
              GuideNotice(
                child: Text(
                  "This changes who can see his private information and who "
                  "receives his notifications from now on.\n\n"
                  "His existing history stays with $from — past associations, "
                  "flagged messages, LIT assessments and interaction logs do "
                  "NOT transfer. Nothing already recorded is moved, copied or "
                  "deleted.",
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
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _fromToRow(BuildContext ctx, String label, String value,
      {bool emphasised = false}) {
    final g = ctx.g;
    final t = ctx.gText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 104, child: Text(label, style: t.caption)),
        Expanded(
          child: Text(
            value,
            style: t.bodyStrong.copyWith(color: emphasised ? g.brass : g.text),
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
      // message, not add real enforcement.
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final boy = _findBoy(allBoys, details.data);
        if (boy == null) return;
        _handleDeleteDrop(boy);
      },
      builder: (context, candidate, rejected) {
        final g = context.g;
        final hovering = candidate.isNotEmpty;
        final tone = hovering ? g.danger : g.mutedText;
        return Container(
          margin: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 0, GuideSpace.pagePadding, 8),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
          decoration: BoxDecoration(
            color: hovering ? g.danger.withValues(alpha: .12) : g.surface,
            borderRadius: BorderRadius.circular(GuideShape.cardRadius),
            border: Border.all(color: hovering ? g.danger : g.border, width: hovering ? 2 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline_rounded, color: tone),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  hovering ? "Release to delete permanently" : "Drop here to delete permanently",
                  textAlign: TextAlign.center,
                  style: context.gText.bodyStrong.copyWith(color: tone),
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
    // HOD: anyone. Anyone else: only an assigned student they may manage
    // (their own, or — for a Guide — one of his Male Enablers').
    if (!_isHod &&
        (boy.guideId.isEmpty ||
            !StudentScope.current().canManage(boy.ref))) {
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
      builder: (_) => const GuideBusyDialog(message: 'Removing the student'),
    );

    // guideId/isHod no longer passed (Master Task, 2026-09-14) — the
    // Cloud Function derives the caller's own identity server-side now,
    // from their locked, email-resolved adminUsers record.
    final result = await deleteStudentEverywhere(uid: boy.uid, name: boy.reportKey);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close the working dialog
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
      builder: (ctx) => GuideDialog(
        title: const Text("Delete this boy permanently?"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(boy.name, style: ctx.gText.cardTitle),
              const SizedBox(height: 14),
              GuideNotice(
                danger: true,
                child: Text(
                  "This permanently deletes ALL of ${boy.name}'s data — "
                  "sadhana reports, scores, book progress, LIT assessments, "
                  "interaction logs, comments, friends and everything else "
                  "recorded about him across this app — AND his sign-in "
                  "account (Firebase Authentication). This CANNOT be "
                  "undone. If he returns, he will need to register again "
                  "from scratch.",
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
            style: ElevatedButton.styleFrom(
                backgroundColor: ctx.g.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete permanently"),
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
        builder: (ctx) => GuideDialog(
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
      builder: (ctx) => GuideDialog(
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
                  color = ctx.g.text;
                } else if (auth.hadNoAuthAccount) {
                  line = "Sign-in account: none existed (manual entry, or "
                      "already removed)";
                  color = ctx.g.text;
                } else {
                  line = "⚠️ Sign-in account could NOT be removed: "
                      "${auth.error}. His data has still been deleted below "
                      "— if he signs in again, he will be treated as a new "
                      "registration.";
                  color = ctx.g.danger;
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
                      fontWeight: FontWeight.bold, color: ctx.g.danger),
                ),
                const SizedBox(height: 4),
                ...failed.map((s) => Text(
                      "• ${s.label}: ${s.error}",
                      style:
                          TextStyle(fontSize: 12.5, color: ctx.g.danger),
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
                    color: ctx.g.mutedText),
              ),
              const SizedBox(height: 4),
              ...result.notFullyScrubbed.map((s) => Text(
                    "• $s",
                    style:
                        TextStyle(fontSize: 11, color: ctx.g.mutedText),
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
  // Residence — shown by the group avatar and pill on each card (`GuideGroup`:
  // FOLK / Hostel / Localite, from `users.role`), with the legend under the top
  // bar (`GuideGroupLegend`). A missing or unexpected role gets a neutral avatar
  // and no pill, never a crash and never a hidden card; the board never writes
  // `users.role`.
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// ⚠️ **Phase 4 — this method decides mandatory-vs-custom, but does not
  /// change how the mandatory board itself renders**: the `_activeBoardId ==
  /// null` branch calls `_board(guide)`. A non-null id routes to
  /// [_customBoardBody] — a fully separate rendering path. The extra
  /// `allBoardsStream()` listener here only drives the top bar's title and its
  /// owner-only actions.
  @override
  Widget build(BuildContext context) {
    _colW = _columnWidthFor(MediaQuery.sizeOf(context).width);
    final guide = _guide;
    return _live<List<BoardDoc>>(
      slot: 'topBoards',
      stream: () => BoardData.instance.boards(),
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
          // The active board vanished (deleted, or no longer shared with this
          // viewer) — fall back to the mandatory board rather than rendering a
          // dead reference. Scheduled for after this frame, since `setState`
          // cannot run during `build`.
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
            : (activeCustomBoard.title.isEmpty ? "(untitled)" : activeCustomBoard.title);

        // Share / rename / delete are owner-only — see `isBoardOwner`'s doc
        // comment for why this is a narrower gate than day-to-day editing.
        final canShare =
            activeCustomBoard != null && isBoardOwner(board: activeCustomBoard, guide: guide);

        return GuideScaffold(
          body: Column(
            children: [
              GuideTopBar(
                title: title,
                titleMaxLines: 2,
                actions: [
                  // Switch board (the board / table view switch).
                  GuideRoundButton(
                    icon: Icons.view_list_rounded,
                    tooltip: "Switch board",
                    onPressed: () => _openBoardSwitcher(guide),
                  ),
                  // "New board" — a plain action in the top bar (no FAB: a FAB
                  // sat over the last row of cards).
                  GuideRoundButton(
                    icon: Icons.add_rounded,
                    tooltip: "New board",
                    onPressed: () => _createBoard(guide),
                  ),
                  // Share, rename, delete — owner-only (`canShare` is
                  // `isBoardOwner`). Share used to be its own icon; it now sits
                  // in this one menu with the other two.
                  if (canShare)
                    PopupMenuButton<String>(
                      tooltip: "Board options",
                      onSelected: (v) {
                        switch (v) {
                          case 'share':
                            _shareCustomBoard(activeCustomBoard!, guide);
                          case 'rename':
                            _renameCustomBoard(activeCustomBoard!);
                          case 'delete':
                            _deleteCustomBoard(activeCustomBoard!, guide);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'share', child: Text("Share board")),
                        PopupMenuItem(value: 'rename', child: Text("Rename board")),
                        PopupMenuItem(value: 'delete', child: Text("Delete board")),
                      ],
                      child: const GuideRoundIcon(icon: Icons.more_horiz_rounded),
                    ),
                ],
              ),
              Expanded(
                child: guide.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            "No guide selected on this device.",
                            textAlign: TextAlign.center,
                            style: context.gText.body,
                          ),
                        ),
                      )
                    : (_activeBoardId == null
                        ? _board(guide)
                        : _customBoardBody(guide, _activeBoardId!)),
              ),
            ],
          ),
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
      builder: (ctx) => GuideDialog(
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
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            final g = context.g;
            final t = context.gText;
            return StreamBuilder<List<BoardDoc>>(
              stream: BoardData.instance.boards(),
              builder: (context, snap) {
                if (!snap.hasData) return _sheetWait(snap);
                // ⚠️ The mandatory board's own tile is found directly from the
                // UNFILTERED list, not from `visibleBoards()` — that function's
                // `isGuideAssignment` branch is HOD-only by design, which is
                // right for a generic "boards you own" list but wrong here:
                // EVERY viewer, HOD or not, must be able to switch back to the
                // mandatory board from inside a custom board, since
                // `_activeBoardId == null` is this workspace's own default
                // state for everyone. The mandatory board's real access control
                // lives entirely inside `_board()` itself.
                final mandatory = snap.data!.where((b) => b.isGuideAssignment).toList();
                final custom = visibleBoards(
                  all: snap.data!,
                  guide: guide,
                  isHod: _isHod,
                ).where((b) => !b.isGuideAssignment).toList();

                Widget row({
                  required IconData icon,
                  required String title,
                  required String subtitle,
                  required bool selected,
                  required VoidCallback onTap,
                }) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      child: GuideCard(
                        color: selected ? g.chipBackground : null,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Row(
                            children: [
                              Icon(icon, color: g.mutedText),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(title, style: t.cardTitleSmall),
                                    Text(subtitle, style: t.caption),
                                  ],
                                ),
                              ),
                              if (selected) Icon(Icons.check_rounded, color: g.brass),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    const Padding(padding: EdgeInsets.only(bottom: 14), child: GuideSheetHandle()),
                    Text("Boards", style: t.sectionTitle),
                    const SizedBox(height: 12),
                    ...mandatory.map((b) => row(
                          icon: Icons.groups_outlined,
                          title: "Guide Assignment",
                          subtitle: "The mandatory board",
                          selected: _activeBoardId == null,
                          onTap: () {
                            setState(() => _activeBoardId = null);
                            Navigator.pop(sheetContext);
                          },
                        )),
                    const SizedBox(height: 8),
                    Text("Custom boards", style: t.small.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (custom.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          "No custom boards yet — tap \"New board\" to create one.",
                          textAlign: TextAlign.center,
                          style: t.small,
                        ),
                      )
                    else
                      ...custom.map((b) {
                        final owned = b.isOwnedBy(guide);
                        final subtitle = owned
                            ? (b.sharedWith.isEmpty
                                ? "Yours"
                                : "Yours · shared with ${b.sharedWith.map(_adminName).join(', ')}")
                            : "Shared by ${_adminName(b.ownerGuideId)}";
                        return row(
                          icon: Icons.dashboard_outlined,
                          title: b.title.isEmpty ? "(untitled)" : b.title,
                          subtitle: subtitle,
                          selected: _activeBoardId == b.id,
                          onTap: () {
                            setState(() => _activeBoardId = b.id);
                            Navigator.pop(sheetContext);
                          },
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

  /// Per-person sharing (Phase 4, Part 4). Lists the admins in the signed-in
  /// admin's profile (`AdminProfile.admins` — `adminUsers` is server-side
  /// only now) as checkboxes, preselected with
  /// the board's current `sharedWith`. A single overwrite on Save via
  /// `setBoardSharedWith` — owner-only, matching [isBoardOwner]; this method
  /// is only ever reachable from the AppBar's share icon, which is itself
  /// only shown when `isBoardOwner` is true (see `build()`).
  Future<void> _shareCustomBoard(BoardDoc board, String guide) async {
    final selected = Set<String>.from(board.sharedWith);
    // A board can never be shared with its own owner — that guide already
    // has full access by ownership, and including them would be meaningless.
    final choices = AdminProfileProvider.require()
        .admins
        .where((a) => a.id != guide)
        .toList();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => GuideDialog(
            title: const Text("Share this board"),
          content: SizedBox(
            width: double.maxFinite,
            child: choices.isEmpty
                ? const Text("No other guides exist yet to share with.")
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          "Anyone checked gets full control of this board — "
                          "they can move cards, add/rename/delete columns, "
                          "and rename the board itself, the same as you. "
                          "They cannot delete the board or change who it is "
                          "shared with — that stays with you.",
                          style: TextStyle(fontSize: 12, color: ctx.g.mutedText),
                        ),
                      ),
                      ...choices.map((a) => CheckboxListTile(
                            value: selected.contains(a.id),
                            title: Text(a.displayName),
                            subtitle: Text(a.role.label),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selected.add(a.id);
                              } else {
                                selected.remove(a.id);
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
      builder: (ctx) => GuideDialog(
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
            style: ElevatedButton.styleFrom(
                backgroundColor: ctx.g.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
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
      builder: (ctx) => GuideDialog(
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
                              ? ctx.g.text
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
      builder: (ctx) => GuideDialog(
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
            style: ElevatedButton.styleFrom(
                backgroundColor: ctx.g.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
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
      builder: (ctx) => GuideDialog(
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
            style: ElevatedButton.styleFrom(
                backgroundColor: ctx.g.warning, foregroundColor: ctx.g.onPrimary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await removePlacement(boardId, boy.uid);
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
                  stream: _studentsStream(),
                  builder: (context, userSnap) {
                    if (!userSnap.hasData) return _sheetWait(userSnap);
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: BoardData.instance.placements(boardId),
                      builder: (context, placeSnap) {
                        final placedUids = (placeSnap.data?.docs ?? [])
                            .map((d) => d.id)
                            .toSet();

                        final candidates = <_Boy>[];
                        for (final doc in userSnap.data!.docs) {
                          if (placedUids.contains(doc.id)) continue;
                          final boy = _Boy.fromUser(doc.id, doc.data());
                          if (boy == null) continue;
                          if (!_customBoardEligible(boy)) continue;
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
                                  const Padding(padding: EdgeInsets.only(bottom: 14), child: GuideSheetHandle()),
                                  Text(
                                    "Add students to \"${column.title}\"",
                                    style: context.gText.sectionTitle,
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
                                          style: context.gText.small,
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
                                                  style: context.gText.caption
                                                      .copyWith(color: context.g.warning),
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
        await BoardData.instance.movePlacement(
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

  /// The board's ghost (two columns) while data loads, or frozen with Retry on a failed (or
  /// unanswered) stream. `setState` re-subscribes: every stream here is built in `build`.
  Widget _boardWait(AsyncSnapshot<Object?>? snap, {bool failed = false}) {
    final ghost = GuideBoardGhost(columnWidth: _colW);
    if (failed || (snap?.hasError ?? false)) {
      return GuideErrorOverGhost(
        ghost: ghost,
        message: 'Could not load the board. Check your connection and try again.',
        onRetry: () => setState(() {
          // a failed stream is dead: Retry listens again from scratch
          _streams.clear();
          _ensureFailed = false;
        }),
      );
    }
    return GuideGhostArea(child: ghost);
  }

  /// Nothing to show: the ghost, still, with a short friendly line.
  Widget _boardEmpty() => GuideEmptyOverGhost(
        ghost: GuideBoardGhost(columnWidth: _colW),
        title: 'No students yet',
        message: 'Students will appear here as soon as they join and are assigned to you.',
      );

  /// The loaded board, cross-faded in over the ghost it replaces.
  Widget _boardReveal(Widget content) {
    final animate = !_everRevealed;
    _everRevealed = true;
    return GuideReveal(ghost: GuideBoardGhost(columnWidth: _colW), animate: animate, child: content);
  }

  /// A bottom sheet's list while it loads: ghost rows (or Retry if it failed).
  Widget _sheetWait(AsyncSnapshot<Object?> snap) {
    if (snap.hasError) {
      return GuideStateView(
        state: GuideLoad.error,
        ghost: const GuideGhostList(rows: 5, rowHeight: 56, pulsing: false),
        content: const SizedBox.shrink(),
        onRetry: () => setState(() {}),
      );
    }
    return const GuideGhostList(rows: 5, rowHeight: 56);
  }

  /// A book-progress line while it loads.
  Widget _bookGhost() => const GuideGhostArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: GuideGhostBar(height: 14),
        ),
      );

  /// The mandatory board. Every state leaves the loading ghost: data -> the board, nothing to
  /// show -> a still ghost with a friendly line, an error or no first answer in time -> a
  /// frozen ghost with Retry.
  ///
  /// Only the HOD reads or creates the shared Guide Assignment board (the security rules), so
  /// ONLY the HOD waits for it. A Guide or an Enabler never does: their lanes come from their
  /// profile (themselves, a Guide's Male Enablers) plus the students the rules let them read.
  Widget _board(String guide) {
    if (!AdminProfileProvider.require().isHod) {
      return _boardBody(
        guide: guide,
        boardId: '',
        columns: const [kUnassignedLocalColumn],
        reconcile: false,
      );
    }
    return _live<List<BoardDoc>>(
      slot: 'guideBoards',
      stream: () => _within(BoardData.instance.boards()),
      builder: (context, boardsSnap) {
        if (!boardsSnap.hasData) return _boardWait(boardsSnap);
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
          if (_ensureFailed) return _boardWait(null, failed: true);
          return _boardWait(boardsSnap);
        }
        final boardId = board.id;

        return _live<List<BoardColumn>>(
          slot: 'guideColumns',
          key: boardId,
          stream: () => _within(BoardData.instance.columns(boardId)),
          builder: (context, colSnap) {
            if (!colSnap.hasData) return _boardWait(colSnap);
            return _boardBody(
              guide: guide,
              boardId: boardId,
              columns: colSnap.data!,
              reconcile: true,
            );
          },
        );
      },
    );
  }

  /// The lanes and cards, once the columns are known. [boardId] is empty (and [reconcile]
  /// false) for a viewer without the shared board: nothing is written to it.
  Widget _boardBody({
    required String guide,
    required String boardId,
    required List<BoardColumn> columns,
    required bool reconcile,
  }) {
    return _live<QuerySnapshot<Map<String, dynamic>>>(
      // The students THIS viewer may see: `StudentScope`'s scoped stream (HOD: the
      // unfiltered collection, which is what lets the Unassigned lanes contain anything for
      // him; everyone else: only what the security rules let them read). See
      // [_studentsStream].
      slot: 'guideStudents',
      stream: () => _within(_studentsStream()),
      builder: (context, userSnap) {
        if (!userSnap.hasData) return _boardWait(userSnap);

        final boys = <_Boy>[];
        for (final doc in userSnap.data!.docs) {
          final boy = _Boy.fromUser(doc.id, doc.data());
          if (boy != null) boys.add(boy);
        }
        boys.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        // Nobody to show (e.g. a new Female Enabler while there are no female students).
        if (boys.isEmpty) return _boardEmpty();

        // Keeps "a column exists because an admin exists" true by construction (the board
        // renders a column for every visible admin even before its document exists - see
        // [_visibleColumns]). Never deletes. HOD only: it writes to the shared board.
        if (reconcile && !_reconciling) {
          _reconciling = true;
          BoardData.instance
              .reconcileColumns(
                boardId: boardId,
                roster: [
                  for (final a in _boardAdmins(AdminProfileProvider.require())) a.id
                ],
                existing: columns,
              )
              .catchError((_) {})
              .whenComplete(() => _reconciling = false);
        }

        // Role-based columns in gender lanes - see [_visibleColumns].
        final visibleColumns = _visibleColumns(columns);

        return _boardReveal(Column(
          children: [
            // FOLK / Hostel / Localite legend under the top bar.
            const GuideGroupLegend(),
            // Drag-to-delete target - see [_trashTarget]'s own doc comment. Only rendered
            // while a card is actually being dragged.
            _trashTarget(allBoys: boys),
            Expanded(
              child: _canvas(
                guide: guide,
                boardId: boardId,
                columns: visibleColumns,
                allBoys: boys,
                columnBoys: (lc) => boys.where(lc.holds).toList(),
                headerExtra: (lc) {
                  final split = residenceSplit(boys.where(lc.holds).map((b) => b.role))
                      .labelFor(female: lc.lane == 'female');
                  final admin = lc.admin;
                  return admin == null ? split : "${admin.role.label} · $split";
                },
              ),
            ),
          ],
        ));
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
  ///
  /// ⚠️ **Role-based now (Master 2, Part A.2):** eligible = the viewer can
  /// MANAGE the student under the hierarchy (`StudentScope.canManage` — HOD
  /// anyone; Guide his team + unassigned males; Male Enabler own + unassigned
  /// males; Female Enabler own + unassigned females). A student the viewer
  /// cannot manage is never eligible.
  bool _customBoardEligible(_Boy boy) =>
      StudentScope.current().canManage(boy.ref);

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
    _markSettle(boy.uid);
    try {
      await BoardData.instance.movePlacement(
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
    String guide,
    String boardId,
  ) {
    return _live<List<BoardDoc>>(
      slot: 'customBoards',
      stream: () => BoardData.instance.boards(),
      builder: (context, boardsSnap) {
        if (!boardsSnap.hasData) return _boardWait(boardsSnap);
        BoardDoc? board;
        for (final b in boardsSnap.data!) {
          if (b.id == boardId) {
            board = b;
            break;
          }
        }
        if (board == null) return _boardWait(boardsSnap);
        final canEdit = canEditBoard(board: board, guide: guide, isHod: _isHod);

        return _live<List<BoardColumn>>(
          slot: 'customColumns',
          key: boardId,
          stream: () => BoardData.instance.columns(boardId),
          builder: (context, colSnap) {
            if (!colSnap.hasData) return _boardWait(colSnap);
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
            return _live<QuerySnapshot<Map<String, dynamic>>>(
              slot: 'customPlacements',
              key: boardId,
              stream: () => BoardData.instance.placements(boardId),
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
                  return _boardReveal(_customCanvas(
                    boardId: boardId,
                    guide: guide,
                    canEdit: canEdit,
                    columns: columns,
                    allBoys: const [],
                    columnBoys: (_) => const [],
                    columnCardCount: (column) =>
                        cardsInColumn(placeSnap.data, column.id),
                  ));
                }

                return _live<QuerySnapshot<Map<String, dynamic>>>(
                  // Scoped stream — a placed student the viewer may not see
                  // (e.g. one the HOD placed on a board shared with a guide)
                  // is simply not rendered; see [_studentsStream].
                  slot: 'customStudents',
                  stream: () => _studentsStream(),
                  builder: (context, userSnap) {
                    if (!userSnap.hasData) return _boardWait(userSnap);

                    final boys = <_Boy>[];
                    for (final doc in userSnap.data!.docs) {
                      // Only students actually placed on THIS board — see
                      // this method's own note above.
                      if (!placementColumnByUid.containsKey(doc.id)) continue;
                      final boy = _Boy.fromUser(doc.id, doc.data());
                      if (boy != null) boys.add(boy);
                    }
                    boys.sort((a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                    return _boardReveal(_customCanvas(
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
                    ));
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
    required String boardId,
    required String guide,
    required bool canEdit,
    required List<BoardColumn> columns,
    required List<_Boy> allBoys,
    required List<_Boy> Function(BoardColumn) columnBoys,
    required int Function(BoardColumn) columnCardCount,
  }) {
    if (columns.isEmpty) {
      return GuideEmptyOverGhost(
        ghost: GuideBoardGhost(columnWidth: _colW),
        title: "This board is empty",
        message: "Add a list to start organising students.",
        action: canEdit
            ? GuideEmptyAction("Add a list", () => _addCustomColumn(boardId, columns),
                icon: Icons.add_rounded)
            : null,
      );
    }

    // Where each column's left edge rests when snapped.
    final snap = <double>[];
    var left = 0.0;
    for (var i = 0; i < columns.length; i++) {
      snap.add(left);
      left += _colW + GuideBoardTokens.columnGap;
    }
    if (canEdit) snap.add(left);

    return ListView(
      controller: _hController,
      scrollDirection: Axis.horizontal,
      physics: _scrollLocked ? const NeverScrollableScrollPhysics() : GuideSnapPhysics(snapOffsets: snap),
      padding: const EdgeInsets.fromLTRB(
          GuideSpace.pagePadding, 4, GuideSpace.pagePadding - GuideBoardTokens.columnGap, 20),
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
        if (canEdit) _newColumnTile(label: "Add a list", onTap: () => _addCustomColumn(boardId, columns)),
      ],
    );
  }

  /// The dashed tile at the end of the row ("New board" on the mandatory board,
  /// "Add a list" on a custom one).
  Widget _newColumnTile({required String label, required VoidCallback onTap}) {
    final g = context.g;
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: GuideBoardTokens.columnGap),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GuideDashedBox(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 160),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: g.mutedText),
                    const SizedBox(height: 6),
                    Text(label, textAlign: TextAlign.center, style: context.gText.small),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
      // Read-only viewers, and drops of a student already in this column, are
      // both rejected here — `canEdit` is re-checked again inside
      // `_handlePlacementDrop` as the real authority.
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
        final t = context.gText;

        return GuideBoardColumnShell(
          width: _colW,
          tone: GuideColumnTone.plain,
          hovering: hovering,
          header: _customColumnHeader(
            boardId: boardId,
            guide: guide,
            canEdit: canEdit,
            column: column,
            columns: columns,
            colour: colour,
            count: boys.length,
            cardCount: cardCount,
          ),
          body: boys.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(hovering ? "Drop here" : "Empty", style: t.caption),
                  ),
                )
              : ListView.builder(
                  key: PageStorageKey<String>('custom-col-$boardId-${column.id}'),
                  physics: _scrollLocked ? const NeverScrollableScrollPhysics() : null,
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  itemCount: boys.length + 1,
                  // Part 3.5 — remove one student from this board: a button on
                  // the card's own top row (custom boards only; the mandatory
                  // board never shows it).
                  itemBuilder: (context, i) => i == boys.length
                      ? GuideDropGap(open: hovering)
                      : _studentCard(
                          boy: boys[i],
                          colour: colour,
                          onRemove: canEdit
                              ? () => _confirmRemoveFromBoard(boardId: boardId, boy: boys[i])
                              : null,
                        ),
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
    final g = context.g;
    return GuideBoardColumnHeader(
      title: column.title,
      accent: colour,
      count: count,
      scroll: _hController,
      columnWidth: _colW,
      actions: [
        if (canEdit)
          GuideCardIconButton(
            icon: Icons.person_add_alt_1_outlined,
            tooltip: "Add students",
            onTap: () => _openAddStudentsPicker(
              boardId: boardId,
              column: column,
              guide: guide,
              currentCardCount: cardCount,
            ),
          ),
        if (canEdit && column.isEditable)
          PopupMenuButton<String>(
            tooltip: "List options",
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
            child: SizedBox(
              width: GuideShape.touchTarget,
              height: GuideShape.touchTarget,
              child: Icon(Icons.more_vert, size: 18, color: g.mutedText),
            ),
          )
        else
          const SizedBox(width: 8),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Canvas — REAL side-by-side columns, restored. A horizontally-scrolling
  // row of columns, each with its own vertically-scrolling card list.
  // ---------------------------------------------------------------------------

  Widget _canvas({
    required String guide,
    required String boardId,
    required List<_LaneColumn> columns,
    required List<_Boy> allBoys,
    required List<_Boy> Function(_LaneColumn) columnBoys,
    required String? Function(_LaneColumn) headerExtra,
  }) {
    if (columns.isEmpty) {
      final g = context.g;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.view_column_outlined, size: 46, color: g.mutedText),
              const SizedBox(height: 14),
              Text("Setting up guide columns…", style: context.gText.cardTitle),
            ],
          ),
        ),
      );
    }

    // A small vertical label opens each gender lane when the viewer sees both
    // (HOD only) — a Guide / Enabler sees a single lane, so no label.
    final bothLanes =
        columns.any((c) => c.lane == 'male') && columns.any((c) => c.lane == 'female');
    final items = <Object>[];
    String? currentLane;
    for (final c in columns) {
      if (bothLanes && c.lane != currentLane) items.add(c.lane);
      currentLane = c.lane;
      items.add(c);
    }

    // Where each column's left edge rests when snapped (a lane label between
    // columns is accounted for), then the dashed "New board" tile.
    final snap = <double>[];
    var left = 0.0;
    for (final item in items) {
      if (item is String) {
        left += _laneLabelWidth + GuideBoardTokens.columnGap;
      } else {
        snap.add(left);
        left += _colW + GuideBoardTokens.columnGap;
      }
    }
    snap.add(left);

    return ListView.builder(
      controller: _hController,
      scrollDirection: Axis.horizontal,
      // Drag fix — while a card is dragged the row must not scroll under the
      // finger (see `_scrollLocked`); otherwise it snaps column by column.
      physics: _scrollLocked ? const NeverScrollableScrollPhysics() : GuideSnapPhysics(snapOffsets: snap),
      padding: const EdgeInsets.fromLTRB(
          GuideSpace.pagePadding, 4, GuideSpace.pagePadding - GuideBoardTokens.columnGap, 20),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) {
          return _newColumnTile(label: "New board", onTap: () => _createBoard(guide));
        }
        final item = items[index];
        if (item is String) return _laneLabel(item);
        final column = item as _LaneColumn;
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

  static const double _laneLabelWidth = 30;

  /// The narrow vertical "MALES" / "FEMALES" strip that starts a gender lane.
  Widget _laneLabel(String lane) {
    final g = context.g;
    final female = lane == 'female';
    return Container(
      width: _laneLabelWidth,
      margin: const EdgeInsets.only(right: GuideBoardTokens.columnGap),
      decoration: BoxDecoration(
        color: g.chipBackground,
        borderRadius: BorderRadius.circular(GuideShape.columnRadius),
        border: Border.all(color: g.border),
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            female ? "FEMALES" : "MALES",
            maxLines: 1,
            style: context.gText.label.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _columnTile({
    required String boardId,
    required _LaneColumn column,
    required List<_Boy> allBoys,
    required List<_Boy> boys,
    required String? headerExtra,
  }) {
    final colour = Color(column.column.colorValue);
    final mine = AdminProfileProvider.current?.id;
    // Green tint on the viewer's own column, cool on Unassigned, plain otherwise.
    final tone = column.isUnassigned
        ? GuideColumnTone.unassigned
        : (column.admin != null && column.admin!.id == mine
            ? GuideColumnTone.folk
            : GuideColumnTone.plain);

    return DragTarget<String>(
      // Every hover is accepted (except a card already in this column) so a
      // blocked move — cross-gender or outside the viewer's scope — gets a
      // snackbar explaining why instead of the card silently bouncing back.
      // The real, authoritative gate is `_handleDrop`'s own check, and the
      // server (`assignStudent`) enforces the same rules again.
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

        return GuideBoardColumnShell(
          width: _colW,
          tone: tone,
          hovering: hovering,
          header: GuideBoardColumnHeader(
            title: column.title,
            accent: colour,
            count: boys.length,
            subtitle: headerExtra,
            scroll: _hController,
            columnWidth: _colW,
          ),
          body: boys.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(hovering ? "Drop here" : "Empty", style: context.gText.caption),
                  ),
                )
              : ListView.builder(
                  key: PageStorageKey<String>('col-$boardId-${column.column.id}'),
                  // Same drag fix as the outer horizontal list — this column's
                  // own vertical scroll is ALSO an ancestor of every card's
                  // `LongPressDraggable` and competes in the exact same way.
                  physics: _scrollLocked ? const NeverScrollableScrollPhysics() : null,
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  itemCount: boys.length + 1,
                  itemBuilder: (context, i) => i == boys.length
                      ? GuideDropGap(open: hovering)
                      : _studentCard(boy: boys[i], colour: colour),
                ),
        );
      },
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
  Widget _studentCard({
    required _Boy boy,
    required Color colour,
    VoidCallback? onRemove,
  }) {
    final cardBody = _cardBody(boy: boy, colour: colour, onRemove: onRemove);

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
        // Picked up: a soft shadow and a 1.02 scale.
        feedback: Material(
          color: Colors.transparent,
          child: Transform.scale(
            scale: 1.02,
            child: SizedBox(
              width: _colW - 20,
              child: _cardBody(boy: boy, colour: colour, forceCollapsed: true, lifted: true),
            ),
          ),
        ),
        // The gap the card leaves behind while it travels.
        childWhenDragging: Opacity(opacity: .35, child: cardBody),
        child: GuideSettle(
          active: _settling(boy.uid),
          onSettled: () => _settleUid = null,
          child: cardBody,
        ),
      ),
    );
  }

  /// The card that was just dropped: it settles (1.02 -> 1.0) where it lands.
  String? _settleUid;

  DateTime _settleAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Marks [uid] as just dropped; it only counts for 3 s (a refused move never lands).
  void _markSettle(String uid) {
    _settleUid = uid;
    _settleAt = DateTime.now();
  }

  bool _settling(String uid) =>
      _settleUid == uid && DateTime.now().difference(_settleAt) < const Duration(seconds: 3);

  Widget _cardBody({
    required _Boy boy,
    required Color colour,
    bool forceCollapsed = false,
    bool lifted = false,
    VoidCallback? onRemove,
  }) {
    final expanded = !forceCollapsed && _expandedUids.contains(boy.uid);
    final g = context.g;
    final t = context.gText;
    final group = guideGroupOf(boy.role);
    final duration = GuideMotion.of(context, GuideMotion.expand);

    return GuideBoardCardFrame(
      lifted: lifted,
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
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: who, and the expand chevron (and, on a custom board, the
              // remove-from-board button).
              Row(
                children: [
                  GuideGroupAvatar(name: boy.name, group: group),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        boy.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.cardTitleSmall,
                      ),
                    ),
                  ),
                  if (!forceCollapsed)
                    ValueListenableBuilder<Map<String, Set<String>>>(
                      valueListenable: _commitmentUnseen,
                      builder: (context, unseen, _) => (unseen[boy.uid]?.isNotEmpty ?? false)
                          ? const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: UnseenDot(size: 9),
                            )
                          : const SizedBox.shrink(),
                    ),
                  if (!forceCollapsed)
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: duration,
                      curve: GuideMotion.standard,
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: g.mutedText),
                    ),
                  if (onRemove != null && !forceCollapsed)
                    GuideCardIconButton(
                      icon: Icons.close_rounded,
                      tooltip: "Remove from this board",
                      onTap: onRemove,
                    )
                  else
                    const SizedBox(width: 10),
                ],
              ),
              // Row 2: the group pill, and the three quick icons — calendar,
              // comments, profile — each a 48 dp target.
              Row(
                children: [
                  // Flexible, not a bare pill: the three icon buttons beside it are a
                  // fixed 48 dp each, so at a large text scale — or while a predictive
                  // back gesture renders this card at ~90% of its width — the pill's
                  // natural width no longer fits and this Row overflowed (4.9 px at
                  // text 1.6). The pill's own Text already ellipsises, so letting it
                  // shrink is all that is needed; the Spacer still pushes the icons to
                  // the right whenever there is room for them.
                  if (group != null) Flexible(child: GuideGroupPill(group: group)),
                  const Spacer(),
                  GuideCardIconButton(
                    icon: Icons.calendar_month_outlined,
                    tooltip: "Calendar",
                    onTap: forceCollapsed
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CalendarPage(
                                  username: boy.reportKey,
                                  role: boy.role,
                                  studentUid: boy.uid,
                                ),
                              ),
                            ),
                  ),
                  // `showStudentCommentsDialog` unchanged, including its own
                  // internal `_canAccess` gate (HOD always; a guide only on
                  // their own current student). Per-student unseen dot: a
                  // message posted (by the OTHER party) since THIS viewer last
                  // opened THIS student's thread.
                  BoardData.instance.commentsBadge(
                    studentUid: boy.uid,
                    child: GuideCardIconButton(
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
                                SeenMarkers.markSeenSub(_guide, 'studentComments', boy.uid);
                              }),
                    ),
                  ),
                  // The orange dot trail for "New suggestions ready": it ends in the profile, where the label
                  // under the picture says so; it clears only when the guide opens those suggestions.
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: _suggestionsUnseen,
                    builder: (context, unseen, child) => UnseenBadge(
                      show: unseen.contains(boy.uid),
                      offset: const Offset(10, 10),
                      child: child!,
                    ),
                    child: GuideCardIconButton(
                      icon: Icons.person_outline_rounded,
                      tooltip: "Profile",
                      onTap: forceCollapsed
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StudentProfilePage(studentUid: boy.uid),
                                ),
                              ),
                    ),
                  ),
                ],
              ),
              // Manually-added student badge: always visible, never behind a tap.
              if (boy.isManualEntry)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 8),
                  child: _manualEntryBadge(),
                ),
              GuideAnimatedSize(
                duration: duration,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(height: 14, color: g.border),
                            GuideFadeIn(child: _expandedDetail(boy: boy)),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
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
    _booksConfigFuture ??= BoardData.instance.booksConfig();
    // A book commitment is "seen" per BOOK now (its level open and its row on screen, or the
    // row tapped), not by expanding the card: see [_levelDropdown] / [_bookStatusRow].

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chanting commitment — Part 5. Same field, same "absent or 0 both
        // mean unset" rule as `BooksProgress.dart`'s own banner
        // (`loadChantingCommitment`), just laid out to fit inside a card
        // instead of a full-width screen banner.
        FutureBuilder<int?>(
          future: BoardData.instance.chantingCommitment(boy.uid),
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
                style: context.gText.caption,
              );
            }
            if (!configSnap.hasData) {
              return _bookGhost();
            }
            final config = configSnap.data!;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // The same `uid ==` filter `BooksProgress.dart` uses (legacy
              // name-keyed `booksRead` documents have no `uid` and are
              // excluded by construction), plus the one extra equality filter
              // the security rules need to PROVE this viewer may read this
              // student's documents (`constrainForStudent`: HOD none; else
              // `scopeTeam` / `scopeGuide` [+ `scopeGender`] from the
              // student's current assignment). Equality only — no index.
              stream: BoardData.instance.booksRead(boy.ref),
              builder: (context, progressSnap) {
                if (!progressSnap.hasData) {
                  return _bookGhost();
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
    final g = context.g;
    final t = context.gText;
    if (commitment == null) {
      return Row(
        children: [
          Icon(Icons.local_fire_department_outlined, size: 16, color: g.mutedText),
          const SizedBox(width: 6),
          Expanded(child: Text("No chanting commitment set", style: t.caption)),
        ],
      );
    }
    // A sand chip: "Committed to N rounds/day".
    return GuidePastelBox(
      pastel: GuidePastel.sand,
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department_outlined, size: 16, color: GuideColors.pastelAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Committed to $commitment rounds/day",
              style: t.onPastelBody.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
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
    final showAll = _allBooksShown.contains(levelKey);
    final listed = showAll ? displayOrder : displayOrder.take(_booksShown).toList();
    final hidden = displayOrder.length - listed.length;
    if (open && books.isNotEmpty) {
      // The rows on screen now: any unseen one is seen shortly.
      _scheduleSeen(boy, level, [for (final b in listed) _bookDocId(boy, b)]);
    }

    final g = context.g;
    final t = context.gText;
    final duration = GuideMotion.of(context, GuideMotion.expand);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A plain GestureDetector, not InkWell — this file's convention for
        // anything nested inside the draggable card.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            if (open) {
              _expandedLevels.remove(levelKey);
            } else {
              _expandedLevels.add(levelKey);
            }
          }),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(kBookLevelLabels[level] ?? level, style: t.cardTitleSmall),
                      ),
                      // An unseen book in this level (also while the level is closed).
                      ValueListenableBuilder<Map<String, Set<String>>>(
                        valueListenable: _commitmentUnseen,
                        builder: (context, unseen, _) {
                          final ids = unseen[boy.uid];
                          final has = ids != null && books.any((b) => ids.contains(_bookDocId(boy, b)));
                          return has
                              ? const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: UnseenDot(size: 9),
                                )
                              : const SizedBox.shrink();
                        },
                      ),
                      AnimatedRotation(
                        turns: open ? .5 : 0,
                        duration: duration,
                        curve: GuideMotion.standard,
                        child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: g.mutedText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    books.isEmpty
                        ? "no books configured"
                        : "$finished of ${books.length} finished"
                            "${reading > 0 ? ' · $reading reading' : ''}",
                    style: t.caption,
                  ),
                  const SizedBox(height: 8),
                  GuideProgressBar(
                    value: books.isEmpty ? 0 : finished / books.length,
                  ),
                ],
              ),
            ),
          ),
        ),
        GuideAnimatedSize(
          duration: duration,
          child: open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: books.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text("No books configured for this level.", style: t.caption),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final b in listed)
                              _bookStatusRow(
                                boy: boy,
                                book: b,
                                status: statusForBookEntry(entries['${b.level}_${b.key}']),
                                entry: entries['${b.level}_${b.key}'],
                              ),
                            if (hidden > 0)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _allBooksShown.add(levelKey)),
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minHeight: GuideShape.touchTarget),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      "Show $hidden more",
                                      style: t.bodyStrong.copyWith(color: g.brass),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                )
              : const SizedBox(width: double.infinity),
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
  /// Completion lives on the CHECKPOINT CIRCLE, not in the assign dialog.
  /// Tapping the circle of an unfinished book asks "Mark this book
  /// finished?" ([_confirmMarkBookFinished], the same single write as
  /// before); tapping a finished one asks "Mark as not completed?"
  /// ([_confirmMarkBookNotFinished]). The circle is tappable in every level's
  /// list, including for a finished book, whose ROW stays untappable — the
  /// circle's own detector is a child of the row's, so it takes the tap and
  /// the assign dialog never opens behind the confirmation. Tapping the
  /// title still opens the assign dialog for an unfinished book.
  ///
  /// The "Mark as completed" button that used to be inside that dialog is
  /// gone; both directions now go through the circle.
  Widget _bookStatusRow({
    required _Boy boy,
    required BookConfigEntry book,
    required BookStatus status,
    required Map<String, dynamic>? entry,
  }) {
    final g = context.g;
    final t = context.gText;
    final isCurrent = status == BookStatus.readingNow;
    final isFinished = status == BookStatus.finished;
    final colour = isFinished ? g.success : (isCurrent ? g.brass : g.mutedText);
    // Open circle: not started; ring with a dot: reading now; tick: done.
    final icon = isFinished
        ? Icons.check_circle_rounded
        : (isCurrent ? Icons.timelapse_rounded : Icons.radio_button_unchecked_rounded);
    final commitmentDate = (entry?['commitmentDate'] as String?)?.trim();
    final commitmentSetBy = (entry?['commitmentSetBy'] as String?)?.trim();

    // Tapping an unfinished book opens the guide-assign dialog (the ONLY way to
    // mark a book finished from this card); a finished one is not tappable.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isFinished
          ? null
          : () {
              _markBookSeen(boy, _bookDocId(boy, book));
              _openAssignBookDialog(boy: boy, book: book, entry: entry);
            },
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: isFinished ? 36 : GuideShape.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              // The checkpoint circle is its own tap target: it marks the
              // book completed, and un-marks it again. It sits INSIDE the
              // row's own GestureDetector, so the child wins the tap and the
              // assign dialog is not opened behind the confirmation. It is
              // tappable for a finished book too, which the row itself is not.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _markBookSeen(boy, _bookDocId(boy, book));
                  if (isFinished) {
                    _confirmMarkBookNotFinished(
                        boy: boy, book: book, entry: entry);
                  } else {
                    _confirmMarkBookFinished(
                        boy: boy, book: book, entry: entry);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 8),
                  child: Icon(icon, size: 18, color: colour),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      book.title.isEmpty ? "(untitled)" : book.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(
                        fontSize: 13,
                        color: status == BookStatus.notStarted ? g.mutedText : g.text,
                      ),
                    ),
                    // The current book's commitment date and who set it.
                    if (isCurrent && commitmentDate != null)
                      Text(
                        commitmentSetBy == 'guide'
                            ? "Due $commitmentDate (set by guide)"
                            : "Due $commitmentDate (set by student)",
                        style: t.caption,
                      ),
                  ],
                ),
              ),
              ValueListenableBuilder<Map<String, Set<String>>>(
                valueListenable: _commitmentUnseen,
                builder: (context, unseen, _) =>
                    (unseen[boy.uid]?.contains(_bookDocId(boy, book)) ?? false)
                        ? const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: UnseenDot(size: 9),
                          )
                        : const SizedBox.shrink(),
              ),
              if (!isFinished) Icon(Icons.chevron_right_rounded, size: 18, color: g.mutedText),
            ],
          ),
        ),
      ),
    );
  }

  /// The other half of the checkpoint circle: a book marked completed by
  /// mistake, put back.
  ///
  /// ONE write, the mirror of [_confirmMarkBookFinished]: `endDate` and
  /// `endedBy` are DELETED (not blanked — `statusForBookEntry` treats an empty
  /// string as unfinished, but a deleted field is what a book that was never
  /// finished actually looks like), and `isCurrentBook` is left FALSE.
  ///
  /// Leaving it false is the safe choice, and it is deliberate: the undefined
  /// combination `isCurrentBook == false` with no `endDate` is already defined
  /// by `statusForBookEntry` as `notStarted` — "the record asserts no progress,
  /// so the caller claims none". Setting it true instead would silently credit
  /// the student with reading a book their own report never claimed, and would
  /// risk a second current book. `startDate` is untouched, so a book that had a
  /// real start date keeps it.
  ///
  /// The "finished is never current" invariant holds here by construction: this
  /// write removes the end date and sets nothing current.
  Future<void> _confirmMarkBookNotFinished({
    required _Boy boy,
    required BookConfigEntry book,
    required Map<String, dynamic>? entry,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: const Text("Mark as not completed?"),
        content: Text(
          "${book.title.isEmpty ? '(untitled)' : book.title} will go back to "
          "not completed for ${boy.name}. It does not become their current "
          "book.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Mark not completed"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await markBookNotFinished(
        studentUid: boy.uid,
        level: book.level,
        bookKey: book.key,
        title: book.title,
      );

      if (!mounted) return;
      showSnackbar(context, "Book marked not completed", Colors.green,
          Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
          context, "Could not update the book", Colors.red, Icons.error);
    }
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
      builder: (dialogContext) => GuideDialog(
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
            child: const Text("Mark finished"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await markBookFinished(
        studentUid: boy.uid,
        level: book.level,
        bookKey: book.key,
        title: book.title,
        hasStarted: hasStarted,
      );

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
            return GuideDialog(
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
                    style: dialogContext.gText.small,
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
                        border: Border.all(color: dialogContext.g.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 10),
                          Flexible(child: Text(
                            picked == null
                                ? "Tap to choose a date"
                                : picked!.toIso8601String().split('T')[0],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ))],
                      ),
                    ),
                  ),
                  // The "Mark as completed" button that used to sit here is
                  // gone: the checkpoint circle on the row itself now does
                  // that job (and undoes it), so this dialog is once again
                  // only about assigning a commitment date.
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

    if (confirmed is! DateTime) return;

    try {
      // One shared write (actions/BookActions.dart): the AI agent assigns a book
      // through exactly this. A transaction, so a book that is already completed
      // is never made the student's CURRENT book.
      final assigned = await assignBook(
        guideId: _guide,
        studentUid: boy.uid,
        level: book.level,
        bookKey: book.key,
        title: book.title,
        commitment: confirmed,
      );

      if (!assigned) {
        if (!mounted) return;
        showSnackbar(
            context,
            "This book is already completed, so it cannot be assigned as a current book",
            Colors.orange,
            Icons.info);
        return;
      }

      if (!mounted) return;
      showSnackbar(context, "Book assigned", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not assign the book", Colors.red, Icons.error);
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
    final g = context.g;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: g.warning.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: g.warning.withValues(alpha: .45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_rounded, size: 14, color: g.warning),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                "Guide-entered · not registered",
                style: context.gText.pill.copyWith(color: g.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
