"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ChatController = void 0;
const supabaseClient_1 = require("../integrations/supabase/supabaseClient");
const socketHandler_1 = require("../sockets/socketHandler");
class ChatController {
    static messages = [];
    static async getConversations(req, res) {
        try {
            const userId = req.user?.id;
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            // Group messages by counterpart
            const conversationMap = new Map();
            for (const msg of ChatController.messages) {
                if (msg.senderId === userId || msg.receiverId === userId) {
                    const otherId = msg.senderId === userId ? msg.receiverId : msg.senderId;
                    const otherProfile = supabaseClient_1.LocalDbStore.profiles.get(otherId) || { displayName: 'Vyber' };
                    const presence = supabaseClient_1.LocalDbStore.presence.get(otherId) || { status: 'offline' };
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
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async getMessages(req, res) {
        try {
            const userId = req.user?.id;
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const otherUserId = String(req.params.otherUserId);
            const msgs = ChatController.messages.filter(m => (m.senderId === userId && m.receiverId === otherUserId) ||
                (m.senderId === otherUserId && m.receiverId === userId));
            res.json({ success: true, data: msgs });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async sendMessage(req, res) {
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
            if (supabaseClient_1.LocalDbStore.userBlocks.has(`${senderId}:${receiverId}`) ||
                supabaseClient_1.LocalDbStore.userBlocks.has(`${receiverId}:${senderId}`)) {
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
            const io = (0, socketHandler_1.getSocketIo)();
            if (io) {
                io.to(`user:${receiverId}`).emit('new_message', msg);
            }
            res.status(201).json({ success: true, data: msg });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    // Safety: Block & Report
    static async blockUser(req, res) {
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
            supabaseClient_1.LocalDbStore.userBlocks.add(`${blockerId}:${targetUserId}`);
            res.json({ success: true, message: 'User blocked successfully.' });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async reportUser(req, res) {
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
            supabaseClient_1.LocalDbStore.userReports.unshift(report);
            res.status(201).json({ success: true, message: 'Report submitted for moderation.', data: report });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    // Notifications
    static async getNotifications(req, res) {
        try {
            const rawUserId = req.user?.id;
            if (!rawUserId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const userId = String(rawUserId).trim().toLowerCase();
            const notifs = supabaseClient_1.LocalDbStore.notifications.filter(n => String(n.userId || '').trim().toLowerCase() === userId);
            res.json({ success: true, data: notifs });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async markAllAsRead(req, res) {
        try {
            const rawUserId = req.user?.id;
            if (!rawUserId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const userId = String(rawUserId).trim().toLowerCase();
            for (const n of supabaseClient_1.LocalDbStore.notifications) {
                if (String(n.userId || '').trim().toLowerCase() === userId) {
                    n.isRead = true;
                }
            }
            supabaseClient_1.LocalDbStore.saveToDisk();
            res.json({ success: true, message: 'All notifications marked as read' });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async clearNotifications(req, res) {
        try {
            const rawUserId = req.user?.id;
            if (!rawUserId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const userId = String(rawUserId).trim().toLowerCase();
            supabaseClient_1.LocalDbStore.notifications = supabaseClient_1.LocalDbStore.notifications.filter(n => String(n.userId || '').trim().toLowerCase() !== userId);
            supabaseClient_1.LocalDbStore.saveToDisk();
            res.json({ success: true, message: 'All notifications cleared' });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
}
exports.ChatController = ChatController;
