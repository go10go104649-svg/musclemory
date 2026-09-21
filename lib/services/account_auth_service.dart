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
}

class SupabaseAccountAuthService implements AccountAuthService {
  SupabaseAccountAuthService._(this._client);
  final SupabaseClient _client;

  static AccountAuthService? configured() => SupabaseConfig.initialized
      ? SupabaseAccountAuthService._(Supabase.instance.client)
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
  Future<void> signOut() => _client.auth.signOut();
}
