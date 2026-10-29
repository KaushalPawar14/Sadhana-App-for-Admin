/// Finding near-identical records, so "delete the duplicate" can show the candidates side by side and let the guide choose.
///
/// Pure functions on plain data: no Firestore, so they are easy to test. The assistant's `find_duplicates` read gives them the
/// records of ONE student the guide may see (the scope is applied by the read, as for every other read).
library;

/// The words of [s] that carry meaning: lower-case, at least three letters, punctuation dropped.
Set<String> _words(String s) => RegExp(r'[a-z0-9ऀ-ॿ઀-૿]{3,}').allMatches(s.toLowerCase()).map((m) => m.group(0)!).toSet();

/// 0 (nothing in common) to 1 (the same words). Two empty texts are the same (1).
double textSimilarity(String a, String b) {
  final x = _words(a);
  final y = _words(b);
  if (x.isEmpty && y.isEmpty) return 1;
  if (x.isEmpty || y.isEmpty) return 0;
  return x.intersection(y).length / x.union(y).length;
}

bool sameDay(DateTime? a, DateTime? b) => a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

bool withinDays(DateTime? a, DateTime? b, int days) => a != null && b != null && a.difference(b).inHours.abs() <= days * 24;

/// One record to compare: its id, when it is about, the words it holds, and anything else worth showing the guide.
class DupItem {
  const DupItem({required this.id, required this.when, required this.text, this.type = '', this.show = const {}});

  final String id;
  final DateTime? when;
  final String text;

  /// How it was made (call, meeting status...); two records of different types are not duplicates.
  final String type;

  /// What the model shows the guide for this record, as it is.
  final Map<String, Object?> show;
}

/// Groups of two or more records that look like the same thing entered twice: same type, close in time, and nearly the same
/// words. [days] is how close in time (0 = the same calendar day); [minSimilarity] how alike the words must be.
List<List<DupItem>> findDuplicateGroups(
  List<DupItem> items, {
  int days = 0,
  double minSimilarity = 0.5,
}) {
  final parent = List<int>.generate(items.length, (i) => i);
  int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      final a = items[i];
      final b = items[j];
      if (a.type != b.type) continue;
      final close = days == 0 ? sameDay(a.when, b.when) : withinDays(a.when, b.when, days);
      if (!close) continue;
      if (textSimilarity(a.text, b.text) < minSimilarity) continue;
      parent[find(i)] = find(j);
    }
  }
  final groups = <int, List<DupItem>>{};
  for (var i = 0; i < items.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(items[i]);
  }
  return [
    for (final g in groups.values)
      if (g.length > 1) g,
  ];
}
