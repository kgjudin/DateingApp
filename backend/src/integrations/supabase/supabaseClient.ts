import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { config } from '../../config';
import fs from 'fs';
import path from 'path';

// In-memory data store for fast local operations, signaling and graceful fallback
export class LocalDbStore {
  public static profiles: Map<string, any> = new Map();
  public static preferences: Map<string, any> = new Map();
  public static presence: Map<string, any> = new Map();
  public static favourites: Set<string> = new Set(); // "userId:favUserId"
  public static follows: Set<string> = new Set(); // "followerId:followingId"
  public static calls: Map<string, any> = new Map();
  public static callHistory: any[] = [];
  public static groups: Map<string, any> = new Map();
  public static groupMembers: any[] = [];
  public static rooms: Map<string, any> = new Map();
  public static roomParticipants: any[] = [];
  public static speakerRequests: any[] = [];
  public static gifts: any[] = [];
  public static wallets: Map<string, { balance: number; earned: number; spent: number }> = new Map();
  public static walletTransactions: any[] = [];
  public static giftTransactions: any[] = [];
  public static notifications: any[] = [];
  public static userBlocks: Set<string> = new Set(); // "blockerId:blockedId"
  public static userReports: any[] = [];
  public static credentials: Map<string, { email: string; password: string }> = new Map();

  private static getStoreFilePath(): string {
    const dataDir = path.join(process.cwd(), 'data');
    if (!fs.existsSync(dataDir)) {
      try {
        fs.mkdirSync(dataDir, { recursive: true });
      } catch (_) {}
    }
    return path.join(dataDir, 'local_db.json');
  }

  public static saveToDisk(): void {
    try {
      const filePath = this.getStoreFilePath();
      const payload = {
        follows: Array.from(this.follows),
        favourites: Array.from(this.favourites),
        notifications: this.notifications,
        wallets: Array.from(this.wallets.entries()),
        userBlocks: Array.from(this.userBlocks)
      };
      fs.writeFileSync(filePath, JSON.stringify(payload, null, 2), 'utf-8');
    } catch (e: any) {
      console.warn('[LocalDbStore] Error saving to disk:', e.message);
    }
  }

  public static loadFromDisk(): void {
    try {
      const filePath = this.getStoreFilePath();
      if (!fs.existsSync(filePath)) return;
      const raw = fs.readFileSync(filePath, 'utf-8');
      const data = JSON.parse(raw);
      if (Array.isArray(data.follows)) {
        for (const item of data.follows) {
          this.follows.add(item);
        }
      }
      if (Array.isArray(data.favourites)) {
        for (const item of data.favourites) {
          this.favourites.add(item);
        }
      }
      if (Array.isArray(data.notifications)) {
        this.notifications = data.notifications;
      }
      if (Array.isArray(data.wallets)) {
        for (const [k, v] of data.wallets) {
          this.wallets.set(k, v);
        }
      }
      if (Array.isArray(data.userBlocks)) {
        for (const item of data.userBlocks) {
          this.userBlocks.add(item);
        }
      }
      console.log(`[LocalDbStore] Restored ${this.follows.size} follow(s) and ${this.notifications.length} notification(s) from disk.`);
    } catch (e: any) {
      console.warn('[LocalDbStore] Error loading from disk:', e.message);
    }
  }

  public static seedDefaults() {
    if (this.gifts.length > 0) return;

    // Default Gifts
    this.gifts = [
      { id: 'gift-1', name: 'Rose', iconName: 'rose', emoji: '🌹', coinPrice: 10, description: 'A sweet red rose' },
      { id: 'gift-2', name: 'Coffee', iconName: 'coffee', emoji: '☕', coinPrice: 20, description: 'Warm coffee for a cozy voice chat' },
      { id: 'gift-3', name: 'Heart', iconName: 'favorite', emoji: '💖', coinPrice: 50, description: 'Send love and appreciation' },
      { id: 'gift-4', name: 'Star', iconName: 'star', emoji: '⭐', coinPrice: 100, description: 'You are a shining star in this room!' },
      { id: 'gift-5', name: 'Fire', iconName: 'whatshot', emoji: '🔥', coinPrice: 250, description: 'This conversation is on fire!' },
      { id: 'gift-6', name: 'Trophy', iconName: 'emoji_events', emoji: '🏆', coinPrice: 500, description: 'Champion speaker badge' },
      { id: 'gift-7', name: 'Diamond', iconName: 'diamond', emoji: '💎', coinPrice: 1000, description: 'A sparkling diamond of pure luxury' },
      { id: 'gift-8', name: 'Crown', iconName: 'workspace_premium', emoji: '👑', coinPrice: 2500, description: 'Royalty status for outstanding hosts' },
      { id: 'gift-9', name: 'Rocket', iconName: 'rocket_launch', emoji: '🚀', coinPrice: 5000, description: 'To the moon! Ultimate hype gift' },
      { id: 'gift-10', name: 'Luxury Car', iconName: 'directions_car', emoji: '🏎️', coinPrice: 10000, description: 'Grand prestige gift of the platform' },
    ];
  }
}

