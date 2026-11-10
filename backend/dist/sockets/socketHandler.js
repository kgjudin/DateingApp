"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanUserId = cleanUserId;
exports.isUserOnline = isUserOnline;
exports.getUserPresence = getUserPresence;
exports.markUserOnline = markUserOnline;
exports.markUserOffline = markUserOffline;
exports.setupSocketHandlers = setupSocketHandlers;
exports.getSocketIo = getSocketIo;
const supabaseClient_1 = require("../integrations/supabase/supabaseClient");
let ioInstance = null;
const userSocketsMap = new Map();
/**
 * Normalizes user ID to ensure consistent case-insensitive mapping.
 */
function cleanUserId(id) {
    if (!id)
        return '';
    return String(id).trim().toLowerCase();
}
/**
 * Checks if a user is currently online with an active socket connection.
 */
function isUserOnline(userId) {
    const uId = cleanUserId(userId);
    if (!uId)
        return false;
    const sockets = userSocketsMap.get(uId);
    return !!(sockets && sockets.size > 0);
}
/**
 * Get accurate presence status for a user.
 * Guaranteed: If user has no active socket connection, status is ALWAYS 'offline' and isOnline is FALSE.
 */
function getUserPresence(userId) {
    const uId = cleanUserId(userId);
    if (!uId) {
        return { status: 'offline', isOnline: false, lastSeenAt: new Date().toISOString() };
    }
    const sockets = userSocketsMap.get(uId);
    const hasActiveSocket = !!(sockets && sockets.size > 0);
    const pres = supabaseClient_1.LocalDbStore.presence.get(uId);
    if (!hasActiveSocket) {
        return {
            status: 'offline',
            isOnline: false,
            lastSeenAt: pres?.lastSeenAt || new Date().toISOString()
        };
    }
    const status = (pres?.status === 'in_call' || pres?.status === 'in_room') ? pres.status : 'online';
    return {
        status,
        isOnline: true,
        lastSeenAt: pres?.lastSeenAt || new Date().toISOString()
    };
}
/**
 * Marks a user online, tracking their active socket connection.
 */
