-- ==============================================================================
-- VYBE DATABASE ARCHITECTURE - WALLETS & COINS TABLE SYSTEM
-- File: database/04_wallets_and_coins_table.sql
-- ==============================================================================

-- 1. Create Wallets Table: Stores coin balance, total earned, and total spent for each user
CREATE TABLE IF NOT EXISTS public.wallets (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    coin_balance BIGINT NOT NULL DEFAULT 100 CHECK (coin_balance >= 0),
    lifetime_earned BIGINT NOT NULL DEFAULT 100 CHECK (lifetime_earned >= 0),
    lifetime_spent BIGINT NOT NULL DEFAULT 0 CHECK (lifetime_spent >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Create Wallet Transactions Table: Records every recharge (+) and usage (-)
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount INT NOT NULL, -- positive for recharge/rewards, negative for spending/gifts
    balance_after BIGINT NOT NULL CHECK (balance_after >= 0),
    type VARCHAR(50) NOT NULL DEFAULT 'coin_purchase', -- 'coin_purchase', 'recharge', 'gift_sent', 'gift_received', 'reward', 'refund', 'call_spend'
    description TEXT,
    reference_id VARCHAR(120),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Create Indexes for High Performance Queries
CREATE INDEX IF NOT EXISTS idx_wallets_user ON public.wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created ON public.wallet_transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_type ON public.wallet_transactions(type);

-- Seed existing users immediately
INSERT INTO public.wallets (user_id, coin_balance, lifetime_earned, lifetime_spent)
SELECT id, 100, 100, 0 FROM auth.users
ON CONFLICT (user_id) DO NOTHING;

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

-- 5. Security Policies: Users can view their own wallet and ledger transactions
DROP POLICY IF EXISTS "Users can view own wallet" ON public.wallets;
CREATE POLICY "Users can view own wallet" 
    ON public.wallets FOR SELECT 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view own wallet transactions" ON public.wallet_transactions;
CREATE POLICY "Users can view own wallet transactions" 
    ON public.wallet_transactions FOR SELECT 
    USING (auth.uid() = user_id);

-- Backend service role has full access
DROP POLICY IF EXISTS "Service role full access on wallets" ON public.wallets;
CREATE POLICY "Service role full access on wallets" 
    ON public.wallets FOR ALL 
    USING (auth.jwt()->>'role' = 'service_role' OR auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Service role full access on transactions" ON public.wallet_transactions;
CREATE POLICY "Service role full access on transactions" 
    ON public.wallet_transactions FOR ALL 
    USING (auth.jwt()->>'role' = 'service_role' OR auth.uid() IS NOT NULL);

-- 6. Trigger: Auto-create wallet with 100 free welcome coins whenever a new user registers
CREATE OR REPLACE FUNCTION public.handle_new_user_wallet()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.wallets (
        user_id,
        coin_balance,
        lifetime_earned,
        lifetime_spent,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        100,
        100,
        0,
        NOW(),
        NOW()
    ) ON CONFLICT (user_id) DO NOTHING;

    INSERT INTO public.wallet_transactions (
        user_id,
        amount,
        balance_after,
        type,
        description,
        created_at
    ) VALUES (
        NEW.id,
        100,
        100,
        'reward',
        'Welcome bonus 100 free coins on signup! 🎉',
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_on_auth_user_created_wallet ON auth.users;
CREATE TRIGGER tr_on_auth_user_created_wallet
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_wallet();

-- 7. Stored Procedure: Atomic Coin Recharge (Increases Balance)
CREATE OR REPLACE FUNCTION public.recharge_user_coins(
    p_user_id UUID,
    p_amount INT,
    p_description TEXT DEFAULT 'Coin Recharge',
    p_reference_id VARCHAR DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_new_balance BIGINT;
    v_tx_id UUID;
    v_wallet RECORD;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Recharge amount must be greater than zero.';
    END IF;

    -- Ensure wallet exists
    INSERT INTO public.wallets (user_id, coin_balance, lifetime_earned, lifetime_spent)
    VALUES (p_user_id, 0, 0, 0)
    ON CONFLICT (user_id) DO NOTHING;

    -- Lock wallet row
    SELECT * INTO v_wallet FROM public.wallets WHERE user_id = p_user_id FOR UPDATE;

    v_new_balance := v_wallet.coin_balance + p_amount;

    UPDATE public.wallets
    SET coin_balance = v_new_balance,
        lifetime_earned = lifetime_earned + p_amount,
        updated_at = NOW()
    WHERE user_id = p_user_id;

    INSERT INTO public.wallet_transactions (
        user_id,
        amount,
        balance_after,
        type,
        description,
        reference_id,
        created_at
    ) VALUES (
        p_user_id,
        p_amount,
        v_new_balance,
        'recharge',
        COALESCE(p_description, 'Recharge of ' || p_amount || ' coins'),
        p_reference_id,
        NOW()
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'userId', p_user_id,
        'amountAdded', p_amount,
        'newBalance', v_new_balance,
        'transactionId', v_tx_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Stored Procedure: Atomic Coin Usage (Reduces Balance)
CREATE OR REPLACE FUNCTION public.deduct_user_coins(
    p_user_id UUID,
    p_amount INT,
    p_type VARCHAR DEFAULT 'coin_spent',
    p_description TEXT DEFAULT 'Used Coins',
    p_reference_id VARCHAR DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_new_balance BIGINT;
    v_tx_id UUID;
    v_wallet RECORD;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Deduct amount must be greater than zero.';
    END IF;

    -- Lock wallet row
    SELECT * INTO v_wallet FROM public.wallets WHERE user_id = p_user_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User wallet not found.';
    END IF;

    IF v_wallet.coin_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient coins. Current balance: %, Required: %', v_wallet.coin_balance, p_amount;
    END IF;

    v_new_balance := v_wallet.coin_balance - p_amount;

    UPDATE public.wallets
    SET coin_balance = v_new_balance,
        lifetime_spent = lifetime_spent + p_amount,
        updated_at = NOW()
    WHERE user_id = p_user_id;

    INSERT INTO public.wallet_transactions (
        user_id,
        amount,
        balance_after,
        type,
        description,
        reference_id,
        created_at
    ) VALUES (
        p_user_id,
        -p_amount,
        v_new_balance,
        COALESCE(p_type, 'coin_spent'),
        COALESCE(p_description, 'Spent ' || p_amount || ' coins'),
        p_reference_id,
        NOW()
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'userId', p_user_id,
        'amountDeducted', p_amount,
        'newBalance', v_new_balance,
        'transactionId', v_tx_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
