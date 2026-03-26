# Standard Account

**Collection:** `issa-staging-standard-accounts`

A Standard Account represents a client's application profile. It tracks identity, platform access, document submissions, visa application progress, and internal staff notes. Accounts can exist in a minimal onboarding state (few fields populated) or a fully active state with rich document history.

---

## Top-Level Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` | ✅ | Firebase Auth UID. Serves as the primary document key. |
| `user_id` | `string` | ⚠️ optional | Same as `id` — present on some accounts, absent on others. Treat as redundant when set; do not rely on its presence. |
| `exists` | `boolean` | ✅ | Always `true` for documents that have been retrieved; acts as a sentinel to confirm the record exists in Firestore. |
| `request_id` | `string \| null` | ⚠️ optional | UUID (or Firebase UID mirror) for the active visa application sub-document. `null` or absent if no application has been started. |
| `tracking_code` | `string \| null` | ⚠️ optional | Short alphanumeric code (e.g. `6TQWTA0W`) used for client-facing tracking. `null` if not yet assigned. |
| `account_type` | `string` | ✅ | Platform the account was created on. Observed values: `"web"`, `"ios"`. |
| `visa_type` | `string \| null` | ⚠️ optional | The visa product the client is applying for. Observed value: `"dtv"` (Digital Nomad Visa). `null` if not yet selected. |
| `expo_token` | `string \| null` | ⚠️ optional | Expo push notification token for iOS clients (e.g. `ExponentPushToken[...]`). Always `null` for web accounts. |
| `created` | `string (ISO 8601)` | ✅ | Account creation timestamp with timezone offset. |
| `last_update_user` | `string (ISO 8601) \| null` | ⚠️ optional | Timestamp of the most recent user-side update. |
| `last_update_issa` | `string (ISO 8601) \| null` | ⚠️ optional | Timestamp of the most recent staff-side update. `null` if no staff action has occurred. |
| `urgent_popups` | `array` | ✅ | List of urgent notification objects to surface in the client UI. Typically an empty array `[]`. |
| `messages` | `object` | ✅ | Key-value map of in-app messages. Empty object `{}` when none exist. Structure of values not observed in this sample. |
| `notes` | `object` | ✅ | Staff-facing notes object. Either `{}` (empty) or `{ text: string, status: string }` with `status` values like `"read"`. |
| `shared_docs` | `object` | ✅ | Documents shared with the client (e.g. templates). Empty object `{}` in all observed records. |
| `payment` | `object` | ✅ | Payment information. Always `{}` in this sample — structure not yet observed. |

---

## `connected_platforms` Object

Indicates which platforms the client has authenticated on.

| Field | Type | Required | Description |
|---|---|---|---|
| `web` | `boolean` | ✅ | Whether the client has a web session. |
| `ios` | `boolean` | ✅ | Whether the client has an iOS app session. |

---

## `channels` Object

Communication channel details for the client.

| Field | Type | Required | Description |
|---|---|---|---|
| `email` | `string \| null` | ⚠️ optional | Primary contact email (often matches `info.email`). |
| `personal_email` | `string \| null` | ⚠️ optional | Secondary personal email address. |
| `whatsapp` | `string \| null` | ⚠️ optional | WhatsApp contact identifier. |
| `line` | `string \| null` | ⚠️ optional | LINE messaging identifier. |
| `channel_preference` | `string \| null` | ⚠️ optional | Client's preferred communication channel. Not populated in this sample. |

---

## `docs` Object

A map of document type IDs to **Document Entry** objects. Keys are string identifiers such as `"dtv_passport"`, `"dtv_financial-assets"`, `"examplesofworkselfemployed"`. The map is empty (`{}`) if the client has not yet uploaded documents.

Observed doc IDs include: `dtv_stamps`, `dtv_accommodation`, `dtv_resume-selfemploy`, `dtv_passport`, `dtv_passport-photo`, `dtv_company-affidavit`, `dtv_financial-assets`, `dtv_address`, `dtv_proof-company-income`, `dtv_website-deck`, `dtv_other`, `examplesofworkselfemployed`.

