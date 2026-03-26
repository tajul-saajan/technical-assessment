# AI Doc Review

**Collection:** `ai-doc-review`

An AI Doc Review record stores the history of automated document assessments run against a user's uploaded files. Each record is keyed by `user_id` and contains one sub-map per document type, with each entry in that sub-map representing a single AI review run triggered at a specific point in time.

The record either has rich review data (`exists: true`, `data` populated) or is a stub indicating the user has no AI review history yet (`exists: false`, `data: null`).

---

## Top-Level Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `user_id` | `string` | ✅ | Firebase Auth UID. Foreign key into `standard_accounts`. |
| `exists` | `boolean` | ✅ | `true` if at least one AI review has been run for this user. `false` if the record is a placeholder with no review history — `data` will be `null` in that case. |
| `data` | `object \| null` | ⚠️ optional | Map of document type IDs to their **Review History** maps. `null` when `exists` is `false`. |

---

## `data` Object

A map where each key is a document type ID string (e.g. `"dtv_passport"`, `"dtv_financial-assets"`, `"dtv_address"`). The same doc type IDs found in `standard_accounts.docs` are used here.

Each value is a **Review History** map for that document type.

### Review History Map

A map where each key is an **ISO 8601 timestamp string** representing when the AI review was triggered. Each value is a **Review Run** object. Multiple runs per document type are common — they represent successive upload attempts by the client.

> **Key design note:** The timestamp is the map key, not a nested field. This means you must iterate over the keys to get the time of each run. Runs are not guaranteed to be in insertion order.

### Review Run Object

| Field | Type | Required | Description |
|---|---|---|---|
| `files` | `array<string>` | ✅ | Storage paths of the files that were reviewed in this run. Each string is a path relative to the storage bucket root (same format as `standard_accounts.docs[*].files[*].path`). |
| `result` | `string` | ✅ | AI assessment outcome. Observed values: `"approved"`, `"rejected"`, `"unsure"`. |
| `feedback` | `string` | ✅ | Human-readable AI explanation of the result. Always present and non-empty. Provides specific pass/fail reasoning for the client and staff. |
| `timestamp` | `string (ISO 8601)` | ✅ | Timestamp of this review run. Mirrors the parent map key — useful for deserialization into objects. |

#### `result` Values

| Value | Meaning |
|---|---|
| `"approved"` | Files meet all requirements for this document type. |
| `"rejected"` | Files fail one or more hard requirements. Specific reason given in `feedback`. |
| `"unsure"` | AI could not make a definitive determination. Requires human review or client resubmission with clarification. |

---

## Notes on Data Patterns

- **Multiple runs are expected.** A client may upload and get rejected several times before achieving `"approved"`. The full history is preserved.
- **File paths are reused across entities.** The same path strings appear in both `standard_accounts.docs[*].files` and in `ai_doc_review.data[docId][timestamp].files`. This allows cross-referencing which AI run corresponds to which upload event.
- **Stubs are common.** Most sampled users have `exists: false` — AI review is only triggered for certain document types or after specific workflow steps.
- **No guarantee of a 1:1 mapping** between AI review runs and staff review history entries in `standard_accounts`. The AI runs asynchronously on upload; staff review happens separately.

---

## Example

