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
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          audioScenario: AudioScenarioType.audioScenarioGameStreaming,
        ),
      );

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint('[Agora] Successfully joined channel: ${connection.channelId}');
            _currentChannel = connection.channelId;
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint('[Agora] Remote user joined: $remoteUid');
            _userJoinedController.add(remoteUid);
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

      await _engine!.enableAudio();
      await _engine!.enableAudioVolumeIndication(interval: 200, smooth: 3, reportVad: true);
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[Agora] Initialization error: $e');
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
        // Set client role
        await _engine!.setClientRole(
          role: isPublisher ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
        );

        await _engine!.joinChannel(
          token: token,
          channelId: channelId,
          uid: 0,
          options: ChannelMediaOptions(
            clientRoleType: isPublisher ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
            publishMicrophoneTrack: isPublisher,
            autoSubscribeAudio: true,
          ),
        );
      }
      _currentChannel = channelId;
      _isMuted = !isPublisher;
    } catch (e) {
      debugPrint('[Agora] Join channel error: $e');
      _currentChannel = channelId;
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
