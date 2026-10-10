import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Services/UpdateFCM.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideColors.dart';

/// LIT assessment — private, guide-only (FOLK_HANDOFF.md Section 8).
///
/// Three **independent** axes, each 1-5. They are never summed, averaged,
/// ranked or reduced to one figure — not in storage, not in the entry form,
/// not in the history list. 125 combinations stay 125 combinations.
///
/// Every assessment is a **new document**. Nothing here updates or overwrites
/// a previous assessment, so a reassessment sits beside its predecessor and a
/// disagreement stays visible instead of being silently resolved.
///
/// LIT is structurally separate from ABCDE (Rule 10): this file writes only
/// `litAssessments`, reads only `litAssessments`, and shares no widget or card
/// with book / chanting / service / association / expedition data.
///
/// Nothing in the Student app reads this collection.

/// The three axes, with the evidence each one is about.
const List<Map<String, String>> kLitAxes = [
  {
    'key': 'L',
    'title': 'Receptivity / learning relationship',
    'hint': 'Humility, openness, willingness to hear and be corrected, trust',
  },
  {
    'key': 'I',
    'title': 'Interest in Krishna consciousness',
    'hint': 'Curiosity, enthusiasm, voluntary engagement, asking questions',
  },
  {
    'key': 'T',
    'title': 'Available time',
    'hint': 'Workload, exams, commute, family situation, other commitments',
  },
];

Color _axisColor(String key, GuideColors g) {
  switch (key) {
    case 'L':
      return g.brass;
    case 'I':
      return g.success;
    default:
      return g.warning;
  }
}

/// Opens the LIT entry sheet. Returns true when an assessment was saved.
///
/// [sourceInteractionId] links the assessment back to an approved interaction
/// log; it stays null for a standalone assessment. [prefilledEvidence] is the
/// interaction's `possibleLitEvidence` text — a starting point the guide edits,
/// never a score. Scores are always chosen by hand.
Future<bool> openLitAssessmentSheet({
  required BuildContext context,
  required String studentUid,
  required String studentName,
  String? sourceInteractionId,
  String prefilledEvidence = '',
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _LitEntrySheet(
      studentUid: studentUid,
      studentName: studentName,
      sourceInteractionId: sourceInteractionId,
      prefilledEvidence: prefilledEvidence,
    ),
  );

  return saved == true;
}

class _LitEntrySheet extends StatefulWidget {
  final String studentUid;
  final String studentName;
  final String? sourceInteractionId;
  final String prefilledEvidence;

  const _LitEntrySheet({
    required this.studentUid,
    required this.studentName,
    required this.sourceInteractionId,
    required this.prefilledEvidence,
  });

  @override
  State<_LitEntrySheet> createState() => _LitEntrySheetState();
}

