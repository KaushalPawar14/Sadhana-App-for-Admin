import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/AdminProfile.dart';
import '../utils/BoardQueries.dart';
import '../utils/ColorProvider.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import 'AbcdeActivityCard.dart';
import 'HolisticSuggestion.dart';
import 'InteractionLogger.dart';
import 'LitAssessment.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../theme/GuideColors.dart';
import '../utils/GuideDb.dart';

/// The student profile page — Phase 3 of the FOLK Boys board redesign.
/// Opened by the new fourth card icon on `Home/FolkBoysWorkspace.dart`'s
/// student cards. **Replaces `Pages/Profile.dart`'s `BoyProfileDetailsPage`**,
/// which stays in place, untouched, until Phase 6 deletes it — this page does
/// not import from or depend on that file at all, so nothing here breaks when
/// it goes.
///
/// ---------------------------------------------------------------------------
/// What was carried over, and how (Rule 1 — reuse verbatim, never reimplement)
/// ---------------------------------------------------------------------------
/// Four real systems, reused completely unmodified, each still writing only
/// its own existing collection:
///  1. LIT assessment — [LitHistorySection] (`Pages/LitAssessment.dart`),
///     which itself calls `openLitAssessmentSheet` internally for "New LIT
///     assessment". L, I, T stay three independent 1-5 axes everywhere in
///     that file — never summed, averaged or reduced. See that file's own
///     `_assessmentCard` for the three separately-labelled chips.
///  2. ABCDE — [AbcdeActivityCard] (`Pages/AbcdeActivityCard.dart`). Five
///     dimensions, never aggregated — that file's own build() ends with the
///     literal disclaimer "these five are shown side by side, never combined
///     into a single score."
///  3. Interactions — [InteractionLogSection] (moved here from
///     `Pages/Profile.dart`'s definition, since that class is small, generic
///     UI plumbing with no business logic of its own — it is just a button
///     that pushes `InteractionLoggerPage`, unchanged). Everything that
///     matters — the long-press multi-select delete via
///     `utils/SelectableDelete.dart`, its own `_canDeleteInteraction`
///     permission check, and `_notifyHod`'s FCM behaviour — lives inside
///     `Pages/InteractionLogger.dart` itself and was never touched.
///  4. Holistic Suggestion — [HolisticSuggestionSection]
///     (`Pages/HolisticSuggestion.dart`), including its permanent
///     "AI-generated suggestion — guide judgment decides the actual next
///     step" disclaimer, unchanged.
///
/// Two more pieces carried over because they would otherwise be lost when
/// `Profile.dart` is deleted in Phase 6:
///  5. [DobCard] — copied verbatim (byte-for-byte) into this file. `Profile.dart`
///     keeps its own copy until Phase 6 deletes that whole file; having two
///     copies of one small, static, non-business-logic widget for one phase
///     is the explicit, sanctioned reading of "carry over ... since they'd
///     otherwise be lost" — not a drift to clean up early.
///  6. The header identity block (name, role badge, email, mobile) — the
///     small `_infoCard`/`_roleBadge` helpers below are the same code
///     `Profile.dart` used, kept as private methods on this page rather than
///     a shared file, since they are generic card-shell UI, not reusable
///     business logic.
///
/// ---------------------------------------------------------------------------
/// Deliberately NOT carried over
/// ---------------------------------------------------------------------------
/// `ScorecardSection`, `BadgesSection`, `BookProgressSection` and
/// `questionsSection` — all four have zero call sites in `Profile.dart`
/// already (Total Points and Badges moved to `Home/Calendar.dart` on
/// 2026-08-14; Book Progress is superseded by the Phase 2 card dropdown;
/// `questionsSection` has been commented out since before this redesign
/// began). None of the four needed carrying anywhere.
///
/// ⚠️ **`GuideAssignmentCard`'s "Assign to Me" button is a deliberate
/// REPLACEMENT, not a silent loss.** Assignment now happens by dragging a
/// card onto a column on the board (`FolkBoysWorkspace._handleDrop`), which
/// already has a real confirmation dialog and, since that file's own earlier
/// task, lets a guide claim/release their own students the same way
/// "Assign to Me" did — the drag mechanism is simply the one, single write
/// path for every kind of reassignment now, rather than two different paths
/// (a button here, a drag there) that could disagree.
///
/// ---------------------------------------------------------------------------
/// Scores moved OFF this page (later task)
/// ---------------------------------------------------------------------------
/// An earlier task resolved the "which score belongs here" open question by
/// putting both the real weighted `competition/{name}` figure and the
/// unweighted `scorecard/{name}` total on this page. A later task moved both
/// to a new "Scores" tab on `Home/Calendar.dart` instead (alongside that
/// screen's pre-existing Points/Badges/Books tabs, the natural home for a
/// student's stat displays) and removed them from here — this page no longer
/// imports `utils/CompetitionScore.dart` or `utils/ScorecardPoints.dart` at
/// all. See `Home/Calendar.dart._scoresPanel` for the current implementation.
///
/// ---------------------------------------------------------------------------
/// Permissions — Part 4, a genuine tightening from the old behaviour
/// ---------------------------------------------------------------------------
/// `Profile.dart` had NO permission gate at all: any guide could open any
/// student's page and edit DOB, log interactions, run LIT assessments, or
/// generate AI suggestions for a student who was not theirs. Now that guides
/// can see unassigned (and, structurally, any) student's uid reach this page,
/// that was worth re-examining rather than carrying forward unexamined.
///
/// Implemented default (explicitly flagged as a default, not a final answer
/// — see [_canAct]'s own doc comment for the real open question): the HOD may
/// act on anyone; a guide may act on their own current students; for anyone
/// else the page still opens and is fully READABLE (every section renders,
/// including LIT/interaction HISTORY), but the actionable controls inside
/// [DobCard], [LitHistorySection], [InteractionLogSection] and
/// [HolisticSuggestionSection] are inert — see [_gatedAction].
///
/// ⚠️ **Why `IgnorePointer` + `Opacity`, not a parameter on the reused
/// widgets.** Adding a `readOnly` flag to any of those four would mean
/// modifying widgets this task explicitly says to reuse verbatim. Gating at
/// the call site instead means every one of those four files is untouched —
/// [_gatedAction] wraps the finished widget from the outside, blocking all
/// touch input to its subtree while still rendering it normally, so existing
/// history (already-recorded LIT assessments, for instance) stays visible —
/// only the ability to add to it is blocked. This IS itself a judgment call
/// worth surfacing: an unrelated guide can still READ another guide's past
/// LIT evidence about this student under this design. If that read access
/// should also be restricted, `LitHistorySection` would need an actual
/// modification (a real Rule 1 exception), which was not made unilaterally.
class StudentProfilePage extends StatefulWidget {
  final String studentUid;

