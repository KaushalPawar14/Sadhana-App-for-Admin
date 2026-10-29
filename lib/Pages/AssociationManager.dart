import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/SeenMarkers.dart';
import '../utils/SelectableDelete.dart';
import '../actions/AssociationActions.dart';
import '../actions/DeleteActions.dart';
import '../utils/Snackbar.dart';
import '../utils/VoiceNote.dart';
import '../widgets/VoiceNoteButton.dart';
import '../utils/StudentScope.dart';
import '../utils/GuideNotes.dart';
import 'InteractionLogger.dart';
import 'OverdueAssociations.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/AiText.dart';
import '../widgets/GuideWait.dart';
import '../widgets/GuideSheet.dart';

/// Association — meeting requests raised by students.
///
/// Firestore: `associations`, scoped to the students the signed-in admin may
/// see (`StudentScope.historyStream`). Student pushes go through the
/// `sendStudentNotification` callable (the server owns the FCM tokens).
class AssociationManagerPage extends StatefulWidget {
  /// Optional deep link. When a caller passes an `associations` doc id, the
  /// screen opens on the tab that record lives in instead of the default one.
  /// Null for every ordinary entry point, which behave exactly as before.
  final String? highlightAssociationId;

  const AssociationManagerPage({super.key, this.highlightAssociationId});

  @override
  State<AssociationManagerPage> createState() => _AssociationManagerPageState();
}

