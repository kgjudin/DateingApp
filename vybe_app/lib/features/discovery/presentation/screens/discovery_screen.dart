import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/online_badge.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../calling/presentation/calling_controller.dart';
import '../discovery_controller.dart';

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoveryState = ref.watch(discoveryControllerProvider);
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'VYBE',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          // Coin Wallet Chip
          GestureDetector(
            onTap: () => context.push('/wallet'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.secondaryBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primaryAccent.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Text('🪙', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    '${authState.coinBalance}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () => context.push('/notifications'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(discoveryControllerProvider.notifier).fetchFeed(),
        color: AppColors.primaryAccent,
        backgroundColor: AppColors.secondaryBackground,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Filter Bar: Gender Preferences
              _buildGenderFilterBar(context, ref, discoveryState),

              const SizedBox(height: 18),

              // SECTION 1: ONLINE NOW (Horizontal Avatar Carousel)
              _buildSectionTitle('Online Now', '${discoveryState.onlineNow.length} active'),
              const SizedBox(height: 12),
              _buildOnlineNowCarousel(context, ref, discoveryState.onlineNow),

              const SizedBox(height: 24),

              // SECTION 2: BASED ON YOUR INTERESTS
              _buildSectionTitle('Based on Your Interests', 'Top shared vibes'),
              const SizedBox(height: 12),
              _buildDiscoveryUserList(context, ref, discoveryState.basedOnInterests),

              const SizedBox(height: 24),

              // SECTION 3: PEOPLE YOU MAY LIKE
              _buildSectionTitle('People You May Like', 'Recommended'),
              const SizedBox(height: 12),
              _buildDiscoveryUserList(context, ref, discoveryState.peopleYouMayLike),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String badge) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.secondaryBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(
              badge,
              style: const TextStyle(color: AppColors.primaryAccentLight, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderFilterBar(BuildContext context, WidgetRef ref, DiscoveryState state) {
    final filters = [
      {'id': 'everyone', 'label': 'Everyone'},
      {'id': 'women', 'label': 'Women'},
      {'id': 'men', 'label': 'Men'},
      {'id': 'non_binary', 'label': 'Non-Binary'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: filters.map((f) {
          final isSelected = state.selectedGenderFilter == f['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f['label']!),
              selected: isSelected,
              onSelected: (_) => ref.read(discoveryControllerProvider.notifier).setGenderFilter(f['id']!),
              backgroundColor: AppColors.secondaryBackground,
              selectedColor: AppColors.primaryAccent.withOpacity(0.2),
              side: BorderSide(
                color: isSelected ? AppColors.primaryAccent : AppColors.glassBorder,
              ),
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primaryAccentLight : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOnlineNowCarousel(BuildContext context, WidgetRef ref, List<dynamic> users) {
    if (users.isEmpty) {
      return Container(
        height: 72,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cardBackground.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: const Text(
          'No other users online right now. Invite friends!',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    return SizedBox(
      height: 106,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          return GestureDetector(
            onTap: () => context.push('/profile/${user['id']}'),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 76,
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundImage: NetworkImage(user['avatarUrl'] ?? ''),
                        ),
                      ),
                      const Positioned(
                        bottom: 0,
                        right: 2,
                        child: OnlineBadge(size: 13, isOnline: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user['displayName']?.toString().split(' ').first ?? 'User',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDiscoveryUserList(BuildContext context, WidgetRef ref, List<dynamic> users) {
    if (users.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cardBackground.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: const Column(
          children: [
            Icon(Icons.people_outline_rounded, color: AppColors.primaryAccentLight, size: 36),
            SizedBox(height: 10),
            Text(
              'No users found matching your filters',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'Try adjusting your preferences or check back soon.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final shared = (user['sharedInterests'] as List?) ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: GlassContainer(
            padding: EdgeInsets.zero,
            onTap: () => context.push('/profile/${user['id']}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover & Avatar Bar
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Image.network(
                        user['coverUrl'] ?? 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000',
                        height: 110,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Container(
                      height: 110,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 14,
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppColors.primaryAccent,
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundImage: NetworkImage(user['avatarUrl'] ?? ''),
                                ),
                              ),
                              const Positioned(
                                bottom: 0,
                                right: 0,
                                child: OnlineBadge(size: 12, isOnline: true),
                              ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${user['displayName']} • ${user['age'] ?? 24}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                user['location'] ?? 'Online',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bio
                      Text(
                        user['bio'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 12),

                      // Shared Interests Pills
                      if (shared.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.hub_rounded, color: AppColors.secondaryAccent, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              '${shared.length} Shared Vibes:',
                              style: const TextStyle(color: AppColors.secondaryAccent, fontWeight: FontWeight.w700, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: shared.map<Widget>((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.secondaryAccent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.secondaryAccent.withOpacity(0.3)),
                              ),
                              child: Text(
                                '#$tag',
                                style: const TextStyle(color: AppColors.secondaryAccent, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Bottom Action Row: Voice Intro & Quick CALL Button
                      Row(
                        children: [
                          if (user['voiceIntroUrl'] != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.secondaryBackground,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.volume_up_rounded, color: AppColors.primaryAccent, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${user['voiceIntroDuration'] ?? 15}s Intro',
                                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),

                          // Quick Call Button
                          ElevatedButton.icon(
                            onPressed: () {
                              ref.read(callingControllerProvider.notifier).startCall(
                                    receiverId: user['id'],
                                    receiverProfile: Map<String, dynamic>.from(user),
                                  );
                              context.push('/calling');
                            },
                            icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                            label: const Text('CALL'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
