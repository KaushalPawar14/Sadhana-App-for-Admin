import 'package:cloud_firestore/cloud_firestore.dart';

import 'GuideDb.dart';

/// A student's HISTORY, one line each, in SEVEN CATEGORIES ([kHistoryCategories]) with at most 30 lines in each, newest first
/// (`studentHistory/{studentUid}`, written only by the server: `functions/studentHistory.js`). The board card's drop-down shows each category as a
/// collapsible section; a tap on a line opens the full details.
///
/// Kinds: [kAdvice] (the plan's advice for him), [kInteraction], [kDealing] (books, meetings, trips), [kNote] (what the guide told the
/// assistant) and [kSadhana] (a significant change: the weekly chanting average moving by 2+ rounds, 3+ missed days, a new best week, a
/// changed commitment, a changed residence) and [kSurrender] (a 10% threshold of his Surrender % crossed, and what an interaction changed).
/// Students never see it.
const String kHistoryAdvice = 'advice';
const String kHistoryInteraction = 'interaction';
const String kHistoryDealing = 'dealing';
const String kHistoryNote = 'note';
const String kHistorySadhana = 'sadhana';
const String kHistorySurrender = 'surrender';

/// How many lines are kept IN EACH CATEGORY (the server trims to this).
const int kHistoryMax = 30;

/// The seven categories, in the order the card shows them: the key the server writes on every line, and its heading.
const List<({String key, String label})> kHistoryCategories = [
  (key: 'interactions', label: 'Interactions & meetings'),
  (key: 'surrender', label: 'Surrender & targets'),
  (key: 'sadhana', label: 'Sadhana'),
  (key: 'books', label: 'Books'),
  (key: 'trips', label: 'Trips & services'),
  (key: 'worries', label: 'Worries'),
  (key: 'doubts', label: 'Doubts'),
];

/// The category of a line the server has not categorised yet (an old line): the same rule as `categoryOf` in `functions/studentHistory.js`.
String historyCategoryOf(String id, String kind) {
  bool starts(List<String> p) => p.any(id.startsWith);
  if (kind == 'surrender' || kind == 'surrender_check' || starts(['cross_', 'surrender_', 'target_', 'note_surrender_check'])) return 'surrender';
  if (starts(['doubt_'])) return 'doubts';
  if (starts(['concern_'])) return 'worries';
  if (starts(['book_'])) return 'books';
  if (starts(['trip_', 'service_'])) return 'trips';
  if (kind == 'sadhana' || starts(['chantavg_', 'best_', 'commit_', 'readcommit_', 'category_', 'report_'])) return 'sadhana';
  return 'interactions';
}

class HistoryLine {
  const HistoryLine({required this.id, required this.kind, required this.title, required this.detail, required this.at, String? category}) : _category = category;

  final String id;
  final String kind;

  final String? _category;

  /// One of [kHistoryCategories]'s keys: the one the server wrote on the line, else worked out from its kind and id (an old line).
  String get category => _category ?? historyCategoryOf(id, kind);

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
    final id = (raw['id'] ?? '').toString();
    final kind = (raw['kind'] ?? kHistoryDealing).toString();
    final given = (raw['category'] ?? '').toString();
    return HistoryLine(
      id: id,
      kind: kind,
      category: kHistoryCategories.any((c) => c.key == given) ? given : null,
      title: title,
      detail: (raw['detail'] ?? '').toString().trim().isEmpty ? title : (raw['detail'] ?? '').toString().trim(),
      at: at is Timestamp ? at.toDate() : null,
    );
  }

  /// The lines of a `studentHistory` document: newest first, at most [kHistoryMax] in each category.
  static List<HistoryLine> fromDoc(Map<String, dynamic>? data) {
    final raw = data?['items'];
    final lines = [
      if (raw is List)
        for (final e in raw)
          if (HistoryLine.fromMap(e) case final l?) l,
    ];
    lines.sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
    final count = <String, int>{};
    return [
      for (final l in lines)
        if ((count[l.category] = (count[l.category] ?? 0) + 1) <= kHistoryMax) l,
    ];
  }
}

/// Live: one student's history (empty until the server writes the first line).
Stream<List<HistoryLine>> studentHistoryStream(String studentUid) =>
    GuideDb.instance.collection('studentHistory').doc(studentUid).snapshots().map((d) => HistoryLine.fromDoc(d.data()));
