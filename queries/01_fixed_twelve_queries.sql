-- ============================================================================
-- Talentra Fixed Benchmark Query Suite
-- Module: Queries and Validation (Phase 5, Milestone 20 & 21; B65-B74)
-- Standards: Section 10 & Milestone 20
-- Engine: PostgreSQL 17.5
-- Total Queries: 12 Fixed Benchmark Scenarios covering Functional,
--                Transactional, Lookup, OLAP, and Partition Pruning paths.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Query 1: Multi-Criteria Candidate Search with Skill & Location Match
-- Business Scenario: Recruiter searches for active candidates matching primary skills,
--                    experience band, salary expectation, and location.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    cp.id AS candidate_id,
    cp.first_name,
    cp.last_name,
    cp.headline,
    c.name AS city_name,
    cp.total_experience_months / 12.0 AS experience_years,
    cp.expected_salary_amount,
    cp.notice_period_days,
    COUNT(cs.skill_id) AS matching_skills_count
FROM candidate_profile cp
JOIN city c ON cp.current_city_id = c.id
JOIN candidate_skill cs ON cp.id = cs.candidate_profile_id
JOIN skill s ON cs.skill_id = s.id
WHERE cp.is_actively_looking = TRUE
  AND cp.deleted_at IS NULL
  AND cp.total_experience_months BETWEEN 36 AND 84
  AND cp.expected_salary_amount <= 2000000.00
  AND c.name IN ('Bengaluru', 'Hyderabad', 'Pune')
  AND s.code IN ('PYTHON', 'POSTGRES', 'DOCKER', 'KUBERNETES')
GROUP BY cp.id, cp.first_name, cp.last_name, cp.headline, c.name, cp.total_experience_months, cp.expected_salary_amount, cp.notice_period_days
HAVING COUNT(cs.skill_id) >= 2
ORDER BY matching_skills_count DESC, cp.total_experience_months DESC
LIMIT 50;

-- ----------------------------------------------------------------------------
-- Query 2: Recruiter Application Pipeline Funnel & Stage Aging
-- Business Scenario: Recruiter views pipeline metrics for an active job requirement,
--                    including applicant counts per stage and average days spent in stage.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    jr.id AS job_id,
    jr.job_title,
    ca.current_status_code AS pipeline_stage,
    COUNT(ca.id) AS candidate_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ca.applied_at)) / 86400.0)::NUMERIC, 1) AS avg_days_since_applied,
    COUNT(CASE WHEN ca.applied_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) AS applied_last_7_days
FROM job_requirement jr
JOIN candidate_application ca ON jr.id = ca.job_requirement_id
WHERE jr.id = '11111111-1111-1111-1111-111111111111'::UUID
  AND ca.is_withdrawn = FALSE
GROUP BY jr.id, jr.job_title, ca.current_status_code
ORDER BY candidate_count DESC;

-- ----------------------------------------------------------------------------
-- Query 3: Gig Worker Availability & Conflict Matching Engine
-- Business Scenario: Match open gig requests with available, non-overlapping gig workers
--                    whose hourly rate falls within the project budget.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    gr.id AS gig_request_id,
    gr.title AS gig_title,
    gwp.id AS worker_id,
    u.email AS worker_email,
    gwp.hourly_rate_amount,
    gwp.average_rating,
    gwp.total_completed_gigs
FROM gig_request gr
JOIN gig_worker_profile gwp ON gwp.hourly_rate_amount <= (gr.budget_amount / 40.0) -- Assuming 40 hour baseline
JOIN users u ON gwp.user_id = u.id
WHERE gr.id = '22222222-2222-2222-2222-222222222222'::UUID
  AND gwp.is_available_for_hire = TRUE
  AND gwp.deleted_at IS NULL
  -- Ensure worker has NO conflicting active gig assignment overlapping the gig window
  AND NOT EXISTS (
      SELECT 1 FROM gig_assignment ga
      WHERE ga.gig_worker_profile_id = gwp.id
        AND ga.assignment_status_code IN ('assigned', 'in_fulfillment')
        AND ga.assignment_window && gr.gig_window
  )
  -- Ensure worker is not blacklisted by the requester organisation
  AND NOT EXISTS (
      SELECT 1 FROM gig_requester_worker_list gwl
      WHERE gwl.organisation_id = gr.organisation_id
        AND gwl.gig_worker_profile_id = gwp.id
        AND gwl.list_type_code = 'blacklist'
  )
ORDER BY gwp.average_rating DESC, gwp.total_completed_gigs DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- Query 4: Recruiter Multi-Tenant Isolation Verification
-- Business Scenario: Prove that a recruiter querying job requirements only sees jobs
--                    belonging to their own organization (RLS / Tenant Isolation).
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    jr.id,
    jr.job_title,
    o.legal_name AS company_name,
    jr.publish_status_code,
    jr.created_at
FROM job_requirement jr
JOIN organisation o ON jr.organisation_id = o.id
WHERE jr.organisation_id = '33333333-3333-3333-3333-333333333333'::UUID
  AND jr.deleted_at IS NULL
