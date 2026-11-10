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

  /**
   * Persists call history entry into LocalDbStore, local_db.json, and Supabase Cloud.
   */
  public static async recordHistoryItem(entry: {
    id?: string;
    callId: string;
    userId: string;
    direction: 'incoming' | 'outgoing';
    peerId: string;
    peerName: string;
    peerAvatar: string;
    callerId: string;
    callerName: string;
    callerAvatar: string;
    receiverId: string;
    receiverName: string;
    receiverAvatar: string;
    status: 'ended' | 'missed' | 'rejected' | 'busy' | 'cancelled';
    duration: number;
    createdAt?: string;
  }): Promise<void> {
    if (!entry.userId) return;

    const record = {
      id: entry.id || `hist_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
      callId: entry.callId,
      userId: entry.userId,
      direction: entry.direction,
      peerId: entry.peerId,
      peerName: entry.peerName,
      peerAvatar: entry.peerAvatar,
      callerId: entry.callerId,
      callerName: entry.callerName,
      callerAvatar: entry.callerAvatar,
      receiverId: entry.receiverId,
      receiverName: entry.receiverName,
      receiverAvatar: entry.receiverAvatar,
      status: entry.status,
      duration: Number(entry.duration) || 0,
      createdAt: entry.createdAt || new Date().toISOString(),
    };

    // Replace if same callId and userId already exists, otherwise prepend
    const existingIndex = LocalDbStore.callHistory.findIndex(
      h => h.callId === record.callId && String(h.userId).toLowerCase() === String(record.userId).toLowerCase()
    );
    if (existingIndex >= 0) {
      LocalDbStore.callHistory[existingIndex] = record;
    } else {
      LocalDbStore.callHistory.unshift(record);
    }
    if (LocalDbStore.callHistory.length > 500) {
      LocalDbStore.callHistory = LocalDbStore.callHistory.slice(0, 500);
    }
    LocalDbStore.saveToDisk();

    // Persist to Supabase Cloud
    const supabase = getSupabase();
    if (supabase) {
      try {
        // Try public.call_history table if it exists in the schema
        try {
          const { error: chErr } = await supabase.from('call_history').insert({
            call_id: record.callId,
            user_id: record.userId,
            peer_id: record.peerId,
            other_user_id: record.peerId,
            peer_name: record.peerName,
            peer_avatar: record.peerAvatar,
            direction: record.direction,
            status: record.status === 'rejected' ? 'missed' : record.status,
            duration: record.duration,
            created_at: record.createdAt,
          });
          if (chErr) console.warn('[CallController] Supabase call_history insert notice:', chErr.message);
        } catch (e: any) {
          console.warn('[CallController] Supabase call_history exception:', e.message);
        }

        // Store in user_metadata so user never loses history across server restarts or redeploys
        const { data } = await supabase.auth.admin.getUserById(record.userId);
        if (data?.user) {
          const currentList: any[] = Array.isArray(data.user.user_metadata?.call_history)
            ? data.user.user_metadata.call_history
            : [];
          const deduped = [record, ...currentList.filter((c: any) => c.callId !== record.callId)].slice(0, 50);
          await supabase.auth.admin.updateUserById(record.userId, {
            user_metadata: {
              ...data.user.user_metadata,
              call_history: deduped,
            }
          });
        }
      } catch (e: any) {
        console.warn(`[CallController] Supabase history sync notice for ${record.userId}:`, e.message);
      }
    }
  }

  public static async declineCall(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const rawUserId = req.user?.id;
      const { callId, reason, callerId: passedCallerId, callerProfile: passedCallerProfile } = req.body;
      let call = callId ? LocalDbStore.calls.get(callId) : null;

      const receiverId = rawUserId || call?.receiverId || '';
      const callerId = call?.callerId || passedCallerId || '';

      if (call) {
        if (call.status === 'rejected' || call.status === 'ended') {
          res.json({ success: true, message: 'Call already terminated.' });
          return;
        }

        call.status = 'rejected';
        call.endReason = reason || 'declined';
        LocalDbStore.calls.set(callId, call);
      }

      // Reset presence
      if (callerId) {
        const callerStatus = isUserOnline(callerId) ? 'online' : 'offline';
        LocalDbStore.presence.set(callerId, { userId: callerId, status: callerStatus, lastSeenAt: new Date().toISOString() });
      }
      if (receiverId) {
        const receiverStatus = isUserOnline(receiverId) ? 'online' : 'offline';
        LocalDbStore.presence.set(receiverId, { userId: receiverId, status: receiverStatus, lastSeenAt: new Date().toISOString() });
      }

      // Resolve caller & receiver names/avatars
      let callerName = call?.callerProfile?.displayName || passedCallerProfile?.displayName || 'Vybe Caller';
      let callerAvatar = call?.callerProfile?.avatarUrl || passedCallerProfile?.avatarUrl || '';
      let receiverName = call?.receiverProfile?.displayName || req.user?.displayName || req.user?.username || 'Vybe User';
      let receiverAvatar = call?.receiverProfile?.avatarUrl || '';

      if (callerId && (!callerName || callerName === 'Vybe Caller')) {
        const cp = LocalDbStore.profiles.get(callerId);
        if (cp) {
          callerName = cp.displayName || cp.username || callerName;
          callerAvatar = cp.avatarUrl || callerAvatar;
        }
      }

      const finalCallId = callId || `call_${Date.now()}`;

      // Caller record — made an outgoing call that was missed/declined
      if (callerId) {
        await CallController.recordHistoryItem({
          callId: finalCallId,
          userId: callerId,
          direction: 'outgoing',
          peerId: receiverId || 'unknown',
          peerName: receiverName,
          peerAvatar: receiverAvatar,
          callerId,
          callerName,
          callerAvatar,
          receiverId: receiverId || 'unknown',
          receiverName,
          receiverAvatar,
          status: 'missed',
          duration: 0,
        });
      }

      // Receiver record — missed an incoming call
      if (receiverId) {
        await CallController.recordHistoryItem({
          callId: finalCallId,
          userId: receiverId,
          direction: 'incoming',
          peerId: callerId || 'unknown',
          peerName: callerName,
          peerAvatar: callerAvatar,
          callerId: callerId || 'unknown',
          callerName,
          callerAvatar,
          receiverId,
          receiverName,
          receiverAvatar,
          status: 'missed',
          duration: 0,
        });
      }

      const io = getSocketIo();
      if (io && callerId) {
        io.to(`user:${callerId}`).emit('call_declined', { callId: finalCallId, reason: reason || 'declined' });
      }

      res.json({ success: true, message: 'Call declined.' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async endCall(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const rawUserId = req.user?.id;
      const { callId, durationSeconds, peerId: passedPeerId, peerName: passedPeerName, peerAvatar: passedPeerAvatar } = req.body;
      const duration = Number(durationSeconds) || 0;
      let call = callId ? LocalDbStore.calls.get(callId) : null;

      let callerId = call?.callerId || '';
      let receiverId = call?.receiverId || '';

      // If call session was not in memory, reconstruct participants using req.user.id and passedPeerId
      if (!call && rawUserId && passedPeerId) {
        callerId = rawUserId;
        receiverId = passedPeerId;
      }

      const wasRinging = call?.status === 'ringing';
      if (call) {
        if (call.status === 'ended') {
          res.json({ success: true, message: 'Call already ended.' });
          return;
        }

        call.status = 'ended';
        call.duration = duration;
        call.endedAt = new Date().toISOString();
        LocalDbStore.calls.set(callId, call);
      }

      // Reset presence
      if (callerId) {
        const callerStatus = isUserOnline(callerId) ? 'online' : 'offline';
        LocalDbStore.presence.set(callerId, { userId: callerId, status: callerStatus, lastSeenAt: new Date().toISOString() });
      }
      if (receiverId) {
        const receiverStatus = isUserOnline(receiverId) ? 'online' : 'offline';
        LocalDbStore.presence.set(receiverId, { userId: receiverId, status: receiverStatus, lastSeenAt: new Date().toISOString() });
      }

      // Resolve caller profile
      let callerName = call?.callerProfile?.displayName;
      let callerAvatar = call?.callerProfile?.avatarUrl || '';
      let receiverName = call?.receiverProfile?.displayName || passedPeerName;
      let receiverAvatar = call?.receiverProfile?.avatarUrl || passedPeerAvatar || '';

      if (!callerName && callerId) {
        const cp = LocalDbStore.profiles.get(callerId);
        callerName = cp?.displayName || cp?.username || (rawUserId === callerId ? req.user?.displayName : 'Vybe Caller');
        callerAvatar = cp?.avatarUrl || callerAvatar;
      }
      if (!receiverName && receiverId) {
        const rp = LocalDbStore.profiles.get(receiverId);
        receiverName = rp?.displayName || rp?.username || (rawUserId === receiverId ? req.user?.displayName : 'Vybe User');
        receiverAvatar = rp?.avatarUrl || receiverAvatar;
      }

      callerName = callerName || 'Vybe Caller';
      receiverName = receiverName || 'Vybe User';

      const finalCallId = callId || `call_${Date.now()}`;

      // Status logic:
      // If duration is 0 or was cancelled while ringing:
      // Caller: ended with 0s
      // Receiver: missed
      // If duration > 0:
      // Both: ended with duration
      const callerStatus = 'ended';
      const receiverStatus = (duration > 0 && !wasRinging) ? 'ended' : 'missed';

      if (callerId) {
        await CallController.recordHistoryItem({
          callId: finalCallId,
          userId: callerId,
          direction: 'outgoing',
          peerId: receiverId || 'unknown',
          peerName: receiverName,
          peerAvatar: receiverAvatar,
          callerId,
          callerName,
          callerAvatar,
          receiverId: receiverId || 'unknown',
          receiverName,
          receiverAvatar,
          status: callerStatus,
          duration,
        });
      }

      if (receiverId && receiverId !== 'unknown') {
        await CallController.recordHistoryItem({
          callId: finalCallId,
          userId: receiverId,
          direction: 'incoming',
          peerId: callerId || 'unknown',
          peerName: callerName,
          peerAvatar: callerAvatar,
          callerId: callerId || 'unknown',
          callerName,
          callerAvatar,
          receiverId,
          receiverName,
          receiverAvatar,
          status: receiverStatus,
          duration,
        });
      }

      const io = getSocketIo();
      if (io) {
        if (callerId) io.to(`user:${callerId}`).emit('call_ended', { callId: finalCallId, duration });
        if (receiverId) io.to(`user:${receiverId}`).emit('call_ended', { callId: finalCallId, duration });
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

      // In-memory / local_db matches
      const localMatches = LocalDbStore.callHistory
        .filter(h => {
          const hUserId = h.userId ? String(h.userId).trim().toLowerCase() : null;
          if (hUserId) return hUserId === userId;
          const cId = h.callerId ? String(h.callerId).trim().toLowerCase() : null;
          const rId = h.receiverId ? String(h.receiverId).trim().toLowerCase() : null;
          return cId === userId || rId === userId;
        });

      // Supabase matches (both table and user_metadata)
      let cloudMatches: any[] = [];
      const supabase = getSupabase();
      if (supabase) {
        try {
          const { data: dbRows } = await supabase
            .from('call_history')
            .select('*')
            .eq('user_id', userId);
          if (Array.isArray(dbRows)) {
            cloudMatches.push(...dbRows.map(r => ({
              id: r.id,
              callId: r.call_id,
              userId: r.user_id,
              peerId: r.peer_id || r.other_user_id,
              peerName: r.peer_name,
              peerAvatar: r.peer_avatar,
              direction: r.direction,
              status: r.status,
              duration: r.duration,
              createdAt: r.created_at
            })));
          }
        } catch (_) {}

        try {
          const { data } = await supabase.auth.admin.getUserById(userId);
          if (Array.isArray(data?.user?.user_metadata?.call_history)) {
            cloudMatches.push(...data.user.user_metadata.call_history);
          }
        } catch (_) {}
      }

      // Merge and deduplicate
      const combined = [...localMatches, ...cloudMatches];
      const seen = new Set<string>();
      const deduped: any[] = [];

      for (const item of combined) {
        const key = item.callId ? `${item.callId}_${item.direction || ''}` : (item.id || JSON.stringify(item));
        if (!seen.has(key)) {
          seen.add(key);
          deduped.push(item);
        }
      }

      const history = deduped
        .map(h => {
          const cId = h.callerId ? String(h.callerId).trim().toLowerCase() : '';
          const rId = h.receiverId ? String(h.receiverId).trim().toLowerCase() : '';
          const isIncoming = h.direction
            ? h.direction === 'incoming'
            : (rId === userId);

          const peerId = h.peerId || (isIncoming ? h.callerId : h.receiverId);
          let peerName = h.peerName || (isIncoming ? (h.callerName || 'Caller') : (h.receiverName || 'User'));
          let peerAvatar = h.peerAvatar || (isIncoming ? (h.callerAvatar || '') : (h.receiverAvatar || ''));

          if ((!peerName || peerName === 'Caller' || peerName === 'User') && peerId) {
            const p = LocalDbStore.profiles.get(peerId);
            if (p) {
              peerName = p.displayName || p.username || peerName;
              peerAvatar = p.avatarUrl || peerAvatar;
            }
          }

          return {
            ...h,
            userId,
            direction: isIncoming ? 'incoming' : 'outgoing',
            peerId,
            peerName,
            peerAvatar,
            status: h.status === 'rejected' ? 'missed' : (h.status || 'ended'),
            duration: Number(h.duration) || 0,
            createdAt: h.createdAt || new Date().toISOString(),
          };
        })
        .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

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
