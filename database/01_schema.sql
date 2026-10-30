-- ==============================================================================
-- VYBE DATABASE ARCHITECTURE - SUPABASE POSTGRESQL SCHEMA
-- Migration: 01_schema.sql
-- ==============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Clean existing schema if necessary (controlled)
-- DO NOT drop auth.users;

-- ------------------------------------------------------------------------------
-- 1. ENUMS & CUSTOM TYPES
-- ------------------------------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE user_gender AS ENUM ('male', 'female', 'non_binary', 'prefer_not_to_say', 'other');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE discovery_gender_pref AS ENUM ('men', 'women', 'non_binary', 'everyone');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE call_status AS ENUM ('initiating', 'ringing', 'accepted', 'rejected', 'missed', 'busy', 'ended', 'failed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE room_role AS ENUM ('host', 'co_host', 'speaker', 'listener');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE speaker_request_status AS ENUM ('pending', 'approved', 'rejected', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE group_role AS ENUM ('owner', 'admin', 'moderator', 'member');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE transaction_type AS ENUM ('coin_purchase', 'gift_sent', 'gift_received', 'reward', 'refund', 'admin_adjustment');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE report_status AS ENUM ('pending', 'investigating', 'resolved', 'dismissed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE presence_status AS ENUM ('online', 'offline', 'in_call', 'in_room', 'busy');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ------------------------------------------------------------------------------
-- 2. TABLE: profiles
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender user_gender NOT NULL DEFAULT 'prefer_not_to_say',
    location VARCHAR(120),
    bio VARCHAR(500),
    avatar_url TEXT,
    cover_url TEXT,
    voice_intro_url TEXT,
    voice_intro_duration INT DEFAULT 0, -- in seconds
    languages TEXT[] DEFAULT ARRAY['English'],
    hobbies TEXT[] DEFAULT ARRAY[]::TEXT[],
    favourite_music TEXT[] DEFAULT ARRAY[]::TEXT[],
    personality_traits TEXT[] DEFAULT ARRAY[]::TEXT[],
    conversation_starters TEXT[] DEFAULT ARRAY[]::TEXT[],
    favourite_topics TEXT[] DEFAULT ARRAY[]::TEXT[],
    is_verified BOOLEAN DEFAULT FALSE,
    is_suspended BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 3. TABLE: profile_photos
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profile_photos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    photo_url TEXT NOT NULL,
    is_primary BOOLEAN DEFAULT FALSE,
    display_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 4. TABLE: profile_interests
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) UNIQUE NOT NULL,
    category VARCHAR(50) NOT NULL,
    icon_name VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.profile_interests (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    interest_id UUID NOT NULL REFERENCES public.interests(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, interest_id)
);

-- ------------------------------------------------------------------------------
-- 5. TABLE: user_preferences (Privacy, Discovery & Notifications)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_preferences (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    preferred_genders TEXT[] DEFAULT ARRAY['everyone'], -- 'men', 'women', 'non_binary', 'everyone'
    preferred_min_age INT DEFAULT 18,
    preferred_max_age INT DEFAULT 99,
    discovery_enabled BOOLEAN DEFAULT TRUE,
    who_can_call_me VARCHAR(30) DEFAULT 'everyone', -- 'everyone', 'favourites', 'nobody'
    show_online_status BOOLEAN DEFAULT TRUE,
    show_age BOOLEAN DEFAULT TRUE,
    show_location BOOLEAN DEFAULT TRUE,
    notify_favourite_online BOOLEAN DEFAULT TRUE,
    notify_incoming_calls BOOLEAN DEFAULT TRUE,
    notify_messages BOOLEAN DEFAULT TRUE,
    notify_gift_received BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 6. TABLE: user_presence
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_presence (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    status presence_status DEFAULT 'offline',
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    active_call_id UUID,
    active_room_id UUID,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 7. TABLE: favourites
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.favourites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    favourite_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, favourite_user_id),
    CONSTRAINT chk_no_self_favourite CHECK (user_id != favourite_user_id)
);

