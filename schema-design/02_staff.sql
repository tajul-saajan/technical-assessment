-- =============================================================
-- 02 — Staff
-- Tables: staff_users
-- =============================================================

-- Internal ISSA staff accounts. Separate from client users.
-- chatwoot_agent_id links to the assignee_id field in conversations,
-- enabling the FK resolution from Chatwoot agent → staff record.
CREATE TABLE staff_users (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email             TEXT NOT NULL UNIQUE,
    display_name      TEXT,
    chatwoot_agent_id BIGINT UNIQUE,  -- maps to conversations.assignee_chatwoot_id
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
