-- ==============================================================================
-- VYBE DATABASE ARCHITECTURE - FUNCTIONS, TRIGGERS & RLS POLICIES
-- Migration: 02_functions_and_triggers.sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. TRIGGER FUNCTION: Initialize User on Auth Signup
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_username VARCHAR(50);
    v_display_name VARCHAR(100);
BEGIN
    -- Extract username from metadata or email
    v_username := COALESCE(
        NEW.raw_user_meta_data->>'username',
        SPLIT_PART(NEW.email, '@', 1) || '_' || SUBSTRING(NEW.id::TEXT, 1, 4)
    );
    v_display_name := COALESCE(
        NEW.raw_user_meta_data->>'display_name',
        SPLIT_PART(NEW.email, '@', 1),
        'Vyber'
    );

    -- 1. Insert Profile
    INSERT INTO public.profiles (
        id,
        username,
        display_name,
        date_of_birth,
        gender,
        bio,
        avatar_url,
        languages
    ) VALUES (
        NEW.id,
        v_username,
        v_display_name,
        COALESCE((NEW.raw_user_meta_data->>'date_of_birth')::DATE, '2000-01-01'::DATE),
        COALESCE((NEW.raw_user_meta_data->>'gender')::user_gender, 'prefer_not_to_say'::user_gender),
        COALESCE(NEW.raw_user_meta_data->>'bio', 'Hey there! I love voice conversations on VYBE.'),
        NEW.raw_user_meta_data->>'avatar_url',
        ARRAY['English']
    ) ON CONFLICT (id) DO NOTHING;

    -- 2. Insert Preferences
    INSERT INTO public.user_preferences (
        user_id,
        preferred_genders,
        discovery_enabled,
        who_can_call_me
    ) VALUES (
        NEW.id,
        ARRAY['everyone'],
        TRUE,
        'everyone'
    ) ON CONFLICT (user_id) DO NOTHING;

    -- 3. Insert Initial Presence
    INSERT INTO public.user_presence (
        user_id,
        status,
        last_seen_at
    ) VALUES (
        NEW.id,
        'online',
        NOW()
    ) ON CONFLICT (user_id) DO NOTHING;

    -- 4. Insert Initial Wallet with 100 Welcome Coins
    INSERT INTO public.wallets (
        user_id,
        coin_balance,
        lifetime_earned,
        lifetime_spent
    ) VALUES (
        NEW.id,
        100,
        100,
        0
    ) ON CONFLICT (user_id) DO NOTHING;

    -- 5. Record Welcome Bonus Transaction
    INSERT INTO public.wallet_transactions (
        user_id,
        amount,
        balance_after,
        type,
        description
    ) VALUES (
        NEW.id,
        100,
        100,
        'reward',
        'Welcome to VYBE! 100 Free Bonus Coins'
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to auth.users if available
DO $$ BEGIN
    DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
    CREATE TRIGGER on_auth_user_created
        AFTER INSERT ON auth.users
        FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
EXCEPTION
    WHEN undefined_table THEN null; -- If running standalone migration test
END $$;

-- ------------------------------------------------------------------------------
-- 2. ATOMIC FUNCTION: transfer_gift_coins (Guarantees ACID transactions)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.transfer_gift_coins(
    p_sender_id UUID,
    p_receiver_id UUID,
    p_gift_id UUID,
    p_room_id UUID DEFAULT NULL,
    p_message TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_gift RECORD;
    v_sender_wallet RECORD;
    v_receiver_wallet RECORD;
    v_gift_tx_id UUID;
    v_sender_new_balance BIGINT;
    v_receiver_new_balance BIGINT;
    v_sender_name TEXT;
BEGIN
    -- Prevent self gifting
    IF p_sender_id = p_receiver_id THEN
        RAISE EXCEPTION 'You cannot send gifts to yourself.';
    END IF;

    -- Check if sender is blocked by receiver or vice-versa
    IF EXISTS (
        SELECT 1 FROM public.user_blocks 
        WHERE (blocker_id = p_receiver_id AND blocked_id = p_sender_id)
           OR (blocker_id = p_sender_id AND blocked_id = p_receiver_id)
    ) THEN
        RAISE EXCEPTION 'Action not permitted due to block settings.';
    END IF;

    -- Fetch gift details
    SELECT * INTO v_gift FROM public.gifts WHERE id = p_gift_id AND is_active = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Gift not found or inactive.';
    END IF;

    -- Lock and check sender wallet
    SELECT * INTO v_sender_wallet 
    FROM public.wallets 
    WHERE user_id = p_sender_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sender wallet does not exist.';
    END IF;

    IF v_sender_wallet.coin_balance < v_gift.coin_price THEN
        RAISE EXCEPTION 'Insufficient coins. Balance: %, Required: %', v_sender_wallet.coin_balance, v_gift.coin_price;
    END IF;

    -- Lock and check receiver wallet
    SELECT * INTO v_receiver_wallet 
    FROM public.wallets 
    WHERE user_id = p_receiver_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Initialize receiver wallet if not present
        INSERT INTO public.wallets (user_id, coin_balance, lifetime_earned, lifetime_spent)
        VALUES (p_receiver_id, 0, 0, 0)
        RETURNING * INTO v_receiver_wallet;
    END IF;

    -- Calculate new balances
    v_sender_new_balance := v_sender_wallet.coin_balance - v_gift.coin_price;
    v_receiver_new_balance := v_receiver_wallet.coin_balance + v_gift.coin_price;

    -- Update sender wallet
    UPDATE public.wallets
    SET coin_balance = v_sender_new_balance,
        lifetime_spent = lifetime_spent + v_gift.coin_price,
        updated_at = NOW()
    WHERE user_id = p_sender_id;

    -- Update receiver wallet
    UPDATE public.wallets
    SET coin_balance = v_receiver_new_balance,
        lifetime_earned = lifetime_earned + v_gift.coin_price,
        updated_at = NOW()
    WHERE user_id = p_receiver_id;

    -- Insert gift transaction record
    INSERT INTO public.gift_transactions (
        sender_id,
        receiver_id,
        gift_id,
        room_id,
        coin_amount,
        message
    ) VALUES (
        p_sender_id,
        p_receiver_id,
        p_gift_id,
        p_room_id,
        v_gift.coin_price,
        p_message
    ) RETURNING id INTO v_gift_tx_id;

    -- Insert debit transaction for sender
    INSERT INTO public.wallet_transactions (
        user_id,
        amount,
        balance_after,
        type,
        description,
        reference_id
    ) VALUES (
        p_sender_id,
        -v_gift.coin_price,
        v_sender_new_balance,
        'gift_sent',
        'Sent gift ' || v_gift.name,
        v_gift_tx_id::TEXT
    );

    -- Insert credit transaction for receiver
    INSERT INTO public.wallet_transactions (
        user_id,
        amount,
        balance_after,
        type,
        description,
        reference_id
    ) VALUES (
        p_receiver_id,
        v_gift.coin_price,
        v_receiver_new_balance,
        'gift_received',
        'Received gift ' || v_gift.name,
        v_gift_tx_id::TEXT
    );

    -- Fetch sender display name for notification
    SELECT display_name INTO v_sender_name FROM public.profiles WHERE id = p_sender_id;

    -- Notify receiver
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        body,
        payload
    ) VALUES (
        p_receiver_id,
        'gift_received',
        'Gift Received!',
        COALESCE(v_sender_name, 'A user') || ' sent you a ' || v_gift.name || '!',
        jsonb_build_object(
            'gift_transaction_id', v_gift_tx_id,
            'gift_name', v_gift.name,
            'icon_name', v_gift.icon_name,
            'coin_price', v_gift.coin_price,
            'sender_id', p_sender_id,
            'room_id', p_room_id
        )
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'transaction_id', v_gift_tx_id,
        'gift_name', v_gift.name,
        'coin_price', v_gift.coin_price,
        'sender_new_balance', v_sender_new_balance
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 3. FUNCTION: record_call_ended
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_call_ended(
    p_call_id UUID,
    p_end_reason VARCHAR(50),
    p_duration INT
)
RETURNS VOID AS $$
DECLARE
    v_call RECORD;
BEGIN
    SELECT * INTO v_call FROM public.calls WHERE id = p_call_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Update call table
    UPDATE public.calls
    SET status = 'ended',
        ended_at = NOW(),
        duration = p_duration,
        end_reason = p_end_reason
    WHERE id = p_call_id;

    -- Insert into history for Caller
    INSERT INTO public.call_history (call_id, user_id, other_user_id, direction, status, duration)
    VALUES (p_call_id, v_call.caller_id, v_call.receiver_id, 'outgoing', 'ended', p_duration);

    -- Insert into history for Receiver
    INSERT INTO public.call_history (call_id, user_id, other_user_id, direction, status, duration)
    VALUES (p_call_id, v_call.receiver_id, v_call.caller_id, 'incoming', 
            CASE WHEN p_end_reason = 'missed' THEN 'missed'::call_status ELSE 'ended'::call_status END, 
            p_duration);

    -- Reset user presence back to online
    UPDATE public.user_presence SET status = 'online', active_call_id = NULL WHERE user_id IN (v_call.caller_id, v_call.receiver_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 4. FUNCTION: update_presence_heartbeat
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_presence_heartbeat(
    p_user_id UUID,
    p_status presence_status DEFAULT 'online'
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.user_presence (user_id, status, last_seen_at, updated_at)
    VALUES (p_user_id, p_status, NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET status = p_status,
        last_seen_at = NOW(),
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favourites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gift_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

-- Profiles: Anyone can view non-suspended profiles, users can update their own
CREATE POLICY "Public profiles are viewable by everyone" 
    ON public.profiles FOR SELECT 
    USING (is_suspended = FALSE);

CREATE POLICY "Users can update their own profile" 
    ON public.profiles FOR UPDATE 
    USING (auth.uid() = id);

-- Profile Photos:
CREATE POLICY "Photos viewable by everyone" 
    ON public.profile_photos FOR SELECT 
    USING (TRUE);

CREATE POLICY "Users can manage their photos" 
    ON public.profile_photos FOR ALL 
    USING (auth.uid() = user_id);

-- Preferences:
CREATE POLICY "Users can manage own preferences" 
    ON public.user_preferences FOR ALL 
    USING (auth.uid() = user_id);

-- Presence:
CREATE POLICY "Presence viewable by authenticated users" 
    ON public.user_presence FOR SELECT 
    USING (TRUE);

CREATE POLICY "Users can update own presence" 
    ON public.user_presence FOR ALL 
    USING (auth.uid() = user_id);

-- Favourites:
CREATE POLICY "Users can manage own favourites" 
    ON public.favourites FOR ALL 
    USING (auth.uid() = user_id);

-- Calls:
CREATE POLICY "Call participants can view call details" 
    ON public.calls FOR SELECT 
    USING (auth.uid() = caller_id OR auth.uid() = receiver_id);

CREATE POLICY "Callers can insert calls" 
    ON public.calls FOR INSERT 
    WITH CHECK (auth.uid() = caller_id);

CREATE POLICY "Call participants can update calls" 
    ON public.calls FOR UPDATE 
    USING (auth.uid() = caller_id OR auth.uid() = receiver_id);

-- Call History:
CREATE POLICY "Users can view own call history" 
    ON public.call_history FOR SELECT 
    USING (auth.uid() = user_id);

-- Groups & Rooms:
CREATE POLICY "Groups viewable by authenticated users" 
    ON public.groups FOR SELECT 
    USING (TRUE);

CREATE POLICY "Users can create groups" 
    ON public.groups FOR INSERT 
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Owners can update their groups" 
    ON public.groups FOR UPDATE 
    USING (auth.uid() = owner_id);

CREATE POLICY "Group rooms viewable by all" 
    ON public.group_rooms FOR SELECT 
    USING (TRUE);

-- Messages:
CREATE POLICY "Participants can view conversation messages" 
    ON public.messages FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM public.conversation_participants 
            WHERE conversation_id = messages.conversation_id AND user_id = auth.uid()
        )
    );

CREATE POLICY "Participants can send messages" 
    ON public.messages FOR INSERT 
    WITH CHECK (auth.uid() = sender_id);

-- Wallets (Strict Security: Users can SELECT own wallet; UPDATES only via backend security definer functions):
CREATE POLICY "Users can view own wallet" 
    ON public.wallets FOR SELECT 
    USING (auth.uid() = user_id);

CREATE POLICY "Users can view own wallet transactions" 
    ON public.wallet_transactions FOR SELECT 
    USING (auth.uid() = user_id);

-- Gift Transactions:
CREATE POLICY "Users can view gifts they sent or received" 
    ON public.gift_transactions FOR SELECT 
    USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- Notifications:
CREATE POLICY "Users can view own notifications" 
    ON public.notifications FOR SELECT 
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update own notifications" 
    ON public.notifications FOR UPDATE 
    USING (auth.uid() = user_id);

-- Blocks:
CREATE POLICY "Users can manage blocks" 
    ON public.user_blocks FOR ALL 
    USING (auth.uid() = blocker_id);

-- Reports:
CREATE POLICY "Users can insert reports" 
    ON public.user_reports FOR INSERT 
    WITH CHECK (auth.uid() = reporter_id);
