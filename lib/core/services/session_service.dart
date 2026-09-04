import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

const _baseUrl          = 'https://kiya.bharatmeta.in/nodeserver/api/v1';
const _tokenUrl         = 'https://kiyaversesit.kiya.ai/EventManager_E_API/api/Agora/getLiveKitToken';
const _livekitUrl       = 'wss://absaverse-nkwzsokx.livekit.cloud';
const _livekitApiKey    = 'APIhFm7C4ynyHav';
const _livekitApiSecret = 'YPKbIT66fiQfg61Qiy6UfPwXGqa6iUCMTeQjOKpZjplC';

enum CallState { idle, calling, inCall }
enum HitlState { idle, waitingAgent, agentAssigned, callRequest, inCall, approved, rejected }

// ── Internal node models ───────────────────────────────────────────────────

class _FormNode {
  final String nodeId;
  final Map<String, String> formValues;
  String rendererUrl; // mutable — updated on agent form submit

  _FormNode({required this.nodeId, required this.formValues, required this.rendererUrl});

  /// Matches SessionJson NodeState format the dashboard reads
  Map<String, dynamic> toJson() => {
    'nodeType':  'FORM',
    'status':    'COMPLETED',
    'renderer':  {'renderType': 'URL', 'url': rendererUrl},
    'variables': formValues.entries.map((e) => {
      'key':    e.key,
      'type':   'String',
      'value':  e.value,
      'source': 'USER',
    }).toList(),
  };
}

class _DocumentNode {
  final String nodeId;
  final String base64Data; // raw base64, no data URI prefix

  const _DocumentNode({required this.nodeId, required this.base64Data});

  /// renderer.url = data URI so dashboard face-match AI can fetch it directly
  Map<String, dynamic> toJson() => {
    'nodeType': 'DOCUMENT',
    'status':   'COMPLETED',
    'renderer': {'renderType': 'BASE64', 'url': 'data:image/jpeg;base64,$base64Data'},
    'variables':      null,
    'uploads':        null,
    'toolExecutions': null,
    'artifacts': [
      {
        'artifactId':   'ART-${nodeId.hashCode.abs() % 900 + 100}',
        'artifactType': 'IMAGE',
        'mimeType':     'image/jpeg',
        'storageType':  'BASE64',
        'data':         '',
      }
    ],
  };
}

// ── SessionService ─────────────────────────────────────────────────────────

class SessionService {
  String _deviceId = 'mobile_${DateTime.now().millisecondsSinceEpoch}';

  String? sessionId;

  String? _hitlSessionId;
  String? _hitlWorkflowId;
  String? _hitlJourneyName;
  String? _activeCallId;
  int _lastAck  = 0;
  int _nodeStep = 0;

  Timer? _heartbeatTimer;
  Timer? _agentTimeoutTimer;

  final _formNodes     = <String, _FormNode>{};
  final _documentNodes = <String, _DocumentNode>{};
  final _visitedNodes  = <String>[];
  String? _currentNodeId;

  final _processedCommandIds = <String>{};

  bool _beating   = false;
  int  _beatingAt = 0;

  final _callStateCtrl  = StreamController<CallState>.broadcast();
  final _callJoinCtrl   = StreamController<Map<String, dynamic>>.broadcast();
  final _callEndCtrl    = StreamController<void>.broadcast();
  final _hitlStateCtrl  = StreamController<HitlState>.broadcast();
  final _hitlResultCtrl = StreamController<String>.broadcast();
  final _agentNameCtrl  = StreamController<String>.broadcast();
  final _sendFormCtrl   = StreamController<String>.broadcast();
  final _sendScanCtrl   = StreamController<String>.broadcast();

  Stream<CallState>            get callState$  => _callStateCtrl.stream;
  Stream<Map<String, dynamic>> get callJoin$   => _callJoinCtrl.stream;
  Stream<void>                 get callEnd$    => _callEndCtrl.stream;
  Stream<HitlState>            get hitlState$  => _hitlStateCtrl.stream;
  Stream<String>               get hitlResult$ => _hitlResultCtrl.stream;
  Stream<String>               get agentName$  => _agentNameCtrl.stream;
  Stream<String>               get sendForm$   => _sendFormCtrl.stream;
  Stream<String>               get sendScan$   => _sendScanCtrl.stream;

  CallState get currentCallState => _callState;
  HitlState get currentHitlState => _hitlState;

  CallState _callState = CallState.idle;
  HitlState _hitlState = HitlState.idle;

