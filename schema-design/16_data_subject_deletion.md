# Data Subject Deletion Workflow — GDPR & PDPA

ISSA Compass operates under two data protection regimes simultaneously:

- **GDPR** (EU Regulation 2016/679) — applies to any user who is an EU/EEA resident, regardless of where ISSA is based. Right to erasure under Article 17.
- **PDPA** (Thailand Personal Data Protection Act B.E. 2562) — applies to any personal data collected, used, or disclosed in Thailand. Right to erasure under Section 33.

The deletion cascade is identical for both. The differences are in **response timelines**, **notification requirements**, and **the legal basis for retention exceptions**.

---

## What Gets Deleted vs. Retained

| Data | Action | Reason |
|---|---|---|
| `users` row | Hard delete | Primary identity record — cascades to all child tables |
| `user_profiles` | Cascade delete | Personal data: name, nationality |
| `user_channels` | Cascade delete | Personal data: email, phone, WhatsApp, Line |
| `user_platform_access` | Cascade delete | Behavioural data |
| `user_chatwoot_links` | Cascade delete | External system link |
| `user_services` | Cascade delete | Service instances owned by the user |
| `user_service_details` | Cascade delete | Via `user_services` |
| `user_service_documents` | Cascade delete | Via `user_services` |
| `document_submissions` | Cascade delete | File path records; physical files deleted separately (see §4) |
| `user_service_steps` | Cascade delete | Via `user_services` |
| `ai_document_reviews` | Cascade delete | AI advisory data linked to the user |
| `payments` | Cascade delete | Via `user_services` |
| `notifications` | Cascade delete | |
| `user_roles` | Cascade delete | |
| `document_reviews` | **Retained** | `reviewer_email` is denormalised (staff identity, not client PII); `reviewer_id` FK goes NULL on staff deletion but review record stays |
| `conversations` | **Retained — unlinked** | `conversations.user_id` SET NULL; conversation remains as an unlinked lead record for Chatwoot operational continuity |
| `conversation_lead_data` | **Retained — unlinked** | Stays with the conversation; `prospect` JSONB may contain name/nationality — see §5 |
| `audit_log` | **Anonymised, not deleted** | Immigration platform has a legitimate legal basis to retain audit records; see §3 |

---

## Step-by-Step Deletion Flow

### Step 1 — Verify the request

Confirm the requestor's identity before acting. Accepted verification methods:
- Authenticated session (Firebase UID matches the requested `user_id`)
- Email confirmation to the address on record

Log the verified request to `audit_log` before any deletion begins:
```sql
INSERT INTO audit_log (actor_type, actor_id, action, entity_type, entity_id, metadata)
VALUES ('user', $user_id, 'deletion_requested', 'user', $user_id::text,
        '{"regulation": "GDPR", "request_received_at": "..."}');
```

### Step 2 — Anonymise audit log rows

Before deleting the `users` row, anonymise any audit log entries that reference this user. Rows must be retained (legal basis: immigration compliance) but must not re-identify the deleted subject.

```sql
UPDATE audit_log
SET actor_id    = NULL,
    actor_email = '[deleted]'
WHERE actor_id = $user_id;

UPDATE audit_log
SET entity_id = '[deleted]'
WHERE entity_type = 'user'
  AND entity_id = $user_id::text;
```

### Step 3 — Unlink conversations

Set `user_id` to NULL on any conversations linked to this user. The conversation record is retained for Chatwoot operational continuity (conversation history, agent notes, lead source tracking). The user is no longer identifiable through it.

```sql
UPDATE conversations
SET user_id = NULL
WHERE user_id = $user_id;
```

### Step 4 — Delete the users row (cascade)

A single DELETE cascades through all child tables via the FK relationships defined in the schema:

```sql
DELETE FROM users WHERE id = $user_id;
```

This cascade removes (in dependency order):
`user_profiles` → `user_channels` → `user_platform_access` → `user_chatwoot_links` → `user_services` → (`user_service_details`, `user_service_documents` → `document_submissions`, `user_service_steps`) → `ai_document_reviews` → `payments` → `notifications` → `user_roles`

### Step 5 — Delete physical files from storage

`document_submissions.file_path` records are deleted by the cascade, but the actual files in the storage bucket (S3/GCS) are not touched by the database. A post-deletion job must:

1. Collect all `file_path` values before the cascade runs (or log them to a deletion queue beforehand).
2. Issue `DELETE` calls against the storage bucket for each path.
3. Log completion to `audit_log` with `action = 'storage_files_deleted'`.

### Step 6 — Delete Chatwoot contact (optional)

If the user has a linked Chatwoot contact (`user_chatwoot_links`), the Chatwoot contact record may also need deletion via the Chatwoot API depending on whether the contact holds personal data that is not otherwise covered by the database cascade. This is a manual or API-triggered step — Chatwoot data is not in the PostgreSQL schema.

### Step 7 — Log completion and notify the user

```sql
INSERT INTO audit_log (actor_type, action, entity_type, entity_id, metadata)
VALUES ('system', 'deletion_completed', 'user', '[deleted]',
        '{"regulation": "GDPR", "completed_at": "..."}');
```

Send a confirmation to the user's last known email address (captured before cascade) that the deletion is complete.

---

## Audit Log Retention Justification

Both GDPR (Article 17(3)(b)) and PDPA (Section 33(4)) allow retention of personal data where necessary for compliance with a legal obligation or for the establishment, exercise, or defence of legal claims.

For an immigration platform:
- Visa application history may be required by Thai immigration authorities.
- Document review history may be needed if a visa decision is appealed.
- Payment records may be subject to Thai tax retention requirements (5 years).

On this basis, audit log rows are anonymised (personal identifiers removed) rather than deleted. The event record (what happened, when, to which service) is retained; the link to the individual is severed.

**This assumption requires a legal review.** If counsel determines no legitimate basis exists, the cascade must extend to audit log rows. See `15_tradeoffs.md` Q8.

---

## GDPR vs. PDPA: Key Differences

| Aspect | GDPR | PDPA |
|---|---|---|
| Response deadline | 30 days (extendable to 90 with notice) | 30 days |
| Breach notification | 72 hours to supervisory authority (DPA) | 72 hours to PDPC (Personal Data Protection Committee) |
| Cross-border transfers | Adequacy decision or SCCs required | Requires consent or approved safeguards |
| Consent withdrawal | Must stop processing within reasonable time | Must stop processing immediately |
| Regulator | EU member state DPA | Thai PDPC |

For ISSA's operational context (Bangkok-based, handling EU/EEA residents):
- A deletion request from an EU resident triggers GDPR obligations.
- All deletion requests also trigger PDPA obligations regardless of the user's nationality.
- The deletion workflow above satisfies both — the differences are in **who you notify** and **when**, not in what data you delete.

---

## conversation_lead_data — Residual PII Risk

`conversation_lead_data.prospect` is a JSONB object that may contain `name`, `nationality`, and `location` captured during the sales conversation. Because `conversation_lead_data` is linked to `conversations` (not `users`), it is not cascade-deleted when the user account is removed.

Two options:
1. **Nullify the `prospect` field** on conversations where `user_id` matched the deleted user — preserves the CRM record but removes the personal fields.
2. **Delete the `conversation_lead_data` row** entirely — loses the lead qualification history.

Option 1 is the safer default. The SQL:
```sql
UPDATE conversation_lead_data
SET prospect = '{}'
WHERE conversation_id IN (
    SELECT id FROM conversations WHERE user_id = $user_id
);
```

This should run **before** the `conversations.user_id` is set to NULL in Step 3.
