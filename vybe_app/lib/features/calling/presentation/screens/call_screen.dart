import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/voice_waveform_widget.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../wallet/presentation/widgets/gift_sheet.dart';
import '../calling_controller.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _isFollowing = false;
  bool _hasCheckedFollow = false;
  bool _hasShownEndDialog = false;
  StreamSubscription? _giftSub;
  Map<String, dynamic>? _activeReceivedGift;
  Timer? _giftDismissTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(callingControllerProvider.notifier).setCallScreenVisible(true);
    });
    _listenForInCallGifts();
  }

  @override
  void dispose() {
    ref.read(callingControllerProvider.notifier).setCallScreenVisible(false);
    _giftSub?.cancel();
    _giftDismissTimer?.cancel();
    super.dispose();
  }

  void _listenForInCallGifts() {
    final socket = ref.read(socketServiceProvider);
    _giftSub = socket.onGiftReceived.listen((data) {
      if (!mounted) return;
      final myId = ref.read(authControllerProvider).user?['id'];
      final receiverId = data['receiverId'];

      if (receiverId != null && myId != null && receiverId != myId) return;

      // Update local wallet coin balance
      if (data['receiverNewBalance'] != null) {
        ref.read(authControllerProvider.notifier).updateCoinBalance(data['receiverNewBalance'] as int);
      } else {
        final current = ref.read(authControllerProvider).coinBalance;
        final delta = (data['coinAmount'] as int?) ?? 0;
        ref.read(authControllerProvider.notifier).updateCoinBalance(current + delta);
      }

      setState(() {
        _activeReceivedGift = data;
      });

      _giftDismissTimer?.cancel();
      _giftDismissTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) {
          setState(() => _activeReceivedGift = null);
        }
      });
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _checkFollowStatus(String peerId) async {
    if (_hasCheckedFollow || peerId.isEmpty) return;
    _hasCheckedFollow = true;
    try {
      final res = await ref.read(apiClientProvider).get('/profile/$peerId');
      if (res is Map && mounted) {
        setState(() {
          _isFollowing = res['isFollowing'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFollow(String peerId, String peerName) async {
    if (peerId.isEmpty) return;
    final next = !_isFollowing;
    setState(() => _isFollowing = next);
    try {
      final res = await ref.read(apiClientProvider).post('/follow/toggle', body: {
        'targetUserId': peerId,
      });
      if (res is Map && mounted) {
        setState(() => _isFollowing = res['isFollowing'] == true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.cardBackground,
            content: Text(
              _isFollowing
                  ? 'Followed $peerName! They received a notification.'
                  : 'Unfollowed $peerName.',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFollowing = !next);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Failed to follow $peerName: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showPostCallDialog(Map<dynamic, dynamic> peer, int duration) {
    if (_hasShownEndDialog || !mounted) return;
    _hasShownEndDialog = true;

    final peerId = peer['id']?.toString() ?? '';
    final peerName = peer['displayName']?.toString() ?? 'Friend';
    final myId = ref.read(authControllerProvider).user?['id']?.toString().toLowerCase();
    final isSelf = myId != null && peerId.isNotEmpty && myId == peerId.toLowerCase();

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: const BoxDecoration(
              color: AppColors.secondaryBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Call Ended icon
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.call_end_rounded, color: AppColors.primaryAccent, size: 32),
                ),
                const SizedBox(height: 12),

                const Text(
                  'Call Finished',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 4),
                Text(
                  'Duration: ${_formatDuration(duration)}',
                  style: const TextStyle(color: AppColors.primaryAccentLight, fontSize: 13, fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 20),

                // Friend preview card
                GlassContainer(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: NetworkImage(
                          peer['avatarUrl'] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peerName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            const Text(
                              'Follow to meet as soon as they become online!',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Follow Friend Action Button
                if (peerId.isNotEmpty && !isSelf)
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _toggleFollow(peerId, peerName);
                      if (context.mounted) {
                        setModalState(() {});
                      }
                    },
                    icon: Icon(
                      _isFollowing ? Icons.check_rounded : Icons.person_add_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: Text(
                      _isFollowing ? 'Following $peerName' : 'Follow $peerName',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isFollowing ? AppColors.cardBackground : AppColors.primaryAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: _isFollowing ? const BorderSide(color: AppColors.primaryAccent) : BorderSide.none,
                      ),
                    ),
                  ),

                const SizedBox(height: 10),

                // Done Button
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (context.mounted && Navigator.canPop(context)) {
                      context.pop();
                    }
                  },
                  child: const Text('Done', style: TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final callingState = ref.watch(callingControllerProvider);
    final peer = callingState.peerProfile ?? {};
    final peerId = peer['id']?.toString() ?? '';
    final peerName = peer['displayName']?.toString() ?? 'Vybe User';

    if (peerId.isNotEmpty && !_hasCheckedFollow) {
      _checkFollowStatus(peerId);
    }

    // When call ends, show the Post-Call Follow Dialog
    if (callingState.status == CallStatus.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPostCallDialog(peer, callingState.durationSeconds);
      });
    } else if (callingState.status == CallStatus.idle && !_hasShownEndDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.canPop(context)) {
          context.pop();
        }
      });
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(callingControllerProvider.notifier).setCallScreenVisible(false);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.primaryBackground,
        body: Stack(
          children: [
            // Background Ambience Glow
            Positioned(
              top: -100,
              left: -50,
              right: -50,
              height: 450,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryAccent.withOpacity(0.25),
                      AppColors.secondaryAccent.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    // Top Minimize & In-Call Follow Action Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            ref.read(callingControllerProvider.notifier).setCallScreenVisible(false);
                            if (Navigator.canPop(context)) {
                              context.pop();
                            } else {
                              context.go('/home');
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryBackground,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 22),
                                SizedBox(width: 4),
                                Text(
                                  'Minimize',
                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryBackground,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: callingState.status == CallStatus.connected
                                    ? AppColors.online
                                    : AppColors.busy,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              callingState.status == CallStatus.connected
                                  ? 'Connected'
                                  : (callingState.status == CallStatus.ringing ? 'Ringing...' : 'Calling...'),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),

                      // In-Call Follow Button
                      if (peerId.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _toggleFollow(peerId, peerName),
                          icon: Icon(
                            _isFollowing ? Icons.check_rounded : Icons.person_add_rounded,
                            size: 13,
                            color: _isFollowing ? AppColors.online : Colors.white,
                          ),
                          label: Text(
                            _isFollowing ? 'Following' : 'Follow',
                            style: TextStyle(
                              color: _isFollowing ? AppColors.online : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _isFollowing ? AppColors.online.withOpacity(0.15) : AppColors.secondaryBackground,
                            side: BorderSide(
                              color: _isFollowing ? AppColors.online : AppColors.glassBorder,
                              width: 1,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),

                  const Spacer(flex: 1),

                  // Center Peer Avatar with Voice Pulsing Rings
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer pulse ring
                        if (callingState.status == CallStatus.connected) ...[
                          Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primaryAccent.withOpacity(0.25), width: 2),
                            ),
                          ),
                          Container(
                            width: 190,
                            height: 190,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primaryAccent.withOpacity(0.4), width: 2),
                            ),
                          ),
                        ],
                        CircleAvatar(
                          radius: 76,
                          backgroundColor: AppColors.primaryAccent,
                          child: CircleAvatar(
                            radius: 72,
                            backgroundImage: NetworkImage(
                              peer['avatarUrl'] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Peer Name & Location
                  Text(
                    peerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    peer['location'] ?? 'Online Audio Session',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),

                  const SizedBox(height: 24),

                  // Call Duration Timer
                  Text(
                    _formatDuration(callingState.durationSeconds),
                    style: const TextStyle(
                      color: AppColors.primaryAccentLight,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Live Waveform
                  VoiceWaveformWidget(
                    isSpeaking: callingState.status == CallStatus.connected && !callingState.isMuted,
                    barCount: 26,
                    maxHeight: 50,
                  ),

                  const Spacer(flex: 2),

                  // In-Call Action Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryBackground,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Mute Button
                        _buildCallButton(
                          icon: callingState.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          label: callingState.isMuted ? 'Unmute' : 'Mute',
                          isActive: callingState.isMuted,
                          onTap: () => ref.read(callingControllerProvider.notifier).toggleMute(),
                        ),

                        // Speakerphone Button
                        _buildCallButton(
                          icon: callingState.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                          label: 'Speaker',
                          isActive: callingState.isSpeakerOn,
                          onTap: () => ref.read(callingControllerProvider.notifier).toggleSpeaker(),
                        ),

                        // Send Virtual Gift Button
                        _buildCallButton(
                          icon: Icons.card_giftcard_rounded,
                          label: 'Gift',
                          isActive: false,
                          iconColor: AppColors.secondaryAccent,
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              builder: (ctx) => GiftBottomSheet(
                                receiverId: peerId,
                                receiverName: peerName,
                              ),
                            );
                          },
                        ),

                        // End Call Button
                        GestureDetector(
                          onTap: () => ref.read(callingControllerProvider.notifier).endCall(),
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.error.withOpacity(0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Celebratory In-Call Gift Notification Overlay
          if (_activeReceivedGift != null)
            Positioned(
              top: 75,
              left: 20,
              right: 20,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF2A1B4E),
                      AppColors.secondaryBackground,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFFFD700), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                      ),
                      child: Text(
                        _activeReceivedGift!['emoji'] ?? '🎁',
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${_activeReceivedGift!['senderName'] ?? 'Friend'} gifted you!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text('✨', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_activeReceivedGift!['giftName']} • +${_activeReceivedGift!['coinAmount'] ?? 0} Coins!',
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                      onPressed: () {
                        setState(() => _activeReceivedGift = null);
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ));
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primaryAccent : AppColors.cardBackground,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? AppColors.primaryAccent : AppColors.glassBorder,
              ),
            ),
            child: Icon(
              icon,
              color: iconColor ?? (isActive ? Colors.white : AppColors.textPrimary),
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
