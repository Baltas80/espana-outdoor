CREATE SCHEMA IF NOT EXISTS outdoor;

CREATE TABLE IF NOT EXISTS outdoor.user_profiles (
    subject TEXT PRIMARY KEY,
    display_name VARCHAR(50) NOT NULL CHECK (char_length(display_name) BETWEEN 2 AND 50),
    username VARCHAR(20) NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9][a-z0-9._-]{2,19}$'),
    home_area VARCHAR(80) NOT NULL DEFAULT '',
    bio VARCHAR(160) NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_profiles_updated_at_idx
    ON outdoor.user_profiles (updated_at DESC);
