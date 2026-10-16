# Talentra — Database Design Hackathon

**Enterprise Operational and Analytical Database for Job Search, Staffing, and Gig Demand Management**  
*Prepared for Northbridge Workforce Systems | Engine: PostgreSQL 17.5 | Solo Engineering Execution*

---

## 🌟 Executive Summary

Talentra is a high-scale recruitment and demand management platform designed to service **10 million candidate profiles, 1 million job requirements, and 100 million applications**. This repository contains the complete relational, analytical, security, and benchmarking artifacts designed to resolve legacy data fragmentation and establish a unified hiring pipeline.

### Core Architecture Highlights
* **Engine:** PostgreSQL 17.5.
* **Temporal Integrity:** Native PostgreSQL `EXCLUDE USING gist` ensures that **gig assignments** and **subscription periods** cannot have overlapping active windows.
* **Database-Enforced Security:** PostgreSQL **Row Level Security (RLS)** enforces recruiter isolation to their own organization, consultant restrictions to open jobs, and automatic blinding of candidates who blocked specific recruiters or employers.
* **Append-Only Financial & Audit Ledgers:** Hard trigger and permission-level restrictions guarantee tamper-proof financial journals, wallet ledgers, and audit events.
* **Scale Architecture:** Declarative range partitioning for high-velocity transactional tables (`candidate_application`, `notification_delivery`).
* **Analytical Layer:** High-performance Star Schema (`dim_candidate`, `dim_organisation`, `dim_job`, `fact_application_funnel`, `fact_gig_engagement`, `fact_wallet_revenue`) with pre-aggregated materialized views for instant executive reporting.
* **Comprehensive Scope:** 100% modeling across all **Tier 1 (Mandatory)**, **Tier 2 (Expected)**, and **Tier 3 (Reference/Bonus)** domains, including salary benchmarks, company ratings, trending jobs, and feature flags.

---

## 📂 Repository Structure

```text
Database-Design-Hackathon-Docket/
├── docs/
│   ├── 01_architecture_decisions.md       # B1-B3 Engine selection, module catalog, solo roadmap
│   ├── 02_rule_compliance_table.md       # 10 Rule Groups compliance verification matrix
│   ├── 03_data_dictionary.md              # Complete data dictionary, nullability justifications, sensitive tagging
│   ├── 04_integration_boundaries.md      # Data ownership, storage, failure mode, idempotency, audit for 9 systems
│   ├── 05_competitive_benchmark.md       # Competitive matrix: Talentra vs Naukri, Monster, LinkedIn
│   ├── 06_performance_extrapolation.md    # 1M -> 10M profiles & 5M -> 100M apps mathematical projection
│   ├── 07_threat_model_and_security.md    # STRIDE threat model, RLS policies, PII encryption/masking
│   └── 08_gate2_signoff_report.md         # Gate 2 sign-off report & defense checklist
├── schema/
│   ├── 01_master_data.sql                 # Master lookups, countries, skills, UI translations (UTF-8)
│   ├── 02_identity_and_accounts.sql       # Users, credentials, roles, permissions, sessions, consent
│   ├── 03_organisation_and_hierarchy.sql  # Employer orgs, locations, tax IDs, recruiter mappings
│   ├── 04_candidate_profile_and_resumes.sql # Profiles, education, experience, skills, projects, resumes
│   ├── 05_job_lifecycle_and_questionnaires.sql # Jobs, positions, questionnaires, publish workflow
│   ├── 06_applications_and_pipeline.sql   # Applications (range partitioned), status pipelines, interviews
│   ├── 07_gig_marketplace.sql             # Gig requests, worker profiles, GiST exclusion constraints
│   ├── 08_licences_devices_sessions.sql   # Licences, seats, concurrent device limits & triggers
│   ├── 09_sourcing_and_consultants.sql    # Sourcing requests, consultant access, bulk outreach
│   ├── 10_subscriptions_wallet_ledger.sql # Append-only ledgers, plans, payments, invoices, refunds
│   ├── 11_engagement_and_support.sql      # Notifications, alerts, community, tickets, FAQs, referrals
│   ├── 12_tier3_reference_domains.sql     # Salary benchmarks, company ratings, trending jobs, feature flags
│   ├── 13_analytics_star_schema.sql       # Dimensions (SCD), Fact tables, and Materialized Aggregates
│   └── 14_security_rls_and_masking.sql    # RLS policies, masking views, pgcrypto functions
├── scripts/
│   ├── seed_data_generator.py             # High-speed synthetic generator with realistic distributions
│   ├── run_seeding.py                     # PostgreSQL COPY loader for laptop-scale data
│   ├── run_benchmarks.py                  # Benchmark runner measuring p50, p95, p99 & buffer stats
│   └── backup_restore_test.ps1            # Automated pg_dump/pg_restore timing and validation
├── queries/
│   ├── 01_fixed_twelve_queries.sql        # The 12 mandatory query scenarios with business rationale
│   └── 02_index_optimizations.sql         # 1 index per module with before-and-after EXPLAIN ANALYZE
└── tests/
    ├── test_domain_rules_and_constraints.sql # Automated validation of all CHECK, EXCLUDE, and FK constraints
    └── test_rls_security_isolation.sql    # Automated test of recruiter and blocklist isolation
```

---
