import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/voice_waveform_widget.dart';
import '../../../wallet/presentation/widgets/gift_sheet.dart';
import '../calling_controller.dart';

class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callingState = ref.watch(callingControllerProvider);
    final peer = callingState.peerProfile ?? {};

    // Auto-pop if call ended
    if (callingState.status == CallStatus.idle || callingState.status == CallStatus.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.canPop(context)) {
          context.pop();
        }
      });
    }

    return Scaffold(
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
                  // Top Minimize Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                        onPressed: () => context.pop(),
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
                      const SizedBox(width: 48), // Balance spacing
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
                    peer['displayName'] ?? 'Vybe User',
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
                                receiverId: peer['id'] ?? '',
                                receiverName: peer['displayName'] ?? 'Vybe User',
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
        ],
      ),
    );
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
