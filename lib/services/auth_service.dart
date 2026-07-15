import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';

/// Email auth backed by Supabase.
///
/// When Supabase is not configured (no --dart-define values) the service
/// reports itself as unavailable and the app falls back to local-only mode.
class AuthService {
  bool _cloudReady = false;
  String? _initializationError;
  SupabaseClient? _client;

  Future<void> initialize() async {
    if (_cloudReady) {
      return;
    }

    if (!AppConfig.hasSupabase) {
      _cloudReady = false;
      _client = null;
      _initializationError =
          'Cloud sync is not configured. Notes are saved locally on this device.';
      return;
    }

    try {
      // Supabase.initialize() is called once in main(); grab the shared client.
      _client = Supabase.instance.client;
      _cloudReady = true;
      _initializationError = null;
    } catch (error) {
      _cloudReady = false;
      _client = null;
      _initializationError =
          'Cloud is unavailable. The app will keep working offline. ($error)';
    }
  }

  bool get isCloudReady => _cloudReady;
  String? get initializationError => _initializationError;

  bool get isSignedIn => _client?.auth.currentUser != null;

  bool get isEmailVerified {
    final User? user = _client?.auth.currentUser;
    if (user == null) {
      return false;
    }
    // Verified once Supabase records an email confirmation timestamp. If email
    // confirmation is disabled in the project, this is set immediately on
    // sign-up so the gate passes transparently.
    return user.emailConfirmedAt != null;
  }

  String get currentUserId =>
      _client?.auth.currentUser?.id ?? 'local-offline-user';

  String? get currentEmail => _client?.auth.currentUser?.email;

  Stream<dynamic> authStateChanges() {
    final SupabaseClient? client = _client;
    if (client == null) {
      return const Stream<dynamic>.empty();
    }
    return client.auth.onAuthStateChange;
  }

  Future<void> createAccountWithEmail({
    required String email,
    required String password,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw Exception('Cloud auth unavailable. Configure Supabase to continue.');
    }
    await client.auth.signUp(email: email.trim(), password: password);
    // Supabase dispatches the confirmation email automatically when enabled.
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw Exception('Cloud auth unavailable. Configure Supabase to continue.');
    }
    await client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }

  /// Deletes the signed-in account. Supabase does not allow a client to delete
  /// its own auth row directly, so this calls a `delete_current_user` RPC
  /// (a SECURITY DEFINER function defined in the schema). Falls back to sign-out
  /// if the RPC is unavailable.
  Future<void> deleteCurrentAccount() async {
    final SupabaseClient? client = _client;
    if (client == null || client.auth.currentUser == null) {
      return;
    }
    try {
      await client.rpc<void>('delete_current_user');
    } finally {
      await client.auth.signOut();
    }
  }

  Future<void> sendVerificationEmail() async {
    final SupabaseClient? client = _client;
    final String? email = currentEmail;
    if (client == null || email == null) {
      return;
    }
    await client.auth.resend(type: OtpType.signup, email: email);
  }

  Future<void> reloadUser() async {
    try {
      await _client?.auth.refreshSession();
    } catch (_) {
      // Session may not need refresh; ignore.
    }
  }

  Future<void> dispose() async {}
}
