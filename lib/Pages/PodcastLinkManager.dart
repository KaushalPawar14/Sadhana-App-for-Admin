import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/DropboxLink.dart';
import '../utils/Snackbar.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';
import '../widgets/GuideMeta.dart';
import '../widgets/GuideExpandable.dart';

/// Podcast / audiobook link manager — FOLK-2/4/8/12/16.
///
/// Deliberately mirrors `BookLinkManager` (same level-sectioned layout, same
/// edit dialog shape, same `normalizeDropboxUrl` on save) so a guide who can
/// manage book links can manage these with no new mental model.
///
/// SCHEMA — two sibling documents per category, exactly like books:
///   podcastModules/F2        -> { episode_1_title: "...",
///                                 episode_1_duration: "12:34", ... }
///   podcastModules/F2_links  -> { episode_1: "https://dropbox.../x.mp3?dl=1" }
///
/// ⚠️ ONE REAL DIFFERENCE FROM `BookLinkManager`, and it is not cosmetic.
/// Book *titles* live in `books/{level}`, which the Guide app must never write
/// — they are authored elsewhere, so that screen only ever edits the `_links`
/// sibling. Nothing else in this system creates `podcastModules/{level}`, so
/// this screen has to write **both** documents: the title + duration on the
/// main doc and the URL on the `_links` doc. That is why this screen has an Add
/// Episode action and a delete, which Book Links has no need for.
///
/// The two documents are kept consistent by always writing them together in a
/// single `WriteBatch` — a half-created episode (a title with no link, or a
/// link with no title) is the one state that would render as a broken row in
/// the Student app.
/// Standalone screen wrapper.
///
/// ⚠️ **Currently unreachable (2026-08-14).** Podcast management moved inline
/// into the Books screen, which embeds [PodcastLinkSections] directly, so this
/// page has no entry point. Kept because it is a three-line shell around the
/// same widget — if podcasts ever need their own screen again, this is it.
class PodcastLinkManagerPage extends StatelessWidget {
  const PodcastLinkManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(title: Text("Podcast Links")),
          body: const PodcastLinkSections(scrollable: true),
        );
      },
    );
  }
}

/// Podcast link management — the category accordions and everything that edits
/// them, with no `Scaffold` of its own.
///
/// **This is the single definition of podcast-link logic.** The Books screen
/// embeds it inline; nothing was copied. `_editEpisode`, `_deleteEpisode`, the
/// two-document `WriteBatch`, the duration validation and
/// `normalizeDropboxUrl` all live here and only here.
///
/// [scrollable] is false when embedded, because the host screen already owns a
/// scroll view and a nested one would fight it.
class PodcastLinkSections extends StatefulWidget {
  final bool scrollable;

  const PodcastLinkSections({super.key, this.scrollable = false});

  @override
  State<PodcastLinkSections> createState() => _PodcastLinkSectionsState();
}

class _PodcastLinkSectionsState extends State<PodcastLinkSections> {
  /// Categories a guide has expanded. Collapsed by default so five categories
  /// of episodes do not open as one unscannable wall.
  final Set<String> _expanded = <String>{};

  /// Follow-up task, 2026-09-10, Part 5 item 4 — hoisted here, in
  /// `initState()`, rather than constructed fresh inside `build()` (this
  /// screen's own pre-existing shape before this task). Adding the
  /// language selector means `setState` now fires on every chip tap too,
  /// not just an `_expanded` toggle — leaving the stream construction in
  /// `build()` would have made an existing anti-pattern fire noticeably
  /// more often, exactly the class of bug the size/performance audit
  /// elsewhere in this app already fixed 14 instances of. Safe
  /// unconditionally: this stream has no filter depending on any state
  /// field (`_language` only changes which key of the already-fetched
  /// snapshot is read, in `build()` below — not what is fetched).
  late final Stream<QuerySnapshot> _modulesStream;

  @override
  void initState() {
    super.initState();
    _modulesStream =
        GuideDb.instance.collection('podcastModules').snapshots();
  }
  /// The five fixed categories. Order is the display order, not a hierarchy —
  /// students browse all five freely (see the Student app's PodcastModulesScreen
  /// for why there is no gating).
  static const List<String> levels = ['F2', 'F4', 'F8', 'F12', 'F16'];

  static const Map<String, String> levelTitles = {
    'F2': '🎧 FOLK-2',
    'F4': '🎧 FOLK-4',
    'F8': '🎧 FOLK-8',
    'F12': '🎧 FOLK-12',
    'F16': '🎧 FOLK-16',
  };

