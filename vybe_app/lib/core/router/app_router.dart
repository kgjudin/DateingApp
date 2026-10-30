import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/calling/presentation/screens/call_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/groups/presentation/screens/live_voice_room_screen.dart';
import '../../features/main_shell.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_builder_screen.dart';
import '../../features/profile/presentation/screens/profile_details_screen.dart';
import '../../features/wallet/presentation/screens/wallet_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: authState.isAuthenticated ? '/home' : '/onboarding',
    redirect: (context, state) {
      final isAuth = authState.isAuthenticated;
      final isAuthPath = state.matchedLocation == '/login' ||
          state.matchedLocation == '/onboarding' ||
          state.matchedLocation == '/profile-builder';

      // If not logged in and not on an auth screen, redirect to onboarding
      if (!isAuth && !isAuthPath) {
        return '/onboarding';
      }

      // If logged in and on an auth screen, redirect to home
      if (isAuth && isAuthPath) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/profile-builder',
        builder: (context, state) => const ProfileBuilderScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const MainNavigationShell(),
      ),
      GoRoute(
        path: '/calling',
        builder: (context, state) => const CallScreen(),
      ),
      GoRoute(
        path: '/room/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? 'room-live-101';
          return LiveVoiceRoomScreen(roomId: id);
        },
      ),
      GoRoute(
        path: '/profile/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return ProfileDetailsScreen(userId: id);
        },
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return ChatScreen(otherUserId: id, otherUserName: 'Marcus Chen');
        },
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
    ],
  );
});
