# Architectural Decisions & Baseline Specification
**Project:** Talentra — Job Search & Demand Management Platform  
**Organization:** Northbridge Workforce Systems  
**Backlogs Covered:** B1, B2, B3 (Phase 1, Milestone 1)  
**Author / Team:** Solo Engineering Execution  
**Target Engine:** PostgreSQL 17.5  

---

## 1. Database Provider Decision (B1)

### 1.1 Decision
We have selected **PostgreSQL 17** as the database engine for Talentra.

### 1.2 Evaluation & Technical Rationale (PostgreSQL 17 vs. MySQL 8)

| Evaluation Dimension | PostgreSQL 17 | MySQL 8.0 / 8.4 | Strategic Impact on Talentra |
| :--- | :--- | :--- | :--- |
| **Temporal Range Exclusion (`EXCLUDE USING gist`)** | Native support with `btree_gist` extension for `tsrange`, `tstzrange`, `daterange`. Prevents overlapping time windows directly in engine. | Not supported. Requires serializable transactions or application-level advisory locking susceptible to race conditions. | **Critical for Gig & Subscriptions:** Solves requirement B35 (no overlapping gig windows for the same worker) and B47/Rule 10 (non-overlapping subscription periods per license). |
| **Row Level Security (RLS)** | Native, mature RLS policies defined directly on tables with session variables (`SET LOCAL`). | No native RLS. Requires multi-tenant views with security definers or complex application query rewrites. | **Mandatory Actor Rules:** Enforces that recruiters only see their org's jobs, consultants only see open jobs, and blocked candidates are filtered invisibly at DB level. |
| **Declarative Table Partitioning** | Declarative range, list, and hash partitioning with run-time partition pruning. Sub-partitioning supported. | Basic range/list partitioning; less flexible index attachment per partition. | **Scale Requirement:** Handles 10M profiles, 100M applications, and tens of millions of notifications efficiently. |
| **Semi-Structured Data & Questionnaires** | Binary JSON (`JSONB`) with GIN indexing, jsonpath queries, and partial indexing. | JSON datatype available, but indexing is limited to generated columns or functional indexes. | **Dynamic Questionnaires:** Job requirements require custom screening questionnaires and responses. |
| **Audit & Append-Only Protection** | Granular privilege revocation (`REVOKE UPDATE, DELETE`) plus `BEFORE UPDATE OR DELETE` triggers. | Triggers supported, but less expressive event handling and no DDL audit triggers. | **Rule Group 4 & 10:** Guarantees tamper-proof financial ledgers and audit records. |
| **Performance Profiling & Observability** | `EXPLAIN (ANALYZE, BUFFERS)` provides exact buffer read/hit counts, heap fetches, and execution cost. | `EXPLAIN ANALYZE` added recently, but lacks granular shared buffer cache hit/miss introspection. | **Section 10 & Milestone 21:** Accurate baseline measurement (p50, p95, p99) and buffer cache projection. |

---

## 2. Comprehensive Module Catalog (B2)

The Talentra platform is partitioned into **11 Core Modules** plus **Tier 3 Reference Extensions**, mapped as follows:

