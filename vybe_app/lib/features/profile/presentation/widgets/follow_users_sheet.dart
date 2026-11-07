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

class FollowUsersSheet extends ConsumerStatefulWidget {
  final String title;
  final String userId;
  final bool isFollowers;

  const FollowUsersSheet({
    super.key,
    required this.title,
    required this.userId,
    required this.isFollowers,
  });

  @override
  ConsumerState<FollowUsersSheet> createState() => _FollowUsersSheetState();
}

class _FollowUsersSheetState extends ConsumerState<FollowUsersSheet> {
  List<dynamic> _users = [];
  bool _isLoading = true;
  StreamSubscription? _presenceSub;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _presenceSub = ref.read(socketServiceProvider).onPresenceChanged.listen((data) {
      final uId = data['userId']?.toString().toLowerCase();
      final status = data['status']?.toString().toLowerCase();
      final isOnline = data['isOnline'] == true || status == 'online' || status == 'in_call' || status == 'in_room';

      if (uId != null && status != null && mounted) {
        setState(() {
          for (int i = 0; i < _users.length; i++) {
            if (_users[i]['id']?.toString().toLowerCase() == uId) {
              _users[i] = Map<String, dynamic>.from(_users[i])
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

  Future<void> _fetchUsers() async {
    try {
      final endpoint = widget.isFollowers
          ? '/follow/followers/${widget.userId}'
          : '/follow/following/${widget.userId}';
      final res = await ref.read(apiClientProvider).get(endpoint);
      if (res is List && mounted) {
        setState(() {
          _users = res;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _users = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow(String targetUserId, int index) async {
    try {
      final res = await ref.read(apiClientProvider).post('/follow/toggle', body: {
        'targetUserId': targetUserId,
      });

      if (res is Map && mounted) {
        final isFollowing = res['isFollowing'] == true;
        setState(() {
          _users[index] = Map<String, dynamic>.from(_users[index])..['isFollowing'] = isFollowing;
        });

        final targetName = _users[index]['displayName'] ?? 'user';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.cardBackground,
            content: Text(
              isFollowing
                  ? 'Followed $targetName! They received a notification.'
                  : 'Unfollowed $targetName.',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update follow: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.read(authControllerProvider).user?['id'];

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.secondaryBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted.withOpacity(0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Sheet Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.title} (${_users.length})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(color: AppColors.glassBorder),
          const SizedBox(height: 10),

          // User list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryAccent))
                : _users.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              widget.isFollowers ? Icons.people_outline_rounded : Icons.person_add_disabled_rounded,
                              size: 48,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.isFollowers ? 'No followers yet' : 'Not following anyone yet',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final status = user['status']?.toString().toLowerCase();
                          final isOnline = user['isOnline'] == true || status == 'online' || status == 'in_call' || status == 'in_room';
                          final isFollowing = user['isFollowing'] == true;
                          final isMe = user['id'] == currentUserId;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: GlassContainer(
                              padding: const EdgeInsets.all(12),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/profile/${user['id']}');
                              },
                              child: Row(
                                children: [
                                  // Avatar with Online Badge
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundImage: NetworkImage(
                                          user['avatarUrl'] ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: OnlineBadge(size: 11, isOnline: isOnline),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),

                                  // Name & Online state
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user['displayName'] ?? 'Vybe User',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              '@${user['username'] ?? 'vyber'}',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              isOnline ? '• Online' : '• Offline',
                                              style: TextStyle(
                                                color: isOnline ? AppColors.online : AppColors.textMuted,
                                                fontSize: 11,
                                                fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Follow Button (if not viewing self)
                                  if (!isMe) ...[
                                    OutlinedButton(
                                      onPressed: () => _toggleFollow(user['id'], index),
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
                                      icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.primaryAccent, size: 20),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        ref.read(callingControllerProvider.notifier).startCall(
                                              receiverId: user['id'],
                                              receiverProfile: Map<String, dynamic>.from(user),
                                            );
                                        context.push('/calling');
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
