import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../calling/presentation/calling_controller.dart';
import '../../../wallet/presentation/widgets/gift_sheet.dart';

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
  bool _isOtherUserOnline = false;
  bool _isFollowing = false;
  StreamSubscription? _presenceSub;
  StreamSubscription? _giftSub;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _fetchOtherUserProfile();
    _presenceSub = ref.read(socketServiceProvider).onPresenceChanged.listen((data) {
      if (data['userId'] == widget.otherUserId && mounted) {
        setState(() {
          _isOtherUserOnline = data['status'] == 'online';
        });
      }
    });

    _giftSub = ref.read(socketServiceProvider).onGiftReceived.listen((data) {
      if (!mounted) return;
      final myId = ref.read(authControllerProvider).user?['id'];
      final receiverId = data['receiverId'];
      final senderId = data['senderId'];

      if (senderId == widget.otherUserId && (receiverId == null || receiverId == myId)) {
        final giftName = data['giftName'] ?? 'Virtual Gift';
        final emoji = data['emoji'] ?? '🎁';
        final coins = data['coinAmount'] ?? 0;

        if (data['receiverNewBalance'] != null) {
          ref.read(authControllerProvider.notifier).updateCoinBalance(data['receiverNewBalance'] as int);
        } else {
          final cur = ref.read(authControllerProvider).coinBalance;
          ref.read(authControllerProvider.notifier).updateCoinBalance(cur + (coins as int));
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.secondaryBackground,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFFFD700)),
            ),
            content: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.otherUserName} sent you a $giftName! (+$coins Coins)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    _giftSub?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _fetchOtherUserProfile() async {
    try {
      final res = await ref.read(apiClientProvider).get('/profile/${widget.otherUserId}');
      if (res is Map && mounted) {
        setState(() {
          _isOtherUserOnline = res['status'] == 'online' || res['presence'] == 'online';
          _isFollowing = res['isFollowing'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final nextState = !_isFollowing;
    setState(() => _isFollowing = nextState);
    try {
      final res = await ref.read(apiClientProvider).post('/follow/toggle', body: {
        'targetUserId': widget.otherUserId,
      });
      if (res is Map && mounted) {
        setState(() => _isFollowing = res['isFollowing'] == true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.cardBackground,
            content: Text(
              _isFollowing
                  ? 'Followed ${widget.otherUserName}! They received a notification.'
                  : 'Unfollowed ${widget.otherUserName}.',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isFollowing = !nextState);
    }
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
        title: GestureDetector(
          onTap: () => context.push('/profile/${widget.otherUserId}'),
          behavior: HitTestBehavior.opaque,
          child: Row(
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
                  Text(
                    _isOtherUserOnline ? 'Online • Voice Verified' : 'Offline • Voice Verified',
                    style: TextStyle(
                      color: _isOtherUserOnline ? AppColors.online : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFollowing ? Icons.check_circle_rounded : Icons.person_add_alt_1_rounded,
              color: _isFollowing ? AppColors.online : Colors.white,
            ),
            tooltip: _isFollowing ? 'Following' : 'Follow',
            onPressed: _toggleFollow,
          ),
          IconButton(
            icon: const Icon(Icons.card_giftcard_rounded, color: AppColors.secondaryAccent),
            tooltip: 'Send Gift',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => GiftBottomSheet(
                  receiverId: widget.otherUserId,
                  receiverName: widget.otherUserName,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.primaryAccent),
            onPressed: () {
              ref.read(callingControllerProvider.notifier).startCall(
                    receiverId: widget.otherUserId,
                    receiverProfile: {
                      'displayName': widget.otherUserName,
                      'avatarUrl': widget.otherUserAvatar,
                    },
                  );
              context.push('/calling');
            },
          ),
          const SizedBox(width: 8),
        ],
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
