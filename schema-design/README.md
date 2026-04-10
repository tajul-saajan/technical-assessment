# ISSA Compass — Unified PostgreSQL Schema Design

**Candidate:** Tajul Islam  
**Submitted to:** aaron@issacompass.com  
**CC:** recruiting.team@issacompass.com

---

## Overview

ISSA Compass currently operates across three disconnected data stores:

| Store | Collection/Table | Purpose |
|---|---|---|
| Firestore | `issa-staging-standard-accounts` | Client profiles, documents, visa progress |
| Firestore | `ai-doc-review` | AI document assessment history |
| PostgreSQL | `public.conversations` | Chatwoot support threads + CRM leads |

This schema consolidates all three into a single PostgreSQL database, preserving the data they contain while fixing known quality issues and filling the documented gaps (payments, audit, access control, notifications).

---

## How to Read This Directory

Run the SQL files **in order** — each file depends on tables defined in earlier files.

| File | Tables | Notes |
|---|---|---|
| `01_core_identity.sql` | users, user_profiles, user_channels, user_platform_access, user_chatwoot_links | Start here |
| `02_staff.sql` | staff_users | Required by documents, conversations |
| `03_service_types.sql` | service_types | Registry — run before user_services |
| `04_user_services.sql` | user_services, user_service_details | Central junction table |
| `05_documents.sql` | document_types, user_service_documents, document_submissions, document_reviews, ai_document_reviews | |
| `06_workflow_steps.sql` | workflow_step_definitions, user_service_steps | |
| `07_conversations.sql` | social_contacts, conversations, tags, conversation_tags, conversation_lead_data | |
| `08_payments.sql` | payments | |
| `09_notifications.sql` | notifications | |
| `10_access_control.sql` | roles, user_roles | |
| `11_audit_log.sql` | audit_log | Append-only, no FKs |
| `12_design_decisions.md` | — | Rationale for every key decision |
| `13_data_quality_fixes.md` | — | The 5 data quality issues addressed |
| `14_migration_strategy.md` | — | 5-phase migration from Firestore + Chatwoot |
| `15_tradeoffs.md` | — | Open questions for team validation |
| `16_data_subject_deletion.md` | — | GDPR + PDPA deletion workflow with SQL |

---

## Entity Relationship Diagram

```
users ──────────────────────────────────────────────────────────────────────┐
  │                                                                          │
  ├─── user_profiles          (1:1 profile info)                            │
  ├─── user_channels          (1:N email, whatsapp, line)                   │
  ├─── user_platform_access   (1:1 web/ios flags)                           │
  ├─── user_roles             (N:M roles)                                   │
  ├─── user_chatwoot_links    (1:1 Chatwoot contact link)                   │
  ├─── notifications          (1:N)                                         │
  ├─── ai_document_reviews    (1:N, intentional separate boundary)          │
  └─── user_services  ────────────────────────────────────────────────────┐ │
         │  (N:M via junction; one user can have DTV + 90day + work permit) │ │
         │                                                                  │ │
         ├─── user_service_details     (1:1 JSONB service-specific fields)  │ │
         ├─── user_service_steps       (1:N workflow milestones)            │ │
         ├─── payments                 (1:N Stripe records)                 │ │
         └─── user_service_documents ─────────────────────────────────────┘ │
                │  (one record per doc type per service)                      │
                ├─── document_submissions  (1:N each upload event)           │
                └─── document_reviews      (1:N staff review history)        │
                                                                              │
social_contacts                                                               │
  └─── conversations ──────── (user_id FK, nullable) ─────────────────────┘
         ├─── conversation_lead_data  (1:1 CRM qualification — prospect JSONB)
         └─── conversation_tags       (N:M → tags)

Reference tables: service_types, document_types, workflow_step_definitions,
                  roles, staff_users
Audit: audit_log (append-only, no FKs — rows survive entity deletion)
```

---

## Access Patterns by Consumer

| Consumer | Primary tables | Key indexes used |
|---|---|---|
| Client Mobile/Web | `user_services`, `user_service_documents`, `document_submissions`, `notifications` | `idx_user_services_user_id`, `idx_user_services_active` |
| Legal Dashboard | `user_services`, `document_reviews`, `ai_document_reviews`, `user_profiles` | `idx_doc_reviews_reviewer`, `idx_ai_reviews_doc_type` |
| Communications Dashboard | `conversations`, `social_contacts`, `conversation_lead_data`, `conversation_tags` | `idx_conversations_channel_src`, `idx_conversation_tags_tag` |
| AI Coordination Layer | `ai_document_reviews`, `user_service_documents`, `document_submissions` | `idx_doc_submissions_path`, `idx_ai_reviews_time` |
| Scheduled Jobs | `user_services`, `user_service_steps`, `payments`, `audit_log` | `idx_user_services_status`, `idx_audit_log_occurred` |