  const StudentProfilePage({super.key, required this.studentUid});

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  /// Who is looking at this page — the signed-in admin's profile (role-based
  /// hierarchy), loaded before any screen is shown.
  final AdminProfile _viewer = AdminProfileProvider.require();

  /// Whether the viewer may act on this student: the same rule the server
  /// enforces ([StudentScope.canManage] — a HOD any student; a Guide his own,
  /// his Male Enablers' and unassigned males; an Enabler his own and unassigned
  /// students of his gender). Evaluated on the student's CURRENT assignment,
  /// read fresh from the same stream the rest of this page uses. For anyone
  /// else the page stays readable but its controls are inert (see
  /// [_gatedAction]).
  bool _canAct(StudentRef student) => StudentScope(_viewer).canManage(student);

  /// Wraps an already-built, verbatim-reused section so its controls become
  /// inert when [allowed] is false, without modifying that section's own
  /// code at all. See this file's header for why this shape was chosen over
  /// adding a parameter to the reused widgets.
  Widget _gatedAction({required bool allowed, required Widget child}) {
    if (allowed) return child;
    return Opacity(
      opacity: 0.55,
      child: IgnorePointer(child: child),
    );
  }

  Widget _readOnlyBanner(ColorProvider colorProvider) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.g.warning.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.g.warning.withValues(alpha: .14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: context.g.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "This student is not in your care. You can view this page, "
              "but date of birth, LIT assessment, interaction logging and AI "
              "suggestions are only available to the admins who manage this "
              "student.",
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.g.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Part 5, this task: a guide-entered student has no submitted data
  /// anywhere on this page — ABCDE, LIT, interactions, the Calendar page's
  /// tabs will all legitimately show their own "no data yet" states, which
  /// could otherwise read as something being broken rather than as expected
  /// for a student who hasn't installed the app yet.
  Widget _manualEntryBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.g.warning.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.g.warning.withValues(alpha: .14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.edit_note, size: 18, color: context.g.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Added manually by a guide — this student hasn't registered "
              "in the app yet, so there's no submitted sadhana data. "
              "Everything here will fill in automatically once they "
              "register with this same mobile number.",
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.g.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header identity block — carried over from Profile.dart (item 6)
  // ---------------------------------------------------------------------------

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: context.g.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: context.g.mutedText, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleBadge(String role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: GuideColors.heroDivider,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role,
        style: context.gText.bodyStrong.copyWith(color: GuideColors.heroText),
      ),
    );
  }

