import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/ThemeModeController.dart';

/// The four colours older screens read (`colorProvider.color`, `.secondColor`,
/// `.thirdColor`, `.fourthColor`), now backed by the Ink & Brass palette so
/// every screen that has not been rewritten yet still follows the theme:
///
///   color        page background
///   secondColor  text
///   thirdColor   brass accent
///   fourthColor  card / surface
///
/// The Light / Dark / Auto choice itself lives in [ThemeModeController]
/// (stored on this device only). This provider only mirrors it; it stores
/// nothing and owns no preference of its own.
class ColorProvider with ChangeNotifier {
  ColorProvider({ThemeModeController? controller}) {
    if (controller != null) bindTo(controller);
  }

  ThemeModeController? _controller;
  bool _dark = false;

  /// Follow [controller]: this provider changes whenever the setting (or, in
  /// Auto, the system brightness) does.
  void bindTo(ThemeModeController controller) {
    _controller?.removeListener(_sync);
    _controller = controller..addListener(_sync);
    _dark = controller.isDark;
  }

  void _sync() {
    final dark = _controller!.isDark;
    if (dark == _dark) return;
    _dark = dark;
    notifyListeners();
  }

  GuideColors get _palette => _dark ? GuideColors.dark : GuideColors.light;

  bool get isDark => _dark;
  Color get color => _palette.pageBackground;
  Color get secondColor => _palette.text;
  Color get thirdColor => _palette.brass;
  Color get fourthColor => _palette.surface;

  /// Light <-> Dark (kept for any caller that still toggles; the Home screen
  /// uses the three-way Light / Dark / Auto sheet instead).
  Future<void> toggleColor() async {
    final c = _controller;
    if (c == null) {
      _dark = !_dark;
      notifyListeners();
      return;
    }
    await c.setMode(c.isDark ? GuideThemeMode.light : GuideThemeMode.dark);
  }

  @override
  void dispose() {
    _controller?.removeListener(_sync);
    super.dispose();
  }
}
