import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import {
  LocalDbStore,
  getSupabase,
  checkProfilesTableExists,
  buildProfileFromSupabaseUser
} from '../integrations/supabase/supabaseClient';

export class ProfileController {
  public static async getProfile(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const id = String(req.params.id);
      const currentUserId = req.user?.id;
      let profile = LocalDbStore.profiles.get(id);

      // If not in local store, fetch from Supabase
      if (!profile) {
        const supabase = getSupabase();
        if (supabase) {
          try {
            const hasProfilesTable = await checkProfilesTableExists();
            let pRow: any = null;
            if (hasProfilesTable) {
              const { data } = await supabase.from('profiles').select('*').eq('id', id).single();
              if (data) pRow = data;
            }

            const { data: usrData } = await supabase.auth.admin.getUserById(id);
            if (usrData?.user) {
              profile = buildProfileFromSupabaseUser(usrData.user, pRow);
              LocalDbStore.profiles.set(id, profile);
            }
          } catch (_) {}
        }
      }

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

      // Persist to Supabase
      const supabase = getSupabase();
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

          const hasProfilesTable = await checkProfilesTableExists();
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
        } catch (sbErr: any) {
          console.warn('[Profile] Supabase profile sync warning:', sbErr.message);
        }
      }

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

      // Persist voice intro to Supabase
      const supabase = getSupabase();
      if (supabase) {
        try {
          await supabase.auth.admin.updateUserById(userId, {
            user_metadata: {
              voiceIntroUrl: existing.voiceIntroUrl,
              voiceIntroDuration: existing.voiceIntroDuration
            }
          });

          const hasProfilesTable = await checkProfilesTableExists();
          if (hasProfilesTable) {
            await supabase.from('profiles').update({
              voice_intro_url: existing.voiceIntroUrl,
              voice_intro_duration: existing.voiceIntroDuration
            }).eq('id', userId);
          }
        } catch (_) {}
      }

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
