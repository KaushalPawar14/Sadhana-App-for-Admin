import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/DropboxLink.dart';
import '../utils/Snackbar.dart';
import 'PodcastLinkManager.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../widgets/GuideSurface.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';

/// Book Link Manager
///
/// Lets a guide attach a Dropbox URL to each book in the `books` collection.
///
/// IMPORTANT — schema note:
/// `books/{level}` stores book *titles* as plain String fields (`book_1`,
/// `book_2`, ...). There is no per-book document to hold extra data, and the
/// Student App iterates every key of `books/{level}` and parses it as
/// `book_<n>` (see BookPageList.dart `loadBooksForLevel`). Adding any new field
/// to those documents would either crash that screen or make the URL show up as
/// a book title.
///
/// So the URLs live in a SIBLING document inside the same `books` collection:
///   books/level-1        -> { book_1: "TITLE", ... }        (never modified)
///   books/level-1_links  -> { book_1: "https://dropbox..." } (written here)
/// Field keys line up one-to-one with the title document.
class BookLinkManagerPage extends StatefulWidget {
  const BookLinkManagerPage({super.key});

  @override
  State<BookLinkManagerPage> createState() => _BookLinkManagerPageState();
}

class _BookLinkManagerPageState extends State<BookLinkManagerPage> {
  /// Levels a guide has expanded. Collapsed by default: three book levels plus
  /// five podcast categories all open at once is an unscannable wall, and the
  /// point of the accordion is that a guide opens the one they came for.
  final Set<String> _expandedLevels = <String>{};

  /// Which language's links this page is currently editing (Part 6). Session
  /// state only — unlike the student's reading language, there is no
  /// per-guide "standing preference" to persist here; a guide picks the
  /// language for the books they are about to edit right now.
  String _language = 'en';

  static const List<String> levels = ['level-1', 'level-2', 'level-3'];

  static const Map<String, String> levelTitles = {
    'level-1': '✨ Level 1',
    'level-2': '🔥 Level 2',
    'level-3': '🙇 Level 3',
  };

  /// Document that holds the URLs for a given level and reading language.
  ///
  /// English keeps the exact, unsuffixed doc id real data already uses
  /// (`level-1_links`, ...) — untouched, never migrated (Rule 3). Every other
  /// language is an additional sibling document in the same `books`
  /// collection, following the identical convention already established for
  /// `{level}_links` itself: `books/level-1` holds titles, `books/level-1_links`
  /// holds English URLs, so `books/level-1_links_hi` holds Hindi URLs.
  ///
  /// Rule 12 — new-collection justification (there is none; this is the
  /// justification for NOT needing one): the alternative considered was
  /// turning each `book_N` value in the links doc into a per-language map
  /// (`book_1: {en: "...", hi: "..."}`) instead of adding sibling documents.
  /// Rejected: every `book_N` value in every existing `_links` document is a
  /// plain String today, and both apps' book screens filter on
  /// `e.value is String` (`BookPageList.dart _sortedBooks`, this file's own
  /// `_sortedBooks`, and `BooksProgress.dart`'s `hasLink` check) — changing
  /// the value type to a Map would make every existing English link
  /// disappear from those type checks, exactly the "restructure that breaks
  /// existing English links" this task was told not to do. A sibling
  /// document per language needs no schema migration, no type change, and no
  /// new collection: it is the same `books` collection, the same document
  /// shape, one more sibling — the minimal extension of what already exists.
  static String linksDocId(String level, String language) =>
      language == 'en' ? '${level}_links' : '${level}_links_$language';

  /// Kept in sync by hand with the Student app's own
  /// `BooksSelectionScreen.kSupportedLanguages` (no shared package between
  /// the two apps to hold a single copy).
  static const Map<String, String> kSupportedLanguages = {
    'en': 'English',
    'hi': 'हिन्दी',
    'gu': 'ગુજરાતી',
    'te': 'తెలుగు',
  };

