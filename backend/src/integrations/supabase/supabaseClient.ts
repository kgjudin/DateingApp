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

    // Seed realistic sample users for discovery and voice calling testing
    const seedUsers = [
      {
        id: 'user-elena-101',
        username: 'elena_v',
        displayName: 'Elena Vance',
        dateOfBirth: '1998-04-12',
        age: 26,
        gender: 'female',
        location: 'Berlin, Germany',
        bio: 'Podcaster & indie musician. Let us talk about travel, late-night acoustic guitar, and philosophy.',
        avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500&auto=format&fit=crop&q=80',
        coverUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000&auto=format&fit=crop&q=80',
        voiceIntroUrl: 'https://actions.google.com/sounds/v1/speech/female_voice.ogg',
        voiceIntroDuration: 14,
        languages: ['English', 'German'],
        interests: ['Music', 'Travelling', 'Art', 'Lifestyle'],
        favouriteMusic: ['Indie Rock', 'Lo-Fi', 'Electronic'],
        status: 'online',
        balance: 450,
      },
      {
        id: 'user-marcus-102',
        username: 'marcus_code',
        displayName: 'Marcus Chen',
        dateOfBirth: '1996-09-21',
        age: 28,
        gender: 'male',
        location: 'San Francisco, USA',
        bio: 'AI researcher and late-night gamer. Always up for thought-provoking debates about the future of tech.',
        avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500&auto=format&fit=crop&q=80',
        coverUrl: 'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=1000&auto=format&fit=crop&q=80',
        voiceIntroUrl: 'https://actions.google.com/sounds/v1/speech/male_voice.ogg',
        voiceIntroDuration: 18,
        languages: ['English', 'Mandarin'],
        interests: ['Technology', 'Gaming', 'Books', 'Business'],
        favouriteMusic: ['Synthwave', 'Ambient'],
        status: 'online',
        balance: 1200,
      },
      {
        id: 'user-sophia-103',
        username: 'sophia_beats',
        displayName: 'Sophia Ray',
        dateOfBirth: '2001-01-15',
        age: 24,
        gender: 'female',
        location: 'London, UK',
        bio: 'Coffee enthusiast, vinyl collector, and documentary filmmaker. Tell me your wildest life story!',
        avatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500&auto=format&fit=crop&q=80',
        coverUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=1000&auto=format&fit=crop&q=80',
        voiceIntroUrl: 'https://actions.google.com/sounds/v1/speech/female_voice.ogg',
        voiceIntroDuration: 21,
        languages: ['English', 'French'],
        interests: ['Movies', 'Food', 'Culture', 'Photography'],
        favouriteMusic: ['Jazz', 'Soul'],
        status: 'online',
        balance: 680,
      },
      {
        id: 'user-zane-104',
        username: 'zane_vibes',
        displayName: 'Zane Parker',
        dateOfBirth: '1995-11-04',
        age: 29,
        gender: 'non_binary',
        location: 'Melbourne, Australia',
        bio: 'Sound designer & deep conversation seeker. Let’s talk about consciousness, cinema, and space.',
        avatarUrl: 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=500&auto=format&fit=crop&q=80',
        coverUrl: 'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=1000&auto=format&fit=crop&q=80',
        voiceIntroUrl: 'https://actions.google.com/sounds/v1/speech/male_voice.ogg',
        voiceIntroDuration: 12,
        languages: ['English'],
        interests: ['Technology', 'Nature', 'Music', 'Fitness'],
        favouriteMusic: ['Neo-Classical', 'Ambient'],
        status: 'online',
        balance: 310,
      },
      {
        id: 'user-priya-105',
        username: 'priya_talks',
        displayName: 'Priya Sharma',
        dateOfBirth: '1999-07-08',
        age: 25,
        gender: 'female',
        location: 'Mumbai, India',
        bio: 'Stand-up comedy writer & travel photographer. Voice chats are way more real than endless texting.',
        avatarUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500&auto=format&fit=crop&q=80',
        coverUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=1000&auto=format&fit=crop&q=80',
        voiceIntroUrl: 'https://actions.google.com/sounds/v1/speech/female_voice.ogg',
        voiceIntroDuration: 16,
        languages: ['English', 'Hindi'],
        interests: ['Entertainment', 'Travelling', 'Food', 'Culture'],
        favouriteMusic: ['Bollywood', 'Acoustic Pop'],
        status: 'online',
        balance: 900,
      }
    ];

    seedUsers.forEach(u => {
      this.profiles.set(u.id, u);
      this.presence.set(u.id, {
        userId: u.id,
        status: u.status,
        lastSeenAt: new Date().toISOString()
      });
      this.preferences.set(u.id, {
        userId: u.id,
        preferredGenders: ['everyone'],
        discoveryEnabled: true,
        whoCanCallMe: 'everyone',
        showOnlineStatus: true,
        showAge: true,
        showLocation: true,
      });
      this.wallets.set(u.id, {
        balance: u.balance,
        earned: u.balance,
        spent: 0
      });
    });

    // Seed Sample Groups & Live Clubhouse Rooms
    const group1 = {
      id: 'grp-night-owls-1',
      name: 'Midnight Philosophers',
      description: 'Deep late-night thoughts, space talks, mind-benders, and chill vibes after 1 AM.',
      category: 'General Conversations',
      avatarUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=500&auto=format&fit=crop&q=80',
      coverUrl: 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=1000&auto=format&fit=crop&q=80',
      ownerId: 'user-elena-101',
      totalMembers: 142,
      isPrivate: false,
      rules: 'Be respectful, let people finish speaking, keep it positive and reflective.'
    };
    this.groups.set(group1.id, group1);

    const group2 = {
      id: 'grp-tech-creators-2',
      name: 'Future & Tech Minds',
      description: 'Generative AI, indie building, startup lessons, and tech trends.',
      category: 'Technology',
      avatarUrl: 'https://images.unsplash.com/photo-1531482615713-2afd69097998?w=500&auto=format&fit=crop&q=80',
      coverUrl: 'https://images.unsplash.com/photo-1519389950473-47ba0277781c?w=1000&auto=format&fit=crop&q=80',
      ownerId: 'user-marcus-102',
      totalMembers: 289,
      isPrivate: false,
      rules: 'Constructive debates only. No spamming links.'
    };
    this.groups.set(group2.id, group2);

    // Live Voice Room 1
    const room1 = {
      id: 'room-live-101',
      groupId: group1.id,
      groupName: group1.name,
      hostId: 'user-elena-101',
      hostName: 'Elena Vance',
      hostAvatar: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500&auto=format&fit=crop&q=80',
      title: 'Late Night Chill & Lo-Fi Vinyl Talks ☕',
      topic: 'Music & Memories',
      channelName: 'vybe_room_night_owls',
      isLive: true,
      listenersCount: 18,
      speakersCount: 3,
      speakers: [
        { userId: 'user-elena-101', name: 'Elena Vance', role: 'host', isMuted: false, avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500&auto=format&fit=crop&q=80' },
        { userId: 'user-zane-104', name: 'Zane Parker', role: 'speaker', isMuted: false, avatarUrl: 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=500&auto=format&fit=crop&q=80' },
        { userId: 'user-sophia-103', name: 'Sophia Ray', role: 'speaker', isMuted: true, avatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500&auto=format&fit=crop&q=80' }
      ]
    };
    this.rooms.set(room1.id, room1);

    // Live Voice Room 2
    const room2 = {
      id: 'room-live-102',
      groupId: group2.id,
      groupName: group2.name,
      hostId: 'user-marcus-102',
      hostName: 'Marcus Chen',
      hostAvatar: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500&auto=format&fit=crop&q=80',
      title: 'Will AI Replace Social Media or Reinvent Voice?',
      topic: 'AI & Social Futures',
      channelName: 'vybe_room_tech_minds',
      isLive: true,
      listenersCount: 42,
      speakersCount: 2,
      speakers: [
        { userId: 'user-marcus-102', name: 'Marcus Chen', role: 'host', isMuted: false, avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500&auto=format&fit=crop&q=80' },
        { userId: 'user-priya-105', name: 'Priya Sharma', role: 'speaker', isMuted: false, avatarUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500&auto=format&fit=crop&q=80' }
      ]
    };
    this.rooms.set(room2.id, room2);
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
