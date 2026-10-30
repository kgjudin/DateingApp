import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final Map<String, dynamic>? user;
  final String? errorMessage;
  final int coinBalance;

  AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.errorMessage,
    this.coinBalance = 100,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    Map<String, dynamic>? user,
    String? errorMessage,
    int? coinBalance,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      errorMessage: errorMessage,
      coinBalance: coinBalance ?? this.coinBalance,
    );
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});

class AuthController extends StateNotifier<AuthState> {
  final Ref _ref;

  AuthController(this._ref) : super(AuthState()) {
    checkSession();
  }

  Future<void> checkSession() async {
    state = state.copyWith(isLoading: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);
      final userId = prefs.getString(AppConstants.userIdKey) ?? 'user-elena-101';

      if (token != null) {
        _ref.read(apiClientProvider).setAuthToken(token);
        _ref.read(socketServiceProvider).connect(userId);

        final res = await _ref.read(apiClientProvider).get('/auth/me');
        if (res is Map && res['user'] != null) {
          final wallet = res['wallet'] as Map?;
          state = state.copyWith(
            isAuthenticated: true,
            isLoading: false,
            user: Map<String, dynamic>.from(res['user']),
            coinBalance: wallet?['balance'] ?? 100,
          );
          return;
        }
      }

      // Default demo login session for seamless initial experience
      await loginDemo('user-elena-101');
    } catch (e) {
      // In case backend is offline, start with demo state
      await loginDemo('user-elena-101');
    }
  }

  Future<bool> loginWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _ref.read(apiClientProvider).post('/auth/login', body: {
        'email': email,
        'password': password,
      });

      if (res is Map && res['token'] != null) {
        final token = res['token'] as String;
        final user = Map<String, dynamic>.from(res['user']);
        final wallet = res['wallet'] as Map?;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.tokenKey, token);
        await prefs.setString(AppConstants.userIdKey, user['id'] ?? 'user-elena-101');

        _ref.read(apiClientProvider).setAuthToken(token);
        _ref.read(socketServiceProvider).connect(user['id'] ?? 'user-elena-101');

        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          user: user,
          coinBalance: wallet?['balance'] ?? 100,
        );
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String displayName,
    required String gender,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _ref.read(apiClientProvider).post('/auth/register', body: {
        'username': username,
        'email': email,
        'password': password,
        'displayName': displayName,
        'gender': gender,
      });

      if (res is Map && res['token'] != null) {
        final token = res['token'] as String;
        final user = Map<String, dynamic>.from(res['user']);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.tokenKey, token);
        await prefs.setString(AppConstants.userIdKey, user['id']);

        _ref.read(apiClientProvider).setAuthToken(token);
        _ref.read(socketServiceProvider).connect(user['id']);

        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          user: user,
          coinBalance: 100,
        );
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<void> loginDemo(String userId) async {
    final devToken = 'dev_token_$userId';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.tokenKey, devToken);
    await prefs.setString(AppConstants.userIdKey, userId);

    _ref.read(apiClientProvider).setAuthToken(devToken);
    _ref.read(socketServiceProvider).connect(userId);

    // Initial demo profile
    state = state.copyWith(
      isAuthenticated: true,
      isLoading: false,
      user: {
        'id': userId,
        'username': 'elena_v',
        'displayName': 'Elena Vance',
        'age': 26,
        'gender': 'female',
        'location': 'Berlin, Germany',
        'bio': 'Podcaster & indie musician. Let us talk about travel, late-night acoustic guitar, and philosophy.',
        'avatarUrl': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500&auto=format&fit=crop&q=80',
        'coverUrl': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000&auto=format&fit=crop&q=80',
        'voiceIntroUrl': 'https://actions.google.com/sounds/v1/speech/female_voice.ogg',
        'voiceIntroDuration': 14,
        'interests': ['Music', 'Travelling', 'Art', 'Lifestyle'],
      },
      coinBalance: 400,
    );
  }

  void updateCoinBalance(int newBalance) {
    state = state.copyWith(coinBalance: newBalance);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userIdKey);
    _ref.read(apiClientProvider).setAuthToken(null);
    _ref.read(socketServiceProvider).disconnect();
    state = AuthState();
  }
}