  /// The three residence values a student may ever have — reused verbatim
  /// from `utils/BoardQueries.dart` (`kRoleFolk`/`kRoleHostel`/
  /// `kRoleLocalite`), the same constants the board's own tint/split logic
  /// already treats as canonical. Never invented here (Rule 3, Master Task
  /// 2026-09-11 "Guide can change a student's residence", Part 2 item 2).
  static const List<String> _residenceOptions = [
    kRoleFolk,
    kRoleHostel,
    kRoleLocalite,
  ];

  /// Which report collection a residence value's FUTURE submissions land
  /// in — the exact same split `Home/Calendar.dart`, `AbcdeActivityCard.dart`
  /// and the Student app's own `Calendar.dart` already use. Reused here only
  /// to detect when a residence change CROSSES that boundary, never to read
  /// or write a report itself (Rule 14/15 — this page never touches
  /// `sadhana-reports`/`hostel-sadhana`).
  String _reportBucketFor(String role) =>
      (role == kRoleHostel || role == kRoleLocalite)
          ? 'hostel-sadhana'
          : 'sadhana-reports';

  /// Residence badge, made tappable only for whoever [_canAct] already
  /// allows to edit this student (Part 2 item 3) — same permission gate
  /// `DobCard`/`InteractionLogSection`/etc. already use on this page, not a
  /// new rule invented for this one field.
  Widget _residenceBadge(String role, bool canAct, StudentRef student) {
    final badge = _roleBadge(role);
    if (!canAct) return badge;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _changeResidence(
        currentRole: role,
        student: student,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            badge,
            const SizedBox(width: 6),
            const Icon(Icons.edit_outlined, size: 16, color: GuideColors.heroMuted),
          ],
        ),
      ),
    );
  }

  /// Part 2 — lets the student's own guide, or the HOD, change residence
  /// from this page.
  ///
  /// ⚠️ **Enforced in code, not just UI (item 3).** `_gatedAction`'s
  /// `IgnorePointer` (used elsewhere on this page) only blocks the TAP that
  /// reaches this method in the first place — it is a UI-layer defense, not
  /// a guarantee. This method re-runs [_canAct] itself, independently,
  /// right before the actual write, so the write refuses even if something
  /// upstream (a future refactor, a stale rebuild) ever let an
  /// unauthorised tap through. `DobCard` above does not do this — it has no
  /// second check of its own — but this task specifically asked for
  /// enforcement in code for this field, so this control holds itself to a
  /// stricter standard than that existing precedent.
  Future<void> _changeResidence({
    required String currentRole,
    required StudentRef student,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Change residence',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              for (final option in _residenceOptions)
                ListTile(
                  title: Text(option),
                  trailing: option == currentRole
                      ? Icon(Icons.check, color: context.g.success)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null || selected == currentRole) return;

    if (!_canAct(student)) {
      if (context.mounted) {
        showSnackbar(
          context,
          "You don't have permission to change this student's residence",
          Colors.red,
          Icons.lock_outline,
        );
      }
      return;
    }

    // Part 2 item 5, revised by Master Task 2026-09-11 "Read reports from
    // both collections so history survives a residence change" — crossing
    // the FOLK <-> Hostel/Localite boundary still changes which collection
    // FUTURE reports land in (past reports are never moved, Rule 14/15),
    // but that no longer hides anything: every read site that shows this
    // student's report history (calendar, ABCDE activity, submission
    // status) now reads and merges BOTH collections
    // (`utils/SadhanaReportSource.dart`), so nothing disappears. This is
    // now a plain heads-up, not a warning — no warning needed at all for a
    // Hostel <-> Localite switch, since both already share the same
    // `hostel-sadhana` bucket and this note would have nothing to say.
    if (_reportBucketFor(currentRole) != _reportBucketFor(selected)) {
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Change residence?'),
          content: const Text(
            "Reports submitted from now on will be filed under the new "
            "residence. Nothing is lost — this student's full sadhana "
            'history, from both before and after the switch, still shows '
            'in their calendar and ABCDE activity. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await GuideDb.instance
          .collection('users')
          .doc(widget.studentUid)
          .set({'role': selected}, SetOptions(merge: true));
      if (context.mounted) {
        showSnackbar(
            context, 'Residence updated', context.g.success, Icons.check_circle);
      }
    } catch (_) {
      if (context.mounted) {
        showSnackbar(context, 'Could not update residence', Colors.red,
            Icons.error);
      }
    }
  }

  Widget _sectionTitle(ColorProvider colorProvider, String text) =>
      GuideSectionTitle(text);

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: GuideDb.instance
                .collection('users')
                .doc(widget.studentUid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data!.data() ?? <String, dynamic>{};

              final name = (data['name'] ?? '').toString();
              final role = (data['role'] ?? '').toString();
              final email = (data['email'] ?? '').toString();
              final mobile = (data['mobileNumber'] ?? '').toString();
              final student = StudentRef.fromUser(widget.studentUid, data);
              final canAct = _canAct(student);

              // Manually-added ("offline roster") student — Part 5, this
              // task: no auth account, no email, so a blank Email card would
              // read as broken data rather than as "not registered yet."
              // See `utils/ManualStudents.dart`'s own header for the schema.
              final isManual = data['isManualEntry'] == true;

              return SingleChildScrollView(
                child: Column(
                  children: [
                    // HEADER — same gradient/avatar/name/role-badge shape as
                    // the old Profile.dart, minus GuideAssignmentCard.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 60, bottom: 40),
                      decoration: const BoxDecoration(
                        gradient: GuideColors.heroGradient,
                        borderRadius:
                            BorderRadius.vertical(bottom: Radius.circular(35)),
                      ),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_ios,
                                    color: GuideColors.heroText),
                                tooltip: 'Back',
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: context.g.brass,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: context.gText.screenTitle.copyWith(
                                fontSize: 36,
                                color: context.g.onPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              name,
                              textAlign: TextAlign.center,
                              style: context.gText.screenTitle
                                  .copyWith(color: GuideColors.heroText),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _residenceBadge(role, canAct, student),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          if (!canAct)
                            _readOnlyBanner(colorProvider),

                          if (isManual) _manualEntryBanner(),

                          _infoCard(
                            icon: Icons.email_outlined,
                            label: "Email Address",
                            value: isManual && email.isEmpty
                                ? "Not registered yet"
                                : email,
                            color: context.g.brass,
                          ),
                          _infoCard(
                            icon: Icons.phone_outlined,
                            label: "Mobile Number",
                            value: mobile,
                            color: context.g.success,
                          ),

                          // DATE OF BIRTH — gated (Part 4).
                          _gatedAction(
                            allowed: canAct,
                            child: DobCard(
                              userId: widget.studentUid,
                              dob: data['dob'] is Timestamp
                                  ? (data['dob'] as Timestamp).toDate()
                                  : null,
                            ),
                          ),

                          const SizedBox(height: 25),

                          // ABCDE ACTIVITY — never gated: this card has no
                          // write action at all (see AbcdeActivityCard.dart's
                          // own header, "STRICTLY READ-ONLY" applies to its
                          // sibling BooksProgress.dart and equally to this
                          // one by inspection — its only interactive control
                          // is a local show/hide trend toggle).
                          _sectionTitle(colorProvider, "ABCDE Activity"),
                          const SizedBox(height: 10),
                          AbcdeActivityCard(
                            studentUid: widget.studentUid,
                            studentName: name,
                            role: role,
                            lifetimeRounds:
                                _asInt(data['lifetimeRounds']),
                          ),

                          const SizedBox(height: 25),

                          // INTERACTIONS — gated (Part 4).
                          _sectionTitle(colorProvider, "Interactions"),
                          const SizedBox(height: 10),
                          _gatedAction(
                            allowed: canAct,
                            child: InteractionLogSection(
                              studentUid: widget.studentUid,
                              studentName: name,
                            ),
                          ),

                          const SizedBox(height: 25),

                          // LIT HISTORY — gated (Part 4).
                          _sectionTitle(colorProvider, "LIT History"),
                          const SizedBox(height: 10),
                          _gatedAction(
                            allowed: canAct,
                            child: LitHistorySection(
                              studentUid: widget.studentUid,
                              studentName: name,
                            ),
                          ),

                          const SizedBox(height: 25),

                          // SUGGESTED NEXT ACTION — gated (Part 4).
                          _sectionTitle(colorProvider, "Suggested Next Action"),
                          const SizedBox(height: 10),
                          _gatedAction(
                            allowed: canAct,
                            child: HolisticSuggestionSection(
                              studentUid: widget.studentUid,
                              studentName: name,
                              profileData: data,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

// -----------------------------------------------------------------------------
// DobCard — copied verbatim from Profile.dart (item 5). See this file's own
// header for why a temporary duplicate, rather than a move, is the correct
// reading of this task's "carry over" instruction.
// -----------------------------------------------------------------------------

/// Date of birth, shown and editable from the guide's side.
///
/// Students who registered before `dob` existed have no value, so this shows
/// an invitation rather than a blank — a guide can fill it in when the
/// student tells them, typically during an association meeting.
///
/// Writes only the `dob` field with merge, so nothing else on the user
/// document is disturbed. The parent is a live StreamBuilder, so the card
/// refreshes itself once the write lands.
class DobCard extends StatelessWidget {
  final String userId;
  final DateTime? dob;

  const DobCard({super.key, required this.userId, this.dob});

  Future<void> _pickAndSave(BuildContext context) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: dob ?? DateTime(now.year - 20),
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 10, now.month, now.day),
      helpText: "Select date of birth",
    );

    if (picked == null) return;

    try {
      await GuideDb.instance.collection('users').doc(userId).set(
        {'dob': Timestamp.fromDate(picked)},
        SetOptions(merge: true),
      );
      if (context.mounted) {
        showSnackbar(context, "Date of birth saved", Colors.green,
            Icons.check_circle);
      }
    } catch (_) {
      if (context.mounted) {
        showSnackbar(context, "Could not save date of birth", Colors.red,
            Icons.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSet = dob != null;
    final colour = isSet ? context.g.danger : context.g.mutedText;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _pickAndSave(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.g.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: context.g.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colour.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.cake_outlined, color: colour, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Date of Birth",
                    style: TextStyle(color: context.g.mutedText, fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isSet
                        ? DateFormat('dd MMM yyyy').format(dob!)
                        : "Not set — tap to add",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSet ? null : context.g.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit, size: 16, color: context.g.mutedText),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// InteractionLogSection — moved here from Profile.dart (item 3). Generic UI
// plumbing only: the real logic (delete, permissions, FCM) lives untouched in
// Pages/InteractionLogger.dart, which this still navigates to unchanged.
// -----------------------------------------------------------------------------

/// "Log Interaction" entry point.
///
/// Lives here rather than a shared file because this page already receives
/// the student's real uid, so `interactionLogs.studentUid` can be set
/// directly — no name lookup, and no ambiguity when two students share a
/// name.
class InteractionLogSection extends StatelessWidget {
  final String studentUid;
  final String studentName;

  const InteractionLogSection({
    super.key,
    required this.studentUid,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: context.g.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.g.brass.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.record_voice_over,
                  color: context.g.brass,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  "Record what happened in your own words. It's saved "
                  "immediately — AI fills in the details, and you can edit "
                  "them afterward from the Interactions list.",
                  style: TextStyle(color: context.g.mutedText, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InteractionLoggerPage(
                    studentUid: studentUid,
                    studentName: studentName,
                  ),
                ),
              ),
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text("Log Interaction"),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.g.brass,
                foregroundColor: context.g.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
