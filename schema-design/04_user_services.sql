-- =============================================================
-- 04 — User Services (multi-service junction)
-- Tables: user_services, user_service_details
-- =============================================================

-- Central table. One row per user per service instance.
-- A single user can have an active DTV application AND a 90-day reporting
-- service simultaneously — each is a separate user_services row.
-- No UNIQUE constraint on (user_id, service_type_id) — concurrent instances
-- of the same service type are allowed (e.g. DTV renewal during active DTV).
CREATE TABLE user_services (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    service_type_id       UUID NOT NULL REFERENCES service_types(id),
    status                TEXT NOT NULL DEFAULT 'onboarding',
    -- Typical lifecycle: onboarding → waiting_for_client → in_review
    --                    → submitted → approved | rejected | cancelled
    -- WARNING: business purpose is unclear. In source data this sometimes mirrors
    -- firebase_uid and is absent on other records. Validate with team before relying on it.
    request_id            TEXT UNIQUE,
    account_status        TEXT,          -- granular sub-status (e.g. 'waiting_for_client')
    readiness_status      TEXT,
    assigned_staff_id     UUID REFERENCES staff_users(id),
    reviewed_by_staff_id  UUID REFERENCES staff_users(id),
    rejected_at           TIMESTAMPTZ,   -- NULL unless status = 'rejected'
    started_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_services_user_id      ON user_services (user_id);
CREATE INDEX idx_user_services_service_type ON user_services (service_type_id);
CREATE INDEX idx_user_services_status       ON user_services (status);

-- Hot path: client dashboard listing a user's active services.
CREATE INDEX idx_user_services_active ON user_services (user_id, service_type_id)
    WHERE status NOT IN ('rejected', 'cancelled');

-- ----------------------------------------------------------------

-- Per-service-instance metadata in JSONB.
--
-- DTV fields stored here:
--   purpose, package, submission_country, submission_embassy,
--   submission_date, exit_date, applied_before, need_course,
--   buy_course, category_tag, go_to_submission_country_date,
--   skip_entry_stamp, is_not_in_thailand, count_days_processing,
--   final_decision_date, embassy_interview_date, has_embassy_interview
--
-- 90-day reporting fields:
--   last_arrival, last_report, in_thailand, issa_handles_service
--
-- Using JSONB avoids ~40 sparse columns while remaining queryable via GIN index.
-- See 12_design_decisions.md §4.2 for the JSONB vs typed columns tradeoff.
CREATE TABLE user_service_details (
    user_service_id UUID PRIMARY KEY REFERENCES user_services(id) ON DELETE CASCADE,
    details         JSONB NOT NULL DEFAULT '{}',
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_service_details_gin ON user_service_details USING GIN (details);
