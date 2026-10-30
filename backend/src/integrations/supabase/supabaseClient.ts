import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { config } from '../../config';

// In-memory data store for rich local development and seamless fallback
export class LocalDbStore {
  public static profiles: Map<string, any> = new Map();
  public static preferences: Map<string, any> = new Map();
  public static presence: Map<string, any> = new Map();
  public static favourites: Set<string> = new Set(); // "userId:favUserId"
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

  public static seedDefaults() {
    if (this.gifts.length > 0) return;

    // Default Gifts
    this.gifts = [
      { id: 'gift-1', name: 'Rose', iconName: 'rose', coinPrice: 10, description: 'A sweet red rose' },
      { id: 'gift-2', name: 'Coffee', iconName: 'coffee', coinPrice: 20, description: 'Warm coffee for a cozy voice chat' },
      { id: 'gift-3', name: 'Heart', iconName: 'favorite', coinPrice: 50, description: 'Send love and appreciation' },
      { id: 'gift-4', name: 'Star', iconName: 'star', coinPrice: 100, description: 'You are a shining star in this room!' },
      { id: 'gift-5', name: 'Fire', iconName: 'whatshot', coinPrice: 250, description: 'This conversation is on fire!' },
      { id: 'gift-6', name: 'Trophy', iconName: 'emoji_events', coinPrice: 500, description: 'Champion speaker badge' },
      { id: 'gift-7', name: 'Diamond', iconName: 'diamond', coinPrice: 1000, description: 'A sparkling diamond of pure luxury' },
      { id: 'gift-8', name: 'Crown', iconName: 'workspace_premium', coinPrice: 2500, description: 'Royalty status for outstanding hosts' },
      { id: 'gift-9', name: 'Rocket', iconName: 'rocket_launch', coinPrice: 5000, description: 'To the moon! Ultimate hype gift' },
      { id: 'gift-10', name: 'Luxury Car', iconName: 'directions_car', coinPrice: 10000, description: 'Grand prestige gift of the platform' },
    ];

    // Only virtual gift store items are seeded. Zero dummy users.
  }
}

// Seed on module load
LocalDbStore.seedDefaults();

let supabaseInstance: SupabaseClient | null = null;

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
