import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/AdminProfile.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../utils/GuideDb.dart';

/// Per-student comment thread — Phase 5 of the Book Reading redesign
/// (built 2026-08-23). Opened by the chat icon on a student's row in All Boys
/// Sadhana.
///
/// ---------------------------------------------------------------------------
/// RULE 12 JUSTIFICATION — why a new collection was unavoidable
/// ---------------------------------------------------------------------------
/// Rule 12 forbids creating a collection when an existing one works. Every
/// candidate was checked and each fails on its own terms:
///
///  * `interactionLogs` — models ONE guide's record of ONE meeting with a
///    student: Gemini-extracted fields, a follow-up date, LIT evidence, a
///    recommended next action. It is a per-event report, not a conversation
///    between guides, and it carries `guideId` as the *author of that meeting*.
///    Writing guide-to-guide chatter into it would corrupt the input to
///    `HolisticSuggestion` and `WeeklyPlanning`, both of which read
///    `approvedSummary` and would start ingesting comments as interaction
///    evidence.
///  * `flaggedChatMessages` — an index into `studentChats`, populated
///    server-side by `functions/chat.js` when a student's own AI-assistant
///    message trips distress or pastoral classification. It has a `reviewed`
///    flag and an `acuteRisk` flag; adding unrelated guide notes would pollute
///    a safety queue, which is the one place in this system that must stay
///    signal-only.
///  * `studentChats/{uid}/messages` — the STUDENT's own transcript. The student
///    can read it. Putting guide commentary there would breach Rule 9 outright.
///  * `holisticSuggestions` — one disposable doc per student, overwritten on
///    every regenerate. A comment thread must be append-only and permanent;
///    this is the exact inverse.
///
/// Nothing existing models a durable, append-only, multi-author thread attached
/// to a student. Hence:
///
///   studentComments/{studentUid}/messages/{autoId}
///     text        String
///     authorId    String     the posting guide's id
///     authorRole  String     "HOD" | "guide"
///     authorName  String     denormalised, so rendering needs no extra lookup
///     createdAt   Timestamp  FieldValue.serverTimestamp()
///
/// A **subcollection under the student**, not a flat collection with a
/// `studentUid` field, because a thread is only ever read for one student at a
/// time. That needs no index and no filter — the path *is* the query.
///
/// ---------------------------------------------------------------------------
/// ⚠️ THE ONLY WRITE THIS ENTIRE REDESIGN INTRODUCES
/// ---------------------------------------------------------------------------
/// Phases 1-4 were read-only or deletions. This file performs exactly one write
/// — `.add()` onto `studentComments/{uid}/messages` — and touches **nothing**
/// else. It never writes `users/{uid}`, `booksRead/**`, `books/**`,
/// `sadhana-reports/**`, `hostel-sadhana/**`, `scorecard`, `competition`,
/// `chantingChallenges*`, `litAssessments`, `interactionLogs` or
/// `flaggedChatMessages`. Append-only: nothing here edits or deletes a message
/// once posted.
///
/// ---------------------------------------------------------------------------
/// Access scope
/// ---------------------------------------------------------------------------
/// A HOD reads and posts on any student. Every other admin only on the
/// students they may manage under the role hierarchy (`StudentScope.canManage`,
/// evaluated on the student's CURRENT `users` document).
///
/// ⚠️ **Comments follow the STUDENT, not a guide's tenure.** A reassigned
/// student's new guide inherits the whole existing thread. This is the
/// *opposite* of Board C's reassignment rule, where `associations`,
/// `flaggedChatMessages`, `litAssessments` and `interactionLogs` deliberately
/// stay with the previous guide. That rule was about those four collections
/// specifically — records of what a particular guide did — whereas a comment
/// thread is context about the boy that a new guide needs in order to pick him
/// up. Confirmed with the product owner before building.
///
/// ⚠️⚠️ **This scoping is CLIENT-SIDE ONLY and is not security.** Firestore
/// security rules do not exist yet (Phase 9, still not started), so the
/// enforcement here stops an honest mistake in the UI, not a determined client.
/// Anyone able to run arbitrary code against this project can read and write
/// any thread. Until Phase 9 lands, treat that as true of every private
/// collection in this system, this one included.
///
/// Students never see any of this: nothing in the Student app references
/// `studentComments`, and this file lives in the Guide app only.