  /// Which language's links this screen edits — follow-up task, 2026-09-10,
  /// Part 4. Mirrors `BookLinkManager.dart`'s own `_language` field exactly:
  /// session state only, no standing per-guide preference to persist (a
  /// guide picks the language for the episodes they are about to edit
  /// right now, same reasoning as that file's own comment).
  String _language = 'en';

  /// Kept in sync by hand with `BookLinkManager.dart`'s own
  /// `kSupportedLanguages` and the Student app's `BooksSelectionScreen`
  /// (no shared package between the two apps to hold one copy).
  static const Map<String, String> kSupportedLanguages = {
    'en': 'English',
    'hi': 'हिन्दी',
    'gu': 'ગુજરાતી',
    'te': 'తెలుగు',
  };

  /// Document that holds the URLs for a given category and reading
  /// language. English keeps the exact, unsuffixed doc id the real data
  /// already uses (`F2_links`, `F4_links`, ...) — untouched, never
  /// migrated (Rule 3). Every other language is an additional sibling
  /// document in the same `podcastModules` collection, the identical
  /// convention `BookLinkManager.dart`'s own `linksDocId` already
  /// established for books: no new collection, no schema migration, no
  /// type change to the existing `episode_n: url` shape — one more
  /// sibling document per language.
  static String linksDocId(String level, String language) =>
      language == 'en' ? '${level}_links' : '${level}_links_$language';

  /// Field-key helpers. Kept as functions rather than inline string
  /// interpolation so the three key shapes are defined in exactly one place.
  static String titleKey(int n) => 'episode_${n}_title';
  static String durationKey(int n) => 'episode_${n}_duration';
  static String linkKey(int n) => 'episode_$n';

  /// Returns the episode numbers present in a category, numerically sorted.
  ///
  /// Any key that is not exactly `episode_<digits>_title` is ignored, so a
  /// stray field can never crash this screen — the same defensive stance
  /// `BookLinkManager._sortedBooks` takes.
  List<int> _episodeNumbers(Map<String, dynamic>? data) {
    if (data == null) return [];

    final pattern = RegExp(r'^episode_(\d+)_title$');

    final numbers = <int>[];
    for (final entry in data.entries) {
      final match = pattern.firstMatch(entry.key);
      if (match != null && entry.value is String) {
        numbers.add(int.parse(match.group(1)!));
      }
    }

    numbers.sort();
    return numbers;
  }

  /// The next free episode number for a category.
  ///
  /// Deliberately `max + 1`, not `count + 1`: if episodes 1, 2 and 3 exist and
  /// 2 is deleted, the next add must be 4, not 3 — reusing 3 would overwrite
  /// the surviving episode 3.
  int _nextEpisodeNumber(Map<String, dynamic>? data) {
    final existing = _episodeNumbers(data);
    if (existing.isEmpty) return 1;
    return existing.last + 1;
  }

