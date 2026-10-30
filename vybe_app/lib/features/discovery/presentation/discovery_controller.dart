import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

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

  DiscoveryController(this._ref) : super(DiscoveryState()) {
    fetchFeed();
  }

  Future<void> fetchFeed() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _ref.read(apiClientProvider).get('/discovery/feed');
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
        onlineNow: [],
        basedOnInterests: [],
        peopleYouMayLike: [],
        newPeople: [],
        errorMessage: e.toString(),
      );
    }
  }

  void setGenderFilter(String gender) {
    state = state.copyWith(selectedGenderFilter: gender);
  }

  void setInterestFilter(String? interest) {
    state = state.copyWith(
      selectedInterestFilter: state.selectedInterestFilter == interest ? null : interest,
    );
  }
}
