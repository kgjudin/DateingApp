import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final agoraVoiceServiceProvider = Provider<AgoraVoiceService>((ref) => AgoraVoiceService());

class AgoraVoiceService {
  RtcEngine? _engine;
  bool _isInitialized = false;
  bool _isPublisher = false;
  bool _isMuted = true;
  bool _isSpeakerOn = true;
  String? _currentChannel;

  final _userJoinedController = StreamController<int>.broadcast();
  final _userOfflineController = StreamController<int>.broadcast();
  final _volumeIndicatorController = StreamController<List<AudioVolumeInfo>>.broadcast();

  Stream<int> get onUserJoined => _userJoinedController.stream;
  Stream<int> get onUserOffline => _userOfflineController.stream;
  Stream<List<AudioVolumeInfo>> get onVolumeIndicator => _volumeIndicatorController.stream;

  bool get isMuted => _isMuted;
  bool get isPublisher => _isPublisher;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isConnected => _currentChannel != null;

  Future<bool> initialize(String appId) async {
    if (_isInitialized && _engine != null) return true;

    try {
      // Request microphone permission on mobile only if needed
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
            debugPrint('[Agora] Joined channel: ${connection.channelId} (localUid: ${connection.localUid}, isPublisher: $_isPublisher, isMuted: $_isMuted)');
            _currentChannel = connection.channelId;
            try {
              if (!_isPublisher || _isMuted) {
                _engine?.muteLocalAudioStream(true);
                _engine?.enableLocalAudio(false);
              } else {
                _engine?.enableLocalAudio(true);
                _engine?.muteLocalAudioStream(false);
              }
              _engine?.muteAllRemoteAudioStreams(false);
            } catch (_) {}
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint('[Agora] Remote user joined: $remoteUid - unmuting remote audio');
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
    bool initiallyMuted = false,
  }) async {
    await initialize(appId);

    _isPublisher = isPublisher;
    _isMuted = !isPublisher || initiallyMuted;

    try {
      if (_engine != null) {
        if (isPublisher) {
          try {
            await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
          } catch (_) {}
          try { await _engine!.enableAudio(); } catch (_) {}
          try { await _engine!.enableLocalAudio(!_isMuted); } catch (_) {}

          await _engine!.joinChannel(
            token: token,
            channelId: channelId,
            uid: 0,
            options: ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleBroadcaster,
              channelProfile: ChannelProfileType.channelProfileCommunication,
              publishMicrophoneTrack: !_isMuted,
              autoSubscribeAudio: true,
              enableAudioRecordingOrPlayout: true,
            ),
          );

          try { await _engine!.muteLocalAudioStream(_isMuted); } catch (_) {}
        } else {
          // Audience / Listener: Strictly disable local mic publishing
          try {
            await _engine!.setClientRole(role: ClientRoleType.clientRoleAudience);
          } catch (_) {}
          try { await _engine!.enableAudio(); } catch (_) {}
          try { await _engine!.enableLocalAudio(false); } catch (_) {}

          await _engine!.joinChannel(
            token: token,
            channelId: channelId,
            uid: 0,
            options: const ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleAudience,
              channelProfile: ChannelProfileType.channelProfileCommunication,
              publishMicrophoneTrack: false,
              autoSubscribeAudio: true,
              enableAudioRecordingOrPlayout: true,
            ),
          );

          try { await _engine!.muteLocalAudioStream(true); } catch (_) {}
        }

        try { await _engine!.muteAllRemoteAudioStreams(false); } catch (_) {}
        try { await _engine!.adjustRecordingSignalVolume(100); } catch (_) {}
        try { await _engine!.adjustPlaybackSignalVolume(100); } catch (_) {}
      }
      _currentChannel = channelId;
    } catch (e) {
      debugPrint('[Agora] Join channel error: $e');
      _currentChannel = channelId;
    }
  }

  Future<void> updateRole({required bool isPublisher, bool isMuted = false}) async {
    _isPublisher = isPublisher;
    _isMuted = !isPublisher || isMuted;

    try {
      if (_engine != null) {
        if (isPublisher) {
          await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
          await _engine!.enableLocalAudio(!_isMuted);
          await _engine!.muteLocalAudioStream(_isMuted);
          try {
            await _engine!.updateChannelMediaOptions(
              ChannelMediaOptions(
                clientRoleType: ClientRoleType.clientRoleBroadcaster,
                publishMicrophoneTrack: !_isMuted,
                autoSubscribeAudio: true,
              ),
            );
          } catch (_) {}
        } else {
          // Demote to audience: immediately silence mic
          await _engine!.muteLocalAudioStream(true);
          await _engine!.enableLocalAudio(false);
          try {
            await _engine!.updateChannelMediaOptions(
              const ChannelMediaOptions(
                clientRoleType: ClientRoleType.clientRoleAudience,
                publishMicrophoneTrack: false,
                autoSubscribeAudio: true,
              ),
            );
          } catch (_) {}
          await _engine!.setClientRole(role: ClientRoleType.clientRoleAudience);
        }
      }
    } catch (e) {
      debugPrint('[Agora] Update role error: $e');
    }
  }

  Future<void> setMuted(bool muted) async {
    if (!_isPublisher) {
      _isMuted = true;
      try {
        if (_engine != null) {
          await _engine!.muteLocalAudioStream(true);
          await _engine!.enableLocalAudio(false);
        }
      } catch (_) {}
      return;
    }

    _isMuted = muted;
    try {
      if (_engine != null) {
        if (_isMuted) {
          await _engine!.muteLocalAudioStream(true);
          await _engine!.enableLocalAudio(false);
          try {
            await _engine!.updateChannelMediaOptions(
              const ChannelMediaOptions(publishMicrophoneTrack: false),
            );
          } catch (_) {}
        } else {
          await _engine!.enableLocalAudio(true);
          await _engine!.muteLocalAudioStream(false);
          try {
            await _engine!.updateChannelMediaOptions(
              const ChannelMediaOptions(publishMicrophoneTrack: true),
            );
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[Agora] Set muted error: $e');
    }
  }

  Future<void> toggleMute() async {
    if (!_isPublisher) return;
    await setMuted(!_isMuted);
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
        try { await _engine!.muteLocalAudioStream(true); } catch (_) {}
        try { await _engine!.enableLocalAudio(false); } catch (_) {}
        await _engine!.leaveChannel();
      }
    } catch (e) {
      debugPrint('[Agora] Leave error: $e');
    } finally {
      _currentChannel = null;
      _isPublisher = false;
      _isMuted = true;
    }
  }

  void dispose() {
    leaveChannel();
    _engine?.release();
    _engine = null;
    _isInitialized = false;
  }
}
