import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    try {
      final res = await ref.read(apiClientProvider).get('/notifications');
      if (res is List && res.isNotEmpty) {
        setState(() {
          _notifications = res;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    // Mock initial notifications
    setState(() {
      _notifications = [
        {
          'id': 'n1',
          'type': 'gift_received',
          'title': 'Gift Received! 🎁',
          'body': 'Marcus Chen sent you a Heart (🪙 50 coins) in Midnight Philosophers.',
          'createdAt': '12 mins ago',
          'icon': Icons.favorite_rounded,
          'color': AppColors.secondaryAccent,
        },
        {
          'id': 'n2',
          'type': 'favourite_online',
          'title': 'Favourite User Online',
          'body': 'Sophia Ray is now online on the voice radar. Start a conversation!',
          'createdAt': '1 hour ago',
          'icon': Icons.radar_rounded,
          'color': AppColors.online,
        },
        {
          'id': 'n3',
          'type': 'room_live',
          'title': 'Live Stage Started',
          'body': 'Future & Tech Minds started a live audio stage: "Will AI Replace Social Media?".',
          'createdAt': '3 hours ago',
          'icon': Icons.mic_rounded,
          'color': AppColors.primaryAccent,
        },
      ];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryAccent))
          : _notifications.isEmpty
              ? const Center(child: Text('No notifications yet', style: TextStyle(color: AppColors.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final item = _notifications[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (item['color'] as Color? ?? AppColors.primaryAccent).withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                (item['icon'] as IconData? ?? Icons.notifications_rounded),
                                color: item['color'] as Color? ?? AppColors.primaryAccent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['title'] ?? 'Notification',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['body'] ?? '',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item['createdAt'] ?? '',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                  ),
                                ],
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
}
