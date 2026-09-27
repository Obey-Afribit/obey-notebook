import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns exceptions into short sentences a person can act on.
///
/// Raw exception text (for example `AuthRetryableFetchException(message:
/// ClientException with SocketException: Failed host lookup ...)`) is never
/// shown to users; it is mapped here instead.
String friendlyError(Object error) {
  final String raw = error.toString();
  final String lower = raw.toLowerCase();

  if (_looksLikeNetworkFailure(lower) || error is AuthRetryableFetchException) {
    return "Can't reach the server. Check your internet connection and try "
        'again.';
  }

  if (error is AuthException) {
    final String code = error.code ?? '';
    final String message = error.message.toLowerCase();

    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return "That email and password don't match. Try again, or reset your "
          'password.';
    }
    if (code == 'user_already_exists' ||
        code == 'email_exists' ||
        message.contains('already registered')) {
      return 'An account with this email already exists. Sign in instead.';
    }
    if (error is AuthWeakPasswordException ||
        code == 'weak_password' ||
        message.contains('password should')) {
      return 'Choose a stronger password: at least 6 characters.';
    }
    if (code == 'email_not_confirmed' || message.contains('not confirmed')) {
      return 'Confirm your email address first, then sign in.';
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        error.statusCode == '429' ||
        message.contains('rate limit')) {
      return 'Too many attempts. Wait a minute, then try again.';
    }
    if (code == 'email_address_invalid' || message.contains('invalid email')) {
      return "That email address doesn't look right.";
    }
    if (code == 'same_password') {
      return 'Your new password must be different from the old one.';
    }
    if (code == 'signup_disabled') {
      return 'New sign-ups are turned off for this notebook.';
    }
    if (code == 'session_expired' || code == 'refresh_token_not_found') {
      return 'Your session expired. Please sign in again.';
    }
    return error.message;
  }

  if (error is StateError) {
    return error.message;
  }

  return 'Something went wrong. Please try again.';
}

bool _looksLikeNetworkFailure(String lower) {
  return lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('clientexception') ||
      lower.contains('xmlhttprequest error') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection closed') ||
      lower.contains('timed out');
}
