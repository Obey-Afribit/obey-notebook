import 'package:local_auth/local_auth.dart';

/// Device authentication (fingerprint, face, PIN, Windows Hello) used to lock
/// folders.
///
/// Browsers have no equivalent API, and some devices have no screen lock set
/// up, so [isSupported] is checked once at start-up and the lock feature is
/// hidden where it cannot work (instead of throwing when a folder is opened).
class PrivacyLockService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false; // web, or plugin unavailable
    }
  }

  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
