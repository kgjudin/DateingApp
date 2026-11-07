import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/online_badge.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../calling/presentation/calling_controller.dart';

class FavouritesScreen extends ConsumerStatefulWidget {
  const FavouritesScreen({super.key});

  @override
  ConsumerState<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends ConsumerState<FavouritesScreen> {
  int _selectedTabIndex = 0; // 0 = Following, 1 = Followers
  List<dynamic> _following = [];
  List<dynamic> _followers = [];
  bool _isLoading = true;
  StreamSubscription? _presenceSub;

  @override
  void initState() {
    super.initState();
    _fetchNetwork();
    _presenceSub = ref.read(socketServiceProvider).onPresenceChanged.listen((data) {
      final uId = data['userId']?.toString().toLowerCase();
      final status = data['status']?.toString().toLowerCase();
      final isOnline = data['isOnline'] == true || status == 'online' || status == 'in_call' || status == 'in_room';

      if (uId != null && status != null && mounted) {
        setState(() {
          for (int i = 0; i < _following.length; i++) {
            if (_following[i]['id']?.toString().toLowerCase() == uId) {
              _following[i] = Map<String, dynamic>.from(_following[i])
                ..['status'] = status
                ..['isOnline'] = isOnline;
            }
          }
          for (int i = 0; i < _followers.length; i++) {
            if (_followers[i]['id']?.toString().toLowerCase() == uId) {
              _followers[i] = Map<String, dynamic>.from(_followers[i])
                ..['status'] = status
                ..['isOnline'] = isOnline;
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchNetwork() async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      setState(() {
        _following = [];
        _followers = [];
        _isLoading = false;
      });
      return;
    }

    try {
      final followingRes = await ref.read(apiClientProvider).get('/follow/following');
      final followersRes = await ref.read(apiClientProvider).get('/follow/followers');
      final favRes = await ref.read(apiClientProvider).get('/favourites');

      List<dynamic> followingList = [];
      if (followingRes is List) {
        followingList = followingRes;
      } else if (favRes is List) {
        followingList = favRes;
      }

      if (mounted) {
        setState(() {
          _following = followingList;
          _followers = (followersRes is List) ? followersRes : [];
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _following = [];
        _followers = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow(String targetUserId, int index, bool isFollowersTab) async {
    try {
      final res = await ref.read(apiClientProvider).post('/follow/toggle', body: {
        'targetUserId': targetUserId,
      });

      if (res is Map && mounted) {
        final isFollowing = res['isFollowing'] == true;
        final name = isFollowersTab
            ? (_followers.length > index ? _followers[index]['displayName'] : 'User')
            : (_following.length > index ? _following[index]['displayName'] : 'User');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.cardBackground,
            content: Text(
              isFollowing
                  ? 'Followed $name! They received a notification.'
                  : 'Unfollowed $name.',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        _fetchNetwork();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _selectedTabIndex == 0 ? _following : _followers;

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('Friends & Network', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: Column(
        children: [
          // Segmented Tab Switcher (Following / Followers)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.secondaryBackground,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSegmentButton(
                      title: 'Following (${_following.length})',
                      isSelected: _selectedTabIndex == 0,
                      onTap: () => setState(() => _selectedTabIndex = 0),
                    ),
                  ),
                  Expanded(
                    child: _buildSegmentButton(
                      title: 'Followers (${_followers.length})',
                      isSelected: _selectedTabIndex == 1,
                      onTap: () => setState(() => _selectedTabIndex = 1),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Users list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryAccent))
                : currentList.isEmpty
                    ? _buildEmptyState(_selectedTabIndex == 0)
                    : RefreshIndicator(
                        onRefresh: _fetchNetwork,
                        color: AppColors.primaryAccent,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          itemCount: currentList.length,
                          itemBuilder: (context, index) {
                            final user = currentList[index];
                            final status = user['status']?.toString().toLowerCase();
                            final isOnline = user['isOnline'] == true || status == 'online' || status == 'in_call' || status == 'in_room';
                            final isFollowing = user['isFollowing'] == true;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: GlassContainer(
                                padding: const EdgeInsets.all(14),
                                onTap: () => context.push('/profile/${user['id']}'),
                                child: Row(
                                  children: [
                                    // Avatar with live Online Indicator
                                    Stack(
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundImage: NetworkImage(
                                            user['avatarUrl'] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: OnlineBadge(size: 13, isOnline: isOnline),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),

                                    // Name & Live Status
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user['displayName'] ?? 'User',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            isOnline
                                                ? (status == 'in_call' ? '🟢 Online • In Call' : '🟢 Online now • Ready to talk')
                                                : 'Offline',
                                            style: TextStyle(
                                              color: isOnline ? AppColors.online : AppColors.textSecondary,
                                              fontSize: 12,
                                              fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Follow / Following button on both tabs
                                    OutlinedButton(
                                      onPressed: () => _toggleFollow(user['id'], index, _selectedTabIndex == 1),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: isFollowing ? Colors.transparent : AppColors.primaryAccent.withOpacity(0.15),
                                        side: BorderSide(
                                          color: isFollowing ? AppColors.textMuted : AppColors.primaryAccent,
                                          width: 1,
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      child: Text(
                                        isFollowing ? 'Following' : '+ Follow',
                                        style: TextStyle(
                                          color: isFollowing ? AppColors.textSecondary : AppColors.primaryAccentLight,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Quick Call Button
                                    IconButton(
                                      icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.primaryAccent),
                                      onPressed: () {
                                        ref.read(callingControllerProvider.notifier).startCall(
                                              receiverId: user['id'],
                                              receiverProfile: Map<String, dynamic>.from(user),
                                            );
                                        context.push('/calling');
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({required String title, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isFollowingTab) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: AppColors.cardBackground, shape: BoxShape.circle),
              child: Icon(
                isFollowingTab ? Icons.person_add_alt_1_rounded : Icons.people_outline_rounded,
                color: AppColors.textMuted,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isFollowingTab ? 'No friends followed yet' : 'No followers yet',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              isFollowingTab
                  ? 'Follow friends after voice calls or from profiles to meet as soon as they become online.'
                  : 'Talk in voice rooms and make calls to gain friends and followers.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
