import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/voice/agora_voice_service.dart';
import '../../auth/presentation/auth_controller.dart';

class RoomState {
  final bool isLoading;
  final List<dynamic> liveRooms;
  final List<dynamic> groups;
  final Map<String, dynamic>? activeRoom;
  final String currentRole; // 'host', 'subhost', 'speaker', 'listener'
  final bool isHandRaised;
  final bool isMuted;
  final List<dynamic> speakerRequests;
  final Map<String, dynamic>? pendingInvitation;
  final Map<String, dynamic>? liveGiftOverlay;
  final String? kickedMessage;
  final String? hostNoticeMessage;
  final String? errorMessage;

  RoomState({
    this.isLoading = false,
    this.liveRooms = const [],
    this.groups = const [],
    this.activeRoom,
    this.currentRole = 'listener',
    this.isHandRaised = false,
    this.isMuted = true,
    this.speakerRequests = const [],
    this.pendingInvitation,
    this.liveGiftOverlay,
    this.kickedMessage,
    this.hostNoticeMessage,
    this.errorMessage,
  });

  RoomState copyWith({
    bool? isLoading,
    List<dynamic>? liveRooms,
    List<dynamic>? groups,
    Map<String, dynamic>? activeRoom,
    String? currentRole,
    bool? isHandRaised,
    bool? isMuted,
    List<dynamic>? speakerRequests,
    Map<String, dynamic>? pendingInvitation,
    bool clearPendingInvitation = false,
    Map<String, dynamic>? liveGiftOverlay,
    String? kickedMessage,
    String? hostNoticeMessage,
    String? errorMessage,
  }) {
    return RoomState(
      isLoading: isLoading ?? this.isLoading,
      liveRooms: liveRooms ?? this.liveRooms,
      groups: groups ?? this.groups,
      activeRoom: activeRoom ?? this.activeRoom,
      currentRole: currentRole ?? this.currentRole,
      isHandRaised: isHandRaised ?? this.isHandRaised,
      isMuted: isMuted ?? this.isMuted,
      speakerRequests: speakerRequests ?? this.speakerRequests,
      pendingInvitation: clearPendingInvitation ? null : (pendingInvitation ?? this.pendingInvitation),
      liveGiftOverlay: liveGiftOverlay,
      kickedMessage: kickedMessage,
      hostNoticeMessage: hostNoticeMessage,
      errorMessage: errorMessage,
    );
  }
}

final roomsControllerProvider = StateNotifierProvider<RoomsController, RoomState>((ref) {
  return RoomsController(ref);
});

class RoomsController extends StateNotifier<RoomState> {
  final Ref _ref;
  StreamSubscription? _liveGiftSub;
  StreamSubscription? _speakerListSub;
  StreamSubscription? _roomUpdatedSub;
  StreamSubscription? _speakerRequestsSub;
  StreamSubscription? _invitationSub;
  StreamSubscription? _speakerApprovedSub;
  StreamSubscription? _speakerMutedSub;
  StreamSubscription? _userKickedSub;
  StreamSubscription? _hostChangedSub;
  StreamSubscription? _roomEndedSub;

  RoomsController(this._ref) : super(RoomState()) {
    fetchRoomsAndGroups();
    _listenSocketEvents();
  }

