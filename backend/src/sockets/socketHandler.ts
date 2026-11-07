import { Server, Socket } from 'socket.io';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';

let ioInstance: Server | null = null;
const userSocketsMap: Map<string, Set<string>> = new Map();

/**
 * Normalizes user ID to ensure consistent case-insensitive mapping.
 */
export function cleanUserId(id: any): string {
  if (!id) return '';
  return String(id).trim().toLowerCase();
}

/**
 * Checks if a user is currently online with an active socket connection.
 */
export function isUserOnline(userId: string): boolean {
  const uId = cleanUserId(userId);
  if (!uId) return false;
  const sockets = userSocketsMap.get(uId);
  return !!(sockets && sockets.size > 0);
}

/**
 * Get accurate presence status for a user.
 * Guaranteed: If user has no active socket connection, status is ALWAYS 'offline' and isOnline is FALSE.
 */
export function getUserPresence(userId: string): { status: string; isOnline: boolean; lastSeenAt: string } {
  const uId = cleanUserId(userId);
  if (!uId) {
    return { status: 'offline', isOnline: false, lastSeenAt: new Date().toISOString() };
  }

  const sockets = userSocketsMap.get(uId);
  const hasActiveSocket = !!(sockets && sockets.size > 0);
  const pres = LocalDbStore.presence.get(uId);

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
export function markUserOnline(userId: string, socketId?: string): void {
  const uId = cleanUserId(userId);
  if (!uId) return;

  if (!userSocketsMap.has(uId)) {
    userSocketsMap.set(uId, new Set());
  }
  if (socketId) {
    userSocketsMap.get(uId)!.add(socketId);
  }

  const existing = LocalDbStore.presence.get(uId);
  const wasOffline = !existing || existing.status === 'offline';
  const statusToSet = (existing?.status === 'in_call' || existing?.status === 'in_room') ? existing.status : 'online';

  LocalDbStore.presence.set(uId, {
    userId: uId,
    status: statusToSet,
    lastSeenAt: new Date().toISOString()
  });

  ioInstance?.emit('user_presence_changed', { userId: uId, status: statusToSet, isOnline: true });

  // If newly came online, notify all followers so they can meet
  if (wasOffline && statusToSet === 'online') {
    const profile = LocalDbStore.profiles.get(uId);
    const friendName = profile?.displayName || profile?.username || 'Your friend';

    for (const key of LocalDbStore.follows) {
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
        LocalDbStore.notifications.unshift(notifData);
        ioInstance?.to(`user:${cleanUserId(followerId)}`).emit('notification_received', notifData);
      }
    }
    LocalDbStore.saveToDisk();
  }
}

/**
 * Marks a user offline, removing all active socket associations.
 */
export function markUserOffline(userId: string): void {
  const uId = cleanUserId(userId);
  if (!uId) return;

  userSocketsMap.delete(uId);

  LocalDbStore.presence.set(uId, {
    userId: uId,
    status: 'offline',
    lastSeenAt: new Date().toISOString()
  });

  ioInstance?.emit('user_presence_changed', { userId: uId, status: 'offline', isOnline: false });
}

