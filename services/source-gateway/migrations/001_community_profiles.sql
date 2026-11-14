CREATE TABLE IF NOT EXISTS community_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subject TEXT NOT NULL UNIQUE,
    display_name TEXT NULL CHECK (
        display_name IS NULL OR char_length(display_name) BETWEEN 2 AND 80
    ),
    email TEXT NULL CHECK (
        email IS NULL OR char_length(email) <= 254
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS community_profiles_updated_at_idx
    ON community_profiles (updated_at DESC);
