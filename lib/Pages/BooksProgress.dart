import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/BookProgressData.dart';
import '../utils/ColorProvider.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';

/// Per-student book reading progress — Phase 4 of the Book Reading redesign
/// (built 2026-08-23). Reached from the student action sheet's "Books" entry.
///
/// ⚠️ **Orphaned as of the Book reading deadlines task** (discovered in
/// passing, not this task's own scope to fix): `Pages/StudentActionSheet.dart`,
/// this page's only caller, was deleted in Phase 6 — grep-confirmed
/// `BooksProgressPage(` has zero real call sites anywhere in this app now.
/// The equivalent capability lives on, reused verbatim, in the board card's
/// own expanded book dropdown (`Home/FolkBoysWorkspace.dart`'s
/// `_levelDropdown`/`_bookStatusRow`, via this same `BookProgressData.dart`).
/// Kept rather than deleted, matching this codebase's own established
/// convention for orphaned-but-still-correct code (`Pages/Profile.dart`'s
/// old `ScorecardSection`/`BadgesSection` before Phase 6 removed that whole
/// file) — not this task's call to make.
///
/// Also the confirmed real "student's history" drill-down a guide reaches
/// from the dashboard (see the task that added the chanting-commitment
/// banner below the AppBar) — this is why that banner lives here rather
/// than a new screen: it is the one place a guide already looks at an
/// individual student's own-submitted data, alongside the book status this
/// screen has always shown.
///
/// ---------------------------------------------------------------------------
/// ⚠️ STRICTLY READ-ONLY
/// ---------------------------------------------------------------------------
/// This screen contains **no write of any kind** — no `.set`, `.update`, `.add`
/// or `.delete`, to `booksRead`, to `users`, or to anything else; it only
/// reads. `commitmentRounds` is written only by
/// `CompleteProfile.dart`/`Profile.dart` (Rules 14/15, still fully true).
///
/// `booksRead` itself is no longer guide-write-free PROJECT-WIDE, though —
/// as of the Master Task's Part 4, `Home/FolkBoysWorkspace.dart` writes
/// `isCurrentBook`/`startDate`/`commitmentDate`/`commitmentSetAt`/
/// `commitmentSetBy` (assigning a book) and `endDate`/`isCurrentBook`
/// (marking one finished). It never writes `madeNotes` — that stays
/// exclusively the student's own self-report, read here, never restated.
///
/// ---------------------------------------------------------------------------
/// Reads
/// ---------------------------------------------------------------------------
///  * `books/level-1`, `books/level-2`, `books/level-3` — the ordered titles.
///    Static config, fetched **once** per screen open (not a stream): the
///    titles do not change while a guide is looking at them.
///  * `books/{level}_links` — link availability. ⚠️ Only `level-1_links`
///    exists, holding exactly `book_2` and `book_9`; `level-2_links` and
///    `level-3_links` **do not exist at all**. A missing document is treated as
///    "no links for that level", not as an error, so 55 of the 57 books
///    currently render as having no file. That is the honest state of the data.
///  * `booksRead where uid == studentUid` — ONE equality filter, the shape
///    every query in this project uses, so no composite index is needed. Live
///    (`.snapshots()`) so a report the boy files while the guide is looking
///    appears without a reopen.
///
/// ⚠️ **Why the `uid` filter and not 57 document gets:** one query replaces 57
/// reads, and it also side-steps a real hazard. `booksRead` holds **two
/// schemas**: 11 legacy documents keyed by student *name* carrying only
/// `{currentBook: "..."}` (including `"Om Patel"` and `"Om Patel "` as separate
/// keys), alongside the live `{uid}_{level}_{bookKey}` documents. The legacy
/// documents have **no `uid` field**, so this query excludes them by
/// construction rather than by a name-matching guess.
///
/// ---------------------------------------------------------------------------
/// Rows are informational, not tappable
/// ---------------------------------------------------------------------------
/// Nothing on this list is tappable. The Guide app has **no book reader** —
/// that is the Student app's `BookReaderPage` — so a tap would have nowhere to
/// go, and inventing a destination is not this phase's job. The "No file"
/// marker therefore reads as information ("nobody has uploaded a copy of this
/// book yet"), which is what a missing `{level}_links` entry actually means.
class BooksProgressPage extends StatefulWidget {
  final String studentUid;
  final String studentName;

  const BooksProgressPage({
    super.key,
    required this.studentUid,
    required this.studentName,
  });

  @override
  State<BooksProgressPage> createState() => _BooksProgressPageState();
}

