import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';
import { getSocketIo } from '../sockets/socketHandler';

export class GiftController {
  public static async getGiftCatalogue(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      res.json({ success: true, data: LocalDbStore.gifts });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async sendGift(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const senderId = req.user?.id;
      if (!senderId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { receiverId, giftId, roomId, message } = req.body;

      if (!receiverId || !giftId) {
        res.status(400).json({ success: false, error: { message: 'receiverId and giftId are required.' } });
        return;
      }

      if (senderId === receiverId) {
        res.status(400).json({ success: false, error: { message: 'You cannot send gifts to yourself.' } });
        return;
      }

      // Check block settings
      if (LocalDbStore.userBlocks.has(`${senderId}:${receiverId}`) ||
          LocalDbStore.userBlocks.has(`${receiverId}:${senderId}`)) {
        res.status(403).json({ success: false, error: { message: 'Cannot send gift due to block settings.' } });
        return;
      }

      // Find gift
      const gift = LocalDbStore.gifts.find(g => g.id === giftId || g.name.toLowerCase() === giftId.toLowerCase());
      if (!gift) {
        res.status(404).json({ success: false, error: { message: 'Gift not found.' } });
        return;
      }

      // Atomically check and deduct sender wallet
      let senderWallet = LocalDbStore.wallets.get(senderId);
      if (!senderWallet) {
        senderWallet = { balance: 100, earned: 100, spent: 0 };
        LocalDbStore.wallets.set(senderId, senderWallet);
      }

      if (senderWallet.balance < gift.coinPrice) {
        res.status(400).json({
          success: false,
          error: {
            code: 'INSUFFICIENT_COINS',
            message: `Insufficient coins. Current balance: ${senderWallet.balance}, Required: ${gift.coinPrice}`
          }
        });
        return;
      }

      // Process transaction
      senderWallet.balance -= gift.coinPrice;
      senderWallet.spent += gift.coinPrice;
      LocalDbStore.wallets.set(senderId, senderWallet);

      // Credit receiver
      let receiverWallet = LocalDbStore.wallets.get(receiverId);
      if (!receiverWallet) {
        receiverWallet = { balance: 100, earned: 100, spent: 0 };
      }
      receiverWallet.balance += gift.coinPrice;
      receiverWallet.earned += gift.coinPrice;
      LocalDbStore.wallets.set(receiverId, receiverWallet);

      const txId = `tx_gift_${Date.now()}`;
      const senderProfile = LocalDbStore.profiles.get(senderId) || { displayName: 'Vyber' };
      const receiverProfile = LocalDbStore.profiles.get(receiverId) || { displayName: 'Vyber' };
      const giftEmoji = (gift as any).emoji || '🎁';

      const giftTx = {
        id: txId,
        senderId,
        receiverId,
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

      LocalDbStore.giftTransactions.unshift(giftTx);

      // Ledger entries
      LocalDbStore.walletTransactions.unshift({
        id: `wtx_deb_${Date.now()}`,
        userId: senderId,
        amount: -gift.coinPrice,
        balanceAfter: senderWallet.balance,
        type: 'gift_sent',
        description: `Sent ${gift.name} ${giftEmoji} to ${receiverProfile.displayName}`,
        referenceId: txId,
        createdAt: new Date().toISOString()
      });

      LocalDbStore.walletTransactions.unshift({
        id: `wtx_crd_${Date.now()}`,
        userId: receiverId,
        amount: gift.coinPrice,
        balanceAfter: receiverWallet.balance,
        type: 'gift_received',
        description: `Received ${gift.name} ${giftEmoji} from ${senderProfile.displayName}`,
        referenceId: txId,
        createdAt: new Date().toISOString()
      });

      // Notification
      const notifData = {
        id: `notif_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
        userId: receiverId,
        type: 'gift_received',
        title: 'Gift Received! 🎁',
        body: `${senderProfile.displayName} sent you a ${gift.name} ${giftEmoji}! (+${gift.coinPrice} Coins)`,
        payload: {
          ...giftTx,
          emoji: giftEmoji,
          senderName: senderProfile.displayName,
          receiverNewBalance: receiverWallet.balance,
        },
        isRead: false,
        createdAt: new Date().toISOString()
      };
      LocalDbStore.notifications.unshift(notifData);
      LocalDbStore.saveToDisk();

      // Broadcast live gift animation & updates via Socket.IO
      const io = getSocketIo();
      if (io) {
        const giftPayload = {
          ...giftTx,
          emoji: giftEmoji,
          receiverNewBalance: receiverWallet.balance
        };

        // 1. Direct delivery to receiver's user channel
        io.to(`user:${receiverId}`).emit('gift_received', giftPayload);
        io.to(`user:${receiverId}`).emit('live_gift_animation', giftPayload);
        io.to(`user:${receiverId}`).emit('wallet_updated', {
          balance: receiverWallet.balance,
          earned: receiverWallet.earned,
          delta: gift.coinPrice,
          transaction: giftTx
        });
        io.to(`user:${receiverId}`).emit('notification_received', notifData);

        // 2. Broadcast live gift animation to group room if sent in a room
        if (roomId) {
          io.to(`room:${roomId}`).emit('live_gift_animation', giftPayload);
        }
      }

      res.status(201).json({
        success: true,
        data: {
          transaction: giftTx,
          senderNewBalance: senderWallet.balance
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async getReceivedGifts(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const received = LocalDbStore.giftTransactions.filter(g => g.receiverId === userId);
      res.json({ success: true, data: received });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async getSentGifts(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const sent = LocalDbStore.giftTransactions.filter(g => g.senderId === userId);
      res.json({ success: true, data: sent });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}

export class WalletController {
  public static async getWallet(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      let wallet = LocalDbStore.wallets.get(userId);
      if (!wallet) {
        wallet = { balance: 100, earned: 100, spent: 0 };
        LocalDbStore.wallets.set(userId, wallet);
      }

      const transactions = LocalDbStore.walletTransactions.filter(t => t.userId === userId);

      res.json({
        success: true,
        data: {
          balance: wallet.balance,
          lifetimeEarned: wallet.earned,
          lifetimeSpent: wallet.spent,
          recentTransactions: transactions.slice(0, 30)
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async purchaseCoins(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { coinsAmount, packageId, receiptToken } = req.body;

      const amount = parseInt(coinsAmount, 10);
      if (!amount || amount <= 0) {
        res.status(400).json({ success: false, error: { message: 'Invalid coin amount' } });
        return;
      }

      // In production, receiptToken is validated against Google Play Developer API / Apple App Store Server API
      let wallet = LocalDbStore.wallets.get(userId);
      if (!wallet) {
        wallet = { balance: 0, earned: 0, spent: 0 };
      }

      wallet.balance += amount;
      LocalDbStore.wallets.set(userId, wallet);

      const tx = {
        id: `wtx_purch_${Date.now()}`,
        userId,
        amount,
        balanceAfter: wallet.balance,
        type: 'coin_purchase',
        description: `Purchased ${amount} coins (Package: ${packageId || 'custom'})`,
        referenceId: receiptToken || `mock_receipt_${Date.now()}`,
        createdAt: new Date().toISOString()
      };

      LocalDbStore.walletTransactions.unshift(tx);

      res.json({
        success: true,
        data: {
          balance: wallet.balance,
          transaction: tx
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
