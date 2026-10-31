import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Home/Calendar.dart';
import 'GoalCompoundQueries.dart';
import '../actions/AssociationActions.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideMeta.dart';
import '../Services/HierarchyApi.dart';
import 'Snackbar.dart';
import '../Pages/AssociationManager.dart';
import '../Pages/LitAssessment.dart';
import '../Pages/StudentDoubtsPage.dart';
import '../Pages/StudentProfilePage.dart';
import '../widgets/RecordInteractionDialog.dart';
import '../widgets/StudentCommitmentsCard.dart';
import 'PlanData.dart';

/// TODAY'S ACTION BUTTONS: every open topic on a student's card has ONE button that opens the exact place where the guide does it by hand. The
/// button never ticks anything: the topic is ticked by itself ONLY when the real record has been saved there (the interaction, the book, the
/// commitment, the answer, the meeting) and the server has seen it.
enum TopicAction { updateBook, assignBook, changeCommitment, openProfile, answerDoubt, openMeeting, recordInteraction, setLit }

const Map<TopicAction, String> kTopicActionLabels = {
  TopicAction.updateBook: 'Update book',
  TopicAction.assignBook: 'Assign book',
  TopicAction.changeCommitment: 'Change commitment',
  TopicAction.openProfile: 'Open profile',
  TopicAction.answerDoubt: 'Answer doubt',
  TopicAction.openMeeting: 'Open meeting',
  TopicAction.recordInteraction: 'Record interaction',
  TopicAction.setLit: 'Set LIT',
};

/// The button of one line inside the Surrender check: a missing LIT -> Set LIT; no interaction / attitude yet -> Record interaction; none for "no reports" (he has to
/// file them). Null for a point to discuss.
TopicAction? subActionOf(PlanSub x) => switch (x.kind) {
      'gap_lit' => TopicAction.setLit,
      'gap_interaction' || 'gap_attitude' => TopicAction.recordInteraction,
      _ => null,
    };

/// The one button of a topic, by what the topic is about.
TopicAction topicActionOf(PlanPoint p) {
  switch (p.kind) {
    case 'bookDue':
      return TopicAction.updateBook;
    case 'doubt':
      return TopicAction.answerDoubt;
    case 'meeting':
    case 'meeting_request':
      return TopicAction.openMeeting;
    case 'target_chanting':
      return TopicAction.changeCommitment;
    case 'target_books':
      return TopicAction.assignBook;
    case 'target_folk':
      return TopicAction.openProfile;
    case 'target_task':
      return switch (p.metric) {
        'chanting' => TopicAction.changeCommitment,
        'books' => TopicAction.assignBook,
        'folk' => TopicAction.openProfile,
        _ => TopicAction.recordInteraction,
      };
    default:
      // a worry, a streak, his sadhana, his daily report / timings, a Surrender step, his next step: all of them are talked about
      return TopicAction.recordInteraction;
  }
}

/// The open topics of a card that are done by recording an interaction (the checkboxes of the Record-interaction form).
List<PlanPoint> recordTopicsOf(PlanItem card) => [for (final p in card.points) if (!p.done && p.kind.isNotEmpty && topicActionOf(p) == TopicAction.recordInteraction) p];

/// The page a button opens, as a route's name (tests and logs read it) and its widget. Null for the buttons that open a dialog.
class TopicDestination {
  const TopicDestination(this.name, this.page);
  final String name;
  final Widget page;
}

/// The page [action] opens for this student, or null when it opens a dialog. [bookId] / [assocId] / [doubtId] point at the exact record when known.
TopicDestination? destinationFor(TopicAction action, {required String uid, required String name, String bookId = '', String assocId = '', String doubtId = '', String bookHint = ''}) {
  switch (action) {
    case TopicAction.updateBook:
      return TopicDestination(
        'topic:updateBook',
        CalendarPage(
          username: name,
          role: '',
          studentUid: uid,
          startOnBooks: true,
          focusBookDocId: bookId,
          booksHint: bookHint.isEmpty ? 'Mark it finished (the circle), or tap the book to set a new due date.' : 'Find "$bookHint": mark it finished (the circle), or tap it to set a new due date.',
        ),
      );
    case TopicAction.assignBook:
      return TopicDestination(
        'topic:assignBook',
        CalendarPage(username: name, role: '', studentUid: uid, startOnBooks: true, openAllBookLevels: true, booksHint: 'Tap a book to assign it, with a finish-by date.'),
      );
    case TopicAction.openProfile:
      return TopicDestination('topic:openProfile', StudentProfilePage(studentUid: uid));
    case TopicAction.answerDoubt:
      return TopicDestination('topic:answerDoubt', StudentDoubtsPage(openDoubtId: doubtId.isEmpty ? null : doubtId));
    case TopicAction.openMeeting:
      return TopicDestination('topic:openMeeting', AssociationManagerPage(highlightAssociationId: assocId.isEmpty ? null : assocId));
    case TopicAction.changeCommitment:
    case TopicAction.recordInteraction:
    case TopicAction.setLit:
      return null;
  }
}

