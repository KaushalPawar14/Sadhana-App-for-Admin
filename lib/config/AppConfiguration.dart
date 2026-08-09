import 'package:flutter/foundation.dart';

class AppConfiguration {
  const AppConfiguration._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const googleOnlyAuthEnabled =
      bool.fromEnvironment('GOOGLE_ONLY_AUTH', defaultValue: true);
  static const mvpPreviewEnabled =
      bool.fromEnvironment('MVP_PREVIEW', defaultValue: false);
  static const canonicalDataMode =
      String.fromEnvironment('CANONICAL_DATA_MODE', defaultValue: 'shadow');
  static const authRedirect = 'com.example.folk_guide_app://login-callback/';

  static bool get hasSupabaseConfiguration =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static bool get canUseGoogleAuth =>
      googleOnlyAuthEnabled && hasSupabaseConfiguration;

  static bool get canUsePrivatePreview => kDebugMode && mvpPreviewEnabled;

  static bool get writesSupabase =>
      canonicalDataMode == 'shadow' || canonicalDataMode == 'supabase';

  static bool get readsSupabase => canonicalDataMode == 'supabase';

  static void debugValidate() {
    if (kDebugMode && googleOnlyAuthEnabled && !hasSupabaseConfiguration) {
      debugPrint(
        'GOOGLE_ONLY_AUTH is enabled but Supabase dart-defines are missing.',
      );
    }
  }
}