  /// Validates a "mm:ss" duration. Returns null when valid, else a message.
  ///
  /// Duration is a display string, not a computed value — it is shown to the
  /// student before playback so they know what they are committing to. It is
  /// typed by a human, so it is checked rather than trusted.
  String? _durationError(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return "Duration is required";

    final match = RegExp(r'^(\d{1,3}):([0-5]\d)$').firstMatch(trimmed);
    if (match == null) return "Use mm:ss, e.g. 12:34";

    return null;
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Creates or edits one episode. Title, duration and link are edited together
  /// because they describe one thing, and because writing them together is what
  /// keeps the two documents consistent.
  Future<void> _editEpisode({
    required String level,
    required int number,
    required String currentTitle,
    required String currentDuration,
    required String currentUrl,
    required bool isNew,
  }) async {
    // Plain Strings fed through TextFormField.initialValue + onChanged, so
    // there is no controller to dispose. Disposing a controller right after
    // showDialog() returns is unsafe: the future completes on Navigator.pop
    // while the route is still animating out and the fields are still mounted.
    String title = currentTitle;
    String duration = currentDuration;
    String url = currentUrl;
    String? durationError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return GuideDialog(
            title: Text(isNew ? "Add Episode" : "Episode $number"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    levelTitles[level] ?? level,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    initialValue: currentTitle,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (value) => title = value,
                    decoration: InputDecoration(
                      labelText: "Episode title",
                      hintText: "e.g. Why we chant",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: currentDuration,
                    keyboardType: TextInputType.datetime,
                    onChanged: (value) {
                      duration = value;
                      if (durationError != null) {
                        setDialogState(() => durationError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: "Duration (mm:ss)",
                      hintText: "12:34",
                      errorText: durationError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: currentUrl,
                    keyboardType: TextInputType.url,
                    onChanged: (value) => url = value,
                    decoration: InputDecoration(
                      labelText: "Dropbox link",
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
                    "dl=0 is corrected to dl=1 automatically, so the file "
                    "plays instead of opening Dropbox.",
                    style:
                        TextStyle(fontSize: 12, color: context.g.mutedText),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: context.g.brass),
                onPressed: () {
                  // Title is required — an untitled episode is unusable in the
                  // student's list, which shows the title before playback.
                  if (title.trim().isEmpty) {
                    setDialogState(
                        () => durationError = null); // clear stale error
                    showSnackbar(dialogContext, "Episode title is required",
                        context.g.danger, Icons.error);
                    return;
                  }

                  final error = _durationError(duration);
                  if (error != null) {
                    setDialogState(() => durationError = error);
                    return;
                  }

                  Navigator.pop(dialogContext, true);
                },
                child:
                    Text("Save", style: TextStyle(color: context.g.onPrimary)),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return; // cancelled

    final normalizedUrl = normalizeDropboxUrl(url);

    try {
      final firestore = GuideDb.instance;
      final batch = firestore.batch();

      // Both documents in one batch: an episode is never half-created.
      batch.set(
        firestore.collection('podcastModules').doc(level),
        {
          titleKey(number): title.trim(),
          durationKey(number): duration.trim(),
        },
        SetOptions(merge: true),
      );

      batch.set(
        firestore.collection('podcastModules').doc(linksDocId(level, _language)),
        {linkKey(number): normalizedUrl},
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;
      showSnackbar(
        context,
        isNew ? "Episode added" : "Episode saved",
        Colors.green,
        Icons.check_circle,
      );
    } catch (e) {
      if (!mounted) return;
      showSnackbar(context, "Failed to save episode", Colors.red, Icons.error);
    }
  }

  /// Removes an episode from both documents.
  ///
  /// Confirmed first, matching the caution pattern used before other
  /// destructive actions in this app. Uses `FieldValue.delete()` rather than
  /// writing empty strings, so a removed episode disappears from the student's
  /// list instead of rendering as a blank row.
  Future<void> _deleteEpisode({
    required String level,
    required int number,
    required String title,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: const Text("Remove episode?"),
        content: Text(
          '"$title" will be removed from ${levelTitles[level] ?? level}. '
          'The audio file on Dropbox is not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.g.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                Text("Remove", style: TextStyle(color: context.g.onPrimary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final firestore = GuideDb.instance;
      final batch = firestore.batch();

      batch.update(
        firestore.collection('podcastModules').doc(level),
        {
          titleKey(number): FieldValue.delete(),
          durationKey(number): FieldValue.delete(),
        },
      );

      // Removes the link in EVERY language, not just `_language` — title
      // and duration are language-agnostic (deleted just above), so leaving
      // another language's link behind would orphan it against an episode
      // that no longer has a title anywhere. `.set(merge: true)` rather
      // than `.update()`: a language never edited for this category has no
      // `_links_<lang>` document yet, and `.update()` on a document that
      // does not exist throws (this file's own established knowledge, see
      // the catch block below) — merging a delete onto a possibly-absent
      // document is always safe, existing or not.
      for (final lang in kSupportedLanguages.keys) {
        batch.set(
          firestore.collection('podcastModules').doc(linksDocId(level, lang)),
          {linkKey(number): FieldValue.delete()},
          SetOptions(merge: true),
        );
      }

      await batch.commit();

      if (!mounted) return;
      showSnackbar(context, "Episode removed", Colors.green, Icons.check_circle);
    } catch (e) {
      if (!mounted) return;
      // An update() on a document that does not exist throws. That is the
      // likely cause here, and it means there was nothing to remove anyway.
      showSnackbar(
          context, "Failed to remove episode", context.g.danger, Icons.error);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// Which language this screen edits — mirrors `BookLinkManager.dart`'s own
  /// `_languageSelector` widget exactly (same layout, same chip styling),
  /// so a guide who already edits book links has no new UI to learn here.
  /// Switching language re-points every category section at that
  /// language's sibling `_links` document; a language with no document yet
  /// just shows every episode as "No link added" — the same empty state a
  /// brand-new category already shows today.
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
              return GuideChoiceChip(label: entry.value, selected: selected, onSelected: (_) => setState(() => _language = entry.key));
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _episodeRow({
    required String level,
    required int number,
    required String title,
    required String duration,
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
              hasLink ? Icons.headphones : Icons.link_off,
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
                  "$number. $title",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.schedule,
                        size: 12, color: context.g.mutedText),
                    const SizedBox(width: 4),
                    Flexible(child: Text(
                      duration.isEmpty ? "no duration" : duration,
                      style: TextStyle(
                          fontSize: 12, color: context.g.mutedText),
                    ))],
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
          const SizedBox(width: 4),
          Column(
            children: [
              IconButton(
                tooltip: "Edit",
                visualDensity: VisualDensity.compact,
                onPressed: () => _editEpisode(
                  level: level,
                  number: number,
                  currentTitle: title,
                  currentDuration: duration,
                  currentUrl: url,
                  isNew: false,
                ),
                icon: Icon(Icons.edit, size: 18, color: context.g.brass),
              ),
              IconButton(
                tooltip: "Remove",
                visualDensity: VisualDensity.compact,
                onPressed: () => _deleteEpisode(
                  level: level,
                  number: number,
                  title: title,
                ),
                icon: Icon(Icons.delete_outline,
                    size: 18, color: context.g.danger),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _levelSection({
    required String level,
    required Map<String, dynamic>? episodesData,
    required Map<String, dynamic>? linksData,
  }) {
    final numbers = _episodeNumbers(episodesData);
    final isOpen = _expanded.contains(level);

    final t = context.gText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GuideExpandableCard(
        expanded: isOpen,
        onChanged: (_) => setState(() {
          if (!_expanded.remove(level)) _expanded.add(level);
        }),
        headerMinHeight: 60,
        headerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        title: Text(levelTitles[level] ?? level),
        titleStyle: t.sectionTitle,
        // The count stays visible while collapsed, so a guide can see what is in
        // each one without opening it.
        trailing: Text(numbers.length == 1 ? "1 episode" : "${numbers.length} episodes", style: t.small),
        // Collapsed levels render nothing below the header. Every Edit button, dialog and
        // Firestore write below is untouched: this only controls whether the rows show.
        body: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const SizedBox(height: 16),
            if (numbers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "No episodes yet",
                  style: TextStyle(color: context.g.mutedText, fontSize: 13),
                ),
              )
            else
              ...numbers.map(
                (n) => _episodeRow(
                  level: level,
                  number: n,
                  title: (episodesData?[titleKey(n)] ?? '').toString(),
                  duration: (episodesData?[durationKey(n)] ?? '').toString(),
                  url: (linksData?[linkKey(n)] ?? '').toString(),
                ),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _editEpisode(
                  level: level,
                  number: _nextEpisodeNumber(episodesData),
                  currentTitle: '',
                  currentDuration: '',
                  currentUrl: '',
                  isNew: true,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Add Episode"),
                style:
                    TextButton.styleFrom(foregroundColor: context.g.success),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorProvider = Provider.of<ColorProvider>(context);

    return StreamBuilder<QuerySnapshot>(
      // One stream over the whole collection, exactly as BookLinkManager
      // does: five categories plus five _links siblings is ten small
      // documents, so ten separate listeners would be worse. Hoisted field
      // (see `_modulesStream`'s own doc comment), not constructed here.
      stream: _modulesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Could not load podcast modules",
                style: TextStyle(color: colorProvider.secondColor),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: const GuideBusyDot(),
            ),
          );
        }

        // Index the documents by id once, rather than searching the
        // snapshot for each of the ten lookups below.
        final docs = <String, Map<String, dynamic>>{};
        for (final doc in snapshot.data!.docs) {
          final data = doc.data();
          if (data is Map<String, dynamic>) docs[doc.id] = data;
        }

        final children = <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              "Five audiobook categories. Students can open all of "
              "them — these are not locked to a student's level.",
              style: TextStyle(
                fontSize: 13,
                color: colorProvider.secondColor,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _languageSelector(colorProvider),
          ),
          ...levels.map(
            (level) => _levelSection(
              level: level,
              episodesData: docs[level],
              linksData: docs[linksDocId(level, _language)],
            ),
          ),
        ];

        if (!widget.scrollable) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: children,
        );
      },
    );
  }
}
