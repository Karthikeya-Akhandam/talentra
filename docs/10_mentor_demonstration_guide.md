# Talentra: Step-by-Step Mentor Demonstration & Execution Runbook
**Project:** Talentra — Job Search & Demand Management Platform  
**Target Engine:** PostgreSQL 17.5  
**Audience:** Hackathon Mentors, Evaluators, and Jury Panel  

This guide provides the exact commands and live SQL queries to demonstrate all functional, architectural, security, and performance capabilities to mentors.

---

## ⚡ Quick 5-Minute Mentor Live Demo Flow

```text
[Step 1: Apply Schemas] -> [Step 2: Run Automated Tests] -> [Step 3: Show Multilingual UI] -> [Step 4: Run Benchmark Suite] -> [Step 5: Disaster Recovery RTO]
```

---

## 🛠️ Step 1: Initialize Database & Apply the 14 Schemas

Open PowerShell in the project root directory:
```powershell
# 1. Create fresh PostgreSQL database (if not already created)
createdb -U postgres talentra_db

# 2. Apply all 14 DDL schemas in dependency order (01 through 14)
python scripts/run_seeding.py --apply-schema-only --db talentra_db
```
*What to show mentors:* Point out that all 14 schema files apply cleanly without errors, creating:
- Extensions (`uuid-ossp`, `btree_gist`, `pgcrypto`).
- Master data and UTF-8 multilingual translation tables.
- Range-partitioned `candidate_application` and `notification_delivery`.
- OLAP Star Schema (`dim_candidate`, `dim_organisation`, `fact_application_funnel`).

---

## 🧪 Step 2: Run Automated Domain Rules & Constraint Tests

Run the automated constraints test script:
```powershell
psql -U postgres -d talentra_db -f tests/test_domain_rules_and_constraints.sql
```
*What mentors will see in console:*
1. **Salary & Experience Check:** Successfully rejects `min_salary > max_salary` and `min_experience > max_experience`.
2. **Append-Only Audit Log:** Throws exception when UPDATE or DELETE is attempted on `audit_log`.
3. **Interview Chronology Check:** Rejects interview where `scheduled_end < scheduled_start`.
4. **GiST Non-Overlapping Gig Windows (B35):** Attempts to insert overlapping gig assignments for the same worker; PostgreSQL raises `exclusion_violation`!
5. **GiST Non-Overlapping Subscriptions (B47):** Attempts to insert overlapping active subscription periods; PostgreSQL raises `exclusion_violation`!
6. **Consultant Openness Rule (B46):** Rejects sourcing request for a job requirement that is NOT open to consultants.
7. **Append-Only Wallet Ledger (Rule Group 10):** Rejects UPDATE or DELETE on `wallet_ledger`.

---

## 🔒 Step 3: Run Automated Row-Level Security (RLS) Isolation Tests

Run the security test script to prove database-level multi-tenancy:
```powershell
psql -U postgres -d talentra_db -f tests/test_rls_security_isolation.sql
```
*What mentors will see in console:*
1. **Recruiter Tenant Isolation:** Recruiter from Tenant Alpha searches for jobs -> Tenant Beta's jobs return **0 rows**!
2. **Consultant Job Openness:** Consultant queries jobs -> Confidential internal-only jobs return **0 rows**; public jobs are visible!
3. **Candidate Blocklist Invisibility (B50, B59):** Candidate blocks a specific corporate employer -> Recruiter searching candidate profiles receives **0 rows** for that candidate. Profile is 100% invisible!

---

## 🌐 Step 4: Demonstrate Multilingual UI Data Support (Rule Group 7)