export function setupSocketHandlers(io: Server): void {
  ioInstance = io;

  io.on('connection', (socket: Socket) => {
    const rawUserId = (socket.handshake.query.userId as string) || (socket.handshake.auth?.userId as string);
    const handshakeUserId = cleanUserId(rawUserId);

    if (handshakeUserId) {
      (socket as any).userId = handshakeUserId;
      socket.join(`user:${handshakeUserId}`);
      markUserOnline(handshakeUserId, socket.id);
      console.log(`[Socket] User connected: ${handshakeUserId} (${socket.id})`);
    }

    // Allow explicit user registration after connect
    socket.on('register', (data: { userId: string }) => {
      const uId = cleanUserId(data?.userId || (socket as any).userId || handshakeUserId);
      if (uId) {
        (socket as any).userId = uId;
        socket.join(`user:${uId}`);
        markUserOnline(uId, socket.id);
        console.log(`[Socket] User registered room: user:${uId} (${socket.id})`);
      }
    });

    // Heartbeat mechanism: client sends heartbeat every 25s
    socket.on('heartbeat', (data: { userId: string }) => {
      const uId = cleanUserId(data?.userId || (socket as any).userId || handshakeUserId);
      if (uId) {
        (socket as any).userId = uId;
        if (!userSocketsMap.has(uId)) {
          userSocketsMap.set(uId, new Set());
        }
        userSocketsMap.get(uId)!.add(socket.id);

        const existing = LocalDbStore.presence.get(uId);
        const currentStatus = (existing?.status === 'in_call' || existing?.status === 'in_room') ? existing.status : 'online';
        LocalDbStore.presence.set(uId, {
          userId: uId,
          status: currentStatus,
          lastSeenAt: new Date().toISOString()
        });
      }
    });

    // Join room channel for group voice audio events
    socket.on('join_room', (data: { roomId: string; userId: string }) => {
      if (data?.roomId) {
        socket.join(`room:${data.roomId}`);
        console.log(`[Socket] User ${data.userId} joined room channel ${data.roomId}`);
      }
    });

    // Leave room channel
    socket.on('leave_room', (data: { roomId: string; userId: string }) => {
      if (data?.roomId) {
        socket.leave(`room:${data.roomId}`);
        console.log(`[Socket] User ${data.userId} left room channel ${data.roomId}`);
      }
    });

    // Realtime speaker mute toggle
    socket.on('toggle_self_mute', (data: { roomId: string; userId: string; isMuted: boolean }) => {
      const uId = cleanUserId(data?.userId || (socket as any).userId || handshakeUserId);
      const roomId = data?.roomId;
      if (roomId && uId) {
        const room = LocalDbStore.rooms.get(roomId);
        if (room && room.isLive) {
          const spk = room.speakers.find((s: any) => cleanUserId(s.userId) === uId);
          if (spk) {
            spk.isMuted = Boolean(data.isMuted);
            LocalDbStore.rooms.set(roomId, room);
            io.to(`room:${roomId}`).emit('speaker_list_updated', { speakers: room.speakers });
            io.to(`room:${roomId}`).emit('room_updated', { room, speakers: room.speakers });
          }
        }
      }
    });

    // Typing indicators
    socket.on('typing_start', (data: { conversationId: string; receiverId: string }) => {
      const uId = cleanUserId((socket as any).userId || handshakeUserId);
      if (data?.receiverId) {
        io.to(`user:${cleanUserId(data.receiverId)}`).emit('typing_status', { userId: uId, isTyping: true });
      }
    });

    socket.on('typing_stop', (data: { conversationId: string; receiverId: string }) => {
      const uId = cleanUserId((socket as any).userId || handshakeUserId);
      if (data?.receiverId) {
        io.to(`user:${cleanUserId(data.receiverId)}`).emit('typing_status', { userId: uId, isTyping: false });
      }
    });

    // Disconnect
    socket.on('disconnect', () => {
      const uId = cleanUserId((socket as any).userId || handshakeUserId);
      if (uId) {
        console.log(`[Socket] Socket disconnected: ${uId} (${socket.id})`);
        const sockets = userSocketsMap.get(uId);
        if (sockets) {
          sockets.delete(socket.id);
          if (sockets.size === 0) {
            userSocketsMap.delete(uId);
            LocalDbStore.presence.set(uId, {
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
    for (const [uId, pres] of LocalDbStore.presence.entries()) {
      if (pres.status !== 'offline') {
        const activeSockets = userSocketsMap.get(uId);
        const hasSockets = activeSockets && activeSockets.size > 0;
        const lastSeenMs = pres.lastSeenAt ? new Date(pres.lastSeenAt).getTime() : 0;
        const isStale = (now - lastSeenMs) > 65000; // > 65s without heartbeat

        if (!hasSockets || isStale) {
          userSocketsMap.delete(uId);
          LocalDbStore.presence.set(uId, {
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

export function getSocketIo(): Server | null {
  return ioInstance;
}
