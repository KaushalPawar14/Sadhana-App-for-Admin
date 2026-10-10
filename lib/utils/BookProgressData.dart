/// Shared book-progress data/status logic — extracted from
/// `Pages/BooksProgress.dart` this task (FOLK Boys board Phase 2) so the new
/// card dropdown can reuse it byte-for-byte instead of a second copy.
///
/// ⚠️ **Why extraction, not a direct import — Rule 1's actual constraint
/// here.** The instruction is to reuse `BooksProgress.dart`'s exact data
/// sources and status logic without reimplementing it. Every relevant piece
/// there (`_Status`, `_Book`, `_BooksConfig`, `_bookNumber`, `_loadConfig`,
/// `_statusFor`, `_statusStyle`) was a **private** (underscore-prefixed)
/// declaration, and Dart's privacy is per-file — a private identifier in one
/// library is not visible from another, so it could not be imported as-is.
/// Duplicating that logic into a second file would violate Rule 1 in
/// substance even if the letter (no literal `import` of a private symbol) were
/// technically satisfied. This file is the mechanical fix: the same logic,
/// renamed to be public, in ONE place; `BooksProgress.dart` now imports and
/// uses these exact symbols too, so there is still only one implementation to
/// ever change.
///
/// **Nothing here changes behaviour.** Every function is a rename-only
/// extraction — same field checks, same ordering rule, same fallbacks. See
/// each symbol's own doc comment for what it was called before.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideColors.dart';

/// The three levels, in the order the ladder is read. Was `_kLevels` in
/// `BooksProgress.dart`.
const List<String> kBookLevels = ['level-1', 'level-2', 'level-3'];

/// Was `_kLevelLabels` in `BooksProgress.dart`.
const Map<String, String> kBookLevelLabels = {
  'level-1': 'Level 1',
  'level-2': 'Level 2',
  'level-3': 'Level 3',
};

/// How far along one book a student is. Was `_Status`.
enum BookStatus { notStarted, readingNow, finished }

/// One book from the static config: its field key, title, and whether a
/// readable file has been linked for it. Was `_Book`.
class BookConfigEntry {
  final String level;
  final String key;
  final String title;
  final bool hasLink;

  const BookConfigEntry({
    required this.level,
    required this.key,
    required this.title,
    required this.hasLink,
  });
}

/// The whole ordered ladder, plus link availability. Was `_BooksConfig`.
class BooksConfig {
  final Map<String, List<BookConfigEntry>> byLevel;

  const BooksConfig(this.byLevel);
}

/// Sorts `book_N` field keys by their **numeric** suffix. Was `_bookNumber`.
///
/// ⚠️ A plain string sort would order `book_10` before `book_2`, silently
/// scrambling a 30-book level. The suffix is parsed rather than compared.
int bookNumberSuffix(String key) {
  final match = RegExp(r'(\d+)').firstMatch(key);
  return match == null ? 0 : (int.tryParse(match.group(1)!) ?? 0);
}

/// Reads the six config documents once. READ-ONLY. Was `_loadConfig`.
///
/// A level whose document is missing contributes no books rather than
/// throwing, and a missing `_links` document simply means every book in that
/// level has no file.
Future<BooksConfig> loadBooksConfig() async {
  final firestore = FirebaseFirestore.instance;
  final byLevel = <String, List<BookConfigEntry>>{};

  for (final level in kBookLevels) {
    final titlesSnap = await firestore.collection('books').doc(level).get();
    final titles = titlesSnap.data() ?? {};

    // A missing `{level}_links` document is normal, not an error — only
    // level-1_links exists today.
    final linksSnap =
        await firestore.collection('books').doc('${level}_links').get();
    final links = linksSnap.data() ?? {};

    final keys = titles.keys.where((k) => k.startsWith('book_')).toList()
      ..sort((a, b) => bookNumberSuffix(a).compareTo(bookNumberSuffix(b)));

    byLevel[level] = keys.map((k) {
      final linkValue = links[k];
      return BookConfigEntry(
        level: level,
        key: k,
        title: (titles[k] ?? '').toString().trim(),
        // A link counts only if it is a non-empty string. A present-but-blank
        // field is as unusable as an absent one.
        hasLink: linkValue is String && linkValue.trim().isNotEmpty,
      );
    }).toList();
  }

  return BooksConfig(byLevel);
}

/// Derives status from one `booksRead` document, or its absence. Was
/// `_statusFor`.
///
/// Order matters: `endDate` is checked first, so a finished book stays
/// finished even if `isCurrentBook` was never cleared.
///
/// ⚠️ **The spec leaves one combination undefined** — a document that exists
/// with `isCurrentBook == false` **and** no `endDate`. Real data contains no
/// such row today, but it is reachable (a student marks a book current, then
/// un-marks it without finishing). It is read as `notStarted`, the
/// conservative choice: the record asserts no progress, so the caller claims
/// none. It is deliberately NOT shown as "reading now", which would credit
/// the boy with progress his own report does not state.
BookStatus statusForBookEntry(Map<String, dynamic>? entry) {
  if (entry == null) return BookStatus.notStarted;

  final endDate = entry['endDate'];
  final finished = endDate != null && endDate.toString().trim().isNotEmpty;
  if (finished) return BookStatus.finished;

  if (entry['isCurrentBook'] == true) return BookStatus.readingNow;

  return BookStatus.notStarted;
}

/// Colour / icon / label for one status. Was `_statusStyle`.
(Color, IconData, String) bookStatusStyle(BookStatus status, GuideColors g) {
  switch (status) {
    case BookStatus.finished:
      return (g.success, Icons.check_circle, "Finished");
    case BookStatus.readingNow:
      // Amber — a deliberate third colour, neither the green of finished nor
      // the grey of untouched. Kept from `BooksProgress.dart` verbatim.
      return (g.warning, Icons.menu_book, "Reading now");
    case BookStatus.notStarted:
      return (g.mutedText, Icons.circle_outlined, "Not started");
  }
}

/// The student's own self-set chanting commitment — READ-ONLY, same
/// discipline as `BooksProgress.dart`'s own header (`commitmentRounds` is
/// written only by `CompleteProfile.dart`/`Profile.dart`). Was the body of
/// `_BooksProgressPageState._loadCommitment`.
///
/// `null` means "no commitment set" — absent or 0 are both treated as unset,
/// never as a real commitment of 0 rounds/day.
Future<int?> loadChantingCommitment(String uid) async {
  try {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final raw = snap.data()?['commitmentRounds'];
    return raw is num && raw > 0 ? raw.toInt() : null;
  } catch (_) {
    return null;
  }
}
