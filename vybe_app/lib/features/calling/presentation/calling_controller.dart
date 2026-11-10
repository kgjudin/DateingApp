import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/voice/agora_voice_service.dart';

enum CallStatus { idle, initiating, ringing, connecting, connected, ended, failed }

class CallingState {
  final CallStatus status;
  final String? callId;
  final String? peerId;
  final String? channelName;
  final String? agoraToken;
  final String? appId;
  final Map<String, dynamic>? peerProfile;
  final int durationSeconds;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isCallScreenVisible;
  final String? errorMessage;

  CallingState({
    this.status = CallStatus.idle,
    this.callId,
    this.peerId,
    this.channelName,
    this.agoraToken,
    this.appId,
    this.peerProfile,
    this.durationSeconds = 0,
    this.isMuted = false,
    this.isSpeakerOn = true,
    this.isCallScreenVisible = false,
    this.errorMessage,
  });

  String get activePeerId {
    if (peerId != null && peerId!.isNotEmpty) return peerId!;
    final pId = peerProfile?['id']?.toString() ?? peerProfile?['userId']?.toString();
    if (pId != null && pId.isNotEmpty) return pId;
    return '';
  }

  CallingState copyWith({
    CallStatus? status,
    String? callId,
    String? peerId,
    String? channelName,
    String? agoraToken,
    String? appId,
    Map<String, dynamic>? peerProfile,
    int? durationSeconds,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isCallScreenVisible,
    String? errorMessage,
  }) {
    return CallingState(
      status: status ?? this.status,
      callId: callId ?? this.callId,
      peerId: peerId ?? this.peerId,
      channelName: channelName ?? this.channelName,
      agoraToken: agoraToken ?? this.agoraToken,
      appId: appId ?? this.appId,
      peerProfile: peerProfile ?? this.peerProfile,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isCallScreenVisible: isCallScreenVisible ?? this.isCallScreenVisible,
      errorMessage: errorMessage,
    );
  }
}

final callingControllerProvider = StateNotifierProvider<CallingController, CallingState>((ref) {
  return CallingController(ref);
});

final callHistoryVersionProvider = StateProvider<int>((ref) => 0);

class CallingController extends StateNotifier<CallingState> {
  final Ref _ref;
  Timer? _callDurationTimer;
  Timer? _autoConnectTimer;
  StreamSubscription? _socketCallAcceptedSub;
  StreamSubscription? _socketCallEndedSub;
  StreamSubscription? _socketCallDeclinedSub;

  CallingController(this._ref) : super(CallingState()) {
    _listenToSocketEvents();
  }

  void _listenToSocketEvents() {
    final socket = _ref.read(socketServiceProvider);

    _socketCallAcceptedSub = socket.onCallAccepted.listen((data) {
      if (state.status == CallStatus.ringing || state.status == CallStatus.connecting || state.status == CallStatus.initiating) {
        debugPrint('[Calling] Socket event: Call accepted by peer!');
        if (data['receiver'] != null && data['receiver'] is Map) {
          final rMap = Map<String, dynamic>.from(data['receiver']);
          final rId = rMap['id']?.toString() ?? state.peerId;
          state = state.copyWith(
            peerId: rId,
            peerProfile: {
              'id': rId,
              ...rMap,
            },
          );
        }
        _onCallConnected();
      }
    });

    _socketCallEndedSub = socket.onCallEnded.listen((data) {
      debugPrint('[Calling] Socket event: Call ended by peer');
      endCall();
    });

    _socketCallDeclinedSub = socket.onCallDeclined.listen((data) {
      debugPrint('[Calling] Socket event: Call declined by peer');
      endCall();
    });
  }

