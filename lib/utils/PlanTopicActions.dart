import 'package:flutter/material.dart';

import '../Home/Calendar.dart';
import '../actions/AssociationActions.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideDialog.dart';
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
