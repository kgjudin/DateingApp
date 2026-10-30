import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../rooms_controller.dart';

class RoomsScreen extends ConsumerWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomState = ref.watch(roomsControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('Live Voice Rooms', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryAccent, size: 28),
            onPressed: () => _showCreateRoomDialog(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(roomsControllerProvider.notifier).fetchRoomsAndGroups(),
        color: AppColors.primaryAccent,
        backgroundColor: AppColors.secondaryBackground,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Banner
              GlassContainer(
                padding: const EdgeInsets.all(18),
                backgroundColor: AppColors.primaryAccent.withOpacity(0.12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Clubhouse-Style Stages', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                          SizedBox(height: 2),
                          Text('Join spontaneous live group audio rooms. Listen or raise your hand to speak.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text('Happening Right Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 14),

              // Live Audio Rooms Cards
              if (roomState.liveRooms.isEmpty) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('No active live rooms. Be the first to start one!', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
              ] else ...[
                ...roomState.liveRooms.map((room) => _buildLiveRoomCard(context, ref, room)),
              ],

              const SizedBox(height: 24),
              const Text('Popular Communities', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 14),

              // Groups horizontal preview
              _buildGroupsGrid(context, roomState.groups),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveRoomCard(BuildContext context, WidgetRef ref, Map<String, dynamic> room) {
    final speakers = (room['speakers'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GlassContainer(
        padding: const EdgeInsets.all(18),
        onTap: () async {
          await ref.read(roomsControllerProvider.notifier).joinLiveRoom(room);
          if (context.mounted) {
            context.push('/room/${room['id']}');
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group & Topic Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.groups_rounded, color: AppColors.primaryAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      room['groupName'] ?? 'Public Room',
                      style: const TextStyle(color: AppColors.primaryAccentLight, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.secondaryAccent.withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.fiber_manual_record_rounded, color: AppColors.secondaryAccent, size: 10),
                      SizedBox(width: 4),
                      Text('LIVE', style: TextStyle(color: AppColors.secondaryAccent, fontWeight: FontWeight.w800, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Room Title
            Text(
              room['title'] ?? 'Voice Chat',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, height: 1.3),
            ),

            const SizedBox(height: 16),

            // Speakers Avatars Row
            Row(
              children: [
                // Overlapping avatars
                SizedBox(
                  height: 44,
                  width: (speakers.length.clamp(1, 4) * 28.0) + 20,
                  child: Stack(
                    children: List.generate(
                      speakers.length.clamp(0, 4),
                      (i) => Positioned(
                        left: i * 26.0,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.cardBackground,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundImage: NetworkImage(
                              speakers[i]['avatarUrl'] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        speakers.map((s) => s['name'] ?? 'Speaker').take(2).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        'Hosted by ${room['hostName'] ?? 'Vybe Host'}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // Audience Count
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.headphones_rounded, color: AppColors.textMuted, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${room['listenersCount'] ?? 1}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupsGrid(BuildContext context, List<dynamic> groups) {
    if (groups.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cardBackground.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: const Text(
          'No communities created yet. Create a group to connect with people!',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: groups.map((g) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildGroupTile(
            g['name'] ?? 'Community',
            '${g['memberCount'] ?? 1} members • ${g['description'] ?? ''}',
            g['category'] ?? 'General',
            Icons.groups_rounded,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGroupTile(String name, String sub, String category, IconData icon) {
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.secondaryBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primaryAccent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primaryAccent),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Join', style: TextStyle(color: AppColors.primaryAccentLight, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showCreateRoomDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final topicController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Start a Live Voice Room',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 6),
            const Text(
              'Anyone on VYBE can tune in and request to speak.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'What do you want to talk about? (e.g. Indie Music)',
                prefixIcon: Icon(Icons.title_rounded, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: topicController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Topic / Tag (e.g. Music, Tech)',
                prefixIcon: Icon(Icons.tag_rounded, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final roomTitle = titleController.text.trim().isEmpty ? 'Open Voice Stage' : titleController.text.trim();
                  final roomTopic = topicController.text.trim().isEmpty ? 'General' : topicController.text.trim();

                  final createdRoom = await ref.read(roomsControllerProvider.notifier).createRoom(
                        title: roomTitle,
                        topic: roomTopic,
                      );

                  if (context.mounted) {
                    Navigator.pop(ctx);
                    if (createdRoom != null) {
                      context.push('/room/${createdRoom['id']}');
                    }
                  }
                },
                child: const Text('Go Live Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
