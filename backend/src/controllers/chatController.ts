import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';
import { getSocketIo } from '../sockets/socketHandler';

export class ChatController {
  private static messages: any[] = [];

  public static async getConversations(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      // Group messages by counterpart
      const conversationMap: Map<string, any> = new Map();

      for (const msg of ChatController.messages) {
        if (msg.senderId === userId || msg.receiverId === userId) {
          const otherId = msg.senderId === userId ? msg.receiverId : msg.senderId;
          const otherProfile = LocalDbStore.profiles.get(otherId) || { displayName: 'Vyber' };
          const presence = LocalDbStore.presence.get(otherId) || { status: 'offline' };

          if (!conversationMap.has(otherId)) {
            conversationMap.set(otherId, {
              counterpartId: otherId,
              displayName: otherProfile.displayName,
              avatarUrl: otherProfile.avatarUrl,
              username: otherProfile.username,
              status: presence.status,
              lastMessage: msg.content,
              lastMessageTime: msg.createdAt,
              unreadCount: msg.receiverId === userId && !msg.isRead ? 1 : 0
            });
          }
        }
      }

      res.json({ success: true, data: Array.from(conversationMap.values()) });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async getMessages(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const otherUserId = String(req.params.otherUserId);

      const msgs = ChatController.messages.filter(
        m => (m.senderId === userId && m.receiverId === otherUserId) ||
             (m.senderId === otherUserId && m.receiverId === userId)
      );

      res.json({ success: true, data: msgs });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async sendMessage(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const senderId = req.user?.id;
      if (!senderId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { receiverId, content, messageType, attachmentUrl } = req.body;

      if (!receiverId || !content) {
        res.status(400).json({ success: false, error: { message: 'receiverId and content are required' } });
        return;
      }

      // Check block
      if (LocalDbStore.userBlocks.has(`${senderId}:${receiverId}`) ||
          LocalDbStore.userBlocks.has(`${receiverId}:${senderId}`)) {
        res.status(403).json({ success: false, error: { message: 'Cannot send message due to block settings.' } });
        return;
      }

      const msg = {
        id: `msg_${Date.now()}`,
        senderId,
        receiverId,
        content,
        messageType: messageType || 'text',
        attachmentUrl: attachmentUrl || null,
        isRead: false,
        createdAt: new Date().toISOString()
      };

      ChatController.messages.push(msg);

      // Emit live message
      const io = getSocketIo();
      if (io) {
        io.to(`user:${receiverId}`).emit('new_message', msg);
      }

      res.status(201).json({ success: true, data: msg });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  // Safety: Block & Report
  public static async blockUser(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const blockerId = req.user?.id;
      if (!blockerId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { targetUserId } = req.body;

      if (!targetUserId) {
        res.status(400).json({ success: false, error: { message: 'targetUserId required' } });
        return;
      }

      LocalDbStore.userBlocks.add(`${blockerId}:${targetUserId}`);
      res.json({ success: true, message: 'User blocked successfully.' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async reportUser(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const reporterId = req.user?.id;
      if (!reporterId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { targetUserId, reason, description, roomId } = req.body;

      const report = {
        id: `rep_${Date.now()}`,
        reporterId,
        targetUserId,
        roomId: roomId || null,
        reason: reason || 'Inappropriate behavior',
        description: description || '',
        status: 'pending',
        createdAt: new Date().toISOString()
      };

      LocalDbStore.userReports.unshift(report);
      res.status(201).json({ success: true, message: 'Report submitted for moderation.', data: report });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  // Notifications
  public static async getNotifications(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const notifs = LocalDbStore.notifications.filter(n => n.userId === userId);
      res.json({ success: true, data: notifs });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
