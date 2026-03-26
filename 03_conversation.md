# Conversation

**Table:** `public.conversations`

A Conversation represents a single customer support thread in the Chatwoot-based messaging platform. Conversations originate from various inbound channels (Instagram, TikTok Business, WhatsApp, etc.) and can be assigned to staff agents. They are enriched with CRM-style qualification fields that capture what is known about the lead or client at the time of the conversation.

Conversations are not directly linked to a `standard_account` by a foreign key in the record itself — the link is made through `standard_accounts.internal.issa_ai_id`, which stores the Chatwoot contact ID.

---

## Core Identity & Channel Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `integer` | ✅ | Auto-incremented primary key for the conversation. |
| `contact_id` | `integer` | ✅ | Chatwoot contact ID for the person who initiated the conversation. |
| `contact_name` | `string` | ✅ | Display name of the contact. May be auto-generated (e.g. `"Contact 1767933850049"`) when no real name is known. |
| `channel_id` | `integer` | ✅ | Internal ID of the channel (inbox) this conversation belongs to. |
| `channel_name` | `string` | ✅ | Human-readable channel name (e.g. `"Instagram (2)"`, `"TikTok Business messaging"`). |
| `channel_source` | `string` | ✅ | Normalized source identifier. Observed values: `"tiktok_business"`, `"instagram"`. |
| `channel_meta` | `object` | ✅ | Channel-specific metadata. Structure varies by `channel_source`. See below. |
| `ai_active` | `boolean` | ✅ | Whether the AI assistant is currently active on this conversation. |

---

## Contact Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `contact_phone` | `string` | ✅ | Contact's phone number. Often `""` (empty string) when unknown — not `null`. |
| `contact_email` | `string` | ✅ | Contact's email. Often `""` when unknown. |
| `contact_language` | `string` | ✅ | Contact's detected or declared language. Often `""`. |
| `contact_profile_pic` | `string` | ✅ | URL to the contact's profile picture. `""` when unavailable (TikTok). Full CDN URL when available (Instagram). |
| `contact_country_code` | `string` | ✅ | ISO country code of the contact. Often `""` when unknown. |
| `contact_status` | `string` | ✅ | Contact-level status in Chatwoot. Observed value: `"closed"`. |

> **Note:** Several contact string fields use `""` (empty string) rather than `null` when data is absent. Treat empty strings as semantically equivalent to null for these fields.

---

## Assignment Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `assignee_id` | `integer` | ✅ | Chatwoot agent ID of the assigned staff member. `0` when unassigned. |
| `assignee_name` | `string` | ✅ | Display name of the assigned agent. `"Unassigned"` when `assignee_id` is `0`. |
| `assignee_email` | `string` | ✅ | Email of the assigned agent. `""` when unassigned. |
| `assignee_team` | `string \| null` | ⚠️ optional | Team the assignee belongs to. `null` in all observed records. |
| `last_assignment_time` | `string (ISO 8601) \| null` | ⚠️ optional | When the conversation was last assigned. `null` in all observed records. |
| `dashboard_assignee_name` | `string \| null` | ⚠️ optional | Assignee name as shown in the internal dashboard. `null` in all observed records. |
| `dashboard_assignee_email` | `string \| null` | ⚠️ optional | Assignee email for the dashboard view. `null` in all observed records. |
| `dashboard_assignee_color` | `string \| null` | ⚠️ optional | Hex color for the assignee's avatar in the dashboard. `null` in all observed records. |

---

## Lifecycle & Timing Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `created_at` | `string (ISO 8601)` | ✅ | When the conversation record was created. |
| `updated_at` | `string (ISO 8601)` | ✅ | When the conversation was last modified. |
| `lifecycle` | `string` | ✅ | CRM lifecycle stage. Observed value: `"New Lead"`. |
| `conversation_opened_at` | `string (ISO 8601) \| null` | ⚠️ optional | When the conversation was opened. `null` if never explicitly opened. Some records show epoch-adjacent timestamps (e.g. `"1970-01-21T18:52:12+07:00"`) indicating a data quality issue — treat these as effectively `null`. |
| `conversation_closed_at` | `string (ISO 8601) \| null` | ⚠️ optional | When the conversation was closed. `null` if still open. Subject to the same epoch anomaly as `conversation_opened_at`. |
| `conversation_opened_by_source` | `string \| null` | ⚠️ optional | System/user that triggered the open event. `null` in all observed records. |
| `conversation_closed_by_source` | `string \| null` | ⚠️ optional | System/user that triggered the close event. `null` in all observed records. |
| `conversation_closed_by_id` | `integer \| null` | ⚠️ optional | Agent ID who closed the conversation. `null` in all observed records. |
| `conversation_closed_by_name` | `string \| null` | ⚠️ optional | Agent name who closed the conversation. `null` in all observed records. |
| `conversation_closed_by_email` | `string \| null` | ⚠️ optional | Agent email who closed the conversation. `null` in all observed records. |
| `first_response_time` | `number \| null` | ⚠️ optional | Time in seconds to the first agent response. `null` in all observed records. |
| `resolution_time` | `number \| null` | ⚠️ optional | Total time in seconds from open to close. `null` in all observed records. |

