import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../auth/presentation/auth_controller.dart';

/// Helper function to match profile gender against the selected filter.
bool matchesGenderFilter(dynamic rawGender, String filter) {
  final f = filter.toLowerCase().trim();
  if (f.isEmpty || f == 'everyone' || f == 'all') {
    return true;
  }
  if (rawGender == null) return false;
  final g = rawGender.toString().toLowerCase().trim();
  if (f == 'women' || f == 'female' || f == 'woman') {
    return g == 'female' || g == 'women' || g == 'woman';
  }
  if (f == 'men' || f == 'male' || f == 'man') {
    return g == 'male' || g == 'men' || g == 'man';
  }
  if (f == 'non_binary' || f == 'non-binary' || f == 'other') {
    return g == 'non_binary' || g == 'non-binary' || g == 'other';
  }
  return g == f;
}

class DiscoveryState {
  final bool isLoading;
  final List<dynamic> onlineNow;
  final List<dynamic> basedOnInterests;
  final List<dynamic> peopleYouMayLike;
  final List<dynamic> newPeople;
  final String selectedGenderFilter; // 'everyone', 'women', 'men', 'non_binary'
  final String? selectedInterestFilter;
  final String? errorMessage;

  DiscoveryState({
    this.isLoading = false,
    this.onlineNow = const [],
    this.basedOnInterests = const [],
    this.peopleYouMayLike = const [],
    this.newPeople = const [],
    this.selectedGenderFilter = 'everyone',
    this.selectedInterestFilter,
    this.errorMessage,
  });

  /// Real-time filtered online users matching the currently selected gender filter
  List<dynamic> get filteredOnlineNow =>
      onlineNow.where((u) => matchesGenderFilter(u is Map ? u['gender'] : null, selectedGenderFilter)).toList();

  /// Real-time filtered users based on interests matching the selected gender filter
  List<dynamic> get filteredBasedOnInterests =>
      basedOnInterests.where((u) => matchesGenderFilter(u is Map ? u['gender'] : null, selectedGenderFilter)).toList();

  /// Real-time filtered people you may like matching the selected gender filter
  List<dynamic> get filteredPeopleYouMayLike =>
      peopleYouMayLike.where((u) => matchesGenderFilter(u is Map ? u['gender'] : null, selectedGenderFilter)).toList();

  DiscoveryState copyWith({
    bool? isLoading,
    List<dynamic>? onlineNow,
    List<dynamic>? basedOnInterests,
    List<dynamic>? peopleYouMayLike,
    List<dynamic>? newPeople,
    String? selectedGenderFilter,
    String? selectedInterestFilter,
    String? errorMessage,
  }) {
    return DiscoveryState(
      isLoading: isLoading ?? this.isLoading,
      onlineNow: onlineNow ?? this.onlineNow,
      basedOnInterests: basedOnInterests ?? this.basedOnInterests,
      peopleYouMayLike: peopleYouMayLike ?? this.peopleYouMayLike,
      newPeople: newPeople ?? this.newPeople,
      selectedGenderFilter: selectedGenderFilter ?? this.selectedGenderFilter,
      selectedInterestFilter: selectedInterestFilter ?? this.selectedInterestFilter,
      errorMessage: errorMessage,
    );
  }
}

final discoveryControllerProvider = StateNotifierProvider<DiscoveryController, DiscoveryState>((ref) {
  return DiscoveryController(ref);
});

class DiscoveryController extends StateNotifier<DiscoveryState> {
  final Ref _ref;
  StreamSubscription? _presenceSub;

  DiscoveryController(this._ref) : super(DiscoveryState()) {
    fetchFeed();
    _listenToPresence();
  }

  void _listenToPresence() {
    _presenceSub?.cancel();
    _presenceSub = _ref.read(socketServiceProvider).onPresenceChanged.listen((data) {
      final userId = data['userId'] as String?;
      final status = data['status'] as String?;
      if (userId == null || status == null) return;

      _handlePresenceUpdate(userId, status);
    });
  }