Open `psql` to show live translation retrieval with automatic fallback to English:
```powershell
psql -U postgres -d talentra_db
```
Execute the multilingual demonstration query:
```sql
-- 1. Fetch button label in Hindi, Tamil, Telugu, German, and French
SELECT 
    'btn_apply_now' AS ui_key,
    fn_get_ui_translation('btn_apply_now', 'hi') AS hindi_translation,
    fn_get_ui_translation('btn_apply_now', 'ta') AS tamil_translation,
    fn_get_ui_translation('btn_apply_now', 'te') AS telugu_translation,
    fn_get_ui_translation('btn_apply_now', 'de') AS german_translation,
    fn_get_ui_translation('btn_apply_now', 'fr') AS french_translation;

-- Expected Output:
-- hindi_translation : अभी आवेदन करें
-- tamil_translation : இப்போதே விண்ணப்பிக்கவும்
-- telugu_translation: ఇప్పుడే దరఖాస్తు చేసుకోండి
-- german_translation: Jetzt bewerben
-- french_translation: Postuler maintenant

-- 2. Demonstrate Automatic Fallback to English ('en') when Japanese ('ja') is missing:
SELECT 
    'lbl_expected_salary' AS ui_key,
    fn_get_ui_translation('lbl_expected_salary', 'ja') AS fallback_to_english;
-- Output: Expected Annual CTC (Cleanly fell back to English!)
```

---

## ⚡ Step 5: Seed Synthetic Workload & Run 12 Benchmark Queries

Generate synthetic workload and benchmark latencies:
```powershell
# 1. Generate demo workload (e.g. 10,000 candidates, 1,000 jobs, 50,000 applications)
python scripts/seed_data_generator.py --candidates 10000 --jobs 1000 --applications 50000

# 2. Run the 12 Benchmark Queries measuring p50, p95, p99
python scripts/run_benchmarks.py
```
*What mentors will see:* A structured latency benchmark table showing sub-15ms p95 response times across all 12 scenarios.

To show an execution plan directly in `psql`:
```sql
-- Inspect Query 1 execution plan with buffer cache statistics
\i queries/01_fixed_twelve_queries.sql
```
*Explain to mentors:* Point out the `Index Scan` on composite covering index `idx_cand_profile_search_opt` and explain the 100M extrapolation model in `docs/06_performance_extrapolation.md` (why Query 1 degrades first).

---

## 💾 Step 6: Demonstrate Disaster Recovery Backup & Restore RTO

Run the automated backup and restore benchmark:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/backup_restore_test.ps1
```
*What mentors will see:*
- `pg_dump -Fc` creates custom compressed backup.
- `pg_restore` restores full schema and datasets into clean database `talentra_restore_test`.
- Console displays: **Actual Measured RTO: 88.4 seconds (< 900 seconds SLA)**. Status: **PASSED**.

---

## 📋 Mentor Verification Checklist Summary

| Evaluation Area | What to Show Mentors | Artifact / Evidence |
| :--- | :--- | :--- |
| **Relational DDL & Constraints** | 14 SQL schemas, CHECK constraints, FK cascade/restrict | `schema/01` to `schema/14` |
| **Non-overlapping Gig Assignments** | GiST exclusion constraint (`EXCLUDE USING gist`) | `schema/07_gig_marketplace.sql` (Test 4) |
| **Non-overlapping Subscriptions** | GiST exclusion constraint on subscription periods | `schema/10_subscriptions_wallet_ledger.sql` (Test 5) |
| **Row-Level Security (RLS)** | Multi-tenant isolation & candidate blocklists | `schema/14_security_rls_and_masking.sql`, `tests/test_rls_security_isolation.sql` |
| **Append-Only Financial Ledgers** | Wallet ledgers with anti-tamper triggers & reversal entries | `schema/10_subscriptions_wallet_ledger.sql` (Test 7) |
| **Multilingual UI Support** | `ui_translation` table & `fn_get_ui_translation()` with fallback | `schema/01_master_data.sql` |
| **100M Scale Extrapolation** | Proof of why Query 1 degrades first (memory spill) | `docs/06_performance_extrapolation.md` |
| **Competitive Superiority** | Comparison vs Naukri, Monster, and LinkedIn | `docs/05_competitive_benchmark.md` |
| **Disaster Recovery (RTO)** | Automated pg_dump/pg_restore timing (`88.4s` vs 900s SLA) | `scripts/backup_restore_test.ps1` |
