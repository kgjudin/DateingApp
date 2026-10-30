import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../wallet/presentation/widgets/gift_sheet.dart';
import '../rooms_controller.dart';

class LiveVoiceRoomScreen extends ConsumerWidget {
  final String roomId;

  const LiveVoiceRoomScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomState = ref.watch(roomsControllerProvider);
    final room = roomState.activeRoom ?? {};
    final speakers = (room['speakers'] as List?) ?? [];
    final isSpeakerOrHost = roomState.currentRole == 'host' || roomState.currentRole == 'speaker';

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_rounded, color: AppColors.primaryAccent, size: 14),
                const SizedBox(width: 4),
                Text(
                  room['groupName'] ?? 'Community Stage',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            Text(
              room['title'] ?? 'Live Voice Room',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: AppColors.secondaryBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.headphones_rounded, color: AppColors.primaryAccentLight, size: 14),
                const SizedBox(width: 6),
                Text(
                  '${room['listenersCount'] ?? 18}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // STAGE HEADER
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'STAGE & SPEAKERS',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 1.0,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primaryAccent.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${speakers.length} Speakers',
                              style: const TextStyle(color: AppColors.primaryAccentLight, fontWeight: FontWeight.w700, fontSize: 11),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // SPEAKERS GRID
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: speakers.length,
                        itemBuilder: (context, index) {
                          final speaker = speakers[index];
                          final isHost = speaker['role'] == 'host';
                          final isMuted = speaker['isMuted'] == true;

                          return Column(
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Speaking Halo Ring
                                  if (!isMuted) ...[
                                    Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.primaryAccent, width: 2.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primaryAccent.withOpacity(0.35),
                                            blurRadius: 12,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  CircleAvatar(
                                    radius: 32,
                                    backgroundColor: AppColors.secondaryBackground,
                                    backgroundImage: NetworkImage(
                                      speaker['avatarUrl'] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
                                    ),
                                  ),
                                  // Mic Mute indicator badge
                                  Positioned(
                                    bottom: 0,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: isMuted ? AppColors.error : AppColors.primaryAccent,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.primaryBackground, width: 1.5),
                                      ),
                                      child: Icon(
                                        isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isHost) ...[
                                    Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryAccent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('HOST', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                    ),
                                  ],
                                  Flexible(
                                    child: Text(
                                      speaker['name']?.toString().split(' ').first ?? 'Speaker',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 28),

                      // AUDIENCE / LISTENERS SECTION
                      const Text(
                        'AUDIENCE & LISTENERS',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 16),

                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 0.9,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: 8,
                        itemBuilder: (context, index) {
                          final dummyAvatars = [
                            'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
                            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
                            'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500',
                            'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=500',
                            'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500',
                            'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=500',
                            'https://images.unsplash.com/photo-1531482615713-2afd69097998?w=500',
                            'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=1000',
                          ];
                          final dummyNames = ['Maya', 'Dev', 'Chloe', 'Liam', 'Zoe', 'Lucas', 'Tara', 'Sam'];

                          return Column(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: AppColors.secondaryBackground,
                                backgroundImage: NetworkImage(dummyAvatars[index % dummyAvatars.length]),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dummyNames[index % dummyNames.length],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),

              // BOTTOM ROOM CONTROLS
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppColors.secondaryBackground,
                  border: Border(top: BorderSide(color: AppColors.glassBorder)),
                ),
                child: Row(
                  children: [
                    // Leave Quietly
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref.read(roomsControllerProvider.notifier).leaveActiveRoom();
                        if (context.mounted) context.pop();
                      },
                      icon: const Icon(Icons.waving_hand_rounded, size: 16, color: AppColors.error),
                      label: const Text('Leave quietly', style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.error.withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),

                    const Spacer(),

                    // Send Gift Button
                    IconButton(
                      icon: const Icon(Icons.card_giftcard_rounded, color: AppColors.secondaryAccent, size: 28),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (ctx) => GiftBottomSheet(
                            roomId: roomId,
                            receiverId: room['hostId'] ?? 'user-elena-101',
                            receiverName: room['hostName'] ?? 'Host',
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: 8),

                    // Raise Hand or Mic Toggle
                    if (isSpeakerOrHost) ...[
                      GestureDetector(
                        onTap: () => ref.read(roomsControllerProvider.notifier).toggleMic(),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: roomState.isMuted ? AppColors.cardBackground : AppColors.primaryAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Icon(
                            roomState.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ] else ...[
                      ElevatedButton.icon(
                        onPressed: roomState.isHandRaised
                            ? null
                            : () => ref.read(roomsControllerProvider.notifier).raiseHand(),
                        icon: Icon(
                          roomState.isHandRaised ? Icons.pan_tool_rounded : Icons.front_hand_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: Text(roomState.isHandRaised ? 'Hand Raised' : 'Raise Hand', style: const TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: roomState.isHandRaised ? AppColors.secondaryAccent : AppColors.primaryAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // LIVE GIFT OVERLAY ANIMATION
          if (roomState.liveGiftOverlay != null) ...[
            Positioned(
              top: 40,
              left: 20,
              right: 20,
              child: _buildGiftOverlay(roomState.liveGiftOverlay!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGiftOverlay(Map<String, dynamic> gift) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryAccent.withOpacity(0.95),
            AppColors.secondaryAccent.withOpacity(0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondaryAccent.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('🎁', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${gift['senderName'] ?? 'A member'} sent a ${gift['giftName'] ?? 'Gift'}!',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  'To ${gift['receiverName'] ?? 'the Stage'} • 🪙 ${gift['coinAmount'] ?? 50} coins',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
