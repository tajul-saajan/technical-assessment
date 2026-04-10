# Migration Strategy

Five phases. Each phase is independently verifiable before the next begins.

---

## Phase 1 — Schema Creation + Reference Data

Run all SQL files in order (`01` → `11`).  
Seed reference tables: `service_types`, `roles`, `workflow_step_definitions`, `document_types`.  
Verify: row counts match expected seed values, all FK constraints validate.

---

## Phase 2 — Migrate `standard_accounts` (Firestore → PostgreSQL)

For each Firestore document:

1. Insert into `users` (`firebase_uid`, `account_type`, `tracking_code`, `expo_token`, `created_at`)
2. Insert into `user_profiles` (name, nationality, referral fields, `client_source`)
3. Insert channel rows into `user_channels` — coerce `""` → NULL, skip nulls
4. Insert into `user_platform_access` (`has_web`, `has_ios`)
5. Insert into `user_chatwoot_links` if `internal.issa_ai_id` is set
6. For each service (currently one per account, keyed by `visa_type`):
   - Insert into `user_services` (resolve `service_type_id` from `visa_type` code)
   - Extract DTV/90-day fields into `user_service_details.details` as JSONB
   - Normalise `dtv_need_course` → BOOLEAN; coerce `""` → NULL throughout
   - Insert completed steps into `user_service_steps`
7. For each document in `docs`:
   - Resolve `document_type_id` from code (e.g. `dtv_passport`)
   - Insert into `user_service_documents` (current status, feedback, change_request)
   - Insert each file into `document_submissions`
   - Insert each history entry into `document_reviews` (resolve `reviewer_id` via email lookup)
8. Insert payment fields into `payments` where non-empty

---

## Phase 3 — Migrate `ai-doc-review` (Firestore → PostgreSQL)

For each user with `exists: true`:

- Iterate over `data[docTypeId][timestamp]` entries (timestamp was the map key)
- Resolve `user_id` via `firebase_uid → users` lookup
- Insert into `ai_document_reviews` (`triggered_at` = the map key timestamp)

Users with `exists: false` produce no rows — this is correct behaviour.

---

## Phase 4 — Migrate `public.conversations` (PostgreSQL → PostgreSQL)

1. Extract unique contacts → insert into `social_contacts` (coerce `""` → NULL)
2. Insert conversation rows:
   - Map `assignee_id = 0` → NULL
   - Null epoch-adjacent timestamps (< 2000-01-01), log each to `audit_log`
   - Resolve `assignee_id` UUID via `chatwoot_agent_id → staff_users` lookup
3. Insert CRM fields → `conversation_lead_data`
4. Resolve `user_id` links: join `conversations.contact_id` → `user_chatwoot_links.chatwoot_contact_id` → `users.id`

---

## Phase 5 — Verify

- Row counts must match source for every table
- Sampled records compared field-by-field against source documents
- All FK constraints pass (`SELECT * FROM information_schema.referential_constraints`)
- Spot-check: pick 5 real Firebase UIDs, verify their full service + document history is intact
- Verify NULL counts — no empty strings remaining in nullable text columns

---

## Cutover Question

**Hard cutover vs. dual-write** is the most impactful operational decision and is not answered here — it requires input from the team. See `15_tradeoffs.md` question 6.
