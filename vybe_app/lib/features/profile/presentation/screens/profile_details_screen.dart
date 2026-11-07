import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/online_badge.dart';
import '../../../../core/widgets/voice_waveform_widget.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../calling/presentation/calling_controller.dart';
import '../../../wallet/presentation/widgets/gift_sheet.dart';
import '../widgets/follow_users_sheet.dart';

class ProfileDetailsScreen extends ConsumerStatefulWidget {
  final String userId;

  const ProfileDetailsScreen({super.key, required this.userId});

  @override
  ConsumerState<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends ConsumerState<ProfileDetailsScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isPlayingIntro = false;
  bool _isFavourite = false;
  bool _isFollowing = false;
  int _followersCount = 0;
  int _followingCount = 0;
  StreamSubscription? _presenceSub;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _presenceSub = ref.read(socketServiceProvider).onPresenceChanged.listen((data) {
      final uId = data['userId']?.toString().toLowerCase();
      final status = data['status']?.toString().toLowerCase();
      final isOnline = data['isOnline'] == true || status == 'online' || status == 'in_call' || status == 'in_room';

      if (uId == widget.userId.toLowerCase() && _profile != null && mounted) {
        setState(() {
          _profile!['status'] = status;
          _profile!['presence'] = status;
          _profile!['isOnline'] = isOnline;
        });
      }
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    try {
      final res = await ref.read(apiClientProvider).get('/profile/${widget.userId}');
      if (res is Map && mounted) {
        setState(() {
          _profile = Map<String, dynamic>.from(res);
          _isFavourite = _profile?['isFavourite'] ?? false;
          _isFollowing = _profile?['isFollowing'] ?? false;
          _followersCount = _profile?['followersCount'] ?? 0;
          _followingCount = _profile?['followingCount'] ?? 0;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _profile = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final myId = ref.read(authControllerProvider).user?['id'];
    if (myId != null && myId == widget.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot follow yourself')),
      );
      return;
    }

    final nextState = !_isFollowing;
    setState(() {
      _isFollowing = nextState;
      _followersCount += nextState ? 1 : -1;
      if (_followersCount < 0) _followersCount = 0;
    });

    try {
      final res = await ref.read(apiClientProvider).post('/follow/toggle', body: {
        'targetUserId': widget.userId,
      });

      if (res is Map && mounted) {
        setState(() {
          if (res['isFollowing'] != null) {
            _isFollowing = res['isFollowing'] == true;
          }
          if (res['followersCount'] != null) {
            _followersCount = res['followersCount'];
          }
          if (res['followingCount'] != null) {
            _followingCount = res['followingCount'];
          }
        });
      }

      if (mounted) {
        final friendName = _profile?['displayName'] ?? 'friend';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.cardBackground,
            content: Text(
              _isFollowing
                  ? 'Followed $friendName! They received a notification.'
                  : 'Unfollowed $friendName.',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowing = !nextState;
          _followersCount += nextState ? -1 : 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update follow: $e')),
        );
      }
    }
  }

  void _openFollowSheet(String title, bool isFollowers) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FollowUsersSheet(
        title: title,
        userId: widget.userId,
        isFollowers: isFollowers,
      ),
    ).then((_) => _fetchProfile());
  }

  Future<void> _toggleFavourite() async {
    setState(() => _isFavourite = !_isFavourite);
    try {
      await ref.read(apiClientProvider).post('/favourites/toggle', body: {'targetUserId': widget.userId});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.primaryBackground,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryAccent)),
      );
    }

