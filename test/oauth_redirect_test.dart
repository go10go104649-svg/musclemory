import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/config/auth_redirects.dart';
import 'package:setkeep/services/account_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';

class _Storage extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => false;
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<void> persistSession(String value) async {}
  @override
  Future<void> removePersistedSession() async {}
}

class _PkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class _Launcher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;
  String? url;
  LaunchOptions? options;
  bool result = true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    this.url = url;
    this.options = options;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final trainer in [false, true]) {
      test(
        'Google authorize redirects to the correct app: $platform trainer=$trainer',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          final original = UrlLauncherPlatform.instance;
          final launcher = _Launcher();
          UrlLauncherPlatform.instance = launcher;
          final client = SupabaseClient(
            'https://shared-project.supabase.co',
            'public-test',
            authOptions: AuthClientOptions(
              autoRefreshToken: false,
              pkceAsyncStorage: _PkceStorage(),
            ),
          );
          addTearDown(() async {
            UrlLauncherPlatform.instance = original;
            debugDefaultTargetPlatformOverride = null;
            await client.dispose();
          });
          final service = trainer
              ? SupabaseAccountAuthService(
                  client,
                  _Storage(),
                  redirectUrl: AuthRedirects.trainer,
                )
              : SupabaseAccountAuthService(client, _Storage());
          await service.signInWithGoogle();
          final url = Uri.parse(launcher.url!);
          expect(url.host, 'shared-project.supabase.co');
          expect(url.path, '/auth/v1/authorize');
          expect(url.queryParameters['provider'], 'google');
          expect(url.queryParameters['code_challenge'], isNotEmpty);
          expect(url.queryParameters['code_challenge_method'], 's256');
          expect(
            url.queryParameters['redirect_to'],
            trainer ? AuthRedirects.trainer : AuthRedirects.setkeep,
          );
          expect(
            launcher.options!.mode,
            PreferredLaunchMode.externalApplication,
          );
          // Opening the browser must never count as a completed sign-in.
          expect(service.isSignedIn, false);
          launcher.result = false;
          await expectLater(
            service.signInWithGoogle(),
            throwsA(isA<AuthException>()),
          );
        },
      );
    }
  }
}
