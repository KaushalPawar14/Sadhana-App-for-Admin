import 'package:cloud_firestore/cloud_firestore.dart';

import 'GuideDb.dart';

/// A student's HISTORY, one line each: the latest 30 things about him, newest first (`studentHistory/{studentUid}`, written only by the
/// server: `functions/studentHistory.js`). The board card's drop-down shows it; a tap opens the full details.
///
/// Kinds: [kAdvice] (the plan's advice for him), [kInteraction], [kDealing] (books, meetings, trips), [kNote] (what the guide told the
/// assistant) and [kSadhana] (a significant change: the weekly chanting average moving by 2+ rounds, 3+ missed days, a new best week, a
/// changed commitment, a changed residence). Students never see it.
const String kHistoryAdvice = 'advice';
const String kHistoryInteraction = 'interaction';
const String kHistoryDealing = 'dealing';
const String kHistoryNote = 'note';
const String kHistorySadhana = 'sadhana';

/// How many lines are kept (the server trims to this).
const int kHistoryMax = 30;

class HistoryLine {
  const HistoryLine({required this.id, required this.kind, required this.title, required this.detail, required this.at});

  final String id;
  final String kind;

  /// The one line shown on the card.
  final String title;

  /// The full details, shown when the line is tapped.
  final String detail;
  final DateTime? at;

  static HistoryLine? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final title = (raw['title'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    final at = raw['at'];
    return HistoryLine(
      id: (raw['id'] ?? '').toString(),
      kind: (raw['kind'] ?? kHistoryDealing).toString(),
      title: title,
      detail: (raw['detail'] ?? '').toString().trim().isEmpty ? title : (raw['detail'] ?? '').toString().trim(),
      at: at is Timestamp ? at.toDate() : null,
    );
  }

  /// The lines of a `studentHistory` document: newest first, at most [kHistoryMax].
  static List<HistoryLine> fromDoc(Map<String, dynamic>? data) {
    final raw = data?['items'];
    final lines = [
      if (raw is List)
        for (final e in raw)
          if (HistoryLine.fromMap(e) case final l?) l,
    ];
    lines.sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
    return lines.take(kHistoryMax).toList();
  }
}

/// Live: one student's history (empty until the server writes the first line).
Stream<List<HistoryLine>> studentHistoryStream(String studentUid) =>
    GuideDb.instance.collection('studentHistory').doc(studentUid).snapshots().map((d) => HistoryLine.fromDoc(d.data()));