function markUserOnline(userId, socketId) {
    const uId = cleanUserId(userId);
    if (!uId)
        return;
    if (!userSocketsMap.has(uId)) {
        userSocketsMap.set(uId, new Set());
    }
    if (socketId) {
        userSocketsMap.get(uId).add(socketId);
    }
    const existing = supabaseClient_1.LocalDbStore.presence.get(uId);
    const wasOffline = !existing || existing.status === 'offline';
    const statusToSet = (existing?.status === 'in_call' || existing?.status === 'in_room') ? existing.status : 'online';
    supabaseClient_1.LocalDbStore.presence.set(uId, {
        userId: uId,
        status: statusToSet,
        lastSeenAt: new Date().toISOString()
    });
    ioInstance?.emit('user_presence_changed', { userId: uId, status: statusToSet, isOnline: true });
    // If newly came online, notify all followers so they can meet
    if (wasOffline && statusToSet === 'online') {
        const profile = supabaseClient_1.LocalDbStore.profiles.get(uId);
        const friendName = profile?.displayName || profile?.username || 'Your friend';
        for (const key of supabaseClient_1.LocalDbStore.follows) {
            const [followerId, followingId] = key.split(':');
            if (cleanUserId(followingId) === uId && cleanUserId(followerId) !== uId) {
                ioInstance?.to(`user:${cleanUserId(followerId)}`).emit('followed_user_online', {
                    userId: uId,
                    displayName: friendName,
                    avatarUrl: profile?.avatarUrl,
                });
                const notifData = {
                    id: `notif_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
                    userId: followerId,
                    type: 'friend_online',
                    title: 'Friend Online! 🟢',
                    body: `${friendName} is now online. Tap to voice chat and meet!`,
                    payload: { userId: uId, displayName: friendName, avatarUrl: profile?.avatarUrl },
                    isRead: false,
                    createdAt: new Date().toISOString()
                };
                supabaseClient_1.LocalDbStore.notifications.unshift(notifData);
                ioInstance?.to(`user:${cleanUserId(followerId)}`).emit('notification_received', notifData);
            }
        }
        supabaseClient_1.LocalDbStore.saveToDisk();
    }
}
/**
 * Marks a user offline, removing all active socket associations.
 */
function markUserOffline(userId) {
    const uId = cleanUserId(userId);
    if (!uId)
        return;
    userSocketsMap.delete(uId);
    supabaseClient_1.LocalDbStore.presence.set(uId, {
        userId: uId,
        status: 'offline',
        lastSeenAt: new Date().toISOString()
    });
    ioInstance?.emit('user_presence_changed', { userId: uId, status: 'offline', isOnline: false });
}
function setupSocketHandlers(io) {
    ioInstance = io;
    io.on('connection', (socket) => {
        const rawUserId = socket.handshake.query.userId || socket.handshake.auth?.userId;
        const handshakeUserId = cleanUserId(rawUserId);
        if (handshakeUserId) {
            socket.userId = handshakeUserId;
            socket.join(`user:${handshakeUserId}`);
            markUserOnline(handshakeUserId, socket.id);
            console.log(`[Socket] User connected: ${handshakeUserId} (${socket.id})`);
        }
        // Allow explicit user registration after connect
        socket.on('register', (data) => {
            const uId = cleanUserId(data?.userId || socket.userId || handshakeUserId);
            if (uId) {
                socket.userId = uId;
                socket.join(`user:${uId}`);
                markUserOnline(uId, socket.id);
                console.log(`[Socket] User registered room: user:${uId} (${socket.id})`);
            }
        });
        // Heartbeat mechanism: client sends heartbeat every 25s
        socket.on('heartbeat', (data) => {
            const uId = cleanUserId(data?.userId || socket.userId || handshakeUserId);
            if (uId) {
                socket.userId = uId;
                if (!userSocketsMap.has(uId)) {
                    userSocketsMap.set(uId, new Set());
                }
                userSocketsMap.get(uId).add(socket.id);
                const existing = supabaseClient_1.LocalDbStore.presence.get(uId);
                const currentStatus = (existing?.status === 'in_call' || existing?.status === 'in_room') ? existing.status : 'online';
                supabaseClient_1.LocalDbStore.presence.set(uId, {
                    userId: uId,
                    status: currentStatus,
                    lastSeenAt: new Date().toISOString()
                });
            }
        });
        // Join room channel for group voice audio events
        socket.on('join_room', (data) => {
            if (data?.roomId) {
                socket.join(`room:${data.roomId}`);
                console.log(`[Socket] User ${data.userId} joined room channel ${data.roomId}`);
            }
        });
        // Leave room channel
        socket.on('leave_room', (data) => {
            if (data?.roomId) {
                socket.leave(`room:${data.roomId}`);
                console.log(`[Socket] User ${data.userId} left room channel ${data.roomId}`);
            }
        });
        // Realtime speaker mute toggle
        socket.on('toggle_self_mute', (data) => {
            const uId = cleanUserId(data?.userId || socket.userId || handshakeUserId);
            const roomId = data?.roomId;
            if (roomId && uId) {
                const room = supabaseClient_1.LocalDbStore.rooms.get(roomId);
                if (room && room.isLive) {
                    const spk = room.speakers.find((s) => cleanUserId(s.userId) === uId);
                    if (spk) {
                        spk.isMuted = Boolean(data.isMuted);
                        supabaseClient_1.LocalDbStore.rooms.set(roomId, room);
                        io.to(`room:${roomId}`).emit('speaker_list_updated', { speakers: room.speakers });
                        io.to(`room:${roomId}`).emit('room_updated', { room, speakers: room.speakers });
                    }
                }
            }
        });
        // Typing indicators
        socket.on('typing_start', (data) => {
            const uId = cleanUserId(socket.userId || handshakeUserId);
            if (data?.receiverId) {
                io.to(`user:${cleanUserId(data.receiverId)}`).emit('typing_status', { userId: uId, isTyping: true });
            }
        });
        socket.on('typing_stop', (data) => {
            const uId = cleanUserId(socket.userId || handshakeUserId);
            if (data?.receiverId) {
                io.to(`user:${cleanUserId(data.receiverId)}`).emit('typing_status', { userId: uId, isTyping: false });
            }
        });
        // Disconnect
        socket.on('disconnect', () => {
            const uId = cleanUserId(socket.userId || handshakeUserId);
            if (uId) {
                console.log(`[Socket] Socket disconnected: ${uId} (${socket.id})`);
                const sockets = userSocketsMap.get(uId);
                if (sockets) {
                    sockets.delete(socket.id);
                    if (sockets.size === 0) {
                        userSocketsMap.delete(uId);
                        supabaseClient_1.LocalDbStore.presence.set(uId, {
                            userId: uId,
                            status: 'offline',
                            lastSeenAt: new Date().toISOString()
                        });
                        io.emit('user_presence_changed', { userId: uId, status: 'offline', isOnline: false });
                        console.log(`[Socket] User presence changed to offline (no active sockets): ${uId}`);
                    }
                }
            }
        });
    });
    // Background cleaner: periodically sweep stale sessions (e.g. abrupt app crash or network drops)
    setInterval(() => {
        const now = Date.now();
        for (const [uId, pres] of supabaseClient_1.LocalDbStore.presence.entries()) {
            if (pres.status !== 'offline') {
                const activeSockets = userSocketsMap.get(uId);
                const hasSockets = activeSockets && activeSockets.size > 0;
                const lastSeenMs = pres.lastSeenAt ? new Date(pres.lastSeenAt).getTime() : 0;
                const isStale = (now - lastSeenMs) > 65000; // > 65s without heartbeat
                if (!hasSockets || isStale) {
                    userSocketsMap.delete(uId);
                    supabaseClient_1.LocalDbStore.presence.set(uId, {
                        userId: uId,
                        status: 'offline',
                        lastSeenAt: pres.lastSeenAt || new Date().toISOString()
                    });
                    ioInstance?.emit('user_presence_changed', { userId: uId, status: 'offline', isOnline: false });
                    console.log(`[Presence Cleaner] Inactive user set to offline: ${uId}`);
                }
            }
        }
    }, 30000);
}
function getSocketIo() {
    return ioInstance;
}
