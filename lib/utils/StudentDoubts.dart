import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'AdminProfile.dart';
import 'GuideDb.dart';
import 'SeenMarkers.dart';
import 'StudentScope.dart';

/// STUDENTS' DOUBTS: a student reading a book can send a doubt to their guide (`bookDoubts/{id}`, written by the Student
/// app; mode "guide"). Each admin sees only the doubts of students they may see (the usual scope: HOD all, Guide his team
/// + unassigned males, Enablers their own + unassigned of their gender) - the same scope-field queries every other list
/// uses, and the server rules enforce it again. An answer is ONE update on that document (answer, answeredBy "guide",
/// answeredByName, answeredAt, status "answered"); the server then tells the student.
///
/// The orange dot trail follows the doubts themselves, not any push: a doubt is "unseen" while it is unanswered and this
/// admin has not opened it since the student asked (the ask time is compared with this admin's per-doubt seen marker, so a
/// re-ask shows again). It clears only when answered or opened - never because a notification was dismissed.
class StudentDoubt {
  const StudentDoubt({
    required this.id,
    required this.studentUid,
    required this.studentName,
    required this.bookTitle,
    required this.question,
    required this.text,
    required this.paragraph,
    required this.answer,
    required this.answeredByName,
    required this.askedAt,
    required this.askRound,
  });

  final String id;
  final String studentUid;
  final String studentName;
  final String bookTitle;
  final String question;

  /// The highlighted passage, and the paragraph it sits in.
  final String text;
  final String paragraph;

  /// Null while unanswered.
  final String? answer;
  final String? answeredByName;
  final Timestamp? askedAt;
  final int askRound;

  bool get answered => (answer ?? '').trim().isNotEmpty;

  /// A short preview of the question for the list.
  String get preview {
    final t = question.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 90 ? '${t.substring(0, 89)}…' : t;
  }

  /// The doubt a guide should see: one the student sent to their guide. Null for an AI doubt or a malformed document.
  static StudentDoubt? fromDoc(String id, Map<String, dynamic> d) {
    if (d['mode'] != 'guide') return null;
    final question = (d['question'] ?? '').toString();
    if (question.trim().isEmpty) return null;
    final asked = d['askedAt'] ?? d['createdAt'];
    final round = d['askRound'];
    final answer = d['status'] == 'answered' && d['answer'] is String && (d['answer'] as String).trim().isNotEmpty ? d['answer'] as String : null;
    return StudentDoubt(
      id: id,
      studentUid: (d['uid'] ?? '').toString(),
      studentName: ((d['studentName'] ?? '').toString().trim().isEmpty) ? 'A student' : (d['studentName'] as String).trim(),
      bookTitle: (d['bookTitle'] ?? '').toString(),
      question: question,
      text: (d['text'] ?? '').toString(),
      paragraph: (d['paragraph'] ?? '').toString(),
      answer: answer,
      answeredByName: d['answeredByName'] is String ? d['answeredByName'] as String : null,
      askedAt: asked is Timestamp ? asked : null,
      askRound: round is num ? round.toInt() : 1,
    );
  }

  /// Unanswered first, then newest first.
  static List<StudentDoubt> sorted(Iterable<StudentDoubt> doubts) {
    final out = doubts.toList();
    int ms(StudentDoubt d) => d.askedAt?.millisecondsSinceEpoch ?? 1 << 50; // a just-written doubt (no server time yet) is the newest
    out.sort((a, b) {
      if (a.answered != b.answered) return a.answered ? 1 : -1;
      return ms(b).compareTo(ms(a));
    });
    return out;
  }
}

class StudentDoubts {
  /// The seen-marker feature key (`seenMarkers/{adminId}.studentDoubts.{doubtId}`).
  static const String featureKey = 'studentDoubts';

  static StudentScope get _scope => StudentScope.current();

  /// Tests only: nothing is unseen (no Firestore), as for the other aggregates.
  @visibleForTesting
  static bool debugDisable = false;

  /// Every doubt of every student this admin may see (merged, scope-field queries; no composite index).
  static Stream<List<StudentDoubt>> stream() => _scope.historyStream('bookDoubts').map(_read);

  static List<StudentDoubt> _read(QuerySnapshot<Map<String, dynamic>> snap) => [
        for (final d in snap.docs)
          if (StudentDoubt.fromDoc(d.id, d.data()) case final doubt?) doubt,
      ];

  /// Whether [d] shows an orange dot to an admin whose per-doubt markers are [cursors]: unanswered, and not opened since asked.
  static bool isUnseen(StudentDoubt d, Map<String, Timestamp> cursors) {
    if (d.answered) return false;
    final asked = d.askedAt;
    if (asked == null) return true; // just sent: the server time has not landed yet
    final seen = cursors[d.id];
    return seen == null || asked.compareTo(seen) > 0;
  }

  /// The ids of the doubts with a dot, live. Drives the list, the category row, the Priority card and the Analysis tab.
  static Stream<Set<String>> unseenIds(String guide) {
    if (debugDisable) return Stream.value(const <String>{});
    late StreamController<Set<String>> controller;
    List<StudentDoubt>? doubts;
    Map<String, Timestamp>? cursors;
    final subs = <StreamSubscription<dynamic>>[];

    void emit() {
      if (doubts == null || cursors == null) return;
      controller.add({for (final d in doubts!) if (isUnseen(d, cursors!)) d.id});
    }

    controller = StreamController<Set<String>>.broadcast(
      onListen: () {
        subs.add(stream().listen((d) {
          doubts = d;
          emit();
        }, onError: (_) {}));
        subs.add(SeenMarkers.subCursors(guide, featureKey).listen((c) {
          cursors = c;
          emit();
        }, onError: (_) {}));
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// "Is any doubt waiting for me" - the aggregate dot.
  static Stream<bool> anyUnseen(String guide, [bool isHod = false]) => unseenIds(guide).map((s) => s.isNotEmpty);

  /// This admin opened the doubt: its own dot clears (a re-ask newer than this shows again).
  static Future<void> markOpened(String guide, String doubtId) => SeenMarkers.markSeenSub(guide, featureKey, doubtId);

  /// Saves the guide's answer on the student's doubt, marked answered. The server rules accept exactly these fields.
  static Future<void> answer({required String doubtId, required String text, required AdminProfile me}) {
    final answer = text.trim();
    if (answer.isEmpty) throw ArgumentError('An answer is required');
    return GuideDb.instance.collection('bookDoubts').doc(doubtId).update({
      'answer': answer.length > 4000 ? answer.substring(0, 4000) : answer,
      'answeredBy': 'guide',
      'answeredByName': me.displayName,
      'answeredAt': FieldValue.serverTimestamp(),
      'status': 'answered',
    });
  }
}
