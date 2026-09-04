import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../core/models/chat_message.dart';
import '../../core/services/chat_db_service.dart';
import '../../core/services/face_compare_service.dart';
import '../../core/services/network_service.dart';
import '../../core/services/request_handler_service.dart';
import '../../core/services/meta_room_service.dart';
import '../../core/services/slm_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/livekit_service.dart';
import '../../core/services/live_call_service.dart';
import 'package:livekit_client/livekit_client.dart' hide ChatMessage;
import 'widgets/message_bubble.dart';
import 'widgets/choice_panel.dart';
import 'widgets/form_panel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _db = ChatDbService();
  final _network = NetworkService();
  final _rh = RequestHandlerService();
  final _metaRoom = MetaRoomService();
  final _slm = SlmService();
  final _faceCompareService = FaceCompareService();
  final _session  = SessionService();
  final _liveKit   = LiveKitService();
  final _liveCall  = LiveCallService();
  final _stt = SpeechToText();
  final _picker = ImagePicker();
  final _inputCtrl = TextEditingController();

  List<ChatMessage> _messages = [];
  bool _isOnline = true;
  bool _isManualOffline = false;
  bool _isFlightMode = false;
  bool _djLoading = false;
  bool _isListening = false;
  bool _showOffline = false;
  bool _showExitConfirm = false;
  bool _showEndSessionModal = false;

  // ── Session call state (HITL / workflow) ──
  CallState _callState = CallState.idle;
  HitlState _hitlState = HitlState.idle;
  String _hitlAgentName = '';
  List<RemoteParticipant> _remoteParticipants = [];
  bool _callMicOn = true;
  bool _callCamOn = true;
  bool _sessionConnected = false;
  StreamSubscription<List<RemoteParticipant>>? _participantsSub;

  // ── Live call state (direct, no session) ──
  LiveCallState _liveCallState = LiveCallState.idle;

  // ── HITL agent-pushed overlays ──
  String? _hitlScanType;   // non-null → show agent scan overlay
  bool _hitlCallMinimized = false;
  String? _agentFormUrl;   // URL to fetch form JSON from
  bool _isAgentForm = false; // true → form was pushed by agent, submit sends state_update

  // SLM state — matches Angular slmState enum
  String _slmState = 'idle'; // idle | checking | downloading | initialising | ready | error
  String _slmCurrentFile   = '';
  int    _slmFileProgress  = 0;
  int    _slmTotalProgress = 0;
  String _slmErrorMsg      = '';

  bool get _slmModelReady => _slmState == 'ready';

  String _panelType = 'none';
  String _panelQuestion = '';
  List<JourneyChoice> _djChoices = [];
  String _djChoiceType = 'radio';
  String _djSelectedChoice = '';
  List<String> _djSelectedChoices = [];
  bool _djChoiceIsQuickReply = false;
  List<JourneyFormGroup> _djFormGroups = [];
  int _djFormGroupIndex = 0;
  bool _djFormHasErrors = false;

  late RHConfig _rhConfig;
  String _rhMsgid = 'startchattingevent';
  dynamic _rhWelcomeqr;
  String _rhSessionId = '';
  bool _rhConfigReady = false;
  String? _rhPendingMessage;
  String? _rhFirstUserMessage;
  final _rhBotConfigUrl =
      'https://genieconsolesit.kiya.ai:5443/GENBOTS2.0/message/getBotsConfigurationByName';

  String _metaRoomStep = 'idle';
  String _metaRoomPendingName = '';
  String _sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
  String? _docImageBase64;

  String _lyricText = '';
  bool _lyricVisible = false;
  bool _showLyricStage = false;
  bool _showTapPrompt = false;
  String _tapPromptLabel = '';
  String? _tapPromptAction;

  final _quickLinks = [
    {'label': 'New Account Opening', 'prompt': 'I want to open a new bank account'},
    {'label': 'Fund Transfer', 'prompt': 'I want to transfer money'},
    {'label': 'Check Balance', 'prompt': 'Check my last 5 transactions'},
    {'label': 'FAQ', 'prompt': 'FAQ'},
    {'label': 'Login to Meta Room', 'prompt': 'Login to Meta Room'},
  ];

  @override
  void initState() {
    super.initState();
    _rhConfig = RHConfig(
      baseUrl: 'https://kiyabots.kiya.ai',
      botname: 'Kiya_INDIA_Mobile',
      groupOfficeName: 'KiyaAiBank',
      organisationName: 'Infrasoft',
      channeltype: 'Web',
      contexttype: 'p2p',
      channelid: RequestHandlerService.genChannelId(),
      display: 'Gen Ai',
      subdisplay: '',
    );
    WidgetsBinding.instance.addObserver(this);
    _db.init();
    _initNetwork();
    _initSession();
    _bootstrapSlm();
    _initStt();
    _metaRoom.authenticated$.listen((session) {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.metaRoom == 'qr');
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(
            metaRoom: 'authenticated',
            metaRoomSession: session.toJson(),
          );
        }
      });
    });
  }

  /// Long-press the session pill in the AppBar to request a video call
  void _simulateIncomingCall() {
    _session.requestCall();
  }

  void _initSession() async {
    final started = await _session.startSession('mobile_${DateTime.now().millisecondsSinceEpoch}');
    if (!started || !mounted) return;
    setState(() => _sessionConnected = true);
    _session.callState$.listen((state) {
      if (!mounted) return;
      setState(() => _callState = state);
    });
    _session.hitlState$.listen((state) {
      if (!mounted) return;
      setState(() => _hitlState = state);
    });
    _session.agentName$.listen((name) {
      if (!mounted) return;
      setState(() => _hitlAgentName = name);
    });
    _session.hitlResult$.listen((result) {
      if (!mounted) return;
      _onHitlResult(result);
    });
    _session.sendForm$.listen((url) {
      if (!mounted) return;
      _loadAgentForm(url);
    });
    _session.sendScan$.listen((deviceType) {
      if (!mounted) return;
      setState(() { _hitlScanType = deviceType; _hitlCallMinimized = true; });
    });
    _participantsSub = _liveKit.participants$.listen((participants) {
      if (!mounted) return;
      setState(() => _remoteParticipants = participants);
    });
    _session.callJoin$.listen((payload) async {
      final url = payload['roomUrl'] as String? ?? '';
      final token = payload['token'] as String? ?? '';
      if (url.isEmpty || token.isEmpty) return;
      await _liveKit.connect(url, token, onDisconnected: () {
        // Remote disconnect during HITL — end HITL call
        if (_hitlState != HitlState.idle) {
          _session.endHitlCall();
        } else {
          _session.endCall();
        }
        if (!mounted) return;
        setState(() { _remoteParticipants = []; _callMicOn = true; _callCamOn = true; _hitlCallMinimized = false; });
      });
    });
    _session.callEnd$.listen((_) async {
      await _liveKit.disconnect();
      if (!mounted) return;
      setState(() {
        _remoteParticipants = [];
        _callMicOn = true;
        _callCamOn = true;
        _hitlCallMinimized = false;
      });
    });
    _initLiveCall();
  }

  void _initLiveCall() {
    _liveCall.state$.listen((state) {
      if (!mounted) return;
      setState(() => _liveCallState = state);
    });
    _liveCall.callReady$.listen((payload) async {
      final url   = payload['roomUrl'] as String? ?? '';
      final token = payload['token']   as String? ?? '';
      if (url.isEmpty || token.isEmpty) return;
      // onDisconnected fires only when remote side (dashboard) ends the call
      await _liveKit.connect(url, token, onDisconnected: () {
        _liveCall.endCall();
        if (!mounted) return;
        setState(() { _remoteParticipants = []; _callMicOn = true; _callCamOn = true; });
      });
    });
    _liveCall.callEnded$.listen((_) async {
      await _liveKit.disconnect();
      if (!mounted) return;
      setState(() {
        _remoteParticipants = [];
        _callMicOn = true;
        _callCamOn = true;
      });
    });
  }

  void _initNetwork() async {
    _isOnline = await _network.isOnline();
    _isFlightMode = await _network.isFlightMode();
    if (_isOnline && !_isManualOffline) _fetchBotConfig();
    _network.onlineStream.listen((online) {
      if (!mounted) return;
      final wasOffline = !_isOnline;
      setState(() {
        _isOnline = online;
        _showOffline = !online && !_isManualOffline;
      });
      if (online && !_isManualOffline) {
        if (wasOffline && _messages.isNotEmpty) {
          _startNewSession();
        } else {
          _fetchBotConfig();
        }
      }
    });
    _network.flightModeStream.listen((flight) {
      if (!mounted) return;
      final isFlight = flight && !_isManualOffline;
      setState(() => _isFlightMode = isFlight);
      if (isFlight) {
        setState(() => _panelType = 'none');
        if (_slmModelReady) {
          _pushBot("You're in flight mode — using On-Device AI. Your data stays private on your device. How can I help you?");
        } else {
          _pushBot("You're in flight mode. On-device AI is not ready yet — please wait or check settings.");
        }
      }
    });
  }

  void _fetchBotConfig() async {
    try {
      final config = await _rh.fetchBotConfig(
          _rhBotConfigUrl, _rhConfig.botname,
          _rhConfig.groupOfficeName, _rhConfig.organisationName);
      if (!mounted) return;
      if (config['isactive'] == 'Y') {
        if (config['templatename'] != null) _rhConfig.display = config['templatename'];
        _rhWelcomeqr = config['welcomeqr'];
      }
      setState(() => _rhConfigReady = true);
      _flushPending();
    } catch (_) {
      if (mounted) setState(() => _rhConfigReady = true);
      _flushPending();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When returning from camera/gallery, clear any stuck _beating flag
    if (state == AppLifecycleState.resumed) _session.clearBeating();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transcriptNotifier.dispose();
    _voiceActiveNotifier.dispose();
    _inputCtrl.dispose();
    _metaRoom.dispose();
    _participantsSub?.cancel();
    _liveKit.dispose();
    _session.dispose();
    _liveCall.dispose();
    super.dispose();
  }

  void _bootstrapSlm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dlPref = prefs.getString('slm_model_download') ?? 'wifi_only';
      if (dlPref == 'disabled') {
        if (mounted) setState(() => _slmState = 'error');
        return;
      }
      if (mounted) setState(() => _slmState = 'checking');
      final ready = await _slm.checkModel();
      if (!ready) {
        if (dlPref == 'wifi_only') {
          final onWifi = await _network.isWifi();
          if (!onWifi) {
            if (mounted) setState(() { _slmState = 'error'; _slmErrorMsg = 'Wi-Fi required to download AI models.'; });
            return;
          }
        }
        if (mounted) setState(() => _slmState = 'downloading');
        await _slm.downloadModels((p) {
          if (mounted) {
            setState(() {
            _slmCurrentFile   = p.file;
            _slmFileProgress  = p.fileProgress;
            _slmTotalProgress = p.totalProgress;
          });
          }
        });
      }
      if (mounted) setState(() => _slmState = 'initialising');
      await _slm.init();
      await _slm.initSlm();
      if (mounted) setState(() => _slmState = 'ready');
    } catch (e) {
      if (mounted) setState(() { _slmState = 'error'; _slmErrorMsg = e.toString(); });
    }
  }

  void _initStt() async {
    _sttReady = await _stt.initialize(
      onError: (e) => debugPrint('[STT] error: ${e.errorMsg}'),
    );
  }

  void _retrySlm() {
    setState(() { _slmErrorMsg = ''; });
    _slm.resetInit();
    _bootstrapSlm();
  }

  void _launchMetaverse() {
    const channel = MethodChannel('com.kiya.bankinggenie/metaverse');
    channel.invokeMethod('launch').catchError((_) {});
  }

  String _now() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _pushBot(String text, {String? chartImage, String? tableHtml, String? csvData}) {
    setState(() => _messages.add(ChatMessage(from: 'bot', text: text, time: _now(), chartImage: chartImage, tableHtml: tableHtml, csvData: csvData)));
    _db.saveMessage({'session_id': _sessionId, 'from_role': 'bot', 'message': text, 'created_at': DateTime.now().millisecondsSinceEpoch});
  }

  void _pushUser(String text, {String? fileName}) {
    setState(() => _messages.add(ChatMessage(from: 'user', text: text, time: _now(), fileName: fileName)));
    _db.saveMessage({'session_id': _sessionId, 'from_role': 'user', 'message': text.isNotEmpty ? text : fileName ?? '', 'file_name': fileName, 'created_at': DateTime.now().millisecondsSinceEpoch});
  }

  void _pushUserCard(String title, List<Map<String, String>> card) {
    setState(() => _messages.add(ChatMessage(from: 'user', text: title, time: _now(), card: card)));
    // Save as JSON: {"__title__": "...", "Label": "value", ...}
    final data = <String, String>{'__title__': title};
    for (final r in card) { data[r['label']!] = r['value']!; }
    _db.saveMessage({'session_id': _sessionId, 'from_role': 'user', 'message': jsonEncode(data), 'created_at': DateTime.now().millisecondsSinceEpoch});
  }

  void _resetChatState() {
    _metaRoom.stopPolling();
    setState(() {
      _messages = [];
      _panelType = 'none';
      _djChoices = [];
      _djFormGroups = [];
      _djFormGroupIndex = 0;
      _isAgentForm = false;
      _djSelectedChoice = '';
      _djSelectedChoices = [];
      _djLoading = false;
      _metaRoomStep = 'idle';
      _metaRoomPendingName = '';
      _rhPendingMessage = null;
      // Reset lyric/tap state
      _showLyricStage = false;
      _lyricVisible = false;
      _showTapPrompt = false;
      _tapPromptAction = null;
      _docImageBase64 = null;
      // Reset voice state
      _globalVoiceActive = false;
      _globalVoiceTranscript = '';
      _gvFieldTarget = '';
      _gvVoiceMatchValue = '';
    });
    _transcriptNotifier.value = '';
    _voiceActiveNotifier.value = false;
    _gvListening = false;
    _gvProcessed = false;
    _gvFinalHandled = false;
    _gvLastPartial = '';
    _gvSessionId++;
    _stt.stop();
    _slm.reset();
    // Reset journey node recording for new chat session
    _session.resetJourneyNodes();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appBg = cs.surface == Colors.white
        ? Theme.of(context).scaffoldBackgroundColor
        : Theme.of(context).scaffoldBackgroundColor;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => setState(() => _showExitConfirm = true),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        resizeToAvoidBottomInset: false,
        appBar: _buildAppBar(),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              Column(
                children: [
                  if (_isFlightMode) _buildFlightModeBanner(),
                  Expanded(child: _buildMessageList()),
                  if (_panelType == 'choice') _buildChoicePanel(),
                  if (_panelType == 'form') _buildFormPanel(),
                  if (_panelType == 'none') _buildInputBar(),
                ],
              ),
              if (_showLyricStage) _buildLyricOverlay(),
              // HITL overlays — only show waiting/assigned when NOT yet in call
              if (_hitlState == HitlState.waitingAgent) _buildHitlWaitingOverlay(),
              if (_hitlState == HitlState.agentAssigned) _buildHitlAgentAssignedOverlay(),
              if (_hitlState == HitlState.callRequest) _buildHitlCallRequestOverlay(),
              // Agent-pushed scan overlay
              if (_hitlScanType != null) _buildHitlScanOverlay(_hitlScanType!),
              // HITL video call — full screen or minimized PiP
              if (_hitlState == HitlState.inCall && !_hitlCallMinimized) _buildCallOverlay(
                agentName: _hitlAgentName,
                onMinimize: () => setState(() => _hitlCallMinimized = true),
                onEnd: () async {
                  await _liveKit.disconnect();
                  await _session.endHitlCall();
                  setState(() { _remoteParticipants = []; _callMicOn = true; _callCamOn = true; _hitlCallMinimized = false; });
                },
              ),
              if (_hitlState == HitlState.inCall && _hitlCallMinimized)
                _buildHitlMinimizedPip(
                  onExpand: () => setState(() => _hitlCallMinimized = false),
                  onEnd: () async {
                    await _liveKit.disconnect();
                    await _session.endHitlCall();
                    setState(() { _remoteParticipants = []; _callMicOn = true; _callCamOn = true; _hitlCallMinimized = false; });
                  },
                ),
              if (_hitlState == HitlState.inCall && _hitlCallMinimized)
                _buildHitlDashboardPanel(),
              // Regular session call (non-HITL)
              if (_callState == CallState.calling && _hitlState == HitlState.idle) _buildCallingOverlay(),
              if (_callState == CallState.inCall && _hitlState == HitlState.idle) _buildCallOverlay(),
              if (_liveCallState == LiveCallState.requesting) _buildLiveCallRequestingOverlay(),
              if (_liveCallState == LiveCallState.inCall &&
                  _callState != CallState.inCall &&
                  _hitlState == HitlState.idle) _buildCallOverlay(onEnd: _liveCall.endCall),
              if (_showExitConfirm) _buildDialog(
                title: 'Exit App?',
                message: 'Are you sure you want to exit?',
                confirmLabel: 'Exit',
                confirmColor: Colors.redAccent,
                onConfirm: () => MethodChannel('com.kiya.bankinggenie/app').invokeMethod('exitApp'),
                onCancel: () => setState(() => _showExitConfirm = false),
              ),
              if (_showEndSessionModal) _buildDialog(
                title: 'New Session?',
                message: 'This will clear the current chat.',
                confirmLabel: 'Start New',
                confirmColor: cs.primary,
                onConfirm: _startNewSession,
                onCancel: () => setState(() => _showEndSessionModal = false),
              ),
              // Mic FAB — only shown when form or choice panel is active
              if ((_panelType == 'form' || _panelType == 'choice') &&
                  !_showLyricStage &&
                  !_isManualOffline &&
                  !_isFlightMode &&
                  _isOnline &&
                  _hitlState == HitlState.idle &&
                  _callState == CallState.idle &&
                  _liveCallState == LiveCallState.idle)
                Positioned(
                  right: 12,
                  bottom: 68,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _voiceActiveNotifier,
                    builder: (_, active, __) => ValueListenableBuilder<String>(
                      valueListenable: _transcriptNotifier,
                      builder: (_, transcript, __) => _VoiceFab(
                        active: active,
                        transcript: transcript,
                        onTap: _toggleGlobalVoice,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final onSurface = cs.onSurface;
    final surfaceColor = Theme.of(context).appBarTheme.backgroundColor ?? cs.surface;

    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;
    if (_isFlightMode) {
      statusColor = const Color(0xFF6366F1);
      statusLabel = 'Flight Mode';
      statusIcon  = Icons.airplanemode_active_rounded;
    } else if (_djLoading) {
      statusColor = primary;
      statusLabel = 'Thinking…';
      statusIcon  = Icons.sync_rounded;
    } else if (_isManualOffline || !_isOnline) {
      statusColor = const Color(0xFFEF4444);
      statusLabel = 'Offline';
      statusIcon  = Icons.wifi_off_rounded;
    } else {
      statusColor = const Color(0xFF16A34A);
      statusLabel = 'Online';
      statusIcon  = Icons.wifi_rounded;
    }

    return AppBar(
      backgroundColor: surfaceColor,
      automaticallyImplyLeading: false,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 10,
      toolbarHeight: 52,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: onSurface.withValues(alpha: 0.08)),
      ),
      title: Row(children: [
        // Avatar
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary.withValues(alpha: 0.12),
            border: Border.all(color: primary.withValues(alpha: 0.3), width: 1.5),
          ),
          child: ClipOval(child: Transform.flip(
            flipX: true,
            child: Image.asset('assets/images/user_icon.png', fit: BoxFit.cover),
          )),
        ),
        const SizedBox(width: 8),
        // Title + status
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('BankingGenie',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: onSurface, fontSize: 14,
                      fontWeight: FontWeight.w700, height: 1.2)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 9, color: statusColor),
                const SizedBox(width: 3),
                Text(statusLabel,
                    style: TextStyle(color: statusColor, fontSize: 10, height: 1.2,
                        fontWeight: FontWeight.w600)),
              ]),
            ],
          ),
        ),
      ]),
      actions: [
        // Flight mode button — only shown when in flight mode
        if (_isFlightMode)
          _appBarBtn(
            icon: Icons.airplanemode_active_rounded,
            color: const Color(0xFF6366F1),
            tooltip: 'Flight mode active',
            onTap: () {},
          ),
        // SLM status
        if (_slmState == 'downloading' || _slmState == 'initialising')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
            child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
          )
        else if (_slmState == 'error')
          _appBarBtn(
            icon: Icons.refresh_rounded,
            color: const Color(0xFFF59E0B),
            tooltip: 'Retry offline AI',
            onTap: _retrySlm,
          ),
        // Wifi toggle — hidden in flight mode
        if (!_isFlightMode)
          _appBarBtn(
            icon: _isManualOffline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
            color: _isManualOffline ? const Color(0xFFEF4444) : primary,
            tooltip: _isManualOffline ? 'Switch online' : 'Switch offline',
            onTap: () {
              final goingOffline = !_isManualOffline;
              setState(() {
                _isManualOffline = goingOffline;
                if (goingOffline) _showOffline = false;
              });
              if (goingOffline) {
                setState(() => _panelType = 'none');
                if (_slmModelReady) {
                  _pushBot("You're using On-Device AI. Your data stays private on your device. How can I help you?");
                } else {
                  _pushBot("You're now in offline mode. On-device AI is not ready yet — please wait or check settings.");
                }
              }
            },
          ),
        // Live call
        if (_liveCallState == LiveCallState.idle && _callState == CallState.idle && !_isManualOffline && _isOnline)
          _appBarBtn(
            icon: Icons.video_call_rounded,
            color: const Color(0xFF329AD6),
            tooltip: 'Start live call',
            onTap: () => _liveCall.requestCall(
              deviceId: 'mobile_user',
              callerName: 'Mobile User',
              branchLocation: 'Mobile App',
            ),
          ),
        // History
        _appBarBtn(
          icon: Icons.history_rounded,
          color: onSurface.withValues(alpha: 0.5),
          tooltip: 'History',
          onTap: () => context.push('/history'),
        ),
        // Settings
        _appBarBtn(
          icon: Icons.settings_outlined,
          color: onSurface.withValues(alpha: 0.5),
          tooltip: 'Settings',
          onTap: () => context.push('/settings'),
        ),
        // New chat
        if (_messages.isNotEmpty)
          _appBarBtn(
            icon: Icons.add_comment_outlined,
            color: onSurface.withValues(alpha: 0.5),
            tooltip: 'New chat',
            onTap: () => setState(() => _showEndSessionModal = true),
          ),
        GestureDetector(
          onLongPress: _sessionConnected ? _simulateIncomingCall : null,
          child: const SizedBox(width: 4),
        ),
      ],
    );
  }

  Widget _appBarBtn({required IconData icon, required Color color, required String tooltip, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 14),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildOfflineBanner() => const SizedBox.shrink();

  Widget _buildFlightModeBanner() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
      child: const Row(children: [
        Icon(Icons.airplanemode_active_rounded, color: Colors.white, size: 15),
        SizedBox(width: 8),
        Expanded(child: Text('Flight mode is on — using on-device AI',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) return _buildQuickLinks();
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      itemCount: _messages.length + (_djLoading ? 1 : 0),
      itemBuilder: (_, i) {
        if (_djLoading && i == 0) return _buildTypingIndicator();
        final msgIndex = _messages.length - 1 - (i - (_djLoading ? 1 : 0));
        return MessageBubble(
            message: _messages[msgIndex],
            index: msgIndex,
            onRetryMetaRoom: _retryMetaRoomLogin,
            onNewSession: _startNewSession);
      },
    );
  }

  // Icons for each quick link
  static const _quickLinkIcons = [
    Icons.account_balance_outlined,
    Icons.swap_horiz_rounded,
    Icons.account_balance_wallet_outlined,
    Icons.help_outline_rounded,
    Icons.view_in_ar_rounded,
  ];

  Widget _buildQuickLinks() {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final onSurface = cs.onSurface;
    final surface = Theme.of(context).appBarTheme.backgroundColor ?? cs.surface;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
      child: Column(
        children: [
          Container(
            width: 80, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // color: surface,
              boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.2), blurRadius: 24, spreadRadius: 2)],
            ),
            child: Image.asset('assets/images/app-new-icon.png', fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
          Text('KiyaAI Banking Assistant',
              textAlign: TextAlign.center,
              style: TextStyle(color: onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('How can I assist you today?',
              textAlign: TextAlign.center,
              style: TextStyle(color: onSurface.withValues(alpha: 0.5), fontSize: 13)),
          const SizedBox(height: 24),
          if (_slmState != 'ready') ...[_buildSlmCard(), const SizedBox(height: 20)],
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Try asking:',
                style: TextStyle(color: onSurface.withValues(alpha: 0.35), fontSize: 11,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: onSurface.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: List.generate(_quickLinks.length, (i) {
                final q = _quickLinks[i];
                final isLast = i == _quickLinks.length - 1;
                return _buildQuickLinkTile(q, isLast);
              }),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _launchMetaverse,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: onSurface.withValues(alpha: 0.08)),
              ),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: primary.withValues(alpha: 0.1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/images/metaverse.png', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Enter Meta Room',
                        style: TextStyle(color: onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Immersive 3D banking experience',
                        style: TextStyle(color: onSurface.withValues(alpha: 0.4), fontSize: 11)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: onSurface.withValues(alpha: 0.3), size: 18),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLinkTile(Map<String, String> q, bool isLast) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _sendMessage(prefill: q['prompt']),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.07))),
        ),
        child: Row(children: [
          Expanded(
            child: Text(q['prompt']!,
                style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Icon(Icons.chevron_right_rounded, color: cs.primary, size: 18),
        ]),
      ),
    );
  }

  Widget _buildSlmCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: _buildSlmCardBody(),
    );
  }

  Widget _buildSlmCardBody() {
    if (_slmState == 'downloading') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _slmRow(const Color(0xFF3B82F6), 'Downloading AI models', pulsing: true,
              trailing: Text('$_slmTotalProgress%',
                  style: const TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.bold))),
          const SizedBox(height: 6),
          Text(_slmCurrentFile,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _slmFileProgress / 100,
              minHeight: 6,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF329AD6)),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _slmTotalProgress / 100,
              minHeight: 3,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFBFDBFE)),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('File $_slmFileProgress%', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
              Text('Overall $_slmTotalProgress%', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
            ],
          ),
        ],
      );
    }
    if (_slmState == 'error') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _slmRow(const Color(0xFFDC2626), _slmErrorMsg.isNotEmpty ? _slmErrorMsg : 'Failed to load AI models'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _retrySlm,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    if (_slmState == 'initialising') {
      return _slmRow(const Color(0xFFF59E0B), 'Initialising AI engine…', pulsing: true);
    }
    return _slmRow(const Color(0xFF94A3B8), 'Checking AI models…', pulsing: true);
  }

  Widget _slmRow(Color dotColor, String label, {bool pulsing = false, Widget? trailing}) {
    return Row(children: [
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(label,
          style: TextStyle(color: dotColor, fontSize: 13, fontWeight: FontWeight.w600))),
      ?trailing,
      if (pulsing) const SizedBox(width: 8),
      if (pulsing)
        SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: dotColor.withValues(alpha: 0.5)),
        ),
    ]);
  }

  Widget _buildTypingIndicator() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Transform.flip(
          flipX: true,
          child: Image.asset('assets/images/user_icon.png', width: 32, height: 32, fit: BoxFit.cover),
        ),
        const SizedBox(width: 8),
        _BubbleSkeleton(surfaceColor: cs.surface),
      ]),
    );
  }

  void _sendMessage({String? prefill}) {
    final text = (prefill ?? _inputCtrl.text).trim();
    if (text.isEmpty) return;

    if (text == 'Login to Meta Room') {
      _inputCtrl.clear();
      _startMetaRoomLogin();
      return;
    }
    if (_metaRoomStep == 'ask_name') {
      _metaRoomPendingName = text;
      _metaRoomStep = 'ask_email';
      _pushUser(text);
      _inputCtrl.clear();
      _pushBot('Please enter your email address:');
      return;
    }
    if (_metaRoomStep == 'ask_email') {
      final name = _metaRoomPendingName;
      _metaRoom.saveUserInfo(name, text);
      _metaRoomStep = 'idle';
      _metaRoomPendingName = '';
      _pushUser(text);
      _inputCtrl.clear();
      _generateAndShowQR(name, text);
      return;
    }
    // ── 6-month statement intent ──────────────────────────────────────────
    if (RegExp(r'6[\s-]?month|six[\s-]?month|half[\s-]?year', caseSensitive: false).hasMatch(text) &&
        RegExp(r'statement|transaction|history|passbook', caseSensitive: false).hasMatch(text)) {
      _pushUser(text);
      _inputCtrl.clear();
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _pushBot('Please authenticate to view your statement.');
        Future.delayed(const Duration(milliseconds: 600), () async {
          if (!mounted) return;
          const channel = MethodChannel('com.kiya.bankinggenie/biometric');
          String result = 'cancelled';
          try {
            result = await channel.invokeMethod<String>('authenticate') ?? 'cancelled';
          } catch (_) {}
          if (!mounted) return;
          if (result != 'success') {
            _pushBot('Authentication was cancelled. Your statement could not be retrieved.');
            return;
          }
          setState(() => _djLoading = true);
          try {
            final data = await _db.loadStatementFromBlob();
            if (!mounted) return;
            setState(() => _djLoading = false);
            _pushBot(
              'Your last 6 months of transactions have been synced with your app.',
              csvData: data.csv,
            );
          } catch (e) {
            if (!mounted) return;
            setState(() => _djLoading = false);
            _pushBot('Unable to load your bank statement at this time. Please try again later.');
          }
        });
      });
      return;
    }

    // Push user message immediately — don't await anything first
    _pushUser(text);
    _inputCtrl.clear();
    if (_isListening) {
      _isListening = false;
      _gvListening = false;
      _stt.stop();
    }
    if (_isManualOffline || _isFlightMode) {
      if (_slmModelReady) { _callSlm(text); return; }
      if (_slmState == 'idle' || _slmState == 'error') { _pushBot('You are offline.'); _retrySlm(); return; }
      _pushBot('On-device AI is loading, please wait a moment...');
      return;
    }
    // Use cached _isOnline for instant routing, verify in background
    if (_isOnline) {
      _callRequestHandler(text);
      // Verify connectivity in background and update state
      _network.isOnline().then((online) {
        if (!mounted) return;
        setState(() => _isOnline = online);
      });
    } else if (_slmModelReady) {
      _callSlm(text);
    } else if (_slmState == 'idle' || _slmState == 'error') {
      _pushBot('You are offline.');
      _retrySlm();
    } else {
      _pushBot('On-device AI is loading, please wait a moment...');
    }
  }

  void _callRequestHandler(String userText) {
    if (!_rhConfigReady || _rhConfig.botname.isEmpty) {
      _rhPendingMessage = userText;
      _rhFirstUserMessage ??= userText;
      return;
    }
    setState(() => _djLoading = true);
    _rhFirstUserMessage ??= userText;
    final config = _rhConfig.copyWith(sessionId: _rhSessionId);
    _rh.call(userText, 'msg', _rhMsgid, _rhWelcomeqr, config).then((res) {
      if (!mounted) return;
      setState(() => _djLoading = false);
      if (res['success'] == 'true') {
        _parseRHContent(res);
      } else {
        _pushBot("I'm currently offline. Please try again when connected.");
      }
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _djLoading = false);
      _pushBot("I'm currently offline. Please try again when connected.");
    });
  }

  static bool _isGreeting(String text) {
    if (text.isEmpty) return false;
    final t = text.toLowerCase().trim();
    return RegExp(
      r'^(good\s+(morning|afternoon|evening|day|night)|hello|hi|hey|greetings|welcome)[^a-z]*'
      r'(how\s+(may|can)\s+i\s+(help|assist)|what\s+can\s+i\s+do)?',
      caseSensitive: false,
    ).hasMatch(t) && t.length < 120;
  }

  void _callSilent(String text, String msgid) {
    final config = _rhConfig.copyWith(sessionId: _rhSessionId);
    _rh.call(text, 'msg', msgid, _rhWelcomeqr, config).then((res) {
      if (!mounted) return;
      if (res['sessionId'] != null) {
        _rhSessionId = res['sessionId'];
        _rhConfig.sessionId = res['sessionId'];
      }
      final nextMsgid = (res['data']?['msgid'] ?? '') as String;
      if (nextMsgid.isNotEmpty) _rhMsgid = nextMsgid;
      if (nextMsgid == 'language') {
        _callSilent('English', nextMsgid);
      } else {
        // Greeting response after language handshake is silently dropped — flush real message
        _flushPending();
      }
    }).catchError((_) => _flushPending());
  }

  void _flushPending() {
    if (_rhPendingMessage != null) {
      final msg = _rhPendingMessage!;
      _rhPendingMessage = null;
      _callRequestHandler(msg);
    }
  }

  void _callSlm(String userText) async {
    if (!_slm.isReady) {
      _pushBot('On-device AI is not ready yet. Please wait or switch to API mode.');
      return;
    }
    setState(() => _djLoading = true);
    try {
      final result = await _slm.querySlm(userText);
      if (!mounted) return;
      setState(() => _djLoading = false);
      final summary    = (result['summary']    as String?) ?? '';
      final chartImage = result['chartImage']  as String?;
      final tableHtml  = result['tableHtml']   as String?;
      _pushBot(
        summary.isNotEmpty ? summary : 'Sorry, I could not understand that.',
        chartImage: chartImage,
        tableHtml: tableHtml,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _djLoading = false);
      _pushBot('On-device AI error. Please try again.');
    }
  }

  void _parseRHContent(Map<String, dynamic> res) {
    final data = res['data'];
    if (data == null) return;
    if (res['sessionId'] != null) {
      _rhSessionId = res['sessionId'] as String;
      _rhConfig.sessionId = res['sessionId'] as String;
    }

    final raw = data['content'] ?? '';
    List<dynamic> items = [];
    try {
      final decoded = jsonDecode(raw is String ? raw : jsonEncode(raw));
      items = decoded is List ? decoded : [decoded];
    } catch (_) {
      items = [{
        'content': raw,
        'msgType': data['msgType'],
        'msgid': data['msgid'],
        'options': data['options'],
      }];
    }

    for (final item in items) {
      final msgType = (item['msgType'] ?? data['msgType'] ?? 'text') as String;
      final msgid   = (item['msgid']   ?? data['msgid']   ?? '') as String;
      final content = (item['content'] ?? '') as String;
      final rawOpts = (item['options'] ?? data['options'] ?? []) as List;

      if (msgid.isNotEmpty) _rhMsgid = msgid;

      // ── Silent language handshake ──────────────────────────────────────
      if (msgid == 'language') {
        _rhPendingMessage ??= _rhFirstUserMessage;
        _callSilent('English', msgid);
        return;
      }

      // ── Form panel ────────────────────────────────────────────────────
      if (msgid == 'form') {
        List rawItems = [];
        try {
          final ri = data['items'];
          rawItems = ri is String ? jsonDecode(ri) : (ri as List? ?? []);
        } catch (_) {}
        if (content.isNotEmpty) _pushBot(content);
        if (rawItems.isNotEmpty) _buildDjForm(rawItems);
        continue;
      }

      // ── QuickReply choice panel ────────────────────────────────────────
      // Filter out blank titles and 'Restart' postbacks (mirrors Angular validOptions)
      final validOpts = rawOpts.where((o) {
        final title = (o['title'] as String? ?? '').trim();
        final postback = (o['postback'] as String? ?? '');
        return title.isNotEmpty && postback != 'Restart';
      }).toList();

      if (msgType == 'quickReply' && validOpts.isNotEmpty) {
        // mediablock: auto-skip back to first user message
        if (msgid == 'mediablock') {
          final msg = _rhFirstUserMessage;
          if (msg != null) {
            _rhFirstUserMessage = null;
            _callRequestHandler(msg);
          }
          return;
        }
        final seen = <String>{};
        final unique = validOpts
            .where((o) => seen.add(o['title'] as String))
            .toList();
        setState(() {
          _djChoices = unique.map<JourneyChoice>((o) => JourneyChoice(
            value: (o['postback'] ?? o['title']) as String,
            displayText: o['title'] as String,
          )).toList();
          _djChoiceType = 'radio';
          _djSelectedChoice = '';
          _djSelectedChoices = [];
          _djChoiceIsQuickReply = true;
          _panelQuestion = content;
          _panelType = 'choice';
        });
        continue;
      }

      // ── Workflow completed ─────────────────────────────────────────────
      if (content.isNotEmpty &&
          RegExp(r'workflow.{0,20}completed.{0,20}successfully', caseSensitive: false)
              .hasMatch(content)) {
        final isFundTransfer =
            RegExp(r'workflow[:\s]+fund\s+transfer', caseSensitive: false)
                .hasMatch(content);
        if (isFundTransfer) {
          _authenticateAndRecordTransfer(content);
        } else {
          _triggerDocFlow();
        }
        continue;
      }

      if (content.isNotEmpty) {
        if (_isGreeting(content)) {
          final msg = _rhFirstUserMessage;
          if (msg != null) _callRequestHandler(msg);
        } else {
          _pushBot(content);
        }
      }
    }
  }

  void _buildDjForm(List rawItems) {
    final groups = <JourneyFormGroup>[];
    for (final container in rawItems) {
      final subs = (container['sub'] ?? container['containerData'] ?? []) as List;
      final fields = <JourneyFormField>[];
      for (final f in subs) {
        final dt = (f['data_type'] ?? f['dataType'] ?? f['type'] ?? 'text').toString().toLowerCase().trim();
        // skip purely decorative elements
        if (['button', 'header', 'paragraph', 'label', 'divider'].contains(dt)) continue;
        // normalise aliases to canonical types
        final canonDt = const {
          'input': 'text', 'string': 'text', 'textbox': 'text',
          'dropdown': 'select', 'list': 'select',
          'multiline': 'textarea', 'multi_line': 'textarea',
          'integer': 'number', 'float': 'number', 'decimal': 'number',
        }[dt] ?? dt;
        // key: try every possible field name the server might use
        final key = [
          f['formName'], f['variableName'], f['variable_name'],
          f['parameter_name'], f['parameterName'], f['name'], f['key'],
        ].firstWhere((v) => v != null && v.toString().trim().isNotEmpty && v.toString() != '@@@@',
            orElse: () => null)?.toString().trim() ?? '';
        if (key.isEmpty) continue;
        final label = (f['parameter_name'] ?? f['parameterName'] ?? f['label'] ?? key).toString();
        fields.add(JourneyFormField(
          variableName: key,
          label: label,
          dataType: canonDt,
          isOptional: (f['optional'] ?? f['isOptional'] ?? 'Y').toString(),
          options: ((f['list_of_values'] ?? f['listOfValues'] ?? f['options'] ?? []) as List)
              .map<Map<String, String>>((v) => {
                    'value': (v['value'] ?? v['id'] ?? '').toString(),
                    'name': (v['name'] ?? v['label'] ?? v['value'] ?? '').toString(),
                  })
              .toList(),
        ));
      }
      if (fields.isEmpty) continue;
      groups.add(JourneyFormGroup(
        name: (container['contName'] ?? container['name'] ?? 'Details').toString(),
        fields: fields,
        values: Map.fromEntries(fields.map((f) =>
            MapEntry(f.variableName, f.dataType == 'checkbox' ? <String>[] : ''))),
        errors: Map.fromEntries(fields.map((f) => MapEntry(f.variableName, ''))),
      ));
    }
    if (groups.isEmpty) return;
    setState(() {
      _djFormGroups = groups;
      _djFormGroupIndex = 0;
      _djFormHasErrors = false;
      _panelType = 'form';
    });
  }

  void _djSelectChoice(JourneyChoice choice) {
    setState(() {
      if (_djChoiceType == 'radio') {
        _djSelectedChoice = choice.value;
      } else {
        if (_djSelectedChoices.contains(choice.value)) {
          _djSelectedChoices.remove(choice.value);
        } else {
          _djSelectedChoices.add(choice.value);
        }
      }
    });
  }

  void _djConfirmChoice() {
    final selected = _djChoiceType == 'radio' ? _djSelectedChoice : _djSelectedChoices.join(',');
    if (selected.isEmpty) return;
    final displayText = _djChoices
        .firstWhere((c) => c.value == selected,
            orElse: () => JourneyChoice(value: selected, displayText: selected))
        .displayText;
    setState(() => _panelType = 'none');
    _pushUser(displayText);
    if (_djChoiceIsQuickReply) _callRequestHandler(selected);
  }

  void _djOnFieldChange(int gi, String varName, dynamic value) async {
    if (value == '__pick_date__') {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        final dateStr = picked.toIso8601String().split('T')[0];
        setState(() {
          final grp = _djFormGroups[gi];
          grp.values = Map<String, dynamic>.from(grp.values)..[varName] = dateStr;
          grp.errors = Map<String, String>.from(grp.errors)..[varName] = '';
          _djFormGroups = List<JourneyFormGroup>.from(_djFormGroups);
        });
      }
      return;
    }
    setState(() {
      final grp = _djFormGroups[gi];
      grp.values = Map<String, dynamic>.from(grp.values)..[varName] = value;
      grp.errors = Map<String, String>.from(grp.errors)..[varName] = '';
      _djFormGroups = List<JourneyFormGroup>.from(_djFormGroups);
    });
  }

  void _djOnCheckboxToggle(int gi, String varName, String value) {
    setState(() {
      final grp = _djFormGroups[gi];
      final arr = List<String>.from(grp.values[varName] ?? []);
      if (arr.contains(value)) arr.remove(value); else arr.add(value);
      grp.values = Map<String, dynamic>.from(grp.values)..[varName] = arr;
      grp.errors = Map<String, String>.from(grp.errors)..[varName] = '';
      _djFormGroups = List<JourneyFormGroup>.from(_djFormGroups);
    });
  }

  bool _djValidateGroup(JourneyFormGroup grp) {
    bool valid = true;
    final newErrors = Map<String, String>.from(grp.errors);
    for (final f in grp.fields) {
      newErrors[f.variableName] = '';
      if (f.isOptional != 'N') continue;
      final v = grp.values[f.variableName];
      final empty = v is List ? v.isEmpty : (v == false || v?.toString().trim().isEmpty == true);
      if (empty) {
        newErrors[f.variableName] = '${f.label} is required.';
        valid = false;
      }
    }
    setState(() {
      grp.errors = newErrors;
      _djFormGroups = List<JourneyFormGroup>.from(_djFormGroups);
      _djFormHasErrors = !valid;
    });
    return valid;
  }

  void _djConfirmForm() {
    final grp = _djFormGroups[_djFormGroupIndex];
    if (!_djValidateGroup(grp)) return;
    final card = grp.fields
        .where((f) => grp.values[f.variableName]?.toString().trim().isNotEmpty == true)
        .map((f) => {'label': f.label, 'value': grp.values[f.variableName].toString()})
        .toList();
    _pushUserCard(grp.name, card.isNotEmpty ? card : [{'label': grp.name, 'value': 'Submitted'}]);
    // Record this form group as a node step
    final formValues = <String, String>{};
    for (final f in grp.fields) {
      final v = grp.values[f.variableName];
      formValues[f.variableName] = v is List ? v.join(',') : v?.toString() ?? '';
    }
    // For agent forms, build the renderer URL from the original form URL + submitted data
    String? nodeRendererUrl;
    if (_isAgentForm && _agentFormUrl != null) {
      final decoded = Uri.decodeFull(_agentFormUrl!);
      final formIdMatch = RegExp(r'formId.{0,3}:\s*[^\d]*(\d+)').firstMatch(decoded);
      final formId = formIdMatch?.group(1) ?? '';
      if (formId.isNotEmpty) {
        final typedValues = formValues.map((k, v) {
          if (v == 'true') return MapEntry(k, true);
          if (v == 'false') return MapEntry(k, false);
          return MapEntry(k, v);
        });
        final params = <String, dynamic>{
          'formId': formId,
          'status': 'submitted',
          'action': 'submit',
          ...typedValues,
        };
        nodeRendererUrl = 'https://www.bharatmeta.in/bm/DYNAMICUI/#/renderForm?${Uri.encodeComponent(jsonEncode(params))}=';
      } else {
        nodeRendererUrl = '';
      }
    }
    _session.recordFormNode(grp.name, formValues, rendererUrl: nodeRendererUrl);
    if (_djFormGroupIndex < _djFormGroups.length - 1) {
      setState(() { _djFormGroupIndex++; _djFormHasErrors = false; });
    } else {
      final allValues = <String, String>{};
      for (final g in _djFormGroups) {
        for (final e in g.values.entries) {
          allValues[e.key] = e.value is List ? (e.value as List).join(',') : e.value.toString();
        }
      }
      final isAgent = _isAgentForm;
      final agentUrl = _agentFormUrl;
      setState(() { _panelType = 'none'; _isAgentForm = false; _agentFormUrl = null; });
      if (isAgent) {
        _session.sendStateUpdate(allValues, formUrl: agentUrl);
      } else {
        _callRequestHandler(jsonEncode(allValues));
      }
    }
  }

  void _startMetaRoomLogin() {
    _pushUser('Login to Meta Room');
    _metaRoom.stopPolling();
    setState(() => _metaRoomStep = 'ask_name');
    _pushBot('Please enter your name to continue:');
  }

  void _generateAndShowQR(String name, String email) async {
    final sessionId = _metaRoom.generateSessionId();
    final session = MetaRoomSession(name: name, email: email, sessionId: sessionId);
    final idx = _messages.length;
    setState(() => _messages.add(ChatMessage(
        from: 'bot', text: '', time: _now(), metaRoom: 'qr', metaRoomPhase: 'skeleton')));

    final sessions = await _db.getAllSessions().catchError((_) => <Map<String, dynamic>>[]);
    final userData = <String, dynamic>{};
    for (final s in sessions) {
      final records = await _db.getSession(s['session_id']).catchError((_) => <Map<String, dynamic>>[]);
      if (records.isNotEmpty) {
        userData[s['session_id']] =
            records.map((r) => {'from_role': r['from_role'], 'message': r['message']}).toList();
      }
    }

    final start = DateTime.now().millisecondsSinceEpoch;
    _metaRoom.generateQR(session, userData).then((data) {
      final delay = (2500 - (DateTime.now().millisecondsSinceEpoch - start)).clamp(0, 2500);
      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted) return;
        setState(() => _messages[idx] =
            _messages[idx].copyWith(metaRoomPhase: 'ready', metaRoomQrUrl: data['qrString']));
      });
      _metaRoom.startPolling(sessionId);
    }).catchError((_) {
      final delay = (2500 - (DateTime.now().millisecondsSinceEpoch - start)).clamp(0, 2500);
      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted) return;
        setState(() => _messages[idx] = _messages[idx].copyWith(
            metaRoom: 'error', metaRoomError: 'Failed to generate QR. Please try again.'));
      });
    });
  }

  void _retryMetaRoomLogin(int msgIdx) {
    _metaRoom.stopPolling();
    setState(() => _messages[msgIdx] = _messages[msgIdx].copyWith(
        metaRoom: 'qr', metaRoomPhase: 'skeleton', metaRoomError: null, metaRoomQrUrl: null));
    _metaRoom.getSavedUserInfo().then((saved) {
      if (saved == null) {
        setState(() => _messages[msgIdx] = _messages[msgIdx].copyWith(
            metaRoom: 'error', metaRoomError: 'No user info found. Please start a new login.'));
        return;
      }
      _generateAndShowQR(saved['name'], saved['email']);
    });
  }

  void _authenticateAndRecordTransfer(String content) async {
    const channel = MethodChannel('com.kiya.bankinggenie/biometric');
    String result = 'cancelled';
    try {
      result = await channel.invokeMethod<String>('authenticate') ?? 'cancelled';
    } catch (e) {
      debugPrint('[Biometric] channel error: $e');
      result = 'cancelled';
    }
    if (!mounted) return;
    if (result != 'success') {
      _pushBot('Authentication was cancelled. The transfer has not been processed.');
      return;
    }
    final amountMatch = RegExp(r'amount[:\s]+(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(content);
    final amount = amountMatch != null ? double.tryParse(amountMatch.group(1) ?? '') ?? 0.0 : 0.0;
    final recipientMatch = RegExp(r'beneficiary\s+name[:\s]+([^\n•]+)', caseSensitive: false).firstMatch(content);
    final recipient = recipientMatch?.group(1)?.trim() ?? 'Unknown';
    final typeMatch = RegExp(r'\b(IMPS|UPI|NEFT|RTGS)\b', caseSensitive: false).firstMatch(content);
    final transferType = typeMatch?.group(1)?.toUpperCase() ?? 'Transfer';
    await _db.insertTransfer(recipient, amount, transferType: transferType);
    _pushBot('Transfer authenticated and recorded successfully.');
  }

  void _triggerDocFlow() {
    _pushBot('Please upload a valid identity document — Aadhaar Card, PAN Card, or Driving Licence.');
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      _runLyrics(['Almost there.', 'We need to verify your identity.', 'Please have your document ready.'], () {
        // Go straight to native file picker — no custom UI
        setState(() { _tapPromptAction = 'doc'; _tapPromptLabel = 'Tap to Scan Document'; _showTapPrompt = true; });
      });
    });
  }

  int _lyricRunId = 0; // incremented on each new lyric run to cancel stale sequences

  void _runLyrics(List<String> lines, VoidCallback onDone) {
    _lyricRunId++;
    final runId = _lyricRunId;
    // Stop global voice when lyric screen appears
    if (_globalVoiceActive) _stopGlobalVoice();
    setState(() { _showLyricStage = true; _lyricVisible = false; _showTapPrompt = false; });
    int i = 0;
    void next() {
      if (!mounted || runId != _lyricRunId) return;
      if (i >= lines.length) {
        setState(() => _lyricVisible = false);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted || runId != _lyricRunId) return;
          // Keep _showLyricStage = true so tap prompt shows inside overlay
          onDone();
        });
        return;
      }
      setState(() => _lyricVisible = false);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || runId != _lyricRunId) return;
        setState(() { _lyricText = lines[i++]; _lyricVisible = true; });
        Future.delayed(const Duration(milliseconds: 2400), next);
      });
    }
    next();
  }

  void _onTapPrompt() {
    final action = _tapPromptAction;
    setState(() {
      _showTapPrompt = false;
      _tapPromptAction = null;
      _showLyricStage = false;
      _lyricVisible = false;
    });
    if (action == 'doc') _pickDoc();
    if (action == 'camera') _pickSelfie();
  }

  // Show native bottom sheet chooser — mirrors Angular pickSource()
  void _pickDoc() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('Upload Document',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A))),
              const SizedBox(height: 4),
              const Text('Choose how to provide your identity document.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              const SizedBox(height: 16),
              _sourceOption(
                icon: Icons.camera_alt_rounded,
                title: 'Open Camera',
                subtitle: 'Capture document with camera',
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 10),
              _sourceOption(
                icon: Icons.photo_library_rounded,
                title: 'Choose from Gallery',
                subtitle: 'Pick an existing image from your device',
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final file = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 60,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _onDocSelected(file.name, b64);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open picker: $e')));
    }
  }

  Widget _sourceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F0FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF329AD6), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A))),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 18),
        ]),
      ),
    );
  }

  // Front camera directly for selfie — on web opens camera input
  void _pickSelfie() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 60,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _onPhotoCapture(file.name, b64);
    } catch (e) {
      // Camera not available (e.g. desktop web) — fall back to gallery
      if (!mounted) return;
      try {
        final file = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 60,
          maxWidth: 800,
          maxHeight: 800,
        );
        if (file == null) return;
        final bytes = await file.readAsBytes();
        final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        _onPhotoCapture(file.name, b64);
      } catch (_) {}
    }
  }

  void _onDocSelected(String fileName, String b64) {
    _docImageBase64 = b64;
    setState(() => _messages.add(ChatMessage(from: 'user', text: '', time: _now(), fileName: fileName, imageUrl: b64, scanned: true)));
    // Record document node step-by-step
    _session.recordDocumentNode('Identity Document', b64);
    setState(() => _djLoading = true);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _djLoading = false);
      _pushBot('Document received. Now I need to verify your identity — please take a live selfie.');
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _runLyrics(
          ['Document verified.', 'One last step — a live photo.', 'Please look at the camera.'],
          () {
            setState(() {
              _tapPromptAction = 'camera';
              _tapPromptLabel = 'Tap to Open Camera';
              _showTapPrompt = true;
            });
          },
        );
      });
    });
  }

  void _onPhotoCapture(String fileName, String b64) {
    setState(() => _messages.add(ChatMessage(from: 'user', text: '', time: _now(), fileName: fileName, imageUrl: b64, scanned: true)));
    // Record selfie as a step
    _session.recordDocumentNode('Live Selfie', b64);
    setState(() => _djLoading = true);
    _faceCompareService.compare(b64, _docImageBase64 ?? '').then((result) {
      if (!mounted) return;
      setState(() => _djLoading = false);
      if (result.matched) {
        _pushBot('Identity verified successfully.');
        Future.delayed(const Duration(milliseconds: 1200), () {
          _pushBot('Your application has been submitted successfully.');
          Future.delayed(const Duration(milliseconds: 1400), () {
            setState(() => _messages.add(ChatMessage(from: 'bot', text: '__session_end__', time: _now())));
          });
        });
      } else {
        final reason = result.error ?? 'Face did not match the document photo.';
        _pushBot('Verification failed: $reason');
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          _runLyrics(
            ['Connecting you to an agent.', 'Please hold on.', 'An agent will assist you shortly.'],
            () {
              if (!mounted) return;
              setState(() => _showLyricStage = false);
              _session.startHitlSession(
                journeyName: 'New Account Opening',
                agentTimeoutSeconds: 60,
              );
            },
          );
        });
      }
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _djLoading = false);
      _pushBot('Face verification service is unavailable. Connecting you to an agent…');
      _runLyrics(
        ['Connecting you to an agent.', 'Please hold on.', 'An agent will assist you shortly.'],
        () {
          if (!mounted) return;
          setState(() => _showLyricStage = false);
          _session.startHitlSession(
            journeyName: 'New Account Opening',
            agentTimeoutSeconds: 60,
          );
        },
      );
    });
  }

  void _onHitlResult(String result) {
    _liveKit.disconnect();
    setState(() { _remoteParticipants = []; _callMicOn = true; _callCamOn = true; _hitlCallMinimized = false; });
    if (result == 'APPROVED') {
      _pushBot('Your identity has been verified by the agent.');
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        _pushBot('Your application has been submitted successfully.');
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (!mounted) return;
          setState(() => _messages.add(ChatMessage(from: 'bot', text: '__session_end__', time: _now())));
        });
      });
    } else if (result == 'REJECTED') {
      _pushBot('The agent was unable to verify your identity. Please visit your nearest branch.');
    } else if (result == 'TIMEOUT') {
      _pushBot('No agent was available. Please try again later or visit your nearest branch.');
    }
  }

  // ── Global voice (mirrors Angular globalVoiceActive / _gvHandleFinal) ──
  bool _globalVoiceActive = false;
  String _globalVoiceTranscript = '';
  String _gvFieldTarget = '';
  String _gvVoiceMatchValue = '';
  bool _sttReady = false;
  bool _gvListening = false;
  bool _gvProcessed = false;
  bool _gvFinalHandled = false;
  String _gvLastPartial = '';
  int _gvSessionId = 0;
  int _gvBusyRetries = 0;
  final _transcriptNotifier = ValueNotifier<String>('');
  final _voiceActiveNotifier = ValueNotifier<bool>(false);

  void _toggleGlobalVoice() {
    debugPrint('[GV] FAB tapped — active=$_globalVoiceActive panelType=$_panelType');
    _globalVoiceActive ? _stopGlobalVoice() : _startGlobalVoice();
  }

  Future<bool> _ensureStt() async {
    if (_sttReady) return true;
    _sttReady = await _stt.initialize(
      onError: (e) => debugPrint('[STT] error: ${e.errorMsg}'),
    );
    return _sttReady;
  }

  void _startGlobalVoice() async {
    debugPrint('[GV] _startGlobalVoice — panelType=$_panelType');
    if (_isListening) {
      _gvListening = false;
      await _stt.stop();
      if (mounted) setState(() => _isListening = false);
    }
    final ok = await _ensureStt();
    debugPrint('[GV] ensureStt=$ok mounted=$mounted');
    if (!ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available.')));
      return;
    }
    if (!mounted) return;
    _gvSessionId++;
    _gvBusyRetries = 0;
    _globalVoiceActive = true;
    _voiceActiveNotifier.value = true;
    _globalVoiceTranscript = '';
    _gvFieldTarget = _panelType == 'form' ? _gvFirstUnfilledField() : '';
    setState(() {});
    debugPrint('[GV] voice active, sessionId=$_gvSessionId, fieldTarget=$_gvFieldTarget');
    if (_panelType == 'form' && _gvFieldTarget.isNotEmpty) {
      for (int gi = 0; gi < _djFormGroups.length; gi++) {
        if (_djFormGroups[gi].fields.any((f) => f.variableName == _gvFieldTarget)) {
          if (gi != _djFormGroupIndex) setState(() => _djFormGroupIndex = gi);
          break;
        }
      }
    }
    _gvListen();
  }

  void _gvListen() {
    if (!_globalVoiceActive || !mounted || _gvListening) return;
    _gvListening = true;
    _gvProcessed = false;
    _gvFinalHandled = false;
    _gvLastPartial = '';
    final sessionId = _gvSessionId;
    _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        if (!mounted || !_globalVoiceActive || sessionId != _gvSessionId || _gvProcessed) return;
        final text = r.recognizedWords.trim();
        if (text.isNotEmpty) _gvLastPartial = text;
        if (!r.finalResult) {
          _transcriptNotifier.value = text;
          return;
        }
        final toProcess = text.isNotEmpty ? text : _gvLastPartial;
        final wordCount = toProcess.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        if (toProcess.isNotEmpty && wordCount >= 3) {
          _gvProcessed = true;
          _gvListening = false;
          _gvLastPartial = '';
          _transcriptNotifier.value = '';
          _gvHandleFinal(toProcess);
        } else {
          _gvListening = false;
          Future.delayed(const Duration(milliseconds: 600), () {
            if (!mounted || !_globalVoiceActive || sessionId != _gvSessionId) return;
            _gvListen();
          });
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      listenOptions: SpeechListenOptions(onDevice: true, cancelOnError: false),
    );
  }

  void _stopGlobalVoice() {
    _gvSessionId++;
    _gvListening = false;
    _gvProcessed = false;
    _gvFinalHandled = false;
    _gvLastPartial = '';
    _gvBusyRetries = 0;
    _stt.stop();
    _transcriptNotifier.value = '';
    _voiceActiveNotifier.value = false;
    if (mounted) setState(() {
      _globalVoiceActive = false;
      _globalVoiceTranscript = '';
      _gvFieldTarget = '';
      _gvVoiceMatchValue = '';
    });
  }

  void _gvHandleFinal(String spoken) {
    // Stop listening immediately when we have a result — prevents double-firing
    _stopGlobalVoice();
    if (_panelType == 'choice') {
      final stripped = spoken
          .replaceAll(RegExp(r'^(select|choose|pick|go with|i want|i choose)\s+', caseSensitive: false), '')
          .toLowerCase()
          .trim();
      JourneyChoice? match;
      // exact match first
      for (final c in _djChoices) {
        if (c.displayText.toLowerCase() == stripped) { match = c; break; }
      }
      // contains match
      if (match == null) {
        for (final c in _djChoices) {
          final d = c.displayText.toLowerCase();
          if (d.contains(stripped) || stripped.contains(d)) { match = c; break; }
        }
      }
      // word overlap match
      if (match == null) {
        final spokenWords = stripped.split(RegExp(r'\s+'));
        for (final c in _djChoices) {
          final words = c.displayText.toLowerCase().split(RegExp(r'\s+'));
          if (words.any((w) => spokenWords.contains(w))) { match = c; break; }
        }
      }
      if (match != null) {
        final matchVal = match.value;
        setState(() {
          _djSelectedChoice = matchVal;
          _gvVoiceMatchValue = matchVal;
        });
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted && _djSelectedChoice == matchVal) {
            setState(() => _gvVoiceMatchValue = '');
            _djConfirmChoice();
          }
        });
      }
    } else if (_panelType == 'form') {
      final cmd = spoken.toLowerCase().trim();
      if (RegExp(r'^(submit|done|finish|complete|next|continue|proceed)$').hasMatch(cmd)) {
        _djConfirmForm(); return;
      }
      if (RegExp(r'^(back|previous|go back)$').hasMatch(cmd)) {
        if (_djFormGroupIndex > 0) setState(() => _djFormGroupIndex--);
        return;
      }
      debugPrint('[GV] form panel — calling _gvFillField');
      _gvFillField(spoken);
    } else {
      _sendMessage(prefill: spoken);
    }
  }

  void _gvFillField(String spoken) {
    debugPrint('[GV] _gvFillField: "$spoken" groups=${_djFormGroups.length}');
    final allFields = <({JourneyFormField field, int gi})>[];
    for (int gi = 0; gi < _djFormGroups.length; gi++) {
      for (final f in _djFormGroups[gi].fields) {
        allFields.add((field: f, gi: gi));
      }
    }

    final s = spoken.toLowerCase().trim();

    // ── Multi-field pass: find ALL label→value pairs in one utterance ──
    // Sort labels longest-first so "account number" matches before "number"
    final sorted = [...allFields]
      ..sort((a, b) => b.field.label.length - a.field.label.length);

    // Build a list of (startIndex, endIndex, field, value) matches in the spoken string
    final hits = <({int start, int end, ({JourneyFormField field, int gi}) entry, String value})>[];
    for (final e in sorted) {
      final lc = e.field.label.toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
      if (lc.isEmpty) continue;
      final labelPattern = lc.split(RegExp(r'\s+')).join(r'\s+');
      final rx = RegExp(
        '$labelPattern\\s*(?:is|are|to|as|:|=|-)?\\s*([\\w\\s.,@-]+?)(?=\\s+(?:${sorted.map((e2) => e2.field.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim().split(RegExp(r'\s+')).join(r'\s+')).where((p) => p.isNotEmpty).join('|')})|\$)',
        caseSensitive: false,
      );
      final m = rx.firstMatch(s);
      if (m != null) {
        final val = m.group(1)?.trim() ?? '';
        if (val.isNotEmpty) {
          // Avoid overlapping matches — skip if this range already covered
          final overlaps = hits.any((h) => h.start < m.end && m.start < h.end);
          if (!overlaps) hits.add((start: m.start, end: m.end, entry: e, value: val));
        }
      }
    }

    if (hits.isNotEmpty) {
      // Sort hits by position in the utterance
      hits.sort((a, b) => a.start.compareTo(b.start));
      debugPrint('[GV] multi-field hits: ${hits.map((h) => "${h.entry.field.label}=${h.value}").join(", ")}');
      // Apply each with 1s gap between them
      for (int i = 0; i < hits.length; i++) {
        final h = hits[i];
        Future.delayed(Duration(milliseconds: i * 1000), () {
          if (!mounted) return;
          _gvApplyField(h.entry.gi, h.entry.field, h.value);
          final next = _gvNextUnfilledAfter(h.entry.field.variableName, allFields);
          setState(() {
            _gvFieldTarget = next;
            if (next.isNotEmpty) {
              final ne = allFields.firstWhere((x) => x.field.variableName == next,
                  orElse: () => allFields.first);
              if (ne.gi != _djFormGroupIndex) _djFormGroupIndex = ne.gi;
            }
          });
        });
      }
      return;
    }

    // ── Single-field fallback: strip filler and fill next unfilled ──
    final cleaned = spoken
        .replaceAll(RegExp(
            r'^(please\s+)?(set|fill|update|enter|change|put|type|write|is|my|the|a|an)\s+',
            caseSensitive: false), '')
        .trim();
    ({JourneyFormField field, int gi})? target;
    if (_gvFieldTarget.isNotEmpty) {
      for (final e in allFields) {
        if (e.field.variableName == _gvFieldTarget) { target = e; break; }
      }
    }
    if (target != null) {
      final v = _djFormGroups[target.gi].values[target.field.variableName];
      final filled = v is List ? v.isNotEmpty : (v?.toString().trim().isNotEmpty ?? false);
      if (filled) target = null;
    }
    if (target == null) {
      for (final e in allFields) {
        final v = _djFormGroups[e.gi].values[e.field.variableName];
        final empty = v is List ? v.isEmpty : (v?.toString().trim().isEmpty ?? true);
        if (empty) { target = e; break; }
      }
    }
    debugPrint('[GV] single-field fill → target=${target?.field.variableName} cleaned="$cleaned"');
    if (target == null) return;
    _gvApplyField(target.gi, target.field, cleaned);
    final next = _gvNextUnfilledAfter(target.field.variableName, allFields);
    setState(() {
      _gvFieldTarget = next;
      if (next.isNotEmpty) {
        final ne = allFields.firstWhere((x) => x.field.variableName == next,
            orElse: () => allFields.first);
        if (ne.gi != _djFormGroupIndex) _djFormGroupIndex = ne.gi;
      }
    });
  }

  // Port of Angular djResolveOption + djApplyFieldValue
  void _gvApplyField(int gi, JourneyFormField field, String raw) {
    debugPrint('[GV] _gvApplyField: field=${field.variableName} dt=${field.dataType} raw="$raw"');
    final dt = field.dataType;
    final v = raw.toLowerCase().trim();
    if (v.isEmpty) return;
    String resolved = raw.trim();

    if ((dt == 'select' || dt == 'radio' || dt == 'checkbox') && field.options.isNotEmpty) {
      // 1. Exact match on name or value
      Map<String, String>? opt;
      for (final o in field.options) {
        if (o['name']!.toLowerCase() == v || o['value']!.toLowerCase() == v) { opt = o; break; }
      }
      // 2. Starts-with match
      if (opt == null) {
        for (final o in field.options) {
          if (o['name']!.toLowerCase().startsWith(v) || v.startsWith(o['name']!.toLowerCase())) { opt = o; break; }
        }
      }
      // 3. Word overlap — score by number of matching words
      if (opt == null) {
        final spokenWords = v.split(RegExp(r'\s+'));
        int bestScore = 0;
        for (final o in field.options) {
          final words = o['name']!.toLowerCase().split(RegExp(r'\s+'));
          final score = words.where((w) => spokenWords.contains(w)).length;
          if (score > bestScore) { bestScore = score; opt = o; }
        }
      }
      if (opt != null) resolved = opt['value']!;
    } else if (dt == 'number') {
      // Convert spoken number words to digits
      resolved = _wordsToDigits(raw);
    } else if (dt == 'date') {
      try {
        final d = DateTime.parse(raw);
        resolved = d.toIso8601String().split('T')[0];
      } catch (_) {
        // Keep raw — user may have said "15th March" etc.
        resolved = raw.trim();
      }
    }

    debugPrint('[GV] _gvApplyField: resolved="$resolved"');
    setState(() {
      final grp = _djFormGroups[gi];
      grp.values = Map<String, dynamic>.from(grp.values)..[field.variableName] = resolved;
      grp.errors = Map<String, String>.from(grp.errors)..[field.variableName] = '';
      _djFormGroups = List<JourneyFormGroup>.from(_djFormGroups);
    });
  }

  /// Convert spoken number words to digit string, fall back to stripping non-digits.
  static String _wordsToDigits(String raw) {
    const words = {
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
      'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      'ten': '10', 'eleven': '11', 'twelve': '12', 'thirteen': '13',
      'fourteen': '14', 'fifteen': '15', 'sixteen': '16', 'seventeen': '17',
      'eighteen': '18', 'nineteen': '19', 'twenty': '20', 'thirty': '30',
      'forty': '40', 'fifty': '50', 'sixty': '60', 'seventy': '70',
      'eighty': '80', 'ninety': '90', 'hundred': '100', 'thousand': '1000',
    };
    var s = raw.toLowerCase().trim();
    // Replace word numbers
    words.forEach((word, digit) {
      s = s.replaceAll(RegExp('\\b$word\\b'), digit);
    });
    // Extract digits and dots only
    final digits = s.replaceAll(RegExp(r'[^0-9.]'), '');
    return digits.isNotEmpty ? digits : raw.trim();
  }

  String _gvFirstUnfilledField() {
    for (final grp in _djFormGroups) {
      for (final f in grp.fields) {
        final v = grp.values[f.variableName];
        if (v is List ? v.isEmpty : (v?.toString().trim().isEmpty ?? true)) return f.variableName;
      }
    }
    return '';
  }

  String _gvNextUnfilledAfter(String varName, List<({JourneyFormField field, int gi})> all) {
    final idx = all.indexWhere((e) => e.field.variableName == varName);
    for (int i = idx + 1; i < all.length; i++) {
      final v = _djFormGroups[all[i].gi].values[all[i].field.variableName];
      if (v is List ? v.isEmpty : (v?.toString().trim().isEmpty ?? true)) return all[i].field.variableName;
    }
    return '';
  }

  void _startNewSession() {
    setState(() => _showEndSessionModal = false);
    // End any active calls before resetting
    if (_hitlState != HitlState.idle) {
      _liveKit.disconnect();
      _session.endHitlCall();
    } else if (_callState != CallState.idle) {
      _liveKit.disconnect();
      _session.endCall();
    }
    if (_liveCallState != LiveCallState.idle) {
      _liveCall.endCall();
    }
    setState(() {
      _remoteParticipants = [];
      _callMicOn = true;
      _callCamOn = true;
      _hitlCallMinimized = false;
      _agentFormUrl = null;
      _isAgentForm = false;
      _hitlScanType = null;
    });
    _resetChatState();
    _sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    _rhSessionId = '';
    _rhFirstUserMessage = null;
    _rhPendingMessage = null;
    _rhConfig.channelid = RequestHandlerService.genChannelId();
    _rhMsgid = 'startchattingevent';
    _rhWelcomeqr = null;
    _rhConfigReady = false;
    _slm.reset();
    if (_isManualOffline) {
      if (_slmModelReady) {
        _pushBot("You're using On-Device AI. Your data stays private on your device. How can I help you?");
      } else {
        _pushBot("You're in offline mode. On-device AI is not ready yet — please wait or check settings.");
      }
    } else {
      _fetchBotConfig();
    }
  }

  Widget _buildInputBar() {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final secondary = cs.secondary;
    final surfaceColor = Theme.of(context).appBarTheme.backgroundColor ?? cs.surface;
    final onSurface = cs.onSurface;
    final keyboardPadding = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 8, 12, keyboardPadding > 0 ? keyboardPadding + 8 : 10),
        decoration: BoxDecoration(
          color: surfaceColor,
          border: Border(top: BorderSide(color: onSurface.withValues(alpha: 0.08))),
          boxShadow: [
            BoxShadow(color: onSurface.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, -2)),
          ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, maxHeight: 120),
              child: Container(
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: _isListening ? const Color(0xFFEF4444) : onSurface.withValues(alpha: 0.12),
                    width: _isListening ? 1.5 : 1,
                  ),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: TextStyle(color: onSurface, fontSize: 14, height: 1.4),
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _isListening ? 'Listening…' : 'Message BankingGenie…',
                        hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.35), fontSize: 14),
                        contentPadding: const EdgeInsets.only(left: 16, right: 4, top: 12, bottom: 12),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      if (_globalVoiceActive) { _stopGlobalVoice(); return; }
                      if (_isListening) {
                        _gvListening = false;
                        await _stt.stop();
                        if (mounted) setState(() => _isListening = false);
                        return;
                      }
                      if (_gvListening) return;
                      final ok = await _ensureStt();
                      if (!ok || !mounted) return;
                      setState(() => _isListening = true);
                      _gvListening = true;
                      _stt.listen(
                        onResult: (SpeechRecognitionResult r) {
                          if (!mounted || !_isListening) return;
                          final text = r.recognizedWords.trim();
                          if (text.isNotEmpty) _inputCtrl.text = text;
                          if (r.finalResult) {
                            _gvListening = false;
                            _stt.stop();
                            if (mounted) setState(() => _isListening = false);
                          }
                        },
                        listenFor: const Duration(seconds: 30),
                        pauseFor: const Duration(seconds: 3),
                        partialResults: true,
                        listenOptions: SpeechListenOptions(onDevice: true, cancelOnError: false),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening ? const Color(0xFFEF4444) : onSurface.withValues(alpha: 0.1),
                        ),
                        child: Icon(
                          _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: _isListening ? Colors.white : onSurface.withValues(alpha: 0.5),
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [primary, secondary],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildChoicePanel() => ChoicePanel(
    question: _panelQuestion,
    choices: _djChoices,
    choiceType: _djChoiceType,
    selectedChoice: _djSelectedChoice,
    selectedChoices: _djSelectedChoices,
    voiceTranscript: _globalVoiceActive ? _globalVoiceTranscript : '',
    voiceMatchValue: _gvVoiceMatchValue,
    onSelect: _djSelectChoice,
    onConfirm: _djConfirmChoice,
  );

  Widget _buildFormPanel() => FormPanel(
    groups: _djFormGroups,
    groupIndex: _djFormGroupIndex,
    hasErrors: _djFormHasErrors,
    voiceTranscript: _globalVoiceActive ? _globalVoiceTranscript : '',
    voiceFieldTarget: _gvFieldTarget,
    onFieldChange: _djOnFieldChange,
    onCheckboxToggle: _djOnCheckboxToggle,
    onConfirm: _djConfirmForm,
    onPrev: () => setState(() { if (_djFormGroupIndex > 0) _djFormGroupIndex--; }),
  );

  // Full-screen lyric overlay — matches Angular .lyric-overlay (position:fixed inset:0)
  Widget _buildLyricOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        child: Stack(
          children: [
            Center(
              child: AnimatedOpacity(
                opacity: _lyricVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 350),
                child: AnimatedSlide(
                  offset: _lyricVisible ? Offset.zero : const Offset(0, 0.15),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_lyricText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                            letterSpacing: 0.01)),
                  ),
                ),
              ),
            ),
            if (_showTapPrompt)
              Positioned(
                bottom: 60,
                left: 0, right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _onTapPrompt,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_tapPromptLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.02)),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── HITL: incoming call request overlay ────────────────────────────────
  Widget _buildHitlCallRequestOverlay() {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.80),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF329AD6).withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.video_call_rounded, color: Color(0xFF329AD6), size: 38),
              ),
              const SizedBox(height: 16),
              Text('Incoming Call',
                  style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
              if (_hitlAgentName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_hitlAgentName,
                    style: const TextStyle(color: Color(0xFF329AD6), fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 6),
              Text('An agent wants to video call you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _session.cancelHitl();
                      _pushBot('Call declined.');
                    },
                    icon: const Icon(Icons.call_end_rounded),
                    label: const Text('Decline'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    // Accept: server will send CALL_JOIN on next heartbeat tick
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Accept'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ── HITL: fetch agent form JSON and render natively ──────────────────────
  void _loadAgentForm(String url) async {
    debugPrint('[AgentForm] _loadAgentForm called: $url');
    setState(() { _agentFormUrl = url; _hitlCallMinimized = true; });
    try {
      // Extract formId from URL param JSON, e.g. ...#/param?{"formId":"320"}
      final decoded = Uri.decodeFull(url);
      final formIdMatch = RegExp(r'formId.{0,3}:\s*[^\d]*(\d+)').firstMatch(decoded);
      final formId = formIdMatch?.group(1) ?? '';
      debugPrint('[AgentForm] formId=$formId');
      if (formId.isEmpty) throw Exception('formId not found in URL');
      const tenantId = '139';
      final apiUrl = 'https://kiyadynamicui.kiya.ai/DynamicUIPOC/api/Forms/getFormDetailsByTenantIdAndFormId/$tenantId/$formId';
      debugPrint('[AgentForm] fetching: $apiUrl');
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => host == 'kiyadynamicui.kiya.ai';
      final request = await httpClient.getUrl(Uri.parse(apiUrl));
      final response = await request.close();
      final body = await response.transform(const Utf8Decoder()).join();
      debugPrint('[AgentForm] response status=${response.statusCode} body=${body.substring(0, body.length.clamp(0, 300))}');
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawJsons = data['formJsons'] as String? ?? '[]';
      final containers = jsonDecode(rawJsons) as List;
      debugPrint('[AgentForm] containers count=${containers.length}');
      final groups = <JourneyFormGroup>[];
      for (final container in containers) {
        final subs = (container['sub'] ?? container['containerData'] ?? []) as List;
        final fields = <JourneyFormField>[];
        for (final f in subs) {
          final dt = (f['data_type'] ?? f['dataType'] ?? f['type'] ?? 'text').toString().toLowerCase().trim();
          if (['button', 'header', 'paragraph', 'label', 'divider'].contains(dt)) continue;
          final canonDt = const {
            'input': 'text', 'string': 'text', 'textbox': 'text',
            'dropdown': 'select', 'list': 'select',
            'multiline': 'textarea', 'multi_line': 'textarea',
            'integer': 'number', 'float': 'number', 'decimal': 'number',
            'terms': 'checkbox',
          }[dt] ?? dt;
          final key = [
            f['formName'], f['variableName'], f['variable_name'],
            f['parameter_name'], f['parameterName'], f['name'], f['key'],
          ].firstWhere((v) => v != null && v.toString().trim().isNotEmpty
              && v.toString() != '@@@@' && v.toString() != 'Dummy',
              orElse: () => null)?.toString().trim() ?? '';
          if (key.isEmpty) continue;
          final label = (f['parameter_name'] ?? f['parameterName'] ?? f['label'] ?? key).toString();
          fields.add(JourneyFormField(
            variableName: key,
            label: label,
            dataType: canonDt,
            isOptional: (f['optional'] ?? f['isOptional'] ?? 'Y').toString(),
            options: ((f['list_of_values'] ?? f['listOfValues'] ?? f['options'] ?? []) as List)
                .map<Map<String, String>>((v) => {
                      'value': (v['value'] ?? v['id'] ?? '').toString(),
                      'name': (v['name'] ?? v['label'] ?? v['value'] ?? '').toString(),
                    }).toList(),
          ));
        }
        debugPrint('[AgentForm] container "${container['contName'] ?? container['name']}" fields=${fields.length}');
        if (fields.isEmpty) continue;
        groups.add(JourneyFormGroup(
          name: (container['contName'] ?? container['name'] ?? 'Form').toString(),
          fields: fields,
          values: Map.fromEntries(fields.map((f) => MapEntry(
              f.variableName,
              f.dataType == 'checkbox'
                  ? (f.options.isNotEmpty ? <String>[] : false)
                  : ''))),
          errors: Map.fromEntries(fields.map((f) => MapEntry(f.variableName, ''))),
        ));
      }
      debugPrint('[AgentForm] groups built=${groups.length} mounted=$mounted');
      if (!mounted) return;
      if (groups.isNotEmpty) {
        setState(() {
          _djFormGroups = groups;
          _djFormGroupIndex = 0;
          _djFormHasErrors = false;
          _isAgentForm = true;
          _panelType = 'form';
        });
        debugPrint('[AgentForm] panelType set to form, groups=${_djFormGroups.length}');
      } else {
        debugPrint('[AgentForm] WARNING: no groups parsed — form will not show');
        setState(() { _agentFormUrl = null; _isAgentForm = false; });
      }
    } catch (e) {
      debugPrint('[AgentForm] failed to load: $e');
      if (mounted) setState(() { _agentFormUrl = null; _isAgentForm = false; });
    }
  }

  // ── HITL: agent-pushed scan overlay ──────────────────────────────────────
  Widget _buildHitlScanOverlay(String deviceType) {
    final cs = Theme.of(context).colorScheme;
    final isBiometric = deviceType.toLowerCase().contains('bio') ||
        deviceType.toLowerCase().contains('finger') ||
        deviceType.toLowerCase().contains('face');
    final icon     = isBiometric ? Icons.fingerprint_rounded : Icons.camera_alt_rounded;
    final label    = isBiometric ? 'Biometric Scan' : 'Document Scan';
    final sublabel = isBiometric
        ? 'The agent requires biometric verification.'
        : 'The agent requires you to scan a document.';
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.80),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF329AD6).withValues(alpha: 0.10),
                ),
                child: Icon(icon, color: const Color(0xFF329AD6), size: 38),
              ),
              const SizedBox(height: 16),
              Text(label,
                  style: TextStyle(color: cs.onSurface, fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(sublabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    setState(() => _hitlScanType = null);
                    if (isBiometric) {
                      const channel = MethodChannel('com.kiya.bankinggenie/biometric');
                      try {
                        final result =
                            await channel.invokeMethod<String>('authenticate') ?? 'cancelled';
                        if (result == 'success') {
                          _session.recordDocumentNode('Biometric Scan', 'biometric_verified');
                          _pushBot('Biometric verification successful.');
                        } else {
                          _pushBot('Biometric verification cancelled.');
                        }
                      } catch (_) {
                        _pushBot('Biometric verification failed.');
                      }
                    } else {
                      _pickDoc();
                    }
                  },
                  icon: Icon(icon),
                  label: Text('Start $label'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF329AD6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => setState(() => _hitlScanType = null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface.withValues(alpha: 0.6),
                    side: BorderSide(color: cs.onSurface.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── HITL: waiting for agent overlay ─────────────────────────────────────
  Widget _buildHitlWaitingOverlay() {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                width: 52, height: 52,
                child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF329AD6)),
              ),
              const SizedBox(height: 16),
              Text('Connecting to Agent…',
                  style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Please wait while we assign a human agent.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _session.cancelHitl();
                    _pushBot('Agent request cancelled.');
                  },
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── HITL: agent assigned overlay ──────────────────────────────────────────
  Widget _buildHitlAgentAssignedOverlay() {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.support_agent_rounded, color: Color(0xFF16A34A), size: 30),
              ),
              const SizedBox(height: 16),
              Text('Agent Assigned',
                  style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
              if (_hitlAgentName.isNotEmpty) ...[  
                const SizedBox(height: 4),
                Text(_hitlAgentName,
                    style: const TextStyle(color: Color(0xFF329AD6), fontSize: 14, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 6),
              Text('The agent is joining the call…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
              const SizedBox(height: 8),
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF329AD6)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Live call requesting overlay (no session) ──────────────────────────
  Widget _buildLiveCallRequestingOverlay() {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                width: 52, height: 52,
                child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF329AD6)),
              ),
              const SizedBox(height: 16),
              Text('Connecting…',
                  style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Waiting for an agent to join.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _liveCall.endCall,
                  icon: const Icon(Icons.call_end_rounded),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Outgoing call overlay (waiting for agent to accept) ──────────────────
  Widget _buildCallingOverlay() {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                width: 52, height: 52,
                child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF329AD6)),
              ),
              const SizedBox(height: 16),
              Text('Calling Agent…',
                  style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Waiting for an agent to accept.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _session.cancelCall,
                  icon: const Icon(Icons.call_end_rounded),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── HITL minimized PiP (bottom-right) ────────────────────────────────────
  Widget _buildHitlMinimizedPip({required VoidCallback onExpand, required VoidCallback onEnd}) {
    final remote = _remoteParticipants.isNotEmpty ? _remoteParticipants.first : null;
    final remoteVideoTrack = remote?.videoTrackPublications
        .where((p) => !p.muted && p.track != null)
        .map((p) => p.track as VideoTrack)
        .firstOrNull;
    return Positioned(
      right: 12, top: 60,
      width: 120, height: 160,
      child: GestureDetector(
        onTap: onExpand,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              if (remoteVideoTrack != null)
                VideoTrackRenderer(remoteVideoTrack)
              else
                Container(
                  color: const Color(0xFF1E293B),
                  child: const Center(
                    child: Icon(Icons.support_agent_rounded, color: Colors.white38, size: 32),
                  ),
                ),
              // End call button
              Positioned(
                top: 6, right: 6,
                child: GestureDetector(
                  onTap: onEnd,
                  child: Container(
                    width: 24, height: 24,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFEF4444),
                    ),
                    child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 13),
                  ),
                ),
              ),
              // Expand hint
              Positioned(
                bottom: 6, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Tap to expand',
                        style: TextStyle(color: Colors.white70, fontSize: 9)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HITL dashboard panel (shown when call is minimized) ───────────────────
  Widget _buildHitlDashboardPanel() => const SizedBox.shrink();

  // ── In-call overlay ──────────────────────────────────────────────────────
  Widget _buildCallOverlay({VoidCallback? onEnd, VoidCallback? onMinimize, String? agentName}) {
    final lp = _liveKit.localParticipant;
    final remote = _remoteParticipants.isNotEmpty ? _remoteParticipants.first : null;
    final remoteVideoTrack = remote?.videoTrackPublications
        .where((p) => !p.muted && p.track != null)
        .map((p) => p.track as VideoTrack)
        .firstOrNull;
    final localVideoTrack = lp?.videoTrackPublications
        .where((p) => !p.muted && p.track != null)
        .map((p) => p.track as VideoTrack)
        .firstOrNull;
    final endFn = onEnd ?? _session.endCall;
    final displayName = agentName ?? _hitlAgentName;

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // Remote video (full screen)
            if (remoteVideoTrack != null)
              VideoTrackRenderer(remoteVideoTrack)
            else
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.support_agent_rounded, color: Colors.white54, size: 44),
                  ),
                  const SizedBox(height: 12),
                  if (displayName.isNotEmpty)
                    Text(displayName,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Connecting video…',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
                  ),
                ]),
              ),
            // Local video (PiP) — always shown so user sees themselves
            if (localVideoTrack != null)
              Positioned(
                right: 16, top: 60,
                width: 100, height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: VideoTrackRenderer(localVideoTrack),
                ),
              )
            else
              Positioned(
                right: 16, top: 60,
                width: 100, height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.white12,
                    child: const Icon(Icons.person_rounded, color: Colors.white38, size: 40),
                  ),
                ),
              ),
            // Minimize button (HITL only)
            if (onMinimize != null)
              Positioned(
                top: 56, right: 130,
                child: GestureDetector(
                  onTap: onMinimize,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Minimize', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ]),
                  ),
                ),
              ),
            // Controls
            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _callBtn(
                    icon: _callMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    color: _callMicOn ? Colors.white24 : Colors.white54,
                    onTap: () async {
                      await _liveKit.toggleMic();
                      setState(() => _callMicOn = !_callMicOn);
                    },
                  ),
                  const SizedBox(width: 20),
                  _callBtn(
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFEF4444),
                    size: 56,
                    onTap: endFn,
                  ),
                  const SizedBox(width: 20),
                  _callBtn(
                    icon: _callCamOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    color: _callCamOn ? Colors.white24 : Colors.white54,
                    onTap: () async {
                      await _liveKit.toggleCamera();
                      setState(() => _callCamOn = !_callCamOn);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _callBtn({required IconData icon, required Color color, double size = 48, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }

  Widget _buildDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 32),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                style: TextStyle(
                    color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface.withValues(alpha: 0.6),
                    side: BorderSide(color: cs.onSurface.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: confirmColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Isolated FAB widget — only this rebuilds on transcript changes ──────────
class _VoiceFab extends StatelessWidget {
  final bool active;
  final String transcript;
  final VoidCallback onTap;
  const _VoiceFab({required this.active, required this.transcript, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active && transcript.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: const BoxConstraints(maxWidth: 200),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(transcript,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46, height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? const Color(0xFFEF4444) : primary,
              boxShadow: [
                BoxShadow(
                  color: (active ? const Color(0xFFEF4444) : primary).withValues(alpha: 0.4),
                  blurRadius: 12, offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              active ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: Colors.white, size: 22,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThinkingText extends StatefulWidget {
  const _ThinkingText();
  @override
  State<_ThinkingText> createState() => _ThinkingTextState();
}

class _ThinkingTextState extends State<_ThinkingText>
    with SingleTickerProviderStateMixin {
  static const _phrases = [
    'Thinking…',
    'Analyzing your request…',
    'Looking that up…',
    'Processing…',
    'Fetching details…',
    'Almost there…',
    'Checking data…',
    'Preparing response…',
  ];

  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  int _i = 0;
  String _current = _phrases[0];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
    _schedule();
  }

  void _schedule() {
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      _ctrl.reverse().then((_) {
        if (!mounted) return;
        setState(() { _i = (_i + 1) % _phrases.length; _current = _phrases[_i]; });
        _ctrl.forward();
        _schedule();
      });
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Text(
        _current,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          fontSize: 11.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _BubbleSkeleton extends StatefulWidget {
  final Color surfaceColor;
  const _BubbleSkeleton({required this.surfaceColor});
  @override
  State<_BubbleSkeleton> createState() => _BubbleSkeletonState();
}

class _BubbleSkeletonState extends State<_BubbleSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _anim = Tween(begin: -1.5, end: 2.5).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: widget.surfaceColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.08),
              blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _shimmerBar(width: 160, height: 11),
            const SizedBox(height: 7),
            _shimmerBar(width: 120, height: 11),
            const SizedBox(height: 7),
            _shimmerBar(width: 80, height: 11),
            const SizedBox(height: 10),
            const _ThinkingText(),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBar({required double width, required double height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _ShimmerPainter(_anim.value, width)),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final double pos;
  final double width;
  _ShimmerPainter(this.pos, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFE2E8F0),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.7),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(pos * width, 0, width, size.height)),
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.pos != pos;
}
