import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/DropboxLink.dart';
import '../utils/GuideDb.dart';

/// The Dropbox link for one book in one language, as one shared write: the book
/// link manager and the AI agent both save through [setBookLink].

/// Languages a book can have a link in. Kept in sync by hand with the Student
/// app's own `BooksSelectionScreen.kSupportedLanguages` — there is no shared
/// package between the two apps to hold one copy.
const Map<String, String> kBookLinkLanguages = {
  'en': 'English',
  'hi': 'हिन्दी',
  'gu': 'ગુજરાતી',
  'te': 'తెలుగు',
};

/// The document holding a level's links for a language. English is the original
/// `{level}_links`, so every existing link stays where it was; other languages
/// are siblings, with no change to the shape of anything already stored.
String bookLinksDocId(String level, String language) =>
    language == 'en' ? '${level}_links' : '${level}_links_$language';

/// Saves [url] for [bookKey] in [level], normalised so it serves the raw file
/// rather than Dropbox's HTML preview page. An empty [url] removes the link.
///
/// @return the URL as stored ('' when removed)
Future<String> setBookLink({
  required String level,
  required String bookKey,
  required String url,
  String language = 'en',
}) async {
  if (!kBookLinkLanguages.containsKey(language)) {
    throw ArgumentError('Unknown language "$language".');
  }
  final normalized = normalizeDropboxUrl(url);
  await GuideDb.instance
      .collection('books')
      .doc(bookLinksDocId(level, language))
      .set({bookKey: normalized}, SetOptions(merge: true));
  return normalized;
}
