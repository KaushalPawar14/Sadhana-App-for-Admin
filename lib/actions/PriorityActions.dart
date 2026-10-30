import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/AdminProfile.dart';
import '../utils/GuideDb.dart';
import '../utils/PlanningQueries.dart';
import '../utils/StudentScope.dart';

/// The priority list, as shared logic with no screen in it: the Priority Students
/// screen and the AI agent both build the list, remove students from it and put
/// them back through these.
///
/// Every read goes through [StudentScope] / the scoped queries, so it is the
/// signed-in admin's own scope and nothing wider.

/// How loudly a concern is drawn. The screen turns it into a colour; the agent
/// ignores it.
enum PriorityTone { danger, warning, brass, brown }

/// One named concern. Deliberately carries no weight or number — a flag is either
/// present or it is not, and the guide reads the words.
///
/// `kind` names the TYPE of concern (never its wording or its day count, which
/// change daily): it is what "Remove from priority list" remembers, so a removed
/// student comes back only when a NEW kind of concern appears.
typedef PriorityFlag = ({String kind, String label, PriorityTone tone});

/// A student with at least one concern, and the concerns themselves. [percent] is his Surrender % (null: none yet), shown beside his name;
/// [distress] / [acute]: a worrying message from his AI chat (acute: it suggested real difficulty), which keeps him at the very top.
typedef PriorityStudent = ({String uid, String name, List<PriorityFlag> flags, int? percent, bool distress, bool acute});

/// How urgent a need is (lower first), the same tiers as the server's plans: a worry, a doubt, sadhana slipping, a surrender step, a target, then
/// those going well.
double priorityTierOf(String key) {
  if (key.startsWith('concern')) return 0;
  if (key.startsWith('doubt')) return 0.5;
  if (key == 'good_sadhana') return 5;
  if (key.startsWith('surrender')) return 3;
  if (key.startsWith('target')) return 4;
  return 2;
}

/// THE ORDER of the Interactions needed list (and of every list of students to interact with): SURRENDER %, HIGHEST FIRST. A worrying / distress
/// message from the AI chat stays at the very top whatever the % (an acute one first); equal % -> the more urgent reasons first, then more
/// reasons, then the name. Mirrors `functions/dailyBatch.js` `byImportance`.
int comparePriority(PriorityStudent a, PriorityStudent b) {
  if (a.distress != b.distress) return a.distress ? -1 : 1;
  if (a.distress && a.acute != b.acute) return a.acute ? -1 : 1;
  int pct(PriorityStudent s) => s.percent ?? -1;
  double tier(PriorityStudent s) => s.flags.map((f) => priorityTierOf(f.kind)).fold<double>(9, (m, t) => t < m ? t : m);
  final byPct = pct(b).compareTo(pct(a));
  if (byPct != 0) return byPct;
  final byTier = tier(a).compareTo(tier(b));
  if (byTier != 0) return byTier;
  final byCount = b.flags.length.compareTo(a.flags.length);
  return byCount != 0 ? byCount : a.name.compareTo(b.name);
}

/// What the priority list came to for the signed-in admin.
class PriorityList {
  const PriorityList({
    this.students = const [],
    this.inScope = 0,
    this.hiddenCount = 0,
    this.dismissed = const {},
    this.rosterFailed = false,
  });

  /// Students with a concern this admin has not removed, most concerns first.
  final List<PriorityStudent> students;

  /// Students this admin may see at all.
  final int inScope;

  /// Students with concerns that this admin removed and that have nothing new.
  final int hiddenCount;

  /// This admin's removals: student uid -> the concern kinds they had then.
  final Map<String, Set<String>> dismissed;

  /// The roster could not be read: nothing is shown rather than a guess.
  final bool rosterFailed;
}

/// How loudly each SOURCE of a need is drawn: a worry, then a doubt, then sadhana, then a surrender step, then a target.
PriorityTone _toneOf(String source, String key) => switch (source) {
      'concern' => PriorityTone.danger,
      'doubt' => PriorityTone.warning,
      'sadhana' => key == 'good_sadhana' ? PriorityTone.brass : PriorityTone.warning,
      'surrender' => PriorityTone.brass,
      _ => PriorityTone.brown,
    };

/// The reasons one student needs an interaction, from his `interactionNeeds` document (the server writes it from the same data the
/// plans use, so this list and the plans cannot disagree). Four sources only: the guide's targets, three days of sadhana (missed, or all
/// fulfilled), a doubt or a worrying message in his AI chat, a surrender step. Nothing else makes a student appear here.
List<PriorityFlag> priorityFlagsFromNeeds(Map<String, dynamic> doc) {
  final out = <PriorityFlag>[];
  for (final n in (doc['needs'] as List? ?? const [])) {
    if (n is! Map) continue;
    final key = (n['key'] ?? '').toString();
    final text = (n['text'] ?? '').toString();
    if (key.isEmpty || text.isEmpty) continue;
    out.add((kind: key, label: text, tone: _toneOf((n['source'] ?? '').toString(), key)));
  }
  return out;
}

