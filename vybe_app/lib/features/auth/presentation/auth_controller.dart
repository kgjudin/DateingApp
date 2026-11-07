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
    this.coinBalance = 0,
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

  AuthController(this._ref) : super(AuthState(isLoading: true)) {
    checkSession();
  }

  Future<void> checkSession() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);
      final userId = prefs.getString(AppConstants.userIdKey);

      if (token != null && userId != null) {
        _ref.read(apiClientProvider).setAuthToken(token);
        _ref.read(socketServiceProvider).connect(userId);

        try {
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
        } catch (_) {
          // Token expired or invalid
          await prefs.remove(AppConstants.tokenKey);
          await prefs.remove(AppConstants.userIdKey);
        }
      }

      // Not authenticated by default - user must log in or sign up
      state = AuthState(isAuthenticated: false, isLoading: false);
    } catch (e) {
      state = AuthState(isAuthenticated: false, isLoading: false);
    }
  }

  Future<bool> loginWithEmail(String email, String password) async {
    final cleanEmail = email.trim();
    final cleanPass = password.trim();

    if (cleanEmail.isEmpty || cleanPass.isEmpty) {
      state = state.copyWith(isLoading: false, errorMessage: 'Please enter both email and password.');
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _ref.read(apiClientProvider).post('/auth/login', body: {
        'email': cleanEmail,
        'password': cleanPass,
      });

      if (res is Map && res['token'] != null) {
        final token = res['token'] as String;
        final user = Map<String, dynamic>.from(res['user']);
        final wallet = res['wallet'] as Map?;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.tokenKey, token);
        await prefs.setString(AppConstants.userIdKey, user['id']);

        _ref.read(apiClientProvider).setAuthToken(token);
        _ref.read(socketServiceProvider).connect(user['id']);

        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          user: user,
          coinBalance: wallet?['balance'] ?? 100,
          errorMessage: null,
        );
        return true;
      }

      state = state.copyWith(isLoading: false, errorMessage: 'Invalid response from server.');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String username,
    required String displayName,
    required String gender,
    String? location,
    String? bio,
    List<String>? interests,
    String? voiceIntroUrl,
    int? voiceIntroDuration,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPass = password.trim();
    final cleanUsername = username.trim().toLowerCase();

    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      state = state.copyWith(isLoading: false, errorMessage: 'Please enter a valid email address.');
      return false;
    }

    if (cleanUsername.isEmpty || cleanUsername.length < 3) {
      state = state.copyWith(isLoading: false, errorMessage: 'Username must be at least 3 characters.');
      return false;
    }

    if (cleanPass.length < 6) {
      state = state.copyWith(isLoading: false, errorMessage: 'Password must be at least 6 characters long.');
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _ref.read(apiClientProvider).post('/auth/register', body: {
        'email': cleanEmail,
        'password': cleanPass,
        'username': cleanUsername,
        'displayName': displayName.trim().isEmpty ? cleanUsername : displayName.trim(),
        'gender': gender,
        'location': location?.trim() ?? 'Online',
        'bio': bio?.trim() ?? 'Voice enthusiast on VYBE',
        'interests': interests ?? ['Music', 'Travelling'],
        'voiceIntroUrl': voiceIntroUrl,
        'voiceIntroDuration': voiceIntroDuration ?? 0,
      });

      if (res is Map && res['token'] != null) {
        final token = res['token'] as String;
        final user = Map<String, dynamic>.from(res['user']);
        final wallet = res['wallet'] as Map?;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.tokenKey, token);
        await prefs.setString(AppConstants.userIdKey, user['id']);

        _ref.read(apiClientProvider).setAuthToken(token);
        _ref.read(socketServiceProvider).connect(user['id']);

        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          user: user,
          coinBalance: wallet?['balance'] ?? 100,
          errorMessage: null,
        );
        return true;
      }

      state = state.copyWith(isLoading: false, errorMessage: 'Registration failed.');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  void updateCoinBalance(int newBalance) {
    state = state.copyWith(coinBalance: newBalance);
  }

  Future<void> logout() async {
    try {
      await _ref.read(apiClientProvider).post('/auth/logout');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userIdKey);
    _ref.read(apiClientProvider).setAuthToken(null);
    _ref.read(socketServiceProvider).disconnect();
    state = AuthState(isAuthenticated: false, isLoading: false);
  }
}
