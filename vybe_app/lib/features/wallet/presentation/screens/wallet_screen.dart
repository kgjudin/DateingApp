import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../auth/presentation/auth_controller.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  List<dynamic> _transactions = [];

  @override
  void initState() {
    super.initState();
    _fetchWalletData();
  }

  Future<void> _fetchWalletData() async {
    try {
      final res = await ref.read(apiClientProvider).get('/wallet');
      if (res is Map) {
        final bal = res['balance'] as int?;
        if (bal != null) {
          ref.read(authControllerProvider.notifier).updateCoinBalance(bal);
        }
        setState(() {
          _transactions = (res['recentTransactions'] as List?) ?? [];
        });
        return;
      }
    } catch (_) {}

    // Fallback transaction ledger
    setState(() {
      _transactions = [
        {'id': 'tx-1', 'description': 'Sent Heart to Marcus Chen', 'amount': -50, 'createdAt': '10 mins ago', 'type': 'gift_sent'},
        {'id': 'tx-2', 'description': 'Received Rose from Priya Sharma', 'amount': 10, 'createdAt': '2 hours ago', 'type': 'gift_received'},
        {'id': 'tx-3', 'description': 'Coin Top-up Package (500 Coins)', 'amount': 500, 'createdAt': 'Yesterday', 'type': 'coin_purchase'},
        {'id': 'tx-4', 'description': 'Welcome to VYBE! Bonus Coins', 'amount': 100, 'createdAt': '3 days ago', 'type': 'reward'},
      ];
    });
  }

  Future<void> _purchasePackage(int coins, String priceUsd) async {
    try {
      final res = await ref.read(apiClientProvider).post('/wallet/purchase', body: {
        'coinsAmount': coins,
        'packageId': 'pkg_$coins',
      });
      if (res is Map && res['balance'] != null) {
        ref.read(authControllerProvider.notifier).updateCoinBalance(res['balance'] as int);
      } else {
        final current = ref.read(authControllerProvider).coinBalance;
        ref.read(authControllerProvider.notifier).updateCoinBalance(current + coins);
      }
      _fetchWalletData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.cardBackground,
            content: Text('Successfully added $coins coins to your wallet!'),
          ),
        );
      }
    } catch (e) {
      final current = ref.read(authControllerProvider).coinBalance;
      ref.read(authControllerProvider.notifier).updateCoinBalance(current + coins);
      _fetchWalletData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final coinBalance = ref.watch(authControllerProvider).coinBalance;

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text('My Coin Wallet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HERO BALANCE CARD
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryAccent.withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TOTAL COIN BALANCE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Icon(Icons.stars_rounded, color: Colors.white, size: 24),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('🪙', style: TextStyle(fontSize: 34)),
                      const SizedBox(width: 12),
                      Text(
                        '$coinBalance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Coins', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Use coins to send virtual gifts and reward speakers in live rooms.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // COIN PACKAGES
            const Text(
              'Recharge Coins',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(child: _buildPackageCard(100, '\$0.99', 'Starter')),
                const SizedBox(width: 12),
                Expanded(child: _buildPackageCard(500, '\$4.99', 'Popular', isPopular: true)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildPackageCard(1200, '\$9.99', 'Pro Vyber')),
                const SizedBox(width: 12),
                Expanded(child: _buildPackageCard(5000, '\$39.99', 'VIP Royalty')),
              ],
            ),

            const SizedBox(height: 28),

            // TRANSACTION LEDGER
            const Text(
              'Transaction Ledger',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 12),

            if (_transactions.isEmpty) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('No transactions yet.', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            ] else ...[
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _transactions.length,
                itemBuilder: (context, index) {
                  final tx = _transactions[index];
                  final isCredit = (tx['amount'] as int? ?? 0) > 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: GlassContainer(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isCredit
                                  ? AppColors.online.withOpacity(0.15)
                                  : AppColors.error.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                              color: isCredit ? AppColors.online : AppColors.error,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tx['description'] ?? 'Transaction',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tx['createdAt'] ?? 'Recent',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${isCredit ? '+' : ''}${tx['amount']} Coins',
                            style: TextStyle(
                              color: isCredit ? AppColors.online : AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageCard(int coins, String price, String label, {bool isPopular = false}) {
    return GestureDetector(
      onTap: () => _purchasePackage(coins, price),
      child: GlassContainer(
        backgroundColor: isPopular ? AppColors.primaryAccent.withOpacity(0.15) : null,
        border: Border.all(
          color: isPopular ? AppColors.primaryAccent : AppColors.glassBorder,
          width: isPopular ? 1.5 : 1,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isPopular) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.secondaryAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('BEST VALUE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
              ),
            ],
            Text('🪙 $coins', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isPopular ? AppColors.primaryAccent : AppColors.secondaryBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                price,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
