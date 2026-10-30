import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../actions/InteractionActions.dart';
import '../actions/StudentActions.dart';
import '../theme/GuideTheme.dart';
import '../utils/AdminProfile.dart';
import '../utils/GuideDb.dart';
import '../utils/PlanData.dart';
import '../utils/PlanTopicActions.dart';
import '../utils/Snackbar.dart';
import '../utils/VoiceNote.dart';
import 'GuideDialog.dart';
import 'GuideMeta.dart';
import 'VoiceNoteButton.dart';

/// The guide's willingness reading, as the form offers it: more / same / less than before.
enum Willingness {
  more('willing', '↑ More'),
  same('neutral', '= Same'),
  less('hesitant', '↓ Less');

  const Willingness(this.wire, this.label);

  /// What the server's Surrender % reads (`willing` | `neutral` | `hesitant`).
  final String wire;
  final String label;
}

/// RECORD INTERACTION by hand (Today's button on a worry, a streak, a Surrender step ... any interaction topic): the student and the card's open topics
/// are filled in; the guide ticks what he covered, types (or speaks with the mic) his notes, says if the student's willingness is more / same /
/// less, and may set a new commitment. Save = the SAME records as the AI path (the interaction, its history line, the Surrender %, the ticks of
/// the covered topics, the next step of the plan), written by plain code: NO AI call (only the mic uses transcription). Nothing is ticked before
/// the save, and the plan ticks by itself when the server has the record.
///
/// Returns true when the interaction was saved.
Future<bool> showRecordInteractionDialog(BuildContext context, {required PlanItem card, PlanPoint? tapped}) =>
    showRecordInteractionFor(context, studentUid: card.studentUid, studentName: card.studentName, topics: recordTopicsOf(card));

/// The same form for a student and the topics to cover (the assistant's "Guide me" button too).
Future<bool> showRecordInteractionFor(BuildContext context, {required String studentUid, required String studentName, List<PlanPoint> topics = const []}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => RecordInteractionDialog(studentUid: studentUid, studentName: studentName, topics: topics),
  );
  return saved == true;
}

class RecordInteractionDialog extends StatefulWidget {
  const RecordInteractionDialog({super.key, required this.studentUid, required this.studentName, required this.topics});

  final String studentUid;
  final String studentName;

  /// The card's open interaction topics (all ticked to begin with).
  final List<PlanPoint> topics;

  @override
  State<RecordInteractionDialog> createState() => _RecordInteractionDialogState();
}

class _RecordInteractionDialogState extends State<RecordInteractionDialog> {
  late final Set<int> _covered = {for (var i = 0; i < widget.topics.length; i++) i};
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _rounds = TextEditingController();
  final TextEditingController _reading = TextEditingController();
  String _type = kInteractionTypes[1]; // Call
  Willingness _will = Willingness.same;
  bool _commitment = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    _rounds.dispose();
    _reading.dispose();
    super.dispose();
  }

  int? _whole(String raw) {
    final s = raw.trim();
    if (s.isEmpty || !RegExp(r'^\d+$').hasMatch(s)) return null;
    return int.tryParse(s);
  }

  bool get _canSave => !_saving && (widget.topics.isEmpty || _covered.isNotEmpty);

  Future<void> _save() async {
    final me = AdminProfileProvider.current;
    if (me == null) return;
    int? newRounds;
    int? newReading;
    if (_commitment) {
      newRounds = _rounds.text.trim().isEmpty ? null : _whole(_rounds.text);
      newReading = _reading.text.trim().isEmpty ? null : _whole(_reading.text);
      final bad = (_rounds.text.trim().isNotEmpty && newRounds == null) || (_reading.text.trim().isNotEmpty && newReading == null);
      final problem = bad ? 'Enter whole numbers for the commitment' : commitmentProblem(rounds: newRounds, readingMinutes: newReading);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await saveInteraction(
        guideId: me.id,
        studentUid: widget.studentUid,
        studentName: widget.studentName,
        raw: _notes.text.trim(),
        interactionType: _type,
        interactionDate: DateTime.now(),
        topicAnswers: [
          for (final i in _covered.toList()..sort())
            {'topic': widget.topics[i].kind, 'answer': 'Covered in the interaction.'},
        ],
        willingness: _will.wire,
        addressed: true,
        source: 'guide_form',
        skipAi: true,
      );
      if (newRounds != null || newReading != null) {
        // only what he typed changes; the other number stays as it is
        final u = (await GuideDb.instance.collection('users').doc(widget.studentUid).get()).data();
        await setStudentCommitments(
          widget.studentUid,
          rounds: newRounds ?? (u?['commitmentRounds'] as num?)?.toInt(),
          readingMinutes: newReading ?? (u?['readingCommitmentMinutes'] as num?)?.toInt(),
        );
      }
      if (!mounted) return;
      showSnackbar(context, 'Interaction with ${widget.studentName} recorded', Colors.green, Icons.check_circle);
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the interaction just now. Nothing was ticked.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return GuideDialog(
      title: Text('Record interaction · ${widget.studentName}', key: const ValueKey('rec-title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.topics.isNotEmpty) ...[
              Text('Which topics did you cover?', style: t.bodyStrong),
              for (var i = 0; i < widget.topics.length; i++)
                CheckboxListTile(
                  key: ValueKey('rec-topic-$i'),
                  value: _covered.contains(i),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(widget.topics[i].title.isEmpty ? widget.topics[i].text : widget.topics[i].title, style: t.body.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: widget.topics[i].title.isEmpty ? null : Text(widget.topics[i].text, style: t.caption),
                  onChanged: (v) => setState(() => v == true ? _covered.add(i) : _covered.remove(i)),
                ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              children: [
                for (final k in kInteractionTypes)
                  GuideChoiceChip(key: ValueKey('rec-type-$k'), label: k, selected: _type == k, onSelected: (_) => setState(() => _type = k)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('rec-notes'),
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (what was said)', alignLabelWithHint: true),
            ),
            const SizedBox(height: 4),
            VoiceNoteButton(
              purpose: VoicePurpose.interaction,
              studentName: widget.studentName,
              existingText: () => _notes.text,
              onText: (text) => setState(() => _notes.text = _notes.text.trim().isEmpty ? text : '${_notes.text.trim()} $text'),
            ),
            const SizedBox(height: 10),
            Text("His willingness, compared with before", style: t.bodyStrong),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final w in Willingness.values)
                  GuideChoiceChip(key: ValueKey('rec-will-${w.name}'), label: w.label, selected: _will == w, onSelected: (_) => setState(() => _will = w)),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              key: const ValueKey('rec-commit-toggle'),
              onTap: () => setState(() => _commitment = !_commitment),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Icon(_commitment ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: g.mutedText),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Set a new commitment (optional)', style: t.body)),
                  ],
                ),
              ),
            ),
            if (_commitment) ...[
              TextField(
                key: const ValueKey('rec-rounds'),
                controller: _rounds,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Chanting (rounds a day)'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('rec-reading'),
                controller: _reading,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Reading (minutes a day)'),
              ),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const ValueKey('rec-error'), style: t.small.copyWith(color: g.danger))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(key: const ValueKey('rec-save'), onPressed: _canSave ? _save : null, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
