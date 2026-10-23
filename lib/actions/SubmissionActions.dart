import '../Services/HierarchyApi.dart';
import '../Services/MissingReportNotification.dart';
import '../utils/AdminProfile.dart';
import '../utils/SadhanaReportSource.dart';
import '../utils/StudentScope.dart';

/// Today's sadhana submissions and the reminder nudge, as shared logic with no
/// screen in it: the Submissions screen and the AI agent read the same status and
/// send the same nudge through these.

/// One student in scope, with just enough to show them or nudge them.
typedef SubmissionEntry = ({String name, String role, String uid});

/// Who has and has not filed today's report, among the students THIS admin may see.
class SubmissionStatus {
  const SubmissionStatus({
    this.notSubmitted = const [],
    this.submitted = const [],
    this.unchecked = const [],
  });

  /// No report for today — "this is what needs action".
  final List<SubmissionEntry> notSubmitted;

  /// Has filed today.
  final List<SubmissionEntry> submitted;

  /// The report could not be read: in neither group, never guessed into one.
  final List<SubmissionEntry> unchecked;

  int get inScope => notSubmitted.length + submitted.length + unchecked.length;
}

/// Checks EVERY student in the signed-in admin's scope against their own report doc
/// for today, so each lands in exactly one group.
///
/// Not derived from `NotificationManager().missingUsernames`: that cache is keyed
/// off the `notification` collection (one doc per token registration), not `users`,
/// so a student with no token yet would never be considered at all. Category
/// separation holds: only the collection of the student's CURRENT category counts.
///
/// A failed roster read returns empty lists (a guide sees nothing rather than a
/// wrong "everyone submitted"); one student's failed read only puts that student
/// in [SubmissionStatus.unchecked].
Future<SubmissionStatus> loadSubmissionStatus() async {
  final profile = AdminProfileProvider.require();
  final notSubmitted = <SubmissionEntry>[];
  final submitted = <SubmissionEntry>[];
  final unchecked = <SubmissionEntry>[];

  try {
    final snap = await StudentScope(profile).studentsGet();
    final today = MissingReportService().getTodayDateId();

    final checks = <Future<void>>[];
    for (final doc in snap.docs) {
      final name = (doc.data()['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final role = (doc.data()['role'] ?? '').toString();
      final entry = (name: name, role: role, uid: doc.id);

      checks.add(Future(() async {
        try {
          final report = await fetchDateReport(name, today, role);
          if (report != null) {
            submitted.add(entry);
          } else {
            notSubmitted.add(entry);
          }
        } catch (_) {
          unchecked.add(entry);
        }
      }));
    }

    await Future.wait(checks);
    notSubmitted.sort((a, b) => a.name.compareTo(b.name));
    submitted.sort((a, b) => a.name.compareTo(b.name));
  } catch (_) {
    return const SubmissionStatus();
  }

  return SubmissionStatus(
    notSubmitted: notSubmitted,
    submitted: submitted,
    unchecked: unchecked,
  );
}

/// The server accepts at most this many students per `sendStudentNotification`.
const int kReminderChunk = 200;

/// Nudges [uids] ("have you filed today's report?", kind `submission_nudge`). The
/// server builds the message and applies each student's own mute setting, so the
/// count that went out can be lower than the number asked.
///
/// Never throws: a failed chunk counts 0 so a bulk run continues through the rest.
/// [onProgress] is told after each chunk with (students tried so far, delivered so
/// far). Returns how many notifications actually went out.
Future<int> sendSubmissionReminders(
  List<String> uids, {
  void Function(int done, int sent)? onProgress,
}) async {
  var done = 0;
  var sent = 0;
  for (var i = 0; i < uids.length; i += kReminderChunk) {
    final end = i + kReminderChunk > uids.length ? uids.length : i + kReminderChunk;
    final chunk = uids.sublist(i, end);
    try {
      final r = await HierarchyApi.instance.sendStudentNotification(
        chunk.length == 1
            ? {'kind': 'submission_nudge', 'studentUid': chunk.first}
            : {'kind': 'submission_nudge', 'studentUids': chunk},
      );
      sent += (r['sent'] as num?)?.toInt() ?? 0;
    } catch (_) {/* counts 0; the rest still go */}
    done += chunk.length;
    onProgress?.call(done, sent);
  }
  return sent;
}
