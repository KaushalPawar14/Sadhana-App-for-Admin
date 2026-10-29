import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Services/GuideAi.dart';
import '../actions/DeleteActions.dart';
import '../actions/InteractionActions.dart';
import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/SelectableDelete.dart';
import '../utils/Snackbar.dart';
import '../utils/VoiceNote.dart';
import '../widgets/VoiceNoteButton.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../utils/AiMarkdown.dart';
import '../widgets/AiText.dart';
import '../widgets/GuideSurface.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';
import '../widgets/GuideSheet.dart';

/// Phase 5, item 1 — interaction logging.
///
/// Single-step entry: the guide types or speaks what was discussed and taps Save. Nothing else
/// is shown or asked — no extracted fields, no review, no approval. The record is complete and
/// live the moment the write succeeds; the SERVER then analyses the note in the background
/// (what the AI extraction used to do on the phone), silently fills in the details, and makes
/// new suggestions for the student (see `functions/interactionAI.js`).
///
/// Writes `interactionLogs/{autoId}`.
///
/// `status` is always written as `'approved'` and `approvedSummary` is always populated
/// immediately — `HolisticSuggestion.dart`, `WeeklyPlanning.dart` and `PlanningQueries.dart`
/// all filter on `status == 'approved'` and read `approvedSummary`.
///
/// LIT is deliberately absent here. `possibleLitEvidence` is free text the guide may read; no
/// score is entered, computed or displayed anywhere in this file.
///
/// Corrections happen after the fact: a saved entry can be opened from the list below and
/// edited directly (`InteractionDetailPage`).
// `kInteractionTypes` lives with the shared save (actions/InteractionActions.dart);
// re-exported so anything that imported it from here still finds it.
export '../actions/InteractionActions.dart' show kInteractionTypes;

class InteractionLoggerPage extends StatefulWidget {
  final String studentUid;
  final String studentName;

  const InteractionLoggerPage({
    super.key,
    required this.studentUid,
    required this.studentName,
  });

  @override
  State<InteractionLoggerPage> createState() => _InteractionLoggerPageState();
}

class _InteractionLoggerPageState extends State<InteractionLoggerPage> {
  final FirebaseFirestore _firestore = GuideDb.instance;

  /// The signed-in admin's id (stamped on a new log as `guideId`).
  String get _selectedGuide => AdminProfileProvider.require().id;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  /// This student's CURRENT assignment, resolved once. This screen's
  /// visibility is NOT scoped by `interactionLogs.guideId`: whoever can reach
  /// the screen for this student already sees every log for them regardless
  /// of who wrote it, so delete permission follows the student (any admin who
  /// may manage the student), not an individual log. It also supplies the
  /// scope filter the list query needs to be provable by the rules.
  StudentRef? _studentRef;
  bool _studentRefFailed = false;

  @override
  void initState() {
    super.initState();
    _loadStudentRef();
  }

  Future<void> _loadStudentRef() async {
    try {
      final doc =
          await _firestore.collection('users').doc(widget.studentUid).get();
      if (mounted) setState(() => _studentRef = StudentRef.fromDoc(doc));
    } catch (_) {
      // Left null — _canDeleteInteraction below fails closed on null.
      if (mounted) setState(() => _studentRefFailed = true);
    }
  }

  // ---------------------------------------------------------------------------
  // Multi-select + delete (Part 2). Shared mechanism — see
  // utils/SelectableDelete.dart's own header for the interaction model and
  // why each delete re-checks permission against fresh data rather than
  // trusting this selection state.
  // ---------------------------------------------------------------------------

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _cancelSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// Deliberately ignores the individual log's own `data` — see the
  /// [_studentRef] doc comment for why this screen's delete permission
  /// is student-scoped, not per-log-`guideId`-scoped.
  Future<bool> _canDeleteInteraction(Map<String, dynamic> data) async {
    return canDeleteForStudent(_studentRef, AdminProfileProvider.require());
  }

