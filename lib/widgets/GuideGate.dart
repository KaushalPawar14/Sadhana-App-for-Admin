import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import 'GuideButtons.dart';
import 'GuideSurface.dart';
import 'GuideTiles.dart';

/// The layout of the full-screen gates (sign in, update required, installed outside
/// the Play Store): the page, a serif title, a short message, an icon tile and the
/// action below. It scrolls when the text is large, never clips.
class GuideGate extends StatelessWidget {
  const GuideGate({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    this.pastel = GuidePastel.sand,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;
  final GuidePastel pastel;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return GuideScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GuidePastelBox(
                    pastel: pastel,
                    fillWidth: false,
                    padding: EdgeInsets.zero,
                    radius: 20,
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Icon(icon, size: 30, color: GuideColors.onPastel),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(title, style: t.screenTitle),
                const SizedBox(height: 12),
                Text(message, style: t.body.copyWith(height: 1.5, color: context.g.mutedText)),
                const SizedBox(height: GuideSpace.xxl + 8),
                action,
                if (footer != null) ...[const SizedBox(height: 16), footer!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Sign in with Google" button: a surface pill with a hairline border and the
/// Google "G" in its brand blue (the one colour that is not ours to change).
class GuideGoogleButton extends StatelessWidget {
  const GuideGoogleButton({super.key, required this.onPressed, required this.loading});

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Sign in with Google',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: GuideShape.primaryButtonHeight + 4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: g.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: g.border),
            boxShadow: g.cardShadow,
          ),
          child: loading
              ? const Center(
                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: Center(
                        child: Text(
                          'G',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            // Google's brand blue — the logo is theirs, not ours.
                            color: Color(0xFF4285F4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text('Sign in with Google',
                          textAlign: TextAlign.center, style: t.bodyStrong.copyWith(fontSize: 15)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A primary action for a gate (a brass pill).
class GuideGateButton extends StatelessWidget {
  const GuideGateButton({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      GuidePrimaryButton(label: label, icon: icon, onPressed: onPressed);
}
