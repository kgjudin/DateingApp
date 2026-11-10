"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FollowController = void 0;
const supabaseClient_1 = require("../integrations/supabase/supabaseClient");
const socketHandler_1 = require("../sockets/socketHandler");
class FollowController {
    static getFollowersCount(userId) {
        const cleanId = (0, socketHandler_1.cleanUserId)(userId);
        let count = 0;
        for (const key of supabaseClient_1.LocalDbStore.follows) {
            const parts = key.split(':');
            if ((0, socketHandler_1.cleanUserId)(parts[1]) === cleanId)
                count++;
        }
        return count;
    }
    static getFollowingCount(userId) {
        const cleanId = (0, socketHandler_1.cleanUserId)(userId);
        let count = 0;
        for (const key of supabaseClient_1.LocalDbStore.follows) {
            const parts = key.split(':');
            if ((0, socketHandler_1.cleanUserId)(parts[0]) === cleanId)
                count++;
        }
        return count;
    }
    static isFollowing(followerId, followingId) {
        const fId = (0, socketHandler_1.cleanUserId)(followerId);
        const fgId = (0, socketHandler_1.cleanUserId)(followingId);
        for (const key of supabaseClient_1.LocalDbStore.follows) {
            const [f, fg] = key.split(':');
            if ((0, socketHandler_1.cleanUserId)(f) === fId && (0, socketHandler_1.cleanUserId)(fg) === fgId) {
                return true;
            }
        }
        return false;
    }
    static async toggleFollow(req, res) {
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
            const supabase = (0, supabaseClient_1.getSupabase)();
            // Ensure follower profile is loaded in memory
            let followerProfile = supabaseClient_1.LocalDbStore.profiles.get(followerId);
            if (!followerProfile && supabase) {
                try {
                    const { data: usrData } = await supabase.auth.admin.getUserById(followerId);
                    if (usrData?.user) {
                        followerProfile = (0, supabaseClient_1.buildProfileFromSupabaseUser)(usrData.user);
                        supabaseClient_1.LocalDbStore.profiles.set(followerId, followerProfile);
                    }
                }
                catch (_) { }
            }
            // Ensure target user profile is loaded in memory
            let targetProfile = supabaseClient_1.LocalDbStore.profiles.get(targetUserId);
            if (!targetProfile && supabase) {
                try {
                    const { data: usrData } = await supabase.auth.admin.getUserById(targetUserId);
                    if (usrData?.user) {
                        targetProfile = (0, supabaseClient_1.buildProfileFromSupabaseUser)(usrData.user);
                        supabaseClient_1.LocalDbStore.profiles.set(targetUserId, targetProfile);
                    }
                }
                catch (_) { }
            }
            if (supabaseClient_1.LocalDbStore.follows.has(key)) {
                // Unfollow
                supabaseClient_1.LocalDbStore.follows.delete(key);
                supabaseClient_1.LocalDbStore.favourites.delete(key);
                isFollowing = false;
                if (supabase) {
                    try {
                        await supabase.from('follows').delete().match({ follower_id: followerId, following_id: targetUserId });
                    }
                    catch (_) { }
                }
            }
            else {
                // Follow
                supabaseClient_1.LocalDbStore.follows.add(key);
                supabaseClient_1.LocalDbStore.favourites.add(key);
                isFollowing = true;
                if (supabase) {
                    try {
                        await supabase.from('follows').upsert({ follower_id: followerId, following_id: targetUserId });
                    }
                    catch (_) { }
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
                supabaseClient_1.LocalDbStore.notifications.unshift(notifData);
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
                    }
                    catch (_) { }
                }
                // Emit real-time socket events: BOTH notification_received and new_follower
                const io = (0, socketHandler_1.getSocketIo)();
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
            supabaseClient_1.LocalDbStore.saveToDisk();
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
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async getFollowers(req, res) {
        try {
            const currentUserId = req.user?.id ? (0, socketHandler_1.cleanUserId)(req.user.id) : null;
            const targetUserId = req.params.userId ? (0, socketHandler_1.cleanUserId)(req.params.userId) : currentUserId;
            if (!targetUserId) {
                res.status(400).json({ success: false, error: { message: 'User ID is required' } });
                return;
            }
            const list = [];
            const supabase = (0, supabaseClient_1.getSupabase)();
            for (const item of supabaseClient_1.LocalDbStore.follows) {
                const [followerId, followingId] = item.split(':');
                if ((0, socketHandler_1.cleanUserId)(followingId) === targetUserId) {
                    let profile = supabaseClient_1.LocalDbStore.profiles.get(followerId);
                    if (!profile && supabase) {
                        try {
                            const { data: usrData } = await supabase.auth.admin.getUserById(followerId);
                            if (usrData?.user) {
                                profile = (0, supabaseClient_1.buildProfileFromSupabaseUser)(usrData.user);
                                supabaseClient_1.LocalDbStore.profiles.set(followerId, profile);
                            }
                        }
                        catch (_) { }
                    }
                    if (profile) {
                        const presenceInfo = (0, socketHandler_1.getUserPresence)(followerId);
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
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async getFollowing(req, res) {
        try {
            const currentUserId = req.user?.id ? (0, socketHandler_1.cleanUserId)(req.user.id) : null;
            const targetUserId = req.params.userId ? (0, socketHandler_1.cleanUserId)(req.params.userId) : currentUserId;
            if (!targetUserId) {
                res.status(400).json({ success: false, error: { message: 'User ID is required' } });
                return;
            }
            const list = [];
            const supabase = (0, supabaseClient_1.getSupabase)();
            for (const item of supabaseClient_1.LocalDbStore.follows) {
                const [followerId, followingId] = item.split(':');
                if ((0, socketHandler_1.cleanUserId)(followerId) === targetUserId) {
                    let profile = supabaseClient_1.LocalDbStore.profiles.get(followingId);
                    if (!profile && supabase) {
                        try {
                            const { data: usrData } = await supabase.auth.admin.getUserById(followingId);
                            if (usrData?.user) {
                                profile = (0, supabaseClient_1.buildProfileFromSupabaseUser)(usrData.user);
                                supabaseClient_1.LocalDbStore.profiles.set(followingId, profile);
                            }
                        }
                        catch (_) { }
                    }
                    if (profile) {
                        const presenceInfo = (0, socketHandler_1.getUserPresence)(followingId);
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
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
}
exports.FollowController = FollowController;
