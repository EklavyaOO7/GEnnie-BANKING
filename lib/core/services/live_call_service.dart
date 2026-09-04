import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

const _baseUrl  = 'https://kiya.bharatmeta.in/nodeserver/api/v1';
const _tokenUrl = 'https://kiyaversesit.kiya.ai/EventManager_E_API/api/Agora/getLiveKitToken';
const _sseUrl   = '$_baseUrl/agent/dashboard-stream';
const _livekitApiKey = 'APIhFm7C4ynyHav';
const _livekitSecret = 'YPKbIT66fiQfg61Qiy6UfPwXGqa6iUCMTeQjOKpZjplC';

enum LiveCallState { idle, requesting, inCall }

class LiveCallService {
  LiveCallState _state = LiveCallState.idle;
  String? _callId;
  String? _roomUrl;
  String? _token;

  final _stateCtrl     = StreamController<LiveCallState>.broadcast();
  final _callReadyCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callEndedCtrl = StreamController<void>.broadcast();

  Stream<LiveCallState>            get state$     => _stateCtrl.stream;
  Stream<Map<String, dynamic>>     get callReady$ => _callReadyCtrl.stream;
  Stream<void>                     get callEnded$ => _callEndedCtrl.stream;

  LiveCallState get currentState => _state;
  String?       get activeCallId => _callId;

  // SSE subscription — kept so we can cancel it when call ends
  StreamSubscription<String>? _sseSub;
  http.Client? _sseClient;

  /// Two-step flow:
  /// 1. POST /v1/live-call/request → roomName + roomUrl + callId
  /// 2. POST EventManager/getLiveKitToken → token
  /// 3. Subscribe to dashboard-stream SSE, watch for LIVE_CALL_ENDED with our callId
  Future<void> requestCall({
    required String deviceId,
    String callerName = 'Kiosk User',
    String branchLocation = 'Main Branch',
  }) async {
    if (_state != LiveCallState.idle) return;
    _setState(LiveCallState.requesting);
    try {
      // Step 1
      final callRes  = await http.post(
        Uri.parse('$_baseUrl/live-call/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': deviceId,
          'callerName': callerName,
          'branchLocation': branchLocation,
        }),
      );
      final callData = jsonDecode(callRes.body);
      final roomName = callData['data']?['roomName'] as String?;
      final roomUrl  = callData['data']?['roomUrl']  as String?;
      _callId        = callData['data']?['callId']   as String?;
      if (roomName == null || roomUrl == null || _callId == null) {
        _setState(LiveCallState.idle);
        return;
      }
      _roomUrl = roomUrl;

      // Step 2
      final tokenRes  = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'Apikey': _livekitApiKey,
          'ParticipantIdentity': callerName,
          'participantName': callerName,
          'RoomName': roomName,
          'secret': _livekitSecret,
          'sessionId': roomName,
          'roomName': roomName,
        }),
      );
      final tokenData = jsonDecode(tokenRes.body);
      _token = tokenData['token']
          ?? tokenData['Token']
          ?? tokenData['accessToken']
          ?? tokenData['data']?['token'] as String?;
      if (_token == null) {
        _setState(LiveCallState.idle);
        return;
      }

      // Step 3 — subscribe to dashboard SSE before emitting callReady
      _subscribeSse(_callId!);

      _setState(LiveCallState.inCall);
      _callReadyCtrl.add({
        'callId':  _callId,
        'roomUrl': _roomUrl,
        'token':   _token,
      });
    } catch (_) {
      _setState(LiveCallState.idle);
    }
  }

  /// Listen to GET /v1/agent/dashboard-stream (same SSE the dashboard uses).
  /// When we receive LIVE_CALL_ENDED for our callId → end the call.
  void _subscribeSse(String callId) {
    _cancelSse();
    _sseClient = http.Client();
    final request = http.Request('GET', Uri.parse(_sseUrl));
    _sseClient!.send(request).then((response) {
      // SSE lines arrive as a byte stream — decode and buffer into lines
      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      String dataBuffer = '';
      _sseSub = lineStream.listen(
        (line) {
          if (line.startsWith('data:')) {
            dataBuffer = line.substring(5).trim();
          } else if (line.isEmpty && dataBuffer.isNotEmpty) {
            // Full SSE event received — parse it
            try {
              final event = jsonDecode(dataBuffer) as Map<String, dynamic>;
              final eventType = event['event'] as String?;
              final data      = event['data']  as Map<String, dynamic>?;
              if (eventType == 'LIVE_CALL_ENDED' &&
                  data?['callId'] == callId) {
                // Dashboard ended the call — clean up from our side
                _handleRemoteEnd();
              }
            } catch (_) {}
            dataBuffer = '';
          }
        },
        onError: (_) => _cancelSse(),
        onDone:  ()  => _cancelSse(),
        cancelOnError: true,
      );
    }).catchError((_) => _cancelSse());
  }

  void _handleRemoteEnd() {
    _cancelSse();
    _callId  = null;
    _roomUrl = null;
    _token   = null;
    _setState(LiveCallState.idle);
    _callEndedCtrl.add(null);
  }

  void _cancelSse() {
    _sseSub?.cancel();
    _sseSub = null;
    _sseClient?.close();
    _sseClient = null;
  }

  /// Caller ends the call
  Future<void> endCall() async {
    final cid = _callId;
    _cancelSse();
    _callId  = null;
    _roomUrl = null;
    _token   = null;
    _setState(LiveCallState.idle);
    if (cid == null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/live-call/end'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'callId': cid, 'endedBy': 'caller'}),
      );
    } catch (_) {}
    _callEndedCtrl.add(null);
  }

  void _setState(LiveCallState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void dispose() {
    _cancelSse();
    _stateCtrl.close();
    _callReadyCtrl.close();
    _callEndedCtrl.close();
  }
}
