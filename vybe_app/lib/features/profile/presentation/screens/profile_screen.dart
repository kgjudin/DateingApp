import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/online_badge.dart';
import '../../../auth/presentation/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user ?? {};
    final interests = (user['interests'] as List?) ?? ['Music', 'Travelling', 'Art', 'Lifestyle'];

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () => _showSettingsModal(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // COVER & AVATAR
            Stack(
              clipBehavior: Clip.none,
              children: [
                Image.network(
                  user['coverUrl'] ?? 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000',
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, AppColors.primaryBackground.withOpacity(0.9)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -40,
                  left: 20,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 46,
                        backgroundColor: AppColors.primaryAccent,
                        child: CircleAvatar(
                          radius: 43,
                          backgroundImage: NetworkImage(
                            user['avatarUrl'] ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
                          ),
                        ),
                      ),
                      const Positioned(
                        bottom: 4,
                        right: 4,
                        child: OnlineBadge(size: 16, isOnline: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 50),

            // NAME & HANDLE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${user['displayName'] ?? 'Vybe User'}${user['age'] != null ? ' • ${user['age']}' : ''}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
                          ),
                          Text(
                            '@${user['username'] ?? 'vyber'}${user['location'] != null ? ' • ${user['location']}' : ''}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/profile-builder'),
                        icon: const Icon(Icons.edit_rounded, size: 14, color: AppColors.primaryAccent),
                        label: const Text('Edit', style: TextStyle(color: AppColors.primaryAccent, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primaryAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // BIO
                  Text(
                    user['bio'] ?? 'No bio added yet. Tap Edit to personalize your profile.',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4),
                  ),

                  const SizedBox(height: 20),

                  // VOICE INTRO PLAYER CARD
                  if (user['voiceIntroUrl'] != null)
                    GlassContainer(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Voice Introduction', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                                Text('Audio Preview', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.graphic_eq_rounded, color: AppColors.primaryAccent, size: 24),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // STATS BAR
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('${user['callsCount'] ?? 0}', 'Voice Calls')),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('${user['roomsHostedCount'] ?? 0}', 'Stages Hosted')),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('🪙 ${authState.coinBalance}', 'Balance')),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // INTEREST TAGS
                  const Text('Interests & Passions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: interests.map<Widget>((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(
                          '#$tag',
                          style: const TextStyle(color: AppColors.primaryAccentLight, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String val, String label) {
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  void _showSettingsModal(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Privacy & Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('Discoverability on Voice Radar', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Allow online users to discover you', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              value: true,
              activeColor: AppColors.primaryAccent,
              onChanged: (_) {},
            ),
            SwitchListTile(
              title: const Text('Show Online Status', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Display emerald active indicator', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              value: true,
              activeColor: AppColors.primaryAccent,
              onChanged: (_) {},
            ),
            const Divider(color: AppColors.glassBorder),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primaryAccent),
              title: const Text('Coin Wallet & Transactions', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/wallet');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.error),
              title: const Text('Sign Out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}
