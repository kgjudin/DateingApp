import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _users = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ref.read(apiClientProvider).get('/admin/users');
      if (res is Map && res['data'] is List) {
        final list = (res['data'] as List).map((u) => Map<String, dynamic>.from(u)).toList();
        if (mounted) {
          setState(() {
            _users = list;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Unexpected response format';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_searchQuery.trim().isEmpty) return _users;
    final q = _searchQuery.toLowerCase().trim();
    return _users.where((u) {
      final name = (u['displayName'] ?? '').toString().toLowerCase();
      final username = (u['username'] ?? '').toString().toLowerCase();
      final id = (u['id'] ?? '').toString().toLowerCase();
      return name.contains(q) || username.contains(q) || id.contains(q);
    }).toList();
  }

  void _showAddCoinsDialog(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final userName = user['displayName']?.toString() ?? 'User';
    final currentCoins = user['coinBalance'] ?? 0;
    final controller = TextEditingController(text: '100');
    int selectedChip = 100;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.secondaryBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.monetization_on_rounded, color: AppColors.primaryAccent, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add Coins to $userName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                            Text('Current balance: 🪙 $currentCoins coins', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Select Quick Amount', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [50, 100, 250, 500, 1000].map((amt) {
                      final isSel = selectedChip == amt;
                      return ChoiceChip(
                        label: Text('+$amt 🪙', style: TextStyle(color: isSel ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w700)),
                        selected: isSel,
                        selectedColor: AppColors.primaryAccent,
                        backgroundColor: AppColors.cardBackground,
                        onSelected: (selected) {
                          if (selected) {
                            setSheetState(() {
                              selectedChip = amt;
                              controller.text = amt.toString();
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Custom Coin Amount',
                      labelStyle: const TextStyle(color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.add_circle_outline, color: AppColors.primaryAccent),
                      filled: true,
                      fillColor: AppColors.cardBackground,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val) ?? 0;
                      setSheetState(() {
                        selectedChip = parsed;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      final amt = int.tryParse(controller.text) ?? 0;
                      if (amt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid coin amount.')),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      await _executeAddCoins(userId, userName, amt);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Confirm & Credit Coins', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _executeAddCoins(String userId, String userName, int amount) async {
    try {
      final res = await ref.read(apiClientProvider).post('/admin/users/$userId/coins', body: {
        'amount': amount,
        'description': 'Admin Grant: Added $amount coins',
      });
      if (res is Map && res['success'] == true) {
        final newBal = res['data']?['newBalance'] ?? 0;
        setState(() {
          final idx = _users.findIndex((u) => u['id'] == userId);
          if (idx >= 0) {
            _users[idx]['coinBalance'] = newBal;
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.cardBackground,
              content: Text('🪙 Added $amount coins to $userName! New balance: $newBal', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.error, content: Text('Failed to add coins: $e')),
        );
      }
    }
  }

  void _showBlockDialog(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final userName = user['displayName']?.toString() ?? 'User';
    final isBlocked = user['isBlocked'] == true;
    final reasonController = TextEditingController(text: isBlocked ? '' : 'Violated community guidelines.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.secondaryBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(isBlocked ? Icons.lock_open_rounded : Icons.block_rounded, color: isBlocked ? AppColors.online : AppColors.error),
            const SizedBox(width: 10),
            Text(isBlocked ? 'Unblock $userName?' : 'Block $userName?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isBlocked
                  ? 'This will restore $userName\'s access to voice calls and group audio rooms.'
                  : 'Blocking will immediately prevent $userName from starting or receiving voice calls and revoke access.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            if (!isBlocked) ...[
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Block Reason',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.cardBackground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _executeToggleBlock(userId, userName, !isBlocked, reasonController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isBlocked ? AppColors.online : AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(isBlocked ? 'Unblock User' : 'Block User', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeToggleBlock(String userId, String userName, bool blockTarget, String reason) async {
    try {
      final res = await ref.read(apiClientProvider).post('/admin/users/$userId/block', body: {
        'isBlocked': blockTarget,
        'reason': reason,
      });
      if (res is Map && res['success'] == true) {
        setState(() {
          final idx = _users.findIndex((u) => u['id'] == userId);
          if (idx >= 0) {
            _users[idx]['isBlocked'] = blockTarget;
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.cardBackground,
              content: Text(blockTarget ? '🚫 $userName has been blocked.' : '🟢 $userName has been unblocked.', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.error, content: Text('Failed to update block status: $e')),
        );
      }
    }
  }

  void _showWarningDialog(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final userName = user['displayName']?.toString() ?? 'User';
    final presets = [
      'Inappropriate language or verbal abuse during voice calls.',
      'Please adhere to VYBE community guidelines and respect other speakers.',
      'Spamming voice calls or harassing other community members.',
      'Inappropriate profile content or impersonation.',
    ];
    final controller = TextEditingController(text: presets[0]);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.secondaryBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Send Official Warning to $userName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                            const Text('The user will receive an in-app alert immediately', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Common Presets', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...presets.map((preset) => InkWell(
                        onTap: () {
                          setSheetState(() {
                            controller.text = preset;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: controller.text == preset ? AppColors.primaryAccent.withValues(alpha: 0.15) : AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: controller.text == preset ? AppColors.primaryAccent : Colors.transparent),
                          ),
                          child: Text(preset, style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      )),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Warning Message',
                      labelStyle: const TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.cardBackground,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final msg = controller.text.trim();
                      if (msg.isEmpty) return;
                      Navigator.pop(ctx);
                      await _executeSendWarning(userId, userName, msg);
                    },
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send Warning Alert', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  Future<void> _executeSendWarning(String userId, String userName, String message) async {
    try {
      final res = await ref.read(apiClientProvider).post('/admin/users/$userId/warning', body: {
        'message': message,
      });
      if (res is Map && res['success'] == true) {
        setState(() {
          final idx = _users.findIndex((u) => u['id'] == userId);
          if (idx >= 0) {
            final cur = (_users[idx]['warningCount'] as int?) ?? 0;
            _users[idx]['warningCount'] = cur + 1;
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.cardBackground,
              content: Text('⚠️ Official warning sent to $userName!', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.error, content: Text('Failed to send warning: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredUsers;
    final totalCount = _users.length;
    final onlineCount = _users.where((u) => u['isOnline'] == true).length;
    final blockedCount = _users.where((u) => u['isBlocked'] == true).length;

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('⚡ Admin Console', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh Roster',
            onPressed: _fetchUsers,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryAccent))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                      const SizedBox(height: 12),
                      Text('Error loading users:\n$_errorMessage', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _fetchUsers, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primaryAccent,
                  onRefresh: _fetchUsers,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stats Metrics Row
                        Row(
                          children: [
                            _buildStatCard('Total Users', totalCount.toString(), AppColors.primaryAccent),
                            const SizedBox(width: 10),
                            _buildStatCard('Online', onlineCount.toString(), AppColors.online),
                            const SizedBox(width: 10),
                            _buildStatCard('Blocked', blockedCount.toString(), AppColors.error),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Search Bar
                        TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search users by name, @username or ID...',
                            hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryAccent),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: Colors.white70),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppColors.secondaryBackground,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                          ),
                          onChanged: (val) => setState(() => _searchQuery = val),
                        ),
                        const SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('User Roster (${filtered.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                            const Text('Actions: Coins • Block • Warn', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 12),

                        if (filtered.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(32),
                            alignment: Alignment.center,
                            child: const Text('No matching users found.', style: TextStyle(color: AppColors.textSecondary)),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final u = filtered[index];
                              final isBlocked = u['isBlocked'] == true;
                              final isOnline = u['isOnline'] == true;
                              final coins = u['coinBalance'] ?? 100;
                              final warns = u['warningCount'] ?? 0;
                              final avatar = u['avatarUrl'] ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500';

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBackground,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isBlocked ? AppColors.error.withValues(alpha: 0.5) : AppColors.glassBorder,
                                    width: isBlocked ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // User Header Row
                                    Row(
                                      children: [
                                        Stack(
                                          children: [
                                            CircleAvatar(
                                              radius: 24,
                                              backgroundImage: NetworkImage(avatar),
                                            ),
                                            Positioned(
                                              bottom: 0,
                                              right: 0,
                                              child: Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: isOnline ? AppColors.online : Colors.grey,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.black, width: 2),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      u['displayName'] ?? 'Vybe User',
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  if (isBlocked)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.error.withValues(alpha: 0.2),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: AppColors.error),
                                                      ),
                                                      child: const Text('BLOCKED', style: TextStyle(color: AppColors.error, fontSize: 9, fontWeight: FontWeight.w800)),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text('@${u['username'] ?? 'vyber'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                        // Coins & Warnings indicators
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text('🪙 $coins', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w800, fontSize: 13)),
                                            ),
                                            if (warns > 0) ...[
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text('⚠️ $warns warns', style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w700)),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),
                                    const Divider(color: AppColors.glassBorder, height: 1),
                                    const SizedBox(height: 10),

                                    // Action Buttons Row
                                    Row(
                                      children: [
                                        // 🪙 Add Coins Button
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _showAddCoinsDialog(u),
                                            icon: const Icon(Icons.add_circle_outline, size: 14),
                                            label: const Text('+ Coins', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: AppColors.primaryAccentLight,
                                              side: const BorderSide(color: AppColors.primaryAccent),
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 🚫 Block / Unblock Button
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _showBlockDialog(u),
                                            icon: Icon(isBlocked ? Icons.lock_open_rounded : Icons.block_rounded, size: 14),
                                            label: Text(isBlocked ? 'Unblock' : 'Block', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: isBlocked ? AppColors.online : AppColors.error,
                                              side: BorderSide(color: isBlocked ? AppColors.online : AppColors.error),
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // ⚠️ Warn Button
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _showWarningDialog(u),
                                            icon: const Icon(Icons.warning_amber_rounded, size: 14),
                                            label: const Text('Warn', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.amber,
                                              side: const BorderSide(color: Colors.amber),
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.secondaryBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

extension ListExt<T> on List<T> {
  int findIndex(bool Function(T) test) {
    for (int i = 0; i < length; i++) {
      if (test(this[i])) return i;
    }
    return -1;
  }
}
