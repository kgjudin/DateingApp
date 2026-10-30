import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';

export class DiscoveryController {
  public static async getDiscoveryFeed(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const currentUserId = req.user?.id || 'user-elena-101';
      const userPrefs = LocalDbStore.preferences.get(currentUserId) || {
        preferredGenders: ['everyone'],
        discoveryEnabled: true,
      };

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
          // Gender preference filter
          if (!allowsEveryone) {
            const genderMatches = preferredGenders.some(g => {
              if (g === 'men' && p.gender === 'male') return true;
              if (g === 'women' && p.gender === 'female') return true;
              if (g === 'non_binary' && p.gender === 'non_binary') return true;
              return false;
            });
            if (!genderMatches) return false;
          }
          return true;
        })
        .map(p => {
          const presence = LocalDbStore.presence.get(p.id) || { status: 'offline' };
          const sharedInterests = (p.interests || []).filter((item: string) => myInterests.includes(item));
          const isFavourite = LocalDbStore.favourites.has(`${currentUserId}:${p.id}`);

          return {
            ...p,
            status: presence.status,
            sharedInterests,
            sharedInterestsCount: sharedInterests.length,
            isFavourite,
          };
        });

      // Sections
      const onlineNow = eligibleUsers.filter(u => u.status === 'online');
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
      const currentUserId = req.user?.id || 'user-elena-101';
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
          if (gender && gender !== 'everyone' && p.gender !== gender) {
            return false;
          }
          if (interest && (!p.interests || !p.interests.includes(interest))) {
            return false;
          }
          return true;
        })
        .map(p => {
          const presence = LocalDbStore.presence.get(p.id) || { status: 'offline' };
          const isFavourite = LocalDbStore.favourites.has(`${currentUserId}:${p.id}`);
          return {
            ...p,
            status: presence.status,
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