class _LitEntrySheetState extends State<_LitEntrySheet> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _evidence = TextEditingController();

  /// Deliberately null until the guide picks. No axis is pre-filled, so an
  /// unconsidered value can never be saved by simply pressing Save.
  final Map<String, int?> _scores = {'L': null, 'I': null, 'T': null};

  String _confidence = 'medium';
  String? _guide;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _evidence.text = widget.prefilledEvidence;
    _loadGuide();
  }

  @override
  void dispose() {
    _evidence.dispose();
    super.dispose();
  }

  Future<void> _loadGuide() async {
    final guide = await UpdateTokenService().getSavedGuide();
    if (mounted) setState(() => _guide = guide);
  }

  Future<void> _save() async {
    final missing = kLitAxes
        .where((axis) => _scores[axis['key']] == null)
        .map((axis) => axis['key'])
        .toList();

    if (missing.isNotEmpty) {
      showSnackbar(
        context,
        "Rate all three axes (${missing.join(', ')} still unset)",
        Colors.orange,
        Icons.info,
      );
      return;
    }

    if (_evidence.text.trim().isEmpty) {
      showSnackbar(
        context,
        "Evidence is required — what did you observe?",
        Colors.orange,
        Icons.info,
      );
      return;
    }

    final guide = _guide;
    if (guide == null || guide.isEmpty) {
      showSnackbar(
        context,
        "No guide selected on this device",
        Colors.red,
        Icons.error,
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // add(), never set() — a reassessment is a new document beside the old
      // one, never a replacement for it.
      await _firestore.collection('litAssessments').add({
        'studentUid': widget.studentUid,
        'studentName': widget.studentName,
        'guideId': guide,
        'L': _scores['L'],
        'I': _scores['I'],
        'T': _scores['T'],
        'evidence': _evidence.text.trim(),
        'confidence': _confidence,
        'sourceInteractionId': widget.sourceInteractionId,
        'assessedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnackbar(context, "Could not save the assessment", Colors.red,
          Icons.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: context.g.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.g.chipBackground,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "LIT assessment — ${widget.studentName}",
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Private to guides. Three independent judgements — they are "
                "never combined into one score.",
                style: TextStyle(fontSize: 12, color: context.g.mutedText),
              ),
              if (widget.sourceInteractionId != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.link, size: 14, color: context.g.mutedText),
                    const SizedBox(width: 6),
                    Text(
                      "Linked to the interaction you just approved",
                      style: TextStyle(
                        fontSize: 11,
                        color: context.g.mutedText,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              ...kLitAxes.map(_axisSelector),
              const SizedBox(height: 6),
              Text(
                "Evidence",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.g.text,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _evidence,
                enabled: !_saving,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: "What did you actually observe?",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "Confidence in this assessment",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.g.text,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: ['low', 'medium', 'high'].map((level) {
                  final selected = _confidence == level;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        level[0].toUpperCase() + level.substring(1),
                      ),
                      selected: selected,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _confidence = level),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              if (_saving)
                const Center(child: CircularProgressIndicator())
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancel"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text("Save privately"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.g.brass,
                          foregroundColor: context.g.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// One axis: its own row of 1-5, its own colour, its own state. Nothing on
  /// this widget references the other two axes.
  Widget _axisSelector(Map<String, String> axis) {
    final key = axis['key']!;
    final color = _axisColor(key, context.g);
    final value = _scores[key];

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  key,
                  style: TextStyle(
                    color: context.g.surface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  axis['title']!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(
              axis['hint']!,
              style: TextStyle(fontSize: 11, color: context.g.mutedText),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) {
              final score = i + 1;
              final selected = value == score;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _saving
                        ? null
                        : () => setState(() => _scores[key] = score),
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? color : context.g.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? color : context.g.chipBackground,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        '$score',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selected ? context.g.surface : context.g.mutedText,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// History
// -----------------------------------------------------------------------------

/// Reverse-chronological list of a student's LIT assessments.
///
/// Every assessment is listed on its own. Nothing is merged, averaged or
/// deduplicated, so two guides disagreeing — or one guide changing their mind —
/// stays visible as two entries for a human to interpret.
class LitHistorySection extends StatefulWidget {
  final String studentUid;
  final String studentName;

  const LitHistorySection({
    super.key,
    required this.studentUid,
    required this.studentName,
  });

  @override
  State<LitHistorySection> createState() => _LitHistorySectionState();
}

class _LitHistorySectionState extends State<LitHistorySection> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  String get studentUid => widget.studentUid;
  String get studentName => widget.studentName;

  @override
  void initState() {
    super.initState();
    _stream = _assessmentsStream();
  }

  @override
  void didUpdateWidget(covariant LitHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentUid != widget.studentUid) {
      _stream = _assessmentsStream();
    }
  }

  /// This student's assessments. The student's `users` doc is read first so the
  /// query carries the scope filter the security rules can prove (hierarchy).
  Stream<QuerySnapshot<Map<String, dynamic>>> _assessmentsStream() async* {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.studentUid)
        .get();
    yield* StudentScope.current()
        .constrainForStudent(
          FirebaseFirestore.instance
              .collection('litAssessments')
              .where('studentUid', isEqualTo: widget.studentUid),
          StudentRef.fromDoc(userDoc),
        )
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.g.brass.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: context.g.brass),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Guide-only. Never shown to the student.",
                  style: TextStyle(
                    fontSize: 12,
                    color: context.g.brass,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => openLitAssessmentSheet(
              context: context,
              studentUid: studentUid,
              studentName: studentName,
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text("New LIT assessment"),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.g.brass,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          // Filtered on studentUid (+ the scope filter), sorted in Dart — no
          // composite index, same approach as the interaction log list.
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final docs = snapshot.data?.docs.toList() ?? [];

            if (docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.g.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    "No assessments recorded yet",
                    style: TextStyle(color: context.g.mutedText, fontSize: 14),
                  ),
                ),
              );
            }

            docs.sort((a, b) {
              final da = a.data()['assessedAt'];
              final db = b.data()['assessedAt'];
              if (da is! Timestamp) return -1;
              if (db is! Timestamp) return 1;
              return db.compareTo(da);
            });

            return Column(
              children: docs
                  .map((d) => _assessmentCard(d.data()))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _assessmentCard(Map<String, dynamic> data) {
    final assessedAt = data['assessedAt'];
    final dateText = assessedAt is Timestamp
        ? DateFormat('dd MMM yyyy, hh:mm a').format(assessedAt.toDate())
        : "Date pending";

    final guide = (data['guideId'] ?? '').toString();
    final evidence = (data['evidence'] ?? '').toString();
    final confidence = (data['confidence'] ?? '').toString();
    final linked = (data['sourceInteractionId'] ?? '').toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dateText,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.g.mutedText,
                  ),
                ),
              ),
              if (confidence.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.g.chipBackground,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${confidence[0].toUpperCase()}${confidence.substring(1)} "
                    "confidence",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: context.g.text,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          /// Three separate labelled values. Never a sum, average or total.
          Row(
            children: kLitAxes.map((axis) {
              final key = axis['key']!;
              final raw = data[key];
              final value = raw is num ? raw.toInt().toString() : '—';
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _axisColor(key, context.g).withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "$key: $value",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _axisColor(key, context.g),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              evidence,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                linked ? Icons.link : Icons.person_outline,
                size: 12,
                color: context.g.mutedText,
              ),
              const SizedBox(width: 5),
              Text(
                linked
                    ? "From a logged interaction · $guide"
                    : "Standalone · $guide",
                style: TextStyle(fontSize: 11, color: context.g.mutedText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
