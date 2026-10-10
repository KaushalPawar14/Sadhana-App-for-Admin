import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';

/// Blocking "please update" screen — follow-up task, 2026-09-10.
///
/// Reached only from `main.dart`'s `SplashScreen`, `pushReplacement`d in
/// place of the normal destination (`CurvedNavBar`/`FolkGuideSelectionPage`)
/// when `utils/ForceUpdateCheck.isUpdateRequired()` returns true. There is
/// therefore nothing behind it on the navigation stack, and nowhere in
/// this app it is willing to let the user reach without updating first.
///
/// `PopScope<Object?>(canPop: false, ...)` is the exact idiom already used
/// throughout this app (see `Pages/Welcome.dart`'s own header comment for
/// the established pattern) — but unlike every existing use of it (close
/// the keyboard first, THEN allow a normal pop/exit), this one absorbs a
/// back press completely and does nothing else: a keyboard-focus check
/// does not apply (no text field here), and there is no "then let them
/// through" fallback, because letting them through is exactly what this
/// screen exists to prevent until they update.
class ForceUpdateScreen extends StatelessWidget {
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=org.folksurat.guides';

  const ForceUpdateScreen({super.key});

  Future<void> _openPlayStore(BuildContext context) async {
    final uri = Uri.parse(playStoreUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not open the Play Store. Please update manually."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Absorbed, deliberately — see this class's own doc comment.
      },
      child: GuideScaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update_alt,
                      size: 72, color: context.g.warning),
                  const SizedBox(height: 24),
                  const Text(
                    "Update required",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "A newer version of the FOLK Guides app is required to "
                    "continue. Please update from the Play Store to keep "
                    "using the app.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14.5, height: 1.5, color: context.g.text),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openPlayStore(context),
                      icon: const Icon(Icons.shop),
                      label: const Text("Update now"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.g.warning,
                        foregroundColor: context.g.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
