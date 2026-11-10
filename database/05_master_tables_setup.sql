-- ==============================================================================
-- VYBE MASTER DATABASE SETUP - SUPABASE SQL CONSOLE
-- File: database/05_master_tables_setup.sql
-- ==============================================================================

-- 1. WALLETS TABLE (Stores Coin Balance)
CREATE TABLE IF NOT EXISTS public.wallets (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    coin_balance BIGINT NOT NULL DEFAULT 100 CHECK (coin_balance >= 0),
    lifetime_earned BIGINT NOT NULL DEFAULT 100 CHECK (lifetime_earned >= 0),
    lifetime_spent BIGINT NOT NULL DEFAULT 0 CHECK (lifetime_spent >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. WALLET TRANSACTIONS TABLE (Records Every Purchase, Recharge, and Spent Gift)
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount INT NOT NULL,
    balance_after BIGINT NOT NULL CHECK (balance_after >= 0),
    type VARCHAR(50) NOT NULL DEFAULT 'coin_purchase',
    description TEXT,
    reference_id VARCHAR(120),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. CALL HISTORY TABLE (Records Every Call Done: Outgoing, Incoming, Missed, Ended)
CREATE TABLE IF NOT EXISTS public.call_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id VARCHAR(100),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    peer_id VARCHAR(100),
    other_user_id VARCHAR(100),
    peer_name VARCHAR(150),
    peer_avatar TEXT,
    direction VARCHAR(20) NOT NULL, -- 'outgoing' or 'incoming'
    status VARCHAR(50) NOT NULL DEFAULT 'ended', -- 'ended' or 'missed'
    duration INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. CALL SESSIONS TABLE (For Active Call Signaling)
CREATE TABLE IF NOT EXISTS public.calls (
    id VARCHAR(100) PRIMARY KEY,
    caller_id VARCHAR(100) NOT NULL,
    receiver_id VARCHAR(100) NOT NULL,
    channel_name VARCHAR(120),
    status VARCHAR(50) DEFAULT 'ringing',
    duration INT DEFAULT 0,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ
);

-- 5. INDEXES FOR LIGHTNING FAST QUERIES
CREATE INDEX IF NOT EXISTS idx_wallets_user ON public.wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created ON public.wallet_transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_history_user_created ON public.call_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calls_participants ON public.calls(caller_id, receiver_id);

-- 6. POPULATE EXISTING REGISTERED USERS INTO WALLETS WITH 100 COINS
INSERT INTO public.wallets (user_id, coin_balance, lifetime_earned, lifetime_spent)
SELECT id, 100, 100, 0 FROM auth.users
ON CONFLICT (user_id) DO NOTHING;

-- 7. ENABLE ROW LEVEL SECURITY (RLS) & FULL POLICIES
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role full access on wallets" ON public.wallets;
CREATE POLICY "Service role full access on wallets" 
    ON public.wallets FOR ALL 
    USING (true);

DROP POLICY IF EXISTS "Service role full access on transactions" ON public.wallet_transactions;
CREATE POLICY "Service role full access on transactions" 
    ON public.wallet_transactions FOR ALL 
    USING (true);

DROP POLICY IF EXISTS "Service role full access on call_history" ON public.call_history;
CREATE POLICY "Service role full access on call_history" 
    ON public.call_history FOR ALL 
    USING (true);

DROP POLICY IF EXISTS "Service role full access on calls" ON public.calls;
CREATE POLICY "Service role full access on calls" 
    ON public.calls FOR ALL 
    USING (true);
