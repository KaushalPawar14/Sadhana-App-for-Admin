import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/SeenMarkers.dart';
import '../actions/AssociationActions.dart';
import '../utils/Snackbar.dart';
import '../utils/VoiceNote.dart';
import '../widgets/VoiceNoteButton.dart';
import '../utils/StudentScope.dart';
import '../utils/GuideNotes.dart';
import 'OverdueAssociations.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/RecordInteractionDialog.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';
import '../widgets/GuideSheet.dart';
import '../utils/Responsive.dart';
import '../widgets/PlanBlocks.dart';

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

class _AssociationManagerPageState extends State<AssociationManagerPage> {
  final FirebaseFirestore _firestore = GuideDb.instance;

  String? _selectedGuide;

  /// HOD and Guide tabs mix several admins' records together. Cards add a
  /// guide label in this mode so mixed records stay attributable.
  bool get _showsGuideLabel {
    final p = AdminProfileProvider.current;
    return p != null && (p.isHod || p.isGuide);
  }

  /// The three sections (Pending, Confirmed, Completed) are open to begin with; a tap on a header collapses one.
  final Set<String> _closed = {};

  /// The record a notification or a Today button pointed at: its section is open and the card is outlined.
  String? _highlightId;

  /// The guide's notes on meetings (`associationGuideNotes`: guide-only, never on the record the student reads), by association id.
  Map<String, String> _guideNotes = const {};
  StreamSubscription<Map<String, String>>? _notesSub;

  @override
  void initState() {
    super.initState();
    _notesSub = guideNotesStream().listen((m) {
      if (mounted) setState(() => _guideNotes = m);
    }, onError: (_) {});
    _loadGuide();

    final target = widget.highlightAssociationId;
    if (target != null && target.isNotEmpty) {
      _openTabFor(target);
    }
  }

  @override
  void dispose() {
    _notesSub?.cancel();
    super.dispose();
  }