class _AssociationManagerPageState extends State<AssociationManagerPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = GuideDb.instance;

  String? _selectedGuide;

  /// HOD and Guide tabs mix several admins' records together. Cards add a
  /// guide label in this mode so mixed records stay attributable.
  bool get _showsGuideLabel {
    final p = AdminProfileProvider.current;
    return p != null && (p.isHod || p.isGuide);
  }

  /// An explicit controller (rather than DefaultTabController) so the FAB can
  /// react to tab changes — reading the inherited controller does not rebuild.
  late final TabController _tabController;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  /// The guide's notes on meetings (`associationGuideNotes`: guide-only, never on the record the student reads), by association id.
  Map<String, String> _guideNotes = const {};
  StreamSubscription<Map<String, String>>? _notesSub;

  @override
  void initState() {
    super.initState();
    _notesSub = guideNotesStream().listen((m) {
      if (mounted) setState(() => _guideNotes = m);
    }, onError: (_) {});
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _loadGuide();

    final target = widget.highlightAssociationId;
    if (target != null && target.isNotEmpty) {
      _openTabFor(target);
    }
  }

  @override
  void dispose() {
    _notesSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  /// Deep-link support: jump to the tab the given record lives on.
  ///
  /// Purely additive — only ever called when a caller supplied an id, so the
  /// default tab and every existing entry point are untouched. A single doc
  /// read, not a change to `_guideStream` or either tab builder.
  Future<void> _openTabFor(String associationId) async {
    try {
      final doc = await _firestore
          .collection('associations')
          .doc(associationId)
          .get();

      final status = (doc.data()?['status'] ?? '').toString();
      if (!mounted || status.isEmpty) return;

      // Pending sits on tab 0; confirmed, completed and cancelled on tab 1.
      _tabController.animateTo(status == 'pending' ? 0 : 1);
    } catch (_) {
      // A deep link is a convenience. If it fails, the default tab stands.
    }
  }

  Future<void> _loadGuide() async {
    final guide = AdminProfileProvider.current?.id;
    if (mounted) setState(() => _selectedGuide = guide);
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // the associations feature (a short list of records, not individually
    // tracked). Fire-and-forget: a failed write here just means the badge
    // on the ABCDE hub tile stays lit a little longer, never a user-facing
    // error.
    if (guide != null && guide.isNotEmpty) {
      SeenMarkers.markSeen(guide, 'associations');
    }
  }


  /// Which admin a record belongs to — shown **only** where the tabs mix
  /// several admins together (HOD, Guide). For everyone else this returns an
  /// empty box, so their card layout is exactly what it was before.
  Widget _guideLabel(Map<String, dynamic> data) {
    if (!_showsGuideLabel) return const SizedBox.shrink();

    // The current owner is the server-stamped `scopeGuide`; records written
    // before the stamp existed fall back to the historic `guideId`.
    final guideId = (data['scopeGuide'] ?? data['guideId'] ?? '').toString();
    if (guideId.isEmpty) return const SizedBox.shrink();
    final label =
        AdminProfileProvider.current?.adminById(guideId)?.displayName ??
            guideId;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.person_pin, size: 13, color: context.g.mutedText),
          const SizedBox(width: 4),
          Flexible(child: Text(
            "Guide: $label",
            style: TextStyle(fontSize: 11, color: context.g.mutedText),
          ))],
      ),
    );
  }

  String _formatTs(dynamic value) {
    if (value is! Timestamp) return "Date not set";
    return DateFormat('dd MMM yyyy, hh:mm a').format(value.toDate());
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _confirmRequest(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final preferred = data['preferredDate'];
    final initial =
        preferred is Timestamp ? preferred.toDate() : DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime.now()) ? DateTime.now() : initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    final confirmed = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    try {
      await confirmMeeting(
        docId,
        studentUid: (data['studentUid'] ?? '').toString(),
        when: confirmed,
      );

      if (!mounted) return;
      showSnackbar(context, "Meeting confirmed", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not confirm", Colors.red, Icons.error);
    }
  }

  /// Moves a confirmed meeting to another day and time, and tells the student.
  ///
  /// Added with the AI agent, which may only do what a guide can do by hand: the
  /// app could confirm a request and cancel a meeting but not move one, so the
  /// Upcoming card gained this, on the same shared write the agent uses.
  Future<void> _rescheduleMeeting(String docId, Map<String, dynamic> data) async {
    final current = data['confirmedDate'];
    final initial = current is Timestamp ? current.toDate() : DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime.now()) ? DateTime.now() : initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    final moved = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    try {
      await rescheduleMeeting(
        docId,
        studentUid: (data['studentUid'] ?? '').toString(),
        when: moved,
      );
      if (!mounted) return;
      showSnackbar(context, "Meeting rescheduled", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not reschedule", Colors.red, Icons.error);
    }
  }

  Future<void> _cancelRequest(String docId, Map<String, dynamic> data) async {
    try {
      await cancelMeeting(
        docId,
        studentUid: (data['studentUid'] ?? '').toString(),
      );

      if (!mounted) return;
      showSnackbar(context, "Meeting cancelled", Colors.orange, Icons.cancel);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not cancel", Colors.red, Icons.error);
    }
  }

  Future<void> _markComplete(String docId, Map<String, dynamic> data) async {
    String notes = _guideNotes[docId] ?? await guideNoteOf(docId);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return GuideDialog(
            title: const Text("Complete Meeting"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data['studentName'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                _MeetingNotesField(
                  initialText: notes,
                  studentName: (data['studentName'] ?? '').toString(),
                  onChanged: (v) => notes = v,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: context.g.brass),
                onPressed: () => Navigator.pop(dialogContext, true),
                child:
                    Text("Save", style: TextStyle(color: context.g.onPrimary)),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;

    try {
      await completeMeeting(docId, notes: notes);

      if (!mounted) return;
      showSnackbar(context, "Meeting completed", Colors.blue, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not save", Colors.red, Icons.error);
    }
  }

  // ---------------------------------------------------------------------------
  // Guide-initiated meeting
  // ---------------------------------------------------------------------------

  // There is no add-interaction button here any more: interactions are recorded only by telling the assistant what happened (typed or dictated
  // in the chat), which saves the same `interactionLogs` record with a confirmation. The history below, and deleting an interaction, stay.

  Future<void> _openCreateMeetingSheet(String guide) async {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> students;

    try {
      final snap = await StudentScope.current().studentsGet();
      students = snap.docs.toList()
        ..sort((a, b) => (a.data()['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b.data()['name'] ?? '').toString().toLowerCase()));
    } catch (_) {
      if (mounted) {
        showSnackbar(context, "Could not load students", Colors.red, Icons.error);
      }
      return;
    }

    if (!mounted) return;

    if (students.isEmpty) {
      showSnackbar(
        context,
        "No students assigned to "
        "${AdminProfileProvider.current?.adminById(guide)?.displayName ?? guide} yet",
        Colors.orange,
        Icons.info,
      );
      return;
    }

    String? studentUid;
    DateTime? pickedDate;
    TimeOfDay? pickedTime;
    String notes = '';
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              if (studentUid == null ||
                  pickedDate == null ||
                  pickedTime == null) {
                showSnackbar(
                  sheetContext,
                  "Pick a student, date and time",
                  Colors.red,
                  Icons.error,
                );
                return;
              }

              setSheetState(() => saving = true);

              final student = students.firstWhere((d) => d.id == studentUid);
              final studentName =
                  (student.data()['name'] ?? '')
                      .toString();

              final preferred = DateTime(
                pickedDate!.year,
                pickedDate!.month,
                pickedDate!.day,
                pickedTime!.hour,
                pickedTime!.minute,
              );

              try {
                await requestMeeting(
                  guideId: guide,
                  studentUid: studentUid!,
                  studentName: studentName,
                  preferred: preferred,
                  message: notes,
                );

                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);

                if (!mounted) return;
                showSnackbar(
                  context,
                  "Meeting requested with $studentName",
                  Colors.green,
                  Icons.check_circle,
                );
              } catch (_) {
                setSheetState(() => saving = false);
                if (!sheetContext.mounted) return;
                showSnackbar(
                  sheetContext,
                  "Could not create meeting",
                  Colors.red,
                  Icons.error,
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                decoration: BoxDecoration(
                  color: context.g.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GuideSheetHeader(title: "Request a Meeting"),
                    const SizedBox(height: 20),

                    DropdownButtonFormField<String>(
                      value: studentUid,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: "Student",
                      ),
                      items: students.map((doc) {
                        final name =
                            (doc.data()['name'] ??
                                    'Unknown')
                                .toString();
                        return DropdownMenuItem(
                          value: doc.id,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (v) => setSheetState(() => studentUid = v),
                    ),

                    const SizedBox(height: 14),

                    _sheetPickerRow(
                      icon: Icons.calendar_today,
                      label: "Preferred date",
                      value: pickedDate == null
                          ? "Not set"
                          : DateFormat('dd MMM yyyy').format(pickedDate!),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: now,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setSheetState(() => pickedDate = picked);
                        }
                      },
                    ),

                    const SizedBox(height: 10),

                    _sheetPickerRow(
                      icon: Icons.access_time,
                      label: "Preferred time",
                      value: pickedTime == null
                          ? "Not set"
                          : pickedTime!.format(sheetContext),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: sheetContext,
                          initialTime: TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => pickedTime = picked);
                        }
                      },
                    ),

                    const SizedBox(height: 14),

                    TextFormField(
                      maxLines: 3,
                      onChanged: (v) => notes = v,
                      decoration: InputDecoration(
                        labelText: "Message (optional)",
                        alignLabelWithHint: true,
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: saving ? null : save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.g.brass,
                        ),
                        child: saving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: const GuideBusyDot(),
                              )
                            : Text(
                                "Send Request",
                                style: TextStyle(
                                  color: context.g.surface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetPickerRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: context.g.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.g.mutedText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color:
                    value == "Not set" ? context.g.mutedText : context.g.text,
                fontWeight:
                    value == "Not set" ? FontWeight.normal : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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

  /// Matches this screen's own read-access model: the server-stamped scope
  /// fields that `_guideStream` reads decide delete permission too — HOD may
  /// delete anything, everyone else only a record about a student they may
  /// manage (`StudentScope.canManage`). A record not yet stamped falls back to
  /// its own `guideId` being the signed-in admin.
  Future<bool> _canDeleteAssociation(Map<String, dynamic> data) async {
    return canDeleteStamped(data, AdminProfileProvider.require());
  }

  Future<void> _deleteSelected() async {
    final deleted = await confirmAndDeleteSelected(
      context: context,
      collectionName: 'associations',
      selectedIds: _selectedIds,
      canDelete: _canDeleteAssociation,
      itemNounSingular: 'association',
      itemNounPlural: 'associations',
    );
    if (!mounted) return;
    setState(() {
      _selectedIds.removeAll(deleted);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------------

  Widget _shell({required String docId, required Widget child}) {
    final selected = _selectedIds.contains(docId);

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
          boxShadow: context.g.cardShadow,
        ),
        child: child,
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _cancelButton(String docId, Map<String, dynamic> data) {
    return OutlinedButton(
      onPressed: () => _cancelRequest(docId, data),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.g.danger,
        side: BorderSide(color: context.g.danger),
      ),
      child: const Text("Cancel"),
    );
  }

  Widget _pendingCard(String docId, Map<String, dynamic> data) {
    final studentNotes = (data['studentNotes'] ?? '').toString();
    final requestedBy = (data['requestedBy'] ?? '').toString();

    final isCounter = data['isCounterProposal'] == true;
    final counterNote = (data['counterProposalNote'] ?? '').toString();
    final counterDate = data['counterProposalDate'];

    return _shell(
      docId: docId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (data['studentName'] ?? 'Unknown').toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (isCounter)
                _badge("Counter-proposal", context.g.brass)
              else if (requestedBy == 'guide')
                _badge("Awaiting student confirmation", context.g.warning),
            ],
          ),
          _guideLabel(data),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event, size: 15, color: context.g.mutedText),
              const SizedBox(width: 5),
              Flexible(child: Text(
                "Preferred: ${_formatTs(data['preferredDate'])}",
                style: TextStyle(fontSize: 12, color: context.g.mutedText),
              ))],
          ),
          if (studentNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              studentNotes,
              style: TextStyle(fontSize: 12, color: context.g.mutedText),
            ),
          ],

          /// What the student proposed instead.
          if (isCounter) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.g.brass.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Student proposed: ${_formatTs(counterDate)}",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.g.brass,
                    ),
                  ),
                  if (counterNote.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      counterNote,
                      style:
                          TextStyle(fontSize: 12, color: context.g.mutedText),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          if (isCounter) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _acceptCounterProposal(docId, data),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: context.g.success,
                ),
                child: Text(
                  "Accept Student's Date",
                  style: TextStyle(color: context.g.onPrimary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmRequest(docId, data),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.g.brass,
                      side: BorderSide(color: context.g.brass),
                    ),
                    child: const Text(
                      "Set My Own Date",
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _cancelButton(docId, data)),
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _confirmRequest(docId, data),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: context.g.success,
                    ),
                    child: Text(
                      "Confirm",
                      style: TextStyle(color: context.g.onPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _cancelButton(docId, data)),
              ],
            ),
        ],
      ),
    );
  }

  /// Accepts the student's proposed slot as-is.
  Future<void> _acceptCounterProposal(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final proposed = data['counterProposalDate'];

    if (proposed is! Timestamp) {
      showSnackbar(context, "No proposed date found", Colors.red, Icons.error);
      return;
    }

    try {
      await acceptStudentProposal(
        docId,
        studentUid: (data['studentUid'] ?? '').toString(),
        proposed: proposed,
      );

      if (!mounted) return;
      showSnackbar(
        context,
        "Meeting confirmed",
        Colors.green,
        Icons.check_circle,
      );
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not confirm", Colors.red, Icons.error);
    }
  }

  Widget _upcomingCard(String docId, Map<String, dynamic> data) {
    return _shell(
      docId: docId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (data['studentName'] ?? 'Unknown').toString(),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          _guideLabel(data),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event_available, size: 15, color: context.g.success),
              const SizedBox(width: 5),
              Flexible(child: Text(
                _formatTs(data['confirmedDate']),
                style: TextStyle(fontSize: 12, color: context.g.success),
              ))],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _markComplete(docId, data),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: context.g.brass,
                  ),
                  child: Text(
                    "Mark Complete",
                    style: TextStyle(color: context.g.onPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _cancelRequest(docId, data),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.g.danger,
                    side: BorderSide(color: context.g.danger),
                  ),
                  child: const Text("Cancel"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: ValueKey('reschedule-$docId'),
              onPressed: () => _rescheduleMeeting(docId, data),
              icon: const Icon(Icons.edit_calendar, size: 18),
              label: const Text("Reschedule"),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.g.brass,
                side: BorderSide(color: context.g.brass),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(String docId, Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString();
    final isCompleted = status == 'completed';
    final guideNotes = _guideNotes[docId] ?? '';

    return _shell(
      docId: docId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (data['studentName'] ?? 'Unknown').toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isCompleted ? context.g.brass : context.g.danger)
                      .withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isCompleted ? "Completed" : "Cancelled",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isCompleted ? context.g.brass : context.g.danger,
                  ),
                ),
              ),
            ],
          ),
          _guideLabel(data),
          const SizedBox(height: 8),
          Text(
            _formatTs(data['confirmedDate'] ?? data['preferredDate']),
            style: TextStyle(fontSize: 12, color: context.g.mutedText),
          ),
          if (guideNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.g.brass.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                guideNotes,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tabs
  // ---------------------------------------------------------------------------

  /// One query per tab. Status is matched in Dart because a second equality
  /// filter would require a composite index.
  ///
  /// The HOD sees every record; everyone else the records about students
  /// they may see (server-stamped `scope*` fields, merged client-side).
  Stream<QuerySnapshot> _guideStream(String guide) =>
      StudentScope.current().historyStream('associations');

  Widget _buildPending(String guide) {
    return StreamBuilder<QuerySnapshot>(
      stream: _guideStream(guide),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GuideWait();
        }

        final docs = (snapshot.data?.docs ?? [])
            .where((d) =>
                ((d.data() as Map<String, dynamic>)['status'] ?? '') ==
                'pending')
            .toList();

        if (docs.isEmpty) {
          return const Center(child: Text("No pending requests"));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: docs
              .map((d) => _pendingCard(d.id, d.data() as Map<String, dynamic>))
              .toList(),
        );
      },
    );
  }

  Widget _buildUpcomingAndHistory(String guide) {
    return StreamBuilder<QuerySnapshot>(
      stream: _guideStream(guide),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GuideWait();
        }

        final all = snapshot.data?.docs ?? [];

        final upcoming = all
            .where((d) =>
                ((d.data() as Map<String, dynamic>)['status'] ?? '') ==
                'confirmed')
            .toList()
          ..sort((a, b) {
            final aDate = (a.data() as Map<String, dynamic>)['confirmedDate'];
            final bDate = (b.data() as Map<String, dynamic>)['confirmedDate'];
            if (aDate is! Timestamp || bDate is! Timestamp) return 0;
            return aDate.compareTo(bDate); // soonest first
          });

        final history = all.where((d) {
          final status = ((d.data() as Map<String, dynamic>)['status'] ?? '');
          return status == 'completed' || status == 'cancelled';
        }).toList();

        // No early return when there are no meetings: a student can have
        // interaction notes and no meetings at all, and those still belong on
        // this tab. The empty case is handled inside the list instead.
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (upcoming.isNotEmpty) ...[
              const Text(
                "Upcoming",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...upcoming.map(
                (d) => _upcomingCard(d.id, d.data() as Map<String, dynamic>),
              ),
              const SizedBox(height: 20),
            ],
            if (history.isNotEmpty) ...[
              const Text(
                "History",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...history
                  .map((d) =>
                      _historyCard(d.id, d.data() as Map<String, dynamic>)),
            ],
            // Interactions live here too now — the guide's own notes, in the
            // same place as everything else that happened with a student.
            _interactionsSection(
              nothingElseHere: upcoming.isEmpty && history.isEmpty,
            ),
          ],
        );
      },
    );
  }

  /// The interaction notes this admin may see, newest first, under their own
  /// heading in the history tab. Read straight from `interactionLogs` through
  /// the same scope stream every other history collection uses, so an admin
  /// sees exactly the notes about the students they may see.
  /// [nothingElseHere] is true when the tab has no meetings at all, so this
  /// section owns the "nothing yet" message instead of the caller.
  Widget _interactionsSection({bool nothingElseHere = false}) {
    return StreamBuilder<QuerySnapshot>(
      stream: StudentScope.current().historyStream('interactionLogs'),
      builder: (context, snapshot) {
        final docs = (snapshot.data?.docs ?? []).toList()
          ..sort((a, b) {
            final ad = _interactionWhen(a.data() as Map<String, dynamic>);
            final bd = _interactionWhen(b.data() as Map<String, dynamic>);
            if (ad == null || bd == null) return 0;
            return bd.compareTo(ad); // newest first
          });
        if (docs.isEmpty) {
          return nothingElseHere
              ? const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: Text("Nothing here yet")),
                )
              : const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              "Interactions (${docs.length})",
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final d in docs)
              _interactionCard(d.id, d.data() as Map<String, dynamic>),
          ],
        );
      },
    );
  }

  /// When an interaction happened: its own `interactionDate`, falling back to
  /// `createdAt`. Older records carry only the latter, so sorting and the date
  /// line must not depend on `interactionDate` being there.
  static DateTime? _interactionWhen(Map<String, dynamic> data) {
    for (final key in ['interactionDate', 'createdAt']) {
      final v = data[key];
      if (v is Timestamp) return v.toDate();
    }
    return null;
  }

  /// One interaction note. Tapping it opens the SAME detail page the
  /// Interactions list always used, so editing and deleting are unchanged.
  Widget _interactionCard(String docId, Map<String, dynamic> data) {
    final g = context.g;
    final when = _interactionWhen(data);
    // `approvedSummary` is a MAP (the same one `InteractionLogger._logCard`
    // reads), never a string — `.toString()` on it would print the raw map.
    // The fallback to `extractedDraft` is that card's too: a stray
    // pre-redesign record has neither populated.
    final source = (data['approvedSummary'] ?? data['extractedDraft'])
        as Map<String, dynamic>?;
    final action = (source?['recommendedNextAction'] ?? '').toString().trim();
    final dictation = (data['rawDictation'] ?? '').toString().trim();
    final body = action.isNotEmpty ? action : dictation;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.record_voice_over, color: g.brass),
        title: Text((data['studentName'] ?? '').toString()),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (when != null)
              Text(DateFormat('dd MMM yyyy').format(when),
                  style: context.gText.caption),
            if (body.isNotEmpty)
              AiText(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InteractionDetailPage(
              docId: docId,
              studentName: (data['studentName'] ?? '').toString(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        final guide = _selectedGuide;

        final tabBar = TabBar(
          controller: _tabController,
          labelColor: context.g.brass,
          unselectedLabelColor: context.g.mutedText,
          indicatorColor: context.g.brass,
          tabs: const [
            Tab(text: "Pending"),
            Tab(text: "Upcoming & History"),
          ],
        );

        return GuideScaffold(
          appBar: _selectionMode
              ? selectionAppBar(
                  context: context,
                  count: _selectedIds.length,
                  onCancel: _cancelSelectionMode,
                  onDelete: _selectedIds.isEmpty ? null : _deleteSelected,
                  bottom: tabBar,
                )
              : GuideAppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Association",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 20,
              ),
            ),
            // Overview — the overdue-associations dashboard, nested here on
            // 2026-08-14 when its own Admin Hub tile was removed. The screen
            // it opens is unchanged.
            //
            // An AppBar action rather than a body button: the body is a
            // `TabBarView`, so anything placed "near the top of the body"
            // would live inside one tab and be missing from the other, or be
            // duplicated across both — wrong either way for a view that spans
            // both. The FAB is already taken and is tab-conditional. This
            // matches how Submission Status was added to the User Dashboard's
            // app bar.
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const OverdueAssociationsPage(),
                    transitionsBuilder: (_, animation, __, child) =>
                        FadeTransition(opacity: animation, child: child),
                  ),
                ),
                icon: Icon(Icons.event_busy,
                    size: 18, color: colorProvider.secondColor),
                label: Text(
                  "Overdue",
                  style: TextStyle(
                    color: colorProvider.secondColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
            bottom: tabBar),
          body: guide == null
              ? const GuideWait()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPending(guide),
                    _buildUpcomingAndHistory(guide),
                  ],
                ),
          // Creating a MEETING only belongs on the pending tab. (Interactions are recorded through the assistant: no button here.)
          floatingActionButton: guide == null || _tabController.index != 0
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'newMeeting',
                  backgroundColor: context.g.brass,
                  onPressed: () => _openCreateMeetingSheet(guide),
                  icon: Icon(Icons.add, color: context.g.onPrimary),
                  label: Text(
                    "New Meeting",
                    style: TextStyle(color: context.g.onPrimary),
                  ),
                ),
        );
      },
    );
  }
}

