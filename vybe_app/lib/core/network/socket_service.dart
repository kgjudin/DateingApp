import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/app_constants.dart';

final socketServiceProvider = Provider<SocketService>((ref) => SocketService());

class SocketService {
  io.Socket? _socket;
  Timer? _heartbeatTimer;

  // Stream Controllers for Reactive UI
  final _incomingCallController = StreamController<Map<String, dynamic>>.broadcast();
  final _callAcceptedController = StreamController<Map<String, dynamic>>.broadcast();
  final _callEndedController = StreamController<Map<String, dynamic>>.broadcast();
  final _callDeclinedController = StreamController<Map<String, dynamic>>.broadcast();
  final _liveGiftController = StreamController<Map<String, dynamic>>.broadcast();
  final _giftReceivedController = StreamController<Map<String, dynamic>>.broadcast();
  final _walletUpdatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  final _roomSpeakerController = StreamController<Map<String, dynamic>>.broadcast();
  final _roomUpdatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _speakerRequestsController = StreamController<Map<String, dynamic>>.broadcast();
  final _roomInvitationController = StreamController<Map<String, dynamic>>.broadcast();
  final _speakerApprovedController = StreamController<Map<String, dynamic>>.broadcast();
  final _speakerMutedController = StreamController<Map<String, dynamic>>.broadcast();
  final _speakerDemotedController = StreamController<Map<String, dynamic>>.broadcast();
  final _userKickedController = StreamController<Map<String, dynamic>>.broadcast();
  final _hostChangedController = StreamController<Map<String, dynamic>>.broadcast();
  final _roomEndedController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceChangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _followedUserOnlineController = StreamController<Map<String, dynamic>>.broadcast();
  final _newFollowerController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onIncomingCall => _incomingCallController.stream;
  Stream<Map<String, dynamic>> get onCallAccepted => _callAcceptedController.stream;
  Stream<Map<String, dynamic>> get onCallEnded => _callEndedController.stream;
  Stream<Map<String, dynamic>> get onCallDeclined => _callDeclinedController.stream;
  Stream<Map<String, dynamic>> get onLiveGift => _liveGiftController.stream;
  Stream<Map<String, dynamic>> get onGiftReceived => _giftReceivedController.stream;
  Stream<Map<String, dynamic>> get onWalletUpdated => _walletUpdatedController.stream;
  Stream<Map<String, dynamic>> get onNotificationReceived => _notificationController.stream;
  Stream<Map<String, dynamic>> get onNewFollower => _newFollowerController.stream;
  Stream<Map<String, dynamic>> get onRoomSpeakerUpdated => _roomSpeakerController.stream;
  Stream<Map<String, dynamic>> get onRoomUpdated => _roomUpdatedController.stream;
  Stream<Map<String, dynamic>> get onSpeakerRequestsUpdated => _speakerRequestsController.stream;
  Stream<Map<String, dynamic>> get onRoomInvitationToSpeak => _roomInvitationController.stream;
  Stream<Map<String, dynamic>> get onSpeakerApproved => _speakerApprovedController.stream;
  Stream<Map<String, dynamic>> get onSpeakerMuted => _speakerMutedController.stream;
  Stream<Map<String, dynamic>> get onSpeakerDemoted => _speakerDemotedController.stream;
  Stream<Map<String, dynamic>> get onUserKicked => _userKickedController.stream;
  Stream<Map<String, dynamic>> get onHostChanged => _hostChangedController.stream;
  Stream<Map<String, dynamic>> get onRoomEnded => _roomEndedController.stream;
  Stream<Map<String, dynamic>> get onPresenceChanged => _presenceChangeController.stream;
  Stream<Map<String, dynamic>> get onFollowedUserOnline => _followedUserOnlineController.stream;

  bool get isConnected => _socket?.connected ?? false;

  String? _connectedUserId;