/// The collection name, in one place.
const String kStudentCommentsCollection = 'studentComments';

/// Opens the thread for one student.
///
/// [studentGuideId] is the student's `users/{uid}.guideId` as the caller knows
/// it; the dialog re-reads the student's `users` document for the access test
/// (guide, team and gender) and only falls back to this value when that read
/// fails. Pass the empty string for an unassigned student.
Future<void> showStudentCommentsDialog({
  required BuildContext context,
  required String studentUid,
  required String studentName,
  required String studentGuideId,
}) {
  return showDialog<void>(
    context: context,
    // Dismissible by tapping outside, like every other dialog in this app.
    builder: (dialogContext) => _StudentCommentsDialog(
      studentUid: studentUid,
      studentName: studentName,
      studentGuideId: studentGuideId,
    ),
  );
}

class _StudentCommentsDialog extends StatefulWidget {
  final String studentUid;
  final String studentName;
  final String studentGuideId;

  const _StudentCommentsDialog({
    required this.studentUid,
    required this.studentName,
    required this.studentGuideId,
  });

  @override
  State<_StudentCommentsDialog> createState() => _StudentCommentsDialogState();
}

class _StudentCommentsDialogState extends State<_StudentCommentsDialog> {
  final FirebaseFirestore _firestore = GuideDb.instance;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _guide;
  bool _loadingGuide = true;
  bool _sending = false;

  /// The student's current assignment, read in [_loadGuide].
  StudentRef? _studentRef;

  bool get _isHod => AdminProfileProvider.viewerIsHod;

  /// HOD anywhere; any other admin only on students they may manage.
  ///
  /// Fails closed: with no profile or no resolved student reference nothing
  /// but the HOD branch can pass.
  bool get _canAccess {
    final g = _guide;
    if (g == null || g.isEmpty) return false;
    if (_isHod) return true;
    final ref = _studentRef;
    if (ref == null) return false;
    return StudentScope.current().canManage(ref);
  }