| # | Module Name | Classification | Architectural Scope | Primary Backlogs |
| :-: | :--- | :--- | :--- | :--- |
| **M01** | **Master Data** | Common | Countries, states, cities, skills, qualifications, industries, job roles, employment/work types, UI translation keys & strings. | B1, B2, B3, B60 |
| **M02** | **Candidate Profile** | Common | Identity, contacts, education, experience, skills, projects, resume versions, assessments, certifications, activity logs. | B4, B5, B8, B9, B12, B13, B16, B17, B20, B21 |
| **M03** | **Jobs & Applications** | Common | Job postings, requirements, questionnaires, applications pipeline (applied to joined), status history, interviews, offers. | B6, B7, B10, B11, B14, B15, B18, B19, B22, B23 |
| **M04** | **Administration & Governance** | Phase 2 | Users, credentials, roles, permissions, session identity, consent records, append-only audit trail. | B24, B27, B30, B33 |
| **M05** | **Organisation & Accounts** | Phase 2 | Employer/client orgs, branches, tax identifiers, verification, recruiter mappings, org hierarchies, account admins. | B25, B28, B31, B34 |
| **M06** | **Gig Marketplace** | Phase 2 | Gig requests, worker profiles, availability slots, applications, assignments with non-overlapping GiST, ratings, earnings handoff. | B26, B29, B32, B35 |
| **M07** | **Licences & Sessions** | Phase 3 | Subscriptions licences, seat allocations, registered devices, active sessions, concurrent device limits, session revocation. | B36, B39, B42, B45 |
| **M08** | **Sourcing & Outreach** | Phase 3 | Sourcing requests, consultant openness, candidate shortlists, bulk outreach campaigns, recipient tracking. | B37, B40, B43, B46 |
| **M09** | **Subscriptions & Wallet** | Phase 3 | Plans, non-overlapping subscription intervals, payment orders, invoices, refunds, append-only credit ledger. | B38, B41, B44, B47 |
| **M10** | **Engagement & Community** | Phase 4 | Notification deliveries, job alerts, preferences, community forums, support tickets, FAQs, referral events. | B48, B51, B54, B57 |
| **M11** | **Analytics & Reporting Marts** | Phase 4 | Dimensional models (`dim_candidate`, `dim_organisation`, `dim_job`), fact tables (`fact_application_funnel`), materialized aggregates. | B49, B52, B55, B58 |
| **M12** | **Shared Team Security & Blocks** | Phase 4 | Candidate-to-employer blocking, candidate-to-recruiter blocking, credentials security, RLS policy definitions. | B50, B53, B56, B59 |
| **M13** | **Tier 3 Reference Domains** | Stretch | Salary benchmark percentiles, company ratings & reviews, trending job snapshots, feature flags. | Section 4 (Tier 3) |

---

## 3. Solo Engineering Assignment & Workflow Strategy (B3)

In the standard docket, modules are partitioned among a 3–5 member team across Phases 1 through 5. To execute this solo with maximum velocity, consistency, and zero defects:

1. **Unified Ownership:** All roles (Team Lead, Member A, Member B, Member C) are consolidated into a phased engineering pipeline.
2. **Incremental Commits:** Execution proceeds in 9 verified Git commits, each maintaining a clean testable state.
3. **Cross-Module Integrity:** A single architect ensures foreign keys, standard domain types, audit columns, and naming conventions remain 100% consistent across all 13 modules without merge drift.
4. **Living Brain Context:** Every macro and minute technical decision, benchmark result, and verification log is mirrored into the Notion master page (`Docket Hackathon`).

---

## 4. Fundamental Design Conventions

### 4.1 Primary & Surrogate Key Strategy
* **High-velocity Transactional Tables** (`candidate_application`, `notification_delivery`, `audit_log`, `wallet_transaction`, `candidate_activity_log`):  
  `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`.  
  *Rationale:* Provides maximum B-tree indexing density, compact 8-byte footprint, and sequential cache locality at 100M row scale.
* **Master & Public Domain Entities** (`users`, `organisation`, `job_requirement`, `gig_request`):  
  `UUID PRIMARY KEY DEFAULT gen_random_uuid()`.  
  *Rationale:* Prevents enumeration attacks across tenant boundaries while maintaining global uniqueness.
* **Natural Keys:** Maintained strictly as `UNIQUE` constraints (e.g. `uq_users_email`, `uq_organisation_tax_identifier`).

### 4.2 Audit & Temporal Standards
* Every business table includes:
  * `created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP`
  * `created_by UUID`
  * `updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP`
  * `updated_by UUID`
* Soft-deleted tables include `deleted_at TIMESTAMPTZ NULL`.
* Automated trigger `fn_set_updated_at()` updates `updated_at` on every `UPDATE`.

### 4.3 Financial & Audit Append-Only Rule
* `audit_log`, `wallet_ledger`, `payment_transaction`, and `profile_download_history` are strictly append-only.
* `UPDATE` and `DELETE` privileges are revoked on these tables, and `BEFORE UPDATE OR DELETE` triggers throw hard database exceptions.
