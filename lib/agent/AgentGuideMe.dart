import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/AdminProfile.dart';
import '../utils/PlanData.dart';
import '../utils/PlanTopicActions.dart';
import '../utils/Snackbar.dart';
import '../widgets/RecordInteractionDialog.dart';
import 'AgentTypes.dart';

/// The assistant's two modes. GUIDE ME: it changes nothing; it answers with the shortest instruction and buttons that open the exact screen. DO IT (the
/// default): it does the task at once, in one message, with a "Done" and an Undo (only a deletion asks first).
enum AgentMode { guide, doIt }

/// The mode is remembered per admin on this device (a missing or unreadable one is "Do it").
class AgentModeStore {
  static String _key(String adminId) => 'agent_mode_$adminId';

  static Future<AgentMode> load(String adminId) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_key(adminId)) == 'guide' ? AgentMode.guide : AgentMode.doIt;
    } catch (_) {
      return AgentMode.doIt;
    }
  }

  static Future<void> save(String adminId, AgentMode m) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(adminId), m == AgentMode.guide ? 'guide' : 'do');
    } catch (_) {
      // the choice then lasts only until the app closes
    }
  }
}

int _distance(String a, String b) {
  if (a == b) return 0;
  if ((a.length - b.length).abs() > 1) return 2;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      cur.add([prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y));
    }
    prev = cur;
  }
  return prev.last;
}

List<String> _words(String s) => [for (final w in s.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) if (w.isNotEmpty) w];

/// The students of the guide's scope [students] (uid -> his user document) whose name the request mentions, allowing a typo, a first name only or a
/// different case: at most 12, the exact ones first. They go to the server with a "Guide me" request, which checks every one against the guide's scope.
List<Map<String, String>> studentCandidates(Map<String, Map<String, dynamic>> students, String text, {int max = 12}) {
  final tokens = {for (final w in _words(text)) if (w.length >= 3) w};
  if (tokens.isEmpty) return const [];
  final scored = <(int, String, String)>[];
  students.forEach((uid, u) {
    final name = (u['name'] ?? '').toString().trim();
    if (name.isEmpty) return;
    var best = 9;
    for (final n in _words(name)) {
      if (n.length < 3) continue;
      for (final t in tokens) {
        if (n == t) {
          best = 0;
        } else if (t.length >= 4 && n.length >= 4 && (n.startsWith(t) || t.startsWith(n))) {
          best = best < 1 ? best : 1;
        } else if (t.length >= 4 && n.length >= 4 && _distance(n, t) <= 1) {
          best = best < 2 ? best : 2;
        }
      }
    }
    if (best < 9) scored.add((best, name, uid));
  });
  scored.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final s in scored.take(max)) {'uid': s.$3, 'name': s.$2}];
}

/// The button's action word -> the place it opens.
TopicAction? topicActionFromWire(String wire) => switch (wire) {
      'record_interaction' => TopicAction.recordInteraction,
      'update_book' => TopicAction.updateBook,
      'assign_book' => TopicAction.assignBook,
      'change_commitment' => TopicAction.changeCommitment,
      'answer_doubt' => TopicAction.answerDoubt,
      'open_meeting' => TopicAction.openMeeting,
      'open_profile' => TopicAction.openProfile,
      _ => null,
    };

/// A Guide-me button was tapped: open the exact place for that student. The student's Today card (when he has one) gives the exact book, meeting or doubt
/// and the topics to cover; without one the place still opens for him. Nothing is changed or ticked here.
Future<void> openGuideButton(BuildContext context, GuideButton b) async {
  final action = topicActionFromWire(b.action);
  if (action == null) return;
  if (b.studentUid.isEmpty) {
    // recording an interaction without a named student: the form opens with its student picker (the guide chooses there)
    if (action == TopicAction.recordInteraction) {
      await showRecordInteractionFor(context);
      return;
    }
    showSnackbar(context, 'Tell me which student, and I will open it.', Colors.blue, Icons.info);
    return;
  }
  PlanItem? card;
  try {
    final me = AdminProfileProvider.current?.id ?? '';
    final plan = await PlanData.instance.plan(me).first.timeout(const Duration(seconds: 3));
    for (final c in plan?.todayItems ?? const <PlanItem>[]) {
      if (c.isCard && c.studentUid == b.studentUid) card = c;
    }
  } catch (_) {
    // the place still opens, without the exact record
  }
  String of(String Function(PlanPoint) pick, bool Function(PlanPoint) where) {
    for (final p in card?.points ?? const <PlanPoint>[]) {
      if (where(p) && pick(p).isNotEmpty) return pick(p);
    }
    return '';
  }

  if (!context.mounted) return;
  await runStudentAction(
    context,
    action,
    uid: b.studentUid,
    name: b.studentName,
    bookId: of((p) => p.bookId, (p) => p.kind == 'bookDue'),
    assocId: of((p) => p.assocId, (p) => p.kind == 'meeting' || p.kind == 'meeting_request'),
    doubtId: of((p) => p.doubtId, (p) => p.kind == 'doubt'),
    bookHint: b.hint,
    topics: card == null ? const [] : recordTopicsOf(card),
  );
}
