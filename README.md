# Backend Technical Assessment

## Introduction

This assessment covers the backend architecture of an immigration services platform — a multi-tenant, multi-channel system that manages visa applications, compliance tasks, and client communications at scale.

The system coordinates data across three source-of-truth stores, serves five distinct platform consumers, and is expected to grow to 1M+ concurrent users. Understanding the data model, the boundaries between systems, and where coupling exists is essential before proposing changes or extensions.

--- 

## Your Task 📚

Propose a unified, scalable data schema for PostgreSQL that could serve as the single source of truth for this system. The current state is a split across Firestore (accounts, AI review) and PostgreSQL (conversations), with denormalized JSON blobs, flat key maps, and no formal relational structure. Your job is to redesign this as a clean, normalized Postgres schema that:
- Models users, services, documents, reviews, conversations, and all supporting entities as proper relational tables
- Supports multiple concurrent services per user (visas, permits, compliance tasks) with a single extensible structure — not one schema per service type
- Is designed to scale to 50k new users/month and 1M concurrent users, with the indexing and partitioning strategy to match
- Preserves full audit history for documents, staff actions, and AI review runs
- Is queryable by all five platform consumers with proper security to protect data without requiring denormalized copies or application-side joins for common access patterns
- Leaves room for new service types, geographies, AI integrations, and compliance products without requiring schema migrations for each addition

Your deliverable is a proposed schema: table definitions, relationships, key design decisions, and the rationale behind them. You should also identify any tradeoffs you are making and what you would validate with the team before finalizing.

When finished, share the results of your work to aaron@issacompass.com (and cc recruiting.team@issacompass.com).

---

## Overview of the System

Clients use the platform to get help with immigration and compliance work: visa applications, work permits, 90-day reporting, address updates, arrival cards, marriage permits, taxes, and more. They upload documents, receive feedback from staff and AI, and track their progress through each service. Meanwhile, the business team is simultaneously managing client conversations coming in from Instagram, TikTok, WhatsApp, and other channels.

The backend sits at the intersection of all of this — it must keep client state consistent across a mobile app, a web app, an internal legal dashboard, a communications platform, and a set of AI + automation services.

---

## Core Data Entities

### 1. Standard Account (`standard_accounts` collection)

The canonical user record. One document per user, keyed by Firebase Auth UID. This is the source of truth for everything about a client's identity and their active service engagement.

**Key structures inside an account:**

- **`info`** — Personal details, application status, nationality, payment state, referral, and all visa/task-specific metadata fields.
- **`docs`** — A map of document type IDs to uploaded file sets and their review state. Each document entry tracks: uploaded files with storage paths and timestamps, current status (`approved` / `need_changes` / `pending`), staff feedback and change requests, and a full history of every review action taken by staff.
- **`steps`** — Workflow milestone completions (e.g. `dtv_begin`, `dtv_upload`) with timestamps.
- **`channels`** — Communication identifiers (email, WhatsApp, LINE) and channel preference.
- **`internal`** — Linkage to the AI communications system (Chatwoot contact ID and link time). This is how an account is cross-referenced to conversations.
- **`connected_platforms`** — Which client-facing platforms (web, iOS) have authenticated this account.
- **`notes`**, **`shared_docs`**, **`payment`**, **`messages`** — Supporting maps for staff notes, shared templates, payment state, and in-app messages.

**Known data quality issues to be aware of:**

- `user_id` is a redundant mirror of `id` and is not always present.
- `rejected_timestamp` uses `""` (empty string) instead of `null` when not rejected — not consistent with other nullable fields.
- `dtv_need_course` has inconsistent types across records: `false` (boolean), `null`, and `"true"` (string).
- `conversation_opened_at` / `conversation_closed_at` on some conversation records contain epoch-adjacent timestamps (`~1970`) indicating a bug in the upstream Chatwoot event system.

---

### 2. AI Doc Review (`ai_doc_review` collection)

Stores the full history of automated document assessments. Decoupled from the main account to keep AI review history append-only and independently queryable.

**Structure:** Keyed by `user_id`. Each document contains a `data` map, where keys are document type IDs (same IDs as in `standard_accounts.docs`), and each value is a map of **ISO 8601 timestamps → review run objects**.

Each review run records:
- Which files were reviewed (storage path array)
- The AI verdict: `approved`, `rejected`, or `unsure`
- A detailed feedback string explaining the outcome

AI reviews are triggered on upload and can run multiple times per document type as the client resubmits. The full history is preserved — no entries are overwritten. Many users have `exists: false` with `data: null`, indicating the AI review pipeline has not yet been triggered for them.

**Relationship to account docs:** The file paths in AI review runs directly match the paths stored in `standard_accounts.docs[docId].files[*].path`. This is the join key when correlating AI verdicts with staff review history.

---

### 3. Conversations (`public.conversations` table — PostgreSQL)

Represents a single customer support thread originating from a social or messaging channel (Instagram, TikTok Business, WhatsApp, etc.). Managed via Chatwoot.

**Key fields:**

- Channel identity: `channel_source`, `channel_id`, `channel_name`, `channel_meta` (structure varies by source — TikTok and Instagram have different schemas)
- Assignment: `assignee_id`, `assignee_name`, `assignee_email`
- Lifecycle: `lifecycle`, `conversation_opened_at`, `conversation_closed_at`, `contact_status`
- AI state: `ai_active`, `is_handed_off`, `is_waiting_for_legal_review`
- Lead qualification: `client_has_account`, `client_interested_in`, `client_location`, `client_nationality`, `client_urgency`, `client_buying_segment`, `client_buying_intent`, and more
- DTV-specific: `current_visa`, `dtv_purpose`, `dtv_package`, `submission_country`, `current_step`

