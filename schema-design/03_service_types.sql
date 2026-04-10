-- =============================================================
-- 03 — Service Types (extensible registry)
-- Tables: service_types
-- =============================================================

-- Adding a new service type (e.g. 'elite_visa') requires only an INSERT here,
-- not a schema migration. No per-service columns anywhere else in the schema.
CREATE TABLE service_types (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code        TEXT NOT NULL UNIQUE,  -- 'dtv', 'work_permit', '90_day_reporting', …
    name        TEXT NOT NULL,
    description TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------
-- Seed data — run as part of service init / migration
-- ----------------------------------------------------------------

INSERT INTO service_types (code, name) VALUES
    ('dtv',              'Digital Nomad Visa'),
    ('work_permit',      'Work Permit'),
    ('90_day_reporting', '90-Day Reporting'),
    ('address_update',   'Address Update'),
    ('marriage_permit',  'Marriage Permit'),
    ('tax',              'Tax Services');
