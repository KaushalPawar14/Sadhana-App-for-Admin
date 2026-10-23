import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/GuideDb.dart';

/// A comment on a student's thread, as one shared write: the comments dialog and
/// the AI agent both post through [postStudentComment].
///
/// Append-only. Nothing edits or deletes a comment, here or anywhere in the app.

/// The collection name, in one place.
const String kStudentCommentsCollection = 'studentComments';

/// The longest a single comment may be. The thread is a conversation, not a document.
const int kMaxCommentChars = 2000;

/// Posts [text] on [studentUid]'s thread as [authorId].
///
/// [authorRole] is 'HOD' for the HOD and 'guide' for everyone else, exactly as the
/// dialog has always stored it. The admin id is permanent; the display name is
/// what a reader needs — both are stored so a later rename does not have to
/// rewrite history.
///
/// @return the new message's id
Future<String> postStudentComment({
  required String studentUid,
  required String text,
  required String authorId,
  required String authorName,
  required bool authorIsHod,
}) async {
  final clean = text.trim();
  if (clean.isEmpty) throw ArgumentError('A comment cannot be empty.');
  if (clean.length > kMaxCommentChars) {
    throw ArgumentError('A comment can be at most $kMaxCommentChars characters.');
  }
  final ref = await GuideDb.instance
      .collection(kStudentCommentsCollection)
      .doc(studentUid)
      .collection('messages')
      .add({
    'text': clean,
    'authorId': authorId,
    'authorRole': authorIsHod ? 'HOD' : 'guide',
    'authorName': authorName,
    'createdAt': FieldValue.serverTimestamp(),
  });
  return ref.id;
}