    if (_profile == null) {
      return Scaffold(
        backgroundColor: AppColors.primaryBackground,
        appBar: AppBar(title: const Text('User Profile')),
        body: const Center(
          child: Text(
            'Profile not found or unavailable.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
        ),
      );
    }

    final user = _profile!;
    final currentUserId = ref.watch(authControllerProvider).user?['id'];
    final isMe = currentUserId != null && currentUserId == widget.userId;
    final status = user['status']?.toString().toLowerCase();
    final isOnline = user['isOnline'] == true || status == 'online' || status == 'in_call' || status == 'in_room' || user['presence'] == 'online';
    final interests = (user['interests'] as List?) ?? [];

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // COVER & HEADER
                Stack(
                  children: [
                    Image.network(
                      user['coverUrl'] ?? 'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=1000',
                      height: 240,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    Container(
                      height: 240,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black.withOpacity(0.5), AppColors.primaryBackground],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.black.withOpacity(0.5),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                                onPressed: () => context.pop(),
                              ),
                            ),
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.black.withOpacity(0.5),
                                  child: IconButton(
                                    icon: Icon(
                                      _isFavourite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                      color: _isFavourite ? AppColors.secondaryAccent : Colors.white,
                                    ),
                                    onPressed: _toggleFavourite,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                CircleAvatar(
                                  backgroundColor: Colors.black.withOpacity(0.5),
                                  child: IconButton(
                                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                                    onPressed: () => _showSafetyOptions(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // USER INFO BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 44,
                                backgroundColor: AppColors.primaryAccent,
                                child: CircleAvatar(
                                  radius: 41,
                                  backgroundImage: NetworkImage(user['avatarUrl'] ?? ''),
                                ),
                              ),
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: OnlineBadge(size: 15, isOnline: isOnline),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${user['displayName']} • ${user['age'] ?? 28}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '@${user['username']} • ${user['location'] ?? 'Online'}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isOnline
                                        ? AppColors.online.withOpacity(0.15)
                                        : AppColors.textMuted.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isOnline ? 'Online Now' : 'Offline',
                                    style: TextStyle(
                                      color: isOnline ? AppColors.online : AppColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // FOLLOWERS, FOLLOWING & FOLLOW ACTION ROW
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openFollowSheet('Followers', true),
                              behavior: HitTestBehavior.opaque,
                              child: GlassContainer(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                child: Column(
                                  children: [
                                    Text('$_followersCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                                    const SizedBox(height: 2),
                                    const Text('Followers', style: TextStyle(color: AppColors.secondaryAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openFollowSheet('Following', false),
                              behavior: HitTestBehavior.opaque,
                              child: GlassContainer(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                child: Column(
                                  children: [
                                    Text('$_followingCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                                    const SizedBox(height: 2),
                                    const Text('Following', style: TextStyle(color: AppColors.secondaryAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: isMe
                                ? OutlinedButton.icon(
                                    onPressed: () => context.push('/profile-builder'),
                                    icon: const Icon(Icons.edit_rounded, size: 16, color: AppColors.primaryAccent),
                                    label: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: AppColors.primaryAccent, width: 1.2),
                                      foregroundColor: AppColors.primaryAccent,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: _toggleFollow,
                                    icon: Icon(
                                      _isFollowing ? Icons.check_rounded : Icons.person_add_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      _isFollowing ? 'Following' : 'Follow',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isFollowing ? AppColors.secondaryBackground : AppColors.primaryAccent,
                                      foregroundColor: Colors.white,
                                      side: _isFollowing ? const BorderSide(color: AppColors.primaryAccent, width: 1.2) : BorderSide.none,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                  ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // BIO
                      Text(
                        user['bio'] ?? '',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.5),
                      ),

                      const SizedBox(height: 24),

                      // VOICE INTRODUCTION PLAYER
                      GlassContainer(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => setState(() => _isPlayingIntro = !_isPlayingIntro),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: const BoxDecoration(
                                      gradient: AppColors.primaryGradient,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _isPlayingIntro ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Voice Introduction', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                                      Text('${user['voiceIntroDuration'] ?? 15}s Audio • Listen to tone and vibe', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (_isPlayingIntro) ...[
                              const SizedBox(height: 16),
                              VoiceWaveformWidget(isSpeaking: true, barCount: 22, maxHeight: 40),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // INTEREST TAGS
                      const Text('Interests & Topics', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
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
                            child: Text('#$tag', style: const TextStyle(color: AppColors.primaryAccentLight, fontSize: 12, fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // CONVERSATION STARTERS
                      const Text('Conversation Starters', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 10),
                      _buildStarterCard('What is the weirdest rabbit hole you went down recently?'),
                      const SizedBox(height: 8),
                      _buildStarterCard('What track never fails to shift your state of mind?'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // BOTTOM CALL & ACTION BAR
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: AppColors.secondaryBackground,
                border: Border(top: BorderSide(color: AppColors.glassBorder)),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Text Chat Button
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
                      onPressed: () {
                        context.push('/chat/${user['id']}');
                      },
                    ),

                    // Gift Button
                    IconButton(
                      icon: const Icon(Icons.card_giftcard_rounded, color: AppColors.secondaryAccent),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (ctx) => GiftBottomSheet(
                            receiverId: user['id'],
                            receiverName: user['displayName'] ?? 'User',
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: 8),

                    // Voice Call Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ref.read(callingControllerProvider.notifier).startCall(
                                receiverId: user['id'],
                                receiverProfile: user,
                              );
                          context.push('/calling');
                        },
                        icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 20),
                        label: const Text('VOICE CALL', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarterCard(String text) {
    return GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.chat_outlined, color: AppColors.primaryAccent, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
        ],
      ),
    );
  }

  void _showSafetyOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block_rounded, color: AppColors.error),
              title: const Text('Block User', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(apiClientProvider).post('/chat/block', body: {'targetUserId': widget.userId});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User blocked.')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.white),
              title: const Text('Report Profile', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(apiClientProvider).post('/chat/report', body: {
                  'targetUserId': widget.userId,
                  'reason': 'Inappropriate content',
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted for admin review.')));
              },
            ),
          ],
        ),
      ),
    );
  }
}
