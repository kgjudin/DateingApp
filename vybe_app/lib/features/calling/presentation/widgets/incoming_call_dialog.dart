import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class IncomingCallDialog extends StatelessWidget {
  final Map<String, dynamic> caller;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallDialog({
    super.key,
    required this.caller,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.primaryAccent.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryAccent.withOpacity(0.35),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryAccent.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'INCOMING VOICE CALL',
                style: TextStyle(
                  color: AppColors.primaryAccentLight,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 46,
              backgroundColor: AppColors.primaryAccent,
              child: CircleAvatar(
                radius: 43,
                backgroundImage: NetworkImage(
                  caller['avatarUrl'] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              caller['displayName'] ?? 'Vybe Caller',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caller['location'] ?? 'Voice Discovery',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline Button
                GestureDetector(
                  onTap: onDecline,
                  child: Column(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: AppColors.error.withOpacity(0.4), blurRadius: 12),
                          ],
                        ),
                        child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 6),
                      const Text('Decline', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                // Accept Button
                GestureDetector(
                  onTap: onAccept,
                  child: Column(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: AppColors.online,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: AppColors.online.withOpacity(0.4), blurRadius: 12),
                          ],
                        ),
                        child: const Icon(Icons.call_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 6),
                      const Text('Accept', style: TextStyle(color: AppColors.online, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
