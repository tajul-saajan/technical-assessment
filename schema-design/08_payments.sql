-- =============================================================
-- 08 — Payments
-- Tables: payments
-- =============================================================

-- Stripe payment records per user service.
-- stripe_checkout_url stored here instead of in JSONB blobs on user_service_details.
--
-- No UNIQUE constraint on user_service_id — a single service can have multiple
-- payment rows (failed retries, refunds, add-ons). Use a partial unique index
-- on completed payments to enforce one-active-payment-per-service at the DB level.
CREATE TABLE payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_service_id     UUID NOT NULL REFERENCES user_services(id),
    stripe_payment_id   TEXT UNIQUE,
    stripe_checkout_url TEXT,
    -- Store in smallest currency unit to avoid floating-point bugs (THB satang)
    amount_satangs      BIGINT,
    currency            TEXT NOT NULL DEFAULT 'THB',
    status              TEXT NOT NULL
                        CHECK (status IN ('pending', 'paid', 'refunded', 'refund_eligible', 'cancelled')),
    payment_date        DATE,
    eligible_for_refund TEXT,   -- 'yes_full', 'yes_partial', 'no'
    referrer_paid_at    DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payments_user_service ON payments (user_service_id);
CREATE INDEX idx_payments_stripe_id    ON payments (stripe_payment_id) WHERE stripe_payment_id IS NOT NULL;

-- Enforce at most one completed payment per service at the DB level.
CREATE UNIQUE INDEX idx_payments_one_completed
    ON payments (user_service_id)
    WHERE status = 'paid';
