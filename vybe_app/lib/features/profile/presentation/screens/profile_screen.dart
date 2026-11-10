import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/online_badge.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../widgets/follow_users_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _liveProfile;

  @override
  void initState() {
    super.initState();
    _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    try {
      final res = await ref.read(apiClientProvider).get('/auth/me');
      if (res is Map && res['user'] != null && mounted) {
        setState(() {
          _liveProfile = Map<String, dynamic>.from(res['user']);
        });
      }
    } catch (_) {}
  }

  void _openFollowSheet(String title, bool isFollowers, String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FollowUsersSheet(
        title: title,
        userId: userId,
        isFollowers: isFollowers,
      ),
    ).then((_) => _refreshProfile());
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = _liveProfile ?? (authState.user ?? {});
    final interests = (user['interests'] as List?) ?? ['Music', 'Travelling', 'Art', 'Lifestyle'];
    final userId = user['id'] ?? '';
    final followersCount = user['followersCount'] ?? 0;
    final followingCount = user['followingCount'] ?? 0;

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
            tooltip: 'Wallet & Gifts',
            onPressed: () => context.push('/wallet'),
          ),
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primaryAccentLight),
            tooltip: 'Admin Console',
            onPressed: () => context.push('/admin'),
          ),
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

                  // STATS BAR: FOLLOWERS & FOLLOWING
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          '$followersCount',
                          'Followers',
                          onTap: () => _openFollowSheet('Followers', true, userId),
                          icon: Icons.people_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          '$followingCount',
                          'Following',
                          onTap: () => _openFollowSheet('Following', false, userId),
                          icon: Icons.person_add_alt_1_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          '${user['callsCount'] ?? 0}',
                          'Calls',
                          icon: Icons.phone_in_talk_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          '🪙 ${authState.coinBalance}',
                          'Coins',
                          onTap: () => context.push('/wallet'),
                        ),
                      ),
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

  Widget _buildStatCard(String val, String label, {VoidCallback? onTap, IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.primaryAccentLight, size: 16),
              const SizedBox(height: 4),
            ],
            Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: onTap != null ? AppColors.secondaryAccent : AppColors.textSecondary,
                fontSize: 10,
                fontWeight: onTap != null ? FontWeight.w600 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
            const Text('Account & Privacy Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('Discoverability on Voice Radar', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Allow online users to discover you', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              value: true,
              activeColor: AppColors.primaryAccent,
              onChanged: (val) {},
            ),
            SwitchListTile(
              title: const Text('Show Online Status', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Display emerald active indicator', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              value: true,
              activeColor: AppColors.primaryAccent,
              onChanged: (val) {},
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primaryAccent),
              title: const Text('Admin Console', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: const Text('Add coins, block users & send warnings', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/admin');
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.error),
              title: const Text('Log Out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(authControllerProvider.notifier).logout();
                context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}
