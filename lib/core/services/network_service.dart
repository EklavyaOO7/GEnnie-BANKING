import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  final _connectivity = Connectivity();

  Stream<bool> get onlineStream => _connectivity.onConnectivityChanged
      .asyncMap((_) => isOnline());

  /// Emits true when device enters flight mode (no connectivity at all)
  Stream<bool> get flightModeStream => _connectivity.onConnectivityChanged
      .map((results) => results.isEmpty || results.every((r) => r == ConnectivityResult.none));

  /// Emits the raw connectivity results on every change
  Stream<List<ConnectivityResult>> get connectivityStream =>
      _connectivity.onConnectivityChanged;

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) return false;
    try {
      final sock = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 3));
      sock.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isFlightMode() async {
    final results = await _connectivity.checkConnectivity();
    return results.isEmpty || results.every((r) => r == ConnectivityResult.none);
  }

  /// Returns true only if currently connected via WiFi
  Future<bool> isWifi() async {
    final results = await _connectivity.checkConnectivity();
    return results.contains(ConnectivityResult.wifi);
  }
}
