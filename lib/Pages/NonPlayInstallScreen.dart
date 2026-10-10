import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/GuideSurface.dart';

/// Blocking screen for a copy installed outside the Play Store (a sideloaded
/// APK): it cannot be trusted to receive updates or to stay signed correctly,
/// so the only way forward is to install the real app.
class NonPlayInstallScreen extends StatelessWidget {
  const NonPlayInstallScreen({super.key});

  static const String packageId = 'org.folksurat.guides';
  static const String message =
      'This copy was installed outside the Play Store. Please uninstall it '
      'and install the app from the Play Store.';

  Future<void> _openPlayStore() async {
    final market = Uri.parse('market://details?id=$packageId');
    final web =
        Uri.parse('https://play.google.com/store/apps/details?id=$packageId');
    if (await canLaunchUrl(market)) {
      if (await launchUrl(market, mode: LaunchMode.externalApplication)) return;
    }
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: GuideScaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shop_two_outlined, size: 64),
                  const SizedBox(height: 20),
                  const Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Open the Play Store'),
                      onPressed: _openPlayStore,
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
