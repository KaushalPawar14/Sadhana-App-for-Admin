import 'package:cloud_firestore/cloud_firestore.dart';

import 'AdminProfile.dart';
import 'GuideDb.dart';
import 'StudentScope.dart';

/// The competition categories. Hostel and Localite students compete TOGETHER in one
/// category, separate from FOLK; the server stamps `category` on every
/// `competition/{name}` document (from the student's residence), next to `gender`.
const String kCategoryFolk = 'folk';
const String kCategoryHostelLocalite = 'hostel_localite';

String categoryLabel(String category) =>
    category == kCategoryHostelLocalite ? 'Hostel & Localite' : 'FOLK';

enum LeaderboardPeriod { weekly, monthly }

/// What the leaderboard says when a ranking has nobody in it. FOLK girls: there are none (girls
/// stay at the Hostel or are Localite), so "No students in this group yet"; every other group
/// names itself: "No scores yet for Hostel & Localite boys this week".
String leaderboardEmptyMessage({
  required String category,
  required String gender,
  required LeaderboardPeriod period,
}) {
  if (category == kCategoryFolk && gender == 'female') return 'No students in this group yet.';
  final who = gender == 'female' ? 'girls' : 'boys';
  final when = period == LeaderboardPeriod.weekly ? 'this week' : 'this month';
  return 'No scores yet for ${categoryLabel(category)} $who $when.';
}

extension LeaderboardPeriodX on LeaderboardPeriod {
  String get label => this == LeaderboardPeriod.weekly ? 'This week' : 'This month';

  /// The literal (dotted) field names on `competition/{name}`; they are flat
  /// top-level fields, not a nested map.
  String get scoreField => this == LeaderboardPeriod.weekly ? 'weekly.total_score' : 'monthly.total_score';
  String get daysField => this == LeaderboardPeriod.weekly ? 'weekly.days_count' : 'monthly.days_count';
}

/// One student's standing in one ranking.
class LeaderboardEntry {
  const LeaderboardEntry({required this.name, required this.score, required this.days});

  final String name;
  final double score;
  final int days;
}

/// A field named with a dot, e.g. `weekly.total_score`. In the real database it is a
/// flat top-level field with a literal dotted name (written by `set` with a merge);
/// a nested `weekly: {total_score}` map is accepted too, so either shape reads right.
Object? dottedField(Map<String, dynamic> data, String name) {
  if (data.containsKey(name)) return data[name];
  final dot = name.indexOf('.');
  if (dot < 0) return null;
  final nested = data[name.substring(0, dot)];
  return nested is Map ? nested[name.substring(dot + 1)] : null;
}

