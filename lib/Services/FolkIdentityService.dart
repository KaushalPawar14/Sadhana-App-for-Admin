import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/AppConfiguration.dart';

class FolkIdentityService {
  FolkIdentityService._();

  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static SupabaseClient? get client =>
      _initialized ? Supabase.instance.client : null;

  static User? get currentUser => client?.auth.currentUser;

  static Stream<AuthState> get authStateChanges =>
      client?.auth.onAuthStateChange ?? const Stream<AuthState>.empty();

  static Future<void> initialize() async {
    AppConfiguration.debugValidate();
    if (_initialized || !AppConfiguration.hasSupabaseConfiguration) return;

    await Supabase.initialize(
      url: AppConfiguration.supabaseUrl,
      publishableKey: AppConfiguration.supabasePublishableKey,
      debug: kDebugMode,
    );
    _initialized = true;
  }

  static Future<void> signInWithGoogle() async {
    if (!AppConfiguration.canUseGoogleAuth || client == null) {
      throw StateError(
        'Google sign-in is not configured for this test build.',
      );
    }

    await client!.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : AppConfiguration.authRedirect,
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  static Future<void> signOut() async {
    await client?.auth.signOut();
  }

  static Future<Map<String, dynamic>?> loadCurrentProfile() async {
    final user = currentUser;
    final activeClient = client;
    if (user == null || activeClient == null) return null;

    return activeClient.from('users').select().eq('id', user.id).maybeSingle();
  }
}
