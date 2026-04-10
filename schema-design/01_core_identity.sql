-- =============================================================
-- 01 — Core Identity
-- Tables: users, user_profiles, user_channels,
--         user_platform_access, user_chatwoot_links
-- =============================================================

-- Primary user record. Firebase UID is preserved for migration and
-- external system references; internal UUID is used for all FK relationships.
CREATE TABLE users (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid             TEXT NOT NULL UNIQUE,
    -- Records the platform the account was CREATED on (signup channel), not current usage.
    -- Active platform usage is tracked separately in user_platform_access (has_web, has_ios).
    account_type             TEXT NOT NULL CHECK (account_type IN ('web', 'ios')),
    tracking_code            TEXT UNIQUE,
    expo_token               TEXT,
    is_ghost                 BOOLEAN NOT NULL DEFAULT FALSE,
    created_at               TIMESTAMPTZ NOT NULL,
    last_updated_by_user_at  TIMESTAMPTZ,
    last_updated_by_staff_at TIMESTAMPTZ,
    inserted_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_firebase_uid  ON users (firebase_uid);
CREATE INDEX idx_users_tracking_code ON users (tracking_code) WHERE tracking_code IS NOT NULL;

-- ----------------------------------------------------------------

-- Normalized profile information. Avoids a 50-column users table.
CREATE TABLE user_profiles (
    user_id        UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    first_name     TEXT,
    last_name      TEXT,
    nationality    TEXT,          -- ISO 3166-1 alpha-2
    referral_code  TEXT UNIQUE,   -- this user's own shareable code
    referral_id    TEXT,          -- firebase_uid or tracking_code of the referrer
    client_source  TEXT,          -- 'client_referral', 'instagram', …
    internal_notes TEXT,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------

-- One row per communication channel per user.
-- email, personal_email, whatsapp, line each get their own row.
-- Empty-string values from the source are stored as NULL.
CREATE TABLE user_channels (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel_type  TEXT NOT NULL CHECK (channel_type IN ('email', 'personal_email', 'whatsapp', 'line')),
    channel_value TEXT NOT NULL CHECK (channel_value <> ''),
    is_preferred  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, channel_type)
);

CREATE INDEX idx_user_channels_user_id ON user_channels (user_id);

-- ----------------------------------------------------------------

-- Web / iOS session flags from standard_accounts.connected_platforms.
CREATE TABLE user_platform_access (
    user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    has_web    BOOLEAN NOT NULL DEFAULT FALSE,
    has_ios    BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------

-- Link from an ISSA account to its Chatwoot contact.
-- Migrated from standard_accounts.internal.issa_ai_id.
-- Enables bidirectional lookup: account → conversation and conversation → account.
CREATE TABLE user_chatwoot_links (
    user_id             UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    chatwoot_contact_id BIGINT NOT NULL UNIQUE,
    linked_at           TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_user_chatwoot_contact ON user_chatwoot_links (chatwoot_contact_id);
