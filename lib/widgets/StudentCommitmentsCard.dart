import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/GuideTheme.dart';
import '../actions/StudentActions.dart';
import '../utils/GuideDb.dart';
import '../utils/Snackbar.dart';
import 'GuideDialog.dart';

/// The student's daily commitments, on the guide's Student profile — shown,
/// and editable by an admin who may act on that student.
///
/// ---------------------------------------------------------------------------
/// The SAME two fields the Student app writes
/// ---------------------------------------------------------------------------
/// `users/{uid}.commitmentRounds` and `users/{uid}.readingCommitmentMinutes`,
/// written with `SetOptions(merge: true)` — byte-for-byte the same shape as
/// `Students/.../widgets/CommitmentDialog.dart`. Nothing new is stored, so the
/// CURRENT Student app shows a guide's edit with no Student app update at all:
/// its Profile reads these very fields (`utils/Commitments.dart`
/// `Commitments.fromUser`), and its live `users/{uid}` stream repaints.
///
/// Points recalculate by themselves: the server's `rescoreOnCommitmentChange`
/// trigger (`functions/scoreRecompute.js`, `onDocumentUpdated users/{uid}`)
/// already re-scores the week and month whenever these fields change, and it
/// does not care WHO changed them. No new server code is needed for (a).
///
/// ---------------------------------------------------------------------------
/// The defaults are the server's, not invented here
/// ---------------------------------------------------------------------------
/// A missing/0 chanting commitment means the standard 16 (`scoring.js`'s
/// `DEFAULT_CHANT_COMMITMENT`), and a missing reading commitment means 0 —
/// which scores a flat 50 for any reading that day. Both are shown as "not set"
/// rather than as a real commitment of 0, matching how the Student app words it.
///
/// ---------------------------------------------------------------------------
/// If the live rules refuse the write
/// ---------------------------------------------------------------------------
/// This card does not assume the deployed Firestore rules let a guide write
/// another user's document. A `permission-denied` is caught and shown as a
/// plain sentence telling the guide the change was not saved and why — never a
/// raw exception, and never a silent no-op that looks like it worked.
class StudentCommitmentsCard extends StatefulWidget {
  const StudentCommitmentsCard({
    super.key,
    required this.studentUid,
    required this.studentName,
    required this.commitmentRounds,
    required this.readingCommitmentMinutes,
    required this.canEdit,
    this.firestore,
  });

  final String studentUid;
  final String studentName;

  /// `users/{uid}.commitmentRounds`, or null when never set.
  final int? commitmentRounds;

  /// `users/{uid}.readingCommitmentMinutes`, or null when never set.
  final int? readingCommitmentMinutes;

  /// The caller's own scope decision (`_canAct` on the profile page): an admin
  /// who may not act on this student sees the values but no Edit button.
  final bool canEdit;

  /// Swapped in tests.
  final FirebaseFirestore? firestore;

  @override
  State<StudentCommitmentsCard> createState() => _StudentCommitmentsCardState();
}

/// The standard daily number when a student has none on file — the server's
/// own `DEFAULT_CHANT_COMMITMENT`.
const int kDefaultChantCommitment = 16;

/// A day's worth of minutes — the ceiling the deployed Firestore rules enforce
/// on `readingCommitmentMinutes` (`readingCommitmentOk`). Kept here so the form
/// refuses the same numbers the server would, with a sentence that explains
/// itself instead of a permission error.
const int kMaxReadingCommitmentMinutes = 1440;

/// "Chanting: 16 rounds · Reading: 30 min", with "not set" where there is no
/// value rather than a made-up zero.
String commitmentsLine(int? rounds, int? readingMinutes) {
  final r = rounds != null && rounds > 0 ? '$rounds rounds' : 'not set';
  final m = readingMinutes != null ? '$readingMinutes min' : 'not set';
  return 'Chanting: $r · Reading: $m';
}

/// The commitments dialog (chanting + reading) for one student, opened from anywhere (the Today button "Change commitment"): reads his current
/// numbers, asks, and saves with the same shared write as the profile card. Returns true when saved.
Future<bool> editStudentCommitments(BuildContext context, {required String studentUid, required String studentName, FirebaseFirestore? firestore}) async {
  final db = firestore ?? GuideDb.instance;
  int? rounds;
  int? reading;
  try {
    final u = (await db.collection('users').doc(studentUid).get()).data();
    rounds = (u?['commitmentRounds'] as num?)?.toInt();
    reading = (u?['readingCommitmentMinutes'] as num?)?.toInt();
  } catch (_) {
    // the dialog still opens, with the standard numbers
  }
  if (!context.mounted) return false;
  final result = await showDialog<_CommitmentChoice>(
    context: context,
    builder: (_) => _CommitmentDialog(studentName: studentName, rounds: rounds, readingMinutes: reading),
  );
  if (result == null || !context.mounted) return false;
  try {
    await setStudentCommitments(studentUid, rounds: result.rounds, readingMinutes: result.readingMinutes, db: db);
    if (context.mounted) showSnackbar(context, 'Commitments saved', Colors.green, Icons.check_circle);
    return true;
  } on FirebaseException catch (e) {
    if (context.mounted) showSnackbar(context, _StudentCommitmentsCardState._friendlyError(e), Colors.red, Icons.error);
  } catch (_) {
    if (context.mounted) showSnackbar(context, 'Could not save the commitments just now.', Colors.red, Icons.error);
  }
  return false;
}

