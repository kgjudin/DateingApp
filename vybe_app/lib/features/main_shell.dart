import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/network/socket_service.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/custom_bottom_nav.dart';
import 'auth/presentation/auth_controller.dart';
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
    _listenForFollowedUsersOnline();
    _listenForNewFollowers();
    _listenForGiftReceived();
    _listenForWalletUpdates();
  }

  void _listenForGiftReceived() {
    final socket = ref.read(socketServiceProvider);
    socket.onGiftReceived.listen((data) {
      if (!mounted) return;

      final myId = ref.read(authControllerProvider).user?['id'];
      final receiverId = data['receiverId'];

      // Only handle if gift was intended for this user or sent to room
      if (receiverId != null && myId != null && receiverId != myId) return;

      final senderName = data['senderName'] ?? 'A friend';
      final giftName = data['giftName'] ?? 'Virtual Gift';
      final emoji = data['emoji'] ?? '🎁';
      final coinAmount = data['coinAmount'] ?? 0;

      // Immediately update local Riverpod coin balance
      if (data['receiverNewBalance'] != null) {
        ref.read(authControllerProvider.notifier).updateCoinBalance(data['receiverNewBalance'] as int);
      } else {
        final current = ref.read(authControllerProvider).coinBalance;
        ref.read(authControllerProvider.notifier).updateCoinBalance(current + (coinAmount as int));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.secondaryBackground,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
          ),
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gift Received from $senderName! 🎁',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$giftName • +$coinAmount Coins added to wallet',
                      style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'WALLET',
            textColor: AppColors.primaryAccentLight,
            onPressed: () => context.push('/wallet'),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    });
  }

  void _listenForWalletUpdates() {
    final socket = ref.read(socketServiceProvider);
    socket.onWalletUpdated.listen((data) {
      if (mounted && data['balance'] != null) {
        ref.read(authControllerProvider.notifier).updateCoinBalance(data['balance'] as int);
      }
    });
  }

  void _listenForFollowedUsersOnline() {
    final socket = ref.read(socketServiceProvider);
    socket.onFollowedUserOnline.listen((data) {
      if (mounted) {
        final name = data['displayName'] ?? 'A friend you follow';
        final userId = data['userId'];

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.secondaryBackground,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.primaryAccent),
            ),
            content: Row(
              children: [
                const Icon(Icons.circle, color: AppColors.online, size: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$name is online now! Ready to talk.',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'CALL',
              textColor: AppColors.primaryAccentLight,
              onPressed: () {
                if (userId != null) {
                  ref.read(callingControllerProvider.notifier).startCall(
                        receiverId: userId,
                        receiverProfile: {
                          'id': userId,
                          'displayName': name,
                          'avatarUrl': data['avatarUrl'],
                        },
                      );
                  context.push('/calling');
                }
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  void _listenForNewFollowers() {
    // Follow notifications are shown exclusively in the Notifications Screen (bell icon at top)
    // as requested by the user, without any bottom popup interrupting the user.
  }

  BuildContext? _incomingCallDialogContext;

  void _listenForIncomingCalls() {
    final socket = ref.read(socketServiceProvider);

    socket.onCallEnded.listen((_) {
      if (_incomingCallDialogContext != null && mounted) {
        try {
          Navigator.of(_incomingCallDialogContext!).pop();
        } catch (_) {}
        _incomingCallDialogContext = null;
      }
    });

    socket.onIncomingCall.listen((data) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            _incomingCallDialogContext = ctx;
            return IncomingCallDialog(
              caller: (data['caller'] as Map?) != null
                  ? Map<String, dynamic>.from(data['caller'])
                  : {'displayName': 'Vybe Caller', 'location': 'Voice Connection'},
              onAccept: () {
                _incomingCallDialogContext = null;
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
                _incomingCallDialogContext = null;
                Navigator.pop(ctx);
                ref.read(callingControllerProvider.notifier).declineCall(
                      data['callId'] ?? '',
                      (data['caller'] as Map?) != null ? Map<String, dynamic>.from(data['caller']) : null,
                    );
              },
            );
          },
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
          // The return-to-call floating banner is handled globally by
          // ActiveCallOverlayWrapper in main.dart (wraps the entire app).
          // This avoids timing issues with isCallScreenVisible on web.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomBottomNav(
              currentIndex: _currentIndex,
              onTap: (index) {
                if (index == 2 && _currentIndex != 2) {
                  // Trigger refresh when navigating to call history tab
                  ref.read(callHistoryVersionProvider.notifier).state++;
                }
                setState(() => _currentIndex = index);
              },
            ),
          ),
        ],
      ),
    );
  }

}