---

## Message Count Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `incoming_message_count` | `integer` | ✅ | Number of messages received from the contact. |
| `outgoing_message_count` | `integer` | ✅ | Number of messages sent to the contact. |

---

## Classification & CRM Fields

All fields in this group are optional and represent enrichment data collected by agents or the AI.

| Field | Type | Required | Description |
|---|---|---|---|
| `conversation_category` | `string \| null` | ⚠️ optional | Categorization of the conversation topic. Not populated in this sample. |
| `conversation_summary` | `string \| null` | ⚠️ optional | AI or agent-written summary. Not populated in this sample. |
| `notes` | `string \| null` | ⚠️ optional | Free-text notes on the conversation. Not populated in this sample. |
| `locale` | `string` | ✅ | Detected language/locale string. Often `""`. |
| `tags` | `array<string>` | ✅ | List of tag strings applied to the conversation. Common observed values: `"tiktok-ads"`. Empty array `[]` when no tags. |
| `lifecycle_automation_disabled` | `boolean` | ✅ | Whether automatic lifecycle transitions are disabled. Defaults to `false`. |
| `is_waiting_for_legal_review` | `boolean` | ✅ | Whether the conversation is pending a legal review. Defaults to `false`. |
| `blocked` | `boolean` | ✅ | Whether the contact has been blocked. Defaults to `false`. |
| `is_handed_off` | `boolean` | ✅ | Whether the conversation has been handed off from AI to a human agent. Defaults to `false`. |

---

## Lead Qualification Fields

Populated progressively by agents or the AI as more is learned about the lead. All optional.

| Field | Type | Required | Description |
|---|---|---|---|
| `client_has_account` | `boolean \| null` | ⚠️ optional | Whether the lead already has an ISSA account. |
| `client_interested_in` | `string \| null` | ⚠️ optional | The service the client expressed interest in. |
| `client_location` | `string \| null` | ⚠️ optional | Where the client is currently located. |
| `client_name` | `string \| null` | ⚠️ optional | Client's name as captured during the conversation (may differ from `contact_name`). |
| `client_nationality` | `string \| null` | ⚠️ optional | Client's nationality. |
| `client_urgency` | `string \| null` | ⚠️ optional | Urgency level expressed by the client. |
| `client_topics` | `string \| null` | ⚠️ optional | Topics discussed in the conversation. |
| `client_buying_segment` | `string \| null` | ⚠️ optional | Sales segment classification. |
| `client_buying_intent` | `string \| null` | ⚠️ optional | Assessed buying intent of the lead. |
| `current_visa` | `string \| null` | ⚠️ optional | The client's current visa type in Thailand. |
| `dtv_purpose` | `string \| null` | ⚠️ optional | Stated purpose for the DTV application. |
| `dtv_package` | `string \| null` | ⚠️ optional | Package of interest. |
| `current_step` | `string \| null` | ⚠️ optional | Current step in the onboarding workflow. |
| `submission_country` | `string \| null` | ⚠️ optional | Country where the DTV application will be submitted. |
| `applied_before` | `boolean \| null` | ⚠️ optional | Whether the client has applied for a DTV before. |
| `is_emergency` | `boolean \| null` | ⚠️ optional | Whether this is flagged as an emergency case. |
| `is_qualified` | `boolean \| null` | ⚠️ optional | Whether the lead has been qualified by an agent. |
| `source` | `string \| null` | ⚠️ optional | Acquisition source for the lead. |

---

## `channel_meta` Object

Structure varies by `channel_source`.

### TikTok Business (`channel_source: "tiktok_business"`)

```json
{
  "meta": {
    "id": "<encoded_tiktok_user_id>",
    "role": "personal_account",
    "profile_pic": null,
    "display_name": "",
    "conversation_id": "<base64_encoded_conversation_id>"
  }
}
```

| Field | Type | Description |
|---|---|---|
| `meta.id` | `string` | Encoded TikTok user identifier. |
| `meta.role` | `string` | Account role. Observed value: `"personal_account"`. |
| `meta.profile_pic` | `string \| null` | Profile picture URL. Often `null` for TikTok. |
| `meta.display_name` | `string` | Display name. Often `""` for TikTok. |
| `meta.conversation_id` | `string` | Base64-encoded TikTok conversation ID. |

### Instagram (`channel_source: "instagram"`)

```json
{
  "meta": {
    "id": "<instagram_user_id>",
    "name": "Display Name",
    "profile_pic": "<cdn_url>"
  }
}
```

| Field | Type | Description |
|---|---|---|
| `meta.id` | `string` | Numeric Instagram user ID as string. |
| `meta.name` | `string` | Instagram display name. |
| `meta.profile_pic` | `string \| null` | Full CDN URL to profile picture. |

---

