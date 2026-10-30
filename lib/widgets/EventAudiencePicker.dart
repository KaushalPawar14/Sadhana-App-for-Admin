import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../utils/StudentScope.dart';
import 'GuideDialog.dart';
import 'GuideMeta.dart';

/// WHO A CALENDAR EVENT IS FOR: everyone (nothing chosen), one or more categories (FOLK / Hostel / Localite) and / or named students. The plans and the
/// assistant apply the event (an exam, a festival, a program ...) only to these students.
class EventAudiencePicker extends StatelessWidget {
  const EventAudiencePicker({super.key, required this.categories, required this.students, required this.onChanged, this.loadStudents});

  final List<String> categories;
  final List<String> students;

  /// Called with the new categories and students.
  final void Function(List<String> categories, List<String> students) onChanged;

  /// The students the guide may choose from (uid -> name); the signed-in admin's own scope when null. Swapped in tests.
  final Future<Map<String, String>> Function()? loadStudents;

  static const Map<String, String> kLabels = {'folk': 'FOLK', 'hostel': 'Hostel', 'localite': 'Localite'};

  static Future<Map<String, String>> _scoped() async {
    final snap = await StudentScope.current().studentsGet();
    return {for (final d in snap.docs) d.id: (d.data()['name'] ?? '').toString()};
  }

  Future<void> _pickStudents(BuildContext context) async {
    final all = await (loadStudents ?? _scoped)();
    if (!context.mounted) return;
    final chosen = {...students};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) {
          final names = all.entries.where((e) => e.value.isNotEmpty).toList()..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
          return GuideDialog(
            title: const Text('Which students?', key: ValueKey('audience-students-title')),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: ListView(
                children: [
                  for (final e in names)
                    CheckboxListTile(
                      key: ValueKey('audience-student-${e.key}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: chosen.contains(e.key),
                      title: Text(e.value),
                      onChanged: (v) => setDialog(() => v == true ? chosen.add(e.key) : chosen.remove(e.key)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              ElevatedButton(key: const ValueKey('audience-students-ok'), onPressed: () => Navigator.pop(dialogContext, chosen.toList()), child: const Text('OK')),
            ],
          );
        },
      ),
    );
    if (result != null) onChanged(categories, result);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final everyone = categories.isEmpty && students.isEmpty;
    return Column(
      key: const ValueKey('event-audience'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who is it for?', style: t.bodyStrong),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            GuideChoiceChip(key: const ValueKey('audience-everyone'), label: 'Everyone', selected: everyone, onSelected: (_) => onChanged(const [], const [])),
            for (final e in kLabels.entries)
              GuideChoiceChip(
                key: ValueKey('audience-${e.key}'),
                label: e.value,
                selected: categories.contains(e.key),
                onSelected: (v) => onChanged(v ? [...categories, e.key] : [for (final c in categories) if (c != e.key) c], students),
              ),
            GuideChoiceChip(
              key: const ValueKey('audience-specific'),
              label: students.isEmpty ? 'Specific students' : 'Specific students (${students.length})',
              selected: students.isNotEmpty,
              onSelected: (_) => _pickStudents(context),
            ),
          ],
        ),
      ],
    );
  }
}
