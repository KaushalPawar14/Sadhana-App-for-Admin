import 'package:intl/intl.dart';

import '../utils/AdminProfile.dart';
import '../utils/SadhanaReportSource.dart';
import '../utils/StudentScope.dart';

/// Who has not filed today's report — among the students THIS admin may see.
///
/// This used to scan the whole `notification` collection (every student's FCM
/// token) and also built the bulk-push token list with a service-account key
/// bundled in the app. Both are gone: tokens are never read by the app now (the
/// server sends — callable `sendStudentNotification`), and the roster is the
/// admin's own scoped student list.
class MissingReportService {
  String getTodayDateId() {
    return DateFormat('dd-MM-yyyy').format(DateTime.now());
  }

  /// Names (the sadhana document ids) of the visible students with no report for today in the collection of
  /// their CURRENT category.
  Future<List<String>> fetchMissingNames() async {
    final today = getTodayDateId();
    final students = await StudentScope(AdminProfileProvider.require())
        .studentsGet();

    final checks = <Future<String?>>[];
    for (final doc in students.docs) {
      final name = (doc.data()['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final role = (doc.data()['role'] ?? '').toString();
      checks.add(() async {
        try {
          final report = await fetchDateReport(name, today, role);
          return report == null ? name : null;
        } catch (_) {
          // One failed read must not hide everybody else's missing report.
          return null;
        }
      }());
    }
    final results = await Future.wait(checks);
    return results.whereType<String>().toList();
  }
}

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  factory NotificationManager() => _instance;
  NotificationManager._internal();

  List<String> missingUsernames = [];

  Future<void> prepareMissingReports() async {
    missingUsernames = await MissingReportService().fetchMissingNames();
  }

  int get missingCount => missingUsernames.length;
}