/// The page a Today topic's button opens for this topic of this student's card, or null when it opens a dialog.
TopicDestination? topicDestinationOf(PlanItem card, PlanPoint p) =>
    destinationFor(topicActionOf(p), uid: card.studentUid, name: card.studentName, bookId: p.bookId, assocId: p.assocId, doubtId: p.doubtId);

/// Opens the place for [action] and a student: a page is pushed, a dialog opens. Nothing is ticked here.
Future<void> runStudentAction(BuildContext context, TopicAction action, {required String uid, required String name, String bookId = '', String assocId = '', String doubtId = '', String bookHint = '', List<PlanPoint> topics = const []}) async {
  final dest = destinationFor(action, uid: uid, name: name, bookId: bookId, assocId: assocId, doubtId: doubtId, bookHint: bookHint);
  if (dest != null) {
    await Navigator.of(context).push(MaterialPageRoute<void>(settings: RouteSettings(name: dest.name), builder: (_) => dest.page));
    return;
  }
  if (action == TopicAction.changeCommitment) {
    await editStudentCommitments(context, studentUid: uid, studentName: name);
    return;
  }
  if (action == TopicAction.setLit) {
    await openLitAssessmentSheet(context: context, studentUid: uid, studentName: name);
    return;
  }
  await showRecordInteractionFor(context, studentUid: uid, studentName: name, topics: topics);
}

/// Runs the button of [p] on [card] (Today).
Future<void> runTopicAction(BuildContext context, PlanItem card, PlanPoint p) => runStudentAction(
      context,
      topicActionOf(p),
      uid: card.studentUid,
      name: card.studentName,
      bookId: p.bookId,
      assocId: p.assocId,
      doubtId: p.doubtId,
      topics: recordTopicsOf(card),
    );

/// A confirmed meeting whose day has passed without "Completed" (see [PlanPoint.late]): its topic has TWO buttons, Completed and Cancelled.
bool isUnmarkedMeeting(PlanPoint p) => p.kind == 'meeting' && p.late && !p.done && p.assocId.isNotEmpty;

/// "Completed": the guide's notes, then the meeting is completed exactly as in the meeting manager (a held meeting counts as an interaction; the server ticks the topic).
Future<void> runMeetingCompleted(BuildContext context, PlanItem card, PlanPoint p) async {
  var notes = '';
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => GuideDialog(
      title: const Text('Meeting completed', key: ValueKey('plan-meeting-completed-title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('plan-meeting-notes'),
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'What was discussed (only you see this)'),
            onChanged: (v) => notes = v,
          ),
        ],
      ),
      actions: [
        TextButton(key: const ValueKey('plan-meeting-completed-no'), onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        ElevatedButton(
          key: const ValueKey('plan-meeting-completed-save'),
          style: ElevatedButton.styleFrom(backgroundColor: dialogContext.g.brass),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text('Save', style: TextStyle(color: dialogContext.g.onPrimary)),
        ),
      ],
    ),
  );
  if (saved != true) return;
  try {
    await completeMeeting(p.assocId, notes: notes);
    if (context.mounted) showSnackbar(context, 'Meeting completed', Colors.blue, Icons.check_circle);
  } catch (_) {
    if (context.mounted) showSnackbar(context, 'Could not save', Colors.red, Icons.error);
  }
}