```json
{
  "user_id": "hj1nWJbbAehWOehW8vux9YYDQ9a2",
  "exists": true,
  "data": {
    "dtv_passport": {
      "2025-12-08T16:08:47.983742+00:00": {
        "files": [
          "web/hj1nWJbbAehWOehW8vux9YYDQ9a2/dtv_passport/czech_passport_6c5680.jpg",
          "web/hj1nWJbbAehWOehW8vux9YYDQ9a2/dtv_passport/israeli_passport_7845e6.jpg"
        ],
        "result": "unsure",
        "feedback": "Two passport biodata pages from different countries were uploaded. Please upload only one passport biodata page (the page with your photo) ensuring the full page is visible with no glare.",
        "timestamp": "2025-12-08T16:08:47.983742+00:00"
      },
      "2025-12-11T07:57:18.024526+00:00": {
        "files": [
          "web/hj1nWJbbAehWOehW8vux9YYDQ9a2/dtv_passport/czech_passport_1_277626.jpg"
        ],
        "result": "approved",
        "feedback": "The passport biodata page is shown in full with clear edges, no glare, and all personal data is legible. Expiry date is 18.07.2035 — roughly 9 years and 7 months of validity remaining. You may proceed with your visa application.",
        "timestamp": "2025-12-11T07:57:18.024526+00:00"
      }
    },
    "dtv_financial-assets": {
      "2026-02-09T05:06:32.633448+00:00": {
        "files": [
          "hj1nWJbbAehWOehW8vux9YYDQ9a2/hj1nWJbbAehWOehW8vux9YYDQ9a2/bank_statement.pdf"
        ],
        "result": "rejected",
        "feedback": "Only a single month of transaction history is visible. Please upload six consecutive months of official personal bank statements (PDF), with the account holder's name and account number clearly visible and an ending balance of at least 500,000 THB per owner.",
        "timestamp": "2026-02-09T05:06:32.633448+00:00"
      },
      "2026-02-11T05:47:56.641048+00:00": {
        "files": [
          "hj1nWJbbAehWOehW8vux9YYDQ9a2/hj1nWJbbAehWOehW8vux9YYDQ9a2/mother_account_confirmation.pdf"
        ],
        "result": "rejected",
        "feedback": "This file does not provide six full months of transaction history with a clearly disclosed ending balance of 500,000 THB or more. Please upload official personal bank statements (six consecutive months) showing complete transactions and the ending balance.",
        "timestamp": "2026-02-11T05:47:56.641048+00:00"
      }
    },
    "dtv_passport-photo": {
      "2025-12-08T16:13:52.870562+00:00": {
        "files": [
          "web/hj1nWJbbAehWOehW8vux9YYDQ9a2/dtv_passport-photo/my_picture_1059c3.jpg"
        ],
        "result": "rejected",
        "feedback": "Your photo appears to be a photo of a printed photo (not an original digital image). Please capture and upload a new high-resolution digital photo directly with your camera, on a plain white/neutral background, facing straight with a neutral expression.",
        "timestamp": "2025-12-08T16:13:52.870562+00:00"
      },
      "2025-12-09T09:48:21.503707+00:00": {
        "files": [
          "web/hj1nWJbbAehWOehW8vux9YYDQ9a2/dtv_passport-photo/my_photo_7d3caf.jpg"
        ],
        "result": "approved",
        "feedback": "✓ Your photo has been successfully verified and meets visa/passport application requirements. You may proceed with your application.",
        "timestamp": "2025-12-09T09:48:21.503707+00:00"
      }
    },
    "dtv_address": {
      "2026-02-06T15:09:28.992738+00:00": {
        "files": [
          "hj1nWJbbAehWOehW8vux9YYDQ9a2/hj1nWJbbAehWOehW8vux9YYDQ9a2/vietnam_address_.pdf"
        ],
        "result": "rejected",
        "feedback": "The hotel booking does not show a total stay of at least 5 working days. Please provide additional bookings or extend the current stay to reach a minimum of 5 working days.",
        "timestamp": "2026-02-06T15:09:28.992738+00:00"
      },
      "2026-02-11T04:13:37.579638+00:00": {
        "files": [
          "hj1nWJbbAehWOehW8vux9YYDQ9a2/hj1nWJbbAehWOehW8vux9YYDQ9a2/Hotel_in_Hanoi.pdf"
        ],
        "result": "approved",
        "feedback": "The Hanoi hotel booking shows a stay from March 22, 2026 to April 14, 2026, totaling more than 5 working days, and clearly lists the full address in Vietnam. ✓ Your address proof has been verified.",
        "timestamp": "2026-02-11T04:13:37.579638+00:00"
      }
    }
  }
}
```

### Stub Example (no review history)

```json
{
  "user_id": "LziK06ayKDf2XW4MxdabSRHerLi1",
  "exists": false,
  "data": null
}
```
