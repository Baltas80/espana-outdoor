BEGIN;

CREATE SCHEMA IF NOT EXISTS outdoor;

CREATE TABLE IF NOT EXISTS outdoor.user_profiles (
    subject TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    display_name TEXT NOT NULL,
    home_area TEXT NOT NULL DEFAULT '',
    bio TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS user_profiles_username_ci_uidx
    ON outdoor.user_profiles (lower(username));

COMMIT;