  void connect(String userId) {
    if (_socket != null && _socket!.connected && _connectedUserId == userId) return;

    try {
      if (_socket != null) {
        _socket!.disconnect();
        _socket!.dispose();
        _socket = null;
      }
      _connectedUserId = userId;

      _socket = io.io(
        AppConstants.socketUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .disableAutoConnect()
            .setQuery({'userId': userId})
            .build(),
      );

      _socket!.connect();

      _socket!.onConnect((_) {
        debugPrint('[Socket] Connected to VYBE signaling server for user: $userId');
        _socket?.emit('register', {'userId': userId});
        _startHeartbeat(userId);
      });

      _socket!.onDisconnect((_) {
        debugPrint('[Socket] Disconnected from server');
        _stopHeartbeat();
      });

      // Call Signaling
      _socket!.on('incoming_call', (data) {
        if (data is Map) {
          _incomingCallController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('call_accepted', (data) {
        if (data is Map) {
          _callAcceptedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('call_ended', (data) {
        if (data is Map) {
          _callEndedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('call_declined', (data) {
        if (data is Map) {
          _callDeclinedController.add(Map<String, dynamic>.from(data));
        }
      });

      // Room & Gift Events
      _socket!.on('gift_received', (data) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _giftReceivedController.add(map);
          _liveGiftController.add(map);
        }
      });

      _socket!.on('live_gift_animation', (data) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _liveGiftController.add(map);
          _giftReceivedController.add(map);
        }
      });

      _socket!.on('wallet_updated', (data) {
        if (data is Map) {
          _walletUpdatedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('new_follower', (data) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _newFollowerController.add(map);
          if (map['notification'] != null && map['notification'] is Map) {
            _notificationController.add(Map<String, dynamic>.from(map['notification']));
          } else {
            _notificationController.add(map);
          }
        }
      });

      _socket!.on('notification_received', (data) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _notificationController.add(map);
          final type = map['type']?.toString();
          if (type == 'new_follower' || type == 'follow') {
            _newFollowerController.add(map);
          }
        }
      });

      _socket!.on('speaker_list_updated', (data) {
        if (data is Map) {
          _roomSpeakerController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('room_updated', (data) {
        if (data is Map) {
          _roomUpdatedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('speaker_requests_updated', (data) {
        if (data is Map) {
          _speakerRequestsController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('speaker_request_received', (data) {
        if (data is Map) {
          _speakerRequestsController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('room_invitation_to_speak', (data) {
        if (data is Map) {
          _roomInvitationController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('speaker_approved', (data) {
        if (data is Map) {
          _speakerApprovedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('speaker_muted', (data) {
        if (data is Map) {
          _speakerMutedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('speaker_demoted', (data) {
        if (data is Map) {
          _speakerDemotedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('user_kicked', (data) {
        if (data is Map) {
          _userKickedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('host_changed', (data) {
        if (data is Map) {
          _hostChangedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('room_ended', (data) {
        if (data is Map) {
          _roomEndedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('user_presence_changed', (data) {
        if (data is Map) {
          _presenceChangeController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('followed_user_online', (data) {
        if (data is Map) {
          _followedUserOnlineController.add(Map<String, dynamic>.from(data));
        }
      });
    } catch (e) {
      debugPrint('[Socket] Init error: $e');
    }
  }

  void joinRoomChannel(String roomId, String userId) {
    _socket?.emit('join_room', {'roomId': roomId, 'userId': userId});
  }

  void leaveRoomChannel(String roomId, String userId) {
    _socket?.emit('leave_room', {'roomId': roomId, 'userId': userId});
  }

  void toggleSelfMute(String roomId, String userId, bool isMuted) {
    _socket?.emit('toggle_self_mute', {'roomId': roomId, 'userId': userId, 'isMuted': isMuted});
  }

  void _startHeartbeat(String userId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('heartbeat', {'userId': userId});
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void disconnect() {
    _stopHeartbeat();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