-- ------------------------------------------------------------------------------
-- 8. TABLE: calls & call_participants & call_history
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.calls (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    caller_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    channel_name VARCHAR(100) UNIQUE NOT NULL,
    status call_status DEFAULT 'initiating',
    agora_token TEXT,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    duration INT DEFAULT 0, -- in seconds
    end_reason VARCHAR(50), -- 'normal', 'declined', 'missed', 'error', 'timeout'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.call_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    call_id UUID NOT NULL REFERENCES public.calls(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role VARCHAR(30) DEFAULT 'peer',
    joined_at TIMESTAMPTZ,
    left_at TIMESTAMPTZ,
    is_muted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.call_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    call_id UUID REFERENCES public.calls(id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    other_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    direction VARCHAR(10) NOT NULL, -- 'incoming', 'outgoing'
    status call_status NOT NULL,
    duration INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 9. TABLE: groups & group_members
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    category VARCHAR(50) NOT NULL DEFAULT 'General Conversations',
    avatar_url TEXT,
    cover_url TEXT,
    owner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    is_private BOOLEAN DEFAULT FALSE,
    rules TEXT,
    total_members INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.group_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role group_role DEFAULT 'member',
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(group_id, user_id)
);

-- ------------------------------------------------------------------------------
-- 10. TABLE: group_rooms, participants, speaker requests
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.group_rooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    host_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title VARCHAR(150) NOT NULL,
    topic VARCHAR(100),
    channel_name VARCHAR(100) UNIQUE NOT NULL,
    is_live BOOLEAN DEFAULT TRUE,
    listeners_count INT DEFAULT 0,
    speakers_count INT DEFAULT 1,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.group_room_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES public.group_rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role room_role DEFAULT 'listener',
    is_speaking BOOLEAN DEFAULT FALSE,
    is_muted BOOLEAN DEFAULT TRUE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    left_at TIMESTAMPTZ,
    UNIQUE(room_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.group_speaker_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES public.group_rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status speaker_request_status DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 11. TABLE: messages & message_attachments
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    is_group BOOLEAN DEFAULT FALSE,
    group_id UUID REFERENCES public.groups(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.conversation_participants (
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    last_read_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY(conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    content TEXT,
    message_type VARCHAR(30) DEFAULT 'text', -- 'text', 'voice_note', 'image', 'gift', 'profile_card', 'group_invite'
    metadata JSONB DEFAULT '{}'::jsonb,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.message_attachments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    file_url TEXT NOT NULL,
    file_type VARCHAR(50) NOT NULL,
    file_size_bytes BIGINT,
    duration_seconds INT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 12. TABLE: gifts, wallets, wallet_transactions, gift_transactions
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gifts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) UNIQUE NOT NULL,
    icon_name VARCHAR(50) NOT NULL,
    animation_url TEXT,
    coin_price INT NOT NULL CHECK (coin_price > 0),
    description VARCHAR(200),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.wallets (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    coin_balance BIGINT DEFAULT 100 CHECK (coin_balance >= 0), -- 100 welcome bonus coins
    lifetime_earned BIGINT DEFAULT 0,
    lifetime_spent BIGINT DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    amount INT NOT NULL, -- positive for credit, negative for debit
    balance_after BIGINT NOT NULL,
    type transaction_type NOT NULL,
    description TEXT,
    reference_id TEXT, -- e.g., gift_transaction_id or IAP receipt ID
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.gift_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    gift_id UUID NOT NULL REFERENCES public.gifts(id) ON DELETE CASCADE,
    room_id UUID REFERENCES public.group_rooms(id) ON DELETE SET NULL,
    coin_amount INT NOT NULL,
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 13. TABLE: notifications, user_devices
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    title VARCHAR(150) NOT NULL,
    body TEXT NOT NULL,
    payload JSONB DEFAULT '{}'::jsonb,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL,
    platform VARCHAR(20) NOT NULL, -- 'android', 'ios'
    last_active TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, fcm_token)
);

-- ------------------------------------------------------------------------------
-- 14. TABLE: user_blocks, user_reports
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_blocks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blocker_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(blocker_id, blocked_id),
    CONSTRAINT chk_no_self_block CHECK (blocker_id != blocked_id)
);

CREATE TABLE IF NOT EXISTS public.user_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    reported_room_id UUID REFERENCES public.group_rooms(id) ON DELETE SET NULL,
    reason VARCHAR(100) NOT NULL,
    description TEXT,
    status report_status DEFAULT 'pending',
    admin_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- ------------------------------------------------------------------------------
-- 15. TABLE: admin_roles & admin_permissions
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_roles (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL DEFAULT 'moderator', -- 'superadmin', 'admin', 'moderator'
    granted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.admin_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role VARCHAR(50) NOT NULL,
    permission VARCHAR(100) NOT NULL,
    UNIQUE(role, permission)
);

-- ------------------------------------------------------------------------------
-- 16. INDEXES FOR HIGH-PERFORMANCE DISCOVERY & CALL LOOKUPS
-- ------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_profiles_username ON public.profiles(username);
CREATE INDEX IF NOT EXISTS idx_profiles_gender ON public.profiles(gender);
CREATE INDEX IF NOT EXISTS idx_user_presence_status ON public.user_presence(status, last_seen_at);
CREATE INDEX IF NOT EXISTS idx_favourites_user ON public.favourites(user_id);
CREATE INDEX IF NOT EXISTS idx_calls_caller ON public.calls(caller_id, status);
CREATE INDEX IF NOT EXISTS idx_calls_receiver ON public.calls(receiver_id, status);
CREATE INDEX IF NOT EXISTS idx_call_history_user ON public.call_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_group_rooms_live ON public.group_rooms(is_live, listeners_count DESC);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON public.messages(conversation_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON public.wallet_transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id, is_read, created_at DESC);
