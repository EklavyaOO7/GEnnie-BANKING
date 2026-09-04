import 'package:local_auth/local_auth.dart';

class BiometricService {
  final _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<String> authenticate() async {
    if (!await isAvailable()) return 'unavailable';
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Authenticate to access BankingGenie',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      return ok ? 'success' : 'cancelled';
    } catch (_) {
      return 'unavailable'; // fail open — let user in
    }
  }
}