  /// Deep-link support: open the section the given record lives on and outline its card.
  Future<void> _openTabFor(String associationId) async {
    try {
      final doc = await _firestore.collection('associations').doc(associationId).get();
      final status = (doc.data()?['status'] ?? '').toString();
      if (!mounted || status.isEmpty) return;
      setState(() {
        _highlightId = associationId;
        _closed.remove(status == 'pending' ? 'pending' : status == 'confirmed' ? 'confirmed' : 'completed');
      });
    } catch (_) {
      // A deep link is a convenience. If it fails, the page stands as it is.
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

  /// "Cancel" on a PENDING request: after a confirmation, as before (the request is cancelled and the student told).
  Future<void> _cancelRequest(String docId, Map<String, dynamic> data) async {
    if (!await _sure('Cancel this request?', 'The request from ${(data['studentName'] ?? 'the student')} will be cancelled and the student told.', 'Cancel request')) return;
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

  /// "Cancelled" on a CONFIRMED meeting: after a confirmation the meeting is DELETED completely and the student told.
  Future<void> _cancelConfirmed(String docId, Map<String, dynamic> data) async {
    if (!await _sure('Cancel this meeting?', 'The meeting with ${(data['studentName'] ?? 'the student')} will be deleted completely and the student told.', 'Delete meeting')) return;
    try {
      await cancelAndDeleteMeeting(docId, studentUid: (data['studentUid'] ?? '').toString());
      if (!mounted) return;
      showSnackbar(context, "Meeting cancelled and deleted", Colors.orange, Icons.cancel);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not cancel", Colors.red, Icons.error);
    }
  }

  Future<bool> _sure(String title, String body, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text(title, key: const ValueKey('assoc-sure-title')),
        content: Text(body),
        actions: [
          TextButton(key: const ValueKey('assoc-sure-no'), onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
          TextButton(key: const ValueKey('assoc-sure-yes'), onPressed: () => Navigator.pop(dialogContext, true), child: Text(yes)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _markComplete(String docId, Map<String, dynamic> data) async {
    String notes = _guideNotes[docId] ?? await guideNoteOf(docId);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return GuideDialog(
            title: const Text("Meeting completed"),
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

  // "Add interaction" (the button at the bottom) opens the shared form with a student picker; the assistant (Do it / Guide me) and Today save the very same record.

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

  // ---------------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------------

  Widget _shell({required String docId, required Widget child}) {
    final lit = _highlightId == docId;
    return Container(
      key: ValueKey('assoc-card-$docId'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.g.cardShadow,
        border: lit ? Border.all(color: context.g.agent, width: 2) : null,
      ),
      child: child,
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
      key: ValueKey('assoc-cancel-$docId'),
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
                "Requested: ${_formatTs(data['preferredDate'])}",
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
                    key: ValueKey('assoc-confirm-$docId'),
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

  /// A CONFIRMED meeting: the student, the date and time, and two buttons: "Completed" (asks for the notes) and "Cancelled" (deletes it, after a confirmation).
  Widget _confirmedCard(String docId, Map<String, dynamic> data) {
    return _shell(
      docId: docId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((data['studentName'] ?? 'Unknown').toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          _guideLabel(data),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event_available, size: 15, color: context.g.success),
              const SizedBox(width: 5),
              Flexible(child: Text(_formatTs(data['confirmedDate']), key: ValueKey('assoc-when-$docId'), style: TextStyle(fontSize: 12, color: context.g.success))),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  key: ValueKey('assoc-completed-$docId'),
                  onPressed: () => _markComplete(docId, data),
                  style: ElevatedButton.styleFrom(elevation: 0, backgroundColor: context.g.brass),
                  child: Text("Completed", style: TextStyle(color: context.g.onPrimary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: ValueKey('assoc-cancelled-$docId'),
                  onPressed: () => _cancelConfirmed(docId, data),
                  style: OutlinedButton.styleFrom(foregroundColor: context.g.danger, side: BorderSide(color: context.g.danger)),
                  child: const Text("Cancelled"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A COMPLETED meeting: the student, the date and the guide's notes (read-only).
  Widget _completedCard(String docId, Map<String, dynamic> data) {
    final guideNotes = _guideNotes[docId] ?? '';
    return _shell(
      docId: docId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((data['studentName'] ?? 'Unknown').toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          _guideLabel(data),
          const SizedBox(height: 8),
          Text(_formatTs(data['confirmedDate'] ?? data['preferredDate']), key: ValueKey('assoc-when-$docId'), style: TextStyle(fontSize: 12, color: context.g.mutedText)),
          if (guideNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              key: ValueKey('assoc-notes-$docId'),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: context.g.brass.withValues(alpha: .06), borderRadius: BorderRadius.circular(10)),
              child: Text(guideNotes, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tabs
  // ---------------------------------------------------------------------------


  /// ONE simple page, three collapsible sections in this order, each header with its count: PENDING (requests waiting for the guide), CONFIRMED
  /// (upcoming, soonest first) and COMPLETED (finished, newest first). Cancelled records are not listed; nothing is deleted except a confirmed meeting the
  /// guide cancels.
  Widget _buildSections(String guide) {
    return StreamBuilder<QuerySnapshot>(
      stream: _guideStream(guide),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GuideWait();
        }
        final all = (snapshot.data?.docs ?? []).map((d) => MapEntry(d.id, d.data() as Map<String, dynamic>)).toList();
        DateTime? when(Map<String, dynamic> m, String key) {
          final v = m[key];
          return v is Timestamp ? v.toDate() : null;
        }

        final pending = all.where((e) => e.value['status'] == 'pending').toList()
          ..sort((a, b) => (when(a.value, 'preferredDate') ?? DateTime(2100)).compareTo(when(b.value, 'preferredDate') ?? DateTime(2100)));
        final confirmed = all.where((e) => e.value['status'] == 'confirmed').toList()
          ..sort((a, b) => (when(a.value, 'confirmedDate') ?? DateTime(2100)).compareTo(when(b.value, 'confirmedDate') ?? DateTime(2100))); // soonest first
        final completed = all.where((e) => e.value['status'] == 'completed').toList()
          ..sort((a, b) => (when(b.value, 'confirmedDate') ?? when(b.value, 'preferredDate') ?? DateTime(2000)).compareTo(when(a.value, 'confirmedDate') ?? when(a.value, 'preferredDate') ?? DateTime(2000))); // newest first

        Widget section(String id, String title, IconData icon, List<MapEntry<String, Map<String, dynamic>>> list, Widget Function(String, Map<String, dynamic>) card, String empty) {
          final open = !_closed.contains(id);
          return PlanBlock(
            id: 'assoc-$id',
            icon: icon,
            title: title,
            total: list.length,
            showCheck: false,
            open: open,
            emptyText: empty,
            onToggle: () => setState(() => open ? _closed.add(id) : _closed.remove(id)),
            children: [for (final e in list) card(e.key, e.value)],
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            section('pending', 'Pending', Icons.hourglass_top_rounded, pending, _pendingCard, 'No pending requests'),
            const PlanBlockDivider(),
            section('confirmed', 'Confirmed', Icons.event_available_rounded, confirmed, _confirmedCard, 'No upcoming meetings'),
            const PlanBlockDivider(),
            section('completed', 'Completed', Icons.task_alt_rounded, completed, _completedCard, 'No completed meetings yet'),
          ],
        );
      },
    );
  }

  /// One query for the page. Status is matched in Dart because a second equality filter would require a composite index.
  ///
  /// The HOD sees every record; everyone else the records about students they may see (server-stamped `scope*` fields, merged client-side).
  Stream<QuerySnapshot> _guideStream(String guide) => StudentScope.current().historyStream('associations');

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        final guide = _selectedGuide;
        return GuideScaffold(
          appBar: GuideAppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Associations",
              style: TextStyle(fontWeight: FontWeight.bold, color: colorProvider.secondColor, fontSize: 20),
            ),
            // Overview — the overdue-associations dashboard.
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const OverdueAssociationsPage(),
                    transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
                  ),
                ),
                icon: Icon(Icons.event_busy, size: 18, color: colorProvider.secondColor),
                label: Text("Overdue", style: TextStyle(color: colorProvider.secondColor, fontWeight: FontWeight.w600, fontSize: 13.5)),
              ),
            ],
          ),
          body: guide == null ? const GuideWait() : ContentWidth(maxWidth: 760, child: _buildSections(guide)),
          // a new meeting, or an interaction (pick the student, then the same form the assistant and Today open), can be added from here
          floatingActionButton: guide == null
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      key: const ValueKey('assoc-add-interaction'),
                      heroTag: 'newInteraction',
                      backgroundColor: context.g.surface,
                      foregroundColor: context.g.text,
                      onPressed: () => showRecordInteractionFor(context),
                      icon: Icon(Icons.record_voice_over_outlined, color: context.g.text),
                      label: Text("Add interaction", style: TextStyle(color: context.g.text)),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'newMeeting',
                      backgroundColor: context.g.brass,
                      onPressed: () => _openCreateMeetingSheet(guide),
                      icon: Icon(Icons.add, color: context.g.onPrimary),
                      label: Text("New Meeting", style: TextStyle(color: context.g.onPrimary)),
                    ),
                  ],
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
