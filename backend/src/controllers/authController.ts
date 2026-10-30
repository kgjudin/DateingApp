import { Response } from 'express';
import jwt from 'jsonwebtoken';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import { LocalDbStore, getSupabase } from '../integrations/supabase/supabaseClient';
import { config } from '../config';

export class AuthController {
  public static async register(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const {
        email,
        password,
        username,
        displayName,
        dateOfBirth,
        gender,
        bio,
        location,
        avatarUrl,
        coverUrl,
        interests,
        voiceIntroUrl,
        voiceIntroDuration,
      } = req.body;

      const cleanEmail = (email || '').trim().toLowerCase();
      const cleanUsername = (username || '').trim().toLowerCase();
      const cleanPassword = (password || '').trim();

      if (!cleanEmail || !cleanEmail.includes('@')) {
        res.status(400).json({ success: false, error: { message: 'A valid email address is required.' } });
        return;
      }

      if (!cleanUsername || cleanUsername.length < 3) {
        res.status(400).json({ success: false, error: { message: 'Username must be at least 3 characters.' } });
        return;
      }

      if (!cleanPassword || cleanPassword.length < 6) {
        res.status(400).json({ success: false, error: { message: 'Password must be at least 6 characters long.' } });
        return;
      }

      // Check if username or email is already taken
      for (const p of LocalDbStore.profiles.values()) {
        if (p.username?.toLowerCase() === cleanUsername) {
          res.status(409).json({ success: false, error: { message: 'This username is already taken. Please choose another.' } });
          return;
        }
        if (p.email?.toLowerCase() === cleanEmail) {
          res.status(409).json({ success: false, error: { message: 'An account with this email already exists. Please log in.' } });
          return;
        }
      }

      for (const cred of LocalDbStore.credentials.values()) {
        if (cred.email.toLowerCase() === cleanEmail) {
          res.status(409).json({ success: false, error: { message: 'An account with this email already exists. Please log in.' } });
          return;
        }
      }

      const userId = `user-${Date.now()}`;
      const newProfile = {
        id: userId,
        email: cleanEmail,
        username: cleanUsername,
        displayName: displayName?.trim() || cleanUsername,
        dateOfBirth: dateOfBirth || '2000-01-01',
        gender: gender || 'prefer_not_to_say',
        location: location?.trim() || 'Online',
        bio: bio?.trim() || 'Hey! I am excited to connect on VYBE.',
        avatarUrl: avatarUrl || `https://api.dicebear.com/7.x/avataaars/svg?seed=${cleanUsername}`,
        coverUrl: coverUrl || 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000&auto=format&fit=crop&q=80',
        voiceIntroUrl: voiceIntroUrl || null,
        voiceIntroDuration: voiceIntroDuration || 0,
        languages: ['English'],
        interests: Array.isArray(interests) && interests.length > 0 ? interests : ['Music', 'Travelling'],
        status: 'online',
        isSuspended: false,
        createdAt: new Date().toISOString()
      };

      // Store in DB store
      LocalDbStore.profiles.set(userId, newProfile);
      LocalDbStore.credentials.set(userId, { email: cleanEmail, password: cleanPassword });
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
      LocalDbStore.wallets.set(userId, { balance: 100, earned: 100, spent: 0 }); // 100 free welcome coins

      // Generate JWT session token
      const token = jwt.sign(
        { sub: userId, id: userId, email: cleanEmail, username: cleanUsername, role: 'user' },
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
      const { email, password } = req.body;

      const input = (email || '').trim().toLowerCase();
      const inputPass = (password || '').trim();

      if (!input || !inputPass) {
        res.status(400).json({ success: false, error: { message: 'Email/Username and password are required.' } });
        return;
      }

      // Find user by email or username
      let foundUser: any = null;
      for (const p of LocalDbStore.profiles.values()) {
        if (p.email?.toLowerCase() === input || p.username?.toLowerCase() === input) {
          foundUser = p;
          break;
        }
      }

      if (!foundUser) {
        res.status(401).json({ success: false, error: { message: 'Invalid credentials. User not found.' } });
        return;
      }

      // Check password
      const creds = LocalDbStore.credentials.get(foundUser.id);
      if (creds) {
        if (creds.password !== inputPass) {
          res.status(401).json({ success: false, error: { message: 'Incorrect password. Please try again.' } });
          return;
        }
      }

      // Successful login
      LocalDbStore.presence.set(foundUser.id, {
        userId: foundUser.id,
        status: 'online',
        lastSeenAt: new Date().toISOString()
      });

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

      const profile = LocalDbStore.profiles.get(userId);
      if (!profile) {
        res.status(404).json({ success: false, error: { message: 'User profile not found.' } });
        return;
      }

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
