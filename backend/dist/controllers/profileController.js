"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ProfileController = void 0;
const supabaseClient_1 = require("../integrations/supabase/supabaseClient");
const socketHandler_1 = require("../sockets/socketHandler");
const followController_1 = require("./followController");
class ProfileController {
    static async getProfile(req, res) {
        try {
            const id = String(req.params.id);
            const currentUserId = req.user?.id;
            let profile = supabaseClient_1.LocalDbStore.profiles.get(id);
            // If not in local store, fetch from Supabase
            if (!profile) {
                const supabase = (0, supabaseClient_1.getSupabase)();
                if (supabase) {
                    try {
                        const hasProfilesTable = await (0, supabaseClient_1.checkProfilesTableExists)();
                        let pRow = null;
                        if (hasProfilesTable) {
                            const { data } = await supabase.from('profiles').select('*').eq('id', id).single();
                            if (data)
                                pRow = data;
                        }
                        const { data: usrData } = await supabase.auth.admin.getUserById(id);
                        if (usrData?.user) {
                            profile = (0, supabaseClient_1.buildProfileFromSupabaseUser)(usrData.user, pRow);
                            supabaseClient_1.LocalDbStore.profiles.set(id, profile);
                        }
                    }
                    catch (_) { }
                }
            }
            if (!profile) {
                res.status(404).json({ success: false, error: { message: 'Profile not found.' } });
                return;
            }
            // Check block status
            if (currentUserId && supabaseClient_1.LocalDbStore.userBlocks.has(`${id}:${currentUserId}`)) {
                res.status(403).json({ success: false, error: { message: 'Profile unavailable.' } });
                return;
            }
            const presenceInfo = (0, socketHandler_1.getUserPresence)(id);
            const currentStatus = presenceInfo.status;
            const isOnline = presenceInfo.isOnline;
            const isFavourite = currentUserId ? supabaseClient_1.LocalDbStore.favourites.has(`${currentUserId}:${id}`) : false;
            const isFollowing = currentUserId ? followController_1.FollowController.isFollowing(currentUserId, id) : false;
            const isFollower = currentUserId ? followController_1.FollowController.isFollowing(id, currentUserId) : false;
            const followersCount = followController_1.FollowController.getFollowersCount(id);
            const followingCount = followController_1.FollowController.getFollowingCount(id);
            res.json({
                success: true,
                data: {
                    ...profile,
                    status: currentStatus,
                    presence: currentStatus,
                    isOnline,
                    isFavourite,
                    isFollowing,
                    isFollower,
                    followersCount,
                    followingCount,
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async updateProfile(req, res) {
        try {
            const userId = req.user?.id;
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const existing = supabaseClient_1.LocalDbStore.profiles.get(userId) || {};
            const updated = {
                ...existing,
                ...req.body,
                id: userId,
                updatedAt: new Date().toISOString()
            };
            supabaseClient_1.LocalDbStore.profiles.set(userId, updated);
            // Persist to Supabase
            const supabase = (0, supabaseClient_1.getSupabase)();
            if (supabase) {
                try {
                    await supabase.auth.admin.updateUserById(userId, {
                        user_metadata: {
                            username: updated.username,
                            displayName: updated.displayName,
                            dateOfBirth: updated.dateOfBirth,
                            gender: updated.gender,
                            location: updated.location,
                            bio: updated.bio,
                            avatarUrl: updated.avatarUrl,
                            coverUrl: updated.coverUrl,
                            voiceIntroUrl: updated.voiceIntroUrl,
                            voiceIntroDuration: updated.voiceIntroDuration,
                            interests: updated.interests,
                            languages: updated.languages
                        }
                    });
                    const hasProfilesTable = await (0, supabaseClient_1.checkProfilesTableExists)();
                    if (hasProfilesTable) {
                        await supabase.from('profiles').upsert({
                            id: userId,
                            username: updated.username,
                            display_name: updated.displayName,
                            date_of_birth: updated.dateOfBirth,
                            gender: updated.gender,
                            location: updated.location,
                            bio: updated.bio,
                            avatar_url: updated.avatarUrl,
                            cover_url: updated.coverUrl,
                            voice_intro_url: updated.voiceIntroUrl,
                            voice_intro_duration: updated.voiceIntroDuration,
                            languages: updated.languages,
                            hobbies: updated.interests
                        });
                    }
                }
                catch (sbErr) {
                    console.warn('[Profile] Supabase profile sync warning:', sbErr.message);
                }
            }
            res.json({
                success: true,
                data: updated
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async updateVoiceIntro(req, res) {
        try {
            const userId = req.user?.id;
            const { voiceIntroUrl, durationSeconds } = req.body;
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const existing = supabaseClient_1.LocalDbStore.profiles.get(userId) || {};
            existing.voiceIntroUrl = voiceIntroUrl;
            existing.voiceIntroDuration = durationSeconds || 15;
            supabaseClient_1.LocalDbStore.profiles.set(userId, existing);
            // Persist voice intro to Supabase
            const supabase = (0, supabaseClient_1.getSupabase)();
            if (supabase) {
                try {
                    await supabase.auth.admin.updateUserById(userId, {
                        user_metadata: {
                            voiceIntroUrl: existing.voiceIntroUrl,
                            voiceIntroDuration: existing.voiceIntroDuration
                        }
                    });
                    const hasProfilesTable = await (0, supabaseClient_1.checkProfilesTableExists)();
                    if (hasProfilesTable) {
                        await supabase.from('profiles').update({
                            voice_intro_url: existing.voiceIntroUrl,
                            voice_intro_duration: existing.voiceIntroDuration
                        }).eq('id', userId);
                    }
                }
                catch (_) { }
            }
            res.json({
                success: true,
                data: {
                    voiceIntroUrl: existing.voiceIntroUrl,
                    voiceIntroDuration: existing.voiceIntroDuration
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async updatePreferences(req, res) {
        try {
            const userId = req.user?.id;
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const existing = supabaseClient_1.LocalDbStore.preferences.get(userId) || { userId };
            const updated = {
                ...existing,
                ...req.body,
                updatedAt: new Date().toISOString()
            };
            supabaseClient_1.LocalDbStore.preferences.set(userId, updated);
            res.json({
                success: true,
                data: updated
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
}
exports.ProfileController = ProfileController;