### Document Entry Object

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` | ✅ | Matches the map key (e.g. `"dtv_passport"`). |
| `status` | `string` | ✅ | Review outcome. Observed values: `"approved"`, `"need_changes"`, `"pending"`. |
| `files` | `array<FileEntry>` | ✅ | Uploaded files for this document type. See File Entry below. |
| `history` | `array<HistoryEntry>` | ✅ | Ordered log of staff review actions. Empty array if no actions yet. |
| `feedback` | `string \| null` | ⚠️ optional | Staff feedback text shown to the client. Can be `null`, `""`, or a populated string. |
| `changes` | `string \| null` | ⚠️ optional | Change request message sent to the client. Can be `null`, `""`, or a populated string. |
| `title` | `string \| null` | ⚠️ optional | Human-readable display name override for this document type. `null` when the default label is used. |
| `timestamp` | `string (ISO 8601) \| null` | ⚠️ optional | Timestamp of the most recent file upload event. `null` if not set. |
| `skip` | `boolean \| null` | ⚠️ optional | Whether this document requirement has been waived. Always `null` in observed data. |
| `is_custom` | `boolean \| null` | ⚠️ optional | Marks non-standard doc types added ad-hoc by staff. Always `null` in observed data. |

### File Entry Object

| Field | Type | Required | Description |
|---|---|---|---|
| `path` | `string` | ✅ | Storage path relative to the bucket root. May begin with `web/`, the user UID, or a request UUID. |
| `originalName` | `string` | ✅ | Original filename as provided by the client. |
| `timestamp` | `string (ISO 8601) \| null` | ⚠️ optional | Upload time. Absent on some older records. |

### History Entry Object

| Field | Type | Required | Description |
|---|---|---|---|
| `action` | `string` | ✅ | Review action taken. Observed values: `"approved"`, `"need_changes"`. |
| `user` | `string` | ✅ | Email of the staff member who performed the action. |
| `timestamp` | `string (ISO 8601)` | ✅ | When the action was taken. |
| `data` | `string (JSON) \| null` | ⚠️ optional | JSON-encoded supplementary data. For `"need_changes"` actions, contains `{"changes": "..."}`. `null` for approvals. |

---

## `internal` Object

Staff-facing linkage to the AI review system (Chatwoot / ISSA AI).

| Field | Type | Required | Description |
|---|---|---|---|
| `issa_ai_id` | `string \| null` | ⚠️ optional | The linked Chatwoot contact ID as a string. `null` if not linked. |
| `issa_ai_link_time` | `string (ISO 8601) \| null` | ⚠️ optional | When the AI linkage was created. `null` if not linked. |
| `pending_notes` | `object` | ⚠️ optional | Map of pending internal notes. Empty `{}` when none exist. |

---

## `info` Object

The primary application metadata record. All fields within `info` are optional — a minimal account may have most set to `null`.

| Field | Type | Required | Description |
|---|---|---|---|
| `first_name` | `string \| null` | ⚠️ optional | Client's first name. |
| `last_name` | `string \| null` | ⚠️ optional | Client's last name. |
| `email` | `string \| null` | ⚠️ optional | Client's email (typically mirrors `channels.email`). |
| `nationality` | `string \| null` | ⚠️ optional | ISO 3166-1 alpha-2 country code (e.g. `"cz"`, `"us"`). |
| `account_status` | `string \| null` | ⚠️ optional | Current application workflow status. Observed values: `"waiting_for_client"`, `null`. |
| `dtv_purpose` | `string \| null` | ⚠️ optional | Reason for the DTV application. Observed values: `"selfemploy"`, `"courses"`. |
| `dtv_package` | `string \| null` | ⚠️ optional | Service package selected. Not populated in this sample. |
| `dtv_submission_country` | `string \| null` | ⚠️ optional | ISO country code where the application will be submitted (e.g. `"VN"`). |
| `dtv_submission_embassy` | `string \| null` | ⚠️ optional | Name of the specific embassy (e.g. `"Hanoi"`). |
| `dtv_submission_date` | `string \| null` | ⚠️ optional | Planned or actual date of submission. |
| `dtv_exit_date` | `string (YYYY-MM-DD) \| null` | ⚠️ optional | Date the client plans to exit Thailand for the submission trip. |
| `dtv_applied_before` | `boolean \| null` | ⚠️ optional | Whether the client has previously applied for a DTV. |
| `dtv_final_decision_date` | `string \| null` | ⚠️ optional | Date of the final embassy decision. |
| `dtv_embassy_interview_date` | `string \| null` | ⚠️ optional | Date of a required embassy interview, if applicable. |
| `has_embassy_interview` | `boolean` | ✅ | Whether an interview has been scheduled. Defaults to `false`. |
| `dtv_count_days_processing` | `number \| null` | ⚠️ optional | Number of days the application has been in processing. |
| `dtv_go_to_submission_country_date` | `string \| null` | ⚠️ optional | Date the client departs to the submission country. |
| `dtv_is_skip_entry_stamp` | `boolean` | ✅ | Whether to skip the entry stamp requirement. Defaults to `false`. |
| `dtv_is_not_in_thailand` | `boolean \| null` | ⚠️ optional | Whether the client is currently outside Thailand. |
| `dtv_need_course` | `boolean \| string \| null` | ⚠️ optional | Whether the client needs to purchase a course. Inconsistently typed — observed as `false`, `null`, and `"true"` (string). |
| `dtv_buy_course` | `string \| null` | ⚠️ optional | Course purchase status or identifier. |
| `dtv_category_tag` | `string \| null` | ⚠️ optional | Internal category tag for the application type. |
| `readiness_status` | `string \| null` | ⚠️ optional | Staff assessment of application readiness. |
| `eligible_for_refund` | `string \| null` | ⚠️ optional | Refund eligibility. Observed values: `"yes_full"`, `null`. |
| `is_ghost` | `boolean` | ✅ | Whether this is a test/ghost account. Defaults to `false`. |
| `issa_assigned` | `string \| null` | ⚠️ optional | Email of the assigned ISSA staff member. |
| `issa_reviewed_by` | `string \| null` | ⚠️ optional | Email of the staff member who completed the review. |
| `referral_code` | `string \| null` | ⚠️ optional | The client's own referral code for sharing. |
| `referral_id` | `string \| null` | ⚠️ optional | ID of the referrer who brought this client in. |
| `client_source` | `string \| null` | ⚠️ optional | Acquisition channel. Observed values: `"client_referral"`, `"instagram"`. |
| `internal_notes` | `string \| null` | ⚠️ optional | Free-text internal notes for staff only. |
| `payment_date` | `string \| null` | ⚠️ optional | Date of payment. |
| `stripe_payment_url` | `string \| null` | ⚠️ optional | Stripe checkout URL for the client. |
| `paid_referrer_date` | `string \| null` | ⚠️ optional | Date the referrer commission was paid. |
| `rejected_timestamp` | `string` | ✅ | Timestamp of rejection, or `""` (empty string) if not rejected. Note: empty string rather than `null`. |
| `consult_date` | `string \| null` | ⚠️ optional | Date of the initial consultation. |
| `ninetydays_last_arrival` | `string \| null` | ⚠️ optional | Date of last entry to Thailand for 90-day reporting. |
| `ninetydays_last_report` | `string \| null` | ⚠️ optional | Date of last 90-day report submission. |
| `ninetydays_in_thailand` | `string \| null` | ⚠️ optional | Whether the client is currently in Thailand for 90-day tracking. |
| `ninetydays_issa_service` | `string \| null` | ⚠️ optional | Whether ISSA handles the client's 90-day reporting. |

---

## `steps` Object

Tracks completion of key workflow steps. Keys are step IDs (e.g. `"dtv_begin"`, `"dtv_upload"`). Empty `{}` if no steps have been completed.

### Step Entry Object

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` | ✅ | Matches the map key. |
| `done` | `string (ISO 8601)` | ✅ | Timestamp when the step was completed. |

