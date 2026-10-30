import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/auth_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;

  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  Future<void> _fetchMessages() async {
    try {
      final res = await ref.read(apiClientProvider).get('/chat/${widget.otherUserId}/messages');
      if (res is List && res.isNotEmpty) {
        setState(() {
          _messages.addAll(List<Map<String, dynamic>>.from(res));
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    setState(() {
      _isLoading = false;
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final myId = ref.read(authControllerProvider).user?['id'] ?? '';
    final newMsg = {
      'id': 'm_${DateTime.now().millisecondsSinceEpoch}',
      'senderId': myId,
      'content': text,
      'createdAt': 'Just now',
    };

    setState(() {
      _messages.add(newMsg);
      _messageController.clear();
    });

    ref.read(apiClientProvider).post('/chat/send', body: {
      'receiverId': widget.otherUserId,
      'content': text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(authControllerProvider).user?['id'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(
                widget.otherUserAvatar ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.otherUserName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const Text('Online • Voice Verified', style: TextStyle(color: AppColors.online, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryAccent))
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet. Send a greeting to start chatting!',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['senderId'] == myId;

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      gradient: isMe ? AppColors.primaryGradient : null,
                      color: isMe ? null : AppColors.secondaryBackground,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                      border: isMe ? null : Border.all(color: AppColors.glassBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['content'] ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg['createdAt'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white70 : AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Message Input Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppColors.secondaryBackground,
              border: Border(top: BorderSide(color: AppColors.glassBorder)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Say something nice...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        fillColor: AppColors.cardBackground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
