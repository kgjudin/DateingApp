import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';
import { AgoraService } from '../integrations/agora/agoraService';
import { getSocketIo } from '../sockets/socketHandler';

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

      const receiverProfile = LocalDbStore.profiles.get(receiverId);
      if (!receiverProfile) {
        res.status(404).json({ success: false, error: { message: 'User not found.' } });
        return;
      }

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

      // Create unique call session
      const callId = `call_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
      const channelName = `vybe_call_${callerId}_${receiverId}_${Date.now()}`;

      // Generate dynamic Agora tokens for both caller and receiver
      const callerAgora = AgoraService.generateRtcToken(channelName, callerId, true);
      const receiverAgora = AgoraService.generateRtcToken(channelName, receiverId, true);

      const callerProfile = LocalDbStore.profiles.get(callerId) || { displayName: 'Vybe Caller', avatarUrl: '' };

      const callSession = {
        id: callId,
        callerId,
        receiverId,
        callerProfile: {
          id: callerId,
          displayName: callerProfile.displayName,
          username: callerProfile.username,
          avatarUrl: callerProfile.avatarUrl,
          location: callerProfile.location
        },
        receiverProfile: {
          id: receiverId,
          displayName: receiverProfile.displayName,
          username: receiverProfile.username,
          avatarUrl: receiverProfile.avatarUrl,
          location: receiverProfile.location
        },
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

      // Signal receiver via WebSockets / Push
      const io = getSocketIo();
      if (io) {
        io.to(`user:${receiverId}`).emit('incoming_call', {
          callId,
          caller: callSession.callerProfile,
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
          receiver: callSession.receiverProfile,
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

      const call = LocalDbStore.calls.get(callId);
      if (!call) {
        res.status(404).json({ success: false, error: { message: 'Call session not found.' } });
        return;
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
        call.status = 'rejected';
        call.endReason = reason || 'declined';
        LocalDbStore.calls.set(callId, call);

        // Reset presence
        LocalDbStore.presence.set(call.callerId, { userId: call.callerId, status: 'online', lastSeenAt: new Date().toISOString() });
        LocalDbStore.presence.set(call.receiverId, { userId: call.receiverId, status: 'online', lastSeenAt: new Date().toISOString() });

        // Record history
        LocalDbStore.callHistory.unshift({
          id: `hist_${Date.now()}`,
          callId,
          callerId: call.callerId,
          receiverId: call.receiverId,
          callerName: call.callerProfile.displayName,
          receiverName: call.receiverProfile.displayName,
          status: 'rejected',
          duration: 0,
          createdAt: new Date().toISOString()
        });

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
        call.status = 'ended';
        call.duration = durationSeconds || 0;
        call.endedAt = new Date().toISOString();
        LocalDbStore.calls.set(callId, call);

        // Reset presence
        LocalDbStore.presence.set(call.callerId, { userId: call.callerId, status: 'online', lastSeenAt: new Date().toISOString() });
        LocalDbStore.presence.set(call.receiverId, { userId: call.receiverId, status: 'online', lastSeenAt: new Date().toISOString() });

        // Record history
        LocalDbStore.callHistory.unshift({
          id: `hist_${Date.now()}`,
          callId,
          callerId: call.callerId,
          receiverId: call.receiverId,
          callerName: call.callerProfile.displayName,
          receiverName: call.receiverProfile.displayName,
          status: 'ended',
          duration: call.duration,
          createdAt: new Date().toISOString()
        });

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
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const history = LocalDbStore.callHistory.filter(
        h => h.callerId === userId || h.receiverId === userId
      );

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
            const presence = LocalDbStore.presence.get(favId) || { status: 'offline' };
            favList.push({
              ...profile,
              status: presence.status,
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
