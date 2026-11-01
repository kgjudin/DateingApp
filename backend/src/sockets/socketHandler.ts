import { Server, Socket } from 'socket.io';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';

let ioInstance: Server | null = null;

export function setupSocketHandlers(io: Server): void {
  ioInstance = io;

  io.on('connection', (socket: Socket) => {
    const userId = (socket.handshake.query.userId as string) || (socket.handshake.auth?.userId as string);

    if (userId) {
      socket.join(`user:${userId}`);
      console.log(`[Socket] User connected: ${userId} (${socket.id})`);

      // Update presence to online
      LocalDbStore.presence.set(userId, {
        userId,
        status: 'online',
        lastSeenAt: new Date().toISOString()
      });

      // Broadcast favourite online notification if newly came online
      io.emit('user_presence_changed', { userId, status: 'online' });
    }

    // Allow explicit user registration after connect
    socket.on('register', (data: { userId: string }) => {
      const uId = data?.userId || userId;
      if (uId) {
        socket.join(`user:${uId}`);
        console.log(`[Socket] User registered room: user:${uId} (${socket.id})`);
        LocalDbStore.presence.set(uId, {
          userId: uId,
          status: 'online',
          lastSeenAt: new Date().toISOString()
        });
      }
    });

    // Heartbeat mechanism: client sends heartbeat every 30s
    socket.on('heartbeat', (data: { userId: string }) => {
      const uId = data?.userId || userId;
      if (uId) {
        LocalDbStore.presence.set(uId, {
          userId: uId,
          status: 'online',
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

    // Typing indicators
    socket.on('typing_start', (data: { conversationId: string; receiverId: string }) => {
      if (data?.receiverId) {
        io.to(`user:${data.receiverId}`).emit('typing_status', { userId, isTyping: true });
      }
    });

    socket.on('typing_stop', (data: { conversationId: string; receiverId: string }) => {
      if (data?.receiverId) {
        io.to(`user:${data.receiverId}`).emit('typing_status', { userId, isTyping: false });
      }
    });

    // Disconnect
    socket.on('disconnect', () => {
      if (userId) {
        console.log(`[Socket] User disconnected: ${userId}`);
        LocalDbStore.presence.set(userId, {
          userId,
          status: 'offline',
          lastSeenAt: new Date().toISOString()
        });
        io.emit('user_presence_changed', { userId, status: 'offline' });
      }
    });
  });
}

export function getSocketIo(): Server | null {
  return ioInstance;
}
