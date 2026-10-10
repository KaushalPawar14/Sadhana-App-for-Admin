import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/GuideColors.dart';
import '../widgets/GuideGate.dart';

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
      child: GuideGate(
        icon: Icons.shop_two_outlined,
        pastel: GuidePastel.clay,
        title: 'Install from the Play Store',
        message: message,
        action: GuideGateButton(
          label: 'Open the Play Store',
          icon: Icons.play_arrow_rounded,
          onPressed: _openPlayStore,
        ),
      ),
    );
  }
}