---

## Example

```json
{
  "id": "hj1nWJbbAehWOehW8vux9YYDQ9a2",
  "user_id": "hj1nWJbbAehWOehW8vux9YYDQ9a2",
  "exists": true,
  "request_id": "hj1nWJbbAehWOehW8vux9YYDQ9a2",
  "tracking_code": "6TQWTA0W",
  "account_type": "web",
  "visa_type": "dtv",
  "expo_token": null,
  "created": "2025-11-25T12:57:33.442485+00:00",
  "last_update_user": "2026-02-11T14:48:07.789937+00:00",
  "last_update_issa": "2026-02-23T04:48:39.716701+00:00",
  "urgent_popups": [],
  "messages": {},
  "notes": {},
  "shared_docs": {},
  "payment": {},
  "connected_platforms": {
    "web": true,
    "ios": false
  },
  "channels": {
    "email": "abc@gmail.com",
    "personal_email": null,
    "whatsapp": null,
    "line": null,
    "channel_preference": null
  },
  "internal": {
    "issa_ai_id": "351109570",
    "issa_ai_link_time": "2026-02-02T11:11:01.182Z",
    "pending_notes": {}
  },
  "docs": {
    "dtv_passport": {
      "id": "dtv_passport",
      "status": "approved",
      "title": null,
      "feedback": null,
      "changes": "Please provide the photo of your passport where all 4 edges are visible with no glare.",
      "timestamp": "2026-02-04T07:28:50.338200+00:00",
      "skip": null,
      "is_custom": null,
      "files": [
        {
          "path": "hj1nWJbbAehWOehW8vux9YYDQ9a2/dtv_passport/60dd72_Yonatan_Goldstein_passport.jpeg",
          "originalName": "Yonatan_Goldstein_passport.jpeg",
          "timestamp": "2026-02-04T07:28:50.338145+00:00"
        }
      ],
      "history": [
        {
          "action": "approved",
          "user": "team@issacompass.com",
          "timestamp": "2026-02-05T10:13:40.271Z",
          "data": null
        }
      ]
    },
    "dtv_financial-assets": {
      "id": "dtv_financial-assets",
      "status": "need_changes",
      "title": null,
      "feedback": "",
      "changes": "Please provide 6 months of personal bank statements with a minimum ending balance of 500,000 THB.",
      "timestamp": "2026-02-10T05:58:14.196185+00:00",
      "skip": null,
      "is_custom": null,
      "files": [
        {
          "path": "hj1nWJbbAehWOehW8vux9YYDQ9a2/hj1nWJbbAehWOehW8vux9YYDQ9a2/bank_statement.pdf",
          "originalName": "bank_statement.pdf",
          "timestamp": "2026-02-09T05:00:00.000000+00:00"
        }
      ],
      "history": [
        {
          "action": "need_changes",
          "user": "team@issacompass.com",
          "timestamp": "2026-02-05T11:37:08.065Z",
          "data": "{\"changes\": \"Please provide 6 months of personal bank statements.\"}"
        }
      ]
    }
  },
  "info": {
    "first_name": "Taylor",
    "last_name": "Swift",
    "email": "abc@gmail.com",
    "nationality": "cz",
    "account_status": "waiting_for_client",
    "dtv_purpose": "selfemploy",
    "dtv_package": null,
    "dtv_submission_country": "VN",
    "dtv_submission_embassy": "Hanoi",
    "dtv_submission_date": null,
    "dtv_exit_date": "2026-03-07",
    "dtv_applied_before": null,
    "dtv_final_decision_date": null,
    "dtv_embassy_interview_date": null,
    "has_embassy_interview": false,
    "dtv_is_skip_entry_stamp": false,
    "dtv_is_not_in_thailand": null,
    "dtv_need_course": false,
    "dtv_buy_course": "",
    "dtv_count_days_processing": null,
    "dtv_go_to_submission_country_date": null,
    "dtv_category_tag": null,
    "readiness_status": null,
    "eligible_for_refund": null,
    "is_ghost": false,
    "issa_assigned": null,
    "issa_reviewed_by": "team@issacompass.com",
    "referral_code": "48LFP2JS",
    "referral_id": null,
    "client_source": "client_referral",
    "internal_notes": "court transcription services; application in March 2026",
    "payment_date": null,
    "stripe_payment_url": null,
    "paid_referrer_date": null,
    "rejected_timestamp": "",
    "consult_date": null,
    "ninetydays_last_arrival": null,
    "ninetydays_last_report": null,
    "ninetydays_in_thailand": null,
    "ninetydays_issa_service": null
  },
  "steps": {
    "dtv_begin": {
      "id": "dtv_begin",
      "done": "2025-11-25T12:57:33.442485+00:00"
    },
    "dtv_upload": {
      "id": "dtv_upload",
      "done": "2026-02-11T12:53:05.409Z"
    }
  }
}
```
