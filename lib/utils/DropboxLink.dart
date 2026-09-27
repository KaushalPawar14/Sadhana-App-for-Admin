/// Dropbox share-link normalization — one definition, two consumers.
///
/// A Dropbox share URL ending in `dl=0` serves Dropbox's **HTML preview page**,
/// not the file. Anything that downloads the URL directly — the Student app's
/// DOCX reader, and now its audio player — receives HTML and fails. So every
/// link a guide pastes is normalized on save.
///
/// **Extracted 2026-08-13 from `BookLinkManager._normalizeDropboxUrl`, with the
/// logic byte-identical.** It was a private instance method on
/// `_BookLinkManagerPageState`, so it could not be called from the new podcast
/// screen at all. The alternative was a second copy, and two copies of "what
/// counts as a downloadable link" is exactly the drift the `kHodGuideId`
/// cleanup (Guide item 25) and the `associationOverdueSince()` extraction
/// (Guide item 27) were done to eliminate. `BookLinkManager` now calls this and
/// behaves exactly as before.
///
/// Deliberately a plain top-level function in `utils/`: no state, no context,
/// no Firestore. It is pure string handling and is trivially testable.
library;

/// Normalizes a Dropbox share link so it serves the raw file instead of the
/// HTML preview page.
///
/// Returns `''` for empty input, so "leave the field empty to remove the link"
/// keeps working unchanged. Non-Dropbox URLs are returned untouched rather than
/// guessed at — a link to some other host is not this function's business.
String normalizeDropboxUrl(String url) {
  final trimmed = url.trim();

  if (trimmed.isEmpty) return '';

  if (trimmed.contains('dl=0')) return trimmed.replaceAll('dl=0', 'dl=1');
  if (trimmed.contains('raw=0')) return trimmed.replaceAll('raw=0', 'raw=1');

  // Already carries an explicit download flag.
  if (trimmed.contains('dl=1') || trimmed.contains('raw=1')) return trimmed;

  // Only Dropbox links get a flag appended.
  if (!trimmed.contains('dropbox.com')) return trimmed;

  // Use & when the link already has a query string, otherwise ?.
  return trimmed.contains('?') ? '$trimmed&dl=1' : '$trimmed?dl=1';
}
