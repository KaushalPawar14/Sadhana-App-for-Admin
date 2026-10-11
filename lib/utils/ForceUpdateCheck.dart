import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'GuideDb.dart';

/// Force-update gate — follow-up task, 2026-09-10.
///
/// ---------------------------------------------------------------------------
/// Rule 12 — why `appConfig/versions`, one document, not a new collection
/// ---------------------------------------------------------------------------
/// A single small document the product owner can open in the Firestore
/// console and edit directly to require an update, with no deploy — the
/// task's own explicit goal. One document with a field per app (`guides`,
/// `students`) rather than two separate top-level documents/collections:
/// both apps already share this one Firebase project, and whoever is
/// looking for "the version gate" has exactly one place to look, for
/// either app.
///
/// ---------------------------------------------------------------------------
/// Why `minBuildNumber` (an int), not the version NAME string
/// ---------------------------------------------------------------------------
/// Play Store already requires `versionCode` (= Flutter's build number,
/// the `+N` in `pubspec.yaml`'s `1.0.0+1`) to strictly increase on every
/// upload — confirmed in the earlier release-signing task. It is already a
/// reliable, monotonically-increasing integer, so comparing it needs no
/// semver-parsing logic to get subtly wrong (is "1.10.0" newer than
/// "1.9.0"? — a real class of bug a plain integer comparison never has).
/// `minVersionName` is stored ALONGSIDE it purely so the product owner can
/// tell, at a glance in the Firestore console, which release a given
/// build number corresponds to — it is never read by this comparison.
///
/// ---------------------------------------------------------------------------
/// Fails OPEN everywhere (item 5)
/// ---------------------------------------------------------------------------
/// Missing document, missing app field, missing/malformed
/// `minBuildNumber`, offline, a slow network, or any thrown error — every
/// one of these lets the user in. A blocking screen must only ever be
/// caused by a genuinely-too-old install, never by connectivity.
class ForceUpdateCheck {
  /// Generous enough for a normal Firestore round trip, short enough that
  /// a genuinely stuck connection still resolves (fails open) well within
  /// the splash screen's own on-screen time on both apps (4-5 seconds).
  static const Duration _timeout = Duration(seconds: 6);

  static Future<bool> isUpdateRequired() async {
    try {
      final snap = await GuideDb.instance
          .collection('appConfig')
          .doc('versions')
          .get()
          .timeout(_timeout);

      if (!snap.exists) {
        return false;
      }

      final appField = snap.data()?['guides'];
      if (appField is! Map) {
        return false;
      }

      final minBuild = appField['minBuildNumber'];
      if (minBuild is! int) {
        return false;
      }

      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber);
      if (currentBuild == null) return false;

      return currentBuild < minBuild;
    } catch (e, st) {
      // Permanent (not part of the earlier force-update-doesn't-work
      // investigation's temp logging, since stripped). 2026-09-16: this catch
      // is exactly what let the update gate silently fail open for its
      // entire life (see the main.dart ordering bug this file's header now
      // documents) — nobody could see it was broken without adding
      // temporary logging first. Fails open regardless either way (a
      // network blip must never lock anyone out), but a real bug in this
      // check should be loud, not invisible. `debugPrint` still runs in
      // release builds (only `print`'s own throttling differs), so this is
      // visible via `adb logcat` without needing a debug build.
      debugPrint(
        '[ForceUpdateCheck] update check FAILED, proceeding without '
        'blocking (fail-open): $e\n$st',
      );
      return false;
    }
  }
}
