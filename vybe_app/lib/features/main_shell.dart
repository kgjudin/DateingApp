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
    final socket = ref.read(socketServiceProvider);
    socket.onNewFollower.listen((data) {
      if (!mounted) return;

      final followerName = data['followerName'] ??
          data['payload']?['displayName'] ??
          data['title']?.toString().replaceAll('New Follower! 🎉', '').trim() ??
          'Someone';
      final followerId = data['followerId'] ??
          data['payload']?['followerId'] ??
          data['payload']?['userId'];

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.secondaryBackground,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.secondaryAccent, width: 1.5),
          ),
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondaryAccent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_add_rounded, color: AppColors.secondaryAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$followerName followed you! 🎉',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Follow back to meet when you\'re online.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'VIEW',
            textColor: AppColors.secondaryAccent,
            onPressed: () {
              if (followerId != null && followerId.toString().isNotEmpty) {
                context.push('/profile/$followerId');
              } else {
                context.push('/notifications');
              }
            },
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    });
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
    final callingState = ref.watch(callingControllerProvider);
    final isCallActive = (callingState.status == CallStatus.connected ||
            callingState.status == CallStatus.connecting ||
            callingState.status == CallStatus.ringing ||
            callingState.status == CallStatus.initiating) &&
        !callingState.isCallScreenVisible;

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCallActive)
                  _buildDockedReturnToCallBanner(context, callingState),
                CustomBottomNav(
                  currentIndex: _currentIndex,
                  onTap: (index) => setState(() => _currentIndex = index),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockedReturnToCallBanner(BuildContext context, CallingState callingState) {
    final peer = callingState.peerProfile ?? {};
    final peerName = peer['displayName']?.toString() ?? 'Active Call';
    final peerAvatar = peer['avatarUrl']?.toString() ??
        'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500';

    final isConnected = callingState.status == CallStatus.connected;
    final m = (callingState.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (callingState.durationSeconds % 60).toString().padLeft(2, '0');
    final durationText = isConnected
        ? '$m:$s'
        : (callingState.status == CallStatus.ringing ? 'Ringing...' : 'Calling...');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            ref.read(callingControllerProvider.notifier).setCallScreenVisible(true);
            context.push('/calling');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1F1138), Color(0xFF131524)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected ? AppColors.online : AppColors.primaryAccent,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? AppColors.online : AppColors.primaryAccent).withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Caller Avatar + Glowing Status Indicator
                Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(peerAvatar),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isConnected ? AppColors.online : AppColors.busy,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Name & Duration
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              peerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('🔊', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: (isConnected ? AppColors.online : AppColors.primaryAccent).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              durationText,
                              style: TextStyle(
                                color: isConnected ? AppColors.online : AppColors.primaryAccentLight,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Tap to return',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // RETURN TO CALL BUTTON
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(callingControllerProvider.notifier).setCallScreenVisible(true);
                    context.push('/calling');
                  },
                  icon: const Icon(Icons.phone_in_talk_rounded, size: 14, color: Colors.white),
                  label: const Text(
                    'RETURN',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected ? AppColors.online : AppColors.primaryAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(width: 8),

                // Quick Hangup Button
                GestureDetector(
                  onTap: () => ref.read(callingControllerProvider.notifier).endCall(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
