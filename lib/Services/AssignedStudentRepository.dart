import 'package:supabase_flutter/supabase_flutter.dart';

import 'FolkIdentityService.dart';

class AssignedStudentSnapshot {
  const AssignedStudentSnapshot({
    required this.studentId,
    required this.fullName,
    required this.cohort,
    required this.isPrimary,
    required this.isSynthetic,
    this.latestEntryDate,
    this.chantingRounds,
    this.bookReadingMinutes,
    this.hearingMinutes,
  });

  final String studentId;
  final String fullName;
  final String cohort;
  final bool isPrimary;
  final bool isSynthetic;
  final DateTime? latestEntryDate;
  final int? chantingRounds;
  final int? bookReadingMinutes;
  final int? hearingMinutes;

  int? get daysSinceEntry => latestEntryDate == null
      ? null
      : DateTime.now().difference(latestEntryDate!).inDays;

  String get focusReason {
    if (latestEntryDate == null) {
      return 'No sādhana submission in the last 60 days';
    }
    if ((daysSinceEntry ?? 0) > 3) {
      return 'Last sādhana submission was $daysSinceEntry days ago';
    }
    if ((chantingRounds ?? 0) < 4) {
      return 'Currently reporting ${chantingRounds ?? 0} chanting rounds';
    }
    if ((bookReadingMinutes ?? 0) == 0) {
      return 'Chanting is active; book reading needs attention';
    }
    return 'Recent sādhana is active and ready for personal follow-up';
  }

  String get nextAction {
    if (latestEntryDate == null || (daysSinceEntry ?? 0) > 3) {
      return 'Offer two personal-association slots';
    }
    if ((chantingRounds ?? 0) < 4) {
      return 'Discuss one attainable chanting step';
    }
    if ((bookReadingMinutes ?? 0) == 0) {
      return 'Send a mentor-approved book motivation draft';
    }
    return 'Ask one reflective question in the next conversation';
  }
}

class AssignedStudentRepository {
  const AssignedStudentRepository();

  Future<List<AssignedStudentSnapshot>> load() async {
    final client = FolkIdentityService.client;
    final guide = FolkIdentityService.currentUser;
    if (client == null || guide == null) return const [];

    final assignmentRows = List<Map<String, dynamic>>.from(
      await client
          .from('guide_student_assignments')
          .select('student_id,is_primary')
          .eq('guide_id', guide.id)
          .eq('is_active', true),
    );
    if (assignmentRows.isEmpty) return const [];

    final studentIds = assignmentRows
        .map((row) => row['student_id'] as String)
        .toSet()
        .toList(growable: false);
    final primaryByStudent = {
      for (final row in assignmentRows)
        row['student_id'] as String: row['is_primary'] == true,
    };

    final profileRows = List<Map<String, dynamic>>.from(
      await client
          .from('users')
          .select(
            'id,email,full_name,college_name_override,academic_year',
          )
          .inFilter('id', studentIds),
    );

    final cutoff = DateTime.now().subtract(const Duration(days: 60));
    final entryRows = List<Map<String, dynamic>>.from(
      await client
          .from('sadhana_entries')
          .select(
            'student_id,entry_date,chanting_rounds,book_reading_minutes,hearing_minutes',
          )
          .inFilter('student_id', studentIds)
          .gte('entry_date', _dateOnly(cutoff))
          .order('entry_date', ascending: false),
    );
    final latestByStudent = <String, Map<String, dynamic>>{};
    for (final entry in entryRows) {
      latestByStudent.putIfAbsent(entry['student_id'] as String, () => entry);
    }

    final snapshots = profileRows.map((profile) {
      final id = profile['id'] as String;
      final entry = latestByStudent[id];
      final college = profile['college_name_override'] as String?;
      final academicYear = profile['academic_year'] as String?;
      final cohortParts = [college, academicYear]
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
      final email = profile['email'] as String? ?? '';
      return AssignedStudentSnapshot(
        studentId: id,
        fullName: profile['full_name'] as String? ?? 'FOLK student',
        cohort: cohortParts.isEmpty
            ? 'College not yet confirmed'
            : cohortParts.join(' · '),
        isPrimary: primaryByStudent[id] ?? false,
        isSynthetic: email.endsWith('@example.test'),
        latestEntryDate: entry == null
            ? null
            : DateTime.tryParse(entry['entry_date'] as String),
        chantingRounds: entry?['chanting_rounds'] as int?,
        bookReadingMinutes: entry?['book_reading_minutes'] as int?,
        hearingMinutes: entry?['hearing_minutes'] as int?,
      );
    }).toList(growable: false)
      ..sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        final aDate = a.latestEntryDate ?? DateTime(2000);
        final bDate = b.latestEntryDate ?? DateTime(2000);
        return aDate.compareTo(bDate);
      });

    return snapshots;
  }

  String _dateOnly(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
