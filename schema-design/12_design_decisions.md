# Design Decisions & Rationale

---

## 1. Multi-Service via Junction Table

**Decision:** `user_services` is a many-to-many junction between `users` and `service_types`.

**Why:** The spec explicitly calls for multi-service accounts ("single user with multiple active visas/services"). Storing service type as a column on `users` or hard-coding DTV-specific columns would require a migration every time a new service type is launched. The junction table approach allows any number of concurrent services per user with zero schema changes.

Family applications fall out of this naturally — a family DTV is four `user_services` rows (one per applicant) under the same account, each with its own independent document checklist, workflow steps, and payment record. No separate dependents table is needed; each applicant has a full service lifecycle.

---

## 2. JSONB for Service-Specific Fields

**Decision:** `user_service_details.details JSONB` stores the ~30 service-specific fields (DTV submission dates, 90-day tracking fields, etc.) rather than sparse columns.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| JSONB on `user_service_details` | No migration for new service fields; GIN-indexable | Less strict typing; schema enforcement in application layer |
| Separate table per service type (`dtv_details`, `ninetydays_details`) | Strong typing, foreign keys | New service = new migration; cross-service queries are awkward |
| EAV (entity-attribute-value) | Maximally flexible | Terrible query performance; no typing at all |

JSONB wins because: (1) ISSA is actively adding service types, (2) the fields within a service type also evolve rapidly (the `dtv_need_course` type inconsistency is evidence of this), and (3) PostgreSQL's GIN indexing makes JSONB fields queryable.

---

## 3. AI Reviews as a Separate Table

**Decision:** `ai_document_reviews` is completely separate from `document_reviews` (staff actions).

**Why:** The spec explicitly states "AI review history separated from authoritative account state (intentional boundary)." AI results are advisory — they inform the client and flag issues for staff, but the legal/visa outcome is determined by staff review. Merging them would blur this responsibility boundary and make it harder to audit which decisions were human vs. automated.

---

## 4. NULL Enforcement Over Empty Strings

**Decision:** All nullable text fields use NULL, not `""`.

**Why:** The current Firestore and Chatwoot data uses `""` for missing values in contact fields (`contact_phone`, `contact_email`, etc.) and `""` for `rejected_timestamp` when not rejected. This creates ambiguity. PostgreSQL's NULL semantics are unambiguous. CHECK constraints enforce this at the DB level:

```sql
CHECK (channel_value <> '')
```

The migration script coerces `""` → NULL during import.

---

## 5. UUID Primary Keys

**Decision:** All new tables use `UUID` PKs via `gen_random_uuid()`.

**Why:** Firebase UIDs are already opaque strings — there's no natural integer sequence for migrated users. UUID PKs avoid leaking record counts in URLs and work naturally with external system references. The Chatwoot `conversations` and `social_contacts` tables retain their original BIGINT PKs to preserve external system compatibility.

---

## 6. Denormalised Emails in Audit Tables

**Decision:** `document_reviews.reviewer_email` and `audit_log.actor_email` are denormalised copies.

**Why:** Audit integrity requires that historical records remain interpretable even if the referenced staff account is later deactivated or deleted. A FK to `staff_users` would either block deletion or produce orphaned review records. The email copy is immutable once written.

---

## 7. Partial Unique Index for Payments

**Decision:** No UNIQUE constraint on `payments.user_service_id`. Instead, a partial unique index on `WHERE status = 'paid'`.

**Why:** A hard unique constraint assumes payment never fails and never needs retry. In practice: failed payment → customer retries → second row needed. A partial index enforces the business rule (one completed payment per service) without blocking legitimate retries or refund flows.

---

## 8. Conversations ↔ Users Link Strategy

**Decision:** `conversations.user_id` is populated via the `user_chatwoot_links` table (which maps `chatwoot_contact_id → user_id`).

**Why:** Currently the link is one-directional: `standard_accounts.internal.issa_ai_id` points to the Chatwoot contact. The new schema makes this bidirectional with `user_chatwoot_links`, allowing both sides to find each other. `conversations.user_id` is nullable because many leads never become ISSA account holders.

---

## 9. Scalability & Operational Concerns

### 9.1 Row-Level Security (RLS)

PostgreSQL RLS enforces data isolation at the database layer — a client can only read rows where `user_id = current_setting('app.user_id')::uuid`, regardless of what the application query says. For an immigration platform where one misconfigured query could expose another user's visa documents, this is a meaningful defence-in-depth layer.

Proposed policies on the highest-risk tables (`user_services`, `user_service_documents`, `payments`):

```sql
ALTER TABLE user_services ENABLE ROW LEVEL SECURITY;

-- Clients see only their own services
CREATE POLICY client_isolation ON user_services
    FOR SELECT
    USING (user_id = current_setting('app.user_id')::uuid);

-- Staff bypass RLS via a separate connection role
CREATE POLICY staff_bypass ON user_services
    FOR ALL
    TO staff_role
    USING (true);
```

The application sets `app.user_id` on each connection before executing queries. Staff connections use a dedicated database role (`staff_role`) that bypasses RLS. This means even a SQL injection in the client-facing API cannot return another user's data.

### 9.2 Read Replicas

Write load (status updates, document uploads, audit log inserts) all go to the primary. Two query patterns benefit from a dedicated read replica:

- **Reporting and analytics** — service counts by status, conversion funnels, SLA calculations. These are full-table scans that compete with OLTP writes.
- **Audit log reads** — audit queries are append-only reads against a large, partitioned table. Offloading these removes a consistent source of I/O contention from the primary.

The application routes writes to the primary connection string and reporting/audit reads to the replica. No schema changes required — this is a connection routing decision at the application layer.

### 9.3 Connection Pooling (PgBouncer)

Each PostgreSQL connection holds ~5–10 MB of memory and has a setup cost. Serverless functions, background workers, and mobile clients opening connections directly will exhaust the connection limit under moderate load.

PgBouncer in transaction-mode pooling sits between the application and PostgreSQL: the application opens connections to PgBouncer (cheap), and PgBouncer maintains a smaller pool of real PostgreSQL connections shared across all application threads. A backend that handles 500 concurrent application connections may only need 20–30 real database connections.

Note: transaction-mode pooling is incompatible with session-level `SET` commands — including the `SET app.user_id` required for RLS (§9.1). The solution is to pass the user context as a query parameter or use a connection-level setting before each transaction rather than relying on session state.

### 9.4 Table Partitioning

Two tables grow unboundedly and benefit from range partitioning by time:

| Table | Partition by | Rationale |
|---|---|---|
| `audit_log` | `occurred_at` monthly | Retention management — old partitions detach without locking the live table |
| `conversations` | `created_at` quarterly | Chatwoot data accumulates across all leads, including non-converting ones |

Partitioning setup is documented in `11_audit_log.sql`. The key operational benefit is that dropping an old partition (e.g. data older than 2 years) is an instantaneous metadata operation, not a row-by-row DELETE that locks the table.

Indexes are created per-partition automatically in PostgreSQL 10+. The composite indexes on `(user_id, service_type_id)`, `(entity_type, entity_id)` etc. apply within each partition and remain efficient without covering the full table history.
