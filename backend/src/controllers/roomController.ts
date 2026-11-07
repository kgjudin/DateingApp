import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';
import { AgoraService } from '../integrations/agora/agoraService';
import { getSocketIo } from '../sockets/socketHandler';

export class RoomController {
  public static async listLiveRooms(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const rooms = Array.from(LocalDbStore.rooms.values()).filter(r => r.isLive);
      const seen = new Set<string>();
      const uniqueRooms = rooms.filter(r => {
        if (!r.id || seen.has(r.id)) return false;
        seen.add(r.id);
        return true;
      });
      res.json({ success: true, data: uniqueRooms });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async getRoomDetails(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const id = String(req.params.id);
      const room = LocalDbStore.rooms.get(id);
      if (!room) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }
      res.json({ success: true, data: room });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async createRoom(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const hostId = req.user?.id;
      if (!hostId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { groupId, title, topic } = req.body;

      if (!title) {
        res.status(400).json({ success: false, error: { message: 'Room title is required' } });
        return;
      }

      // Close any previous live room hosted by this user to avoid duplicate listings
      const io = getSocketIo();
      for (const [rId, r] of LocalDbStore.rooms.entries()) {
        if (r.isLive && String(r.hostId) === String(hostId)) {
          r.isLive = false;
          r.endedAt = new Date().toISOString();
          LocalDbStore.rooms.set(rId, r);
          if (io) {
            io.to(`room:${rId}`).emit('room_ended', { roomId: rId, reason: 'Host started a new room' });
          }
        }
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
        groupName: group?.name || 'Open Community Stage',
        hostId,
        originalHostId: hostId,
        subHostId: null,
        hostName: hostProfile.displayName || 'Vybe Host',
        hostAvatar: hostProfile.avatarUrl || '',
        title,
        topic: topic || 'Open Voice Discussion',
        channelName,
        isLive: true,
        listenersCount: 0,
        speakersCount: 1,
        speakers: [
          {
            userId: hostId,
            name: hostProfile.displayName || 'Vybe Host',
            role: 'host',
            isMuted: false,
            avatarUrl: hostProfile.avatarUrl || ''
          }
        ],
        listeners: [],
        speakerRequests: [],
        kickedUserIds: [],
        createdAt: new Date().toISOString()
      };

      LocalDbStore.rooms.set(roomId, newRoom);

      if (io) {
        io.emit('room_created', newRoom);
      }

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
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const id = String(req.params.id);

      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Live room not found or has ended' } });
        return;
      }

      // Check if user was kicked by host
      if (room.kickedUserIds && room.kickedUserIds.includes(userId)) {
        res.status(403).json({ success: false, error: { message: 'You have been removed from this room by the host' } });
        return;
      }

      const userProfile = LocalDbStore.profiles.get(userId) || { displayName: 'Vyber', avatarUrl: '' };
      const io = getSocketIo();

      // Check if user is the ORIGINAL creator / host returning
      const isOriginalHost = String(room.originalHostId) === String(userId);
      let role = 'listener';

      if (isOriginalHost) {
        // Original host enters back! Reclaim Host role immediately
        if (String(room.hostId) !== String(userId)) {
          const previousHostId = room.hostId;
          room.hostId = userId;
          for (const spk of room.speakers) {
            if (String(spk.userId) === String(previousHostId)) {
              spk.role = 'subhost';
            }
          }
          if (io) {
            io.to(`room:${id}`).emit('host_changed', {
              hostId: userId,
              hostName: userProfile.displayName,
              message: `${userProfile.displayName} (Original Host) returned and resumed Host role!`
            });
          }
        }

        // Ensure host is on speakers list as host
        const existingSpeaker = room.speakers.find((s: any) => String(s.userId) === String(userId));
        if (existingSpeaker) {
          existingSpeaker.role = 'host';
        } else {
          room.speakers.unshift({
            userId,
            name: userProfile.displayName,
            role: 'host',
            isMuted: false,
            avatarUrl: userProfile.avatarUrl || ''
          });
        }
        room.listeners = (room.listeners || []).filter((l: any) => String(l.userId) !== String(userId));
        role = 'host';
      } else if (String(room.hostId) === String(userId)) {
        role = 'host';
      } else if (String(room.subHostId) === String(userId)) {
        const isSpeaker = room.speakers.some((s: any) => String(s.userId) === String(userId));
        role = isSpeaker ? 'subhost' : 'listener';
      } else {
        const isSpeaker = room.speakers.some((s: any) => String(s.userId) === String(userId));
        if (isSpeaker) {
          role = 'speaker';
        } else {
          role = 'listener';
          if (!room.listeners) room.listeners = [];
          if (!room.listeners.some((l: any) => String(l.userId) === String(userId))) {
            room.listeners.push({
              userId,
              name: userProfile.displayName,
              avatarUrl: userProfile.avatarUrl || ''
            });
          }
        }
      }

      room.speakersCount = room.speakers.length;
      room.listenersCount = (room.listeners || []).length;
      LocalDbStore.rooms.set(id, room);

      const isPublisher = role === 'host' || role === 'subhost' || role === 'speaker';
      const agora = AgoraService.generateRtcToken(room.channelName, userId, isPublisher);

      if (io) {
        io.to(`room:${id}`).emit('room_updated', {
          room,
          speakers: room.speakers,
          listeners: room.listeners,
          listenersCount: room.listenersCount,
          speakersCount: room.speakersCount,
          hostId: room.hostId,
          subHostId: room.subHostId
        });
        io.to(`room:${id}`).emit('user_joined_room', {
          userId,
          name: userProfile.displayName,
          avatarUrl: userProfile.avatarUrl,
          role,
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
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const id = String(req.params.id);

      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      const userProfile = LocalDbStore.profiles.get(userId) || { displayName: 'Vyber', avatarUrl: '' };
      if (!room.speakerRequests) room.speakerRequests = [];

      const already = room.speakerRequests.some((r: any) => String(r.userId) === String(userId));
      if (!already) {
        room.speakerRequests.push({
          userId,
          name: userProfile.displayName,
          avatarUrl: userProfile.avatarUrl || '',
          requestedAt: new Date().toISOString()
        });
      }

      LocalDbStore.rooms.set(id, room);

      const io = getSocketIo();
      if (io) {
        io.to(`room:${id}`).emit('speaker_requests_updated', {
          roomId: id,
          requests: room.speakerRequests
        });
        io.to(`user:${room.hostId}`).emit('speaker_request_received', {
          roomId: id,
          user: { userId, name: userProfile.displayName, avatarUrl: userProfile.avatarUrl },
          requests: room.speakerRequests
        });
        if (room.subHostId) {
          io.to(`user:${room.subHostId}`).emit('speaker_request_received', {
            roomId: id,
            user: { userId, name: userProfile.displayName, avatarUrl: userProfile.avatarUrl },
            requests: room.speakerRequests
          });
        }
      }

      res.json({ success: true, message: 'Hand raised successfully', data: room.speakerRequests });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async lowerHand(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      const id = String(req.params.id);
      const { targetUserId } = req.body || {};
      const userToLower = targetUserId || userId;

      const room = LocalDbStore.rooms.get(id);
      if (!room) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      room.speakerRequests = (room.speakerRequests || []).filter((r: any) => String(r.userId) !== String(userToLower));
      LocalDbStore.rooms.set(id, room);

      const io = getSocketIo();
      if (io) {
        io.to(`room:${id}`).emit('speaker_requests_updated', {
          roomId: id,
          requests: room.speakerRequests
        });
        io.to(`room:${id}`).emit('room_updated', {
          room,
          speakerRequests: room.speakerRequests
        });
      }

      res.json({ success: true, message: 'Hand lowered', data: room.speakerRequests });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async approveSpeaker(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const callerId = req.user?.id;
      const id = String(req.params.id);
      const { targetUserId } = req.body;

      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      const isHost = String(room.hostId) === String(callerId) || callerId === 'admin';
      const isSubHost = String(room.subHostId) === String(callerId);

      if (!isHost && !isSubHost) {
        res.status(403).json({ success: false, error: { message: 'Only the host or sub-host can approve speakers' } });
        return;
      }

      // Remove from requests
      room.speakerRequests = (room.speakerRequests || []).filter((r: any) => String(r.userId) !== String(targetUserId));
      // Remove from listeners
      room.listeners = (room.listeners || []).filter((l: any) => String(l.userId) !== String(targetUserId));
      room.listenersCount = room.listeners.length;

      // Add to speakers
      const targetProfile = LocalDbStore.profiles.get(targetUserId) || { displayName: 'Speaker', avatarUrl: '' };
      const alreadySpeaker = room.speakers.some((s: any) => String(s.userId) === String(targetUserId));
      if (!alreadySpeaker) {
        room.speakers.push({
          userId: targetUserId,
          name: targetProfile.displayName,
          role: 'speaker',
          isMuted: false,
          avatarUrl: targetProfile.avatarUrl || ''
        });
      }
      room.speakersCount = room.speakers.length;
      LocalDbStore.rooms.set(id, room);

      const speakerAgora = AgoraService.generateRtcToken(room.channelName, targetUserId, true);

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
        io.to(`room:${id}`).emit('speaker_requests_updated', {
          roomId: id,
          requests: room.speakerRequests
        });
        io.to(`room:${id}`).emit('room_updated', {
          room,
          speakers: room.speakers,
          listeners: room.listeners,
          speakerRequests: room.speakerRequests
        });
      }

      res.json({ success: true, message: 'Speaker approved', data: room });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async inviteToSpeak(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const callerId = req.user?.id;
      if (!callerId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const id = String(req.params.id);
      const { targetUserId } = req.body;

      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      const isHost = String(room.hostId) === String(callerId) || callerId === 'admin';
      const isSubHost = String(room.subHostId) === String(callerId);

      if (!isHost && !isSubHost) {
        res.status(403).json({ success: false, error: { message: 'Only host or sub-host can invite users to speak' } });
        return;
      }

      const callerProfile = LocalDbStore.profiles.get(callerId) || { displayName: 'Room Host' };

      const io = getSocketIo();
      if (io) {
        io.to(`user:${targetUserId}`).emit('room_invitation_to_speak', {
          roomId: id,
          roomTitle: room.title,
          hostName: callerProfile.displayName,
          inviterId: callerId
        });
      }

      res.json({ success: true, message: 'Invitation sent to user' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async acceptInvitation(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const id = String(req.params.id);
      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      // Remove from listeners
      room.listeners = (room.listeners || []).filter((l: any) => String(l.userId) !== String(userId));
      room.listenersCount = room.listeners.length;
      room.speakerRequests = (room.speakerRequests || []).filter((r: any) => String(r.userId) !== String(userId));

      const targetProfile = LocalDbStore.profiles.get(userId) || { displayName: 'Speaker', avatarUrl: '' };
      const alreadySpeaker = room.speakers.some((s: any) => String(s.userId) === String(userId));
      if (!alreadySpeaker) {
        room.speakers.push({
          userId,
          name: targetProfile.displayName,
          role: 'speaker',
          isMuted: false,
          avatarUrl: targetProfile.avatarUrl || ''
        });
      }
      room.speakersCount = room.speakers.length;
      LocalDbStore.rooms.set(id, room);

      const speakerAgora = AgoraService.generateRtcToken(room.channelName, userId, true);

      const io = getSocketIo();
      if (io) {
        io.to(`user:${userId}`).emit('speaker_approved', {
          roomId: id,
          token: speakerAgora.token,
          role: 'speaker'
        });
        io.to(`room:${id}`).emit('speaker_list_updated', {
          speakers: room.speakers
        });
        io.to(`room:${id}`).emit('room_updated', {
          room,
          speakers: room.speakers,
          listeners: room.listeners
        });
      }

      res.json({ success: true, message: 'Joined stage as speaker', data: room });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async muteSpeaker(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const callerId = req.user?.id;
      const id = String(req.params.id);
      const { targetUserId, isMuted } = req.body;

      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      const isSelf = String(callerId) === String(targetUserId);
      const isHost = String(room.hostId) === String(callerId) || callerId === 'admin';
      const isSubHost = String(room.subHostId) === String(callerId);

      if (!isSelf && !isHost && !isSubHost) {
        res.status(403).json({ success: false, error: { message: 'Only host, sub-host, or speaker themselves can toggle mute' } });
        return;
      }

      // Sub-host cannot mute the main host
      if (!isSelf && !isHost && String(room.hostId) === String(targetUserId)) {
        res.status(403).json({ success: false, error: { message: 'Cannot mute the host' } });
        return;
      }

      const speaker = room.speakers.find((s: any) => String(s.userId) === String(targetUserId));
      if (speaker) {
        speaker.isMuted = isMuted !== undefined ? Boolean(isMuted) : true;
      }
      LocalDbStore.rooms.set(id, room);

      const io = getSocketIo();
      if (io) {
        if (!isSelf) {
          io.to(`user:${targetUserId}`).emit('speaker_muted', {
            roomId: id,
            isMuted: speaker ? speaker.isMuted : true,
            byHost: true
          });
        }
        io.to(`room:${id}`).emit('speaker_list_updated', {
          speakers: room.speakers
        });
        io.to(`room:${id}`).emit('room_updated', {
          room,
          speakers: room.speakers
        });
      }

      res.json({ success: true, message: `Speaker ${speaker?.isMuted ? 'muted' : 'unmuted'}`, data: room.speakers });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async demoteSpeaker(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const callerId = req.user?.id;
      const id = String(req.params.id);
      const { targetUserId } = req.body;

      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      const isHost = String(room.hostId) === String(callerId) || callerId === 'admin';
      if (!isHost) {
        res.status(403).json({ success: false, error: { message: 'Only host can move speakers to audience' } });
        return;
      }

      if (String(room.hostId) === String(targetUserId)) {
        res.status(400).json({ success: false, error: { message: 'Host cannot be demoted' } });
        return;
      }

      room.speakers = room.speakers.filter((s: any) => String(s.userId) !== String(targetUserId));
      room.speakersCount = room.speakers.length;

      const targetProfile = LocalDbStore.profiles.get(targetUserId) || { displayName: 'Listener', avatarUrl: '' };
      if (!room.listeners) room.listeners = [];
      if (!room.listeners.some((l: any) => String(l.userId) === String(targetUserId))) {
        room.listeners.push({
          userId: targetUserId,
          name: targetProfile.displayName,
          avatarUrl: targetProfile.avatarUrl || ''
        });
      }
      room.listenersCount = room.listeners.length;
      LocalDbStore.rooms.set(id, room);

      const io = getSocketIo();
      if (io) {
        io.to(`user:${targetUserId}`).emit('speaker_demoted', {
          roomId: id,
          role: 'listener'
        });
        io.to(`room:${id}`).emit('speaker_list_updated', {
          speakers: room.speakers
        });
        io.to(`room:${id}`).emit('room_updated', {
          room,
          speakers: room.speakers,
          listeners: room.listeners
        });
      }

      res.json({ success: true, message: 'User moved to audience', data: room });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async kickUser(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const callerId = req.user?.id;
      const id = String(req.params.id);
      const { targetUserId } = req.body;

      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      const isHost = String(room.hostId) === String(callerId) || callerId === 'admin';
      if (!isHost) {
        res.status(403).json({ success: false, error: { message: 'Only host can remove users from the room' } });
        return;
      }

      if (String(room.hostId) === String(targetUserId)) {
        res.status(400).json({ success: false, error: { message: 'Host cannot kick themselves' } });
        return;
      }

      room.speakers = room.speakers.filter((s: any) => String(s.userId) !== String(targetUserId));
      room.speakersCount = room.speakers.length;
      room.listeners = (room.listeners || []).filter((l: any) => String(l.userId) !== String(targetUserId));
      room.listenersCount = room.listeners.length;
      room.speakerRequests = (room.speakerRequests || []).filter((r: any) => String(r.userId) !== String(targetUserId));

      if (!room.kickedUserIds) room.kickedUserIds = [];
      if (!room.kickedUserIds.includes(targetUserId)) {
        room.kickedUserIds.push(targetUserId);
      }
      LocalDbStore.rooms.set(id, room);

      const io = getSocketIo();
      if (io) {
        io.to(`user:${targetUserId}`).emit('user_kicked', {
          roomId: id,
          reason: 'You were removed from this room by the host'
        });
        io.to(`room:${id}`).emit('user_left_room', {
          userId: targetUserId,
          isLive: room.isLive
        });
        io.to(`room:${id}`).emit('room_updated', {
          room,
          speakers: room.speakers,
          listeners: room.listeners
        });
      }

      res.json({ success: true, message: 'User removed from room', data: room });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async makeSubHost(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const callerId = req.user?.id;
      const id = String(req.params.id);
      const { targetUserId } = req.body;

      const room = LocalDbStore.rooms.get(id);
      if (!room || !room.isLive) {
        res.status(404).json({ success: false, error: { message: 'Room not found' } });
        return;
      }

      const isHost = String(room.hostId) === String(callerId) || callerId === 'admin';
      if (!isHost) {
        res.status(403).json({ success: false, error: { message: 'Only the room host can designate a sub-host' } });
        return;
      }

      room.subHostId = targetUserId;
      const targetProfile = LocalDbStore.profiles.get(targetUserId) || { displayName: 'Sub-Host' };

      const spk = room.speakers.find((s: any) => String(s.userId) === String(targetUserId));
      if (spk) {
        spk.role = 'subhost';
      } else {
        room.listeners = (room.listeners || []).filter((l: any) => String(l.userId) !== String(targetUserId));
        room.speakers.push({
          userId: targetUserId,
          name: targetProfile.displayName,
          role: 'subhost',
          isMuted: false,
          avatarUrl: targetProfile.avatarUrl || ''
        });
        room.speakersCount = room.speakers.length;
      }
      LocalDbStore.rooms.set(id, room);

      const subHostAgora = AgoraService.generateRtcToken(room.channelName, targetUserId, true);

      const io = getSocketIo();
      if (io) {
        io.to(`user:${targetUserId}`).emit('subhost_assigned', {
          roomId: id,
          role: 'subhost',
          token: subHostAgora.token,
          message: 'You have been designated as Sub-Host!'
        });
        io.to(`room:${id}`).emit('room_updated', {
          room,
          speakers: room.speakers,
          hostId: room.hostId,
          subHostId: room.subHostId
        });
      }

      res.json({ success: true, message: 'Sub-host assigned successfully', data: room });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async leaveRoom(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      const id = String(req.params.id);
      const { newSubHostId, endRoomForEveryone } = req.body || {};

      const room = LocalDbStore.rooms.get(id);
      if (room) {
        const isCurrentHost = String(room.hostId) === String(userId);
        const io = getSocketIo();

        if (isCurrentHost) {
          const designatedSubHost = newSubHostId || room.subHostId;
          const remainingParticipants = [
            ...(room.speakers || []).filter((s: any) => String(s.userId) !== String(userId)),
            ...(room.listeners || []).filter((l: any) => String(l.userId) !== String(userId))
          ];

          if (!endRoomForEveryone && (designatedSubHost || remainingParticipants.length > 0)) {
            const nextHostId = String(designatedSubHost || remainingParticipants[0]?.userId || '');
            const nextHostProfile = (nextHostId ? LocalDbStore.profiles.get(nextHostId) : null) || { displayName: 'Sub-Host' };

            room.hostId = nextHostId;
            room.subHostId = nextHostId;
            room.speakers = room.speakers.filter((s: any) => String(s.userId) !== String(userId));

            const nextSpk = room.speakers.find((s: any) => String(s.userId) === String(nextHostId));
            if (nextSpk) {
              nextSpk.role = 'host';
            } else {
              room.speakers.push({
                userId: nextHostId,
                name: nextHostProfile.displayName,
                role: 'host',
                isMuted: false,
                avatarUrl: nextHostProfile.avatarUrl || ''
              });
              room.listeners = (room.listeners || []).filter((l: any) => String(l.userId) !== String(nextHostId));
            }
            room.speakersCount = room.speakers.length;
            room.listenersCount = (room.listeners || []).length;
            LocalDbStore.rooms.set(id, room);

            if (io) {
              io.to(`room:${id}`).emit('host_changed', {
                hostId: nextHostId,
                hostName: nextHostProfile.displayName,
                message: `${nextHostProfile.displayName} is now the Host while the creator is away!`
              });
              io.to(`room:${id}`).emit('user_left_room', { userId, isLive: true });
              io.to(`room:${id}`).emit('room_updated', {
                room,
                speakers: room.speakers,
                listeners: room.listeners,
                hostId: room.hostId,
                subHostId: room.subHostId
              });
            }

            res.json({ success: true, message: 'Transferred host role and left room' });
            return;
          } else {
            room.isLive = false;
            room.endedAt = new Date().toISOString();
            LocalDbStore.rooms.set(id, room);
            if (io) {
              io.to(`room:${id}`).emit('room_ended', { roomId: id, isLive: false });
              io.to(`room:${id}`).emit('user_left_room', { userId, isLive: false });
            }
          }
        } else {
          room.speakers = room.speakers.filter((s: any) => String(s.userId) !== String(userId));
          room.listeners = (room.listeners || []).filter((l: any) => String(l.userId) !== String(userId));
          room.speakersCount = room.speakers.length;
          room.listenersCount = room.listeners.length;
          LocalDbStore.rooms.set(id, room);

          if (io) {
            io.to(`room:${id}`).emit('user_left_room', { userId, isLive: room.isLive });
            io.to(`room:${id}`).emit('room_updated', {
              room,
              speakers: room.speakers,
              listeners: room.listeners
            });
          }
        }
      }

      res.json({ success: true, message: 'Left room' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
