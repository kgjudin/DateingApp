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
      state = state.copyWith(
        isLoading: false,
        liveRooms: [],
        groups: [],
        errorMessage: e.toString(),
      );
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
      final currentUserId = _ref.read(authControllerProvider).user?['id'] ?? '';

      _ref.read(socketServiceProvider).joinRoomChannel(roomId, currentUserId);

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
      return false;
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

    final currentUserId = _ref.read(authControllerProvider).user?['id'] ?? '';
    _ref.read(socketServiceProvider).leaveRoomChannel(roomId, currentUserId);
    await _ref.read(agoraVoiceServiceProvider).leaveChannel();

    state = state.copyWith(activeRoom: null, isHandRaised: false);
  }

  @override
  void dispose() {
    _liveGiftSub?.cancel();
    _speakerListSub?.cancel();
    super.dispose();
  }
}