  Future<void> _deleteSelected() async {
    final deleted = await confirmAndDeleteSelected(
      context: context,
      collectionName: 'interactionLogs',
      selectedIds: _selectedIds,
      canDelete: _canDeleteInteraction,
      itemNounSingular: 'interaction log',
      itemNounPlural: 'interaction logs',
    );
    if (!mounted) return;
    setState(() {
      _selectedIds.removeAll(deleted);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  /// The "Delete interaction" button on a card: the same confirmed, permission-checked delete as long-press select, for one.
  Future<void> _deleteOne(String docId) async {
    await confirmAndDeleteSelected(
      context: context,
      collectionName: 'interactionLogs',
      selectedIds: {docId},
      canDelete: _canDeleteInteraction,
      itemNounSingular: 'interaction log',
      itemNounPlural: 'interaction logs',
    );
  }

  /// The "Remove follow-up" button: clears only the follow-up date (the interaction and its notes stay), after asking.
  Future<void> _removeFollowUp(String docId, DateTime when) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: const Text('Remove this follow-up?'),
        content: Text('The follow-up on ${DateFormat('dd MMM yyyy').format(when)} will be removed from your lists. The interaction itself and its notes stay.'),
        actions: [
          TextButton(key: const ValueKey('follow-up-keep'), onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
          TextButton(
            key: const ValueKey('follow-up-remove-yes'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Remove', style: TextStyle(color: dialogContext.g.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await removeInteractionFollowUp(docId);
      if (mounted) showSnackbar(context, 'Follow-up removed', context.g.success, Icons.check_circle);
    } catch (_) {
      if (mounted) showSnackbar(context, "Couldn't remove the follow-up. Check your connection and try again.", context.g.warning, Icons.info);
    }
  }

  // ---------------------------------------------------------------------------
  // New interaction — single step
  // ---------------------------------------------------------------------------

  Future<void> _openEntrySheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EntrySheet(
        guideId: _selectedGuide,
        studentUid: widget.studentUid,
        studentName: widget.studentName,
      ),
    );
    if (saved == true && mounted) {
      showSnackbar(
        context,
        "Interaction saved",
        Colors.green,
        Icons.check_circle,
      );
    }
  }

  Future<void> _openDetail(String docId) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InteractionDetailPage(
          docId: docId,
          studentName: widget.studentName,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // List
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: _selectionMode
              ? selectionAppBar(
                  context: context,
                  count: _selectedIds.length,
                  onCancel: _cancelSelectionMode,
                  onDelete: _selectedIds.isEmpty ? null : _deleteSelected,
                )
              : GuideAppBar(title: Text("Interactions")),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: context.g.brass,
            onPressed: _openEntrySheet,
            icon: Icon(Icons.add, color: context.g.onPrimary),
            label: Text(
              "New",
              style: TextStyle(color: context.g.onPrimary),
            ),
          ),
          body: _studentRef == null && !_studentRefFailed
              ? const GuideWait()
              : StreamBuilder<QuerySnapshot>(
                  // studentUid plus the scope filter that proves the viewer may read
                  // this student's logs; sorted in Dart so no composite index is
                  // needed — same approach as AssociationManager.
                  stream: _studentRef == null
                      ? const Stream<QuerySnapshot>.empty()
                      : StudentScope.current()
                          .constrainForStudent(
                              _firestore.collection('interactionLogs').where(
                                  'studentUid',
                                  isEqualTo: widget.studentUid),
                              _studentRef!)
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _studentRef != null) {
                      return const GuideWait();
                    }

                    final docs = snapshot.data?.docs.toList() ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            "No interactions logged yet.\n"
                            "Tap New to record one.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.g.mutedText),
                          ),
                        ),
                      );
                    }

                    docs.sort((a, b) {
                      final da =
                          (a.data() as Map<String, dynamic>)['interactionDate'];
                      final db =
                          (b.data() as Map<String, dynamic>)['interactionDate'];
                      if (da is! Timestamp) return 1;
                      if (db is! Timestamp) return -1;
                      return db.compareTo(da);
                    });

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final data = doc.data() as Map<String, dynamic>;
                        return _logCard(doc.id, data);
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _logCard(String docId, Map<String, dynamic> data) {
    final date = data['interactionDate'];
    final dateText = date is Timestamp
        ? DateFormat('dd MMM yyyy').format(date.toDate())
        : "No date";

    // Legacy fallback: a stray pre-redesign 'draft' record (never approved,
    // never extracted) has neither map populated.
    final source = (data['approvedSummary'] ?? data['extractedDraft'])
        as Map<String, dynamic>?;

    final type = (source?['interactionType'] ?? '').toString();
    final action = (source?['recommendedNextAction'] ?? '').toString();
    final reasoning = (source?['recommendedReasoning'] ?? '').toString();
    final incomplete = source == null;
    final selected = _selectedIds.contains(docId);
    final followUp = _dateFrom(source?['followUpDate']);

    return selectableCard(
      context: context,
      selected: selected,
      selectionMode: _selectionMode,
      onTap: () {
        if (_selectionMode) _toggleSelection(docId);
      },
      onLongPress: () => _enterSelectionMode(docId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.g.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    type.isEmpty ? "Interaction" : type,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (incomplete)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.g.chipBackground,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Incomplete (old)",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.g.mutedText,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.event, size: 13, color: context.g.mutedText),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(
                  dateText,
                  style: TextStyle(fontSize: 12, color: context.g.mutedText),
                ))
              ],
            ),
            if (action.isNotEmpty || reasoning.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.g.brass.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Suggested next action",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .4,
                        color: context.g.brass,
                      ),
                    ),
                    if (action.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      AiText(action, style: const TextStyle(fontSize: 13)),
                    ],
                    if (reasoning.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      AiText(
                        reasoning,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: context.g.mutedText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (followUp != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.event_repeat, size: 15, color: context.g.brass),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Follow-up ${DateFormat('dd MMM yyyy').format(followUp)}',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.g.text),
                    ),
                  ),
                  TextButton(
                    key: ValueKey('follow-up-remove-$docId'),
                    onPressed: _selectionMode ? null : () => _removeFollowUp(docId, followUp),
                    child: const Text('Remove follow-up'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(
                  key: ValueKey('interaction-delete-$docId'),
                  onPressed: _selectionMode ? null : () => _deleteOne(docId),
                  child: Text('Delete interaction', style: TextStyle(color: _selectionMode ? null : context.g.danger)),
                ),
                TextButton(
                  onPressed: () => _openDetail(docId),
                  child: const Text("View / edit"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared helpers
// -----------------------------------------------------------------------------

DateTime? _dateFrom(Object? value) {
  if (value is Timestamp) return value.toDate();
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

// -----------------------------------------------------------------------------
// New interaction — the sheet
// -----------------------------------------------------------------------------

/// The guide types or speaks what was discussed and taps Save. Nothing else is shown or asked:
/// the server analyses the note in the background and makes new suggestions for the student.
///
/// Its own widget, so the text controller lives exactly as long as the sheet's route does. (A
/// controller disposed by the screen that opened the sheet — the moment the sheet's future
/// completes — is disposed while the sheet is still sliding away and still painting the field,
/// which is a red "used after being disposed" error on the phone's back button.)
class _EntrySheet extends StatefulWidget {
  const _EntrySheet({
    required this.guideId,
    required this.studentUid,
    required this.studentName,
  });

  final String guideId;
  final String studentUid;
  final String studentName;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final TextEditingController _controller = TextEditingController();
  DateTime _interactionDate = DateTime.now();
  String? _interactionType;
  DateTime? _followUpDate;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      showSnackbar(
        context,
        "Type what was discussed first",
        Colors.orange,
        Icons.info,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await saveInteraction(
        guideId: widget.guideId,
        studentUid: widget.studentUid,
        studentName: widget.studentName,
        raw: raw,
        interactionType: _interactionType ?? '',
        interactionDate: _interactionDate,
        followUpDate: _followUpDate,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackbar(
        context,
        "Could not save the interaction",
        Colors.red,
        Icons.error,
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, true);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The form scrolls; Save stays pinned below it, so it is always on screen (at a large text size
            // or with the keyboard up it used to sit below the fold of the sheet).
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GuideSheetHeader(
                        title: "Log interaction — ${widget.studentName}"),
                    const SizedBox(height: 14),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.event, color: context.g.brass),
                        title: const Text("Interaction date"),
                        subtitle: Text(
                          DateFormat('dd MMM yyyy').format(_interactionDate),
                        ),
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: _busy
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _interactionDate,
                                  firstDate:
                                      now.subtract(const Duration(days: 365)),
                                  lastDate: now,
                                );
                                if (picked != null && mounted) {
                                  setState(() => _interactionDate = picked);
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _interactionType,
                      decoration: const InputDecoration(
                        labelText: "How did you connect? (optional)",
                      ),
                      items: kInteractionTypes
                          .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _interactionType = v),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            Icon(Icons.event_available, color: context.g.brass),
                        title: const Text("Follow-up date (optional)"),
                        subtitle: Text(
                          _followUpDate == null
                              ? "Not set"
                              : DateFormat('dd MMM yyyy')
                                  .format(_followUpDate!),
                        ),
                        trailing: _followUpDate == null
                            ? const Icon(Icons.edit, size: 18)
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _busy
                                    ? null
                                    : () =>
                                        setState(() => _followUpDate = null),
                              ),
                        onTap: _busy
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _followUpDate ?? now,
                                  firstDate: now,
                                  lastDate: now.add(const Duration(days: 365)),
                                );
                                if (picked != null && mounted) {
                                  setState(() => _followUpDate = picked);
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _controller,
                      enabled: !_busy,
                      maxLines: 9,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText:
                            "e.g. Met Ravi after the evening program. He is "
                            "struggling to chant during exam week...",
                      ),
                    ),
                    // Speak it instead: English, Hindi, Gujarati or a mix, turned into clean
                    // English and added below whatever is already here. It lands in the box
                    // above, editable, before anything is saved.
                    VoiceNoteButton(
                      purpose: VoicePurpose.interaction,
                      studentName: widget.studentName,
                      enabled: !_busy,
                      existingText: () => _controller.text,
                      onText: (clean) => revealAppend(_controller, clean,
                          animate: !(MediaQuery.maybeDisableAnimationsOf(context) ?? false),
                          done: () {
                            if (mounted) setState(() {});
                          }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(width: 18, height: 18, child: GuideBusyDot()),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text("Saving…", style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text("Save"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.g.brass,
                    foregroundColor: context.g.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// View / edit a saved interaction
// -----------------------------------------------------------------------------

class InteractionDetailPage extends StatefulWidget {
  final String docId;
  final String studentName;

  const InteractionDetailPage({
    super.key,
    required this.docId,
    required this.studentName,
  });

  @override
  State<InteractionDetailPage> createState() => _InteractionDetailPageState();
}

class _InteractionDetailPageState extends State<InteractionDetailPage> {
  final FirebaseFirestore _firestore = GuideDb.instance;

  /// One controller per free-text field. `interactionType` is handled by a
  /// dedicated dropdown below, not a text controller.
  final Map<String, TextEditingController> _controllers = {};

  DateTime? _interactionDateTime;
  DateTime? _followUpDate;
  String? _interactionType;
  String _confidence = 'low';

  bool _loading = true;
  bool _saving = false;
  bool _extracting = false;
  String _rawDictation = '';

  static const List<List<String>> _textFields = [
    ['durationMinutes', 'Duration (minutes)'],
    ['themes', 'Themes (comma separated)'],
    ['studentConcerns', 'Student concerns'],
    ['personalRevelation', 'Personal revelation / relationship depth'],
    ['commitmentsMade', 'Commitments made'],
    ['abcdeEvidence', 'ABCDE evidence'],
    ['possibleLitEvidence', 'Possible LIT evidence (notes only, no score)'],
    ['temporaryCircumstances', 'Temporary circumstances'],
    ['recommendedNextAction', 'Recommended next action'],
    ['recommendedReasoning', 'Reasoning'],
  ];

  @override
  void initState() {
    super.initState();
    for (final field in _textFields) {
      _controllers[field[0]] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await _firestore
          .collection('interactionLogs')
          .doc(widget.docId)
          .get();

      final data = snap.data() ?? {};
      _rawDictation = (data['rawDictation'] ?? '').toString();

      // Legacy fallback: a stray pre-redesign 'draft' record only ever had
      // extractedDraft populated.
      final source = (data['approvedSummary'] ?? data['extractedDraft'])
              as Map<String, dynamic>? ??
          {};

      _fill(source);
    } catch (_) {
      if (mounted) {
        showSnackbar(
            context, "Could not load the interaction", Colors.red, Icons.error);
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  void _fill(Map<String, dynamic> source) {
    for (final field in _textFields) {
      final key = field[0];
      final value = source[key];
      if (key == 'themes' && value is List) {
        _controllers[key]!.text = value.join(', ');
      } else if (key == 'durationMinutes') {
        final n = value is num ? value.toInt() : 0;
        _controllers[key]!.text = n == 0 ? '' : n.toString();
      } else {
        _controllers[key]!.text = plainAiText((value ?? '').toString());
      }
    }

    _interactionDateTime = _dateFrom(source['interactionDateTime']);
    _followUpDate = _dateFrom(source['followUpDate']);

    final type = (source['interactionType'] ?? '').toString().trim();
    _interactionType = type.isEmpty ? null : type;

    final conf = (source['extractionConfidence'] ?? 'low').toString();
    _confidence = ['low', 'medium', 'high'].contains(conf) ? conf : 'low';
  }

  /// Dropdown options: the three canonical types, plus the current value if
  /// it's a legacy free-text type that predates this redesign — so an old
  /// record is never silently changed just by opening it.
  List<String> _typeOptions() {
    final opts = List<String>.from(kInteractionTypes);
    final current = _interactionType;
    if (current != null && current.isNotEmpty && !opts.contains(current)) {
      opts.insert(0, current);
    }
    return opts;
  }

  /// The current editor state, in the in-memory (ISO string) shape.
  Map<String, dynamic> _currentSummary() {
    final themes = _controllers['themes']!
        .text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return {
      'interactionType': _interactionType ?? '',
      'interactionDateTime': _interactionDateTime?.toIso8601String() ?? '',
      'durationMinutes':
          int.tryParse(_controllers['durationMinutes']!.text.trim()) ?? 0,
      'themes': themes,
      'studentConcerns': _controllers['studentConcerns']!.text.trim(),
      'personalRevelation': _controllers['personalRevelation']!.text.trim(),
      'commitmentsMade': _controllers['commitmentsMade']!.text.trim(),
      'followUpDate': _followUpDate?.toIso8601String() ?? '',
      'abcdeEvidence': _controllers['abcdeEvidence']!.text.trim(),
      'possibleLitEvidence': _controllers['possibleLitEvidence']!.text.trim(),
      'temporaryCircumstances':
          _controllers['temporaryCircumstances']!.text.trim(),
      'recommendedNextAction':
          _controllers['recommendedNextAction']!.text.trim(),
      'recommendedReasoning': _controllers['recommendedReasoning']!.text.trim(),
      'extractionConfidence': _confidence,
    };
  }

  /// Saves guide corrections in place. Always writes `status: 'approved'` —
  /// a no-op for an already-complete record, and the natural way a stray
  /// legacy 'draft' record (see `_load`'s fallback) gets finalized if a guide
  /// ever opens and saves one.
  Future<void> _saveChanges() async {
    setState(() => _saving = true);
    try {
      await saveInteractionEdits(
        widget.docId,
        summary: _currentSummary(),
        interactionDate: _interactionDateTime,
      );
      if (!mounted) return;
      showSnackbar(context, "Saved", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not save", Colors.red, Icons.error);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _reExtract() async {
    if (_rawDictation.trim().isEmpty) {
      showSnackbar(
        context,
        "The original notes are no longer stored for this log",
        Colors.orange,
        Icons.info,
      );
      return;
    }

    setState(() => _extracting = true);

    try {
      // The server reads the notes again and saves the result; the guide's own choices (how
      // they connected, when, the follow-up date) stay authoritative over the AI's guesses.
      await reExtractInteraction(widget.docId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showSnackbar(context, "Re-extracted", Colors.green, Icons.check_circle);
    } on AiException catch (e) {
      if (mounted) {
        showSnackbar(context, e.message, Colors.red, Icons.error);
      }
    } catch (e) {
      if (mounted) {
        showSnackbar(context, "Extraction failed: $e", Colors.red, Icons.error);
      }
    }

    if (mounted) setState(() => _extracting = false);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar:
              GuideAppBar(title: Text("Interaction — ${widget.studentName}")),
          body: _loading
              ? const GuideWait()
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _dateTile(
                              label: "When it happened",
                              value: _interactionDateTime,
                              format: 'dd MMM yyyy',
                              onPick: () => _pickDate(
                                current: _interactionDateTime,
                                past: true,
                                onPicked: (d) =>
                                    setState(() => _interactionDateTime = d),
                              ),
                            ),
                            const Divider(height: 18),
                            _dateTile(
                              label: "Follow-up date",
                              value: _followUpDate,
                              format: 'dd MMM yyyy',
                              onPick: () => _pickDate(
                                current: _followUpDate,
                                past: false,
                                onPicked: (d) =>
                                    setState(() => _followUpDate = d),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _card(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _interactionType,
                          decoration: const InputDecoration(
                            labelText: "How did you connect?",
                            border: InputBorder.none,
                          ),
                          items: _typeOptions()
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _interactionType = v),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ..._textFields.map((field) {
                        final key = field[0];
                        final multiline =
                            key != 'durationMinutes' && key != 'themes';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _card(
                            child: TextField(
                              controller: _controllers[key],
                              maxLines: multiline ? null : 1,
                              minLines: multiline ? 2 : 1,
                              keyboardType: key == 'durationMinutes'
                                  ? TextInputType.number
                                  : TextInputType.multiline,
                              decoration: InputDecoration(
                                labelText: field[1],
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        );
                      }),
                      _card(
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                "Extraction confidence",
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                            DropdownButton<String>(
                              value: _confidence,
                              underline: const SizedBox(),
                              onChanged: (v) =>
                                  setState(() => _confidence = v ?? 'low'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'low', child: Text("Low")),
                                DropdownMenuItem(
                                    value: 'medium', child: Text("Medium")),
                                DropdownMenuItem(
                                    value: 'high', child: Text("High")),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _actions(),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? value,
    required String format,
    required VoidCallback onPick,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.event, color: context.g.brass),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          value == null ? "Not set" : DateFormat(format).format(value),
          style: TextStyle(
            fontSize: 13,
            color: value == null ? context.g.mutedText : context.g.text,
          ),
        ),
        trailing: const Icon(Icons.edit, size: 18),
        onTap: onPick,
      ),
    );
  }

  Future<void> _pickDate({
    required DateTime? current,
    required bool past,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: past ? now.subtract(const Duration(days: 365)) : now,
      lastDate: past ? now : now.add(const Duration(days: 365)),
    );
    if (picked != null) onPicked(picked);
  }

  /// Deletes this interaction, after asking, if the guide may manage this student (the same check as the list).
  Future<void> _deleteThis() async {
    final snap = await _firestore.collection('interactionLogs').doc(widget.docId).get();
    final uid = (snap.data()?['studentUid'] ?? '').toString();
    final userDoc = uid.isEmpty ? null : await _firestore.collection('users').doc(uid).get();
    final ref = userDoc == null ? null : StudentRef.fromDoc(userDoc);
    if (!mounted) return;
    final deleted = await confirmAndDeleteSelected(
      context: context,
      collectionName: 'interactionLogs',
      selectedIds: {widget.docId},
      canDelete: (_) async => canDeleteForStudent(ref, AdminProfileProvider.require()),
      itemNounSingular: 'interaction log',
      itemNounPlural: 'interaction logs',
    );
    if (mounted && deleted.contains(widget.docId)) Navigator.pop(context);
  }

  Widget _actions() {
    if (_saving || _extracting) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: GuideBusyDot(),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            key: const ValueKey('interaction-detail-delete'),
            onPressed: _deleteThis,
            icon: Icon(Icons.delete_outline, size: 18, color: context.g.danger),
            label: Text('Delete interaction', style: TextStyle(color: context.g.danger)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _reExtract,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text("Re-extract from original notes"),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saveChanges,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text("Save changes"),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.g.success,
              foregroundColor: context.g.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
