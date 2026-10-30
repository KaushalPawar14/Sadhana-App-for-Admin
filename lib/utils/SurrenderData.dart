import 'GuideDb.dart';

/// A student's SURRENDER % — for guides and HODs only; students never see it. Worked out daily by the server (`functions/surrender.js`,
/// weights in one config there) from his commitment (10%), the sadhana he actually did (40%: four equal pieces of 10 from the daily report forms, the last
/// 30 days: reporting regularity, chanting, reading, timings), association with his guide (20%), his
/// attitude and willingness (10%) and his LIT (20%); a student not living in FOLK is held at 90%. NO FREE MARKS: a part with nothing to
/// show yet scores 0 and the others are not scaled up. The board card shows the bar; a tap shows each part, its points earned of the
/// points possible, and its reason.
class SurrenderPart {
  const SurrenderPart({required this.key, required this.label, required this.weight, required this.score, required this.reason, this.effectiveWeight, this.points, this.missing = false, this.sub = const []});

  final String key;
  final String label;

  /// The part's weight in the percent = the points possible (commitment 10, sadhana 40, association — attitude & willingness 20, LIT 20, bonus 10); a bonus piece 2.5.
  final double weight;

  /// 0..1 (a part with nothing to show yet is 0). Null only in a record written before the new weights.
  final double? score;
  final String reason;

  /// Kept for old records (the weight a part counted for once the others were scaled up); the server no longer scales.
  final double? effectiveWeight;

  /// The points earned (0..[weight]); [missing]: nothing to show yet, so it earned 0.
  final double? points;
  final bool missing;

  /// The BONUS part is four pieces of 2.5 (extraordinary chanting, extraordinary reading, chanting above his commitment, reading above it), shown the same way.
  /// The Sadhana part is FOUR EQUAL PIECES of 10 (reporting regularity, chanting, reading, timings), each with its points and reason ("Reported 3 of 30 days → 1 of 10").
  /// Empty for the other parts and for a record written before the pieces.
  final List<SurrenderPart> sub;

  /// The points earned: the server's own figure, else the score times the weight.
  double get earned => points ?? ((score ?? 0) * weight);

  static SurrenderPart? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = (raw['key'] ?? '').toString();
    if (key.isEmpty) return null;
    final s = raw['score'];
    final w = raw['weight'];
    return SurrenderPart(
      key: key,
      label: (raw['label'] ?? key).toString(),
      weight: w is num ? w.toDouble() : 0,
      score: s is num ? s.toDouble().clamp(0.0, 1.0) : null,
      reason: (raw['reason'] ?? '').toString(),
      effectiveWeight: raw['effectiveWeight'] is num ? (raw['effectiveWeight'] as num).toDouble() : null,
      points: raw['points'] is num ? (raw['points'] as num).toDouble() : null,
      missing: raw['missing'] == true,
      sub: [
        for (final e in (raw['sub'] as List? ?? const []))
          if (SurrenderPart.fromMap(e) case final p?) p,
      ],
    );
  }
}

class SurrenderInfo {
  const SurrenderInfo({required this.percent, required this.trend, required this.parts, required this.cap, required this.complete, required this.residence, this.noData = false, this.gender = '', this.name = ''});

  /// The student's gender and name, so the notes about him or her say the right words (the server writes them with the record).
  final String gender;
  final String name;

  /// 0..100.
  final int percent;

  /// The change against about a week ago (null before a week of days).
  final int? trend;
  final List<SurrenderPart> parts;

  /// 'residence' (not living in FOLK: at most 90%), 'incomplete' (not everything is known: at most 95%), or null.
  final String? cap;
  final bool complete;
  final String residence;

  /// Only an old record (before the new weights) can say "no percent yet"; the server now always gives a number.
  final bool noData;

  /// The stage he is in (each 10% step has its own focus).
  String get stage => surrenderStageOf(percent);

  static SurrenderInfo? fromDoc(Map<String, dynamic>? d) {
    if (d == null) return null;
    final p = d['percent'];
    final noData = d['noData'] == true && p is! num;
    if (p is! num && !noData) return null;
    final t = d['trend'];
    return SurrenderInfo(
      noData: noData,
      gender: (d['studentGender'] ?? '').toString(),
      name: (d['studentName'] ?? '').toString(),
      percent: p is num ? p.round().clamp(0, 100) : 0,
      trend: t is num ? t.round() : null,
      parts: [
        for (final e in (d['parts'] as List? ?? const []))
          if (SurrenderPart.fromMap(e) case final part?) part,
      ],
      cap: d['cap']?.toString(),
      complete: d['complete'] == true,
      residence: (d['residence'] ?? '').toString(),
    );
  }
}

/// The six stages (the server holds the full focus and the questions): 0–10 start, 10–30 consistency, 30–50 deepen, 50–70 commit,
/// 70–90 strict sadhana, 90–100 surrender.
String surrenderStageOf(int percent) {
  if (percent < 10) return 'Start';
  if (percent < 30) return 'Consistency';
  if (percent < 50) return 'Deepen';
  if (percent < 70) return 'Commit';
  if (percent < 90) return 'Strict sadhana';
  return 'Surrender';
}

/// Live: one student's Surrender % (null until the server has worked it out).
Stream<SurrenderInfo?> studentSurrenderStream(String studentUid) =>
    GuideDb.instance.collection('studentSurrender').doc(studentUid).snapshots().map((d) => SurrenderInfo.fromDoc(d.data()));

/// Reads for tests / callers that only need the document's map.
Future<SurrenderInfo?> readSurrender(String studentUid) async =>
    SurrenderInfo.fromDoc((await GuideDb.instance.collection('studentSurrender').doc(studentUid).get()).data());
