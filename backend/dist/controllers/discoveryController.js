"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DiscoveryController = void 0;
exports.matchGender = matchGender;
const supabaseClient_1 = require("../integrations/supabase/supabaseClient");
const socketHandler_1 = require("../sockets/socketHandler");
/**
 * Universal helper to match profile gender against a filter query.
 * Handles 'women'/'female'/'woman', 'men'/'male'/'man', 'non_binary'/'non-binary'/'other', and 'everyone'.
 */
function matchGender(profileGender, targetFilter) {
    if (!targetFilter || targetFilter === 'everyone')
        return true;
    if (!profileGender)
        return false;
    const pg = String(profileGender).toLowerCase().trim();
    const tf = targetFilter.toLowerCase().trim();
    if (tf === 'women' || tf === 'female' || tf === 'woman') {
        return pg === 'female' || pg === 'women' || pg === 'woman';
    }
    if (tf === 'men' || tf === 'male' || tf === 'man') {
        return pg === 'male' || pg === 'men' || pg === 'man';
    }
    if (tf === 'non_binary' || tf === 'non-binary' || tf === 'other') {
        return pg === 'non_binary' || pg === 'non-binary' || pg === 'other';
    }
    return pg === tf;
}
class DiscoveryController {
    static async getDiscoveryFeed(req, res) {
        try {
            const currentUserId = req.user?.id;
            if (!currentUserId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const userPrefs = supabaseClient_1.LocalDbStore.preferences.get(currentUserId) || {
                preferredGenders: ['everyone'],
                discoveryEnabled: true,
            };
            const requestedGender = req.query.gender?.toLowerCase().trim();
            const preferredGenders = userPrefs.preferredGenders || ['everyone'];
            const allowsEveryone = preferredGenders.includes('everyone') || preferredGenders.length === 0;
            const allProfiles = Array.from(supabaseClient_1.LocalDbStore.profiles.values());
            const currentUserProfile = supabaseClient_1.LocalDbStore.profiles.get(currentUserId);
            const myInterests = currentUserProfile?.interests || [];
            // Filter eligible users
            const eligibleUsers = allProfiles
                .filter(p => p.id !== currentUserId)
                .filter(p => !p.isSuspended)
                .filter(p => {
                // Block filter
                if (supabaseClient_1.LocalDbStore.userBlocks.has(`${currentUserId}:${p.id}`) ||
                    supabaseClient_1.LocalDbStore.userBlocks.has(`${p.id}:${currentUserId}`)) {
                    return false;
                }
                // Discovery setting filter
                const targetPrefs = supabaseClient_1.LocalDbStore.preferences.get(p.id);
                if (targetPrefs && targetPrefs.discoveryEnabled === false) {
                    return false;
                }
                // Gender preference filter: query parameter overrides user profile preference
                if (requestedGender && requestedGender !== 'everyone') {
                    if (!matchGender(p.gender, requestedGender))
                        return false;
                }
                else if (!allowsEveryone) {
                    const genderMatches = preferredGenders.some(g => matchGender(p.gender, g));
                    if (!genderMatches)
                        return false;
                }
                return true;
            })
                .map(p => {
                const presenceInfo = (0, socketHandler_1.getUserPresence)(p.id);
                const currentStatus = presenceInfo.status;
                const isOnline = presenceInfo.isOnline;
                const sharedInterests = (p.interests || []).filter((item) => myInterests.includes(item));
                const isFavourite = supabaseClient_1.LocalDbStore.favourites.has(`${currentUserId}:${p.id}`);
                return {
                    ...p,
                    status: currentStatus,
                    isOnline,
                    sharedInterests,
                    sharedInterestsCount: sharedInterests.length,
                    isFavourite,
                };
            });
            // Sections
            const onlineNow = eligibleUsers.filter(u => u.isOnline || u.status === 'online' || u.status === 'in_call' || u.status === 'in_room');
            const basedOnInterests = [...eligibleUsers].sort((a, b) => b.sharedInterestsCount - a.sharedInterestsCount);
            const peopleYouMayLike = [...eligibleUsers].reverse();
            const newPeople = [...eligibleUsers];
            res.json({
                success: true,
                data: {
                    onlineNow,
                    basedOnInterests,
                    peopleYouMayLike,
                    newPeople,
                    totalEligible: eligibleUsers.length
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async searchUsers(req, res) {
        try {
            const currentUserId = req.user?.id;
            if (!currentUserId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const { query, gender, interest } = req.query;
            const q = (query || '').toLowerCase();
            const allProfiles = Array.from(supabaseClient_1.LocalDbStore.profiles.values());
            const results = allProfiles
                .filter(p => p.id !== currentUserId && !p.isSuspended)
                .filter(p => {
                if (q) {
                    const matchName = p.displayName?.toLowerCase().includes(q) || p.username?.toLowerCase().includes(q);
                    const matchBio = p.bio?.toLowerCase().includes(q);
                    if (!matchName && !matchBio)
                        return false;
                }
                if (gender && gender !== 'everyone' && !matchGender(p.gender, gender)) {
                    return false;
                }
                if (interest && (!p.interests || !p.interests.includes(interest))) {
                    return false;
                }
                return true;
            })
                .map(p => {
                const presence = (0, socketHandler_1.getUserPresence)(p.id);
                const isFavourite = supabaseClient_1.LocalDbStore.favourites.has(`${currentUserId}:${p.id}`);
                return {
                    ...p,
                    status: presence.status,
                    isOnline: presence.isOnline,
                    isFavourite
                };
            });
            res.json({
                success: true,
                data: results
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
}
exports.DiscoveryController = DiscoveryController;