/// "Cancelled": after a confirmation the meeting is deleted and the student told, exactly as in the meeting manager; the topic goes.
Future<void> runMeetingCancelled(BuildContext context, PlanItem card, PlanPoint p) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => GuideDialog(
      title: const Text('Cancel this meeting?', key: ValueKey('plan-meeting-cancelled-title')),
      content: Text('The meeting with ${card.studentName} will be deleted completely and the student told.'),
      actions: [
        TextButton(key: const ValueKey('plan-meeting-cancelled-no'), onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
        TextButton(key: const ValueKey('plan-meeting-cancelled-yes'), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete meeting')),
      ],
    ),
  );
  if (yes != true) return;
  try {
    await cancelAndDeleteMeeting(p.assocId, studentUid: card.studentUid);
    if (context.mounted) showSnackbar(context, 'Meeting cancelled and deleted', Colors.orange, Icons.cancel);
  } catch (_) {
    if (context.mounted) showSnackbar(context, 'Could not cancel', Colors.red, Icons.error);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------
// LATER: postpone a topic to a chosen date

/// The key the server knows a postponable topic by (`topicLater.js`), or null for a topic that cannot be postponed: a meeting (it is rescheduled in the meeting itself), a topic with
/// nothing to name it, a topic that is already done.
String? laterKeyOf(PlanPoint p) {
  if (p.done) return null;
  switch (p.kind) {
    case 'bookDue':
      return p.bookId.isEmpty ? null : 'bookDue:${p.bookId}';
    case 'target_chanting':
    case 'target_books':
    case 'target_folk':
      return 'target:${p.kind.substring(7)}';
    case 'target_task':
      return p.metric.isEmpty ? null : 'target:${p.metric}';
    case 'concern':
    case 'doubt':
    case 'sadhana_slip':
    case 'reporting_habit':
    case 'discipline_habit':
    case 'surrender':
    case 'good_sadhana':
    case 'festival_boost':
    case 'surrender_check':
      return p.kind;
    default:
      return null; // meetings, requests, a follow-up that already came back from Later ...
  }
}

/// Whether the topic gets the second button, "Later".
bool isPostponable(PlanPoint p) => laterKeyOf(p) != null;

/// The quick choices of the Later panel, from [today]: tomorrow, next week (7 days on), next month (the same day), the middle of next month (the 15th). A custom date is chosen on top of these.
List<(String, String, DateTime)> laterQuickPicks(DateTime today) {
  final d = DateTime(today.year, today.month, today.day);
  DateTime inMonth(int day) {
    final first = DateTime(d.year, d.month + 1, 1);
    final last = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, day > last ? last : day);
  }

  return [
    ('tomorrow', 'Tomorrow', d.add(const Duration(days: 1))),
    ('week', 'Next week', d.add(const Duration(days: 7))),
    ('month', 'Next month', inMonth(d.day)),
    ('mid', 'Mid next month', inMonth(15)),
  ];
}

/// "YYYY-MM-DD".
String laterDayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Replaces the date picker of the Custom choice (tests).
@visibleForTesting
Future<DateTime?> Function(BuildContext context, DateTime first)? debugLaterDatePicker;

/// Today's date for the quick picks (tests).
@visibleForTesting
DateTime Function() laterClock = DateTime.now;

/// What a topic is called in the panel ("Raise to 12 rounds").
String laterTopicName(PlanPoint p) => p.title.isNotEmpty ? p.title : p.text;

/// The LATER panel of one topic: a date (tomorrow, next week, next month, mid next month, or a chosen day), an optional note, and Postpone. When the date is after the end of the target
/// the topic belongs to, it says so ("He will be removed from this target."). Postponing saves nothing in the student's history; the topic leaves Today now and returns on the date.
/// Returns the server's answer, or null when the guide cancelled.
Future<Map<String, dynamic>?> showLaterPanel(BuildContext context, PlanItem card, PlanPoint p) async {
  final key = laterKeyOf(p);
  if (key == null) return null;
  final picks = laterQuickPicks(laterClock());
  String? chosen; // a quick pick's id, or 'custom'
  DateTime? date;
  var note = '';
  var busy = false;
  String? error;
  Map<String, dynamic>? answer;
  final end = DateTime.tryParse(p.targetEnd);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final after = date != null && end != null && DateTime(date!.year, date!.month, date!.day).isAfter(DateTime(end.year, end.month, end.day));
        final t = Theme.of(context).textTheme;
        Widget chip(String id, String label, DateTime? d) => GuideChoiceChip(
              key: ValueKey('later-pick-$id'),
              label: label,
              selected: chosen == id,
              onSelected: busy
                  ? null
                  : (_) async {
                      if (id == 'custom') {
                        final first = DateTime(laterClock().year, laterClock().month, laterClock().day + 1);
                        final picker = debugLaterDatePicker;
                        final got = picker != null
                            ? await picker(context, first)
                            : await showDatePicker(context: context, initialDate: date ?? first, firstDate: first, lastDate: DateTime(first.year + 20, first.month, first.day));
                        if (got == null) return;
                        setState(() {
                          chosen = 'custom';
                          date = got;
                        });
                      } else {
                        setState(() {
                          chosen = id;
                          date = d;
                        });
                      }
                    },
            );
        return GuideDialog(
          title: const Text('Later', key: ValueKey('later-title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${card.studentName}: ${laterTopicName(p)}', key: const ValueKey('later-topic'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text('It leaves Today now and comes back on the day you choose.', key: ValueKey('later-hint')),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, children: [for (final q in picks) chip(q.$1, q.$2, q.$3), chip('custom', 'Choose a date', null)]),
                if (date != null) ...[
                  const SizedBox(height: 8),
                  Text(DateFormat('EEEE d MMMM yyyy').format(date!), key: const ValueKey('later-date'), style: t.bodyMedium),
                ],
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('later-note'),
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: const InputDecoration(hintText: 'A note for that day (optional): He will move to 12 rounds by mid-November'),
                  onChanged: (v) => note = v,
                ),
                if (after) ...[
                  const SizedBox(height: 6),
                  Text('This is after your target ends (${DateFormat('d MMM yyyy').format(end)}). He will be removed from this target.', key: const ValueKey('later-after-target'), style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
                ],
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(error!, key: const ValueKey('later-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(key: const ValueKey('later-cancel'), onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              key: const ValueKey('later-postpone'),
              style: ElevatedButton.styleFrom(backgroundColor: dialogContext.g.brass),
              onPressed: date == null || busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        answer = await HierarchyApi.instance.postponeTopic(
                          studentUid: card.studentUid,
                          key: key,
                          date: laterDayKey(date!),
                          note: note,
                          label: '',
                          to: p.to,
                          bookTitle: p.bookTitle.isEmpty ? null : p.bookTitle,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        setState(() {
                          busy = false;
                          error = 'Could not postpone: ${e is HierarchyException ? e.message : e}';
                        });
                      }
                    },
              child: Text(after ? 'Postpone and remove from the target' : 'Postpone', style: TextStyle(color: dialogContext.g.onPrimary)),
            ),
          ],
        );
      },
    ),
  );
  if (answer != null && context.mounted) showSnackbar(context, (answer!['message'] ?? 'Postponed.').toString(), Colors.blue, Icons.schedule);
  return answer;
}

