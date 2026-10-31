import 'PlanData.dart';

/// TODAY, as the Plan page shows it: three sections (Follow-ups, Target tasks, Other tasks) of TASKS, each task a student's one card (with his topics)
/// or a task of its own. Everything ticks BY ITSELF: a topic is done when the guide reported it to the assistant (or the data finished it), a task
/// when all its topics are, a section when all its tasks are. Done things stay in Today with their tick.
///
/// Worries are follow-ups: a card with a worry sits in Follow-ups, on top. Nothing here is tapped to be ticked.

/// One of the three sections.
class TodaySection {
  const TodaySection({required this.id, required this.title, required this.tasks});

  final String id;
  final String title;
  final List<PlanItem> tasks;

  int get total => tasks.length;
  int get done => tasks.where((t) => t.done).length;
  bool get allDone => total > 0 && done == total;
}

const String kSectionFollowUps = 'followups';
const String kSectionTargets = 'targets';
const String kSectionOthers = 'others';

/// The section a task belongs to: a student's card in his most important one (worries, then targets, then follow-ups, then others); a target task / phase end / deadline in Target tasks; the doubts waiting
/// in Follow-ups; everything else in Other tasks.
String todaySectionOf(PlanItem it) {
  if (it.isCard) {
    // ONE card per student with all his topics, placed by the most important: a WORRY first (Follow-ups), then anything about a TARGET (chanting, reading, a FOLK invitation: Target tasks),
    // then the other follow-ups (a doubt, a poor sadhana), then Other tasks
    final gs = it.inGroups.toSet();
    if (gs.contains(PlanGroup.worry)) return kSectionFollowUps;
    if (gs.contains(PlanGroup.target)) return kSectionTargets;
    if (gs.contains(PlanGroup.followUp)) return kSectionFollowUps;
    return kSectionOthers;
  }
  if (it.kind == 'targetTask' || it.kind == 'phaseTask' || it.kind == 'targetDeadline' || it.kind == 'targetEnded') return kSectionTargets;
  if (it.kind == 'doubtsToAnswer') return kSectionFollowUps;
  return kSectionOthers;
}

/// What counts as a task (a calendar line is information, never a task; a HOD's guide summary is not one of his tasks).
bool isTodayTask(PlanItem it) => !it.isGuideSummary && it.kind != 'calendar';

class TodayView {
  const TodayView({required this.sections, required this.information, required this.summaries});

  final List<TodaySection> sections;

  /// Calendar lines (what is on today): shown, not counted.
  final List<PlanItem> information;

  /// A HOD's summary line of each guide, below his own tasks.
  final List<PlanItem> summaries;

  int get total => sections.fold(0, (n, s) => n + s.total);
  int get done => sections.fold(0, (n, s) => n + s.done);
  int get left => total - done;

  /// "Total tasks today: 9 · Done 4 · Left 5".
  String get summaryText => 'Total tasks today: $total · Done $done · Left $left';

  TodaySection section(String id) => sections.firstWhere((s) => s.id == id);

  static TodayView of(PlanDoc? plan) {
    final items = plan?.todayItems ?? const <PlanItem>[];
    final tasks = items.where(isTodayTask).toList();
    List<PlanItem> mine(String id) {
      final list = tasks.where((i) => todaySectionOf(i) == id).toList();
      // what is still to do first, done ones below (each keeps the server's order, which is the guide's priority order)
      return [...list.where((i) => !i.done), ...list.where((i) => i.done)];
    }

    return TodayView(
      sections: [
        TodaySection(id: kSectionFollowUps, title: 'Follow-ups', tasks: mine(kSectionFollowUps)),
        TodaySection(id: kSectionTargets, title: 'Target tasks', tasks: mine(kSectionTargets)),
        TodaySection(id: kSectionOthers, title: 'Other tasks', tasks: mine(kSectionOthers)),
      ],
      information: items.where((i) => i.kind == 'calendar').toList(),
      summaries: items.where((i) => i.isGuideSummary).toList(),
    );
  }
}
