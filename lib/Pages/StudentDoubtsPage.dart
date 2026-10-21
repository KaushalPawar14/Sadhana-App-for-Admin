import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/GuideTheme.dart';
import '../utils/AdminProfile.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentDoubts.dart';
import '../utils/UnseenDot.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideButtons.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideMeta.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import '../widgets/GuideWait.dart';

/// Students' doubts - the third "who needs you" category in Priority students.
///
/// Lists the doubts students sent to their guide while reading (`bookDoubts`, mode "guide"): the student, a preview of the
/// question, the book and when - unanswered ones on top, newest first, an orange dot on each one this admin has not opened.
/// Tapping one opens it: the highlighted paragraph, the question and (while unanswered) an answer field with Send. Sending
/// saves the answer on the student's doubt, marks it answered and the server tells the student.
///
/// Scope: each admin sees only the doubts of students they may see (HOD all) - [StudentDoubts.stream] asks the usual
/// scope-field queries and the rules check it again.
class StudentDoubtsPage extends StatefulWidget {
  const StudentDoubtsPage({super.key, this.openDoubtId});

  /// A notification about one doubt: open it as soon as the list is in.
  final String? openDoubtId;

  @override
  State<StudentDoubtsPage> createState() => _StudentDoubtsPageState();
}

class _StudentDoubtsPageState extends State<StudentDoubtsPage> {
  late final Stream<List<StudentDoubt>> _doubts = StudentDoubts.stream();
  Stream<Set<String>>? _unseen;
  bool _openedFromLink = false;

  String get _me => AdminProfileProvider.current?.id ?? '';

  @override
  void initState() {
    super.initState();
    if (_me.isNotEmpty) _unseen = StudentDoubts.unseenIds(_me);
  }

