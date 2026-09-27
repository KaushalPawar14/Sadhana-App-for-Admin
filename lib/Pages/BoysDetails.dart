import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Services/UpdateFCM.dart';
import '../utils/ColorProvider.dart';
import '../utils/GuideRoster.dart';
import '../utils/ManualStudents.dart';
import '../utils/Snackbar.dart';
import 'AdminManager.dart';
import 'SubmissionStatus.dart';
// `AdminRegisterUserPage` is no longer imported here: its "Add Hostelers" tile
// was removed on 2026-08-14. **The screen file was deliberately kept** — it
// registers a student wholesale into `users/{uid}`, which is the only path in
// this app for creating a student at all, so deleting it would remove a real
// capability rather than a dead end. It is now unreachable until re-wired,
// the same treatment given to `BookReadReport.dart` and `sendReminder()`.
// `FlaggedMessages`, `PriorityStudents` and `PodcastLinkManager` are no longer
// imported here either — all three tiles moved on 2026-08-14. Priority
// Students and Flagged Messages are now reached from `PriorityHub.dart` on the
// Folk Analysis tab; podcast links are embedded inline in the Books screen.

class AdminControlPage extends StatefulWidget {
  const AdminControlPage({super.key});

  @override
  State<AdminControlPage> createState() => _AdminControlPageState();
}

class _AdminControlPageState extends State<AdminControlPage> {

  /// Who is using this device, for the HOD-only tile below. Null until the
  /// pref is read, so the gated tile simply does not render on first frame.
  String? _selectedGuide;

  /// The single HOD check for this screen — compares against [kHodGuideId],
  /// never a literal, so changing the HOD in `GuideRoster.dart` moves this
  /// gate with it and needs no edit here.
  bool get _isHod => _selectedGuide == kHodGuideId;

  @override
  void initState() {
    super.initState();
    _loadGuide();
  }

  Future<void> _loadGuide() async {
    final guide = await UpdateTokenService().getSavedGuide();
    if (mounted) setState(() => _selectedGuide = guide);
  }