  @override
  void initState() {
    super.initState();
    _loadGuide();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGuide() async {
    final g = AdminProfileProvider.current?.id;
    StudentRef ref;
    try {
      final doc =
          await _firestore.collection('users').doc(widget.studentUid).get();
      ref = StudentRef.fromUser(widget.studentUid, doc.data());
    } catch (_) {
      // Fall back to what the caller knew; gender stays blank, so only the
      // HOD (who never needs the reference) can get through.
      ref = StudentRef(
        uid: widget.studentUid,
        guideId: widget.studentGuideId,
        teamGuide: '',
        gender: '',
      );
    }
    if (!mounted) return;
    setState(() {
      _guide = g;
      _studentRef = ref;
      _loadingGuide = false;
    });
  }

  CollectionReference<Map<String, dynamic>> get _messagesRef => _firestore
      .collection(kStudentCommentsCollection)
      .doc(widget.studentUid)
      .collection('messages');

  /// The one and only write. Append-only `.add()`.
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // Re-checked at send time, not just at render time, so a stale dialog
    // cannot post after the guide's access has changed underneath it.
    if (!_canAccess) {
      showSnackbar(context, "You cannot post on this student's thread",
          context.g.danger, Icons.error);
      return;
    }

    final guide = _guide!;
    setState(() => _sending = true);

    try {
      await _messagesRef.add({
        'text': text,
        'authorId': guide,
        'authorRole': _isHod ? 'HOD' : 'guide',
        // The admin id is permanent; the display name is what a reader needs.
        // Both are stored so a later rename does not have to rewrite history.
        'authorName':
            AdminProfileProvider.current?.displayName ?? guide,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _controller.clear();
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showSnackbar(context, "Could not send", Colors.red, Icons.error);
    }
  }

  void _scrollToBottom() {
    // After the frame the new message is laid out in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        // Lifts the whole dialog clear of the keyboard, so the input and send
        // button stay reachable one-handed instead of being covered.
        padding: EdgeInsets.only(bottom: viewInsets > 0 ? 8 : 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Shrinks as the keyboard grows, so the message list gives up space
            // rather than the composer being pushed off-screen.
            maxHeight: size.height * 0.78 - (viewInsets > 0 ? viewInsets * 0.35 : 0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              const Divider(height: 1),
              Expanded(child: _body()),
              const Divider(height: 1),
              _composer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 10),
      child: Row(
        children: [
          Icon(Icons.forum_outlined, size: 20, color: context.g.brass),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName.isEmpty ? "Comments" : widget.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
                Text(
                  "Guide notes · not visible to the student",
                  style: TextStyle(fontSize: 10.5, color: context.g.mutedText),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: context.g.mutedText,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loadingGuide) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_canAccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 34, color: context.g.mutedText),
              const SizedBox(height: 12),
              Text(
                _guide == null || _guide!.isEmpty
                    ? "No guide selected on this device."
                    : "This student is not assigned to you.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.g.mutedText),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // The path IS the query — one student's thread, no filter, no index.
      stream: _messagesRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text("Could not load comments",
                  style: TextStyle(color: context.g.mutedText)),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.toList()
          // Sorted in Dart, oldest first — the project convention, and it also
          // avoids an orderBy on `createdAt`, which is momentarily null on a
          // just-sent message and would otherwise drop it out of the ordering
          // until the server timestamp resolves. Nulls sort last, so an
          // in-flight message sits at the bottom where the sender expects it.
          ..sort((a, b) {
            final ta = a.data()['createdAt'];
            final tb = b.data()['createdAt'];
            if (ta is! Timestamp) return 1;
            if (tb is! Timestamp) return -1;
            return ta.compareTo(tb);
          });

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                "No comments yet.\nStart the thread below.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.g.mutedText),
              ),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          itemCount: docs.length,
          itemBuilder: (context, i) => _message(docs[i].data()),
        );
      },
    );
  }

  Widget _message(Map<String, dynamic> data) {
    final authorId = (data['authorId'] ?? '').toString();
    final author = (data['authorName'] ?? data['authorId'] ?? '').toString();
    final role = (data['authorRole'] ?? '').toString();
    final text = (data['text'] ?? '').toString();
    final ts = data['createdAt'];

    final isHodAuthor = role == 'HOD';
    // Own messages align right, the familiar chat convention.
    final isMine = (authorId.isNotEmpty ? authorId : author) == _guide;

    final when = ts is Timestamp
        ? DateFormat('dd MMM yyyy · hh:mm a').format(ts.toDate())
        : "Sending…";

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.66,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isMine ? context.g.brass.withValues(alpha: .14) : context.g.chipBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMine ? context.g.brass.withValues(alpha: .14) : context.g.chipBackground,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  author.isEmpty ? "Unknown" : author,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isHodAuthor
                        ? context.g.brass.withValues(alpha: .14)
                        : context.g.success.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isHodAuthor ? "HOD" : "Guide",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isHodAuthor
                          ? context.g.brass
                          : context.g.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
            const SizedBox(height: 5),
            Text(
              when,
              style: TextStyle(fontSize: 9.5, color: context.g.mutedText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    if (!_canAccess) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_sending,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: "Write a comment…",
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 6),
          _sending
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send_rounded),
                  color: context.g.brass,
                  onPressed: _send,
                ),
        ],
      ),
    );
  }
}
