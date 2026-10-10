import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Installers that count as "installed from the Play Store".
const Set<String> kPlayStoreInstallers = {
  'com.android.vending',
  'com.google.android.feedback', // very old Play Store builds
};

const MethodChannel _channel = MethodChannel('folk/install_source');

/// The package that installed this app: "com.android.vending" for the Play
/// Store, null for a file / adb install, another package for another store.
/// Null as well when it cannot be read.
Future<String?> readInstallerPackage({MethodChannel? channel}) async {
  try {
    return await (channel ?? _channel).invokeMethod<String>('installer');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// True when this copy came from the Play Store.
bool isPlayStoreInstaller(String? installer) =>
    installer != null && kPlayStoreInstallers.contains(installer);

/// Whether to block this copy: a RELEASE build whose installer is not the Play
/// Store. Debug / profile builds (adb, IDE) are never blocked, and neither is a
/// device where the installer cannot be read at all (the platform channel is
/// missing) — only a positive "not from the Play Store" answer blocks.
Future<bool> installedOutsidePlayStore({
  MethodChannel? channel,
  bool? releaseMode,
}) async {
  if (!(releaseMode ?? kReleaseMode)) return false;
  final ch = channel ?? _channel;
  try {
    final installer = await ch.invokeMethod<String>('installer');
    return !isPlayStoreInstaller(installer);
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