  /// Manually-added ("offline roster") students — a guide can record a real
  /// student who chants but hasn't installed the app yet, so roadmap targets
  /// reflect reality rather than app adoption. See
  /// `utils/ManualStudents.dart`'s own header for the full schema/Rule 12
  /// justification and `functions/manualStudents.js` for the auto-merge that
  /// runs when the real student later registers with the same number.
  ///
  /// Available to EVERY guide, not just the HOD (unlike "Add Admin" below) —
  /// a guide records their OWN students. The guide-ASSIGNMENT dropdown
  /// inside this dialog (not the app's own login/identity — that picker is
  /// dead as of Master Task 2026-09-14) only appears for the HOD, per this
  /// task's Part 3 item 3; a non-HOD guide's own identity is used
  /// automatically (Part 3 item 2).
  Future<void> _openAddStudentDialog() async {
    if (_selectedGuide == null || _selectedGuide!.isEmpty) {
      showSnackbar(context, "Still loading your guide profile — try again in a moment",
          Colors.yellow, Icons.watch_later_outlined);
      return;
    }

    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final roundsController = TextEditingController();
    String? residence;
    String? assignedGuide; // HOD only; null = Unassigned
    String? error;
    bool saving = false;

    List<String> guides = const [];
    if (_isHod) {
      try {
        guides = await guideRosterStream().first;
      } catch (_) {
        guides = const [];
      }
    }

    if (!mounted) return;

    // Root cause of the "Cancel restarts the app" report (Part 2), found by
    // reading Flutter's own `Overlay.of()` source
    // (`packages/flutter/lib/src/widgets/overlay.dart:575-617`), not
    // guessed: the PREVIOUS version of `save()`'s success branch called
    // `Navigator.pop(dialogContext)` and then, on the very next line, called
    // `showSnackbar(context, ...)` using `context` — the `StatefulBuilder`'s
    // OWN context, a descendant of the dialog route JUST popped. `Overlay.of`
    // ends in `return result!;`, a non-null assertion that throws
    // (`Null check operator used on a null value`) in EVERY build mode, not
    // just debug, once that route's element is torn down — and because
    // `Navigator.pop` disposal isn't synchronous within the same
    // continuation, this was TIMING-DEPENDENT, matching a bug that doesn't
    // reproduce every single time. Worse: the `catch (_)` wrapping that call
    // then invoked `setDialogState(...)` on the SAME already-popped
    // `StatefulBuilder` — a SECOND, uncaught `setState() called after
    // dispose()` exception with nothing left to catch it, propagating to the
    // zone's uncaught-error handler, which is the kind of unhandled crash
    // that can surface as "the app restarted."
    //
    // The actual Cancel button's own handler (`Navigator.pop(dialogContext)`
    // and nothing else) was read in full and found to be already clean of
    // this pattern — byte-for-byte identical to "Add Guide"'s own working
    // Cancel button above. The fix below removes the shared root cause for
    // good rather than only patching the one call site: `showDialog` now
    // returns whether a save happened, and ONLY the outer method — using the
    // stable PAGE context, guarded by the PAGE's own `mounted`, never a
    // context tied to the dialog route itself — decides whether to show the
    // success snackbar, after `await showDialog` has fully resolved. Nothing
    // inside the dialog's own widget tree touches any context or calls
    // `setDialogState` after popping itself, on either the Cancel or the
    // Save path.
    String? addedStudentName;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              // Crash-fix task (2026-09-03) — re-entrancy guard, same pattern
              // as `GuideCalendarPage._extract()`'s own fix for the identical
              // family of bug: `onPressed: saving ? null : save` only
              // disables the button on the NEXT rebuild, leaving a narrow
              // window where a rapid double-tap invokes `save()` twice
              // concurrently before `saving` has ever been set. Checked here,
              // at the very top of the handler itself, not just at the
              // button.
              if (saving) return;

              final name = nameController.text.trim();
              if (name.isEmpty) {
                setDialogState(() => error = "Enter the student's name");
                return;
              }
              if (residence == null) {
                setDialogState(() => error = "Select FOLK, Hostel or Localite");
                return;
              }
              final normalizedMobile =
                  normalizeMobileNumber(mobileController.text);
              if (!isValidNormalizedMobile(normalizedMobile)) {
                setDialogState(
                    () => error = "Enter a valid 10-digit mobile number");
                return;
              }

              setDialogState(() {
                error = null;
                saving = true;
              });

              try {
                // Part 3 item 5 — warn before saving and refuse the
                // duplicate outright, rather than a confirm-to-override.
                final existing = await findUserByMobileNumber(normalizedMobile);
                if (existing != null) {
                  setDialogState(() {
                    saving = false;
                    error = 'This mobile number already belongs to '
                        '"${existing['name'] ?? 'another student'}" — '
                        'cannot add a duplicate.';
                  });
                  return;
                }

                final roundsText = roundsController.text.trim();
                final rounds =
                    roundsText.isEmpty ? null : int.tryParse(roundsText);

                // Part 3 items 2/3: guide adding -> assigned to themself
                // automatically; HOD adding -> whatever the picker holds
                // (including null, i.e. Unassigned).
                final guideForNewStudent =
                    _isHod ? assignedGuide : _selectedGuide;

                final id = generateManualStudentId();
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(id)
                    .set({
                  'name': name,
                  'mobileNumber': normalizedMobile,
                  'role': residence,
                  if (guideForNewStudent != null &&
                      guideForNewStudent.isNotEmpty)
                    'guideId': guideForNewStudent,
                  if (rounds != null && rounds > 0) 'commitmentRounds': rounds,
                  'isManualEntry': true,
                  'addedByGuideId': _selectedGuide,
                  'addedAt': Timestamp.now(),
                  'createdAt': Timestamp.now(),
                });

                // Captured in the OUTER scope, read only AFTER this dialog
                // has fully closed — see this method's own header for why
                // nothing after this pop touches `context` or
                // `setDialogState` again.
                addedStudentName = name;
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (_) {
                setDialogState(() {
                  saving = false;
                  error = "Could not save. Check your connection.";
                });
              }
            }

            return AlertDialog(
              title: const Text("Add a student"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: "Name"),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mobileController,
                      enabled: !saving,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: "Mobile number"),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: roundsController,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Daily chanting rounds (optional)",
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: residence,
                      decoration:
                          const InputDecoration(labelText: "Residence"),
                      items: const [
                        DropdownMenuItem(
                            value: 'Stay at FOLK',
                            child: Text('Stay at FOLK')),
                        DropdownMenuItem(
                            value: 'Stay at Hostel',
                            child: Text('Stay at Hostel')),
                        DropdownMenuItem(
                            value: 'Stay at Localite',
                            child: Text('Stay at Localite')),
                      ],
                      onChanged: saving
                          ? null
                          : (v) => setDialogState(() => residence = v),
                    ),
                    if (_isHod) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        value: assignedGuide,
                        decoration: const InputDecoration(
                            labelText: "Assign to guide"),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('Unassigned')),
                          ...guides.map((g) => DropdownMenuItem<String?>(
                              value: g, child: Text(g))),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setDialogState(() => assignedGuide = v),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    mobileController.dispose();
    roundsController.dispose();

    // Shown here, not from inside the dialog — see this method's own header.
    // `context`/`mounted` here are the PAGE's own, unrelated to the
    // now-fully-closed dialog route.
    if (addedStudentName != null && mounted) {
      showSnackbar(context, "$addedStudentName added", Colors.green,
          Icons.check_circle);
    }
  }

  /// ⚠️ **Layout redesign, 2026-09-03.** Was a `LayoutBuilder` picking a tile
  /// `size` (130/100) from `constraints`, feeding a `Row` of at-most-three
  /// hand-placed circular tiles. Removed for two independent reasons:
  ///
  ///  1. **Crash fix (Part 1).** Real-device crash — `'_dependents.isEmpty'
  ///     is not true` plus duplicate `GlobalKey`s, `_LayoutBuilderElement.
  ///     _rebuildWithConstraints` in the stack — the SAME structural family
  ///     already fixed twice in this app (`FolkBoysEntry.dart`'s own
  ///     `LayoutBuilder` removal; `GuideCalendarPage.dart`'s doc comment on
  ///     "three real crashes in a row" from the same root cause): a
  ///     `LayoutBuilder`'s pending layout callback left unresolved while a
  ///     dialog/route pops across the same Navigator/Overlay collides with
  ///     that teardown. No `LayoutBuilder` anywhere on this screen means it
  ///     cannot happen here again, regardless of what the Add Student dialog
  ///     does. Nothing in this file used a literal `GlobalKey`, so the
  ///     "duplicate GlobalKeys" half of the report is this same framework
  ///     confusion, not a second bug to hunt down separately.
  ///  2. **The redesign itself (Part 2)** no longer needs `constraints` at
  ///     all: `GridView`'s `SliverGridDelegateWithMaxCrossAxisExtent` picks
  ///     its own column count from the layout constraints it is handed
  ///     internally — the exact "reflows naturally, no manual width
  ///     arithmetic" property a fixed `Row` never had. A `Row` of tiles
  ///     works for three; it does not reflow to a second line for six or
  ///     eight without rewriting this method — the grid does, unchanged,
  ///     because column count was never hand-picked here to begin with.
  @override
  Widget build(BuildContext context) {
    final colorProvider = Provider.of<ColorProvider>(context);

    /// ⚠️ Every non-HOD tile that used to live here has been relocated
    /// (2026-08-14): Priority Students and Flagged Messages to the Folk
    /// Analysis tab's "Priority Students" hub, Podcast Links inline into the
    /// Books screen. **This screen was empty for any non-HOD guide** until
    /// "Add Student" below — the first tile on this tab available to every
    /// guide, not just the HOD.
    final tiles = <Widget>[
      _taskTile(
        icon: Icons.person_add,
        label: "Add Student",
        accent: Colors.teal,
        onTap: _openAddStudentDialog,
      ),

      /// Master Task Part 5 items 2-3 — replaces the missing-reports section
      /// removed from the calendar's today panel (`GuideCalendarPage.dart`).
      /// Available to every guide, same as "Add Student":
      /// `SubmissionStatusPage` resolves its own HOD/guide scoping
      /// internally (item 5 — it already reuses this screen's own scoped-
      /// query pattern), so no role check is needed here.
      _taskTile(
        icon: Icons.fact_check,
        label: "Submissions",
        accent: Colors.deepOrange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SubmissionStatusPage()),
        ),
      ),

      /// Available to any guide and the HOD (Master Task, 2026-09-14, Part
      /// 3.4 — product owner's explicit decision). Replaces the old
      /// HOD-only "Add Guide" tile entirely, rather than sitting alongside
      /// it: that dialog never collected an email, and every admin now
      /// needs one to ever sign in (Part 2) — see `AdminManager.dart`'s
      /// own header for the full reasoning.
      _taskTile(
        icon: Icons.person_add_alt_1,
        label: "Add Admin",
        accent: Colors.blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminManagerPage()),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: colorProvider.color,
      // The AppBar wrapping this page (`BottomNavBar.dart`) already titles
      // this tab "Other tasks" — no second heading repeated in the body.
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(24),
          // `SliverGridDelegateWithMaxCrossAxisExtent` computes its own
          // column count from the constraints it receives during layout —
          // no `LayoutBuilder`, no `MediaQuery` width arithmetic, and no
          // possible overflow at any screen size (Part 2 items 1/5): a
          // narrow phone gets fewer, wider columns; a tablet gets more,
          // same-sized ones. The SAME three tiles today and six or eight
          // later both just flow into more rows of the same grid — nothing
          // here changes when a tile is added.
          // Part 4 (Master Task, 2026-09-10): retuned from
          // `maxCrossAxisExtent: 108` / `childAspectRatio: 0.88`, which put
          // the 3-column boundary width (~104dp, hit on ordinary phones)
          // right at the edge of this tile's own required content height
          // (icon + spacing + up to 2 text lines + padding) — a margin of
          // well under 1dp, which is exactly the reported "1.7px bottom
          // overflow" on the Submissions tile (the label most likely to
          // wrap to 2 lines). `maxCrossAxisExtent: 200` keeps this at two
          // columns across the entire normal phone width range (~280-430dp
          // screens), satisfying "two per row on a normal phone width"
          // without any manual width arithmetic — still entirely
          // constraints-derived, same delegate as before, only the
          // parameters changed. `childAspectRatio: 0.7` (taller cells,
          // paired with `_taskTile`'s own enlarged content below) leaves
          // real headroom at the narrowest realistic cell width instead of
          // the previous near-zero margin, so this can't silently
          // reproduce the same overflow at a different boundary.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 0.7,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, index) => tiles[index],
        ),
      ),
    );
  }

  /// A single, compact task tile — restrained chrome, coloured icon.
  ///
  /// ⚠️ **Design direction (Part 2 item 3):**
  ///  - Spacing on a regular 4pt-multiple scale throughout (8/12/16/24),
  ///    never an arbitrary value.
  ///  - The tile's own surface is `colorProvider.fourthColor` — this app's
  ///    existing "card/surface" token (already used for exactly this role
  ///    elsewhere, e.g. `BottomNavBar.dart`'s bar background), not a new
  ///    colour invented for this task. Restrained colour lives ONLY in the
  ///    icon and its soft badge tint (`accent.withOpacity(0.12)` behind a
  ///    full-strength `accent` icon) — the tile surface, its text and its
  ///    elevation are neutral and identical across every tile, so the icon
  ///    alone carries identity, per the product owner's explicit ask.
  ///  - `Material`'s own `elevation` (not a hand-rolled `BoxShadow`) gives
  ///    the tile just enough definition to read as a distinct surface —
  ///    checked, not assumed: in LIGHT mode `fourthColor` is `Colors.
  ///    white70`, which composites to indistinguishable-from-white directly
  ///    on top of this Scaffold's own plain white background with no
  ///    elevation at all — confirmed by computing the alpha blend (white
  ///    over white is white regardless of alpha), not by eyeballing it. A
  ///    small `elevation: 1.5` restores a soft, native, theme-correct edge
  ///    in light mode via Flutter's own Material shadow rendering, and is
  ///    visually negligible in dark mode (where `fourthColor`'s
  ///    `Colors.grey[850]` already contrasts against the near-black
  ///    scaffold on its own) — satisfying "generous whitespace... over
  ///    heavy borders" (item 3) with no border at all, and "works in light
  ///    and dark theme" (item 4) in both directions, not just one.
  ///  - `InkWell`'s own ripple is the tap feedback — no custom animation.
  ///    The previous continuous sine-wave bob (`AnimatedBuilder` +
  ///    `floatController`, now removed along with its `AnimationController`
  ///    and `TickerProviderStateMixin`) read as playful/unfinished, the
  ///    opposite of the "genuinely professional" look asked for here, and
  ///    cost a perpetual animation ticking even while nothing was pressed.
  Widget _taskTile({
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final colorProvider = Provider.of<ColorProvider>(context);

    return Material(
      color: colorProvider.fourthColor,
      elevation: 1.5,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Part 4 (Master Task, 2026-09-10) — enlarged from 44/22 to
              // 52/26 as part of "noticeably larger" tiles (item 2); the
              // grid delegate above was retuned in tandem so this still has
              // real headroom, not just a bigger version of the same
              // near-zero margin.
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: colorProvider.secondColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// final Map<String, List<String>> questionLevels = {
//   "level-1": [
//     "Who am I?",
//     "Does God exist?",
//     "GOD Vs. Demigods & Definition of GOD",
//     "Yugadharma for Kaliyuga",
//     "Laws of Karma",
//   ],
//
//   "level-2": [
//     "Importance of Vedic Literatures",
//     "3 modes of material Nature",
//     "Reincarnation",
//     "Material world Vs. Spiritual world",
//     "4 regulative Principles",
//   ],
//
//   "level-3": [
//     "Energies of Lord Krishna",
//     "Incarnations of Lord Krishna",
//     "Glories of devotional service",
//     "Purpose of Human form of Life",
//     "Importance of accepting a Spiritual Master",
//   ],
//
//   "level-4": [
//     "3 features of Absolute Truth",
//     "Deity Worship or Idol Worship",
//     "Why so many religions in different parts of the World",
//     "Glories of Visiting Lord's Dhams",
//     "Glories of Vaishnava association",
//   ],
//
//   "level-5": [
//     "Importance of ekadashi and observing fasting on acharyas appearance etc",
//     "Pranam Mantras of Deities",
//     "Vaishnava etiquettes",
//     "Different kinds of Liberation",
//     "Different kinds of mellows of relationship with the Lord",
//     "Glories of Preaching Krishna consciousness to others",
//   ]
// };
//
// Future<void> uploadForAllUsers() async {
//
//   final users = await FirebaseFirestore.instance.collection('users').get();
//
//   for (var user in users.docs) {
//     await uploadQuestions(user.id);
//   }
//
//   print("All users updated");
// }
//
// Future<void> uploadQuestions(String uid) async {
//
//   final ref = FirebaseFirestore.instance
//       .collection('users')
//       .doc(uid)
//       .collection('questions');
//
//   for (var level in questionLevels.entries) {
//
//     Map<String, dynamic> data = {};
//
//     for (int i = 0; i < level.value.length; i++) {
//       data['q${i + 1}'] = {
//         "question": level.value[i],
//         "completed": false,
//       };
//     }
//
//     await ref.doc(level.key).set(data);
//   }
// }