import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Account authentication is independent of cloud/Premium entitlement.
/// The small boundary also permits offline tests without an authentication server.
abstract class AccountAuthService {
  bool get isSignedIn;
  String? get email;
  Stream<void> get changes;
  Future<void> signIn(String email, String password);

  /// True when registration immediately creates a session.
  Future<bool> signUp(String email, String password);
  Future<void> signOut();
  Future<void> deleteAccount();
  Future<void> signInWithGoogle();
}

class SupabaseAccountAuthService implements AccountAuthService {
  SupabaseAccountAuthService(this._client, this._storage);
  final LocalStorage _storage;
  final SupabaseClient _client;

  static AccountAuthService? configured() => SupabaseConfig.initialized
      ? SupabaseAccountAuthService(
          Supabase.instance.client,
          SupabaseConfig.authStorage!,
        )
      : null;

  @override
  bool get isSignedIn => _client.auth.currentUser != null;
  @override
  String? get email => _client.auth.currentUser?.email;
  @override
  Stream<void> get changes => _client.auth.onAuthStateChange.map((_) {});

  @override
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<bool> signUp(String email, String password) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    return response.session != null;
  }

  @override
  Future<void> signInWithGoogle() async {
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: SupabaseConfig.authRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw const AuthException('Googleログイン画面を開けませんでした');
    }
    // Browser launch is not authentication; the callback updates auth state.
  }

  @override
  Future<void> deleteAccount() async {
    if (_client.auth.currentSession == null) {
      throw const AuthException('ログインし直してからお試しください。');
    }
    try {
      final response = await _client.functions.invoke('delete-account');
      if (response.status != 200 ||
          response.data is! Map ||
          response.data['deleted'] != true) {
        throw const AuthException('削除を確認できませんでした。');
      }
    } catch (_) {
      // Never report success or erase the local session on an ambiguous response.
      throw const AuthException('削除の完了を確認できませんでした。接続を確認して再度お試しください。');
    }
    try {
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // The SDK clears memory before its remote logout request. The Auth user
        // is already deleted, so a remote logout failure must not block erasure.
        if (_client.auth.currentSession != null) rethrow;
      }
      await _storage.removePersistedSession();
      if (await _storage.hasAccessToken()) {
        throw StateError('Session remains');
      }
    } catch (_) {
      throw const AuthException('アカウントは削除されましたが、端末のログイン情報を消去できませんでした。');
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
