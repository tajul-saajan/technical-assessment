-- =============================================================
-- 10 — Access Control
-- Tables: roles, user_roles
-- =============================================================

CREATE TABLE roles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code        TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed data
INSERT INTO roles (code, description) VALUES
    ('client',      'Client-facing mobile/web user'),
    ('staff',       'ISSA internal staff'),
    ('legal_staff', 'Legal dashboard reviewer'),
    ('admin',       'Platform administrator'),
    ('ai_agent',    'Automated AI coordination layer'),
    ('scheduler',   'Batch job runner');

-- ----------------------------------------------------------------

CREATE TABLE user_roles (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id    UUID NOT NULL REFERENCES roles(id),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    granted_by UUID REFERENCES staff_users(id),
    PRIMARY KEY (user_id, role_id)
);
