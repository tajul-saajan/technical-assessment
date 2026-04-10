-- =============================================================
-- 09 — Notifications
-- Tables: notifications
-- =============================================================

CREATE TABLE notifications (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel    TEXT NOT NULL CHECK (channel IN ('push', 'email', 'whatsapp', 'line')),
    title      TEXT,
    body       TEXT NOT NULL,
    -- Structured payload for channel-specific data (e.g. deep-link for push)
    payload    JSONB NOT NULL DEFAULT '{}',
    sent_at    TIMESTAMPTZ,
    read_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user   ON notifications (user_id);
-- Partial index for unread notifications — drives the client notification badge count.
CREATE INDEX idx_notifications_unread ON notifications (user_id, created_at DESC) WHERE read_at IS NULL;