  Future<void> _open(StudentDoubt d) async {
    // Opening it clears its own dot (best effort: the markers are only a convenience).
    if (_me.isNotEmpty) {
      try {
        StudentDoubts.markOpened(_me, d.id).catchError((_) {});
      } catch (_) {}
    }
    final sent = await showDoubtAnswerDialog(context, d);
    if (sent == true && mounted) {
      showSnackbar(context, 'Answer sent to ${d.studentName}', Colors.green, Icons.check_circle_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GuideScaffold(
      appBar: const GuideAppBar(title: Text("Students' doubts")),
      body: StreamBuilder<List<StudentDoubt>>(
        stream: _doubts,
        builder: (context, snap) {
          if (snap.hasError) {
            return _Message(key: const ValueKey('doubts-error'), text: 'Could not load the doubts. Check your connection and come back.');
          }
          if (!snap.hasData) return const GuideWait();
          final doubts = StudentDoubt.sorted(snap.data!);
          final link = widget.openDoubtId;
          if (link != null && !_openedFromLink) {
            _openedFromLink = true;
            final hit = doubts.where((d) => d.id == link);
            if (hit.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _open(hit.first);
              });
            }
          }
          if (doubts.isEmpty) {
            return _Message(key: const ValueKey('doubts-empty'), text: 'No student has sent you a doubt yet. When one does, it appears here.');
          }
          final waiting = doubts.where((d) => !d.answered).length;
          return StreamBuilder<Set<String>>(
            stream: _unseen,
            builder: (context, unseenSnap) {
              final unseen = unseenSnap.data ?? const <String>{};
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  GuideSummaryBanner(
                    tone: waiting == 0 ? GuideTone.good : GuideTone.warn,
                    icon: waiting == 0 ? Icons.check_circle_outline : Icons.help_outline_rounded,
                    title: waiting == 0 ? 'All doubts answered' : (waiting == 1 ? '1 doubt waiting for you' : '$waiting doubts waiting for you'),
                    lines: [
                      AdminProfileProvider.viewerIsHod ? 'All students (HOD view)' : 'Your students',
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final d in doubts) _DoubtCard(doubt: d, unseen: unseen.contains(d.id), onTap: () => _open(d)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.g.mutedText, fontSize: 14, height: 1.5)),
        ),
      );
}

class _DoubtCard extends StatelessWidget {
  const _DoubtCard({required this.doubt, required this.unseen, required this.onTap});

  final StudentDoubt doubt;
  final bool unseen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final asked = doubt.askedAt;
    final when = asked == null ? 'just now' : DateFormat('dd MMM yyyy, hh:mm a').format(asked.toDate());
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: "${doubt.studentName}, ${doubt.answered ? 'answered' : 'waiting for an answer'}: ${doubt.preview}",
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('doubt-${doubt.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: g.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: g.border),
              boxShadow: g.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (unseen) ...[
                      UnseenDot(key: ValueKey('doubt-dot-${doubt.id}'), size: 10),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(doubt.studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(answered: doubt.answered),
                  ],
                ),
                const SizedBox(height: 8),
                Text(doubt.preview, style: const TextStyle(fontSize: 13, height: 1.4)),
                const SizedBox(height: 10),
                GuideMetaWrap(
                  children: [
                    if (doubt.bookTitle.isNotEmpty) GuideMeta(doubt.bookTitle, icon: Icons.menu_book_outlined),
                    GuideMeta(when, icon: Icons.schedule),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.answered});
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final colour = answered ? g.success : g.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: colour.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
      child: Text(
        answered ? 'Answered' : 'Waiting',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: g.isDark ? colour : Color.lerp(colour, g.text, .45)!),
      ),
    );
  }
}

/// The doubt, the way a guide answers it: the paragraph with the student's passage highlighted, the question and (when
/// unanswered) an answer field. Returns true when an answer was sent.
Future<bool?> showDoubtAnswerDialog(BuildContext context, StudentDoubt doubt) =>
    showDialog<bool>(context: context, builder: (_) => _DoubtAnswerDialog(doubt: doubt));

class _DoubtAnswerDialog extends StatefulWidget {
  const _DoubtAnswerDialog({required this.doubt});
  final StudentDoubt doubt;

  @override
  State<_DoubtAnswerDialog> createState() => _DoubtAnswerDialogState();
}

class _DoubtAnswerDialogState extends State<_DoubtAnswerDialog> {
  final TextEditingController _answer = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final me = AdminProfileProvider.current;
    final text = _answer.text.trim();
    if (me == null || text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await StudentDoubts.answer(doubtId: widget.doubt.id, text: text, me: me);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Could not send your answer. Check your connection and try again.';
      });
    }
  }

  /// The paragraph with the passage highlighted (the passage alone when the paragraph does not hold it).
  Widget _passage(BuildContext context) {
    final g = context.g;
    final d = widget.doubt;
    final base = TextStyle(fontSize: 13, height: 1.5, color: g.text);
    final mark = base.copyWith(backgroundColor: g.attention.withValues(alpha: .28), fontWeight: FontWeight.w600);
    final text = d.text.trim();
    final para = d.paragraph.trim();
    final at = text.isEmpty ? -1 : para.indexOf(text);
    final spans = at < 0
        ? [TextSpan(text: text.isEmpty ? para : text, style: text.isEmpty ? base : mark)]
        : [
            if (at > 0) TextSpan(text: para.substring(0, at), style: base),
            TextSpan(text: text, style: mark),
            if (at + text.length < para.length) TextSpan(text: para.substring(at + text.length), style: base),
          ];
    return Container(
      key: const ValueKey('doubt-passage'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: g.chipBackground, borderRadius: BorderRadius.circular(12)),
      child: Text.rich(TextSpan(children: spans)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final d = widget.doubt;
    final label = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: g.mutedText, letterSpacing: .4);
    return GuideDialog(
      title: Text(d.studentName, key: const ValueKey('doubt-dialog-title')),
      content: Column(
        key: const ValueKey('doubt-dialog'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.bookTitle.isNotEmpty) ...[
            Text(d.bookTitle, style: TextStyle(fontSize: 12, color: g.mutedText)),
            const SizedBox(height: 10),
          ],
          Text('PASSAGE', style: label),
          const SizedBox(height: 6),
          _passage(context),
          const SizedBox(height: 14),
          Text('DOUBT', style: label),
          const SizedBox(height: 6),
          Text(d.question, key: const ValueKey('doubt-question'), style: const TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          if (d.answered) ...[
            Text('YOUR ANSWER${(d.answeredByName ?? '').isEmpty ? '' : ' · ${d.answeredByName}'}', style: label),
            const SizedBox(height: 6),
            Text(d.answer!, key: const ValueKey('doubt-answer-text'), style: const TextStyle(fontSize: 14, height: 1.45)),
          ] else ...[
            Text('YOUR ANSWER', style: label),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('doubt-answer-field'),
              controller: _answer,
              enabled: !_sending,
              minLines: 3,
              maxLines: 8,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Write your answer for the student'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, key: const ValueKey('doubt-send-error'), style: TextStyle(fontSize: 12, color: g.danger)),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('doubt-close'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: Text(d.answered ? 'Close' : 'Cancel'),
        ),
        if (!d.answered)
          GuidePrimaryButton(
            key: const ValueKey('doubt-send'),
            label: 'Send',
            expand: false,
            loading: _sending,
            onPressed: _answer.text.trim().isEmpty ? null : _send,
          ),
      ],
    );
  }
}