class _BooksProgressPageState extends State<BooksProgressPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final Future<BooksConfig> _configFuture;

  /// The student's own self-set chanting commitment — READ-ONLY here, same
  /// discipline as everything else on this screen (see this file's own
  /// header). Fetched once, independently of the book config/progress
  /// streams above, so it renders without waiting on either.
  late final Future<int?> _commitmentFuture;

  /// This student's `booksRead` documents. The student's `users` doc is read
  /// first so the query carries the scope filter the security rules can prove
  /// (hierarchy); legacy name-keyed docs have no `uid` and stay excluded.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _progressStream;

  Stream<QuerySnapshot<Map<String, dynamic>>> _progress() async* {
    final userDoc =
        await _firestore.collection('users').doc(widget.studentUid).get();
    yield* StudentScope.current()
        .constrainForStudent(
          _firestore
              .collection('booksRead')
              .where('uid', isEqualTo: widget.studentUid),
          StudentRef.fromDoc(userDoc),
        )
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _progressStream = _progress();
    // Both extracted to `utils/BookProgressData.dart` this task — see that
    // file's header for why (Dart's file-level privacy meant these could not
    // be shared as private declarations once the FOLK Boys board needed the
    // same logic). Behaviour unchanged.
    _configFuture = loadBooksConfig();
    _commitmentFuture = loadChantingCommitment(widget.studentUid);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: AppBar(
            elevation: 0,
            backgroundColor: colorProvider.color,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Books — ${widget.studentName}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: Column(
            children: [
              _commitmentBanner(colorProvider),
              Expanded(
                child: FutureBuilder<BooksConfig>(
            future: _configFuture,
            builder: (context, configSnap) {
              if (configSnap.hasError) {
                return _message(
                    colorProvider, "Could not load the book list.");
              }
              if (!configSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final config = configSnap.data!;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                // `uid` equality (+ scope filter). Legacy name-keyed documents
                // carry no `uid` field and are excluded by construction.
                stream: _progressStream,
                builder: (context, progressSnap) {
                  if (!progressSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Keyed "{level}_{bookKey}" — matches on the document's own
                  // fields rather than by re-deriving its id, so a document
                  // whose id ever drifts still lands on the right row.
                  final entries = <String, Map<String, dynamic>>{};
                  for (final doc in progressSnap.data!.docs) {
                    final data = doc.data();
                    final level = (data['level'] ?? '').toString();
                    final key = (data['bookKey'] ?? '').toString();
                    if (level.isEmpty || key.isEmpty) continue;
                    entries['${level}_$key'] = data;
                  }

                  return _list(colorProvider, config, entries);
                },
              );
            },
          ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Read-only. `null` future value or a still-loading state both render as
  /// nothing rather than a spinner — the book list below is the primary
  /// content and should not be blocked by this secondary read.
  Widget _commitmentBanner(ColorProvider colorProvider) {
    return FutureBuilder<int?>(
      future: _commitmentFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final commitment = snap.data;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.g.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: commitment == null
                  ? context.g.chipBackground
                  : context.g.warning.withValues(alpha: .35),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.local_fire_department,
                size: 18,
                color: commitment == null
                    ? context.g.mutedText
                    : context.g.warning,
              ),
              const SizedBox(width: 8),
              Text(
                commitment == null
                    ? "No chanting commitment set"
                    : "Committed to $commitment rounds/day",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: commitment == null
                      ? context.g.mutedText
                      : context.g.text,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _message(ColorProvider colorProvider, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: colorProvider.secondColor.withValues(alpha: .8)),
        ),
      ),
    );
  }

  Widget _list(
    ColorProvider colorProvider,
    BooksConfig config,
    Map<String, Map<String, dynamic>> entries,
  ) {
    final children = <Widget>[];

    // A student with zero booksRead documents falls straight through this loop
    // and gets the complete ladder, every row grey — never a blank screen and
    // never an error.
    for (final level in kBookLevels) {
      final books = config.byLevel[level] ?? const <BookConfigEntry>[];
      if (books.isEmpty) continue;

      var finished = 0;
      var reading = 0;
      for (final b in books) {
        final s = statusForBookEntry(entries['${b.level}_${b.key}']);
        if (s == BookStatus.finished) finished++;
        if (s == BookStatus.readingNow) reading++;
      }

      children.add(_levelHeader(
        colorProvider,
        label: kBookLevelLabels[level] ?? level,
        total: books.length,
        finished: finished,
        reading: reading,
      ));

      for (final b in books) {
        children.add(_bookRow(b, statusForBookEntry(entries['${b.level}_${b.key}']),
            entries['${b.level}_${b.key}']));
      }

      children.add(const SizedBox(height: 8));
    }

    if (children.isEmpty) {
      return _message(colorProvider, "No books are configured yet.");
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: children,
    );
  }

  Widget _levelHeader(
    ColorProvider colorProvider, {
    required String label,
    required int total,
    required int finished,
    required int reading,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8, left: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: colorProvider.secondColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "$finished of $total finished"
              "${reading > 0 ? ' · $reading reading' : ''}",
              style: TextStyle(
                fontSize: 11.5,
                color: colorProvider.secondColor.withValues(alpha: .7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One book. Not tappable — see this file's header.
  Widget _bookRow(BookConfigEntry book, BookStatus status, Map<String, dynamic>? entry) {
    final (colour, icon, label) = bookStatusStyle(status, context.g);
    final madeNotes = entry?['madeNotes'] == true;
    final unavailable = !book.hasLink;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status == BookStatus.notStarted
              ? context.g.chipBackground
              : colour.withValues(alpha: .35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 20, color: colour),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title.isEmpty ? "(untitled)" : book.title,
                  // Wraps rather than truncating — several titles are long and
                  // this list is read on a phone.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: status == BookStatus.notStarted
                        ? FontWeight.w500
                        : FontWeight.w600,
                    color: unavailable && status == BookStatus.notStarted
                        ? context.g.mutedText
                        : context.g.text,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: colour,
                      ),
                    ),
                    if (madeNotes)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note,
                              size: 14, color: context.g.brass),
                          const SizedBox(width: 2),
                          Text(
                            "Notes",
                            style: TextStyle(
                              fontSize: 10.5,
                              color: context.g.brass,
                            ),
                          ),
                        ],
                      ),
                    if (unavailable)
                      Text(
                        "No file",
                        style: TextStyle(
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          color: context.g.mutedText,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
