import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabaseの接続情報をソースコードに残さず、ビルド時に受け取ります。
class SupabaseConfig {
  SupabaseConfig._();

  static const projectUrl = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const authRedirectUrl = 'musclemory://login-callback/';

  static bool initialized = false;
  static Object? initializationError;

  static String get key =>
      publishableKey.isNotEmpty ? publishableKey : legacyAnonKey;

  static bool get isConfigured => projectUrl.isNotEmpty && key.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;

    try {
      await Supabase.initialize(url: projectUrl, publishableKey: key);
      initialized = true;
    } catch (error) {
      initializationError = error;
    }
  }
}
