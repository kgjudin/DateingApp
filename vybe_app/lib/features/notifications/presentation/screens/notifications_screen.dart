import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../calling/presentation/calling_controller.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  StreamSubscription? _notifSub;
  final Set<String> _followedBackIds = {};

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _listenForLiveNotifications();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  void _listenForLiveNotifications() {
    final socket = ref.read(socketServiceProvider);
    _notifSub = socket.onNotificationReceived.listen((data) {
      if (!mounted) return;
      final newId = data['id'];
      if (newId != null && _notifications.any((n) => n['id'] == newId)) {
        return;
      }
      setState(() {
        _notifications.insert(0, data);
      });
    });
  }

  Future<void> _fetchNotifications() async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      setState(() {
        _notifications = [];
        _isLoading = false;
      });
      return;
    }
    try {
      final res = await ref.read(apiClientProvider).get('/notifications');
      if (res is List) {
        setState(() {
          _notifications = res;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _notifications = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchNotifications();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryAccent))
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_none_rounded, color: AppColors.textSecondary, size: 40),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No notifications yet',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'You\'ll see virtual gifts, online alerts and follows here.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primaryAccent,
                  backgroundColor: AppColors.secondaryBackground,
                  onRefresh: _fetchNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final item = _notifications[index];
                      return _buildNotificationCard(item);
                    },
                  ),
                ),
    );
  }

  Widget _buildNotificationCard(dynamic item) {
    final type = item['type']?.toString() ?? '';
    final title = item['title']?.toString() ?? 'Notification';
    final body = item['body']?.toString() ?? '';
    final createdAt = item['createdAt']?.toString() ?? '';
    final payload = (item['payload'] is Map) ? Map<String, dynamic>.from(item['payload']) : <String, dynamic>{};

    final isGift = type == 'gift_received';
    final isFriendOnline = type == 'friend_online';
    final isFollow = type == 'follow' || type == 'new_follower';

    final giftEmoji = payload['emoji'] ?? '🎁';
    final coinAmount = payload['coinAmount'];
    final targetUserId = payload['followerId']?.toString() ?? payload['userId']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        onTap: isFollow && targetUserId != null && targetUserId.isNotEmpty
            ? () => context.push('/profile/$targetUserId')
            : null,
        border: isGift
            ? Border.all(color: const Color(0xFFFFD700).withOpacity(0.5), width: 1.2)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Leading Icon or Emoji badge
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isGift
                        ? const Color(0xFFFFD700).withOpacity(0.18)
                        : isFriendOnline
                            ? AppColors.online.withOpacity(0.18)
                            : AppColors.primaryAccent.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: isGift
                      ? Text(giftEmoji, style: const TextStyle(fontSize: 22))
                      : Icon(
                          isFriendOnline
                              ? Icons.phone_in_talk_rounded
                              : isFollow
                                  ? Icons.person_add_rounded
                                  : Icons.notifications_rounded,
                          color: isFriendOnline
                              ? AppColors.online
                              : isFollow
                                  ? AppColors.secondaryAccent
                                  : AppColors.primaryAccent,
                          size: 20,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                          if (isGift && coinAmount != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFFD700), width: 1),
                              ),
                              child: Text(
                                '+$coinAmount 🪙',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Action Buttons
            if (isGift) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/wallet'),
                    icon: const Icon(Icons.account_balance_wallet_rounded, size: 14, color: Color(0xFFFFD700)),
                    label: const Text('View in Wallet', style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFFD700)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ] else if (isFriendOnline && payload['userId'] != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      ref.read(callingControllerProvider.notifier).startCall(
                            receiverId: payload['userId'],
                            receiverProfile: {
                              'displayName': payload['displayName'] ?? 'Friend',
                              'avatarUrl': payload['avatarUrl'],
                            },
                          );
                      context.push('/calling');
                    },
                    icon: const Icon(Icons.phone_in_talk_rounded, size: 14, color: Colors.white),
                    label: const Text('Call Friend', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.online,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ] else if (isFollow && targetUserId != null && targetUserId.isNotEmpty) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final isFollowedBack = _followedBackIds.contains(targetUserId);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => context.push('/profile/$targetUserId'),
                      icon: const Icon(Icons.person_rounded, size: 14, color: AppColors.secondaryAccent),
                      label: const Text('View Profile', style: TextStyle(color: AppColors.secondaryAccent, fontSize: 12, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.secondaryAccent),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (isFollowedBack) {
                          context.push('/profile/$targetUserId');
                          return;
                        }
                        setState(() {
                          _followedBackIds.add(targetUserId);
                        });
                        try {
                          await ref.read(apiClientProvider).post('/follow/toggle', body: {
                            'targetUserId': targetUserId,
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Followed back successfully! 🎉'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            setState(() {
                              _followedBackIds.remove(targetUserId);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not follow back: $e')),
                            );
                          }
                        }
                      },
                      icon: Icon(
                        isFollowedBack ? Icons.check_rounded : Icons.person_add_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      label: Text(
                        isFollowedBack ? 'Following' : 'Follow Back',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFollowedBack ? AppColors.secondaryBackground : AppColors.primaryAccent,
                        foregroundColor: Colors.white,
                        side: isFollowedBack ? const BorderSide(color: AppColors.primaryAccent, width: 1.2) : BorderSide.none,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
