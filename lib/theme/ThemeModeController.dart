import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GuideThemeMode { light, dark, auto }

/// The Light / Dark / Auto choice. Stored on this device only (SharedPreferences),
/// never in Firestore. Auto follows the system brightness.
class ThemeModeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeModeController._(this._prefs, this._mode) {
    WidgetsBinding.instance.addObserver(this);
  }

  static const String prefsKey = 'folk_guide_theme_mode';

  /// The old setting: `ColorProvider` stored `isDarkMode` (true / false).
  static const String _legacyKey = 'isDarkMode';

  final SharedPreferences _prefs;
  GuideThemeMode _mode;

  /// First launch with the new setting: an old explicit choice is kept
  /// (isDarkMode true -> Dark, false -> Light); no old value -> Auto.
  static Future<ThemeModeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return fromPrefs(prefs);
  }

  static Future<ThemeModeController> fromPrefs(SharedPreferences prefs) async {
    var mode = _parse(prefs.getString(prefsKey));
    if (mode == null) {
      final legacy = prefs.getBool(_legacyKey);
      mode = legacy == null
          ? GuideThemeMode.auto
          : (legacy ? GuideThemeMode.dark : GuideThemeMode.light);
      await prefs.setString(prefsKey, mode.name);
    }
    return ThemeModeController._(prefs, mode);
  }

  static GuideThemeMode? _parse(String? value) {
    for (final m in GuideThemeMode.values) {
      if (m.name == value) return m;
    }
    return null;
  }

  GuideThemeMode get mode => _mode;

  ThemeMode get themeMode => switch (_mode) {
        GuideThemeMode.light => ThemeMode.light,
        GuideThemeMode.dark => ThemeMode.dark,
        GuideThemeMode.auto => ThemeMode.system,
      };

  bool get isDark => switch (_mode) {
        GuideThemeMode.light => false,
        GuideThemeMode.dark => true,
        GuideThemeMode.auto =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark,
      };

  Future<void> setMode(GuideThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _prefs.setString(prefsKey, mode.name);
    // Keep the legacy flag in step for any old reader (and a downgrade).
    if (mode != GuideThemeMode.auto) {
      await _prefs.setBool(_legacyKey, mode == GuideThemeMode.dark);
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == GuideThemeMode.auto) notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