// ---------------------------------------------------------------------------------------------------------------------------------
// "TARGET ENDED": delete the target, or extend its end date

/// What the two buttons of a "Target ended" topic do (tests replace them: the real ones call the same functions the target screens use).
class TargetEndActions {
  TargetEndActions({required this.delete, required this.extend});

  /// Deletes the target with its phases and tasks (`callDeleteCompoundTarget`, as the target's own delete does).
  final Future<void> Function(String guideId, String targetId) delete;

  /// Moves the end date, then plans the remaining students and phases again at once (phases never more than the weeks left).
  final Future<void> Function(String guideId, String targetId, DateTime endDate, String note) extend;

  static TargetEndActions instance = TargetEndActions(
    delete: (guideId, targetId) => callDeleteCompoundTarget(guideId: guideId, targetId: targetId).then((_) {}),
    extend: (guideId, targetId, endDate, note) async {
      await updateTargetEndDate(guideId: guideId, targetId: targetId, endDate: endDate);
      await callRegenerateCompoundPlan(guideId: guideId, targetId: targetId, note: note);
    },
  );
}

/// Whether a Today item is a "Target ended" topic that still waits for the guide's choice.
bool isEndedTarget(PlanItem it) => it.kind == 'targetEnded' && !it.done && it.targetId.isNotEmpty;

/// "Delete target": after a confirmation the target is deleted with its phases and tasks; the topic goes with it.
Future<void> runDeleteEndedTarget(BuildContext context, String guideId, PlanItem it) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => GuideDialog(
      title: const Text('Delete this target?', key: ValueKey('target-delete-title')),
      content: const Text('The target is deleted with its phases and tasks. The students and their numbers stay as they are.'),
      actions: [
        TextButton(key: const ValueKey('target-delete-no'), onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
        TextButton(key: const ValueKey('target-delete-yes'), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete target')),
      ],
    ),
  );
  if (yes != true) return;
  try {
    await TargetEndActions.instance.delete(guideId, it.targetId);
    if (context.mounted) showSnackbar(context, 'Target deleted', Colors.orange, Icons.delete_outline);
  } catch (e) {
    if (context.mounted) showSnackbar(context, 'Could not delete the target', Colors.red, Icons.error);
  }
}

/// Replaces the date picker of "Extend end date" (tests).
@visibleForTesting
Future<DateTime?> Function(BuildContext context, DateTime first)? debugEndDatePicker;

/// "Extend end date": pick the new end date (after today); the target continues and a new plan is made at once for the remaining students and phases.
Future<void> runExtendEndedTarget(BuildContext context, String guideId, PlanItem it) async {
  final now = laterClock();
  final first = DateTime(now.year, now.month, now.day + 1);
  final picker = debugEndDatePicker;
  final picked = picker != null ? await picker(context, first) : await showDatePicker(context: context, initialDate: first.add(const Duration(days: 30)), firstDate: first, lastDate: DateTime(first.year + 5, first.month, first.day), helpText: 'New end date');
  if (picked == null || !context.mounted) return;
  try {
    await TargetEndActions.instance.extend(guideId, it.targetId, picked, 'The end date was moved to ${DateFormat('d MMM yyyy').format(picked)}: plan what is left for the students who have not reached the goal.');
    if (context.mounted) showSnackbar(context, 'Target extended to ${DateFormat('d MMM yyyy').format(picked)}; the new plan is being made', Colors.blue, Icons.event_available);
  } catch (e) {
    if (context.mounted) showSnackbar(context, 'Could not extend the target', Colors.red, Icons.error);
  }
}