  void _handlePresenceUpdate(String userId, String status) {
    final currentOnline = List<dynamic>.from(state.onlineNow);
    final currentInterests = List<dynamic>.from(state.basedOnInterests);
    final currentMayLike = List<dynamic>.from(state.peopleYouMayLike);
    final currentNew = List<dynamic>.from(state.newPeople);

    final uId = userId.toLowerCase();
    final isUserNowOnline = status == 'online' || status == 'in_call' || status == 'in_room';

    // Update status in all feed lists
    dynamic targetUser;
    for (int i = 0; i < currentNew.length; i++) {
      if (currentNew[i] is Map && currentNew[i]['id']?.toString().toLowerCase() == uId) {
        currentNew[i] = Map<String, dynamic>.from(currentNew[i])
          ..['status'] = status
          ..['isOnline'] = isUserNowOnline;
        targetUser = currentNew[i];
      }
    }
    for (int i = 0; i < currentInterests.length; i++) {
      if (currentInterests[i] is Map && currentInterests[i]['id']?.toString().toLowerCase() == uId) {
        currentInterests[i] = Map<String, dynamic>.from(currentInterests[i])
          ..['status'] = status
          ..['isOnline'] = isUserNowOnline;
        targetUser ??= currentInterests[i];
      }
    }
    for (int i = 0; i < currentMayLike.length; i++) {
      if (currentMayLike[i] is Map && currentMayLike[i]['id']?.toString().toLowerCase() == uId) {
        currentMayLike[i] = Map<String, dynamic>.from(currentMayLike[i])
          ..['status'] = status
          ..['isOnline'] = isUserNowOnline;
        targetUser ??= currentMayLike[i];
      }
    }

    if (isUserNowOnline) {
      final existsInOnline = currentOnline.any((u) => u is Map && u['id']?.toString().toLowerCase() == uId);
      if (!existsInOnline && targetUser != null) {
        currentOnline.insert(0, targetUser);
      } else if (!existsInOnline && targetUser == null) {
        // Unknown user came online: refresh feed to fetch their profile into cache
        fetchFeed();
        return;
      }
    } else {
      currentOnline.removeWhere((u) => u is Map && u['id']?.toString().toLowerCase() == uId);
    }

    state = state.copyWith(
      onlineNow: currentOnline,
      basedOnInterests: currentInterests,
      peopleYouMayLike: currentMayLike,
      newPeople: currentNew,
    );
  }

  Future<void> fetchFeed({String? gender}) async {
    final auth = _ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      state = state.copyWith(
        isLoading: false,
        onlineNow: [],
        basedOnInterests: [],
        peopleYouMayLike: [],
        newPeople: [],
      );
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final g = gender ?? state.selectedGenderFilter;
      final queryParam = (g.isNotEmpty && g != 'everyone') ? '?gender=$g' : '';
      final res = await _ref.read(apiClientProvider).get('/discovery/feed$queryParam');
      if (res is Map) {
        state = state.copyWith(
          isLoading: false,
          onlineNow: (res['onlineNow'] as List?) ?? [],
          basedOnInterests: (res['basedOnInterests'] as List?) ?? [],
          peopleYouMayLike: (res['peopleYouMayLike'] as List?) ?? [],
          newPeople: (res['newPeople'] as List?) ?? [],
        );
        return;
      }
      state = state.copyWith(
        isLoading: false,
        onlineNow: [],
        basedOnInterests: [],
        peopleYouMayLike: [],
        newPeople: [],
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void setGenderFilter(String gender) {
    state = state.copyWith(selectedGenderFilter: gender);
    fetchFeed(gender: gender);
  }

  void setInterestFilter(String? interest) {
    state = state.copyWith(
      selectedInterestFilter: state.selectedInterestFilter == interest ? null : interest,
    );
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    super.dispose();
  }
}
