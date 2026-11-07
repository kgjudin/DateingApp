import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final agoraVoiceServiceProvider = Provider<AgoraVoiceService>((ref) => AgoraVoiceService());

class AgoraVoiceService {
  RtcEngine? _engine;
  bool _isInitialized = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  String? _currentChannel;

  final _userJoinedController = StreamController<int>.broadcast();
  final _userOfflineController = StreamController<int>.broadcast();
  final _volumeIndicatorController = StreamController<List<AudioVolumeInfo>>.broadcast();

  Stream<int> get onUserJoined => _userJoinedController.stream;
  Stream<int> get onUserOffline => _userOfflineController.stream;
  Stream<List<AudioVolumeInfo>> get onVolumeIndicator => _volumeIndicatorController.stream;

  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isConnected => _currentChannel != null;

  Future<bool> initialize(String appId) async {
    if (_isInitialized && _engine != null) return true;

    try {
      // Request microphone permission on mobile
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          debugPrint('[Agora] Microphone permission denied');
        }
      }

      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          audioScenario: AudioScenarioType.audioScenarioDefault,
        ),
      );

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint('[Agora] Successfully joined channel: ${connection.channelId} localUid: ${connection.localUid}');
            _currentChannel = connection.channelId;
            try { _engine?.muteLocalAudioStream(false); } catch (_) {}
            try { _engine?.muteAllRemoteAudioStreams(false); } catch (_) {}
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint('[Agora] Remote user joined: $remoteUid - unmuting remote audio stream');
            _userJoinedController.add(remoteUid);
            try {
              _engine?.muteRemoteAudioStream(uid: remoteUid, mute: false);
            } catch (_) {}
            try {
              if (!kIsWeb) {
                _engine?.adjustUserPlaybackSignalVolume(uid: remoteUid, volume: 100);
              }
            } catch (_) {}
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint('[Agora] Remote user offline: $remoteUid');
            _userOfflineController.add(remoteUid);
          },
          onAudioVolumeIndication: (RtcConnection connection, List<AudioVolumeInfo> speakers, int totalVolume, int speakerNumber) {
            _volumeIndicatorController.add(speakers);
          },
          onError: (ErrorCodeType err, String msg) {
            debugPrint('[Agora Error] $err: $msg');
          },
        ),
      );

      try { await _engine!.enableAudio(); } catch (_) {}
      try { await _engine!.enableLocalAudio(true); } catch (_) {}
      try { await _engine!.muteLocalAudioStream(false); } catch (_) {}
      try { await _engine!.muteAllRemoteAudioStreams(false); } catch (_) {}
      try { await _engine!.adjustRecordingSignalVolume(100); } catch (_) {}
      try { await _engine!.adjustPlaybackSignalVolume(100); } catch (_) {}
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
        try { await _engine!.setDefaultAudioRouteToSpeakerphone(true); } catch (_) {}
      }
      try { await _engine!.enableAudioVolumeIndication(interval: 200, smooth: 3, reportVad: true); } catch (_) {}
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[Agora] Initialization notice: $e');
      _isInitialized = true; // Allow dev fallback
      return false;
    }
  }

  Future<void> joinVoiceChannel({
    required String appId,
    required String channelId,
    required String token,
    required bool isPublisher,
  }) async {
    await initialize(appId);

    try {
      if (_engine != null) {
        try {
          await _engine!.setClientRole(
            role: ClientRoleType.clientRoleBroadcaster,
          );
        } catch (_) {}

        try { await _engine!.enableAudio(); } catch (_) {}
        try { await _engine!.enableLocalAudio(true); } catch (_) {}

        await _engine!.joinChannel(
          token: token,
          channelId: channelId,
          uid: 0,
          options: const ChannelMediaOptions(
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            channelProfile: ChannelProfileType.channelProfileCommunication,
            publishMicrophoneTrack: true,
            autoSubscribeAudio: true,
            enableAudioRecordingOrPlayout: true,
          ),
        );

        try { await _engine!.muteLocalAudioStream(false); } catch (_) {}
        try { await _engine!.muteAllRemoteAudioStreams(false); } catch (_) {}
        try { await _engine!.adjustRecordingSignalVolume(100); } catch (_) {}
        try { await _engine!.adjustPlaybackSignalVolume(100); } catch (_) {}
      }
      _currentChannel = channelId;
      _isMuted = false;
    } catch (e) {
      debugPrint('[Agora] Join channel error: $e');
      _currentChannel = channelId;
    }
  }

  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    try {
      if (_engine != null) {
        await _engine!.muteLocalAudioStream(_isMuted);
      }
    } catch (e) {
      debugPrint('[Agora] Set muted error: $e');
    }
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    try {
      if (_engine != null) {
        await _engine!.muteLocalAudioStream(_isMuted);
      }
    } catch (e) {
      debugPrint('[Agora] Mute error: $e');
    }
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    try {
      if (_engine != null) {
        await _engine!.setEnableSpeakerphone(_isSpeakerOn);
      }
    } catch (e) {
      debugPrint('[Agora] Speaker error: $e');
    }
  }

  Future<void> leaveChannel() async {
    try {
      if (_engine != null && _currentChannel != null) {
        await _engine!.leaveChannel();
      }
    } catch (e) {
      debugPrint('[Agora] Leave error: $e');
    } finally {
      _currentChannel = null;
      _isMuted = false;
    }
  }

  void dispose() {
    leaveChannel();
    _engine?.release();
    _engine = null;
    _isInitialized = false;
  }
}
