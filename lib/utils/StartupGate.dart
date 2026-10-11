import '../Services/HierarchyApi.dart';
import 'AdminProfile.dart';

/// Where the app goes after launch, and why.
enum StartupTarget {
  /// The installed build is older than `appConfig/versions.guides.minBuildNumber`.
  forceUpdate,

  /// Nobody is signed in.
  signIn,

  /// A release build installed from outside the Play Store.
  nonPlayInstall,

  /// Signed in and resolved: the app shell.
  shell,

  /// Signed in, but the account is no longer a registered admin: sign out, then sign-in
  /// with an explanation.
  notRegistered,

  /// The server could not be reached while resolving who this is (and no cached profile):
  /// keep the session and ask to retry.
  offline,
}

class StartupOutcome {
  const StartupOutcome(this.target, {this.guideId, this.fromCache = false});

  final StartupTarget target;

  /// The resolved admin id (for [StartupTarget.shell]).
  final String? guideId;

  /// The shell is shown from the cached profile; the caller then refreshes it in the
  /// background ([AdminProfileProvider.revalidate]).
  final bool fromCache;
}

const String kNotRegisteredMessage =
    'This account is not registered as a FOLK guide. Contact your HOD.';
const String kOfflineMessage =
    'Could not reach the server. Check your connection and try again.';

/// The launch decision, with every slow thing started AT ONCE (the force-update read, the
/// install-source check) and nothing waited for that does not have to be.
///
/// The ORDER of the decisions is exactly what the splash screen always did:
///   1. an update is required        -> the update screen (wins over everything)
///   2. nobody is signed in          -> sign-in
///   3. installed outside Play Store -> the blocking screen
///   4. resolve who this is          -> the shell / "not registered" / "offline"
/// The one change: step 4 first looks at the cached profile of THIS signed-in email, and if
/// there is one the shell opens at once instead of waiting for the `getAdminProfile` call
/// (about 1.7 s); the caller refreshes the profile in the background and signs the admin out
/// if the server says they were removed.
class StartupGate {
  StartupGate._();

  static Future<StartupOutcome> run({
    required Future<bool> Function() forceUpdate,
    required String? Function() currentEmail,
    required Future<bool> Function() installedOutsidePlayStore,
    required Future<AdminProfile?> Function(String email) cachedProfile,
    required Future<String?> Function(String email) resolveFresh,
    void Function(String label)? trace,
  }) async {
    final force = forceUpdate();
    final email = currentEmail();
    final outside = email == null ? Future<bool>.value(false) : installedOutsidePlayStore();

    if (await force) {
      trace?.call('force-update check done: update required');
      return const StartupOutcome(StartupTarget.forceUpdate);
    }
    trace?.call('force-update check done');
    if (email == null) return const StartupOutcome(StartupTarget.signIn);
    if (await outside) return const StartupOutcome(StartupTarget.nonPlayInstall);

    final cached = await cachedProfile(email);
    if (cached != null) {
      trace?.call('cached admin profile found');
      return StartupOutcome(StartupTarget.shell, guideId: cached.id, fromCache: true);
    }
    try {
      final id = await resolveFresh(email);
      trace?.call('getAdminProfile done (no cache)');
      if (id == null) return const StartupOutcome(StartupTarget.notRegistered);
      return StartupOutcome(StartupTarget.shell, guideId: id);
    } on HierarchyException {
      return const StartupOutcome(StartupTarget.offline);
    }
  }
}
