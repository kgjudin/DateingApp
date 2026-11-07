import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import {
  LocalDbStore,
  getSupabase,
  buildProfileFromSupabaseUser
} from '../integrations/supabase/supabaseClient';
import { isUserOnline, getSocketIo, getUserPresence, cleanUserId } from '../sockets/socketHandler';

export class FollowController {
  public static getFollowersCount(userId: string): number {
    const cleanId = cleanUserId(userId);
    let count = 0;
    for (const key of LocalDbStore.follows) {
      const parts = key.split(':');
      if (cleanUserId(parts[1]) === cleanId) count++;
    }
    return count;
  }

  public static getFollowingCount(userId: string): number {
    const cleanId = cleanUserId(userId);
    let count = 0;
    for (const key of LocalDbStore.follows) {
      const parts = key.split(':');
      if (cleanUserId(parts[0]) === cleanId) count++;
    }
    return count;
  }

  public static isFollowing(followerId: string, followingId: string): boolean {
    const fId = cleanUserId(followerId);
    const fgId = cleanUserId(followingId);
    for (const key of LocalDbStore.follows) {
      const [f, fg] = key.split(':');
      if (cleanUserId(f) === fId && cleanUserId(fg) === fgId) {
        return true;
      }
    }
    return false;
  }

  public static async toggleFollow(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const followerId = req.user?.id ? String(req.user.id).trim() : null;
      if (!followerId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }

      const rawTarget = req.body?.targetUserId;
      if (!rawTarget) {
        res.status(400).json({ success: false, error: { message: 'targetUserId is required' } });
        return;
      }
      const targetUserId = String(rawTarget).trim();

      if (followerId === targetUserId) {
        res.status(400).json({ success: false, error: { message: 'You cannot follow yourself' } });
        return;
      }

      const key = `${followerId}:${targetUserId}`;
      let isFollowing = false;
      const supabase = getSupabase();

      // Ensure follower profile is loaded in memory
      let followerProfile = LocalDbStore.profiles.get(followerId);
      if (!followerProfile && supabase) {
        try {
          const { data: usrData } = await supabase.auth.admin.getUserById(followerId);
          if (usrData?.user) {
            followerProfile = buildProfileFromSupabaseUser(usrData.user);
            LocalDbStore.profiles.set(followerId, followerProfile);
          }
        } catch (_) {}
      }

      // Ensure target user profile is loaded in memory
      let targetProfile = LocalDbStore.profiles.get(targetUserId);
      if (!targetProfile && supabase) {
        try {
          const { data: usrData } = await supabase.auth.admin.getUserById(targetUserId);
          if (usrData?.user) {
            targetProfile = buildProfileFromSupabaseUser(usrData.user);
            LocalDbStore.profiles.set(targetUserId, targetProfile);
          }
        } catch (_) {}
      }

      if (LocalDbStore.follows.has(key)) {
        // Unfollow
        LocalDbStore.follows.delete(key);
        LocalDbStore.favourites.delete(key);
        isFollowing = false;

        if (supabase) {
          try {
            await supabase.from('follows').delete().match({ follower_id: followerId, following_id: targetUserId });
          } catch (_) {}
        }
      } else {
        // Follow
        LocalDbStore.follows.add(key);
        LocalDbStore.favourites.add(key);
        isFollowing = true;

        if (supabase) {
          try {
            await supabase.from('follows').upsert({ follower_id: followerId, following_id: targetUserId });
          } catch (_) {}
        }

        // Send Rich Notification to user being followed
        const followerName = followerProfile?.displayName || req.user?.displayName || req.user?.username || 'Someone';
        const avatarUrl = followerProfile?.avatarUrl || `https://api.dicebear.com/7.x/avataaars/svg?seed=${followerName}`;

        const notifData = {
          id: `notif_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
          userId: targetUserId,
          type: 'new_follower',
          title: 'New Follower! 🎉',
          body: `${followerName} followed you! Follow back to meet when you're online.`,
          payload: {
            followerId,
            userId: followerId,
            displayName: followerName,
            username: followerProfile?.username || req.user?.username || 'vyber',
            avatarUrl,
          },
          isRead: false,
          createdAt: new Date().toISOString()
        };

        LocalDbStore.notifications.unshift(notifData);

        if (supabase) {
          try {
            await supabase.from('notifications').insert({
              user_id: targetUserId,
              type: 'new_follower',
              title: notifData.title,
              body: notifData.body,
              payload: notifData.payload,
              is_read: false
            });
          } catch (_) {}
        }

        // Emit real-time socket events: BOTH notification_received and new_follower
        const io = getSocketIo();
        if (io) {
          console.log(`[Follow] Emitting real-time new_follower notification to room user:${targetUserId}`);
          io.to(`user:${targetUserId}`).emit('notification_received', notifData);
          io.to(`user:${targetUserId}`).emit('new_follower', {
            followerId,
            followerName,
            avatarUrl,
            notification: notifData,
          });
        }
      }

      // Persist store to disk
      LocalDbStore.saveToDisk();

      const followersCount = FollowController.getFollowersCount(targetUserId);
      const followingCount = FollowController.getFollowingCount(targetUserId);

      res.json({
        success: true,
        data: {
          isFollowing,
          targetUserId,
          followersCount,
          followingCount
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async getFollowers(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const currentUserId = req.user?.id ? cleanUserId(req.user.id) : null;
      const targetUserId = req.params.userId ? cleanUserId(req.params.userId) : currentUserId;
      if (!targetUserId) {
        res.status(400).json({ success: false, error: { message: 'User ID is required' } });
        return;
      }

      const list: any[] = [];
      const supabase = getSupabase();

      for (const item of LocalDbStore.follows) {
        const [followerId, followingId] = item.split(':');
        if (cleanUserId(followingId) === targetUserId) {
          let profile = LocalDbStore.profiles.get(followerId);
          if (!profile && supabase) {
            try {
              const { data: usrData } = await supabase.auth.admin.getUserById(followerId);
              if (usrData?.user) {
                profile = buildProfileFromSupabaseUser(usrData.user);
                LocalDbStore.profiles.set(followerId, profile);
              }
            } catch (_) {}
          }
          if (profile) {
            const presenceInfo = getUserPresence(followerId);
            list.push({
              ...profile,
              status: presenceInfo.status,
              isOnline: presenceInfo.isOnline,
              isFollowing: currentUserId ? FollowController.isFollowing(currentUserId, followerId) : false
            });
          }
        }
      }

      res.json({ success: true, data: list });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async getFollowing(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const currentUserId = req.user?.id ? cleanUserId(req.user.id) : null;
      const targetUserId = req.params.userId ? cleanUserId(req.params.userId) : currentUserId;
      if (!targetUserId) {
        res.status(400).json({ success: false, error: { message: 'User ID is required' } });
        return;
      }

      const list: any[] = [];
      const supabase = getSupabase();

      for (const item of LocalDbStore.follows) {
        const [followerId, followingId] = item.split(':');
        if (cleanUserId(followerId) === targetUserId) {
          let profile = LocalDbStore.profiles.get(followingId);
          if (!profile && supabase) {
            try {
              const { data: usrData } = await supabase.auth.admin.getUserById(followingId);
              if (usrData?.user) {
                profile = buildProfileFromSupabaseUser(usrData.user);
                LocalDbStore.profiles.set(followingId, profile);
              }
            } catch (_) {}
          }
          if (profile) {
            const presenceInfo = getUserPresence(followingId);
            list.push({
              ...profile,
              status: presenceInfo.status,
              isOnline: presenceInfo.isOnline,
              isFollowing: currentUserId ? FollowController.isFollowing(currentUserId, followingId) : true
            });
          }
        }
      }

      res.json({ success: true, data: list });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
