import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';
import { AgoraService } from '../integrations/agora/agoraService';
import { getSocketIo } from '../sockets/socketHandler';

export class RoomController {
  public static async listLiveRooms(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const rooms = Array.from(LocalDbStore.rooms.values()).filter(r => r.isLive);
      res.json({ success: true, data: rooms });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async createRoom(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const hostId = req.user?.id || 'user-elena-101';
      const { groupId, title, topic } = req.body;

      if (!title) {
        res.status(400).json({ success: false, error: { message: 'Room title is required' } });
        return;
      }

      const hostProfile = LocalDbStore.profiles.get(hostId) || { displayName: 'Vybe Host', avatarUrl: '' };
      const group = groupId ? LocalDbStore.groups.get(groupId) : null;

      const roomId = `room_${Date.now()}`;
      const channelName = `vybe_room_${roomId}`;

      // Host gets Publisher Agora token
      const hostAgora = AgoraService.generateRtcToken(channelName, hostId, true);

      const newRoom = {
        id: roomId,
        groupId: groupId || 'grp-general',
        groupName: group?.name || 'Open Community Room',
        hostId,
        hostName: hostProfile.displayName,
        hostAvatar: hostProfile.avatarUrl,
        title,
        topic: topic || 'Open Voice Discussion',
        channelName,
        isLive: true,
        listenersCount: 1,
        speakersCount: 1,
        speakers: [
          {
            userId: hostId,
            name: hostProfile.displayName,
            role: 'host',
            isMuted: false,
            avatarUrl: hostProfile.avatarUrl
          }
        ],
        listeners: [],
        speakerRequests: [],
        createdAt: new Date().toISOString()
      };

      LocalDbStore.rooms.set(roomId, newRoom);

      res.status(201).json({
        success: true,
        data: {
          ...newRoom,
          token: hostAgora.token,
          appId: hostAgora.appId,
          role: 'host'
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async joinRoom(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id || 'user-marcus-102';
      const id = String(req.params.id);

      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Live room not found or has ended' } });
        return;
      }

      const userProfile = LocalDbStore.profiles.get(userId) || { displayName: 'Vyber', avatarUrl: '' };
      const isHost = room.hostId === userId;
      const isAlreadySpeaker = room.speakers.some((s: any) => s.userId === userId);

      const role = isHost ? 'host' : (isAlreadySpeaker ? 'speaker' : 'listener');
      const isPublisher = role === 'host' || role === 'speaker';

      // Generate appropriate Agora token based on role
      const agora = AgoraService.generateRtcToken(room.channelName, userId, isPublisher);

      if (!isHost && !isAlreadySpeaker) {
        room.listenersCount = (room.listenersCount || 0) + 1;
        if (!room.listeners) room.listeners = [];
        if (!room.listeners.some((l: any) => l.userId === userId)) {
          room.listeners.push({
            userId,
            name: userProfile.displayName,
            avatarUrl: userProfile.avatarUrl
          });
        }
      }

      LocalDbStore.rooms.set(id, room);

      // Broadcast room join to room channel
      const io = getSocketIo();
      if (io) {
        io.to(`room:${id}`).emit('user_joined_room', {
          userId,
          name: userProfile.displayName,
          avatarUrl: userProfile.avatarUrl,
          listenersCount: room.listenersCount
        });
      }

      res.json({
        success: true,
        data: {
          ...room,
          token: agora.token,
          appId: agora.appId,
          role
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async raiseHand(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id || 'user-marcus-102';
      const id = String(req.params.id);

      const room = LocalDbStore.rooms.get(id);
      if (!room) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      const userProfile = LocalDbStore.profiles.get(userId) || { displayName: 'Vyber', avatarUrl: '' };
      if (!room.speakerRequests) room.speakerRequests = [];

      const alreadyRequested = room.speakerRequests.some((r: any) => r.userId === userId);
      if (!alreadyRequested) {
        room.speakerRequests.push({
          userId,
          name: userProfile.displayName,
          avatarUrl: userProfile.avatarUrl,
          requestedAt: new Date().toISOString()
        });
      }

      LocalDbStore.rooms.set(id, room);

      // Notify host via socket
      const io = getSocketIo();
      if (io) {
        io.to(`user:${room.hostId}`).emit('speaker_request_received', {
          roomId: id,
          user: { userId, name: userProfile.displayName, avatarUrl: userProfile.avatarUrl }
        });
      }

      res.json({ success: true, message: 'Hand raised successfully' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async approveSpeaker(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const hostId = req.user?.id;
      const id = String(req.params.id);
      const { targetUserId } = req.body;

      const room = LocalDbStore.rooms.get(id);
      if (!room) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      if (room.hostId !== hostId && hostId !== 'admin') {
        res.status(403).json({ success: false, error: { message: 'Only the room host can approve speakers' } });
        return;
      }

      // Remove from requests
      room.speakerRequests = (room.speakerRequests || []).filter((r: any) => r.userId !== targetUserId);

      // Add to speakers
      const targetProfile = LocalDbStore.profiles.get(targetUserId) || { displayName: 'Speaker' };
      const newSpeaker = {
        userId: targetUserId,
        name: targetProfile.displayName,
        role: 'speaker',
        isMuted: false,
        avatarUrl: targetProfile.avatarUrl
      };

      room.speakers.push(newSpeaker);
      room.speakersCount = room.speakers.length;
      LocalDbStore.rooms.set(id, room);

      // Generate Publisher token for target user
      const speakerAgora = AgoraService.generateRtcToken(room.channelName, targetUserId, true);

      // Notify target user and room
      const io = getSocketIo();
      if (io) {
        io.to(`user:${targetUserId}`).emit('speaker_approved', {
          roomId: id,
          token: speakerAgora.token,
          role: 'speaker'
        });
        io.to(`room:${id}`).emit('speaker_list_updated', {
          speakers: room.speakers
        });
      }

      res.json({ success: true, message: 'Speaker approved', data: room.speakers });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async leaveRoom(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      const id = String(req.params.id);

      const room = LocalDbStore.rooms.get(id);
      if (room) {
        // If host leaves, end room
        if (room.hostId === userId) {
          room.isLive = false;
          room.endedAt = new Date().toISOString();
        } else {
          room.speakers = room.speakers.filter((s: any) => s.userId !== userId);
          room.speakersCount = room.speakers.length;
          room.listenersCount = Math.max(0, (room.listenersCount || 1) - 1);
        }
        LocalDbStore.rooms.set(id, room);

        const io = getSocketIo();
        if (io) {
          io.to(`room:${id}`).emit('user_left_room', { userId, isLive: room.isLive });
        }
      }

      res.json({ success: true, message: 'Left room' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
