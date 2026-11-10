import { Response } from 'express';
import jwt from 'jsonwebtoken';
import { AuthenticatedRequest } from '../middleware/authMiddleware';
import {
  LocalDbStore,
  getSupabase,
  checkProfilesTableExists,
  buildProfileFromSupabaseUser
} from '../integrations/supabase/supabaseClient';
import { config } from '../config';
import { markUserOffline, isUserOnline } from '../sockets/socketHandler';
import { FollowController } from './followController';
import { WalletService } from './giftController';

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

      const supabase = getSupabase();

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

      if (supabase) {
        try {
          const { data: userList } = await supabase.auth.admin.listUsers();
          if (userList?.users) {
            const exists = userList.users.some(
              u =>
                u.email?.toLowerCase() === cleanEmail ||
                u.user_metadata?.username?.toLowerCase() === cleanUsername
            );
            if (exists) {
              res.status(409).json({
                success: false,
                error: { message: 'An account with this email or username already exists. Please log in.' }
              });
              return;
            }
          }
        } catch (_) {}
      }

      let userId = `user-${Date.now()}`;
      let sessionToken: string | null = null;
      let userProfile: any = null;

      const metadata = {
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
      };

      if (supabase) {
        const { data: createData, error: createError } = await supabase.auth.admin.createUser({
          email: cleanEmail,
          password: cleanPassword,
          email_confirm: true,
          user_metadata: metadata,
        });

        if (createError) {
          res.status(400).json({ success: false, error: { message: createError.message } });
          return;
        }

        userId = createData.user.id;

        // Try getting session token via Supabase Auth
        try {
          const { data: signData } = await supabase.auth.signInWithPassword({
            email: cleanEmail,
            password: cleanPassword,
          });
          if (signData?.session?.access_token) {
            sessionToken = signData.session.access_token;
          }
        } catch (_) {}

        // If public.profiles exists, insert/upsert into it
        const hasProfilesTable = await checkProfilesTableExists();
        if (hasProfilesTable) {
          try {
            await supabase.from('profiles').upsert({
              id: userId,
              username: cleanUsername,
              display_name: metadata.displayName,
              date_of_birth: metadata.dateOfBirth,
              gender: metadata.gender,
              location: metadata.location,
              bio: metadata.bio,
              avatar_url: metadata.avatarUrl,
              cover_url: metadata.coverUrl,
              voice_intro_url: metadata.voiceIntroUrl,
              voice_intro_duration: metadata.voiceIntroDuration,
              languages: metadata.languages,
              hobbies: metadata.interests,
            });
          } catch (_) {}
        }

        userProfile = buildProfileFromSupabaseUser(createData.user);
      } else {
        userProfile = {
          id: userId,
          email: cleanEmail,
          username: cleanUsername,
          displayName: metadata.displayName,
          dateOfBirth: metadata.dateOfBirth,
          gender: metadata.gender,
          location: metadata.location,
          bio: metadata.bio,
          avatarUrl: metadata.avatarUrl,
          coverUrl: metadata.coverUrl,
          voiceIntroUrl: metadata.voiceIntroUrl,
          voiceIntroDuration: metadata.voiceIntroDuration,
          languages: metadata.languages,
          interests: metadata.interests,
          status: 'offline',
          isSuspended: false,
          createdAt: new Date().toISOString()
        };
      }

      // Store in memory cache
      LocalDbStore.profiles.set(userId, userProfile);
      LocalDbStore.credentials.set(userId, { email: cleanEmail, password: cleanPassword });
      LocalDbStore.presence.set(userId, { userId, status: 'offline', lastSeenAt: new Date().toISOString() });
      LocalDbStore.preferences.set(userId, {
        userId,
        preferredGenders: ['everyone'],
        discoveryEnabled: true,
        whoCanCallMe: 'everyone',
        showOnlineStatus: true,
        showAge: true,
        showLocation: true
      });
      const wallet = await WalletService.getWallet(userId);

      // Generate JWT if not already provided by Supabase
      if (!sessionToken) {
        sessionToken = jwt.sign(
          { sub: userId, id: userId, email: cleanEmail, username: cleanUsername, displayName: userProfile.displayName, role: 'user' },
          config.supabase.jwtSecret,
          { expiresIn: '30d' }
        );
      }

      res.status(201).json({
        success: true,
        data: {
          token: sessionToken,
          user: userProfile,
          wallet
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async login(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { email, password } = req.body;

      const input = (email || '').trim();
      const inputPass = (password || '').trim();

      if (!input || !inputPass) {
        res.status(400).json({ success: false, error: { message: 'Email/Username and password are required.' } });
        return;
      }

      const supabase = getSupabase();
      let emailToUse = input.toLowerCase();

      if (supabase) {
        // If input does not contain '@', user signed in with username - resolve email
        if (!input.includes('@')) {
          try {
            const hasProfilesTable = await checkProfilesTableExists();
            if (hasProfilesTable) {
              const { data: pRows } = await supabase
                .from('profiles')
                .select('id, email, username')
                .ilike('username', input)
                .limit(1);

              if (pRows && pRows.length > 0 && pRows[0].email) {
                emailToUse = pRows[0].email.toLowerCase();
              }
            }

            // Also search auth users metadata
            if (!emailToUse.includes('@')) {
              const { data: usersData } = await supabase.auth.admin.listUsers();
              if (usersData?.users) {
                const found = usersData.users.find(
                  u =>
                    u.user_metadata?.username?.toLowerCase() === input.toLowerCase() ||
                    u.email?.toLowerCase() === input.toLowerCase()
                );
                if (found && found.email) {
                  emailToUse = found.email.toLowerCase();
                }
              }
            }
          } catch (_) {}

          // Fallback to local profiles
          if (!emailToUse.includes('@')) {
            for (const p of LocalDbStore.profiles.values()) {
              if (p.username?.toLowerCase() === input.toLowerCase() && p.email) {
                emailToUse = p.email.toLowerCase();
                break;
              }
            }
          }
        }

        // Authenticate with Supabase Auth
        try {
          const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
            email: emailToUse,
            password: inputPass,
          });

          if (!signInError && signInData?.user) {
            const sbUser = signInData.user;
            let pRow: any = null;

            const hasProfilesTable = await checkProfilesTableExists();
            if (hasProfilesTable) {
              try {
                const { data } = await supabase.from('profiles').select('*').eq('id', sbUser.id).single();
                if (data) pRow = data;
              } catch (_) {}
            }

            const finalProfile = buildProfileFromSupabaseUser(sbUser, pRow);

            // Populate local cache
            LocalDbStore.profiles.set(sbUser.id, finalProfile);
            LocalDbStore.credentials.set(sbUser.id, { email: emailToUse, password: inputPass });
            LocalDbStore.presence.set(sbUser.id, {
              userId: sbUser.id,
              status: isUserOnline(sbUser.id) ? 'online' : 'offline',
              lastSeenAt: new Date().toISOString()
            });

            if (!LocalDbStore.preferences.has(sbUser.id)) {
              LocalDbStore.preferences.set(sbUser.id, {
                userId: sbUser.id,
                preferredGenders: ['everyone'],
                discoveryEnabled: true,
                whoCanCallMe: 'everyone',
                showOnlineStatus: true,
                showAge: true,
                showLocation: true
              });
            }

            const wallet = await WalletService.getWallet(sbUser.id);

            const token = signInData.session?.access_token || jwt.sign(
              { sub: sbUser.id, id: sbUser.id, email: sbUser.email, username: finalProfile.username, displayName: finalProfile.displayName, role: 'user' },
              config.supabase.jwtSecret,
              { expiresIn: '30d' }
            );

            res.json({
              success: true,
              data: {
                token,
                user: finalProfile,
                wallet
              }
            });
            return;
          }
        } catch (sbErr: any) {
          console.warn('[Auth] Supabase auth attempt notice:', sbErr.message);
        }
      }

      // Check LocalDbStore fallback
      let foundUser: any = null;
      for (const p of LocalDbStore.profiles.values()) {
        if (p.email?.toLowerCase() === input.toLowerCase() || p.username?.toLowerCase() === input.toLowerCase()) {
          foundUser = p;
          break;
        }
      }

      if (foundUser) {
        const creds = LocalDbStore.credentials.get(foundUser.id);
        if (creds && creds.password !== inputPass) {
          res.status(401).json({ success: false, error: { message: 'Incorrect password. Please try again.' } });
          return;
        }

        LocalDbStore.presence.set(foundUser.id, {
          userId: foundUser.id,
          status: isUserOnline(foundUser.id) ? 'online' : 'offline',
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
        return;
      }

      res.status(401).json({
        success: false,
        error: { message: 'Invalid credentials. Incorrect email, username, or password.' }
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

      let profile = LocalDbStore.profiles.get(userId);

      // If not in local cache, load from Supabase
      if (!profile) {
        const supabase = getSupabase();
        if (supabase) {
          try {
            const hasProfilesTable = await checkProfilesTableExists();
            let pRow: any = null;
            if (hasProfilesTable) {
              const { data } = await supabase.from('profiles').select('*').eq('id', userId).single();
              if (data) pRow = data;
            }

            const { data: usrData } = await supabase.auth.admin.getUserById(userId);
            if (usrData?.user) {
              profile = buildProfileFromSupabaseUser(usrData.user, pRow);
              LocalDbStore.profiles.set(userId, profile);
              if (!LocalDbStore.presence.has(userId)) {
                LocalDbStore.presence.set(userId, { userId, status: isUserOnline(userId) ? 'online' : 'offline', lastSeenAt: new Date().toISOString() });
              }
              if (!LocalDbStore.wallets.has(userId)) {
                LocalDbStore.wallets.set(userId, { balance: 100, earned: 100, spent: 0 });
              }
              if (!LocalDbStore.preferences.has(userId)) {
                LocalDbStore.preferences.set(userId, {
                  userId,
                  preferredGenders: ['everyone'],
                  discoveryEnabled: true,
                  whoCanCallMe: 'everyone',
                  showOnlineStatus: true,
                  showAge: true,
                  showLocation: true
                });
              }
            }
          } catch (_) {}
        }
      }

      if (!profile) {
        res.status(404).json({ success: false, error: { message: 'User profile not found.' } });
        return;
      }

      const preferences = LocalDbStore.preferences.get(userId) || {
        userId,
        preferredGenders: ['everyone'],
        discoveryEnabled: true,
        whoCanCallMe: 'everyone',
        showOnlineStatus: true,
        showAge: true,
        showLocation: true
      };
      const wallet = await WalletService.getWallet(userId);

      const followersCount = FollowController.getFollowersCount(userId);
      const followingCount = FollowController.getFollowingCount(userId);

      res.json({
        success: true,
        data: {
          user: {
            ...profile,
            followersCount,
            followingCount,
          },
          preferences,
          wallet
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async logout(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (userId) {
        markUserOffline(userId);
      }
      res.json({ success: true, message: 'Logged out successfully.' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
}
