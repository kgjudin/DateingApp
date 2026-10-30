-- ==============================================================================
-- VYBE DATABASE ARCHITECTURE - SEED DATA
-- Migration: 03_seed.sql
-- ==============================================================================

-- 1. Insert Default Interests
INSERT INTO public.interests (name, category, icon_name) VALUES
    ('Music', 'Entertainment', 'music_note'),
    ('Movies', 'Entertainment', 'movie'),
    ('Travelling', 'Lifestyle', 'flight_takeoff'),
    ('Technology', 'Career', 'devices'),
    ('Gaming', 'Entertainment', 'sports_esports'),
    ('Sports', 'Fitness', 'fitness_center'),
    ('Photography', 'Art', 'camera_alt'),
    ('Food', 'Lifestyle', 'restaurant'),
    ('Business', 'Career', 'trending_up'),
    ('Art', 'Art', 'palette'),
    ('Fitness', 'Fitness', 'directions_run'),
    ('Books', 'Education', 'menu_book'),
    ('Nature', 'Lifestyle', 'park'),
    ('Entertainment', 'Entertainment', 'theater_comedy'),
    ('Culture', 'Education', 'public'),
    ('Learning', 'Education', 'school'),
    ('Lifestyle', 'Lifestyle', 'self_improvement')
ON CONFLICT (name) DO NOTHING;

-- 2. Insert Default Virtual Gifts
INSERT INTO public.gifts (name, icon_name, coin_price, description) VALUES
    ('Rose', 'rose', 10, 'A sweet red rose to brighten someone''s day.'),
    ('Coffee', 'coffee', 20, 'Warm coffee for a cozy voice chat.'),
    ('Heart', 'favorite', 50, 'Send love and appreciation.'),
    ('Star', 'star', 100, 'You are a shining star in this room!'),
    ('Fire', 'whatshot', 250, 'This conversation is on fire!'),
    ('Trophy', 'emoji_events', 500, 'Champion speaker badge of honor.'),
    ('Diamond', 'diamond', 1000, 'A sparkling diamond of pure luxury.'),
    ('Crown', 'workspace_premium', 2500, 'Royalty status for outstanding hosts.'),
    ('Rocket', 'rocket_launch', 5000, 'To the moon! Ultimate hype gift.'),
    ('Luxury Car', 'directions_car', 10000, 'Grand prestige gift of the platform.')
ON CONFLICT (name) DO UPDATE SET
    coin_price = EXCLUDED.coin_price,
    description = EXCLUDED.description;