/// The ranked entries of one period, best first. A student with no score and no
/// reported day in the period is not ranked (a quiet student is not "last", they
/// simply have no result yet). Ties are ordered by name so the order is stable.
List<LeaderboardEntry> rankCompetition(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  LeaderboardPeriod period,
) {
  double num0(Object? v) => v is num ? v.toDouble() : 0;
  final out = <LeaderboardEntry>[];
  for (final d in docs) {
    final data = d.data();
    final score = num0(dottedField(data, period.scoreField));
    final days = num0(dottedField(data, period.daysField)).toInt();
    if (score <= 0 && days <= 0) continue;
    final named = (data['Name'] ?? '').toString().trim();
    out.add(LeaderboardEntry(name: named.isEmpty ? d.id : named, score: score, days: days));
  }
  out.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

/// One of the two weekly Best performer winners of a ranking (decided on the server,
/// `functions/bestPerformers.js`).
class BestWinnerInfo {
  const BestWinnerInfo({required this.name, required this.reason, required this.inScope});

  final String name;

  /// The short reason: "+24 points vs last week" / "kept 16 rounds on 6 of 7 days".
  final String reason;

  /// Whether the winner is one of THIS admin's students (their team, their own, or an
  /// unassigned student of their gender); the HOD's scope is everyone.
  final bool inScope;
}

/// The two winners of one category (for the viewed gender) in the latest finalised week.
class BestPerformerSet {
  const BestPerformerSet({this.mostImproved, this.commitmentKeeper});

  final BestWinnerInfo? mostImproved;
  final BestWinnerInfo? commitmentKeeper;

  bool get hasWinner => mostImproved != null || commitmentKeeper != null;
}

/// Whether a student with this assignment is within [profile]'s scope. The same rule as
/// `StudentScope`: HOD all; Guide his team and the unassigned boys; Enabler their own and
/// the unassigned of their gender.
bool winnerInScope(AdminProfile profile, {required String scopeGuide, required String scopeTeam, required String gender}) {
  if (profile.isHod) return true;
  final unassignedOfMine = scopeGuide.isEmpty && gender == profile.gender;
  if (profile.isGuide) return scopeTeam == profile.id || unassignedOfMine;
  return scopeGuide == profile.id || unassignedOfMine;
}

BestWinnerInfo? parseBestWinner(Object? raw, AdminProfile profile, String gender) {
  if (raw is! Map) return null;
  final name = (raw['name'] ?? '').toString().trim();
  if (name.isEmpty) return null;
  return BestWinnerInfo(
    name: name,
    reason: (raw['reason'] ?? '').toString().trim(),
    inScope: winnerInScope(
      profile,
      scopeGuide: (raw['scopeGuide'] ?? '').toString(),
      scopeTeam: (raw['scopeTeam'] ?? '').toString(),
      gender: gender,
    ),
  );
}

/// Everything the Leaderboard screen reads, behind one interface (the app uses the
/// Firestore-backed one; a widget test can hand in plain values).
abstract class LeaderboardData {
  static LeaderboardData instance = const FirestoreLeaderboardData();

  /// The ranking of [category] and [gender] for [period] among the students the
  /// signed-in admin may see.
  Future<List<LeaderboardEntry>> ranking({
    required String category,
    required String gender,
    required LeaderboardPeriod period,
  });

  /// The latest week's two winners for [gender], per category (`folk`, `hostel_localite`).
  /// A category with no results is absent from the map.
  Future<Map<String, BestPerformerSet>> bestPerformers({required String gender});
}

class FirestoreLeaderboardData implements LeaderboardData {
  const FirestoreLeaderboardData();

  @override
  Future<List<LeaderboardEntry>> ranking({
    required String category,
    required String gender,
    required LeaderboardPeriod period,
  }) async {
    // The admin's own scope (HOD all; Guide his team + unassigned boys; an Enabler
    // his own + unassigned of his gender) PLUS the category and gender asked for:
    // equality filters only, so the security rules can prove every query.
    final snap = await StudentScope.current().historyGet(
      'competition',
      extraEquals: {'category': category, 'gender': gender},
    );
    return rankCompetition(snap.docs, period);
  }

  @override
  Future<Map<String, BestPerformerSet>> bestPerformers({required String gender}) async {
    final profile = AdminProfileProvider.require();
    final weeks = await GuideDb.instance
        .collection('competition-results')
        .doc('weekly')
        .collection('weeks')
        .orderBy('generatedAt', descending: true)
        .limit(1)
        .get();
    final out = <String, BestPerformerSet>{};
    if (weeks.docs.isEmpty) return out;
    for (final category in [kCategoryFolk, kCategoryHostelLocalite]) {
      // The rules let an admin read the rankings of THEIR gender only.
      final snap = await weeks.docs.first.reference.collection('byCategory').doc('${category}_$gender').get();
      final data = snap.data();
      if (data == null) continue;
      out[category] = BestPerformerSet(
        mostImproved: parseBestWinner(data['mostImproved'], profile, gender),
        commitmentKeeper: parseBestWinner(data['commitmentKeeper'], profile, gender),
      );
    }
    return out;
  }
}
