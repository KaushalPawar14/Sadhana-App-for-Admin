import 'GuideDb.dart';

/// A student's SURRENDER % — for guides and HODs only; students never see it. Worked out daily by the server (`functions/surrender.js`,
/// weights in one config there) from his commitment (20%), the sadhana he actually did (40%), association with his guide (15%), his
/// attitude and willingness (15%) and his LIT (10%); a student not living in FOLK is held at 90%; a part with nothing to judge is
/// "not enough data" and never counts as failure. The board card shows the bar; a tap shows each part, with its reason.
class SurrenderPart {
  const SurrenderPart({required this.key, required this.label, required this.weight, required this.score, required this.reason, this.effectiveWeight});

  final String key;
  final String label;

  /// The part's weight in the percent (20 / 40 / 15 / 15 / 10).
  final int weight;

  /// 0..1, or null: not enough data (the part is left out, never counted as a failure).
  final double? score;
  final String reason;

  /// What the part counts for once the parts without data are left out and the others scaled up (null for a part that is left out).
  final double? effectiveWeight;

  static SurrenderPart? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = (raw['key'] ?? '').toString();
    if (key.isEmpty) return null;
    final s = raw['score'];
    final w = raw['weight'];
    return SurrenderPart(
      key: key,
      label: (raw['label'] ?? key).toString(),
      weight: w is num ? w.round() : 0,
      score: s is num ? s.toDouble().clamp(0.0, 1.0) : null,
      reason: (raw['reason'] ?? '').toString(),
      effectiveWeight: raw['effectiveWeight'] is num ? (raw['effectiveWeight'] as num).toDouble() : null,
    );
  }
}

class SurrenderInfo {
  const SurrenderInfo({required this.percent, required this.trend, required this.parts, required this.cap, required this.complete, required this.residence, this.noData = false});

  /// 0..100.
  final int percent;

  /// The change against about a week ago (null before a week of days).
  final int? trend;
  final List<SurrenderPart> parts;

  /// 'residence' (not living in FOLK: at most 90%), 'incomplete' (not everything is known: at most 95%), or null.
  final String? cap;
  final bool complete;
  final String residence;

  /// Truly no sadhana reports and no commitment: there is no percent yet (the breakdown still says why each part is missing).
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
