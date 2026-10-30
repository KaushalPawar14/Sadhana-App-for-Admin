import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../actions/BookActions.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/BoardData.dart';
import '../utils/BookProgressData.dart';
import '../utils/GuideDb.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../utils/UnseenDot.dart';
import 'GuideDialog.dart';
import 'GuideTiles.dart';
import 'GuideWait.dart';

/// The BOOKS tab of the student page: where the student is in each book, level by level, with the guide's own actions - tap a book to
/// assign it (with a commitment date), tap its circle to mark it finished (or put it back). It was the book dropdown of the board card;
/// the card now shows the student's one-line history instead and the books live here.
///
/// Everything it reads and writes is what the card dropdown used: `booksRead` for this student (scoped for the rules), the books
/// configuration, and the shared writes in `actions/BookActions.dart` (the assistant assigns through the same ones). A book commitment
/// the guide has not seen carries a dot until the tab has been open a moment.
class StudentBooksPanel extends StatefulWidget {
  const StudentBooksPanel({super.key, required this.studentUid, required this.studentName, this.focusDocId = '', this.hint = '', this.openAllLevels = false});

  final String studentUid;
  final String studentName;

  /// The `booksRead` document (`uid_level_bookKey`) to show selected: its level opens and its row is outlined (the Today button "Update book").
  final String focusDocId;

  /// A line above the list saying what to do here ("Tap a book to assign it ...").
  final String hint;

  /// Every level opens (the Today button "Assign book").
  final bool openAllLevels;

  @override
  State<StudentBooksPanel> createState() => _StudentBooksPanelState();
}

class _StudentBooksPanelState extends State<StudentBooksPanel> {
  static const int _booksShown = 5;
  static const Duration _seenDelay = Duration(milliseconds: 900);

  late final Future<BooksConfig> _config = BoardData.instance.booksConfig();
  late final Future<StudentRef> _ref = GuideDb.instance.collection('users').doc(widget.studentUid).get().then((d) => StudentRef.fromUser(widget.studentUid, d.data()));
  final Set<String> _open = {};
  final Set<String> _showAll = {};
  Set<String> _unseen = const {};
  StreamSubscription<Map<String, Set<String>>>? _unseenSub;
  Timer? _seenTimer;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _booksStream;

  String get _guide => AdminProfileProvider.current?.id ?? '';
  String _docId(BookConfigEntry b) => '${widget.studentUid}_${b.level}_${b.key}';

  @override
  void initState() {
    super.initState();
    _unseenSub = BoardData.instance.unseenCommitments(_guide).listen((m) {
      if (!mounted) return;
      setState(() => _unseen = m[widget.studentUid] ?? const {});
      _scheduleSeen();
    }, onError: (_) {});
  }

  /// Opening the tab is seeing the commitments: they are marked a moment after the list is on screen.
  void _scheduleSeen() {
    if (_unseen.isEmpty || _seenTimer != null) return;
    _seenTimer = Timer(_seenDelay, () {
      _seenTimer = null;
      if (!mounted || _unseen.isEmpty) return;
      BoardData.instance.markBooksSeen(_guide, widget.studentUid, _unseen.toList());
    });
  }

