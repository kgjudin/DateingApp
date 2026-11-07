import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/auth_controller.dart';
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
    final listeners = (room['listeners'] as List?) ?? [];
    final currentUserId = ref.read(authControllerProvider).user?['id']?.toString() ?? '';
    final isHost = roomState.currentRole == 'host';
    final isSubHost = roomState.currentRole == 'subhost';
    final isHostOrSubHost = isHost || isSubHost;
    final isSpeakerOrHost = isHostOrSubHost || roomState.currentRole == 'speaker';

    // Auto-pop if user was kicked
    if (roomState.kickedMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final msg = roomState.kickedMessage!;
        ref.read(roomsControllerProvider.notifier).clearKickedMessage();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.pop();
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => _handleLeave(context, ref, isHost, speakers, listeners),
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
          // Hand Raises Badge for Host / Sub-Host
          if (isHostOrSubHost && roomState.speakerRequests.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _showSpeakerRequestsSheet(context, ref, roomState.speakerRequests),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.front_hand_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${roomState.speakerRequests.length}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Listener Count Badge
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
                  '${room['listenersCount'] ?? listeners.length}',
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
              // Host Notice Banner (e.g. host changed, subhost assigned)
              if (roomState.hostNoticeMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.primaryAccent.withOpacity(0.2),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.primaryAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          roomState.hostNoticeMessage!,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => ref.read(roomsControllerProvider.notifier).clearHostNotice(),
                      ),
                    ],
                  ),
                ),
              ],

              // Pending Speaker Invitation Banner (for Listeners)
              if (roomState.pendingInvitation != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.secondaryAccent.withOpacity(0.9),
                        AppColors.primaryAccent.withOpacity(0.9),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondaryAccent.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Invited to Speak!',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            Text(
                              '${roomState.pendingInvitation!['hostName'] ?? 'Host'} invited you to join the stage',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.read(roomsControllerProvider.notifier).declineSpeakerInvitation(),
                        child: const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                      ElevatedButton(
                        onPressed: () => ref.read(roomsControllerProvider.notifier).acceptSpeakerInvitation(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Speak', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],

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
                          childAspectRatio: 0.82,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: speakers.length,
                        itemBuilder: (context, index) {
                          final speaker = speakers[index];
                          final spkUserId = speaker['userId']?.toString() ?? '';
                          final isSpkHost = speaker['role'] == 'host' || spkUserId == room['hostId']?.toString();
                          final isSpkSubHost = speaker['role'] == 'subhost' || spkUserId == room['subHostId']?.toString();
                          final isSelf = spkUserId == currentUserId;
                          final isMuted = isSelf ? roomState.isMuted : (speaker['isMuted'] == true);

                          return GestureDetector(
                            onTap: () {
                              if (isSelf) {
                                ref.read(roomsControllerProvider.notifier).toggleMic();
                              } else if (isHostOrSubHost) {
                                _showSpeakerModerationSheet(context, ref, speaker, isHost);
                              }
                            },
                            child: Column(
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
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isSpkHost) ...[
                                      Container(
                                        margin: const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryAccent,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text('HOST', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                      ),
                                    ] else if (isSpkSubHost) ...[
                                      Container(
                                        margin: const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: Colors.teal,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text('SUB-HOST', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                                      ),
                                    ],
                                    Flexible(
                                      child: Text(
                                        isSelf ? 'You' : (speaker['name'] ?? 'Speaker').toString().split(' ').first,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isSelf) ...[
                                  Text(
                                    isMuted ? 'Muted (Tap)' : 'Mic On (Tap)',
                                    style: TextStyle(
                                      color: isMuted ? AppColors.error : AppColors.primaryAccentLight,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 28),

                      // AUDIENCE / LISTENERS SECTION
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'AUDIENCE & LISTENERS',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 1.0,
                            ),
                          ),
                          if (isHostOrSubHost) ...[
                            Text(
                              'Tap listener to invite / manage',
                              style: TextStyle(color: AppColors.primaryAccentLight.withOpacity(0.8), fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (listeners.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'No listeners currently in the room',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                            ),
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            childAspectRatio: 0.9,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: listeners.length,
                          itemBuilder: (context, index) {
                            final listener = listeners[index];
                            final lUserId = listener['userId']?.toString() ?? '';
                            final avatar = listener['avatarUrl'] ?? '';
                            final name = listener['name'] ?? listener['displayName'] ?? 'Listener';
                            final isSelf = lUserId == currentUserId;

                            return GestureDetector(
                              onTap: () {
                                if (isHostOrSubHost && !isSelf) {
                                  _showListenerModerationSheet(context, ref, listener, isHost);
                                }
                              },
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: AppColors.secondaryBackground,
                                    backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                    child: avatar.isEmpty ? const Icon(Icons.person, color: AppColors.textMuted) : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
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
                    // Leave Button
                    OutlinedButton.icon(
                      onPressed: () => _handleLeave(context, ref, isHost, speakers, listeners),
                      icon: const Icon(Icons.waving_hand_rounded, size: 16, color: AppColors.error),
                      label: Text(
                        isHost ? 'Leave / End' : 'Leave quietly',
                        style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
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
                            receiverId: room['hostId'] ?? '',
                            receiverName: room['hostName'] ?? 'Host',
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: 8),

                    // Raise Hand or Mic Toggle
                    if (isSpeakerOrHost) ...[
                      ElevatedButton.icon(
                        onPressed: () => ref.read(roomsControllerProvider.notifier).toggleMic(),
                        icon: Icon(
                          roomState.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          roomState.isMuted ? 'Unmute Mic' : 'Mute Mic',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: roomState.isMuted ? AppColors.error : AppColors.primaryAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ] else ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          if (roomState.isHandRaised) {
                            ref.read(roomsControllerProvider.notifier).lowerHand();
                          } else {
                            ref.read(roomsControllerProvider.notifier).raiseHand();
                          }
                        },
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

  void _handleLeave(
    BuildContext context,
    WidgetRef ref,
    bool isHost,
    List<dynamic> speakers,
    List<dynamic> listeners,
  ) {
    if (!isHost) {
      ref.read(roomsControllerProvider.notifier).leaveActiveRoom();
      context.pop();
      return;
    }

    final currentUserId = ref.read(authControllerProvider).user?['id']?.toString() ?? '';
    final otherParticipants = [
      ...speakers.where((s) => s['userId']?.toString() != currentUserId),
      ...listeners.where((l) => l['userId']?.toString() != currentUserId),
    ];

    if (otherParticipants.isEmpty) {
      // Host is alone in room, simply end it
      ref.read(roomsControllerProvider.notifier).leaveActiveRoom(endRoomForEveryone: true);
      context.pop();
      return;
    }

    // Show leave modal with Sub-Host delegation option
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leave Room',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'You are the Host. You can assign a Sub-Host so the room stays open, and you will regain Host status when you return.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Option 1: Assign Sub-Host & Leave
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.swap_horiz_rounded, color: AppColors.primaryAccentLight, size: 24),
              ),
              title: const Text('Assign Sub-Host & Leave', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text(
                'Designate ${otherParticipants.first['name'] ?? 'a member'} as acting host',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              onTap: () async {
                final targetSubHostId = otherParticipants.first['userId']?.toString();
                await ref.read(roomsControllerProvider.notifier).leaveActiveRoom(newSubHostId: targetSubHostId);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) context.pop();
              },
            ),

            const Divider(color: AppColors.glassBorder),

            // Option 2: End Room for Everyone
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_end_rounded, color: AppColors.error, size: 24),
              ),
              title: const Text('End Room for Everyone', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Text('Closes the room and ends audio for all participants', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              onTap: () async {
                await ref.read(roomsControllerProvider.notifier).leaveActiveRoom(endRoomForEveryone: true);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) context.pop();
              },
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showSpeakerRequestsSheet(BuildContext context, WidgetRef ref, List<dynamic> requests) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Raised Hands',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${requests.length} Requests',
                    style: const TextStyle(color: AppColors.primaryAccentLight, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (requests.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No pending hand raises', style: TextStyle(color: AppColors.textMuted)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const Divider(color: AppColors.glassBorder),
                  itemBuilder: (c, i) {
                    final reqUser = requests[i];
                    final userId = reqUser['userId']?.toString() ?? '';
                    final name = reqUser['name'] ?? 'User';
                    final avatar = reqUser['avatarUrl'] ?? '';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                        child: avatar.isEmpty ? const Icon(Icons.person) : null,
                      ),
                      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                            onPressed: () {
                              ref.read(roomsControllerProvider.notifier).lowerHand(userId);
                              Navigator.pop(ctx);
                            },
                          ),
                          ElevatedButton(
                            onPressed: () {
                              ref.read(roomsControllerProvider.notifier).approveSpeaker(userId);
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            ),
                            child: const Text('Allow to Speak', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSpeakerModerationSheet(BuildContext context, WidgetRef ref, Map<String, dynamic> speaker, bool isHost) {
    final targetUserId = speaker['userId']?.toString() ?? '';
    final name = speaker['name'] ?? 'Speaker';
    final isMuted = speaker['isMuted'] == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manage $name',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 14),

            // Mute / Unmute
            ListTile(
              leading: Icon(isMuted ? Icons.mic_rounded : Icons.mic_off_rounded, color: Colors.orangeAccent),
              title: Text(isMuted ? 'Unmute Speaker' : 'Mute Speaker', style: const TextStyle(color: Colors.white)),
              onTap: () {
                ref.read(roomsControllerProvider.notifier).muteSpeaker(targetUserId, isMuted: !isMuted);
                Navigator.pop(ctx);
              },
            ),

            // Demote to Listener
            ListTile(
              leading: const Icon(Icons.arrow_downward_rounded, color: Colors.blueAccent),
              title: const Text('Move to Audience', style: TextStyle(color: Colors.white)),
              onTap: () {
                ref.read(roomsControllerProvider.notifier).demoteSpeaker(targetUserId);
                Navigator.pop(ctx);
              },
            ),

            // Make Sub-Host (Host only)
            if (isHost)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primaryAccentLight),
                title: const Text('Designate as Sub-Host', style: TextStyle(color: Colors.white)),
                onTap: () {
                  ref.read(roomsControllerProvider.notifier).makeSubHost(targetUserId);
                  Navigator.pop(ctx);
                },
              ),

            // Remove from room
            ListTile(
              leading: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error),
              title: const Text('Remove from Room', style: TextStyle(color: AppColors.error)),
              onTap: () {
                ref.read(roomsControllerProvider.notifier).kickUser(targetUserId);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showListenerModerationSheet(BuildContext context, WidgetRef ref, Map<String, dynamic> listener, bool isHost) {
    final targetUserId = listener['userId']?.toString() ?? '';
    final name = listener['name'] ?? listener['displayName'] ?? 'Listener';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manage $name',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 14),

            // Invite to Speak
            ListTile(
              leading: const Icon(Icons.record_voice_over_rounded, color: AppColors.primaryAccentLight),
              title: const Text('Invite to Speak on Stage', style: TextStyle(color: Colors.white)),
              onTap: () {
                ref.read(roomsControllerProvider.notifier).inviteToSpeak(targetUserId);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Invited $name to speak!'),
                    backgroundColor: AppColors.primaryAccent,
                  ),
                );
              },
            ),

            // Make Sub-Host
            if (isHost)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_rounded, color: Colors.tealAccent),
                title: const Text('Designate as Sub-Host', style: TextStyle(color: Colors.white)),
                onTap: () {
                  ref.read(roomsControllerProvider.notifier).makeSubHost(targetUserId);
                  Navigator.pop(ctx);
                },
              ),

            // Remove from Room
            ListTile(
              leading: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error),
              title: const Text('Remove from Room', style: TextStyle(color: AppColors.error)),
              onTap: () {
                ref.read(roomsControllerProvider.notifier).kickUser(targetUserId);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
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
