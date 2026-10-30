import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';

export class ProfileController {
  public static async getProfile(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const id = String(req.params.id);
      const currentUserId = req.user?.id;
      const profile = LocalDbStore.profiles.get(id);

      if (!profile) {
        res.status(404).json({ success: false, error: { message: 'Profile not found.' } });
        return;
      }

      // Check block status
      if (currentUserId && LocalDbStore.userBlocks.has(`${id}:${currentUserId}`)) {
        res.status(403).json({ success: false, error: { message: 'Profile unavailable.' } });
        return;
      }

      const presence = LocalDbStore.presence.get(id) || { status: 'offline' };
      const isFavourite = currentUserId ? LocalDbStore.favourites.has(`${currentUserId}:${id}`) : false;

      res.json({
        success: true,
        data: {
          ...profile,
          presence: presence.status,
          isFavourite,
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async updateProfile(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }

      const existing = LocalDbStore.profiles.get(userId) || {};
      const updated = {
        ...existing,
        ...req.body,
        id: userId,
        updatedAt: new Date().toISOString()
      };

      LocalDbStore.profiles.set(userId, updated);

      res.json({
        success: true,
        data: updated
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async updateVoiceIntro(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      const { voiceIntroUrl, durationSeconds } = req.body;

      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }

      const existing = LocalDbStore.profiles.get(userId) || {};
      existing.voiceIntroUrl = voiceIntroUrl;
      existing.voiceIntroDuration = durationSeconds || 15;
      LocalDbStore.profiles.set(userId, existing);

      res.json({
        success: true,
        data: {
          voiceIntroUrl: existing.voiceIntroUrl,
          voiceIntroDuration: existing.voiceIntroDuration
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async updatePreferences(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }

      const existing = LocalDbStore.preferences.get(userId) || { userId };
      const updated = {
        ...existing,
        ...req.body,
        updatedAt: new Date().toISOString()
      };

      LocalDbStore.preferences.set(userId, updated);

      res.json({
        success: true,
        data: updated
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
