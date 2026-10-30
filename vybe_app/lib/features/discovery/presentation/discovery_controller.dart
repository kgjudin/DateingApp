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
      _loadFallbackMock();
    } catch (e) {
      _loadFallbackMock();
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

  void _loadFallbackMock() {
    final mockUsers = [
      {
        'id': 'user-marcus-102',
        'displayName': 'Marcus Chen',
        'username': 'marcus_code',
        'age': 28,
        'gender': 'male',
        'location': 'San Francisco, USA',
        'bio': 'AI researcher and late-night gamer. Always up for thought-provoking debates about tech.',
        'avatarUrl': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500&auto=format&fit=crop&q=80',
        'coverUrl': 'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=1000&auto=format&fit=crop&q=80',
        'voiceIntroUrl': 'https://actions.google.com/sounds/v1/speech/male_voice.ogg',
        'voiceIntroDuration': 18,
        'interests': ['Technology', 'Gaming', 'Books', 'Business'],
        'status': 'online',
        'sharedInterests': ['Technology', 'Books'],
        'isFavourite': false,
      },
      {
        'id': 'user-sophia-103',
        'displayName': 'Sophia Ray',
        'username': 'sophia_beats',
        'age': 24,
        'gender': 'female',
        'location': 'London, UK',
        'bio': 'Coffee enthusiast, vinyl collector, and documentary filmmaker. Tell me your wildest life story!',
        'avatarUrl': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500&auto=format&fit=crop&q=80',
        'coverUrl': 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=1000&auto=format&fit=crop&q=80',
        'voiceIntroUrl': 'https://actions.google.com/sounds/v1/speech/female_voice.ogg',
        'voiceIntroDuration': 21,
        'interests': ['Movies', 'Food', 'Culture', 'Photography'],
        'status': 'online',
        'sharedInterests': ['Movies', 'Photography'],
        'isFavourite': false,
      },
      {
        'id': 'user-zane-104',
        'displayName': 'Zane Parker',
        'username': 'zane_vibes',
        'age': 29,
        'gender': 'non_binary',
        'location': 'Melbourne, Australia',
        'bio': 'Sound designer & deep conversation seeker. Let’s talk about consciousness and space.',
        'avatarUrl': 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=500&auto=format&fit=crop&q=80',
        'coverUrl': 'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=1000&auto=format&fit=crop&q=80',
        'voiceIntroUrl': 'https://actions.google.com/sounds/v1/speech/male_voice.ogg',
        'voiceIntroDuration': 12,
        'interests': ['Technology', 'Nature', 'Music', 'Fitness'],
        'status': 'online',
        'sharedInterests': ['Music', 'Technology'],
        'isFavourite': false,
      },
      {
        'id': 'user-priya-105',
        'displayName': 'Priya Sharma',
        'username': 'priya_talks',
        'age': 25,
        'gender': 'female',
        'location': 'Mumbai, India',
        'bio': 'Stand-up comedy writer & travel photographer. Voice chats are way more real than endless texting.',
        'avatarUrl': 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500&auto=format&fit=crop&q=80',
        'coverUrl': 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=1000&auto=format&fit=crop&q=80',
        'voiceIntroUrl': 'https://actions.google.com/sounds/v1/speech/female_voice.ogg',
        'voiceIntroDuration': 16,
        'interests': ['Entertainment', 'Travelling', 'Food', 'Culture'],
        'status': 'online',
        'sharedInterests': ['Travelling', 'Food'],
        'isFavourite': true,
      }
    ];

    state = state.copyWith(
      isLoading: false,
      onlineNow: mockUsers,
      basedOnInterests: mockUsers,
      peopleYouMayLike: mockUsers.reversed.toList(),
      newPeople: mockUsers,
    );
  }
}
