import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/network/socket_service.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/custom_bottom_nav.dart';
import 'calling/presentation/calling_controller.dart';
import 'calling/presentation/screens/calls_history_screen.dart';
import 'calling/presentation/widgets/incoming_call_dialog.dart';
import 'discovery/presentation/screens/discovery_screen.dart';
import 'favourites/presentation/screens/favourites_screen.dart';
import 'groups/presentation/screens/rooms_screen.dart';
import 'profile/presentation/screens/profile_screen.dart';

class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key});

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DiscoveryScreen(),
    RoomsScreen(),
    CallsHistoryScreen(),
    FavouritesScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _listenForIncomingCalls();
  }

  void _listenForIncomingCalls() {
    final socket = ref.read(socketServiceProvider);
    socket.onIncomingCall.listen((data) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => IncomingCallDialog(
            caller: (data['caller'] as Map?) != null
                ? Map<String, dynamic>.from(data['caller'])
                : {'displayName': 'Vybe Caller', 'location': 'Voice Connection'},
            onAccept: () {
              Navigator.pop(ctx);
              ref.read(callingControllerProvider.notifier).acceptCall(
                    callId: data['callId'] ?? '',
                    channelName: data['channelName'] ?? '',
                    token: data['token'] ?? '',
                    appId: data['appId'] ?? '',
                    callerProfile: Map<String, dynamic>.from(data['caller'] ?? {}),
                  );
              if (mounted) {
                context.push('/calling');
              }
            },
            onDecline: () {
              Navigator.pop(ctx);
              ref.read(callingControllerProvider.notifier).endCall();
            },
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomBottomNav(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
            ),
          ),
        ],
      ),
    );
  }
}
