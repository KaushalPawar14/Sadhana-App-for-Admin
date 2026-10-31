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
import '../utils/StudentScope.dart';
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

/// The same form for a student and the topics to cover (the assistant's "Guide me" button too). With NO student ([studentUid] empty) the form opens with a student
/// picker (search, the guide's own students): the Associations page's "Add interaction" and a "Guide me" request that names nobody.
Future<bool> showRecordInteractionFor(BuildContext context, {String studentUid = '', String studentName = '', List<PlanPoint> topics = const []}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => RecordInteractionDialog(studentUid: studentUid, studentName: studentName, topics: topics),
  );
  return saved == true;
}

class RecordInteractionDialog extends StatefulWidget {
  const RecordInteractionDialog({super.key, this.studentUid = '', this.studentName = '', this.topics = const []});

  /// Empty: the form starts with a student picker.
  final String studentUid;
  final String studentName;

  /// The card's open interaction topics (all ticked to begin with).
  final List<PlanPoint> topics;

  @override
  State<RecordInteractionDialog> createState() => _RecordInteractionDialogState();
}

class _RecordInteractionDialogState extends State<RecordInteractionDialog> {
  late String _uid = widget.studentUid;
  late String _name = widget.studentName;
  late List<PlanPoint> _topics = widget.topics;
  late final Set<int> _covered = {for (var i = 0; i < widget.topics.length; i++) i};

  // the picker (only when no student was given)
  final TextEditingController _search = TextEditingController();
  List<({String uid, String name})>? _students;
  bool _studentsFailed = false;
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _rounds = TextEditingController();
  final TextEditingController _reading = TextEditingController();
  String _type = kInteractionTypes[1]; // Call
  // his willingness: optional (tap the chosen one again to leave it out); "same" to begin with, as the Today form has always done
  Willingness? _will = Willingness.same;
  bool _commitment = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_uid.isEmpty) _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final snap = await StudentScope.current().studentsGet();
      final list = [
        for (final d in snap.docs)
          if ((d.data()['name'] ?? '').toString().trim().isNotEmpty) (uid: d.id, name: (d.data()['name'] ?? '').toString().trim()),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() => _students = list);
    } catch (_) {
      if (mounted) setState(() => _studentsFailed = true);
    }
  }

  /// A student was picked: his open Today topics (the ones an interaction covers) are offered to tick; none is fine.
  Future<void> _pick(String uid, String name) async {
    setState(() {
      _uid = uid;
      _name = name;
      _topics = const [];
      _covered.clear();
    });
    try {
      final me = AdminProfileProvider.current?.id ?? '';
      final plan = await PlanData.instance.plan(me).first.timeout(const Duration(seconds: 3));
      for (final c in plan?.todayItems ?? const <PlanItem>[]) {
        if (c.isCard && c.studentUid == uid && mounted && _uid == uid) {
          final t = recordTopicsOf(c);
          setState(() {
            _topics = t;
            _covered
              ..clear()
              ..addAll([for (var i = 0; i < t.length; i++) i]);
          });
        }
      }
    } catch (_) {
      // no topics to offer: the interaction is still saved for him
    }
  }

  @override
  void dispose() {
    _search.dispose();
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

  bool get _canSave => !_saving && _uid.isNotEmpty && (_topics.isEmpty || _covered.isNotEmpty);

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
        studentUid: _uid,
        studentName: _name,
        raw: _notes.text.trim(),
        interactionType: _type,
        interactionDate: DateTime.now(),
        topicAnswers: [
          for (final i in _covered.toList()..sort())
            {'topic': _topics[i].kind, 'answer': 'Covered in the interaction.'},
        ],
        willingness: _will?.wire,
        addressed: true,
        source: 'guide_form',
        skipAi: true,
      );
      if (newRounds != null || newReading != null) {
        // only what he typed changes; the other number stays as it is
        final u = (await GuideDb.instance.collection('users').doc(_uid).get()).data();
        await setStudentCommitments(
          _uid,
          rounds: newRounds ?? (u?['commitmentRounds'] as num?)?.toInt(),
          readingMinutes: newReading ?? (u?['readingCommitmentMinutes'] as num?)?.toInt(),
        );
      }
      if (!mounted) return;
      showSnackbar(context, 'Interaction with $_name recorded', Colors.green, Icons.check_circle);
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the interaction just now. Nothing was ticked.';
      });
    }
  }

  /// The student picker: a search box and the guide's own students that match it.
  List<Widget> _picker(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final q = _search.text.trim().toLowerCase();
    final all = _students;
    final hits = all == null ? const <({String uid, String name})>[] : [for (final s in all) if (q.isEmpty || s.name.toLowerCase().contains(q)) s];
    return [
      Text('Which student?', style: t.bodyStrong),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey('rec-student-search'),
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Search by name', prefixIcon: Icon(Icons.search_rounded)),
      ),
      const SizedBox(height: 4),
      if (_studentsFailed)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Could not load your students. Check your connection and try again.', key: const ValueKey('rec-students-error'), style: t.small.copyWith(color: g.danger)))
      else if (all == null)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Loading your students…', style: t.small))
      else if (hits.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(all.isEmpty ? 'You have no students yet.' : 'Nobody matches "${_search.text.trim()}".', key: const ValueKey('rec-students-none'), style: t.small))
      else
        // a plain column (the dialog scrolls as a whole; a lazy list cannot be measured inside a dialog)
        Column(
          children: [
            for (final s in hits.take(40))
              ListTile(
                key: ValueKey('rec-student-${s.uid}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: 12,
                title: Text(s.name, style: t.body.copyWith(fontWeight: FontWeight.w600)),
                onTap: () => _pick(s.uid, s.name),
              ),
          ],
        ),
      const SizedBox(height: 8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return GuideDialog(
      title: Text(_name.isEmpty ? 'Record interaction' : 'Record interaction · $_name', key: const ValueKey('rec-title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_uid.isEmpty) ..._picker(context),
            if (widget.studentUid.isEmpty && _uid.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('rec-student-change'),
                  onPressed: () => setState(() {
                    _uid = '';
                    _name = '';
                    _topics = const [];
                    _covered.clear();
                  }),
                  child: const Text('Change student'),
                ),
              ),
            if (_topics.isNotEmpty) ...[
              Text('Which topics did you cover?', style: t.bodyStrong),
              for (var i = 0; i < _topics.length; i++)
                CheckboxListTile(
                  key: ValueKey('rec-topic-$i'),
                  value: _covered.contains(i),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(_topics[i].title.isEmpty ? _topics[i].text : _topics[i].title, style: t.body.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: _topics[i].title.isEmpty ? null : Text(_topics[i].text, style: t.caption),
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
              studentName: _name,
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
                  GuideChoiceChip(key: ValueKey('rec-will-${w.name}'), label: w.label, selected: _will == w, onSelected: (_) => setState(() => _will = _will == w ? null : w)),
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