  @override
  void dispose() {
    _unseenSub?.cancel();
    _seenTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return FutureBuilder<BooksConfig>(
      future: _config,
      builder: (context, configSnap) {
        if (configSnap.hasError) {
          return Padding(padding: const EdgeInsets.all(16), child: Text('Could not load the book list.', style: t.caption));
        }
        if (!configSnap.hasData) return const Padding(padding: EdgeInsets.all(16), child: GuideWait(compact: true));
        return FutureBuilder<StudentRef>(
          future: _ref,
          builder: (context, refSnap) {
            if (!refSnap.hasData) return const Padding(padding: EdgeInsets.all(16), child: GuideWait(compact: true));
            _booksStream ??= BoardData.instance.booksRead(refSnap.data!);
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _booksStream,
              builder: (context, progress) {
                if (!progress.hasData) return const Padding(padding: EdgeInsets.all(16), child: GuideWait(compact: true));
                final entries = <String, Map<String, dynamic>>{};
                for (final doc in progress.data!.docs) {
                  final d = doc.data();
                  final level = (d['level'] ?? '').toString();
                  final key = (d['bookKey'] ?? '').toString();
                  if (level.isEmpty || key.isEmpty) continue;
                  entries['${level}_$key'] = d;
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    key: const ValueKey('student-books-panel'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<int?>(
                        future: BoardData.instance.chantingCommitment(widget.studentUid),
                        builder: (context, c) => c.hasData ? _commitment(c.data) : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 8),
                      if (widget.hint.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(widget.hint, key: const ValueKey('books-hint'), style: t.bodyStrong.copyWith(color: context.g.agent)),
                        ),
                      for (final level in kBookLevels) _level(level, configSnap.data!, entries),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _commitment(int? rounds) {
    final g = context.g;
    final t = context.gText;
    return Row(
      children: [
        Icon(Icons.local_fire_department_outlined, size: 16, color: g.mutedText),
        const SizedBox(width: 6),
        Expanded(child: Text(rounds == null ? 'No chanting commitment set' : 'Committed to $rounds rounds/day', style: t.caption)),
      ],
    );
  }

  Widget _level(String level, BooksConfig config, Map<String, Map<String, dynamic>> entries) {
    final g = context.g;
    final t = context.gText;
    final books = config.byLevel[level] ?? const <BookConfigEntry>[];
    var finished = 0;
    var reading = 0;
    final done = <BookConfigEntry>[];
    final current = <BookConfigEntry>[];
    final rest = <BookConfigEntry>[];
    for (final b in books) {
      final s = statusForBookEntry(entries['${b.level}_${b.key}']);
      if (s == BookStatus.finished) {
        finished++;
        done.add(b);
      } else if (s == BookStatus.readingNow) {
        reading++;
        current.add(b);
      } else {
        rest.add(b);
      }
    }
    final order = [...done, ...current, ...rest];
    final key = '${widget.studentUid}_$level';
    final focusHere = widget.focusDocId.isNotEmpty && books.any((b) => _docId(b) == widget.focusDocId);
    final open = _open.contains(key) || widget.openAllLevels || focusHere;
    final shown = _showAll.contains(key) || focusHere ? order : order.take(_booksShown).toList();
    final hidden = order.length - shown.length;
    final hasUnseen = books.any((b) => _unseen.contains(_docId(b)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: ValueKey('books-level-$level'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open.contains(key) || widget.openAllLevels || focusHere ? _open.remove(key) : _open.add(key)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(kBookLevelLabels[level] ?? level, style: t.cardTitleSmall)),
                      if (hasUnseen) const Padding(padding: EdgeInsets.only(right: 6), child: UnseenDot(size: 9)),
                      Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 20, color: g.mutedText),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    books.isEmpty ? 'no books configured' : '$finished of ${books.length} finished${reading > 0 ? ' · $reading reading' : ''}',
                    style: t.caption,
                  ),
                  const SizedBox(height: 8),
                  GuideProgressBar(value: books.isEmpty ? 0 : finished / books.length),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: books.isEmpty
                ? Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('No books configured for this level.', style: t.caption))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final b in shown) _row(b, statusForBookEntry(entries['${b.level}_${b.key}']), entries['${b.level}_${b.key}']),
                      if (hidden > 0)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _showAll.add(key)),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
                            child: Align(alignment: Alignment.centerLeft, child: Text('Show $hidden more', style: t.bodyStrong.copyWith(color: g.brass))),
                          ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }

  Widget _row(BookConfigEntry book, BookStatus status, Map<String, dynamic>? entry) {
    final g = context.g;
    final t = context.gText;
    final current = status == BookStatus.readingNow;
    final finished = status == BookStatus.finished;
    final colour = finished ? g.success : (current ? g.brass : g.mutedText);
    final icon = finished ? Icons.check_circle_rounded : (current ? Icons.timelapse_rounded : Icons.radio_button_unchecked_rounded);
    final due = (entry?['commitmentDate'] as String?)?.trim();
    final by = (entry?['commitmentSetBy'] as String?)?.trim();
    final focused = widget.focusDocId.isNotEmpty && _docId(book) == widget.focusDocId;
    return GestureDetector(
      key: ValueKey('book-row-${book.level}_${book.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: finished ? null : () => _assign(book),
      child: Container(
        key: focused ? const ValueKey('book-focused') : null,
        decoration: focused ? BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: g.agent, width: 1.5)) : null,
        child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: finished ? 36 : GuideShape.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              GestureDetector(
                key: ValueKey('book-circle-${book.level}_${book.key}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => finished ? _unfinish(book) : _finish(book, entry),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child: Icon(icon, size: 18, color: colour)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(book.title.isEmpty ? '(untitled)' : book.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.body.copyWith(fontSize: 13, color: status == BookStatus.notStarted ? g.mutedText : g.text)),
                    if (current && due != null && due.isNotEmpty) Text(by == 'guide' ? 'Due $due (set by guide)' : 'Due $due (set by student)', style: t.caption),
                  ],
                ),
              ),
              if (_unseen.contains(_docId(book))) const Padding(padding: EdgeInsets.only(right: 6), child: UnseenDot(size: 9)),
              if (!finished) Icon(Icons.chevron_right_rounded, size: 18, color: g.mutedText),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _unfinish(BookConfigEntry book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => GuideDialog(
        title: const Text('Mark as not completed?'),
        content: Text('${book.title.isEmpty ? '(untitled)' : book.title} will go back to not completed for ${widget.studentName}. It does not become their current book.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Mark not completed')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await markBookNotFinished(studentUid: widget.studentUid, level: book.level, bookKey: book.key, title: book.title);
      if (mounted) showSnackbar(context, 'Book marked not completed', Colors.green, Icons.check_circle);
    } catch (_) {
      if (mounted) showSnackbar(context, 'Could not update the book', Colors.red, Icons.error);
    }
  }

  Future<void> _finish(BookConfigEntry book, Map<String, dynamic>? entry) async {
    final started = (entry?['startDate'] as String?)?.trim().isNotEmpty ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => GuideDialog(
        title: const Text('Mark this book finished?'),
        content: Text(started
            ? "${book.title.isEmpty ? '(untitled)' : book.title} will no longer be ${widget.studentName}'s current book."
            : '${book.title.isEmpty ? '(untitled)' : book.title} was never started by ${widget.studentName}. Marking it finished sets today as both its start and end date, and it will not become their current book.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Mark finished')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await markBookFinished(studentUid: widget.studentUid, level: book.level, bookKey: book.key, title: book.title, hasStarted: started);
      if (mounted) showSnackbar(context, 'Book marked finished', Colors.green, Icons.check_circle);
    } catch (_) {
      if (mounted) showSnackbar(context, 'Could not update the book', Colors.red, Icons.error);
    }
  }

  Future<void> _assign(BookConfigEntry book) async {
    DateTime? picked = DateTime.now();
    final chosen = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => GuideDialog(
          title: const Text('Assign this book'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(book.title.isEmpty ? '(untitled)' : book.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text("Choose a commitment date. This book becomes ${widget.studentName}'s current book, and they'll be notified.", style: dialogContext.gText.small),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final r = await showDatePicker(context: dialogContext, initialDate: picked ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
                  if (r != null) setDialog(() => picked = r);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(border: Border.all(color: dialogContext.g.border), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 16),
                    const SizedBox(width: 10),
                    Flexible(child: Text(picked == null ? 'Tap to choose a date' : picked!.toIso8601String().split('T')[0], style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(onPressed: picked == null ? null : () => Navigator.pop(dialogContext, picked), child: const Text('Assign')),
          ],
        ),
      ),
    );
    if (!mounted || chosen is! DateTime) return;
    try {
      final ok = await assignBook(guideId: _guide, studentUid: widget.studentUid, level: book.level, bookKey: book.key, title: book.title, commitment: chosen);
      if (!mounted) return;
      if (!ok) {
        showSnackbar(context, 'This book is already completed, so it cannot be assigned as a current book', Colors.orange, Icons.info);
        return;
      }
      showSnackbar(context, 'Book assigned', Colors.green, Icons.check_circle);
    } catch (_) {
      if (mounted) showSnackbar(context, 'Could not assign the book', Colors.red, Icons.error);
    }
  }
}
