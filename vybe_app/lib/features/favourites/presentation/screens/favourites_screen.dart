import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/online_badge.dart';
import '../../../calling/presentation/calling_controller.dart';

class FavouritesScreen extends ConsumerStatefulWidget {
  const FavouritesScreen({super.key});

  @override
  ConsumerState<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends ConsumerState<FavouritesScreen> {
  List<dynamic> _favourites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFavourites();
  }

  Future<void> _fetchFavourites() async {
    try {
      final res = await ref.read(apiClientProvider).get('/favourites');
      if (res is List) {
        setState(() {
          _favourites = res;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    // Real empty state
    setState(() {
      _favourites = [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('Favourites', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryAccent))
          : _favourites.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: _favourites.length,
                  itemBuilder: (context, index) {
                    final user = _favourites[index];
                    final isOnline = user['status'] == 'online';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(14),
                        onTap: () => context.push('/profile/${user['id']}'),
                        child: Row(
                          children: [
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
                                    isOnline ? 'Online now • Ready to talk' : 'Offline',
                                    style: TextStyle(
                                      color: isOnline ? AppColors.online : AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.cardBackground, shape: BoxShape.circle),
            child: const Icon(Icons.favorite_border_rounded, color: AppColors.textMuted, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('No favourites saved', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 6),
          const Text('Tap the heart icon on any profile to stay notified when they come online.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}
