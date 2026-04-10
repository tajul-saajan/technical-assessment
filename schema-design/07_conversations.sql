-- =============================================================
-- 07 — Conversations (normalized from Chatwoot)
-- Tables: social_contacts, conversations, conversation_lead_data
-- =============================================================

-- Normalized contact records. Currently embedded in each conversation row.
-- BIGINT PKs preserve the original Chatwoot contact_id for compatibility.
-- Empty-string values from the source are converted to NULL.
CREATE TABLE social_contacts (
    id              BIGINT PRIMARY KEY,     -- preserve Chatwoot contact_id
    display_name    TEXT NOT NULL,
    phone           TEXT,                   -- NULL (was "" in source)
    email           TEXT,
    language        TEXT,
    profile_pic_url TEXT,
    country_code    TEXT,
    status          TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------

CREATE TABLE conversations (
    id                            BIGINT PRIMARY KEY,   -- preserve Chatwoot conversation id
    contact_id                    BIGINT NOT NULL REFERENCES social_contacts(id),

    -- FK to users populated when client_has_account = true and account is found.
    -- Linked via: conversations.contact_id → user_chatwoot_links.chatwoot_contact_id → users.id
    user_id                       UUID REFERENCES users(id),

    channel_id                    BIGINT NOT NULL,
    channel_name                  TEXT NOT NULL,
    channel_source                TEXT NOT NULL,        -- 'instagram', 'tiktok_business', …
    channel_meta                  JSONB NOT NULL DEFAULT '{}',  -- varies by channel_source

    ai_active                     BOOLEAN NOT NULL DEFAULT FALSE,

    -- NULL when unassigned (replaces assignee_id = 0 from source)
    assignee_id                   UUID REFERENCES staff_users(id),
    assignee_chatwoot_id          BIGINT,               -- raw Chatwoot agent ID for reference

    lifecycle                     TEXT,                 -- 'New Lead', …
    incoming_message_count        INTEGER NOT NULL DEFAULT 0,
    outgoing_message_count        INTEGER NOT NULL DEFAULT 0,
    first_response_time_seconds   INTEGER,
    resolution_time_seconds       INTEGER,

    lifecycle_automation_disabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_waiting_for_legal_review   BOOLEAN NOT NULL DEFAULT FALSE,
    blocked                       BOOLEAN NOT NULL DEFAULT FALSE,
    is_handed_off                 BOOLEAN NOT NULL DEFAULT FALSE,

    conversation_category         TEXT,
    conversation_summary          TEXT,
    notes                         TEXT,
    locale                        TEXT,
    -- tags moved to conversation_tags junction table (see below)

    -- Epoch-adjacent timestamps (values near 1970) are stored as NULL.
    -- Migration identifies these with: WHERE opened_at < '2000-01-01'
    opened_at                     TIMESTAMPTZ,
    closed_at                     TIMESTAMPTZ,
    opened_by_source              TEXT,
    closed_by_staff_id            UUID REFERENCES staff_users(id),

    created_at                    TIMESTAMPTZ NOT NULL,
    updated_at                    TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_conversations_contact     ON conversations (contact_id);
CREATE INDEX idx_conversations_user        ON conversations (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_conversations_assignee    ON conversations (assignee_id) WHERE assignee_id IS NOT NULL;
CREATE INDEX idx_conversations_channel_src ON conversations (channel_source);
CREATE INDEX idx_conversations_created     ON conversations (created_at DESC);
CREATE INDEX idx_conversations_channel_gin  ON conversations USING GIN (channel_meta);

-- ----------------------------------------------------------------

-- Tags (Chatwoot labels) are a managed taxonomy — staff create and name them in Chatwoot,
-- then apply them to conversations. Because they are entities with identity (not free-form
-- strings), they are modelled as a reference table rather than a TEXT[] array.
--
-- Advantages over TEXT[]:
--   - Rename a tag in one row instead of updating every conversation row.
--   - Prevents variant spellings ('DTV', 'dtv', 'Dtv') from becoming separate tags.
--   - Tag metadata (color, description) has a natural home.
--   - Tag usage counts are a simple COUNT(*) instead of array unnesting.
--   - Extensible: the same tags table can reference other entity types in future.
--
-- ON DELETE RESTRICT on tag_id: deleting a tag that is in use requires explicitly
-- untagging all conversations first — prevents accidental data loss.
--
-- Migration: seed tags by SELECT DISTINCT unnest(tags) FROM conversations (source data).
CREATE TABLE tags (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    color       TEXT,           -- hex code for UI rendering, e.g. '#FF5733'
    description TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Junction table: many conversations ↔ many tags.
-- PRIMARY KEY (conversation_id, tag_id) prevents duplicate tagging.
-- tagged_at records when the label was applied (useful for audit and trend queries).
CREATE TABLE conversation_tags (
    conversation_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    tag_id          UUID   NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
    tagged_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (conversation_id, tag_id)
);

-- Reverse lookup: "which conversations carry this tag?" without a full table scan.
CREATE INDEX idx_conversation_tags_tag ON conversation_tags (tag_id);

-- ----------------------------------------------------------------

-- CRM lead qualification data, separated from the core conversation record.
-- Populated progressively by agents or AI as the conversation unfolds.
--
-- Naming: columns use "prospect" not "client" deliberately.
-- At conversation time this person has not purchased anything — calling them a "client"
-- is a premature label. A prospect becomes a client only after they pay and a user_service
-- row exists. Using "client_name", "client_nationality" etc. in the source data was
-- a misnomer; "prospect" reflects the actual CRM stage.
--
-- Structure: four structural fields stay typed (they drive queries, routing, and joins).
-- Everything else collapses into prospect JSONB — these fields are captured progressively
-- and are rarely all present at once. Sparse nullable columns are harder to reason about
-- than a single object that contains only what is known.
--
-- service_details JSONB holds service-specific qualification fields shaped by interested_in.
-- This avoids a wide sparse table as new service types add their own qualification fields.
CREATE TABLE conversation_lead_data (
    conversation_id  BIGINT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    has_account      BOOLEAN,      -- TRUE once this prospect creates an ISSA account
    is_qualified     BOOLEAN,      -- pipeline flag: has this lead met qualification criteria?
    is_emergency     BOOLEAN,      -- priority routing: needs immediate staff attention
    source           TEXT,         -- acquisition channel: 'instagram', 'referral', …
    interested_in    TEXT,         -- service of interest: 'dtv', 'work_permit', … (routes service_details shape)
    -- Progressive snapshot of what is known about this prospect at conversation time.
    -- Populated by AI or agents; fields present only when captured.
    -- Example: {"name":"John","nationality":"GB","location":"Bangkok",
    --            "urgency":"high","buying_segment":"premium","topics":"dtv cost"}
    prospect         JSONB NOT NULL DEFAULT '{}',
    -- Service-specific qualification fields shaped by interested_in value.
    -- DTV:         {"current_visa":"TR","dtv_purpose":"work","applied_before":false,"current_step":"upload"}
    -- Work permit: {"employer_name":"Acme","industry":"tech","current_permit":"B"}
    service_details  JSONB NOT NULL DEFAULT '{}',
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_lead_data_prospect        ON conversation_lead_data USING GIN (prospect);
CREATE INDEX idx_lead_data_service_details ON conversation_lead_data USING GIN (service_details);
