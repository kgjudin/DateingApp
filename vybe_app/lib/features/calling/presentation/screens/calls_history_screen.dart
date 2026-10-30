import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../calling_controller.dart';

class CallsHistoryScreen extends ConsumerStatefulWidget {
  const CallsHistoryScreen({super.key});

  @override
  ConsumerState<CallsHistoryScreen> createState() => _CallsHistoryScreenState();
}

class _CallsHistoryScreenState extends ConsumerState<CallsHistoryScreen> {
  List<dynamic> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final res = await ref.read(apiClientProvider).get('/calls/history');
      if (res is List) {
        setState(() {
          _history = res;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    // No mock fallback: maintain real state
    setState(() {
      _history = [];
      _isLoading = false;
    });
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return 'Missed';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
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

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(14),
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
                                    isIncoming ? (item['callerName'] ?? 'Caller') : (item['receiverName'] ?? 'User'),
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
                            IconButton(
                              icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.primaryAccent),
                              onPressed: () {
                                final targetId = item['receiverId'] ?? item['callerId'] ?? '';
                                ref.read(callingControllerProvider.notifier).startCall(
                                      receiverId: targetId,
                                      receiverProfile: {
                                        'displayName': item['callerName'] ?? item['receiverName'] ?? 'Vybe User',
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
            decoration: BoxDecoration(
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