/// The notes box of "Complete Meeting", with the mic under it.
///
/// A widget of its own so that it owns its controller. The controller used to be
/// created before the dialog opened and disposed the moment it closed — which is
/// while the dialog's exit animation is still painting this very field, and
/// Flutter rightly objects to a disposed controller being used. A widget disposes
/// its controller when it is actually removed from the tree, not before.
class _MeetingNotesField extends StatefulWidget {
  const _MeetingNotesField({
    required this.initialText,
    required this.studentName,
    required this.onChanged,
  });

  final String initialText;
  final String studentName;
  final ValueChanged<String> onChanged;

  @override
  State<_MeetingNotesField> createState() => _MeetingNotesFieldState();
}

class _MeetingNotesFieldState extends State<_MeetingNotesField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _controller,
          autofocus: true,
          maxLines: 4,
          onChanged: widget.onChanged,
          decoration: const InputDecoration(
            labelText: "Notes from the meeting",
            alignLabelWithHint: true,
          ),
        ),
        // Speak it instead: English, Hindi, Gujarati or a mix, turned into clean
        // English and added after whatever is already here — editable before Save.
        VoiceNoteButton(
          purpose: VoicePurpose.associationNote,
          studentName: widget.studentName,
          existingText: () => _controller.text,
          onText: (clean) {
            revealAppend(_controller, clean,
                animate: !(MediaQuery.maybeDisableAnimationsOf(context) ?? false),
                done: () => widget.onChanged(_controller.text));
          },
        ),
      ],
    );
  }
}
