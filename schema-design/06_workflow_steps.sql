-- =============================================================
-- 06 — Workflow Steps
-- Tables: workflow_step_definitions, user_service_steps
-- =============================================================

-- Master list of step codes per service type.
-- E.g. DTV: dtv_begin, dtv_upload, dtv_submitted, dtv_approved.
-- user_service_id = NULL  → global step, applies to all instances of this service type.
-- user_service_id = non-NULL → custom step visible only to that specific service instance.
-- Progress bar query: WHERE service_type_id = ? AND (user_service_id IS NULL OR user_service_id = ?)
CREATE TABLE workflow_step_definitions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_type_id UUID NOT NULL REFERENCES service_types(id),
    -- NULL = global; non-NULL = custom step added by staff for one client only.
    user_service_id UUID REFERENCES user_services(id) ON DELETE CASCADE,
    step_code       TEXT NOT NULL,
    display_name    TEXT NOT NULL,
    step_order      INTEGER NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (service_type_id, user_service_id, step_code)
);

-- ----------------------------------------------------------------

-- Completion record per step per user service.
-- Migrated from standard_accounts.steps (the step_id → {done} map).
-- UNIQUE constraint prevents a step being marked done twice.
CREATE TABLE user_service_steps (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_service_id UUID NOT NULL REFERENCES user_services(id) ON DELETE CASCADE,
    step_code       TEXT NOT NULL,
    completed_at    TIMESTAMPTZ NOT NULL,
    UNIQUE (user_service_id, step_code)
);

CREATE INDEX idx_user_service_steps_service ON user_service_steps (user_service_id);
