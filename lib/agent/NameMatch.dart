/// Close-name matching for the assistant: a name typed or dictated with a slip (a letter more or less, only the first name, a nickname's
/// ending, different case, extra spaces or digits - "Manan21", "mananjit" for "Mananjeet") finds the student the guide means.
///
/// Pure and deterministic. It runs ONLY over names the guide may already see (the caller passes the scoped list), so nothing outside
/// the scope can ever be suggested.
library;

/// The name as it is compared: lower case, letters only (digits, dots, dashes, extra spaces dropped), single spaces.
String normaliseName(String s) {
  final letters = s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\s]', unicode: true), ' ');
  return letters.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).join(' ');
}

/// Edit distance counting a swap of two neighbouring letters as one edit.
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final d = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost].reduce((x, y) => x < y ? x : y);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        final t = d[i - 2][j - 2] + 1;
        if (t < v) v = t;
      }
      d[i][j] = v;
    }
  }
  return d[a.length][b.length];
}

/// Vowels that read alike are folded, so "Mananjit" and "Mananjeet" (ee/i, oo/u, ph/f, w/v) compare as the same sound.
String soundKey(String s) {
  var k = s
      .replaceAll('ph', 'f')
      .replaceAll('w', 'v')
      .replaceAll('z', 'j')
      .replaceAll('ee', 'i')
      .replaceAll('ii', 'i')
      .replaceAll('oo', 'u')
      .replaceAll('uu', 'u')
      .replaceAll('ey', 'i')
      .replaceAll('y', 'i')
      .replaceAll('aa', 'a')
      .replaceAll('kh', 'k')
      .replaceAll('gh', 'g')
      .replaceAll('th', 't')
      .replaceAll('dh', 'd')
      .replaceAll('sh', 's');
  k = k.replaceAll(RegExp(r'(.)\1+'), r'$1'); // double letters
  return k;
}

/// How many edits a word of this length may be off by and still be "the same name".
int _allowed(int len) => len <= 3 ? 0 : (len <= 6 ? 1 : 2);

/// 0..1: how well one typed word matches one word of a name (0 = not at all).
double _wordScore(String q, String w) {
  if (q == w) return 1;
  if (q.length >= 3 && w.startsWith(q)) return 0.92; // "manan" for "mananjeet"
  if (w.length >= 3 && q.startsWith(w) && q.length - w.length <= 2) return 0.9; // a letter or two too many
  final qs = soundKey(q);
  final ws = soundKey(w);
  if (qs == ws && qs.length >= 3) return 0.9;
  final len = q.length < w.length ? q.length : w.length;
  final allowed = _allowed(len);
  if (allowed == 0) return 0;
  final dist = editDistance(q, w);
  final dist2 = editDistance(qs, ws);
  final best = dist < dist2 ? dist : dist2;
  if (best <= allowed) return 0.85 - 0.1 * (best - 1).clamp(0, 5) - (q[0] == w[0] ? 0 : 0.1);
  if (qs.length >= 4 && ws.startsWith(qs)) return 0.8;
  return 0;
}

/// How well [query] matches [name], 0..1. Every typed word must find a word of the name (in any order); the score is their average.
/// A name with only its first word typed counts fully; a typed word that matches nothing makes the whole name not match.
double nameScore(String query, String name) {
  final q = normaliseName(query).split(' ').where((t) => t.isNotEmpty).toList();
  final words = normaliseName(name).split(' ').where((t) => t.isNotEmpty).toList();
  if (q.isEmpty || words.isEmpty) return 0;

  var total = 0.0;
  for (final t in q) {
    var best = 0.0;
    for (final w in words) {
      final s = _wordScore(t, w);
      if (s > best) best = s;
    }
    if (best == 0) {
      // run together or split apart: "manan jit" vs "mananjit"
      final whole = _wordScore(q.join(), words.join());
      return whole;
    }
    total += best;
  }
  return total / q.length;
}

/// A student a typed name may mean.
class NameMatch<T> {
  const NameMatch(this.item, this.score);
  final T item;
  final double score;
}

/// The names that are not an exact match but are close, best first. Returns nothing at all when [query] already matches a name
/// exactly (every typed word is part of the name, which the plain search handles), so a correct name never triggers a question.
///
/// [minScore]: 0.6 keeps "Did you mean" to genuinely close names.
List<NameMatch<T>> closeNames<T>(String query, Iterable<T> items, String Function(T) nameOf, {double minScore = 0.6, int max = 6}) {
  final out = <NameMatch<T>>[];
  for (final it in items) {
    final s = nameScore(query, nameOf(it));
    if (s >= minScore) out.add(NameMatch(it, s));
  }
  out.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : nameOf(a.item).toLowerCase().compareTo(nameOf(b.item).toLowerCase());
  });
  return out.take(max).toList();
}

/// One clear best match (it leads the next by a margin), so the assistant asks a single "Did you mean X?" instead of a list.
bool hasClearBest<T>(List<NameMatch<T>> ms, {double margin = 0.08}) {
  if (ms.isEmpty) return false;
  if (ms.length == 1) return true;
  return ms[0].score - ms[1].score >= margin;
}
