"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WalletController = exports.GiftController = exports.WalletService = void 0;
const supabaseClient_1 = require("../integrations/supabase/supabaseClient");
const socketHandler_1 = require("../sockets/socketHandler");
class WalletService {
    /**
     * Retrieves or initializes a user's wallet with multi-tier persistence.
     * Priority: LocalDbStore -> Supabase DB -> Supabase Auth user_metadata -> Welcome default (100 coins)
     */
    static async getWallet(userId) {
        const uId = (0, socketHandler_1.cleanUserId)(userId);
        let wallet = supabaseClient_1.LocalDbStore.wallets.get(uId);
        // If not in memory or balance is default, attempt restore from Supabase
        const supabase = (0, supabaseClient_1.getSupabase)();
        if (supabase) {
            try {
                // Try public.wallets table first
                const { data: dbWallet } = await supabase
                    .from('wallets')
                    .select('coin_balance, lifetime_earned, lifetime_spent')
                    .eq('user_id', uId)
                    .single();
                if (dbWallet) {
                    const restored = {
                        balance: Number(dbWallet.coin_balance) || 0,
                        earned: Number(dbWallet.lifetime_earned) || 0,
                        spent: Number(dbWallet.lifetime_spent) || 0
                    };
                    supabaseClient_1.LocalDbStore.wallets.set(uId, restored);
                    return restored;
                }
                // Try auth user_metadata fallback
                const { data: authData } = await supabase.auth.admin.getUserById(uId);
                if (authData?.user?.user_metadata?.wallet) {
                    const metaWallet = authData.user.user_metadata.wallet;
                    const restored = {
                        balance: Number(metaWallet.balance) || 0,
                        earned: Number(metaWallet.earned) || 0,
                        spent: Number(metaWallet.spent) || 0
                    };
                    supabaseClient_1.LocalDbStore.wallets.set(uId, restored);
                    return restored;
                }
            }
            catch (_) { }
        }
        if (!wallet) {
            // Default welcome wallet: 100 free coins on initial onboarding
            wallet = { balance: 100, earned: 100, spent: 0 };
            supabaseClient_1.LocalDbStore.wallets.set(uId, wallet);
            supabaseClient_1.LocalDbStore.saveToDisk();
            WalletService.syncToCloud(uId, wallet).catch(() => { });
        }
        return wallet;
    }
    /**
     * Atomically adds/recharges coins to a user's balance and logs a credit transaction.
     */
    static async addCoins(userId, amount, details) {
        const uId = (0, socketHandler_1.cleanUserId)(userId);
        const coinsToAdd = Math.max(0, Math.floor(amount));
        if (coinsToAdd <= 0) {
            throw new Error('Coin amount must be greater than zero.');
        }
        const wallet = await WalletService.getWallet(uId);
        wallet.balance += coinsToAdd;
        wallet.earned += coinsToAdd;
        supabaseClient_1.LocalDbStore.wallets.set(uId, wallet);
        const tx = {
            id: `wtx_crd_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
            userId: uId,
            amount: coinsToAdd,
            balanceAfter: wallet.balance,
            type: details.type || 'coin_purchase',
            description: details.description || `Recharged ${coinsToAdd} coins (Package: ${details.packageId || 'custom'})`,
            referenceId: details.referenceId || `ref_${Date.now()}`,
            createdAt: new Date().toISOString()
        };
        supabaseClient_1.LocalDbStore.walletTransactions.unshift(tx);
        supabaseClient_1.LocalDbStore.saveToDisk();
        // Persist to Supabase Cloud synchronously before responding
        try {
            await WalletService.syncToCloud(uId, wallet, tx);
        }
        catch (e) {
            console.warn('[WalletService] Cloud sync error:', e.message);
        }
        // Broadcast realtime event to user socket room
        const io = (0, socketHandler_1.getSocketIo)();
        if (io) {
            io.to(`user:${uId}`).emit('wallet_updated', {
                balance: wallet.balance,
                earned: wallet.earned,
                spent: wallet.spent,
                delta: coinsToAdd,
                transaction: tx
            });
        }
        return { wallet, transaction: tx };
    }
    /**
     * Atomically reduces/deducts coins from a user's balance and logs a debit transaction.
     */
    static async deductCoins(userId, amount, details) {
        const uId = (0, socketHandler_1.cleanUserId)(userId);
        const coinsToDeduct = Math.max(0, Math.floor(amount));
        if (coinsToDeduct <= 0) {
            throw new Error('Deduct coin amount must be greater than zero.');
        }
        const wallet = await WalletService.getWallet(uId);
        if (wallet.balance < coinsToDeduct) {
            const err = new Error(`Insufficient coins. Current balance: ${wallet.balance}, Required: ${coinsToDeduct}`);
            err.code = 'INSUFFICIENT_COINS';
            err.balance = wallet.balance;
            err.required = coinsToDeduct;
            throw err;
        }
        wallet.balance -= coinsToDeduct;
        wallet.spent += coinsToDeduct;
        supabaseClient_1.LocalDbStore.wallets.set(uId, wallet);
        const tx = {
            id: `wtx_deb_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
            userId: uId,
            amount: -coinsToDeduct,
            balanceAfter: wallet.balance,
            type: details.type || 'coin_spent',
            description: details.description || `Used ${coinsToDeduct} coins`,
            referenceId: details.referenceId || `ref_${Date.now()}`,
            createdAt: new Date().toISOString()
        };
        supabaseClient_1.LocalDbStore.walletTransactions.unshift(tx);
        supabaseClient_1.LocalDbStore.saveToDisk();
        // Persist to Supabase Cloud synchronously before responding
        try {
            await WalletService.syncToCloud(uId, wallet, tx);
        }
        catch (e) {
            console.warn('[WalletService] Cloud sync error:', e.message);
        }
        // Broadcast realtime event
        const io = (0, socketHandler_1.getSocketIo)();
        if (io) {
            io.to(`user:${uId}`).emit('wallet_updated', {
                balance: wallet.balance,
                earned: wallet.earned,
                spent: wallet.spent,
                delta: -coinsToDeduct,
                transaction: tx
            });
        }
        return { wallet, transaction: tx };
    }
    /**
     * Dual-layer sync: tries Supabase SQL tables and updates Supabase Auth user_metadata.
     */
    static async syncToCloud(userId, wallet, transaction) {
        const supabase = (0, supabaseClient_1.getSupabase)();
        if (!supabase)
            return;
        const uId = (0, socketHandler_1.cleanUserId)(userId);
        // 1. Try public.wallets table
        try {
            const { error: wErr } = await supabase.from('wallets').upsert({
                user_id: uId,
                coin_balance: wallet.balance,
                lifetime_earned: wallet.earned,
                lifetime_spent: wallet.spent,
                updated_at: new Date().toISOString()
            });
            if (wErr)
                console.warn('[WalletService] Supabase wallets upsert notice:', wErr.message);
        }
        catch (e) {
            console.warn('[WalletService] Supabase wallets table exception:', e.message);
        }
        // 2. Try public.wallet_transactions table
        if (transaction) {
            try {
                const { error: txErr } = await supabase.from('wallet_transactions').insert({
                    user_id: uId,
                    amount: transaction.amount,
                    balance_after: transaction.balanceAfter,
                    type: transaction.type,
                    description: transaction.description,
                    reference_id: transaction.referenceId,
                    created_at: transaction.createdAt
                });
                if (txErr)
                    console.warn('[WalletService] Supabase wallet_transactions insert notice:', txErr.message);
            }
            catch (e) {
                console.warn('[WalletService] Supabase wallet_transactions table exception:', e.message);
            }
        }
        // 3. User metadata fallback so coins survive container spin-downs
        try {
            const { data } = await supabase.auth.admin.getUserById(uId);
            if (data?.user) {
                const currentTxs = Array.isArray(data.user.user_metadata?.wallet_transactions)
                    ? data.user.user_metadata.wallet_transactions
                    : [];
                const updatedTxs = transaction ? [transaction, ...currentTxs].slice(0, 50) : currentTxs;
                await supabase.auth.admin.updateUserById(uId, {
                    user_metadata: {
                        ...data.user.user_metadata,
                        wallet: {
                            balance: wallet.balance,
                            earned: wallet.earned,
                            spent: wallet.spent,
                            updatedAt: new Date().toISOString()
                        },
                        wallet_transactions: updatedTxs
                    }
                });
            }
        }
        catch (_) { }
    }
}
exports.WalletService = WalletService;
class GiftController {
    static async getGiftCatalogue(req, res) {
        try {
            res.json({ success: true, data: supabaseClient_1.LocalDbStore.gifts });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async sendGift(req, res) {
        try {
            const senderId = (0, socketHandler_1.cleanUserId)(req.user?.id);
            if (!senderId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const { receiverId, giftId, roomId, message } = req.body;
            if (!receiverId || !giftId) {
                res.status(400).json({ success: false, error: { message: 'receiverId and giftId are required.' } });
                return;
            }
            let targetReceiverId = (0, socketHandler_1.cleanUserId)(receiverId);
            // Check block settings
            if (supabaseClient_1.LocalDbStore.userBlocks.has(`${senderId}:${targetReceiverId}`) ||
                supabaseClient_1.LocalDbStore.userBlocks.has(`${targetReceiverId}:${senderId}`)) {
                res.status(403).json({ success: false, error: { message: 'Cannot send gift due to block settings.' } });
                return;
            }
            // Find gift
            const gift = supabaseClient_1.LocalDbStore.gifts.find(g => g.id === giftId || g.name.toLowerCase() === giftId.toLowerCase());
            if (!gift) {
                res.status(404).json({ success: false, error: { message: 'Gift not found.' } });
                return;
            }
            const isSelfGift = senderId === targetReceiverId;
            const giftEmoji = gift.emoji || '🎁';
            const senderProfile = supabaseClient_1.LocalDbStore.profiles.get(senderId) || { displayName: req.user?.displayName || 'Vyber' };
            const receiverProfile = supabaseClient_1.LocalDbStore.profiles.get(targetReceiverId) || { displayName: 'Vyber' };
            const txId = `tx_gift_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;
            // 1. Deduct sender wallet
            let senderWalletResult;
            try {
                senderWalletResult = await WalletService.deductCoins(senderId, gift.coinPrice, {
                    type: 'gift_sent',
                    description: `Sent ${gift.name} ${giftEmoji} to ${receiverProfile.displayName}`,
                    referenceId: txId
                });
            }
            catch (coinErr) {
                res.status(400).json({
                    success: false,
                    error: {
                        code: coinErr.code || 'INSUFFICIENT_COINS',
                        message: coinErr.message || 'Insufficient coins.'
                    }
                });
                return;
            }
            // 2. Credit receiver wallet (if not self gift)
            let receiverNewBalance = senderWalletResult.wallet.balance;
            if (!isSelfGift) {
                const receiverResult = await WalletService.addCoins(targetReceiverId, gift.coinPrice, {
                    type: 'gift_received',
                    description: `Received ${gift.name} ${giftEmoji} from ${senderProfile.displayName}`,
                    referenceId: txId
                });
                receiverNewBalance = receiverResult.wallet.balance;
            }
            const giftTx = {
                id: txId,
                senderId,
                receiverId: targetReceiverId,
                senderName: senderProfile.displayName,
                receiverName: receiverProfile.displayName,
                senderAvatar: senderProfile.avatarUrl,
                giftId: gift.id,
                giftName: gift.name,
                emoji: giftEmoji,
                iconName: gift.iconName,
                coinAmount: gift.coinPrice,
                roomId,
                message: message || '',
                createdAt: new Date().toISOString()
            };
            supabaseClient_1.LocalDbStore.giftTransactions.unshift(giftTx);
            supabaseClient_1.LocalDbStore.saveToDisk();
            // Notification to receiver
            const notifData = {
                id: `notif_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
                userId: targetReceiverId,
                type: 'gift_received',
                title: 'Gift Received! 🎁',
                body: `${senderProfile.displayName} sent you a ${gift.name} ${giftEmoji}! (+${gift.coinPrice} Coins)`,
                payload: {
                    ...giftTx,
                    emoji: giftEmoji,
                    senderName: senderProfile.displayName,
                    receiverNewBalance
                },
                isRead: false,
                createdAt: new Date().toISOString()
            };
            supabaseClient_1.LocalDbStore.notifications.unshift(notifData);
            supabaseClient_1.LocalDbStore.saveToDisk();
            // Broadcast live gift animation & updates via Socket.IO
            const io = (0, socketHandler_1.getSocketIo)();
            if (io) {
                const giftPayload = {
                    ...giftTx,
                    emoji: giftEmoji,
                    receiverNewBalance
                };
                // Deliver to receiver
                io.to(`user:${targetReceiverId}`).emit('gift_received', giftPayload);
                io.to(`user:${targetReceiverId}`).emit('live_gift_animation', giftPayload);
                io.to(`user:${targetReceiverId}`).emit('notification_received', notifData);
                // Deliver to sender for animation confirmation
                io.to(`user:${senderId}`).emit('gift_received', {
                    ...giftPayload,
                    isSender: true,
                    senderNewBalance: senderWalletResult.wallet.balance
                });
                io.to(`user:${senderId}`).emit('live_gift_animation', {
                    ...giftPayload,
                    isSender: true,
                    senderNewBalance: senderWalletResult.wallet.balance
                });
                // Broadcast to group room if sent during a live room
                if (roomId) {
                    io.to(`room:${roomId}`).emit('live_gift_animation', giftPayload);
                }
            }
            res.status(201).json({
                success: true,
                data: {
                    transaction: giftTx,
                    senderNewBalance: senderWalletResult.wallet.balance,
                    receiverNewBalance
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async getReceivedGifts(req, res) {
        try {
            const userId = (0, socketHandler_1.cleanUserId)(req.user?.id);
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const received = supabaseClient_1.LocalDbStore.giftTransactions.filter(g => (0, socketHandler_1.cleanUserId)(g.receiverId) === userId);
            res.json({ success: true, data: received });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async getSentGifts(req, res) {
        try {
            const userId = (0, socketHandler_1.cleanUserId)(req.user?.id);
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const sent = supabaseClient_1.LocalDbStore.giftTransactions.filter(g => (0, socketHandler_1.cleanUserId)(g.senderId) === userId);
            res.json({ success: true, data: sent });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
}
exports.GiftController = GiftController;
class WalletController {
    static async getWallet(req, res) {
        try {
            const userId = (0, socketHandler_1.cleanUserId)(req.user?.id);
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const wallet = await WalletService.getWallet(userId);
            // Local transactions
            const localTxs = supabaseClient_1.LocalDbStore.walletTransactions.filter(t => (0, socketHandler_1.cleanUserId)(t.userId) === userId);
            // Supabase user_metadata transactions
            let cloudTxs = [];
            const supabase = (0, supabaseClient_1.getSupabase)();
            if (supabase) {
                try {
                    const { data } = await supabase.auth.admin.getUserById(userId);
                    if (Array.isArray(data?.user?.user_metadata?.wallet_transactions)) {
                        cloudTxs = data.user.user_metadata.wallet_transactions;
                    }
                }
                catch (_) { }
            }
            // Merge and deduplicate by id / referenceId
            const combined = [...localTxs, ...cloudTxs];
            const seen = new Set();
            const deduped = [];
            for (const item of combined) {
                const key = item.id || item.referenceId || JSON.stringify(item);
                if (!seen.has(key)) {
                    seen.add(key);
                    deduped.push(item);
                }
            }
            deduped.sort((a, b) => new Date(b.createdAt || 0).getTime() - new Date(a.createdAt || 0).getTime());
            res.json({
                success: true,
                data: {
                    balance: wallet.balance,
                    lifetimeEarned: wallet.earned,
                    lifetimeSpent: wallet.spent,
                    recentTransactions: deduped.slice(0, 50)
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async getBalance(req, res) {
        try {
            const userId = (0, socketHandler_1.cleanUserId)(req.user?.id);
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const wallet = await WalletService.getWallet(userId);
            res.json({
                success: true,
                data: {
                    balance: wallet.balance,
                    lifetimeEarned: wallet.earned,
                    lifetimeSpent: wallet.spent
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async purchaseCoins(req, res) {
        try {
            const userId = (0, socketHandler_1.cleanUserId)(req.user?.id);
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const { coinsAmount, packageId, receiptToken, description } = req.body;
            const amount = parseInt(coinsAmount, 10);
            if (!amount || amount <= 0) {
                res.status(400).json({ success: false, error: { message: 'A valid coin amount greater than 0 is required.' } });
                return;
            }
            const { wallet, transaction } = await WalletService.addCoins(userId, amount, {
                type: 'coin_purchase',
                description: description || `Recharged ${amount} coins (Package: ${packageId || 'custom'})`,
                referenceId: receiptToken || `rcpt_${Date.now()}`,
                packageId
            });
            res.json({
                success: true,
                data: {
                    balance: wallet.balance,
                    lifetimeEarned: wallet.earned,
                    lifetimeSpent: wallet.spent,
                    transaction
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async deductCoins(req, res) {
        try {
            const userId = (0, socketHandler_1.cleanUserId)(req.user?.id);
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const { amount: rawAmount, coinsAmount, type, description, referenceId } = req.body;
            const amount = parseInt(rawAmount || coinsAmount, 10);
            if (!amount || amount <= 0) {
                res.status(400).json({ success: false, error: { message: 'A valid coin amount greater than 0 is required.' } });
                return;
            }
            try {
                const { wallet, transaction } = await WalletService.deductCoins(userId, amount, {
                    type: type || 'coin_spent',
                    description: description || `Used ${amount} coins`,
                    referenceId
                });
                res.json({
                    success: true,
                    data: {
                        balance: wallet.balance,
                        lifetimeEarned: wallet.earned,
                        lifetimeSpent: wallet.spent,
                        transaction
                    }
                });
            }
            catch (err) {
                res.status(400).json({
                    success: false,
                    error: {
                        code: err.code || 'INSUFFICIENT_COINS',
                        message: err.message || 'Failed to deduct coins.'
                    }
                });
            }
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
}
exports.WalletController = WalletController;