  /// Returns the `book_n` entries of a level document, numerically sorted.
  /// Any key that is not exactly `book_<digits>` is ignored so a stray field
  /// can never crash this screen.
  List<MapEntry<String, String>> _sortedBooks(Map<String, dynamic>? data) {
    if (data == null) return [];

    final pattern = RegExp(r'^book_\d+$');

    final entries = data.entries
        .where((e) => pattern.hasMatch(e.key) && e.value is String)
        .map((e) => MapEntry(e.key, e.value as String))
        .toList();

    entries.sort((a, b) => int.parse(a.key.split('_')[1])
        .compareTo(int.parse(b.key.split('_')[1])));

    return entries;
  }

  // `_normalizeDropboxUrl` moved to `utils/DropboxLink.dart` on 2026-08-13 as
  // the top-level `normalizeDropboxUrl()`, so the podcast link manager can use
  // the same definition instead of carrying a second copy. The logic is
  // byte-identical; only its location changed. The Student App's reader unzips
  // whatever the link returns, so a preview page would still fail to open as a
  // .docx — that is why this normalization exists at all.

  Future<void> _editLink({
    required String level,
    required String fieldKey,
    required String bookTitle,
    required String currentUrl,
  }) async {
    // Kept as a plain String fed through TextFormField.initialValue +
    // onChanged, so there is no TextEditingController to dispose. Disposing a
    // controller immediately after showDialog() returns is unsafe: the future
    // completes on Navigator.pop, while the route is still animating out and
    // the field is still mounted and listening to that controller.
    String enteredUrl = currentUrl;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return GuideDialog(
            title: const Text("Dropbox Link"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: currentUrl,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  onChanged: (value) => enteredUrl = value,
                  decoration: InputDecoration(
                    hintText: "https://www.dropbox.com/...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Leave empty to remove the link.",
                  style: TextStyle(fontSize: 12, color: context.g.mutedText),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: context.g.brass),
                onPressed: () =>
                    Navigator.pop(dialogContext, enteredUrl.trim()),
                child:
                    Text("Save", style: TextStyle(color: context.g.onPrimary)),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return; // cancelled

    final normalizedUrl = normalizeDropboxUrl(result);

    try {
      await GuideDb.instance
          .collection('books')
          .doc(linksDocId(level, _language))
          .set({fieldKey: normalizedUrl}, SetOptions(merge: true));

      if (!mounted) return;
      showSnackbar(
        context,
        result.isEmpty ? "Link removed" : "Link saved successfully",
        Colors.green,
        Icons.check_circle,
      );
    } catch (e) {
      if (!mounted) return;
      showSnackbar(context, "Failed to save link", Colors.red, Icons.error);
    }
  }

  /// Which language this page edits (Part 6). Switching language re-points
  /// every level section at that language's sibling `_links` document —
  /// picking a language with no document yet just shows every book as
  /// "No link added", the same empty state a level with no `_links` doc at
  /// all already shows today (`level-2_links` / `level-3_links`).
  Widget _languageSelector(ColorProvider colorProvider) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.g.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Editing links for",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.g.mutedText,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSupportedLanguages.entries.map((entry) {
              final selected = _language == entry.key;
              return ChoiceChip(
                label: Text(entry.value),
                selected: selected,
                onSelected: (_) => setState(() => _language = entry.key),
                selectedColor: context.g.brass.withValues(alpha: .14),
                labelStyle: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                  color: selected ? context.g.brass : context.g.text,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _bookRow({
    required String level,
    required String fieldKey,
    required String title,
    required String url,
  }) {
    final hasLink = url.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: context.g.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasLink ? context.g.success.withValues(alpha: .14) : context.g.warning.withValues(alpha: .14),
            ),
            child: Icon(
              hasLink ? Icons.link : Icons.link_off,
              size: 18,
              color: hasLink ? context.g.success : context.g.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasLink ? url : "No link added",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasLink ? context.g.brass : context.g.mutedText,
                    fontStyle: hasLink ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _editLink(
              level: level,
              fieldKey: fieldKey,
              bookTitle: title,
              currentUrl: url,
            ),
            icon: const Icon(Icons.edit, size: 16),
            label: const Text("Edit"),
            style: TextButton.styleFrom(foregroundColor: context.g.brass),
          ),
        ],
      ),
    );
  }

  Widget _levelSection({
    required String level,
    required Map<String, dynamic>? titlesData,
    required Map<String, dynamic>? linksData,
    required ColorProvider colorProvider,
  }) {
    final books = _sortedBooks(titlesData);
    final isOpen = _expandedLevels.contains(level);

    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(GuideShape.cardRadius),
        border: Border.all(color: context.g.border),
        boxShadow: context.g.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Accordion header. The whole row is the tap target rather than just
          // the chevron — a small icon is a poor thing to ask a thumb to find.
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() {
              if (!_expandedLevels.remove(level)) _expandedLevels.add(level);
            }),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 22,
                  decoration: BoxDecoration(
                    color: context.g.text,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  levelTitles[level] ?? level,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.g.text,
                  ),
                ),
                const Spacer(),
                // Count stays visible while collapsed, so a guide can see what
                // is in each level without opening it.
                Text(
                  "${books.length} books",
                  style: TextStyle(fontSize: 12, color: context.g.mutedText),
                ),
                const SizedBox(width: 4),
                Icon(
                  isOpen ? Icons.expand_less : Icons.expand_more,
                  size: 22,
                  color: context.g.text,
                ),
              ],
            ),
          ),
          // Collapsed levels render nothing below the header. Every Edit
          // button, dialog and Firestore write below is untouched — this
          // controls only whether the rows are on screen.
          if (isOpen) ...[
          const SizedBox(height: 16),
          if (books.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                "No books found for this level",
                style: TextStyle(color: context.g.mutedText, fontSize: 13),
              ),
            )
          else
            ...books.map(
              (entry) => _bookRow(
                level: level,
                fieldKey: entry.key,
                title: entry.value,
                url: (linksData?[entry.key] ?? '').toString(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(
            title: Text(
              // Renamed 2026-08-14 when podcast links were merged in below.
              "Books & Podcasts",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 20,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            )),
          body: StreamBuilder<QuerySnapshot>(
            stream:
                GuideDb.instance.collection('books').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const GuideWait();
              }

              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}"));
              }

              if (!snapshot.hasData) {
                return const Center(child: Text("No books found."));
              }

              // Index every document in the collection by its id so both the
              // title docs and the *_links docs are available.
              final Map<String, Map<String, dynamic>> docs = {
                for (var doc in snapshot.data!.docs)
                  doc.id: (doc.data() as Map<String, dynamic>)
              };

              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _languageSelector(colorProvider),
                  const SizedBox(height: 16),
                  ...levels.map(
                    (level) => _levelSection(
                      level: level,
                      titlesData: docs[level],
                      linksData: docs[linksDocId(level, _language)],
                      colorProvider: colorProvider,
                    ),
                  ),

                  /// PODCASTS — merged in on 2026-08-14 from what used to be a
                  /// separate "Podcast Links" Admin Hub tile.
                  ///
                  /// `PodcastLinkSections` is the real podcast implementation
                  /// embedded inline, not a copy: episode editing, the
                  /// two-document `WriteBatch`, duration validation and Dropbox
                  /// normalization all still live in `PodcastLinkManager.dart`
                  /// and are called from here. Its own accordion matches the
                  /// book levels above.
                  const SizedBox(height: 8),
                  Divider(thickness: 1.2, color: context.g.mutedText),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.headphones,
                          size: 20, color: colorProvider.secondColor),
                      const SizedBox(width: 8),
                      Text(
                        "Podcast Links",
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: colorProvider.secondColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const PodcastLinkSections(),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