## Example (TikTok, unassigned, minimal lead data)

```json
{
  "id": 40048,
  "contact_id": 372372596,
  "contact_name": "Contact 1767933850049",
  "assignee_id": 0,
  "assignee_name": "Unassigned",
  "assignee_email": "",
  "assignee_team": null,
  "last_assignment_time": null,
  "channel_id": 371774,
  "channel_name": "TikTok Business messaging",
  "channel_source": "tiktok_business",
  "channel_meta": {
    "meta": {
      "id": "+dZj8I+kBE8YbqA4ZgsYqDRHMkQCtbQl4YDmpRs2E0ABpsFIlu1DSlwgyhv//7FY",
      "role": "personal_account",
      "profile_pic": null,
      "display_name": "",
      "conversation_id": "u5Nvrc2tBwxtO+xnEUtY8eyVDg=="
    }
  },
  "ai_active": true,
  "created_at": "2026-01-09T11:44:19.348971+07:00",
  "updated_at": "2026-01-09T11:44:14.322000+07:00",
  "contact_phone": "",
  "contact_email": "",
  "contact_language": "",
  "contact_profile_pic": "",
  "contact_country_code": "",
  "contact_status": "closed",
  "lifecycle": "New Lead",
  "lifecycle_automation_disabled": false,
  "conversation_opened_at": null,
  "conversation_closed_at": "2026-01-10T02:11:22+07:00",
  "conversation_opened_by_source": null,
  "conversation_closed_by_source": null,
  "conversation_closed_by_id": null,
  "conversation_closed_by_name": null,
  "conversation_closed_by_email": null,
  "conversation_category": null,
  "conversation_summary": null,
  "first_response_time": null,
  "resolution_time": null,
  "incoming_message_count": 3,
  "outgoing_message_count": 2,
  "is_waiting_for_legal_review": false,
  "blocked": false,
  "is_handed_off": false,
  "notes": null,
  "locale": "",
  "tags": ["tiktok-ads"],
  "client_has_account": null,
  "client_interested_in": null,
  "client_location": null,
  "client_name": null,
  "client_nationality": null,
  "client_urgency": null,
  "client_topics": null,
  "client_buying_segment": null,
  "client_buying_intent": null,
  "current_visa": null,
  "dtv_purpose": null,
  "dtv_package": null,
  "current_step": null,
  "submission_country": null,
  "applied_before": null,
  "is_emergency": null,
  "is_qualified": null,
  "source": null,
  "dashboard_assignee_name": null,
  "dashboard_assignee_email": null,
  "dashboard_assignee_color": null
}
```

## Example (Instagram, assigned agent, partial lead qualification)

```json
{
  "id": 15174,
  "contact_id": 331483811,
  "contact_name": "Chig Kartee",
  "assignee_id": 830545,
  "assignee_name": "Issa Team",
  "assignee_email": "team@issacompass.com",
  "assignee_team": null,
  "last_assignment_time": null,
  "channel_id": 371824,
  "channel_name": "Instagram (2)",
  "channel_source": "instagram",
  "channel_meta": {
    "meta": {
      "id": "1469620664297753",
      "name": "Chig Kartee",
      "profile_pic": "https://cdn.chatapi.net/app/contact/avatar/331483811.jpg"
    }
  },
  "ai_active": true,
  "created_at": "2025-10-14T18:03:52.707999+07:00",
  "updated_at": "2025-10-14T18:10:03.736000+07:00",
  "contact_phone": "",
  "contact_email": "",
  "contact_language": "",
  "contact_profile_pic": "https://cdn.chatapi.net/app/contact/avatar/331483811.jpg",
  "contact_country_code": "",
  "contact_status": "closed",
  "lifecycle": "New Lead",
  "lifecycle_automation_disabled": false,
  "conversation_opened_at": null,
  "conversation_closed_at": null,
  "conversation_opened_by_source": null,
  "conversation_closed_by_source": null,
  "conversation_closed_by_id": null,
  "conversation_closed_by_name": null,
  "conversation_closed_by_email": null,
  "conversation_category": null,
  "conversation_summary": null,
  "first_response_time": null,
  "resolution_time": null,
  "incoming_message_count": 0,
  "outgoing_message_count": 0,
  "is_waiting_for_legal_review": false,
  "blocked": false,
  "is_handed_off": false,
  "notes": null,
  "locale": "",
  "tags": [],
  "client_has_account": null,
  "client_interested_in": null,
  "client_location": null,
  "client_name": null,
  "client_nationality": null,
  "client_urgency": null,
  "client_topics": null,
  "client_buying_segment": null,
  "client_buying_intent": null,
  "current_visa": null,
  "dtv_purpose": null,
  "dtv_package": null,
  "current_step": null,
  "submission_country": null,
  "applied_before": null,
  "is_emergency": null,
  "is_qualified": null,
  "source": null,
  "dashboard_assignee_name": null,
  "dashboard_assignee_email": null,
  "dashboard_assignee_color": null
}
```
