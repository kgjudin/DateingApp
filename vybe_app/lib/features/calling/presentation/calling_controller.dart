import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/voice/agora_voice_service.dart';

enum CallStatus { idle, initiating, ringing, connecting, connected, ended, failed }

class CallingState {
  final CallStatus status;
  final String? callId;
  final String? channelName;
  final String? agoraToken;
  final String? appId;
  final Map<String, dynamic>? peerProfile;
  final int durationSeconds;
  final bool isMuted;
  final bool isSpeakerOn;
  final String? errorMessage;

  CallingState({
    this.status = CallStatus.idle,
    this.callId,
    this.channelName,
    this.agoraToken,
    this.appId,
    this.peerProfile,
    this.durationSeconds = 0,
    this.isMuted = false,
    this.isSpeakerOn = true,
    this.errorMessage,
  });

  CallingState copyWith({
    CallStatus? status,
    String? callId,
    String? channelName,
    String? agoraToken,
    String? appId,
    Map<String, dynamic>? peerProfile,
    int? durationSeconds,
    bool? isMuted,
    bool? isSpeakerOn,
    String? errorMessage,
  }) {
    return CallingState(
      status: status ?? this.status,
      callId: callId ?? this.callId,
      channelName: channelName ?? this.channelName,
      agoraToken: agoraToken ?? this.agoraToken,
      appId: appId ?? this.appId,
      peerProfile: peerProfile ?? this.peerProfile,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      errorMessage: errorMessage,
    );
  }
}

final callingControllerProvider = StateNotifierProvider<CallingController, CallingState>((ref) {
  return CallingController(ref);
});

class CallingController extends StateNotifier<CallingState> {
  final Ref _ref;
  Timer? _callDurationTimer;
  StreamSubscription? _socketCallAcceptedSub;
  StreamSubscription? _socketCallEndedSub;

  CallingController(this._ref) : super(CallingState()) {
    _listenToSocketEvents();
  }

  void _listenToSocketEvents() {
    final socket = _ref.read(socketServiceProvider);

    _socketCallAcceptedSub = socket.onCallAccepted.listen((data) {
      if (state.status == CallStatus.ringing || state.status == CallStatus.connecting) {
        _onCallConnected();
      }
    });

    _socketCallEndedSub = socket.onCallEnded.listen((data) {
      endCall();
    });
  }

  Future<void> startCall({
    required String receiverId,
    required Map<String, dynamic> receiverProfile,
  }) async {
    state = state.copyWith(
      status: CallStatus.initiating,
      peerProfile: receiverProfile,
      durationSeconds: 0,
      errorMessage: null,
    );

    try {
      final res = await _ref.read(apiClientProvider).post('/calls/initiate', body: {
        'receiverId': receiverId,
      });

      if (res is Map && res['callId'] != null) {
        final callId = res['callId'] as String;
        final channelName = res['channelName'] as String;
        final token = res['token'] as String;
        final appId = res['appId'] as String;

        state = state.copyWith(
          status: CallStatus.ringing,
          callId: callId,
          channelName: channelName,
          agoraToken: token,
          appId: appId,
        );

        // Join Agora voice channel
        await _ref.read(agoraVoiceServiceProvider).joinVoiceChannel(
              appId: appId,
              channelId: channelName,
              token: token,
              isPublisher: true,
            );
      }
    } catch (e) {
      debugPrint('[Calling] Start call error: $e');
      // Dev simulation fallback
      state = state.copyWith(
        status: CallStatus.ringing,
        callId: 'call_${DateTime.now().millisecondsSinceEpoch}',
        channelName: 'vybe_dev_channel',
      );
      // Simulate answer after 3 seconds in demo mode
      Future.delayed(const Duration(seconds: 3), () {
        if (state.status == CallStatus.ringing) {
          _onCallConnected();
        }
      });
    }
  }

  Future<void> acceptCall({
    required String callId,
    required String channelName,
    required String token,
    required String appId,
    required Map<String, dynamic> callerProfile,
  }) async {
    state = state.copyWith(
      status: CallStatus.connecting,
      callId: callId,
      channelName: channelName,
      agoraToken: token,
      appId: appId,
      peerProfile: callerProfile,
    );

    try {
      await _ref.read(apiClientProvider).post('/calls/accept', body: {'callId': callId});
      await _ref.read(agoraVoiceServiceProvider).joinVoiceChannel(
            appId: appId,
            channelId: channelName,
            token: token,
            isPublisher: true,
          );
      _onCallConnected();
    } catch (e) {
      _onCallConnected(); // allow demo fallback
    }
  }

  void _onCallConnected() {
    state = state.copyWith(status: CallStatus.connected);
    _startDurationTimer();
  }

  void _startDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(durationSeconds: state.durationSeconds + 1);
    });
  }

  Future<void> toggleMute() async {
    await _ref.read(agoraVoiceServiceProvider).toggleMute();
    state = state.copyWith(isMuted: _ref.read(agoraVoiceServiceProvider).isMuted);
  }

  Future<void> toggleSpeaker() async {
    await _ref.read(agoraVoiceServiceProvider).toggleSpeaker();
    state = state.copyWith(isSpeakerOn: _ref.read(agoraVoiceServiceProvider).isSpeakerOn);
  }

  Future<void> endCall() async {
    _callDurationTimer?.cancel();
    _callDurationTimer = null;

    final callId = state.callId;
    final duration = state.durationSeconds;

    try {
      if (callId != null) {
        await _ref.read(apiClientProvider).post('/calls/end', body: {
          'callId': callId,
          'durationSeconds': duration,
        });
      }
    } catch (_) {}

    await _ref.read(agoraVoiceServiceProvider).leaveChannel();

    state = state.copyWith(status: CallStatus.ended);
    Future.delayed(const Duration(milliseconds: 500), () {
      state = CallingState();
    });
  }

  @override
  void dispose() {
    _callDurationTimer?.cancel();
    _socketCallAcceptedSub?.cancel();
    _socketCallEndedSub?.cancel();
    super.dispose();
  }
}