**Relationship to accounts:** Conversations are linked to accounts via `standard_accounts.internal.issa_ai_id`, which stores the Chatwoot `contact_id`. There is no foreign key on the conversation record itself pointing back to a user account — the join is one-directional from the account side.

---

## Platform Consumers

Five distinct platforms consume this data. Each has different read/write access patterns and sensitivity requirements.

### Client-Facing Mobile + Web App
- Single authenticated user, reads/writes their own account only.
- Primary interactions: document uploads, step progression, viewing doc status and feedback.
- Must never expose data from other accounts. Strict per-user auth scoping required.
- Real-time updates needed: when staff approve/reject a document, the client should see it without polling.

### Internal Legal Dashboard
- Staff-facing. Reads many accounts simultaneously for case management.
- Needs to query across accounts by status, assignee, visa type, submission country, readiness, and date ranges.
- Writes staff review actions back to `standard_accounts.docs[*].history`.
- Requires audit trail — all staff actions should be logged with user and timestamp.

### Internal Communications Dashboard (Chatwoot)
- Business team uses this to manage all inbound social conversations.
- Primary data store is the `conversations` table (PostgreSQL).
- Agents assign, qualify, tag, and close conversations here.
- Cross-links to accounts via `issa_ai_id` to surface client context during conversations.

### AI Coordination Layer
- Reads conversation state to decide when to engage or hand off.
- Triggers document AI review on upload events.
- Writes AI review results to `ai_doc_review`.
- Updates `ai_active` and `is_handed_off` on conversations.
- Reads account `docs` state and `info` fields to personalize responses.
- Must operate without blocking the client-facing request path — all AI work is async.

### Scheduled Jobs
- Batch processes for data audits, lifecycle automation, SLA monitoring, health checks, and referral tracking.
- Read-heavy with targeted writes (e.g. updating `lifecycle_automation_disabled`, sending overdue alerts, computing `dtv_count_days_processing`).
- Must be idempotent — jobs may retry on failure.

---

## Assumptions & Design Constraints

### Multi-Service Accounts
A single user account may have multiple active services simultaneously — a visa application, a 90-day reporting task, and a work permit could all be in progress at once. The current `docs` and `steps` maps are flat and visa-prefixed (e.g. `dtv_passport`, `dtv_begin`). Any schema extension for multi-service support needs to introduce a service/application namespace without breaking existing flat-keyed records.

### Extendable Service Types
New visa products, compliance services, and geographies will be added over time. Document requirements, workflow steps, and info fields will differ per service type. The system should not hard-code service logic into the data layer — service configuration (required docs, steps, validation rules) should be driven by configuration or a registry, not by schema shape.

### Scale Targets
- 50,000 new users per month
- 1,000,000 concurrent users within ~2 years
- Read-heavy workload: most users are reading their own status, not writing
- Write spikes expected during document upload events and staff review sessions

Firestore's document-per-user model scales well horizontally for isolated reads, but cross-account queries (needed by the legal dashboard and jobs) require careful indexing strategy or a separate read model. The PostgreSQL conversations table will need indexing on `contact_id`, `assignee_id`, `channel_source`, `lifecycle`, and `created_at` to support the communications dashboard at scale.

### AI Expansion
The AI layer is expected to take over more of the review and communication workflow over time. The current design separates AI review history (`ai_doc_review`) from the authoritative account state (`standard_accounts.docs`) — this is intentional. The AI produces verdicts; humans (or explicit automation rules) decide when to promote those verdicts into the account record. This boundary should be preserved as AI capabilities expand.

---

## Data Flow Summary

```
Client uploads document
  → File written to storage bucket
  → standard_accounts.docs[docId].files updated
  → AI review triggered async → ai_doc_review entry written
  → Staff notified for human review
  → Staff writes action to standard_accounts.docs[docId].history
  → Client sees updated status in app

Inbound social message (IG / TikTok / WhatsApp)
  → Conversation created in public.conversations
  → AI checks ai_active flag → responds or routes
  → Agent qualifies lead → updates CRM fields on conversation
  → If client has account: link via contact_id → issa_ai_id
  → Conversation closed or handed off

Scheduled job (e.g. SLA audit)
  → Reads accounts with account_status = 'waiting_for_client'
  → Computes days since last update
  → Triggers alert or automation if threshold exceeded
```

---

## What Is NOT Covered Here

The following are known gaps in the current data sample that the assessment should address:

- **Payment records** — Payment state, Stripe integration, and refund logic are not yet represented.
- **Multi-visa / multi-service data model** — The current schema is DTV-centric. Extension to support concurrent services for one user is a primary design challenge.
- **Notification system** — `expo_token` exists for iOS push, but the full notification dispatch pipeline is not modeled.
- **Audit logging** — Staff actions in `docs.history` provide partial audit coverage, but a system-wide audit log for compliance purposes is not present.
- **Access control model** — Role definitions (client, agent, legal staff, admin, AI service account) and their permission boundaries are not formalized in the schema.

---

## File Index

| File | Entity | Description |
|---|---|---|
| `01_standard_account.md` | `standard_accounts` | Full field reference for user account records |
| `02_ai_doc_review.md` | `ai_doc_review` | AI document review history structure |
| `03_conversation.md` | `public.conversations` | Conversation and lead qualification record |