class _StudentCommitmentsCardState extends State<StudentCommitmentsCard> {
  bool _saving = false;

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  Future<void> _edit() async {
    final result = await showDialog<_CommitmentChoice>(
      context: context,
      builder: (_) => _CommitmentDialog(
        studentName: widget.studentName,
        rounds: widget.commitmentRounds,
        readingMinutes: widget.readingCommitmentMinutes,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _saving = true);
    try {
      // Only the two fields, merged — never a whole-document write, which
      // would clobber anything a newer Student app version added. One shared write
      // (actions/StudentActions.dart): the AI agent sets commitments through this.
      await setStudentCommitments(
        widget.studentUid,
        rounds: result.rounds,
        readingMinutes: result.readingMinutes,
        db: _db,
      );
      if (!mounted) return;
      showSnackbar(context, 'Commitments saved', Colors.green, Icons.check_circle);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      showSnackbar(context, _friendlyError(e), Colors.red, Icons.error);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, 'Could not save the commitments just now.',
          Colors.red, Icons.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A sentence a guide can act on. `permission-denied` is the one worth
  /// naming: it means the deployed rules do not (yet) allow a guide to write
  /// this student's document, which is a server-side change, not something the
  /// guide did wrong.
  static String _friendlyError(FirebaseException e) =>
      e.code == 'permission-denied'
          ? 'You are not allowed to change this student\'s commitments yet. '
              'This needs a rules update on the server.'
          : 'Could not save the commitments just now.';

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: g.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: g.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: g.brass.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.flag_outlined, color: g.brass, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Commitments',
                    style: TextStyle(color: g.mutedText, fontSize: 13)),
                const SizedBox(height: 3),
                Text(
                  commitmentsLine(
                      widget.commitmentRounds, widget.readingCommitmentMinutes),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (widget.canEdit) ...[
            const SizedBox(width: 8),
            _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: _edit,
                    child: const Text('Edit'),
                  ),
          ],
        ],
      ),
    );
  }
}

/// What the dialog hands back.
class _CommitmentChoice {
  const _CommitmentChoice(this.rounds, this.readingMinutes);
  final int rounds;
  final int readingMinutes;
}

/// Both commitments in one dialog: chanting a whole number of rounds >= 1,
/// reading a whole number of minutes >= 0 (0 is a real answer — a beginner —
/// and scores a flat 50 for any reading that day).
class _CommitmentDialog extends StatefulWidget {
  const _CommitmentDialog({
    required this.studentName,
    required this.rounds,
    required this.readingMinutes,
  });

  final String studentName;
  final int? rounds;
  final int? readingMinutes;

  @override
  State<_CommitmentDialog> createState() => _CommitmentDialogState();
}

class _CommitmentDialogState extends State<_CommitmentDialog> {
  late final TextEditingController _rounds = TextEditingController(
      text: (widget.rounds ?? kDefaultChantCommitment).toString());
  late final TextEditingController _reading =
      TextEditingController(text: (widget.readingMinutes ?? 0).toString());

  String? _roundsError;
  String? _readingError;

  @override
  void dispose() {
    _rounds.dispose();
    _reading.dispose();
    super.dispose();
  }

  /// Whole numbers only; no sign, no decimal point, no blank.
  int? _whole(String raw) {
    final s = raw.trim();
    if (s.isEmpty || !RegExp(r'^\d+$').hasMatch(s)) return null;
    return int.tryParse(s);
  }

  void _save() {
    final r = _whole(_rounds.text);
    final m = _whole(_reading.text);
    setState(() {
      _roundsError = (r == null || r < 1)
          ? 'Enter a whole number of rounds, at least 1'
          : null;
      // The ceiling is the deployed rules' own (`readingCommitmentOk`:
      // `is int && >= 0 && <= 1440`). Without this a guide could type a number
      // the form accepted and the server then refused with permission-denied,
      // which reads as "you are not allowed" rather than "that is too many".
      _readingError = (m == null)
          ? 'Enter a whole number of minutes, 0 or more'
          : (m > kMaxReadingCommitmentMinutes
              ? 'A day is $kMaxReadingCommitmentMinutes minutes'
              : null);
    });
    if (_roundsError != null || _readingError != null) return;
    Navigator.pop(context, _CommitmentChoice(r!, m!));
  }

  @override
  Widget build(BuildContext context) {
    return GuideDialog(
      title: const Text('Set commitments'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'These are the numbers ${widget.studentName}\'s daily points are '
            'measured against.',
            style: context.gText.small,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _rounds,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Chanting (rounds a day)',
              errorText: _roundsError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reading,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Reading (minutes a day)',
              errorText: _readingError,
              helperText: '0 means any reading that day scores full marks',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
