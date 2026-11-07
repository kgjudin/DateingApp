import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore, getSupabase, buildProfileFromSupabaseUser } from '../integrations/supabase/supabaseClient';
import { AgoraService } from '../integrations/agora/agoraService';
import { getSocketIo, isUserOnline, getUserPresence } from '../sockets/socketHandler';

export class CallController {
  public static async initiateCall(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const callerId = req.user?.id;
      if (!callerId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { receiverId } = req.body;

      if (!receiverId) {
        res.status(400).json({ success: false, error: { message: 'Receiver ID is required.' } });
        return;
      }

      if (callerId === receiverId) {
        res.status(400).json({ success: false, error: { message: 'You cannot call yourself.' } });
        return;
      }

      // Check blocks
      if (LocalDbStore.userBlocks.has(`${callerId}:${receiverId}`) ||
          LocalDbStore.userBlocks.has(`${receiverId}:${callerId}`)) {
        res.status(403).json({ success: false, error: { message: 'Call not allowed due to user block settings.' } });
        return;
      }

      // Resolve Caller Profile from local store or Supabase
      let callerProfile = LocalDbStore.profiles.get(callerId);
      if (!callerProfile || !callerProfile.displayName || callerProfile.displayName === 'Vybe Caller') {
        const supabase = getSupabase();
        if (supabase) {
          try {
            const { data } = await supabase.auth.admin.getUserById(callerId);
            if (data?.user) {
              callerProfile = buildProfileFromSupabaseUser(data.user);
              LocalDbStore.profiles.set(callerId, callerProfile);
            }
          } catch (_) {}
        }
      }

      const callerName = req.user?.displayName || callerProfile?.displayName || callerProfile?.username || req.user?.username || req.user?.email?.split('@')[0] || 'Vybe Caller';
      const callerAvatar = callerProfile?.avatarUrl || `https://api.dicebear.com/7.x/avataaars/svg?seed=${callerProfile?.username || callerId}`;

      // Resolve Receiver Profile from local store or Supabase
      let receiverProfile = LocalDbStore.profiles.get(receiverId);
      if (!receiverProfile || !receiverProfile.displayName || receiverProfile.displayName === 'Vybe User') {
        const supabase = getSupabase();
        if (supabase) {
          try {
            const { data } = await supabase.auth.admin.getUserById(receiverId);
            if (data?.user) {
              receiverProfile = buildProfileFromSupabaseUser(data.user);
              LocalDbStore.profiles.set(receiverId, receiverProfile);
            }
          } catch (_) {}
        }
      }

      if (!receiverProfile) {
        receiverProfile = {
          id: receiverId,
          displayName: 'Vybe User',
          username: 'vyber',
          avatarUrl: `https://api.dicebear.com/7.x/avataaars/svg?seed=${receiverId}`,
          location: 'Online'
        };
        LocalDbStore.profiles.set(receiverId, receiverProfile);
      }

      const receiverName = receiverProfile.displayName || receiverProfile.username || 'Vybe User';
      const receiverAvatar = receiverProfile.avatarUrl || `https://api.dicebear.com/7.x/avataaars/svg?seed=${receiverProfile.username || receiverId}`;

      // Check receiver call permission preference
      const receiverPrefs = LocalDbStore.preferences.get(receiverId) || {};
      if (receiverPrefs.whoCanCallMe === 'nobody') {
        res.status(403).json({ success: false, error: { message: 'This user is not accepting calls currently.' } });
        return;
      }

      if (receiverPrefs.whoCanCallMe === 'favourites') {
        const isFav = LocalDbStore.favourites.has(`${receiverId}:${callerId}`);
        if (!isFav) {
          res.status(403).json({ success: false, error: { message: 'This user only accepts calls from their favourites.' } });
          return;
        }
      }

      // Create unique call session with short alphanumeric channelName strictly under 64 bytes (Agora requirement)
      const callId = `call_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
      const channelName = `vc_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;

      // Generate dynamic Agora tokens for both caller and receiver with universal numeric UID 0
      const callerAgora = AgoraService.generateRtcToken(channelName, 0, true);
      const receiverAgora = AgoraService.generateRtcToken(channelName, 0, true);

      const callerInfo = {
        id: callerId,
        displayName: callerName,
        username: callerProfile?.username || req.user?.username || 'vyber',
        avatarUrl: callerAvatar,
        location: callerProfile?.location || 'Online'
      };

      const receiverInfo = {
        id: receiverId,
        displayName: receiverName,
        username: receiverProfile.username || 'vyber',
        avatarUrl: receiverAvatar,
        location: receiverProfile.location || 'Online'
      };

      const callSession = {
        id: callId,
        callerId,
        receiverId,
        callerProfile: callerInfo,
        receiverProfile: receiverInfo,
        channelName,
        status: 'ringing',
        startedAt: new Date().toISOString(),
        callerAgoraToken: callerAgora.token,
        receiverAgoraToken: receiverAgora.token,
        appId: callerAgora.appId,
        expiresAt: callerAgora.expiresAt,
      };

      LocalDbStore.calls.set(callId, callSession);

      // Set caller presence to in_call
      LocalDbStore.presence.set(callerId, { userId: callerId, status: 'in_call', lastSeenAt: new Date().toISOString() });

      // Signal receiver via WebSockets / Push with full caller and receiver profiles
      const io = getSocketIo();
      if (io) {
        io.to(`user:${receiverId}`).emit('incoming_call', {
          callId,
          caller: callerInfo,
          receiver: receiverInfo,
          channelName,
          token: receiverAgora.token,
          appId: receiverAgora.appId
        });
      }

      res.status(201).json({
        success: true,
        data: {
          callId,
          channelName,
          token: callerAgora.token,
          appId: callerAgora.appId,
          caller: callerInfo,
          receiver: receiverInfo,
          status: 'ringing'
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async acceptCall(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const receiverId = req.user?.id;
      if (!receiverId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { callId } = req.body;

      let call = LocalDbStore.calls.get(callId);
      if (!call) {
        const fallbackChannel = `vc_${callId.replace(/[^a-zA-Z0-9]/g, '').substring(0, 30)}`;
        const fallbackToken = AgoraService.generateRtcToken(fallbackChannel, 0, true).token;
        call = {
          id: callId,
          callerId: 'peer',
          receiverId: receiverId,
          callerProfile: { id: 'peer', displayName: 'Vybe Caller', avatarUrl: '', location: 'Online' },
          receiverProfile: { id: receiverId, displayName: 'Vybe Receiver', avatarUrl: '', location: 'Online' },
          channelName: fallbackChannel,
          status: 'accepted',
          callerAgoraToken: fallbackToken,
          receiverAgoraToken: fallbackToken,
          appId: AgoraService.generateRtcToken(fallbackChannel, 0, true).appId,
          connectedAt: new Date().toISOString()
        };
        LocalDbStore.calls.set(callId, call);
      }

      call.status = 'accepted';
      call.connectedAt = new Date().toISOString();
      LocalDbStore.calls.set(callId, call);

      // Set receiver presence to in_call
      LocalDbStore.presence.set(receiverId, { userId: receiverId, status: 'in_call', lastSeenAt: new Date().toISOString() });

      // Notify caller via socket
      const io = getSocketIo();
      if (io) {
        io.to(`user:${call.callerId}`).emit('call_accepted', {
          callId,
          caller: call.callerProfile,
          receiver: call.receiverProfile,
          connectedAt: call.connectedAt
        });
      }

      res.json({
        success: true,
        data: {
          callId,
          channelName: call.channelName,
          token: call.receiverAgoraToken,
          appId: call.appId,
          caller: call.callerProfile,
          receiver: call.receiverProfile,
          status: 'accepted'
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async declineCall(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { callId, reason } = req.body;
      const call = LocalDbStore.calls.get(callId);

      if (call) {
        if (call.status === 'rejected' || call.status === 'ended') {
          res.json({ success: true, message: 'Call already terminated.' });
          return;
        }

        call.status = 'rejected';
        call.endReason = reason || 'declined';
        LocalDbStore.calls.set(callId, call);

        // Reset presence
        const callerStatus = isUserOnline(call.callerId) ? 'online' : 'offline';
        const receiverStatus = isUserOnline(call.receiverId) ? 'online' : 'offline';
        LocalDbStore.presence.set(call.callerId, { userId: call.callerId, status: callerStatus, lastSeenAt: new Date().toISOString() });
        LocalDbStore.presence.set(call.receiverId, { userId: call.receiverId, status: receiverStatus, lastSeenAt: new Date().toISOString() });

        // Record history for BOTH participants with their own direction context
        const histBase = {
          callId,
          callerId: call.callerId,
          receiverId: call.receiverId,
          callerName: call.callerProfile.displayName,
          callerAvatar: call.callerProfile.avatarUrl || '',
          receiverName: call.receiverProfile.displayName,
          receiverAvatar: call.receiverProfile.avatarUrl || '',
          status: 'missed',   // declined → show as missed on both sides
          duration: 0,
          createdAt: new Date().toISOString(),
        };
        // Caller's record — they made an outgoing call that was missed
        LocalDbStore.callHistory.unshift({
          ...histBase,
          id: `hist_${Date.now()}_caller`,
          userId: call.callerId,
          direction: 'outgoing',
          peerName: call.receiverProfile.displayName,
          peerAvatar: call.receiverProfile.avatarUrl || '',
          peerId: call.receiverId,
        });
        // Receiver's record — they missed an incoming call
        LocalDbStore.callHistory.unshift({
          ...histBase,
          id: `hist_${Date.now()}_receiver`,
          userId: call.receiverId,
          direction: 'incoming',
          peerName: call.callerProfile.displayName,
          peerAvatar: call.callerProfile.avatarUrl || '',
          peerId: call.callerId,
        });

        LocalDbStore.saveToDisk();

        const io = getSocketIo();
        if (io) {
          io.to(`user:${call.callerId}`).emit('call_declined', { callId, reason: call.endReason });
        }
      }

      res.json({ success: true, message: 'Call declined.' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async endCall(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { callId, durationSeconds } = req.body;
      const call = LocalDbStore.calls.get(callId);

      if (call) {
        if (call.status === 'ended') {
          res.json({ success: true, message: 'Call already ended.' });
          return;
        }

        call.status = 'ended';
        call.duration = durationSeconds || 0;
        call.endedAt = new Date().toISOString();
        LocalDbStore.calls.set(callId, call);

        // Reset presence
        const callerStatus = isUserOnline(call.callerId) ? 'online' : 'offline';
        const receiverStatus = isUserOnline(call.receiverId) ? 'online' : 'offline';
        LocalDbStore.presence.set(call.callerId, { userId: call.callerId, status: callerStatus, lastSeenAt: new Date().toISOString() });
        LocalDbStore.presence.set(call.receiverId, { userId: call.receiverId, status: receiverStatus, lastSeenAt: new Date().toISOString() });

        // Record history for BOTH participants with their own direction context
        const histBase = {
          callId,
          callerId: call.callerId,
          receiverId: call.receiverId,
          callerName: call.callerProfile.displayName,
          callerAvatar: call.callerProfile.avatarUrl || '',
          receiverName: call.receiverProfile.displayName,
          receiverAvatar: call.receiverProfile.avatarUrl || '',
          status: 'ended',
          duration: call.duration,
          createdAt: new Date().toISOString(),
        };
        // Caller's record — outgoing call
        LocalDbStore.callHistory.unshift({
          ...histBase,
          id: `hist_${Date.now()}_caller`,
          userId: call.callerId,
          direction: 'outgoing',
          peerName: call.receiverProfile.displayName,
          peerAvatar: call.receiverProfile.avatarUrl || '',
          peerId: call.receiverId,
        });
        // Receiver's record — incoming call
        LocalDbStore.callHistory.unshift({
          ...histBase,
          id: `hist_${Date.now()}_receiver`,
          userId: call.receiverId,
          direction: 'incoming',
          peerName: call.callerProfile.displayName,
          peerAvatar: call.callerProfile.avatarUrl || '',
          peerId: call.callerId,
        });

        LocalDbStore.saveToDisk();

        const io = getSocketIo();
        if (io) {
          io.to(`user:${call.callerId}`).emit('call_ended', { callId, duration: call.duration });
          io.to(`user:${call.receiverId}`).emit('call_ended', { callId, duration: call.duration });
        }
      }

      res.json({ success: true, message: 'Call ended successfully.' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async getCallHistory(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const rawUserId = req.user?.id;
      if (!rawUserId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const userId = String(rawUserId).trim().toLowerCase();

      // Filter STRICTLY to only records where this user participated (caller or receiver).
      // NEVER show any other user's calls.
      const history = LocalDbStore.callHistory
        .filter(h => {
          const hUserId = h.userId ? String(h.userId).trim().toLowerCase() : null;
          if (hUserId) {
            return hUserId === userId;
          }
          const cId = h.callerId ? String(h.callerId).trim().toLowerCase() : null;
          const rId = h.receiverId ? String(h.receiverId).trim().toLowerCase() : null;
          return cId === userId || rId === userId;
        })
        .map(h => {
          const cId = h.callerId ? String(h.callerId).trim().toLowerCase() : '';
          const rId = h.receiverId ? String(h.receiverId).trim().toLowerCase() : '';
          const isIncoming = h.direction
            ? h.direction === 'incoming'
            : (rId === userId);

          const peerId = h.peerId || (isIncoming ? h.callerId : h.receiverId);
          const peerName = h.peerName || (isIncoming ? (h.callerName || 'Caller') : (h.receiverName || 'User'));
          const peerAvatar = h.peerAvatar || (isIncoming ? (h.callerAvatar || '') : (h.receiverAvatar || ''));

          return {
            ...h,
            direction: isIncoming ? 'incoming' : 'outgoing',
            peerId,
            peerName,
            peerAvatar,
            status: h.status === 'rejected' ? 'missed' : (h.status || 'ended'),
          };
        });

      res.json({ success: true, data: history });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  // Favourites
  public static async toggleFavourite(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { targetUserId } = req.body;

      if (!targetUserId) {
        res.status(400).json({ success: false, error: { message: 'targetUserId required' } });
        return;
      }

      const key = `${userId}:${targetUserId}`;
      let isFavourite = false;

      if (LocalDbStore.favourites.has(key)) {
        LocalDbStore.favourites.delete(key);
        isFavourite = false;
      } else {
        LocalDbStore.favourites.add(key);
        isFavourite = true;
      }

      res.json({ success: true, data: { isFavourite, targetUserId } });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async getFavourites(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const favList: any[] = [];

      for (const item of LocalDbStore.favourites) {
        const [uId, favId] = item.split(':');
        if (uId === userId) {
          const profile = LocalDbStore.profiles.get(favId);
          if (profile) {
            const presenceInfo = getUserPresence(favId);
            favList.push({
              ...profile,
              status: presenceInfo.status,
              isOnline: presenceInfo.isOnline,
              isFavourite: true
            });
          }
        }
      }

      res.json({ success: true, data: favList });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
