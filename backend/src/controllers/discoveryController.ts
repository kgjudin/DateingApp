import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';
import { isUserOnline, getUserPresence } from '../sockets/socketHandler';

/**
 * Universal helper to match profile gender against a filter query.
 * Handles 'women'/'female'/'woman', 'men'/'male'/'man', 'non_binary'/'non-binary'/'other', and 'everyone'.
 */
export function matchGender(profileGender: any, targetFilter?: string): boolean {
  if (!targetFilter || targetFilter === 'everyone') return true;
  if (!profileGender) return false;
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

export class DiscoveryController {
  public static async getDiscoveryFeed(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const currentUserId = req.user?.id;
      if (!currentUserId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const userPrefs = LocalDbStore.preferences.get(currentUserId) || {
        preferredGenders: ['everyone'],
        discoveryEnabled: true,
      };

      const requestedGender = (req.query.gender as string)?.toLowerCase().trim();
      const preferredGenders: string[] = userPrefs.preferredGenders || ['everyone'];
      const allowsEveryone = preferredGenders.includes('everyone') || preferredGenders.length === 0;

      const allProfiles = Array.from(LocalDbStore.profiles.values());
      const currentUserProfile = LocalDbStore.profiles.get(currentUserId);
      const myInterests: string[] = currentUserProfile?.interests || [];

      // Filter eligible users
      const eligibleUsers = allProfiles
        .filter(p => p.id !== currentUserId)
        .filter(p => !p.isSuspended)
        .filter(p => {
          // Block filter
          if (LocalDbStore.userBlocks.has(`${currentUserId}:${p.id}`) ||
              LocalDbStore.userBlocks.has(`${p.id}:${currentUserId}`)) {
            return false;
          }
          // Discovery setting filter
          const targetPrefs = LocalDbStore.preferences.get(p.id);
          if (targetPrefs && targetPrefs.discoveryEnabled === false) {
            return false;
          }
          // Gender preference filter: query parameter overrides user profile preference
          if (requestedGender && requestedGender !== 'everyone') {
            if (!matchGender(p.gender, requestedGender)) return false;
          } else if (!allowsEveryone) {
            const genderMatches = preferredGenders.some(g => matchGender(p.gender, g));
            if (!genderMatches) return false;
          }
          return true;
        })
        .map(p => {
          const presenceInfo = getUserPresence(p.id);
          const currentStatus = presenceInfo.status;
          const isOnline = presenceInfo.isOnline;
          const sharedInterests = (p.interests || []).filter((item: string) => myInterests.includes(item));
          const isFavourite = LocalDbStore.favourites.has(`${currentUserId}:${p.id}`);

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
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async searchUsers(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const currentUserId = req.user?.id;
      if (!currentUserId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }
      const { query, gender, interest } = req.query;

      const q = (query as string || '').toLowerCase();
      const allProfiles = Array.from(LocalDbStore.profiles.values());

      const results = allProfiles
        .filter(p => p.id !== currentUserId && !p.isSuspended)
        .filter(p => {
          if (q) {
            const matchName = p.displayName?.toLowerCase().includes(q) || p.username?.toLowerCase().includes(q);
            const matchBio = p.bio?.toLowerCase().includes(q);
            if (!matchName && !matchBio) return false;
          }
          if (gender && gender !== 'everyone' && !matchGender(p.gender, gender as string)) {
            return false;
          }
          if (interest && (!p.interests || !p.interests.includes(interest))) {
            return false;
          }
          return true;
        })
        .map(p => {
          const presence = getUserPresence(p.id);
          const isFavourite = LocalDbStore.favourites.has(`${currentUserId}:${p.id}`);
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
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