  // ── App session start ────────────────────────────────────────────────────
  Future<bool> startSession(String deviceId) async {
    if (deviceId.isNotEmpty) _deviceId = deviceId;
    return _registerSession();
  }

  Future<bool> _registerSession() async {
    try {
      print('[Session] POST $_baseUrl/session/start deviceId=$_deviceId');
      final res = await http.post(
        Uri.parse('$_baseUrl/session/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId':    _deviceId,
          'channel':     'Mobile',
          'tenant':      'Infrasoft',
          'groupOffice': 'Kiyaaibank',
        }),
      ).timeout(const Duration(seconds: 10));
      print('[Session] status=${res.statusCode} body=${res.body}');
      final data = jsonDecode(res.body);
      final ok = data['success'] == true ||
                 data['success'] == 1 ||
                 data['success'].toString() == 'true';
      print('[Session] ok=$ok');
      if (ok) {
        sessionId = (data['data']?['sessionId']
                  ?? data['sessionId']
                  ?? data['data']?['session_id']) as String?;
        print('[Session] sessionId=$sessionId');
        if (sessionId != null) {
          _startHeartbeat();
          return true;
        }
        print('[Session] sessionId is null in response — keys: ${data.keys}');
      } else {
        print('[Session] success=false — full body: ${res.body}');
      }
    } catch (e) {
      print('[Session] startSession error: $e');
    }
    return false;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) => _beat());
  }

  void clearBeating() => _beating = false;

  // ── Heartbeat ────────────────────────────────────────────────────────────
  Future<void> _beat({Map<String, dynamic>? extra}) async {
    if (sessionId == null) return;
    if (_beating) {
      if (DateTime.now().millisecondsSinceEpoch - _beatingAt < 10000) return;
      _beating = false;
    }
    _beating   = true;
    _beatingAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final body = <String, dynamic>{
        'sessionId':               sessionId,
        'lastProcessedSequenceId': _lastAck,
        ...?extra,
      };
      if (extra != null) {
        print('[Beat] event=${extra["event"]} sessionId=$sessionId lastAck=$_lastAck hitlState=$_hitlState');
        _logJson('[Beat]', body);
      }
      final res = await http.post(
        Uri.parse('$_baseUrl/session/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 8));
      if (extra != null) {
        print('[Beat] response status=${res.statusCode} body=${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final ok = data['success'] == true ||
                 data['success'] == 1 ||
                 data['success'].toString() == 'true';
      if (!ok) return;
      final commands = (data['data']?['serverCommands'] as List?) ?? [];
      for (final cmd in commands) {
        print('[Beat] incoming command type=${cmd["type"]} id=${cmd["commandId"]} seq=${cmd["sequenceId"]}');
        _handleCommand(cmd as Map<String, dynamic>);
        final seq = cmd['sequenceId'];
        if (seq is int && seq > _lastAck) _lastAck = seq;
      }
    } catch (e) {
      print('[Beat] error: $e');
    } finally {
      _beating = false;
    }
  }

  // ── Command handler ──────────────────────────────────────────────────────
  void _handleCommand(Map<String, dynamic> cmd) {
    final commandId = cmd['commandId'] as String?;
    final type      = cmd['type']      as String?;
    final payload   = (cmd['payload']  as Map<String, dynamic>?) ?? {};

    if (commandId != null && commandId.isNotEmpty) {
      if (!_processedCommandIds.add(commandId)) return;
    }

    switch (type) {
      case 'AGENT_ASSIGNED':
        _agentTimeoutTimer?.cancel();
        _setHitlState(HitlState.agentAssigned);
        _agentNameCtrl.add(payload['agentName'] as String? ?? 'Agent');

      case 'CALL_REQUEST':
        _activeCallId = payload['callId'] as String?;
        _setHitlState(HitlState.callRequest);

      case 'CALL_JOIN':
        _activeCallId = payload['callId'] as String?;
        _setCallState(CallState.inCall);
        _setHitlState(HitlState.inCall);
        _fetchTokenAndJoin(payload);

      case 'CALL_END':
        _activeCallId = null;
        _setCallState(CallState.idle);
        _callEndCtrl.add(null);

      case 'APPROVED':
        _handleHitlDecision('APPROVED');

      case 'REJECTED':
        _handleHitlDecision('REJECTED');

      case 'SEND_FORM':
      case 'FORM_URL_RESPONSE':
        final formUrl = payload['formUrl'] as String? ?? '';
        if (formUrl.isNotEmpty) _sendFormCtrl.add(formUrl);

      case 'SEND_SCAN':
        final deviceType = payload['deviceType'] as String? ?? 'camera';
        _sendScanCtrl.add(deviceType);
    }
  }

  Future<void> _fetchTokenAndJoin(Map<String, dynamic> payload) async {
    final roomName = payload['roomName'] as String? ?? '';
    final roomUrl  = payload['roomUrl']  as String?
        ?? payload['serverUrl'] as String?
        ?? payload['url']       as String?
        ?? _livekitUrl;

    if (roomName.isEmpty) { _callJoinCtrl.add(payload); return; }

    try {
      final res = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'Apikey':              _livekitApiKey,
          'ParticipantIdentity': 'Mobile User',
          'participantName':     'Mobile User',
          'RoomName':            roomName,
          'secret':              _livekitApiSecret,
          'sessionId':           _hitlSessionId ?? roomName,
          'roomName':            roomName,
        }),
      ).timeout(const Duration(seconds: 10));
      final data  = jsonDecode(res.body) as Map<String, dynamic>;
      final token = data['token']       as String?
          ?? data['Token']              as String?
          ?? data['accessToken']        as String?
          ?? (data['data'] as Map<String, dynamic>?)?['token'] as String?;
      if (token != null && token.isNotEmpty) {
        _callJoinCtrl.add({...payload, 'roomUrl': roomUrl, 'token': token});
        return;
      }
    } catch (_) {}
    _callJoinCtrl.add({...payload, 'roomUrl': roomUrl});
  }

  bool _hitlEndSent = false;

  void _handleHitlDecision(String result) {
    _setHitlState(result == 'APPROVED' ? HitlState.approved : HitlState.rejected);
    if (!_hitlEndSent) {
      _hitlEndSent = true;
      _beat(extra: {'event': 'hitl_end', 'reason': 'HITL_COMPLETE'});
    }
    _hitlResultCtrl.add(result);
    _endHitlSession();
  }

  void _setCallState(CallState s) { _callState = s; _callStateCtrl.add(s); }
  void _setHitlState(HitlState s) { _hitlState = s; _hitlStateCtrl.add(s); }

  // ── Regular call ─────────────────────────────────────────────────────────
  Future<void> requestCall() async {
    if (_callState != CallState.idle) return;
    _setCallState(CallState.calling);
    await _beat(extra: {'event': 'video_call_requested'});
  }

  Future<void> cancelCall() async {
    final cid = _activeCallId;
    _activeCallId = null;
    _setCallState(CallState.idle);
    await _beat(extra: cid != null
        ? {'event': 'CALL_REJECT', 'callId': cid, 'reason': 'USER_CANCELLED'}
        : {'event': 'CALL_END',    'reason': 'USER_CANCELLED'});
  }

  Future<void> endCall() async {
    final cid = _activeCallId;
    _activeCallId = null;
    _setCallState(CallState.idle);
    if (cid != null) await _beat(extra: {'event': 'CALL_END', 'callId': cid});
  }

  // ── Node recording ───────────────────────────────────────────────────────

  /// Record a completed form group.
  void recordFormNode(String label, Map<String, String> formValues, {String? rendererUrl}) {
    _nodeStep++;
    final nodeId = 'NODE_${label.toUpperCase().replaceAll(' ', '_')}_$_nodeStep';
    final url = rendererUrl ?? '';
    _formNodes[nodeId] = _FormNode(nodeId: nodeId, formValues: formValues, rendererUrl: url);
    if (!_visitedNodes.contains(nodeId)) _visitedNodes.add(nodeId);
    _currentNodeId = nodeId;
  }

  /// Record a document/image capture. [base64Data] may include data URI prefix.
  void recordDocumentNode(String label, String base64Data) {
    _nodeStep++;
    final nodeId = 'NODE_${label.toUpperCase().replaceAll(' ', '_')}_$_nodeStep';
    final clean  = base64Data.contains(',') ? base64Data.split(',').last : base64Data;

    _documentNodes[nodeId] = _DocumentNode(nodeId: nodeId, base64Data: clean);
    if (!_visitedNodes.contains(nodeId)) _visitedNodes.add(nodeId);
    _currentNodeId = nodeId;
  }

  // ── HITL session ─────────────────────────────────────────────────────────
  Future<void> startHitlSession({
    required String journeyName,
    int agentTimeoutSeconds = 60,
  }) async {
    // Force-reset any stale HITL state from a previous unclean session
    _agentTimeoutTimer?.cancel();
    _hitlEndSent  = false;
    _activeCallId = null;
    _setCallState(CallState.idle);
    _setHitlState(HitlState.idle);

    _hitlJourneyName = journeyName;
    _hitlSessionId   = sessionId; // will be updated after _ensureSession
    _hitlWorkflowId  = _buildWorkflowId(journeyName);

    // Reset per-HITL tracking so old commands/acks don't bleed in
    _processedCommandIds.clear();
    _lastAck = 0;

    // Re-register session if server has expired it (handles 404 on second HITL)
    final sessionOk = await _ensureSession();
    if (!sessionOk) {
      print('[HITL] failed to ensure session — aborting hitl_start');
      _setHitlState(HitlState.idle);
      return;
    }
    _hitlSessionId = sessionId;

    print('[HITL] startHitlSession — appSessionId=$sessionId hitlSessionId=$_hitlSessionId workflowId=$_hitlWorkflowId journeyName=$_hitlJourneyName lastAck=$_lastAck');

    _setHitlState(HitlState.waitingAgent);

    // Stop any in-flight heartbeat then send hitl_start immediately
    _beating = false;
    await _beat(extra: _buildHitlStartPayload());

    _agentTimeoutTimer = Timer(Duration(seconds: agentTimeoutSeconds), _onAgentTimeout);
  }

  /// Verifies the current session is alive; re-registers if the server has expired it.
  Future<bool> _ensureSession() async {
    if (sessionId == null) return _registerSession();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/session/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionId': sessionId, 'lastProcessedSequenceId': 0}),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final ok = data['success'] == true ||
                 data['success'] == 1 ||
                 data['success'].toString() == 'true';
      if (ok) {
        print('[Session] _ensureSession: session still alive sessionId=$sessionId');
        return true;
      }
      // 404 or success=false — session expired, re-register
      print('[Session] _ensureSession: session expired (${res.statusCode}), re-registering...');
      _heartbeatTimer?.cancel();
      sessionId = null;
      final restarted = await _registerSession();
      return restarted;
    } catch (e) {
      print('[Session] _ensureSession error: $e');
      return false;
    }
  }

  void _onAgentTimeout() {
    if (_hitlState != HitlState.waitingAgent) return;
    if (!_hitlEndSent) {
      _hitlEndSent = true;
      _beat(extra: {'event': 'hitl_end', 'reason': 'SESSION_RESET'});
    }
    _endHitlSession();
    _hitlResultCtrl.add('TIMEOUT');
  }

  /// Builds the exact SessionJson structure the dashboard reads.
  /// Sent as `state` field in the hitl_start heartbeat body.
  Map<String, dynamic> _buildSessionJson() {
    // Build nodeStates map — ordered by visitedNodes
    final nodeStates = <String, dynamic>{};
    for (final nodeId in _visitedNodes) {
      if (_formNodes.containsKey(nodeId)) {
        nodeStates[nodeId] = _formNodes[nodeId]!.toJson();
      } else if (_documentNodes.containsKey(nodeId)) {
        nodeStates[nodeId] = _documentNodes[nodeId]!.toJson();
      }
    }

    final now = DateTime.now().toIso8601String();

    return {
      'session': {
        'sessionId':                 _hitlSessionId,
        'channel':                   'Mobile',
        'journeyName':               _hitlJourneyName,
        'workflowId':                _hitlWorkflowId,
        'currentNodeId':             _currentNodeId,
        'currentStage':              'PROCESSING',
        'humanInterventionRequired': true,
        'priority':                  'NORMAL',
        'status':                    'WAITING_FOR_HUMAN',
        'createdAt':                 now,
        'updatedAt':                 now,
        'meta': {
          'sourceSystem': 'Mobile',
          'tenant':       'Infrasoft',
          'groupOffice':  'kiyaaibank',
        },
      },
      'customer': null,
      'runtime': {
        'executionMode':           'LIVE',
        'visitedNodes':            List<String>.from(_visitedNodes),
        'nodeStates':              nodeStates,
        'currentExecutionPointer': _currentNodeId,
      },
      'audit': {
        'createdBy':      'NBP',
        'lastModifiedBy': 'GENIE',
        'eventLogs': [
          {'event': 'WORKFLOW_STARTED',           'timestamp': now},
          {'event': 'HUMAN_INTERVENTION_INVOKED', 'timestamp': now},
        ],
      },
    };
  }

  Map<String, dynamic> _buildHitlStartPayload() {
    final sessionJson = _buildSessionJson();
    return {
      // Top-level fields the server reads for routing/SSE broadcast
      'event':          'hitl_start',
      'journeyName':    _hitlJourneyName,
      'workflowId':     _hitlWorkflowId,
      'tenant':         'Infrasoft',
      'groupOffice':    'Kiyaaibank',
      'channel':        'Mobile',
      'deviceId':       _deviceId,
      'podId':          'POD-MOBILE',
      'branchLocation': 'Mobile App',
      'currentScreen':  'chat_screen',
      // Full SessionJson under 'state' — dashboard reads this via setActiveSessions → sessionState
      'state':          sessionJson,
      // Also send sessionState at root for servers that read it directly
      'sessionState':   sessionJson,
    };
  }

  void _endHitlSession() {
    _agentTimeoutTimer?.cancel();
    _hitlSessionId   = null;
    _hitlWorkflowId  = null;
    _hitlJourneyName = null;
    _activeCallId    = null;
    _hitlEndSent     = false;
    _lastAck         = 0;
    _processedCommandIds.clear();
    _setCallState(CallState.idle);
    _setHitlState(HitlState.idle);
  }

  Future<void> endHitlCall() async {
    final cid = _activeCallId;
    _activeCallId = null;
    _setCallState(CallState.idle);
    if (!_hitlEndSent) {
      _hitlEndSent = true;
      _beat(extra: {'event': 'hitl_end', 'reason': 'HITL_COMPLETE'});
    }
    if (cid != null) await _beat(extra: {'event': 'CALL_END', 'callId': cid});
    _endHitlSession();
  }

  Future<void> cancelHitl() async {
    _agentTimeoutTimer?.cancel();
    if (!_hitlEndSent) {
      _hitlEndSent = true;
      _beat(extra: {'event': 'hitl_end', 'reason': 'SESSION_RESET'});
    }
    _endHitlSession();
  }

  /// Send a state_update heartbeat with full session state + submitted form URL.
  /// Does NOT create a new node — the node was already recorded by recordFormNode
  /// in _djConfirmForm with the correct renderer URL.
  Future<void> sendStateUpdate(Map<String, String> formValues, {String? formUrl}) async {
    // Force-clear the beating guard so this important event is never dropped
    _beating = false;
    final state = _buildSessionJson();
    await _beat(extra: {
      'event':        'state_update',
      'state':        state,
      'sessionState': state,
      'formData':     formValues,
    });
  }

  void resetJourneyNodes() {
    _formNodes.clear();
    _documentNodes.clear();
    _visitedNodes.clear();
    _currentNodeId = null;
    _nodeStep = 0;
  }

  // ── App session end ──────────────────────────────────────────────────────
  Future<void> endSession() async {
    _heartbeatTimer?.cancel();
    _agentTimeoutTimer?.cancel();
    if (sessionId == null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/session/end'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionId': sessionId, 'reason': 'USER_EXIT'}),
      ).timeout(const Duration(seconds: 6));
    } catch (_) {}
    sessionId = null;
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _agentTimeoutTimer?.cancel();
    _callStateCtrl.close();
    _callJoinCtrl.close();
    _callEndCtrl.close();
    _hitlStateCtrl.close();
    _hitlResultCtrl.close();
    _agentNameCtrl.close();
    _sendFormCtrl.close();
    _sendScanCtrl.close();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  static String _buildWorkflowId(String journeyName) =>
      'WF-${journeyName.trim().toUpperCase().replaceAll(' ', '-').replaceAll('_', '-')}';

  /// Deep-clone a map/list, replacing any base64 string values with '<base64>'.
  static dynamic _stripBase64(dynamic v) {
    if (v is Map) {
      return Map<String, dynamic>.fromEntries(
        v.entries.map((e) => MapEntry(e.key.toString(), _stripBase64(e.value))),
      );
    } else if (v is List) {
      return v.map(_stripBase64).toList();
    } else if (v is String && v.startsWith('data:image/')) {
      return '<dataUri:${v.length}chars>';
    } else if (v is String && v.length > 200 && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(v)) {
      return '<base64:${v.length}chars>';
    }
    return v;
  }

  static void _logJson(String tag, Map<String, dynamic> data) {
    final stripped = _stripBase64(data) as Map<String, dynamic>;
    final json = jsonEncode(stripped);
    const chunk = 600;
    final total = (json.length / chunk).ceil();
    for (int i = 0; i < json.length; i += chunk) {
      final part = i ~/ chunk;
      print('$tag [${part + 1}/$total] ${json.substring(i, (i + chunk).clamp(0, json.length))}');
    }
  }
}
