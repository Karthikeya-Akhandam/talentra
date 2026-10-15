# Enterprise Data Dictionary & Attribute Specification
**Project:** Talentra — Job Search & Demand Management Platform  
**Organization:** Northbridge Workforce Systems  
**Standards:** Rule Group 3 (Standard Domains), Rule Group 5 (Nullability Justifications), Rule Group 6 (Sensitive Data Classification)  
**Target Engine:** PostgreSQL 17.5  

---

## 1. Data Dictionary Standards & Tagging Legend

* **Standard Domains:**
  * `Identifier`: Surrogate key (`UUID` or `BIGINT IDENTITY`).
  * `Person Name`: `VARCHAR(150)` UTF-8.
  * `Email Address`: `VARCHAR(254)` lowercase unique.
  * `Phone Number`: E.164 with separate dial code.
  * `Money`: `DECIMAL(14, 2)` accompanied by `CHAR(3)` currency code.
  * `Date Range / Temporal Window`: `TSTZRANGE` with GiST non-overlap constraints.
* **Sensitivity Classification (Rule Group 6):**
  * `[Public]`: Freely readable without authentication.
  * `[Internal]`: Accessible only by staff or owning tenant organisation.
  * `[Personal]`: Identifies an individual (requires RBAC & audit logging).
  * `[Sensitive]`: Passwords, tax identifiers, payment tokens (requires hashing or `pgcrypto` AES encryption).

---

## 2. Core Entity Data Dictionary

### 2.1 Identity & Accounts (`users`, `user_credential`)
| Table | Column Name | Data Type | Standard Domain | Nullable? | Nullability Justification (Rule 5) | Sensitivity (Rule 6) |
| :--- | :--- | :--- | :--- | :---: | :--- | :---: |
| `users` | `id` | `UUID` | Identifier | NO | Surrogate primary key. | `[Internal]` |
| `users` | `email` | `VARCHAR(254)` | Email Address | NO | Primary account identifier and communication handle. | `[Personal]` |
| `users` | `phone_country_code` | `VARCHAR(10)` | Phone Code | YES | Optional during initial email-based registration. | `[Personal]` |
| `users` | `phone_number` | `VARCHAR(20)` | Phone Number | YES | Optional during initial email-based registration. | `[Personal]` |
| `users` | `user_type_code` | `VARCHAR(30)` | Enumeration | NO | Discriminator for portal persona (candidate, recruiter, etc.). | `[Internal]` |
| `users` | `status_code` | `VARCHAR(30)` | Enumeration | NO | Account lifecycle state. | `[Internal]` |
| `user_credential` | `password_hash` | `VARCHAR(255)`| Free Text | NO | Argon2id hash representation. | `[Sensitive]` |
| `user_credential` | `password_salt` | `VARCHAR(100)`| Free Text | YES | Included within argon2id format; nullable if OAuth SSO used. | `[Sensitive]` |

### 2.2 Candidate Profile Core (`candidate_profile`, `candidate_experience`)
| Table | Column Name | Data Type | Standard Domain | Nullable? | Nullability Justification (Rule 5) | Sensitivity (Rule 6) |
| :--- | :--- | :--- | :--- | :---: | :--- | :---: |
| `candidate_profile` | `id` | `UUID` | Identifier | NO | Surrogate primary key. | `[Internal]` |
| `candidate_profile` | `user_id` | `UUID` | Identifier | NO | Mandatory mapping to `users`. | `[Internal]` |
| `candidate_profile` | `first_name` | `VARCHAR(150)`| Person Name | NO | Mandatory personal identification. | `[Personal]` |
| `candidate_profile` | `last_name` | `VARCHAR(150)`| Person Name | NO | Mandatory personal identification. | `[Personal]` |
| `candidate_profile` | `current_salary_amount` | `DECIMAL(14,2)`| Money | YES | Candidate may choose not to disclose prior compensation. | `[Personal]` |
| `candidate_profile` | `expected_salary_amount`| `DECIMAL(14,2)`| Money | YES | Fresher or gig workers may negotiate per project. | `[Personal]` |
| `candidate_experience` | `end_date` | `DATE` | Date | YES | Null indicates currently active employment (`is_current_job = true`). | `[Personal]` |
| `candidate_experience` | `description` | `TEXT` | Free Text | YES | Optional detailed work description. | `[Personal]` |