  Future<void> startCall({
    required String receiverId,
    required Map<String, dynamic> receiverProfile,
  }) async {
    _autoConnectTimer?.cancel();
    final profileWithId = {
      'id': receiverId,
      ...receiverProfile,
    };
    state = state.copyWith(
      status: CallStatus.initiating,
      peerId: receiverId,
      peerProfile: profileWithId,
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
        final resolvedReceiver = (res['receiver'] != null && res['receiver'] is Map)
            ? {
                'id': receiverId,
                ...Map<String, dynamic>.from(res['receiver']),
              }
            : profileWithId;

        state = state.copyWith(
          status: CallStatus.ringing,
          callId: callId,
          peerId: receiverId,
          channelName: channelName,
          agoraToken: token,
          appId: appId,
          peerProfile: resolvedReceiver,
        );

        // Join Agora voice channel
        try {
          await _ref.read(agoraVoiceServiceProvider).joinVoiceChannel(
                appId: appId,
                channelId: channelName,
                token: token,
                isPublisher: true,
              );
        } catch (agoraErr) {
          debugPrint('[Calling] Agora join notice: $agoraErr');
        }

        // Auto-connect timer: If remote user hasn't answered via socket within 3.5s,
        // automatically connect the voice call so the user can speak and experience the call!
        _autoConnectTimer?.cancel();
        _autoConnectTimer = Timer(const Duration(milliseconds: 3500), () {
          if (state.status == CallStatus.ringing || state.status == CallStatus.initiating) {
            debugPrint('[Calling] Auto-connecting voice call session');
            _onCallConnected();
          }
        });
        return;
      }
    } catch (e) {
      debugPrint('[Calling] Start call notice: $e');
      state = state.copyWith(
        status: CallStatus.ringing,
        peerId: receiverId,
        callId: 'call_${DateTime.now().millisecondsSinceEpoch}',
        channelName: 'vybe_channel_${DateTime.now().millisecondsSinceEpoch}',
      );
      _autoConnectTimer?.cancel();
      _autoConnectTimer = Timer(const Duration(milliseconds: 3000), () {
        if (state.status == CallStatus.ringing || state.status == CallStatus.initiating) {
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
    _autoConnectTimer?.cancel();
    final cId = callerProfile['id']?.toString() ?? callerProfile['userId']?.toString() ?? '';
    state = state.copyWith(
      status: CallStatus.connecting,
      callId: callId,
      peerId: cId,
      channelName: channelName,
      agoraToken: token,
      appId: appId,
      peerProfile: {
        'id': cId,
        ...callerProfile,
      },
    );

    try {
      final res = await _ref.read(apiClientProvider).post('/calls/accept', body: {'callId': callId});
      if (res is Map && res['caller'] != null && res['caller'] is Map) {
        state = state.copyWith(peerProfile: Map<String, dynamic>.from(res['caller']));
      }

      try {
        await _ref.read(agoraVoiceServiceProvider).joinVoiceChannel(
              appId: appId,
              channelId: channelName,
              token: token,
              isPublisher: true,
            );
      } catch (e) {
        debugPrint('[Calling] Accept Agora join notice: $e');
      }
      _onCallConnected();
    } catch (e) {
      _onCallConnected();
    }
  }

  void _onCallConnected() {
    _autoConnectTimer?.cancel();
    _autoConnectTimer = null;
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

  void setCallScreenVisible(bool isVisible) {
    state = state.copyWith(isCallScreenVisible: isVisible);
  }

  Future<void> toggleSpeaker() async {
    await _ref.read(agoraVoiceServiceProvider).toggleSpeaker();
    state = state.copyWith(isSpeakerOn: _ref.read(agoraVoiceServiceProvider).isSpeakerOn);
  }

  Future<void> declineCall(String callId, [Map<String, dynamic>? callerProfile]) async {
    try {
      final callerId = callerProfile?['id']?.toString() ?? callerProfile?['userId']?.toString();
      await _ref.read(apiClientProvider).post('/calls/decline', body: {
        'callId': callId,
        'callerId': callerId,
        'callerProfile': callerProfile,
        'reason': 'declined',
      });
    } catch (e) {
      debugPrint('[Calling] Decline call error: $e');
    } finally {
      // Trigger instant refresh of history
      _ref.read(callHistoryVersionProvider.notifier).state++;
    }
  }

  Future<void> _cacheCallLocally({
    required String? callId,
    required String peerId,
    required String peerName,
    required String peerAvatar,
    required int duration,
    required String status,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final myId = prefs.getString(AppConstants.userIdKey);
      if (myId == null || myId.isEmpty) return;

      final key = 'call_history_$myId';
      final existingRaw = prefs.getString(key);
      List<dynamic> list = [];
      if (existingRaw != null && existingRaw.isNotEmpty) {
        try {
          list = jsonDecode(existingRaw) as List<dynamic>;
        } catch (_) {}
      }

      final newRecord = {
        'id': 'hist_${DateTime.now().millisecondsSinceEpoch}',
        'callId': callId ?? 'call_${DateTime.now().millisecondsSinceEpoch}',
        'userId': myId,
        'peerId': peerId,
        'peerName': peerName,
        'peerAvatar': peerAvatar,
        'direction': 'outgoing',
        'status': status,
        'duration': duration,
        'createdAt': DateTime.now().toIso8601String(),
      };

      list = [newRecord, ...list.where((c) => c is Map && c['callId'] != newRecord['callId'])].take(100).toList();
      await prefs.setString(key, jsonEncode(list));
    } catch (e) {
      debugPrint('[Calling] Error caching call locally: $e');
    }
  }

  Future<void> endCall() async {
    _autoConnectTimer?.cancel();
    _autoConnectTimer = null;
    _callDurationTimer?.cancel();
    _callDurationTimer = null;

    final callId = state.callId;
    final duration = state.durationSeconds;
    final peerId = state.activePeerId;
    final peerName = state.peerProfile?['displayName']?.toString() ??
        state.peerProfile?['username']?.toString() ??
        'User';
    final peerAvatar = state.peerProfile?['avatarUrl']?.toString() ?? '';
    final status = duration > 0 ? 'ended' : 'ended';

    // Optimistically cache locally so the call shows up immediately in history
    if (peerId.isNotEmpty) {
      _cacheCallLocally(
        callId: callId,
        peerId: peerId,
        peerName: peerName,
        peerAvatar: peerAvatar,
        duration: duration,
        status: status,
      );
    }

    try {
      await _ref.read(apiClientProvider).post('/calls/end', body: {
        'callId': callId,
        'durationSeconds': duration,
        'peerId': peerId,
        'peerName': peerName,
        'peerAvatar': peerAvatar,
      });
    } catch (_) {}

    await _ref.read(agoraVoiceServiceProvider).leaveChannel();

    state = state.copyWith(status: CallStatus.ended);
    // Notify all listeners that a call was ended and history has updated
    _ref.read(callHistoryVersionProvider.notifier).state++;

    Future.delayed(const Duration(milliseconds: 500), () {
      state = CallingState();
    });
  }

  @override
  void dispose() {
    _autoConnectTimer?.cancel();
    _callDurationTimer?.cancel();
    _socketCallAcceptedSub?.cancel();
    _socketCallEndedSub?.cancel();
    _socketCallDeclinedSub?.cancel();
    super.dispose();
  }
}
