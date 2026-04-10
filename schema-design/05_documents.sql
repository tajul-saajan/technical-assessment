-- =============================================================
-- 05 — Documents & Reviews
-- Tables: document_types, user_service_documents,
--         document_submissions, document_reviews,
--         ai_document_reviews
-- =============================================================

-- Catalog of document types per service type.
-- Allows the Legal Dashboard to query: "what docs does a DTV require?"
CREATE TABLE document_types (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_type_id UUID NOT NULL REFERENCES service_types(id),
    code            TEXT NOT NULL,   -- 'dtv_passport', 'dtv_financial-assets', …
    display_name    TEXT NOT NULL,
    is_required     BOOLEAN NOT NULL DEFAULT TRUE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (service_type_id, code)
);

CREATE INDEX idx_document_types_service ON document_types (service_type_id);

-- ----------------------------------------------------------------

-- One row per document type per user service.
-- Tracks current status and staff feedback for each required document.
-- is_custom = TRUE for ad-hoc document types added by staff per-client.
CREATE TABLE user_service_documents (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_service_id  UUID NOT NULL REFERENCES user_services(id) ON DELETE CASCADE,
    document_type_id UUID NOT NULL REFERENCES document_types(id),
    status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'need_changes', 'approved', 'waived')),
    feedback         TEXT,         -- staff feedback shown to client (context/explanation)
    change_request   TEXT,         -- specific action instruction shown to client
    -- 'waived' = staff decision that this document requirement does not apply to this client.
    -- Distinct from 'skipped' (client bypass) — waiving is always a staff action.
    is_waived        BOOLEAN NOT NULL DEFAULT FALSE,
    waived_by        UUID REFERENCES staff_users(id),   -- which staff member waived it
    waived_at        TIMESTAMPTZ,                        -- when the waiver was granted
    is_custom        BOOLEAN NOT NULL DEFAULT FALSE,     -- TRUE for ad-hoc docs added by staff
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_service_id, document_type_id)
);

CREATE INDEX idx_user_service_docs_service ON user_service_documents (user_service_id);
CREATE INDEX idx_user_service_docs_status  ON user_service_documents (status);

-- ----------------------------------------------------------------

-- Each file the client uploads is a separate record.
-- Preserves full upload history even across re-uploads.
-- file_path is the storage bucket path — same format used in ai_document_reviews.file_paths[].
CREATE TABLE document_submissions (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_service_document_id UUID NOT NULL REFERENCES user_service_documents(id) ON DELETE CASCADE,
    file_path                TEXT NOT NULL,
    original_name            TEXT NOT NULL,
    submitted_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_doc_submissions_doc  ON document_submissions (user_service_document_id);
-- Path index enables cross-referencing with ai_document_reviews.file_paths[].
CREATE INDEX idx_doc_submissions_path ON document_submissions (file_path);

-- ----------------------------------------------------------------

-- Append-only staff review history. Mirrors standard_accounts.docs[*].history[].
-- reviewer_email is denormalised: preserved in audit record even if staff account is deleted.
CREATE TABLE document_reviews (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_service_document_id UUID NOT NULL REFERENCES user_service_documents(id),
    reviewer_id              UUID REFERENCES staff_users(id),
    reviewer_email           TEXT NOT NULL,
    action                   TEXT NOT NULL CHECK (action IN ('approved', 'need_changes')),
    change_request           TEXT,   -- populated when action = 'need_changes'
    reviewed_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_doc_reviews_doc      ON document_reviews (user_service_document_id);
CREATE INDEX idx_doc_reviews_reviewer ON document_reviews (reviewer_id);

-- ----------------------------------------------------------------

-- AI review runs. Intentionally SEPARATE from document_reviews (staff actions).
-- AI data is advisory; staff review is authoritative.
-- This boundary is preserved from the current Firestore architecture by design.
-- See 12_design_decisions.md §4.3 for rationale.
--
-- file_paths links back to document_submissions.file_path for cross-referencing
-- which AI run corresponds to which upload event.
-- triggered_at was the map key in Firestore (ISO 8601 timestamp → review run).
CREATE TABLE ai_document_reviews (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- document_type_id replaces document_type_code TEXT — enforces referential integrity
    -- and allows joining directly to document_types without a string scan.
    document_type_id UUID NOT NULL REFERENCES document_types(id),
    -- user_service_id scopes the review to a specific service instance.
    -- AI advisory boundary is preserved: this FK is for queryability only.
    -- No code path should read this table to auto-promote user_service_documents.status.
    user_service_id  UUID REFERENCES user_services(id) ON DELETE SET NULL,
    file_paths       TEXT[] NOT NULL,  -- storage paths reviewed in this run
    result           TEXT NOT NULL CHECK (result IN ('approved', 'rejected', 'unsure')),
    feedback         TEXT NOT NULL,
    model_version    TEXT,             -- e.g. 'gpt-4o-2024-08-06'; NULL if unknown during migration
    triggered_at     TIMESTAMPTZ NOT NULL,  -- original AI trigger time (Firestore map key)
    inserted_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ai_reviews_user     ON ai_document_reviews (user_id);
CREATE INDEX idx_ai_reviews_doc_type ON ai_document_reviews (user_id, document_type_id);
CREATE INDEX idx_ai_reviews_service  ON ai_document_reviews (user_service_id);
CREATE INDEX idx_ai_reviews_time     ON ai_document_reviews (triggered_at);
