# Data Quality Fixes

Five specific issues identified in the source data, each addressed at the schema level.

---

## 1. `rejected_timestamp: ""` instead of NULL

**Source:** `standard_accounts.info.rejected_timestamp`  
**Problem:** An empty string is used to represent "not rejected" instead of NULL. This means the field has two representations of the same state and breaks standard NULL-check queries.  
**Fix:** Stored as `rejected_at TIMESTAMPTZ NULL` on `user_services`. Migration script coerces `""` → NULL. Constraint added:
```sql
CHECK (rejected_at IS NULL OR rejected_at > '2000-01-01')
```

---

## 2. `dtv_need_course` typed inconsistently as boolean / string / null

**Source:** `standard_accounts.info.dtv_need_course`  
**Problem:** Same field observed as `false` (boolean), `null`, and `"true"` (string) across different records. Impossible to query reliably.  
**Fix:** Stored as `BOOLEAN` inside `user_service_details.details` JSONB. Migration script normalises all values: `"true"` → `true`, `"false"` → `false`, `""` → `null`.

---

## 3. `user_id` is a redundant mirror of `id`

**Source:** `standard_accounts.user_id`  
**Problem:** Present on some accounts, absent on others. Always equals `id` when present. Creates ambiguity about which field is authoritative.  
**Fix:** Dropped entirely. `users.firebase_uid` is the canonical external reference. No downstream system should be relying on `user_id` independently.

---

## 4. Empty strings in Chatwoot contact fields

**Source:** `public.conversations` — `contact_phone`, `contact_email`, `contact_language`, `contact_profile_pic`, `contact_country_code`  
**Problem:** Uses `""` (empty string) rather than NULL when data is absent. Makes IS NULL checks unreliable and inflates storage.  
**Fix:** All nullable contact fields in `social_contacts` and `conversations` use NULL. Migration coerces `""` → NULL. CHECK constraints prevent future empty-string insertion.

---

## 5. Epoch-adjacent timestamps (~1970) in conversation records

**Source:** `public.conversations.conversation_opened_at`, `conversation_closed_at`  
**Problem:** Some records contain timestamps near the Unix epoch (`1970-01-21T18:52:12+07:00`), indicating a bug in the upstream Chatwoot event system. These corrupt SLA calculations (first response time, resolution time) and date-range queries.  
**Fix:** Stored as NULL in `conversations.opened_at` / `closed_at`. Migration identifies them with:
```sql
WHERE opened_at < '2000-01-01'
```
Each nulled record is logged to `audit_log` with `action = 'epoch_timestamp_nulled'` for traceability.
