import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../calling_controller.dart';

class CallsHistoryScreen extends ConsumerStatefulWidget {
  const CallsHistoryScreen({super.key});

  @override
  ConsumerState<CallsHistoryScreen> createState() => _CallsHistoryScreenState();
}

class _CallsHistoryScreenState extends ConsumerState<CallsHistoryScreen> {
  List<dynamic> _history = [];
  Set<String> _followedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      setState(() {
        _history = [];
        _isLoading = false;
      });
      return;
    }
    try {
      final res = await ref.read(apiClientProvider).get('/calls/history');
      final followingRes = await ref.read(apiClientProvider).get('/follow/following');

      final followed = <String>{};
      if (followingRes is List) {
        for (final item in followingRes) {
          if (item is Map && item['id'] != null) {
            followed.add(item['id'].toString());
          }
        }
      }

      if (res is List && mounted) {
        setState(() {
          _history = res;
          _followedIds = followed;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _history = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow(String targetUserId, String friendName) async {
    final isCurrentlyFollowed = _followedIds.contains(targetUserId);
    setState(() {
      if (isCurrentlyFollowed) {
        _followedIds.remove(targetUserId);
      } else {
        _followedIds.add(targetUserId);
      }
    });

    try {
      final res = await ref.read(apiClientProvider).post('/follow/toggle', body: {
        'targetUserId': targetUserId,
      });

      if (res is Map && mounted) {
        final isFollowing = res['isFollowing'] == true;
        setState(() {
          if (isFollowing) {
            _followedIds.add(targetUserId);
          } else {
            _followedIds.remove(targetUserId);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.cardBackground,
            content: Text(
              isFollowing
                  ? 'Followed $friendName! They received a notification.'
                  : 'Unfollowed $friendName.',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (isCurrentlyFollowed) {
            _followedIds.add(targetUserId);
          } else {
            _followedIds.remove(targetUserId);
          }
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return 'Missed';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.read(authControllerProvider).user?['id'];

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('Call History', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryAccent))
          : _history.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    final isMissed = item['status'] == 'missed';
                    final isIncoming = item['direction'] == 'incoming';
                    final friendId = isIncoming ? item['callerId'] : item['receiverId'];
                    final friendName = isIncoming ? (item['callerName'] ?? 'Caller') : (item['receiverName'] ?? 'User');
                    final isFollowed = _followedIds.contains(friendId);
                    final isSelf = friendId == myId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(14),
                        onTap: () {
                          if (friendId != null && !isSelf) {
                            context.push('/profile/$friendId');
                          }
                        },
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundImage: NetworkImage(
                                item['avatarUrl'] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    friendName,
                                    style: TextStyle(
                                      color: isMissed ? AppColors.error : Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        isMissed
                                            ? Icons.call_missed_rounded
                                            : (isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded),
                                        size: 14,
                                        color: isMissed ? AppColors.error : AppColors.primaryAccent,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${item['createdAt'] ?? 'Recent'} • ${_formatDuration(item['duration'] ?? 0)}',
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Follow Called Friend Button
                            if (!isSelf && friendId != null) ...[
                              OutlinedButton.icon(
                                onPressed: () => _toggleFollow(friendId, friendName),
                                icon: Icon(
                                  isFollowed ? Icons.check_rounded : Icons.person_add_rounded,
                                  size: 13,
                                  color: isFollowed ? AppColors.textSecondary : AppColors.primaryAccent,
                                ),
                                label: Text(
                                  isFollowed ? 'Following' : 'Follow',
                                  style: TextStyle(
                                    color: isFollowed ? AppColors.textSecondary : AppColors.primaryAccentLight,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isFollowed ? Colors.transparent : AppColors.primaryAccent.withOpacity(0.12),
                                  side: BorderSide(
                                    color: isFollowed ? AppColors.glassBorder : AppColors.primaryAccent,
                                    width: 1,
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],

                            // Call Back Button
                            IconButton(
                              icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.primaryAccent),
                              onPressed: () {
                                final targetId = item['receiverId'] ?? item['callerId'] ?? '';
                                ref.read(callingControllerProvider.notifier).startCall(
                                      receiverId: targetId,
                                      receiverProfile: {
                                        'displayName': friendName,
                                        'avatarUrl': item['avatarUrl'],
                                      },
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.cardBackground,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_missed_rounded, color: AppColors.textMuted, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('No calls yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 6),
          const Text('Connect with people on the discovery feed to start a call.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}
