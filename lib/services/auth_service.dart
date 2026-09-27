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
          'Cloud sync is not configured in this build. Notes are saved on '
          'this device only.';
      return;
    }

    try {
      // Supabase.initialize() is called once in main(); grab the shared client.
      _client = Supabase.instance.client;
      _cloudReady = true;
      _initializationError = null;
    } catch (_) {
      _cloudReady = false;
      _client = null;
      _initializationError =
          'The cloud is unavailable right now. The app keeps working offline.';
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
    // Set once Supabase records a confirmation. With email confirmation turned
    // off in the project, it is set immediately on sign-up.
    return user.emailConfirmedAt != null;
  }

  String get currentUserId =>
      _client?.auth.currentUser?.id ?? 'local-offline-user';

  String? get currentEmail => _client?.auth.currentUser?.email;

  Stream<AuthState> authStateChanges() {
    final SupabaseClient? client = _client;
    if (client == null) {
      return const Stream<AuthState>.empty();
    }
    return client.auth.onAuthStateChange;
  }

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw StateError('Cloud sign-in is unavailable in this build.');
    }
    return client;
  }

  /// Creates an account. Returns true when the user is signed in straight
  /// away, false when the project requires email confirmation first.
  Future<bool> createAccountWithEmail({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _requireClient().auth.signUp(
          email: email.trim(),
          password: password,
          emailRedirectTo: AppConfig.webAppUrl,
        );
    return response.session != null;
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _requireClient()
        .auth
        .signInWithPassword(email: email.trim(), password: password);
  }

  /// Emails a reset link that opens the web app, which then asks for a new
  /// password. The web app works from any device, including phones.
  Future<void> sendPasswordReset(String email) async {
    await _requireClient().auth.resetPasswordForEmail(
          email.trim(),
          redirectTo: AppConfig.webAppUrl,
        );
  }

  Future<void> updatePassword(String newPassword) async {
    await _requireClient()
        .auth
        .updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }

  /// Deletes the signed-in account. Supabase does not allow a client to delete
  /// its own auth row directly, so this calls a `delete_current_user` RPC
  /// (a SECURITY DEFINER function defined in the schema).
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
    await client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: AppConfig.webAppUrl,
    );
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
