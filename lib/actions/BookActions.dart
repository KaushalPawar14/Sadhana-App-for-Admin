import 'package:cloud_firestore/cloud_firestore.dart';

import '../Services/HierarchyApi.dart';
import '../utils/BoardData.dart';
import '../utils/GuideDb.dart';

/// Books a guide assigns to a student, marks finished, or puts back — as shared
/// writes with no screen in them. The board's book rows and the AI agent both
/// call these, so a book the agent assigns is the same document, the same
/// commitment, and the same push to the student as one assigned by hand.
///
/// The complete set of `booksRead` fields the Guide app ever writes, across all
/// three: `uid`, `level`, `bookKey`, `bookTitle`, `isCurrentBook`, `startDate`,
/// `endDate`, `endedBy`, `commitmentDate`, `commitmentSetAt`, `commitmentSetBy`.
/// `madeNotes` — the student's own self-report about taking notes — is never
/// written here: it is exclusively student-authored.

/// The document id for one student's one book.
String bookDocId(String studentUid, String level, String bookKey) =>
    '${studentUid}_${level}_$bookKey';

String _today() => DateTime.now().toIso8601String().split('T')[0];

/// Assigns a book: it becomes the student's CURRENT book, with a commitment date
/// the guide chose, and the student is told.
///
/// Also writes `startDate` = today — the day of assignment, distinct from
/// `commitmentDate`, the future due-date. Same `yyyy-MM-dd` shape the Student
/// app's own start date uses, so both write paths agree on the field.
///
/// A transaction, so the document is read at the moment of writing: a book that
/// is already completed (an end date, marked finished by the student, or ended
/// by a guide) is never made the student's current book. That invariant — a
/// finished book is never current — holds here whatever called this.
///
/// @return true if assigned, false if the book was already completed
Future<bool> assignBook({
  required String guideId,
  required String studentUid,
  required String level,
  required String bookKey,
  required String title,
  required DateTime commitment,
}) async {
  final commitmentDate = commitment.toIso8601String().split('T')[0];
  final startDate = _today();
  final bookRef = GuideDb.instance
      .collection('booksRead')
      .doc(bookDocId(studentUid, level, bookKey));

  final assigned = await GuideDb.instance.runTransaction<bool>((tx) async {
    final latest = (await tx.get(bookRef)).data();
    final endDate = latest?['endDate'];
    final endedBy = latest?['endedBy'];
    final completed =
        (endDate != null && endDate.toString().trim().isNotEmpty) ||
            latest?['finishedViaButton'] == true ||
            (endedBy != null && endedBy.toString().trim().isNotEmpty);
    if (completed) return false;
    tx.set(
        bookRef,
        {
          'uid': studentUid,
          'level': level,
          'bookKey': bookKey,
          'bookTitle': title,
          'isCurrentBook': true,
          'startDate': startDate,
          'commitmentDate': commitmentDate,
          'commitmentSetAt': FieldValue.serverTimestamp(),
          'commitmentSetBy': 'guide',
        },
        SetOptions(merge: true));
    return true;
  });
  if (!assigned) return false;

  // The admin who set the commitment has seen it: it must not light their own dot.
  BoardData.instance
      .markBooksSeen(guideId, studentUid, [bookDocId(studentUid, level, bookKey)]);

  await notifyBookAssigned(
    studentUid: studentUid,
    bookTitle: title,
    commitmentDate: commitmentDate,
  );
  return true;
}

/// The "book assigned" push goes through the server: the student's FCM token is
/// never read by the app, and the server builds the title and body.
Future<void> notifyBookAssigned({
  required String studentUid,
  required String bookTitle,
  required String commitmentDate,
}) async {
  try {
    await HierarchyApi.instance.sendStudentNotification({
      'kind': 'book_assigned',
      'studentUid': studentUid,
      'bookTitle': bookTitle,
      'commitmentDate': commitmentDate,
    });
  } catch (_) {
    // A failed notification must never undo the assignment write, which has
    // already landed by the time this runs.
  }
}

/// Marks a book finished in ONE write: `endDate` = today, `isCurrentBook` =
/// false and `endedBy` = 'guide' together, so there is no intermediate state
/// where any one is set and not the others.
///
/// [hasStarted] is whether the book already has a start date. A book that was
/// NEVER started gets `startDate` = today as well, so it has a real (equal) start
/// and end rather than an end with no start; a book that has one keeps it — this
/// never overwrites a real start date the student or a previous assignment
/// recorded.
Future<void> markBookFinished({
  required String studentUid,
  required String level,
  required String bookKey,
  required String title,
  required bool hasStarted,
}) async {
  final today = _today();
  await GuideDb.instance
      .collection('booksRead')
      .doc(bookDocId(studentUid, level, bookKey))
      .set({
    'uid': studentUid,
    'level': level,
    'bookKey': bookKey,
    'bookTitle': title,
    'endDate': today,
    'isCurrentBook': false,
    // Read by the Student app to show "Marked complete by your guide" instead of
    // leaving a student wondering why a book they never finished shows as done.
    'endedBy': 'guide',
    if (!hasStarted) 'startDate': today,
  }, SetOptions(merge: true));
}

/// The other half: a book marked completed by mistake, put back.
///
/// ONE write. `endDate` and `endedBy` are DELETED (not blanked — a deleted field
/// is what a book that was never finished actually looks like), and
/// `isCurrentBook` is left FALSE. That is deliberate: the combination
/// `isCurrentBook == false` with no `endDate` already reads as not started ("the
/// record asserts no progress, so the caller claims none"), whereas setting it
/// true would silently credit the student with reading a book their own report
/// never claimed and risk a second current book. `startDate` is untouched.
Future<void> markBookNotFinished({
  required String studentUid,
  required String level,
  required String bookKey,
  required String title,
}) async {
  await GuideDb.instance
      .collection('booksRead')
      .doc(bookDocId(studentUid, level, bookKey))
      .set({
    'uid': studentUid,
    'level': level,
    'bookKey': bookKey,
    'bookTitle': title,
    'endDate': FieldValue.delete(),
    'endedBy': FieldValue.delete(),
    'isCurrentBook': false,
  }, SetOptions(merge: true));
}