### 2.3 Organisation & Recruiter (`organisation`, `organisation_tax_identifier`)
| Table | Column Name | Data Type | Standard Domain | Nullable? | Nullability Justification (Rule 5) | Sensitivity (Rule 6) |
| :--- | :--- | :--- | :--- | :---: | :--- | :---: |
| `organisation` | `id` | `UUID` | Identifier | NO | Surrogate primary key. | `[Internal]` |
| `organisation` | `legal_name` | `VARCHAR(200)`| Person/Org Name| NO | Official registered company name. | `[Public]` |
| `organisation` | `website_url` | `VARCHAR(255)`| Free Text | YES | Optional company website link. | `[Public]` |
| `organisation_tax_identifier`| `identifier_value` | `VARCHAR(100)`| Tax Identifier | NO | Legal business registration number (GSTIN, EIN). | `[Sensitive]` |
| `recruiter_mapping` | `effective_to` | `TIMESTAMPTZ` | Timestamp | YES | Null indicates currently active recruiter mapping. | `[Internal]` |

### 2.4 Job Requirements & Applications (`job_requirement`, `candidate_application`)
| Table | Column Name | Data Type | Standard Domain | Nullable? | Nullability Justification (Rule 5) | Sensitivity (Rule 6) |
| :--- | :--- | :--- | :--- | :---: | :--- | :---: |
| `job_requirement` | `id` | `UUID` | Identifier | NO | Surrogate primary key. | `[Public]` |
| `job_requirement` | `min_salary_amount` | `DECIMAL(14,2)`| Money | YES | Optional if salary is undisclosed / negotiable. | `[Public]` |
| `job_requirement` | `max_salary_amount` | `DECIMAL(14,2)`| Money | YES | Optional if salary is undisclosed / negotiable. | `[Public]` |
| `job_requirement` | `published_at` | `TIMESTAMPTZ` | Timestamp | YES | Null while job is in draft or pending approval state. | `[Internal]` |
| `candidate_application` | `id` | `BIGINT` | Identifier | NO | High-velocity identity sequence. | `[Internal]` |
| `candidate_application` | `resume_version_id` | `BIGINT` | Identifier | YES | Null if candidate applied via standard profile snapshot. | `[Personal]` |
| `candidate_application` | `rejection_reason_code` | `VARCHAR(50)`| Enumeration | YES | Null until application reaches rejected stage. | `[Internal]` |

### 2.5 Gig Marketplace (`gig_worker_profile`, `gig_assignment`)
| Table | Column Name | Data Type | Standard Domain | Nullable? | Nullability Justification (Rule 5) | Sensitivity (Rule 6) |
| :--- | :--- | :--- | :--- | :---: | :--- | :---: |
| `gig_worker_profile` | `hourly_rate_amount`| `DECIMAL(10,2)`| Money | NO | Primary pricing model for project work. | `[Public]` |
| `gig_worker_profile` | `daily_rate_amount` | `DECIMAL(10,2)`| Money | YES | Optional alternative pricing for full-day bookings. | `[Public]` |
| `gig_assignment` | `assignment_window` | `TSTZRANGE` | Date Range | NO | Exact start and end timestamp range (GiST constrained). | `[Internal]` |
| `gig_external_earning` | `reconciled_at` | `TIMESTAMPTZ` | Timestamp | YES | Null until external system webhook confirms payment settlement. | `[Internal]` |

### 2.6 Subscriptions & Wallet (`wallet_ledger`, `subscription_period`)
| Table | Column Name | Data Type | Standard Domain | Nullable? | Nullability Justification (Rule 5) | Sensitivity (Rule 6) |
| :--- | :--- | :--- | :--- | :---: | :--- | :---: |
| `wallet_ledger` | `credit_delta` | `DECIMAL(14,2)`| Money/Credits | NO | Immutable credit delta (+ for credits, - for debits). | `[Internal]` |
| `wallet_ledger` | `parent_reversal_entry_id`| `BIGINT` | Identifier | YES | Null for normal transactions; populated only on reversal entries. | `[Internal]` |
| `subscription_period` | `period_window` | `TSTZRANGE` | Date Range | NO | Active subscription validity window (GiST constrained). | `[Internal]` |
| `profile_download_history` | `downloaded_at` | `TIMESTAMPTZ` | Timestamp | NO | Immutable audit record of candidate profile download. | `[Personal]` |
