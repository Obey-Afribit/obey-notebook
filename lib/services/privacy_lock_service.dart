import 'package:local_auth/local_auth.dart';

class PrivacyLockService {
  final LocalAuthentication _localAuthentication = LocalAuthentication();

  Future<bool> canUseBiometrics() {
    return _localAuthentication.canCheckBiometrics;
  }

  Future<bool> authenticate({required String reason}) {
    return _localAuthentication.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
      ),
    );
  }
}
