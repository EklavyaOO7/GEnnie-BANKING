import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

class LiveKitService {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  final _participantCtrl =
      StreamController<List<RemoteParticipant>>.broadcast();
  Stream<List<RemoteParticipant>> get participants$ =>
      _participantCtrl.stream;

  List<RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants.values.toList() ?? [];

  LocalParticipant? get localParticipant => _room?.localParticipant;

  bool get isConnected => _room != null;

  Future<void> connect(
    String url,
    String token, {
    VoidCallback? onDisconnected,
  }) async {
    await disconnect();

    _room = Room();
    _listener = _room!.createListener();

    _listener!
      ..on<ParticipantConnectedEvent>((_) => _emitParticipants())
      ..on<ParticipantDisconnectedEvent>((_) => _emitParticipants())
      ..on<TrackSubscribedEvent>((_) => _emitParticipants())
      ..on<TrackUnsubscribedEvent>((_) => _emitParticipants())
      ..on<LocalTrackPublishedEvent>((_) => _emitParticipants())
      ..on<LocalTrackUnpublishedEvent>((_) => _emitParticipants())
      ..on<RoomDisconnectedEvent>((_) {
        if (_room != null) onDisconnected?.call();
      });

    try {
      await _room!
          .connect(
            url,
            token,
            roomOptions: const RoomOptions(
              adaptiveStream: true,
              dynacast: true,
            ),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[LiveKit] connect failed: $e');
      await disconnect();
      return;
    }

    unawaited(_enableMedia());
    _emitParticipants();
  }

  Future<void> _enableMedia() async {
    try {
      await _room?.localParticipant
          ?.setCameraEnabled(true)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[LiveKit] camera enable failed: $e');
    }
    try {
      await _room?.localParticipant
          ?.setMicrophoneEnabled(true)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[LiveKit] mic enable failed: $e');
    }
    _emitParticipants();
  }

  void _emitParticipants() {
    if (!_participantCtrl.isClosed) {
      _participantCtrl.add(remoteParticipants);
    }
  }

  Future<void> toggleMic() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    try {
      await lp
          .setMicrophoneEnabled(!lp.isMicrophoneEnabled())
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> toggleCamera() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    try {
      await lp
          .setCameraEnabled(!lp.isCameraEnabled())
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> disconnect() async {
    final room = _room;
    _room = null;
    _listener?.dispose();
    _listener = null;
    try {
      await room?.disconnect().timeout(const Duration(seconds: 5));
    } catch (_) {}
    room?.dispose();
    _emitParticipants();
  }

  void dispose() {
    unawaited(disconnect());
    _participantCtrl.close();
  }
}
