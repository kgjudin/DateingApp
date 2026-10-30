import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/voice/agora_voice_service.dart';

class RoomState {
  final bool isLoading;
  final List<dynamic> liveRooms;
  final List<dynamic> groups;
  final Map<String, dynamic>? activeRoom;
  final String currentRole; // 'host', 'speaker', 'listener'
  final bool isHandRaised;
  final bool isMuted;
  final Map<String, dynamic>? liveGiftOverlay;
  final String? errorMessage;

  RoomState({
    this.isLoading = false,
    this.liveRooms = const [],
    this.groups = const [],
    this.activeRoom,
    this.currentRole = 'listener',
    this.isHandRaised = false,
    this.isMuted = true,
    this.liveGiftOverlay,
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
    Map<String, dynamic>? liveGiftOverlay,
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
      liveGiftOverlay: liveGiftOverlay,
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
  }

  Future<void> fetchRoomsAndGroups() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final roomsRes = await _ref.read(apiClientProvider).get('/rooms/live');
      final groupsRes = await _ref.read(apiClientProvider).get('/groups');

      state = state.copyWith(
        isLoading: false,
        liveRooms: (roomsRes is List ? roomsRes : []),
        groups: (groupsRes is List ? groupsRes : []),
      );
    } catch (e) {
      _loadMockRooms();
    }
  }

  Future<bool> joinLiveRoom(Map<String, dynamic> room) async {
    state = state.copyWith(isLoading: true, activeRoom: room, currentRole: 'listener', isMuted: true);
    final roomId = room['id'];

    try {
      final res = await _ref.read(apiClientProvider).post('/rooms/$roomId/join');
      final token = res?['token'] ?? '';
      final appId = res?['appId'] ?? 'test_agora_app_id_vybe';
      final role = res?['role'] ?? 'listener';

      _ref.read(socketServiceProvider).joinRoomChannel(roomId, 'user-elena-101');

      await _ref.read(agoraVoiceServiceProvider).joinVoiceChannel(
            appId: appId,
            channelId: room['channelName'] ?? 'vybe_room_$roomId',
            token: token,
            isPublisher: role == 'host' || role == 'speaker',
          );

      state = state.copyWith(isLoading: false, currentRole: role, isMuted: role == 'listener');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return true; // allow dev fallback
    }
  }

  Future<void> raiseHand() async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id'];

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/raise-hand');
      state = state.copyWith(isHandRaised: true);
    } catch (_) {
      state = state.copyWith(isHandRaised: true);
    }
  }

  Future<void> toggleMic() async {
    if (state.currentRole == 'listener') return;
    await _ref.read(agoraVoiceServiceProvider).toggleMute();
    state = state.copyWith(isMuted: _ref.read(agoraVoiceServiceProvider).isMuted);
  }

  Future<void> leaveActiveRoom() async {
    if (state.activeRoom == null) return;
    final roomId = state.activeRoom!['id'];

    try {
      await _ref.read(apiClientProvider).post('/rooms/$roomId/leave');
    } catch (_) {}

    _ref.read(socketServiceProvider).leaveRoomChannel(roomId, 'user-elena-101');
    await _ref.read(agoraVoiceServiceProvider).leaveChannel();

    state = state.copyWith(activeRoom: null, isHandRaised: false);
  }

  void _loadMockRooms() {
    final mockRooms = [
      {
        'id': 'room-live-101',
        'title': 'Late Night Chill & Lo-Fi Vinyl Talks ☕',
        'topic': 'Music & Memories',
        'groupName': 'Midnight Philosophers',
        'hostName': 'Elena Vance',
        'hostAvatar': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
        'listenersCount': 18,
        'speakersCount': 3,
        'channelName': 'vybe_room_night_owls',
        'speakers': [
          {'userId': 'user-elena-101', 'name': 'Elena Vance', 'role': 'host', 'isMuted': false, 'avatarUrl': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500'},
          {'userId': 'user-zane-104', 'name': 'Zane Parker', 'role': 'speaker', 'isMuted': false, 'avatarUrl': 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=500'},
          {'userId': 'user-sophia-103', 'name': 'Sophia Ray', 'role': 'speaker', 'isMuted': true, 'avatarUrl': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500'},
        ]
      },
      {
        'id': 'room-live-102',
        'title': 'Will AI Replace Social Media or Reinvent Voice?',
        'topic': 'AI & Social Futures',
        'groupName': 'Future & Tech Minds',
        'hostName': 'Marcus Chen',
        'hostAvatar': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
        'listenersCount': 42,
        'speakersCount': 2,
        'channelName': 'vybe_room_tech_minds',
        'speakers': [
          {'userId': 'user-marcus-102', 'name': 'Marcus Chen', 'role': 'host', 'isMuted': false, 'avatarUrl': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500'},
          {'userId': 'user-priya-105', 'name': 'Priya Sharma', 'role': 'speaker', 'isMuted': false, 'avatarUrl': 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500'},
        ]
      }
    ];

    state = state.copyWith(
      isLoading: false,
      liveRooms: mockRooms,
    );
  }

  @override
  void dispose() {
    _liveGiftSub?.cancel();
    _speakerListSub?.cancel();
    super.dispose();
  }
}