  void _listenSocketEvents() {
    final socket = _ref.read(socketServiceProvider);

    _liveGiftSub = socket.onLiveGift.listen((giftData) {
      state = state.copyWith(liveGiftOverlay: giftData);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) state = state.copyWith(liveGiftOverlay: null);
      });
    });

    _speakerListSub = socket.onRoomSpeakerUpdated.listen((data) {
      if (state.activeRoom != null && data['speakers'] is List) {
        final updatedRoom = Map<String, dynamic>.from(state.activeRoom!);
        updatedRoom['speakers'] = data['speakers'];
        state = state.copyWith(activeRoom: updatedRoom);
      }
    });

    _roomUpdatedSub = socket.onRoomUpdated.listen((data) {
      if (state.activeRoom != null) {
        final updatedRoom = Map<String, dynamic>.from(state.activeRoom!);
        if (data['speakers'] is List) updatedRoom['speakers'] = data['speakers'];
        if (data['listeners'] is List) updatedRoom['listeners'] = data['listeners'];
        if (data['listenersCount'] != null) updatedRoom['listenersCount'] = data['listenersCount'];
        if (data['speakersCount'] != null) updatedRoom['speakersCount'] = data['speakersCount'];
        if (data['hostId'] != null) updatedRoom['hostId'] = data['hostId'];
        if (data['subHostId'] != null) updatedRoom['subHostId'] = data['subHostId'];

        final currentUserId = _ref.read(authControllerProvider).user?['id']?.toString() ?? '';
        String role = state.currentRole;
        if (updatedRoom['hostId'] == currentUserId) {
          role = 'host';
        } else if (updatedRoom['subHostId'] == currentUserId) {
          role = 'subhost';
        } else if ((updatedRoom['speakers'] as List? ?? []).any((s) => s['userId']?.toString() == currentUserId)) {
          role = 'speaker';
        }

        final requests = data['speakerRequests'] is List ? (data['speakerRequests'] as List) : state.speakerRequests;

        state = state.copyWith(
          activeRoom: updatedRoom,
          currentRole: role,
          speakerRequests: requests,
        );
      }
    });

    _speakerRequestsSub = socket.onSpeakerRequestsUpdated.listen((data) {
      if (data['requests'] is List) {
        state = state.copyWith(speakerRequests: List<dynamic>.from(data['requests']));
      }
    });

    _invitationSub = socket.onRoomInvitationToSpeak.listen((data) {
      state = state.copyWith(pendingInvitation: data);
    });

    _speakerApprovedSub = socket.onSpeakerApproved.listen((data) async {
      // Current user was approved to speak
      final token = data['token'] ?? '';
      final appId = data['appId'] ?? 'test_agora_app_id_vybe';
      final roomId = state.activeRoom?['id'] ?? '';

      await _ref.read(agoraVoiceServiceProvider).joinVoiceChannel(
            appId: appId,
            channelId: state.activeRoom?['channelName'] ?? 'vybe_room_$roomId',
            token: token,
            isPublisher: true,
          );

      await _ref.read(agoraVoiceServiceProvider).setMuted(false);
      state = state.copyWith(
        currentRole: 'speaker',
        isMuted: false,
        isHandRaised: false,
        clearPendingInvitation: true,
      );
    });

    _speakerMutedSub = socket.onSpeakerMuted.listen((data) async {
      final isMuted = data['isMuted'] == true;
      await _ref.read(agoraVoiceServiceProvider).setMuted(isMuted);
      state = state.copyWith(isMuted: isMuted);
    });

    _userKickedSub = socket.onUserKicked.listen((data) async {
      final reason = data['reason']?.toString() ?? 'You have been removed from the room by the host.';
      await leaveActiveRoom();
      state = state.copyWith(kickedMessage: reason);
    });

    _hostChangedSub = socket.onHostChanged.listen((data) {
      final msg = data['message']?.toString() ?? 'Host has changed.';
      state = state.copyWith(hostNoticeMessage: msg);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) state = state.copyWith(hostNoticeMessage: null);
      });
    });

    _roomEndedSub = socket.onRoomEnded.listen((data) async {
      await leaveActiveRoom();
      state = state.copyWith(hostNoticeMessage: 'The room has ended.');
      fetchRoomsAndGroups();
    });
  }

  void clearKickedMessage() {
    state = state.copyWith(kickedMessage: null);
  }

  void clearHostNotice() {
    state = state.copyWith(hostNoticeMessage: null);
  }

  Future<void> fetchRoomsAndGroups() async {
    final auth = _ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      state = state.copyWith(isLoading: false, liveRooms: [], groups: []);
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final roomsRes = await _ref.read(apiClientProvider).get('/rooms/live');
      final groupsRes = await _ref.read(apiClientProvider).get('/groups');

      // Deduplicate live rooms by id
      final seen = <String>{};
      final uniqueRooms = <dynamic>[];
      if (roomsRes is List) {
        for (final r in roomsRes) {
          final id = r['id']?.toString() ?? '';
          if (id.isNotEmpty && !seen.contains(id)) {
            seen.add(id);
            uniqueRooms.add(r);
          }
        }
      }

      state = state.copyWith(
        isLoading: false,
        liveRooms: uniqueRooms,
        groups: (groupsRes is List ? groupsRes : []),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        liveRooms: [],
        groups: [],
        errorMessage: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>?> createRoom({
    required String title,
    required String topic,
    String? groupId,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _ref.read(apiClientProvider).post('/rooms/create', body: {
        'title': title,
        'topic': topic,
        if (groupId != null) 'groupId': groupId,
      });

      if (res is Map) {
        final roomData = Map<String, dynamic>.from(res);
        final roomId = roomData['id'] ?? 'room_${DateTime.now().millisecondsSinceEpoch}';
        final token = roomData['token'] ?? '';
        final appId = roomData['appId'] ?? 'test_agora_app_id_vybe';
        final currentUserId = _ref.read(authControllerProvider).user?['id']?.toString() ?? '';

        _ref.read(socketServiceProvider).joinRoomChannel(roomId, currentUserId);

        await _ref.read(agoraVoiceServiceProvider).joinVoiceChannel(
              appId: appId,
              channelId: roomData['channelName'] ?? 'vybe_room_$roomId',
              token: token,
              isPublisher: true,
            );

        await _ref.read(agoraVoiceServiceProvider).setMuted(false);

        // Deduplicate in liveRooms list
        final seen = <String>{roomId.toString()};
        final updatedRooms = <dynamic>[roomData];
        for (final r in state.liveRooms) {
          final rId = r['id']?.toString() ?? '';
          if (rId.isNotEmpty && !seen.contains(rId)) {
            seen.add(rId);
            updatedRooms.add(r);
          }
        }

        state = state.copyWith(
          isLoading: false,
          activeRoom: roomData,
          currentRole: 'host',
          isMuted: false,
          isHandRaised: false,
          liveRooms: updatedRooms,
          speakerRequests: [],
        );
        return roomData;
      }
      state = state.copyWith(isLoading: false);
      return null;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<bool> joinLiveRoom(Map<String, dynamic> room) async {
    state = state.copyWith(isLoading: true, activeRoom: room, currentRole: 'listener', isMuted: true);
    final roomId = room['id']?.toString() ?? '';

    try {
      final res = await _ref.read(apiClientProvider).post('/rooms/$roomId/join');
      final token = res?['token'] ?? '';
      final appId = res?['appId'] ?? 'test_agora_app_id_vybe';
      final role = res?['role'] ?? 'listener';
      final currentUserId = _ref.read(authControllerProvider).user?['id']?.toString() ?? '';

      _ref.read(socketServiceProvider).joinRoomChannel(roomId, currentUserId);

      final isPublisher = role == 'host' || role == 'subhost' || role == 'speaker';
      await _ref.read(agoraVoiceServiceProvider).joinVoiceChannel(
            appId: appId,
            channelId: room['channelName'] ?? 'vybe_room_$roomId',
            token: token,
            isPublisher: isPublisher,
          );

      if (!isPublisher) {
        await _ref.read(agoraVoiceServiceProvider).setMuted(true);
      }

      final requests = res?['speakerRequests'] is List ? (res!['speakerRequests'] as List) : [];

      state = state.copyWith(
        isLoading: false,
        activeRoom: res is Map ? Map<String, dynamic>.from(res) : room,
        currentRole: role,
        isMuted: !isPublisher,
        speakerRequests: requests,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<void> raiseHand() async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/raise-hand');
      state = state.copyWith(isHandRaised: true);
    } catch (_) {
      state = state.copyWith(isHandRaised: true);
    }
  }

  Future<void> lowerHand([String? targetUserId]) async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/lower-hand', body: {
        if (targetUserId != null) 'targetUserId': targetUserId,
      });
      if (targetUserId == null) {
        state = state.copyWith(isHandRaised: false);
      }
    } catch (_) {
      if (targetUserId == null) {
        state = state.copyWith(isHandRaised: false);
      }
    }
  }

  Future<void> approveSpeaker(String targetUserId) async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/approve-speaker', body: {
        'targetUserId': targetUserId,
      });
      final updatedReqs = state.speakerRequests.where((r) => r['userId']?.toString() != targetUserId).toList();
      state = state.copyWith(speakerRequests: updatedReqs);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> inviteToSpeak(String targetUserId) async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/invite-to-speak', body: {
        'targetUserId': targetUserId,
      });
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> acceptSpeakerInvitation() async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      final res = await _ref.read(apiClientProvider).post('/rooms/$roomId/accept-invitation');
      state = state.copyWith(
        clearPendingInvitation: true,
        currentRole: 'speaker',
        isMuted: false,
        isHandRaised: false,
        activeRoom: res is Map ? Map<String, dynamic>.from(res) : state.activeRoom,
      );
      await _ref.read(agoraVoiceServiceProvider).setMuted(false);
    } catch (_) {
      state = state.copyWith(clearPendingInvitation: true);
    }
  }

  void declineSpeakerInvitation() {
    state = state.copyWith(clearPendingInvitation: true);
  }

  Future<void> muteSpeaker(String targetUserId, {bool isMuted = true}) async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/mute-speaker', body: {
        'targetUserId': targetUserId,
        'isMuted': isMuted,
      });
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> demoteSpeaker(String targetUserId) async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/demote-speaker', body: {
        'targetUserId': targetUserId,
      });
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> kickUser(String targetUserId) async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/kick-user', body: {
        'targetUserId': targetUserId,
      });
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> makeSubHost(String targetUserId) async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/make-subhost', body: {
        'targetUserId': targetUserId,
      });
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> toggleMic() async {
    if (state.currentRole == 'listener') return;
    await _ref.read(agoraVoiceServiceProvider).toggleMute();
    state = state.copyWith(isMuted: _ref.read(agoraVoiceServiceProvider).isMuted);
  }

  Future<void> leaveActiveRoom({String? newSubHostId, bool endRoomForEveryone = false}) async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id']?.toString() ?? '';

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/leave', body: {
        if (newSubHostId != null) 'newSubHostId': newSubHostId,
        'endRoomForEveryone': endRoomForEveryone,
      });
    } catch (_) {}

    final currentUserId = _ref.read(authControllerProvider).user?['id']?.toString() ?? '';
    _ref.read(socketServiceProvider).leaveRoomChannel(roomId, currentUserId);
    await _ref.read(agoraVoiceServiceProvider).leaveChannel();

    state = state.copyWith(
      activeRoom: null,
      isHandRaised: false,
      currentRole: 'listener',
      isMuted: true,
      speakerRequests: [],
      clearPendingInvitation: true,
    );

    // Refresh rooms list
    fetchRoomsAndGroups();
  }

  @override
  void dispose() {
    _liveGiftSub?.cancel();
    _speakerListSub?.cancel();
    _roomUpdatedSub?.cancel();
    _speakerRequestsSub?.cancel();
    _invitationSub?.cancel();
    _speakerApprovedSub?.cancel();
    _speakerMutedSub?.cancel();
    _userKickedSub?.cancel();
    _hostChangedSub?.cancel();
    _roomEndedSub?.cancel();
    super.dispose();
  }
}