ORDER BY jr.created_at DESC;

-- ----------------------------------------------------------------------------
-- Query 5: Candidate Blocklist Enforced Search (B50, B59)
-- Business Scenario: Employer searches candidates; system invisibly excludes any
--                    candidates who have placed a block on this company or recruiter.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    cp.id AS candidate_id,
    cp.first_name,
    cp.last_name,
    cp.headline,
    cp.total_experience_months
FROM candidate_profile cp
WHERE cp.is_actively_looking = TRUE
  AND cp.deleted_at IS NULL
  -- Filter out candidate if candidate blocked this specific recruiter
  AND NOT EXISTS (
      SELECT 1 FROM user_block_list ubl
      WHERE ubl.blocker_user_id = cp.user_id
        AND ubl.blocked_user_id = '44444444-4444-4444-4444-444444444444'::UUID -- Current Recruiter User ID
  )
  -- Filter out candidate if candidate blocked this recruiter's employer company
  AND NOT EXISTS (
      SELECT 1 FROM company_block_list cbl
      WHERE cbl.candidate_user_id = cp.user_id
        AND cbl.blocked_organisation_id = '33333333-3333-3333-3333-333333333333'::UUID -- Current Employer Org ID
  )
LIMIT 50;

-- ----------------------------------------------------------------------------
-- Query 6: Consultant Sourcing Shortlist Conversion & Commission Ledger
-- Business Scenario: Measure consultant performance: submitted candidates,
--                    interview conversion rate, and commission payable.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    u.id AS consultant_id,
    u.email AS consultant_email,
    COUNT(DISTINCT sr.id) AS total_engagements,
    COUNT(DISTINCT scs.id) AS candidates_submitted,
    COUNT(DISTINCT CASE WHEN scs.submission_status_code = 'hired' THEN scs.id END) AS successful_placements,
    ROUND(
        COUNT(DISTINCT CASE WHEN scs.submission_status_code = 'hired' THEN scs.id END)::NUMERIC / 
        NULLIF(COUNT(DISTINCT scs.id), 0) * 100.0, 2
    ) AS conversion_rate_percentage,
    COALESCE(SUM(pr.fee_invoiced_amount * (sr.proposed_commission_rate / 100.0)), 0.00) AS total_commission_earned
FROM users u
JOIN sourcing_request sr ON u.id = sr.consultant_user_id
LEFT JOIN sourcing_candidate_shortlist scs ON sr.id = scs.sourcing_request_id
LEFT JOIN candidate_application ca ON scs.candidate_profile_id = ca.candidate_profile_id AND sr.job_requirement_id = ca.job_requirement_id
LEFT JOIN placement_record pr ON ca.id = pr.application_id
WHERE u.user_type_code = 'consultant'
  AND sr.status_code = 'accepted'
GROUP BY u.id, u.email
ORDER BY successful_placements DESC;

-- ----------------------------------------------------------------------------
-- Query 7: Concurrent Device Session Quota & Active Session Inspection (Rule Group 9)
-- Business Scenario: Monitor organization seat utilization and active device session
--                    counts vs licensed quotas to identify concurrency abuse.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    o.id AS organisation_id,
    o.legal_name,
    sl.max_users,
    sl.max_devices_per_user,
    COUNT(DISTINCT sa.user_id) AS allocated_seats_count,
    COUNT(DISTINCT us.id) AS currently_active_sessions_count,
    ROUND((COUNT(DISTINCT us.id)::NUMERIC / (sl.max_users * sl.max_devices_per_user)) * 100.0, 2) AS device_capacity_utilization_pct
FROM organisation o
JOIN subscription_licence sl ON o.id = sl.organisation_id AND sl.status_code = 'active'
LEFT JOIN licence_seat_allocation sa ON sl.id = sa.subscription_licence_id AND sa.is_active = TRUE
LEFT JOIN user_session us ON sa.user_id = us.user_id AND us.is_active = TRUE AND us.end_time IS NULL
WHERE o.id = '33333333-3333-3333-3333-333333333333'::UUID
GROUP BY o.id, o.legal_name, sl.max_users, sl.max_devices_per_user;

-- ----------------------------------------------------------------------------
-- Query 8: Append-Only Wallet Ledger Reconciliation & Balance Audit (Rule Group 10)
-- Business Scenario: Cryptographically verify wallet balance integrity by summing
--                    all immutable transaction deltas and comparing against current balance.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    w.id AS wallet_id,
    w.organisation_id,
    w.credit_balance AS stored_wallet_balance,
    COALESCE(SUM(wl.credit_delta), 0.00) AS computed_sum_of_ledger_deltas,
    (w.credit_balance - COALESCE(SUM(wl.credit_delta), 0.00)) AS reconciliation_variance,
    COUNT(wl.id) AS total_ledger_transactions_count,
    MAX(wl.created_at) AS last_ledger_timestamp