/// The signed-in admin's list: every student in THEIR scope with at least one need for an interaction, minus the ones they removed and
/// that have nothing new. (Was "Priority students".)
///
/// A signal that cannot be read costs that signal, never the list; a roster that cannot be read fails closed ([PriorityList.rosterFailed]).
Future<PriorityList> loadPriorityList() async {
  final profile = AdminProfileProvider.require();
  final students = await scopedStudents();

  if (students == null) {
    // Fail closed — show nothing rather than another guide's students.
    return const PriorityList(rosterFailed: true);
  }

  // One scoped read: the server-written need documents the admin's scope allows.
  final needs = <String, Map<String, dynamic>>{};
  try {
    for (final d in (await StudentScope.current().historyGet('interactionNeeds')).docs) {
      final uid = (d.data()['studentUid'] ?? d.id).toString();
      needs[uid] = d.data();
    }
  } catch (_) {/* a missing signal must not blank the list */}

  // The students THIS admin already removed from their own list (a read failure just shows everyone).
  final dismissed = await readPriorityDismissals(profile.id);

  final result = <PriorityStudent>[];
  var hidden = 0;

  for (final student in students) {
    final doc = needs[student.uid];
    if (doc == null) continue;
    // An UNASSIGNED student's tasks (his interactions needed too) are the owning HOD's: a Guide or an Enabler still sees him on the board and may claim
    // him, and then his needs are in their list.
    if (!profile.isHod && (doc['scopeGuide'] ?? '').toString().isEmpty) continue;
    final flags = priorityFlagsFromNeeds(doc);

    // No needs means no interaction is due. Such a student is simply absent.
    if (flags.isEmpty) continue;

    // Removed by this admin, and nothing NEW has come up since: stays off their list.
    final removedKinds = dismissed[student.uid];
    if (removedKinds != null && flags.every((f) => removedKinds.contains(f.kind))) {
      hidden++;
      continue;
    }

    final needList = [for (final n in (doc['needs'] as List? ?? const [])) if (n is Map) Map<String, dynamic>.from(n)];
    final concerns = needList.where((n) => (n['source'] ?? '') == 'concern').toList();
    final p = doc['percent'];
    result.add((
      uid: student.uid,
      name: student.name,
      flags: flags,
      percent: p is num ? p.round() : null,
      distress: concerns.isNotEmpty,
      acute: concerns.any((n) => n['facts'] is Map && (n['facts'] as Map)['acute'] == true),
    ));
  }

  // Surrender %, highest first (a worry stays on top; ties: the more urgent reasons, then the name).
  result.sort(comparePriority);

  return PriorityList(
    students: result,
    inScope: students.length,
    hiddenCount: hidden,
    dismissed: dismissed,
  );
}

/// This admin's "removed from my priority list" records: student uid -> the concern
/// kinds they had then. A read failure is an empty map, so everyone shows.
Future<Map<String, Set<String>>> readPriorityDismissals(String adminId) async {
  try {
    final snap = await GuideDb.instance
        .collection('priorityDismissals')
        .where('adminId', isEqualTo: adminId)
        .get();
    return {
      for (final d in snap.docs)
        (d.data()['studentUid'] ?? '').toString(): {
          for (final k in (d.data()['kinds'] as List? ?? const [])) k.toString(),
        },
    }..remove('');
  } catch (_) {
    return {};
  }
}

/// Takes [chosen] off THIS admin's priority list. It writes one small record per
/// student (`priorityDismissals/{adminId}__{studentUid}`: adminId, studentUid,
/// kinds, dismissedAt) and nothing else: the student, their reports, chats,
/// meetings and assessments are never touched.
///
/// [chosen] carries each student's concerns AS SHOWN, because the removal
/// remembers their kinds — that is what lets a NEW kind of concern bring the
/// student back.
Future<void> removeFromPriority(List<PriorityStudent> chosen) async {
  if (chosen.isEmpty) return;
  final profile = AdminProfileProvider.require();
  final db = GuideDb.instance;
  final batch = db.batch();
  for (final p in chosen) {
    batch.set(db.collection('priorityDismissals').doc('${profile.id}__${p.uid}'), {
      'adminId': profile.id,
      'studentUid': p.uid,
      'kinds': [for (final f in p.flags) f.kind],
      'dismissedAt': FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

/// Puts the students [uids] this admin removed back on their list (deletes only
/// those small records).
Future<void> restoreToPriority(Iterable<String> uids) async {
  final profile = AdminProfileProvider.require();
  final db = GuideDb.instance;
  final batch = db.batch();
  for (final uid in uids) {
    batch.delete(db.collection('priorityDismissals').doc('${profile.id}__$uid'));
  }
  await batch.commit();
}
