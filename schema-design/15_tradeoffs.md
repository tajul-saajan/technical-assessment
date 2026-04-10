# Tradeoffs & Open Questions

These are the decisions I made reasonable assumptions on to keep the proposal moving. Each one changes something real in the schema — a constraint, a table structure, or the migration approach. I would want to validate these with the team before treating any of it as final.

---

**1. Can a single user have two active instances of the same service type simultaneously?**

For example: a DTV renewal started while the original application is still in-flight, or two family members applying under the same account. I've assumed yes — there is no UNIQUE constraint on `(user_id, service_type_id)` in `user_services`. If the answer is no, adding that constraint catches duplicates at the database level and simplifies some queries.

---

**2. Is one payment per service confirmed, or can a service have multiple payment records?**

Failed payment retries, instalment plans, and add-on fees would all produce more than one payment row per service. I've used a partial unique index (`WHERE status = 'paid'`) as the safer default. If one-payment-per-service is a firm business rule, a full unique constraint on `user_service_id` is cleaner and I'd use that instead.

---

**3. Which Stripe objects are in use — PaymentIntent, Checkout Session, Invoice, or Subscription?**

The `stripe_payment_url` in the current data looks like a Checkout Session link, so I've modelled payments as one-off transactions. If Subscriptions are involved for any service type, the payment model changes significantly — recurring billing means multiple rows over time rather than one per service.

---

**4. For the 90-day reporting service — does each reporting cycle create a new service instance, or is there one persistent record per user that recurs?**

If every cycle is a fresh submission, a long-term resident accumulates many `user_services` rows and the table needs to accommodate that volume. If it's a single record with a recurring job behind it, the data model and queuing logic look different. I've left this open in the current design.

---

**5. What happens when a client uploads a new file for a document already in approved status?**

Does the approval get revoked and the document reset to pending? Or does the new file sit until staff explicitly trigger re-review? This determines whether `user_service_documents.status` is mutable after approval and whether the review history needs a "superseded" concept.

---

**6. Is the migration a hard cutover or a dual-write period?**

Dual-write means every write path fans out to two stores for the duration of the transition — significant engineering overhead, and the two stores can drift if any write path is missed. Hard cutover means a backfill job, a switchover window, and a tested rollback path. The schema is the same either way but the migration plan is completely different.

---

**7. Does PDPA apply alongside GDPR?**

Thailand's PDPA has its own requirements around consent, data subject rights, and breach notification that are not identical to GDPR. If both apply simultaneously, the deletion workflow and audit log retention need to satisfy both at once. I've modelled GDPR-style hard delete with audit anonymisation (`actor_id` → NULL, `entity_id` → `[deleted]`), but I'd want to confirm whether PDPA changes any of those assumptions.

---

**8. When a user requests account deletion, are audit log rows about them also deleted?**

I've anonymised audit rows on deletion rather than deleting them, on the basis that an immigration platform has a legitimate legal basis to retain audit records even after account closure. If that assumption is wrong — if audit rows must also be purged — the cascade design changes significantly. This needs a legal call, not an engineering assumption.

---

**9. JSONB vs typed columns for service-specific fields — revisit trigger**

If DTV-specific queries on `user_service_details.details` become frequent and complex (e.g. "find all DTV users where submission_country = 'VN' and status = 'submitted'"), a dedicated `dtv_service_details` table with typed columns and proper indexes is worth revisiting. The GIN index on JSONB handles this reasonably at current scale but has limits.

---

**10. Document sharing across service types**

If a user has both a DTV application and a work permit active, and both require a passport — are these separate document submissions (one per service)? I've modelled documents as belonging to a specific service, which keeps service lifecycles independent. But if an approved document should carry over across services, a join table is needed and the review history becomes more complex.

---

**11. What is the intended structure of `messages` and `shared_docs`?**

Both fields on `standard_accounts` are always `{}` in the sample data — no populated example exists anywhere in the provided documentation. If `messages` is an active in-app messaging system, it needs its own table (sender, recipient, body, read_at, thread). If `shared_docs` is for staff sharing templates or guides with clients, it needs a similar treatment. If either was abandoned or not yet built, they can stay out of scope. Cannot model these correctly without a populated example.

---

**12. Should document waiving track `waived_by` and `waived_at`, or is a boolean flag sufficient?**

I've added `waived_by UUID REFERENCES staff_users(id)` and `waived_at TIMESTAMPTZ` to `user_service_documents` alongside `is_waived`. For a visa compliance product, knowing *who* waived a document requirement and *when* seems essential — a waiver without attribution has no audit value. If the business intent is only to suppress the document from the client's checklist (UI flag only), a boolean is enough and the accountability columns add unnecessary complexity.

---

**13. Can workflow steps be customised per client, or is the step list always uniform per service type?**

Currently `workflow_step_definitions` is defined at the service type level — every DTV application follows the same step sequence. There is no mechanism for a staff member to add a bespoke step for a specific client (e.g. "obtain embassy appointment letter before proceeding").

If custom per-client steps are a real requirement, I'd add an optional `user_service_id` column to `workflow_step_definitions`:

```sql
-- NULL = global step, applies to all instances of this service type
-- non-NULL = custom step visible only to this specific service instance
user_service_id UUID REFERENCES user_services(id) ON DELETE CASCADE
```

The progress bar query then filters `WHERE service_type_id = ? AND (user_service_id IS NULL OR user_service_id = ?)`. This keeps `workflow_step_definitions` as the single source of truth for display name and ordering — avoids spreading definition data into the completion table. The alternative (allowing free-form step codes in `user_service_steps` with no matching definition) is simpler but loses display name and ordering for custom steps entirely.

---

**14. Should roles have an explicit permissions table (RBAC), or is application-layer role checking sufficient?**

The current `roles` table is a coarse label — access control logic (`if role == 'legal_staff': allow`) lives entirely in application code. This is fast to build and sufficient when role boundaries are stable and well-understood across a small team.

A `role_permissions` table becomes necessary when:
- A staff member needs temporary or case-specific elevated access.
- Two people share the same role but need different allowed actions (e.g. one legal reviewer handles DTV only).
- Audit requirements demand proof that access was explicitly granted rather than inferred from a role name.

The standard evolution is:

```sql
CREATE TABLE permissions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code        TEXT NOT NULL UNIQUE,  -- e.g. 'document:review', 'payment:refund', 'user:delete'
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE role_permissions (
    role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);
```

I've left this out of the current schema — there are no requirements in the spec around fine-grained permissions, and an empty permissions table with no seed data provides no value over application-layer checks. This is the natural next step once the team identifies the first case where two users share a role but need different access.
