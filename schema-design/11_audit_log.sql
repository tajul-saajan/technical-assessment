-- =============================================================
-- 11 — Audit Log (append-only)
-- Tables: audit_log
-- =============================================================

-- Append-only. Never UPDATE or DELETE rows in this table.
--
-- No FK constraints intentionally — rows must survive the deletion of their
-- referenced entities to preserve the complete audit trail.
-- actor_email and entity_id are stored as text for the same reason.
CREATE TABLE audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_type  TEXT NOT NULL
                CHECK (actor_type IN ('user', 'staff', 'ai_agent', 'scheduler', 'system')),
    actor_id    UUID,       -- NULL for system/scheduler events
    actor_email TEXT,       -- denormalized for integrity after account changes
    action      TEXT NOT NULL,
    -- e.g. 'created', 'updated', 'approved', 'rejected', 'submitted', 'deleted'
    entity_type TEXT NOT NULL,
    -- e.g. 'user', 'user_service', 'document_review', 'conversation'
    entity_id   TEXT NOT NULL,  -- stored as text to support UUID and BIGINT entities
    diff        JSONB,          -- { before: {}, after: {} } for mutations
    metadata    JSONB,          -- trace_id, request_id, IP, user agent, etc.
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_log_entity   ON audit_log (entity_type, entity_id);
CREATE INDEX idx_audit_log_actor    ON audit_log (actor_id) WHERE actor_id IS NOT NULL;
CREATE INDEX idx_audit_log_occurred ON audit_log (occurred_at DESC);

-- ----------------------------------------------------------------
-- Partitioning (recommended before table exceeds ~50M rows)
-- ----------------------------------------------------------------
-- At 50k users/month with multiple events per user this table grows fast.
-- Range partitioning by month enables efficient retention management.
--
-- Example setup (PostgreSQL 10+):
--
--   ALTER TABLE audit_log PARTITION BY RANGE (occurred_at);
--
--   CREATE TABLE audit_log_2026_q2 PARTITION OF audit_log
--       FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');
--
--   CREATE TABLE audit_log_2026_q3 PARTITION OF audit_log
--       FOR VALUES FROM ('2026-07-01') TO ('2026-10-01');
--
-- Old partitions can be detached and archived without locking the live table.
