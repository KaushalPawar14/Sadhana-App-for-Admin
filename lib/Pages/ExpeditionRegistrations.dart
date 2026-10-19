import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../utils/ExpeditionModel.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';

/// The students registered for ONE trip (those this admin may see), with each student's attendance and,
/// when they wrote one, their reflection.
///
/// [editable] is true for an active trip: each student's status is a tap away (Pending / Partially completed /
/// Fully completed). For a trip in History it is false: the same list, read only, statuses frozen as they were
/// (the rules refuse a change as well).
class ExpeditionRegistrationsList extends StatelessWidget {
  const ExpeditionRegistrationsList({
    super.key,
    required this.tripId,
    required this.editable,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
  });

  final String tripId;
  final bool editable;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: StudentScope.current().historyStream('expeditionRegistrations'),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text("Couldn't load the registrations just now.")));
        }
        if (!snap.hasData) return const GuideWait();
        final docs = snap.data!.docs.where((d) => (d.data()['expeditionId'] ?? '').toString() == tripId).toList()
          ..sort((a, b) => (a.data()['studentName'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b.data()['studentName'] ?? '').toString().toLowerCase()));
        final summary = summariseAttendance(docs.map((d) => d.data()));

        return ListView(
          padding: padding,
          children: [
            _SummaryBar(total: docs.length, summary: summary),
            const SizedBox(height: 8),
            if (docs.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Text('Nobody has registered yet'))
            else
              for (final d in docs) _StudentRow(doc: d, editable: editable),
          ],
        );
      },
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.total, required this.summary});

  final int total;
  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Column(
      key: const ValueKey('attendance-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$total registered', style: TextStyle(fontSize: 12, color: g.mutedText)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _countChip('Pending', summary.pending, g.warning),
            _countChip('Partially completed', summary.partial, g.brass),
            _countChip('Fully completed', summary.full, g.success),
          ],
        ),
      ],
    );
  }

  Widget _countChip(String label, int n, Color color) => _Pill(label: '$label $n', color: color);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.trailing});

  final String label;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.doc, required this.editable});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool editable;

  Color _color(BuildContext context, String a) {
    final g = context.g;
    switch (a) {
      case kAttendanceFull:
        return g.success;
      case kAttendancePartial:
        return g.brass;
      default:
        return g.warning;
    }
  }

  Future<void> _choose(BuildContext context, String current) async {
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Attendance'),
        children: [
          for (final v in kAttendanceValues)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, v),
              child: Row(
                children: [
                  Icon(v == current ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: dialogContext.g.brass),
                  const SizedBox(width: 10),
                  Flexible(child: Text(attendanceLabel(v))),
                ],
              ),
            ),
        ],
      ),
    );
    if (next == null || next == current || !context.mounted) return;
    try {
      await doc.reference.update({'attendance': next});
      if (!context.mounted) return;
      showSnackbar(context, attendanceLabel(next), Colors.blue, Icons.check_circle);
    } catch (_) {
      if (!context.mounted) return;
      showSnackbar(context, 'Could not update', Colors.red, Icons.error);
    }
  }

  void _showReflection(BuildContext context, Map<String, dynamic> data) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text((data['studentName'] ?? 'Reflection').toString()),
        content: SingleChildScrollView(
          child: Text(
            (data['reflectionText'] ?? '').toString().isEmpty ? 'No reflection text.' : data['reflectionText'].toString(),
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final data = doc.data();
    final name = (data['studentName'] ?? 'Unknown').toString();
    final attendance = attendanceOf(data);
    final reflected = data['hasReflected'] == true;
    final color = _color(context, attendance);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: g.surface, borderRadius: BorderRadius.circular(14), boxShadow: g.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: g.brass,
                child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(color: g.onPrimary)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    widthFactor: 1,
                    child: InkWell(
                      key: ValueKey('attendance-${doc.id}'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: editable ? () => _choose(context, attendance) : null,
                      child: _Pill(
                        label: attendanceLabel(attendance),
                        color: color,
                        trailing: editable ? Icon(Icons.arrow_drop_down, size: 18, color: color) : null,
                      ),
                    ),
                  ),
                ),
                if (reflected)
                  TextButton.icon(
                    key: ValueKey('reflection-${doc.id}'),
                    onPressed: () => _showReflection(context, data),
                    icon: const Icon(Icons.notes, size: 16),
                    label: const Text('View reflection'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