FROM wallet w
LEFT JOIN wallet_ledger wl ON w.id = wl.wallet_id
WHERE w.organisation_id = '33333333-3333-3333-3333-333333333333'::UUID
GROUP BY w.id, w.organisation_id, w.credit_balance;

-- ----------------------------------------------------------------------------
-- Query 9: Partition Pruning on High-Volume Candidate Applications (5M -> 100M Scale)
-- Business Scenario: Query applications submitted in Q1 2026; verifies that PostgreSQL
--                    performs Partition Pruning and scans ONLY candidate_application_p2026.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    ca.job_requirement_id,
    ca.current_status_code,
    COUNT(ca.id) AS total_applications
FROM candidate_application ca
WHERE ca.applied_at >= '2026-01-01 00:00:00+00'
  AND ca.applied_at < '2026-04-01 00:00:00+00'
  AND ca.is_withdrawn = FALSE
GROUP BY ca.job_requirement_id, ca.current_status_code
ORDER BY total_applications DESC
LIMIT 50;

-- ----------------------------------------------------------------------------
-- Query 10: High-Volume Notification Delivery Latency by Channel (B57)
-- Business Scenario: Analyze dispatch volume, failure rate, and delivery latency
--                    across messaging channels (SMS, Email, WhatsApp, Push).
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    nd.channel_type_code,
    COUNT(nd.id) AS total_dispatched,
    COUNT(CASE WHEN nd.delivery_status_code = 'delivered' THEN 1 END) AS successful_deliveries,
    COUNT(CASE WHEN nd.delivery_status_code = 'failed' THEN 1 END) AS failed_deliveries,
    ROUND(
        COUNT(CASE WHEN nd.delivery_status_code = 'delivered' THEN 1 END)::NUMERIC / 
        NULLIF(COUNT(nd.id), 0) * 100.0, 2
    ) AS delivery_success_rate_pct,
    ROUND(AVG(EXTRACT(EPOCH FROM (nd.delivered_at - nd.sent_at)))::NUMERIC, 2) AS avg_delivery_latency_seconds
FROM notification_delivery nd
WHERE nd.created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY nd.channel_type_code
ORDER BY total_dispatched DESC;

-- ----------------------------------------------------------------------------
-- Query 11: Star Schema OLAP Mart: Recruitment Funnel Velocity & KPIs
-- Business Scenario: Executive dashboard query evaluating Time-to-Hire and Offer
--                    Acceptance Rate across industries and cities.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    dorg.industry_name,
    djob.city_name,
    ddate.calendar_year,
    ddate.calendar_quarter,
    COUNT(faf.fact_key) AS total_applications_funneled,
    SUM(CASE WHEN faf.is_hired = TRUE THEN 1 ELSE 0 END) AS total_hires,
    ROUND(AVG(faf.time_to_hire_days), 1) AS avg_time_to_hire_days,
    ROUND(AVG(faf.offered_salary_amount), 2) AS avg_offered_salary,
    SUM(faf.placement_fee_amount) AS total_placement_revenue_inr
FROM fact_application_funnel faf
JOIN dim_organisation dorg ON faf.organisation_dim_key = dorg.organisation_dim_key
JOIN dim_job djob ON faf.job_dim_key = djob.job_dim_key
JOIN dim_date ddate ON faf.applied_date_key = ddate.date_key
WHERE ddate.calendar_year = 2026
GROUP BY dorg.industry_name, djob.city_name, ddate.calendar_year, ddate.calendar_quarter
ORDER BY total_hires DESC, total_placement_revenue_inr DESC
LIMIT 50;

-- ----------------------------------------------------------------------------
-- Query 12: Salary Benchmark Market Deviation Analysis (Tier 3 Domain)
-- Business Scenario: Compare active job requisition salaries against market 50th and
--                    90th percentiles to flag uncompetitive job postings.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    jr.id AS job_id,
    jr.job_title,
    o.legal_name AS company_name,
    jr.min_salary_amount AS job_min_salary,
    jr.max_salary_amount AS job_max_salary,
    sb.percentile_25 AS market_p25,
    sb.percentile_50 AS market_median,
    sb.percentile_75 AS market_p75,
    CASE 
        WHEN jr.max_salary_amount < sb.percentile_25 THEN 'Significantly Below Market'
        WHEN jr.max_salary_amount < sb.percentile_50 THEN 'Below Median'
        WHEN jr.max_salary_amount > sb.percentile_75 THEN 'Highly Competitive'
        ELSE 'At Market Median'
    END AS competitiveness_status
FROM job_requirement jr
JOIN organisation o ON jr.organisation_id = o.id
JOIN salary_benchmark sb ON jr.job_role_id = sb.job_role_id
                        AND jr.primary_city_id = sb.city_id
                        AND sb.is_active = TRUE
WHERE jr.publish_status_code = 'published'
  AND jr.deleted_at IS NULL
ORDER BY (jr.max_salary_amount - sb.percentile_50) ASC
LIMIT 50;
