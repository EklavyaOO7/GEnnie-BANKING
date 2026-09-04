import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MetaRoomSession {
  final String name;
  final String email;
  final String sessionId;
  MetaRoomSession({required this.name, required this.email, required this.sessionId});
  Map<String, dynamic> toJson() => {'name': name, 'email': email, 'sessionId': sessionId};
}

class MetaRoomService {
  static const _qrApiBase = 'https://meta.kiya.ai/MetaQR/api';
  static const _userInfoKey = 'mfx_meta_user';

  Timer? _pollTimer;
  final _authenticatedController = StreamController<MetaRoomSession>.broadcast();
  Stream<MetaRoomSession> get authenticated$ => _authenticatedController.stream;

  Future<Map<String, dynamic>?> getSavedUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userInfoKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on Exception {
      return null;
    }
  }

  Future<void> saveUserInfo(String name, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userInfoKey, jsonEncode({'name': name, 'email': email}));
  }

  String generateSessionId() =>
      'SES${DateTime.now().millisecondsSinceEpoch}${(1000 + DateTime.now().microsecond % 9000)}';

  Future<Map<String, dynamic>> generateQR(
      MetaRoomSession session, Map<String, dynamic> userData) async {
    final body = jsonEncode({'user_info': session.toJson(), 'user_data': userData});
    final res = await http.post(
      Uri.parse('$_qrApiBase/QRGenerate'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['status'] != 'SUCCESS') throw Exception(data['message'] ?? 'QR generation failed');
    return data; // contains qrString
  }

  Future<Map<String, dynamic>> checkStatus(String sessionId) async {
    final res = await http.post(
      Uri.parse('$_qrApiBase/checkStatus'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'sessionId': sessionId}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void startPolling(String sessionId) {
    stopPolling();
    Future.delayed(const Duration(seconds: 10), () {
      _poll(sessionId);
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll(sessionId));
    });
  }

  void _poll(String sessionId) async {
    try {
      final res = await checkStatus(sessionId);
      if (res['status'] == 'SESSION_ENDED' || res['status'] == 'EXPIRED') {
        stopPolling();
      } else if (res['status'] == 'SUCCESS' || res['authenticated'] == true) {
        stopPolling();
        _authenticatedController.add(MetaRoomSession(
          name: res['name'] ?? '',
          email: res['email'] ?? '',
          sessionId: sessionId,
        ));
      }
    } catch (_) {}
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() {
    stopPolling();
    _authenticatedController.close();
  }
}
