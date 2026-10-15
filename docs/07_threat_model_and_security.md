# Comprehensive Security Design Note & STRIDE Threat Model
**Project:** Talentra — Job Search & Demand Management Platform  
**Organization:** Northbridge Workforce Systems  
**Milestone:** Phase 5, Milestone 22 (B75, B76, B77, B78, B81)  
**Target Engine:** PostgreSQL 17.5  

---

## 1. PII & Sensitive Data Classification Matrix (B75, B76, B77)

In strict compliance with **Rule Group 6** and **Milestone 22**, all data attributes across all 13 modules are categorized into four security classifications: **Public**, **Internal**, **Personal**, and **Sensitive**.

| Domain / Module | Attributes | Classification | Security Control & Technical Strategy |
| :--- | :--- | :---: | :--- |
| **Administration (B75)** | `user_credential.password_hash` | **Sensitive** | Argon2id salted hashing (`memory_cost = 64MB`, `iterations = 3`, `parallelism = 4`). Cleartext passwords never written to disk or logs. |
| **Administration (B75)** | `users.email`, `users.phone_number` | **Personal** | Stored in UTF-8. Masked dynamically for non-owners via `vw_candidate_profile_masked`. Unique index on lowercase email. |
| **Organisation & Accounts (B75)** | `organisation_tax_identifier.identifier_value` | **Sensitive** | Encrypted using PostgreSQL `pgcrypto` AES-256 with key rotated from external KMS; masked in views showing only first 2 and last 3 characters (`vw_organisation_tax_masked`). |
| **Gig Marketplace (B75)** | `gig_external_earning.actual_total_earning_amount` | **Internal** | Accessible only by the gig worker and the contracting employer. Revoked from general search queries. |
| **Gig Marketplace (B75)** | `gig_requester_worker_list` (Blacklist) | **Internal** | Strictly private to requester organization. Hidden from workers to prevent dispute escalation. |
| **Licences & Sessions (B76)** | `user_session.session_token_hash` | **Sensitive** | SHA-256 hash of random 256-bit entropy bearer token. Token revoked immediately on logout or device limit enforcement. |
| **Licences & Sessions (B76)** | `user_device.device_fingerprint_hash` | **Internal** | Hardware hash stored for fraud detection and concurrent session limits. |
| **Subscriptions & Wallet (B76)** | `payment_order.gateway_transaction_reference` | **Sensitive** | Pseudonymized reference token issued by Stripe/Razorpay. No raw credit card, CVV, or bank numbers stored on premises (PCI-DSS Level 1 compliance by design). |
| **Subscriptions & Wallet (B76)** | `wallet_ledger.credit_delta`, `wallet.credit_balance` | **Internal** | Append-only financial ledger. Write-only permissions for background billing services; read restricted to tenant account admins. |
| **Profile Downloads (B76)** | `profile_download_history` | **Internal / Personal** | Append-only audit logging actor recruiter ID, target candidate ID, and credit deduction. |
| **Notifications & Community (B77)**| `notification_delivery.recipient_user_id` | **Personal** | Contact details masked in logs; notification payloads purged after 30-day retention window. |
| **Shared Security (B77)** | `user_block_list`, `company_block_list` | **Personal** | Candidate-controlled privacy boundary. Enforced by PostgreSQL Row Level Security (RLS) to invisibly exclude blocked candidates. |

---

## 2. STRIDE Threat Model & Applied Controls (B78)

We conducted an architectural STRIDE analysis on the Talentra database layer:

### 2.1 Spoofing Identity
* **Threat:** Malicious actor assumes recruiter identity to scrape candidate resumes or post fraudulent job requirements.
* **Database Controls:**
  * Strict session token validation with device binding (`user_device_id`).
  * Expired sessions invalidated automatically by trigger `fn_enforce_concurrent_device_session_limit()`.
  * Multi-factor authentication (MFA) credentials stored in `user_credential` with `locked_until` backoff on repeated failed attempts.

### 2.2 Tampering with Data
* **Threat:** Rogue employee or compromised application connection updates financial balances in `wallet` or deletes audit entries in `audit_log`.
* **Database Controls:**
  * Strict `REVOKE UPDATE, DELETE ON audit_log, wallet_ledger, profile_download_history FROM application_role;`.
  * Hardware-enforced PostgreSQL trigger `fn_prevent_audit_log_tamper()` throws hard exception if superuser or background process attempts an update or delete.
  * GiST exclusion constraints (`ex_gig_assignment_no_overlap`, `ex_subscription_period_no_overlap`) physically reject overlapping time windows at engine level.

### 2.3 Repudiation
* **Threat:** Recruiter disputes downloading 500 candidate profiles or employer denies canceling a gig assignment.
* **Database Controls:**
  * Immutable `profile_download_history` captures actor, candidate, timestamp, IP address, and credit deduction.
  * Centralized append-only `audit_log` records state diffs (`old_state`, `new_state`, `diff_payload`) on every sensitive status change.

### 2.4 Information Disclosure
* **Threat:** Recruiter from Company A queries database and views proprietary job applications or candidate pipelines of Company B.
* **Database Controls:**
  * **PostgreSQL Row Level Security (RLS):** Table `job_requirement` and `candidate_application` enforce policy `organisation_id = current_setting('talentra.current_org_id')::UUID`.
  * Candidate Blocklists: RLS policy on `candidate_profile` filters out candidate profiles if the viewing recruiter's organization is blocked in `company_block_list`.

### 2.5 Denial of Service (DoS)
* **Threat:** Malicious concurrent logins consume database connection pool or trigger massive unindexed table scans.
* **Database Controls:**
  * Connection limits enforced via session quotas (`max_devices_per_user` check).
  * Runaway queries bounded via `statement_timeout = '15s'` in production configuration.
  * High-volume partitioned tables (`candidate_application`, `notification_delivery`) prevent table lock saturation during large batch insertions.

### 2.6 Elevation of Privilege
* **Threat:** Standard candidate or recruiter modifies their role to `super_admin` in `user_role`.
* **Database Controls:**
  * Role assignment guarded by foreign key constraint and restricted administrative stored procedures (`sp_assign_user_role()`).
  * `is_system_role` flag protects core administrative roles from dynamic alteration.

---

## 3. Security Design Note & Defense Summary (B81)

The Talentra security architecture departs from traditional "application-only security" by embedding defense-in-depth directly into PostgreSQL:
1. **Engine-Level RLS:** Zero reliance on application developers remembering `WHERE organisation_id = ?`. Queries execute with database tenant context.
2. **Immutable Ledgers:** Auditing and financial accounting are mathematically append-only.
3. **Automated Session Revocation:** Device concurrency is governed at the session boundary with automated termination of stale devices.
