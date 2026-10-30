import { Response } from 'express';
import jwt from 'jsonwebtoken';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore, getSupabase } from '../integrations/supabase/supabaseClient';
import { config } from '../config';

export class AuthController {
  public static async register(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { email, password, username, displayName, dateOfBirth, gender } = req.body;

      if (!email || !username) {
        res.status(400).json({ success: false, error: { message: 'Email and username are required.' } });
        return;
      }

      // Check if username taken
      for (const p of LocalDbStore.profiles.values()) {
        if (p.username?.toLowerCase() === username.toLowerCase()) {
          res.status(409).json({ success: false, error: { message: 'Username is already taken.' } });
          return;
        }
      }

      const userId = `user-${Date.now()}`;
      const newProfile = {
        id: userId,
        email,
        username,
        displayName: displayName || username,
        dateOfBirth: dateOfBirth || '2000-01-01',
        gender: gender || 'prefer_not_to_say',
        location: 'Online',
        bio: 'Hey! I am excited to connect on VYBE.',
        avatarUrl: `https://api.dicebear.com/7.x/avataaars/svg?seed=${username}`,
        coverUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000&auto=format&fit=crop&q=80',
        voiceIntroUrl: null,
        voiceIntroDuration: 0,
        languages: ['English'],
        interests: ['Music', 'Travelling', 'Lifestyle'],
        status: 'online',
        isSuspended: false,
        createdAt: new Date().toISOString()
      };

      LocalDbStore.profiles.set(userId, newProfile);
      LocalDbStore.presence.set(userId, { userId, status: 'online', lastSeenAt: new Date().toISOString() });
      LocalDbStore.preferences.set(userId, {
        userId,
        preferredGenders: ['everyone'],
        discoveryEnabled: true,
        whoCanCallMe: 'everyone',
        showOnlineStatus: true,
        showAge: true,
        showLocation: true
      });
      LocalDbStore.wallets.set(userId, { balance: 100, earned: 100, spent: 0 }); // 100 welcome coins

      // Generate session token
      const token = jwt.sign(
        { sub: userId, id: userId, email, username, role: 'user' },
        config.supabase.jwtSecret,
        { expiresIn: '30d' }
      );

      res.status(201).json({
        success: true,
        data: {
          token,
          user: newProfile,
          wallet: { balance: 100 }
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async login(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { email, password, phone, loginType } = req.body;

      // Find user by email or phone or match seed users
      let foundUser: any = null;
      for (const p of LocalDbStore.profiles.values()) {
        if (email && (p.email === email || p.username === email)) {
          foundUser = p;
          break;
        }
      }

      // Fallback: Default to demo user Elena if credentials match demo
      if (!foundUser) {
        foundUser = LocalDbStore.profiles.get('user-elena-101');
      }

      const token = jwt.sign(
        { sub: foundUser.id, id: foundUser.id, email: foundUser.email, username: foundUser.username, role: 'user' },
        config.supabase.jwtSecret,
        { expiresIn: '30d' }
      );

      res.json({
        success: true,
        data: {
          token,
          user: foundUser,
          wallet: LocalDbStore.wallets.get(foundUser.id) || { balance: 100, earned: 100, spent: 0 }
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async getCurrentUser(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
        return;
      }

      const profile = LocalDbStore.profiles.get(userId) || LocalDbStore.profiles.get('user-elena-101');
      const preferences = LocalDbStore.preferences.get(userId);
      const wallet = LocalDbStore.wallets.get(userId) || { balance: 100, earned: 100, spent: 0 };

      res.json({
        success: true,
        data: {
          user: profile,
          preferences,
          wallet
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