// Seed defaults and load persisted data on load
LocalDbStore.seedDefaults();
LocalDbStore.loadFromDisk();

let supabaseInstance: SupabaseClient | null = null;
let _hasCheckedProfilesTable = false;
let _profilesTableExists = false;

export function getSupabase(): SupabaseClient | null {
  if (
    config.supabase.url &&
    !config.supabase.url.includes('dummy') &&
    config.supabase.serviceRoleKey &&
    !config.supabase.serviceRoleKey.includes('dummy')
  ) {
    if (!supabaseInstance) {
      supabaseInstance = createClient(config.supabase.url, config.supabase.serviceRoleKey, {
        auth: { persistSession: false },
      });
    }
    return supabaseInstance;
  }
  return null;
}

/**
 * Checks whether the public.profiles table exists in Supabase.
 */
export async function checkProfilesTableExists(): Promise<boolean> {
  if (_hasCheckedProfilesTable) return _profilesTableExists;
  const supabase = getSupabase();
  if (!supabase) return false;

  try {
    const { error } = await supabase.from('profiles').select('id').limit(1);
    if (!error) {
      _profilesTableExists = true;
    } else {
      _profilesTableExists = false;
    }
  } catch {
    _profilesTableExists = false;
  }
  _hasCheckedProfilesTable = true;
  return _profilesTableExists;
}

/**
 * Helper to build a normalized User Profile from Supabase User & Metadata.
 */
export function buildProfileFromSupabaseUser(sbUser: any, pRow?: any): any {
  const meta = sbUser?.user_metadata || {};
  const email = sbUser?.email || meta.email || '';
  const username = pRow?.username || meta.username || (email ? email.split('@')[0] : 'vybe_user');
  const displayName = pRow?.display_name || meta.displayName || meta.display_name || username || 'Vyber';

  return {
    id: sbUser.id,
    email: email,
    username: username,
    displayName: displayName,
    dateOfBirth: pRow?.date_of_birth || meta.dateOfBirth || '2000-01-01',
    gender: pRow?.gender || meta.gender || 'prefer_not_to_say',
    location: pRow?.location || meta.location || 'Online',
    bio: pRow?.bio || meta.bio || 'Voice enthusiast on VYBE',
    avatarUrl: pRow?.avatar_url || meta.avatarUrl || `https://api.dicebear.com/7.x/avataaars/svg?seed=${username}`,
    coverUrl: pRow?.cover_url || meta.coverUrl || 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000&auto=format&fit=crop&q=80',
    voiceIntroUrl: pRow?.voice_intro_url || meta.voiceIntroUrl || null,
    voiceIntroDuration: pRow?.voice_intro_duration || meta.voiceIntroDuration || 0,
    languages: pRow?.languages || meta.languages || ['English'],
    interests: pRow?.hobbies || meta.interests || ['Music', 'Travelling'],
    status: 'offline',
    isSuspended: pRow?.is_suspended || false,
    createdAt: pRow?.created_at || sbUser.created_at || new Date().toISOString()
  };
}

/**
 * Preloads users from Supabase Auth & public.profiles into LocalDbStore on bootstrap.
 */
export async function syncUsersFromSupabase(): Promise<void> {
  const supabase = getSupabase();
  if (!supabase) return;

  try {
    const tableExists = await checkProfilesTableExists();
    const { data: list, error } = await supabase.auth.admin.listUsers();
    if (error || !list?.users) return;

    let profilesMap = new Map<string, any>();
    if (tableExists) {
      try {
        const { data: profiles } = await supabase.from('profiles').select('*');
        if (profiles) {
          for (const p of profiles) {
            profilesMap.set(p.id, p);
          }
        }
      } catch (_) {}
    }

    for (const u of list.users) {
      const pRow = profilesMap.get(u.id);
      const profile = buildProfileFromSupabaseUser(u, pRow);

      LocalDbStore.profiles.set(u.id, profile);

      // Users default strictly to offline on sync/startup until an active socket connects
      LocalDbStore.presence.set(u.id, {
        userId: u.id,
        status: 'offline',
        lastSeenAt: u.last_sign_in_at || u.created_at || new Date().toISOString()
      });

      if (!LocalDbStore.preferences.has(u.id)) {
        LocalDbStore.preferences.set(u.id, {
          userId: u.id,
          preferredGenders: ['everyone'],
          discoveryEnabled: true,
          whoCanCallMe: 'everyone',
          showOnlineStatus: true,
          showAge: true,
          showLocation: true
        });
      }

      if (!LocalDbStore.wallets.has(u.id)) {
        LocalDbStore.wallets.set(u.id, { balance: 100, earned: 100, spent: 0 });
      }
    }

    // Preload follows if table exists
    try {
      const { data: followRows } = await supabase.from('follows').select('follower_id, following_id');
      if (followRows) {
        for (const row of followRows) {
          LocalDbStore.follows.add(`${row.follower_id}:${row.following_id}`);
        }
      }
    } catch (_) {}
    console.log(`[Supabase] Synced ${list.users.length} active user(s) into memory cache.`);
  } catch (err: any) {
    console.warn('[Supabase] Warning syncing users:', err.message);
  }
}
