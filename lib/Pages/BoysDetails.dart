import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../Services/UpdateFCM.dart';
import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import '../utils/AdminProfile.dart';
import '../utils/ManualStudents.dart';
import '../utils/Snackbar.dart';
import 'AdminManager.dart';
import 'NotificationSettings.dart';
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

  /// The single HOD check for this screen — role based (several HODs are
  /// possible; no id is special).
  bool get _isHod => AdminProfileProvider.viewerIsHod;

  @override
  void initState() {
    super.initState();
    _loadGuide();
  }

  Future<void> _loadGuide() async {
    final guide = AdminProfileProvider.current?.id ??
        await UpdateTokenService().getSavedGuide();
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
          context.g.warning, Icons.watch_later_outlined);
      return;
    }

    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final roundsController = TextEditingController();
    String? residence;
    String? assignedGuide; // HOD only; null = Unassigned
    String? error;
    bool saving = false;

    final me = AdminProfileProvider.require();
    // A Female Enabler adds females; a Guide / Male Enabler adds males; a HOD
    // chooses. Females are only ever owned by Female Enablers, males by anyone
    // but a Female Enabler.
    String gender = me.isFemaleEnabler ? 'female' : 'male';
    final admins = me.admins;
    List<AdminSummary> ownersFor(String g) => [
          for (final a in admins)
            if (g == 'female'
                ? a.role == AdminRole.femaleEnabler
                : a.role != AdminRole.femaleEnabler)
              a,
        ];

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
                  'gender': gender,
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
                    if (_isHod) ...[
                      DropdownButtonFormField<String>(
                        value: gender,
                        decoration:
                            const InputDecoration(labelText: "Gender"),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'female', child: Text('Female')),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setDialogState(() {
                                  gender = v ?? gender;
                                  // The owner must suit the gender.
                                  if (assignedGuide != null &&
                                      !ownersFor(gender)
                                          .any((a) => a.id == assignedGuide)) {
                                    assignedGuide = null;
                                  }
                                }),
                      ),
                      const SizedBox(height: 10),
                    ],
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
                          ...ownersFor(gender).map((a) =>
                              DropdownMenuItem<String?>(
                                  value: a.id, child: Text(a.displayName))),
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
                              TextStyle(color: context.g.danger, fontSize: 12)),
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

  /// The Tasks tab ("Other tasks"): a two-column grid of pastel tiles. The tiles
  /// reflow in a plain two-column grid (no `LayoutBuilder`: that caused real-device
  /// crashes in this app), each as tall as the taller of its row and growing with
  /// the text.
  ///
  /// Add student and Submissions are available to every guide; Add admin follows
  /// the add-rights matrix on its own screen; Notifications is every admin's own
  /// preferences.
  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final tiles = <Widget>[
      GuideGradientTile(
        pastel: GuidePastel.sage,
        icon: Icons.person_add_alt_outlined,
        title: "Add student",
        subtitle: "Register a new student",
        onTap: _openAddStudentDialog,
        minHeight: 150,
        large: true,
        showChevron: false,
      ),

      /// Replaces the missing-reports section removed from the calendar's today
      /// panel. Available to every guide: `SubmissionStatusPage` resolves its own
      /// HOD/guide scoping internally.
      GuideGradientTile(
        pastel: GuidePastel.sand,
        icon: Icons.fact_check_outlined,
        title: "Submissions",
        subtitle: "Review submitted work",
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SubmissionStatusPage()),
        ),
        minHeight: 150,
        large: true,
        showChevron: false,
      ),

      /// Available to any guide and the HOD (see `AdminManager.dart`).
      GuideGradientTile(
        pastel: GuidePastel.slate,
        icon: Icons.person_add_alt_1_outlined,
        title: "Add admin",
        subtitle: "Invite another guide",
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminManagerPage()),
        ),
        minHeight: 150,
        large: true,
        showChevron: false,
      ),

      /// Which students and which kinds of events notify this admin (saved on the
      /// server; applied when notifications route).
      GuideGradientTile(
        pastel: GuidePastel.mauve,
        icon: Icons.notifications_active_outlined,
        title: "Notifications",
        subtitle: "Choose what you hear about",
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
        ),
        minHeight: 150,
        large: true,
        showChevron: false,
      ),
    ];

    return ListView(
      padding: EdgeInsets.only(bottom: GuideSpace.navClearanceOf(context)),
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                GuideSpace.pagePadding, 28, GuideSpace.pagePadding, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GuideLabel('Manage'),
                const SizedBox(height: 4),
                Text('Other tasks', style: t.screenTitle),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              GuideSpace.pagePadding, 22, GuideSpace.pagePadding, 0),
          child: GuideTileGrid(tiles: tiles),
        ),
      ],
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