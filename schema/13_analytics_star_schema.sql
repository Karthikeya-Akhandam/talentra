-- ============================================================================
-- Talentra Schema: 13_analytics_star_schema.sql
-- Modules: Analytics Layer and Reporting Marts (M11) - Phase 4 (Milestones 15-18; B49, B52, B55, B58)
-- Standards: Rule Group 1, 2, 3, 4, 8 (Prefixes: dim_, fact_, agg_)
-- Key Features:
--   1. Slowly Changing Dimensions (SCD Type 2) for historical pipeline tracking (B58)
--   2. Star Schema Facts for High-Throughput OLAP queries
--   3. Materialized / Precomputed Aggregates for Dashboard KPIs
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Dimension: dim_date
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_date (
    date_key INT PRIMARY KEY, -- e.g. 20261015
    calendar_date DATE NOT NULL,
    day_of_week INT NOT NULL,
    day_name VARCHAR(15) NOT NULL,
    day_of_month INT NOT NULL,
    month_number INT NOT NULL,
    month_name VARCHAR(15) NOT NULL,
    calendar_quarter INT NOT NULL,
    calendar_year INT NOT NULL,
    is_weekend BOOLEAN NOT NULL DEFAULT FALSE,
    is_business_day BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_dim_date_calendar UNIQUE (calendar_date)
);

CREATE INDEX IF NOT EXISTS idx_dim_date_year_month ON dim_date (calendar_year, month_number);

-- ----------------------------------------------------------------------------
-- Dimension: dim_candidate (SCD Type 2 for tracking candidate career evolution)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_candidate (
    candidate_dim_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id UUID NOT NULL,
    full_name VARCHAR(200) NOT NULL,
    current_city_name VARCHAR(150) NULL,
    experience_bracket VARCHAR(50) NOT NULL, -- '0-2_years', '3-5_years', '6-8_years', '8+_years'
    highest_qualification VARCHAR(100) NULL,
    primary_skill_name VARCHAR(150) NULL,
    is_actively_looking BOOLEAN NOT NULL,
    scd_start_time TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    scd_end_time TIMESTAMPTZ NULL,
    is_current_record BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_dim_candidate_lookup ON dim_candidate (candidate_profile_id, is_current_record);

-- ----------------------------------------------------------------------------
-- Dimension: dim_organisation (SCD Type 2)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_organisation (
    organisation_dim_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id UUID NOT NULL,
    legal_name VARCHAR(200) NOT NULL,
    industry_name VARCHAR(150) NOT NULL,
    organisation_type VARCHAR(50) NOT NULL,
    employee_count_band VARCHAR(50) NOT NULL,
    verification_status VARCHAR(30) NOT NULL,
    hq_city_name VARCHAR(150) NULL,
    scd_start_time TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    scd_end_time TIMESTAMPTZ NULL,
    is_current_record BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_dim_org_lookup ON dim_organisation (organisation_id, is_current_record);

-- ----------------------------------------------------------------------------
-- Dimension: dim_job (SCD Type 2)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_job (
    job_dim_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id UUID NOT NULL,
    job_title VARCHAR(200) NOT NULL,
    job_role_title VARCHAR(150) NOT NULL,
    industry_name VARCHAR(150) NOT NULL,
    employment_type_name VARCHAR(100) NOT NULL,
    work_mode_name VARCHAR(100) NOT NULL,
    city_name VARCHAR(150) NOT NULL,
    salary_band VARCHAR(50) NOT NULL,
    is_open_to_consultants BOOLEAN NOT NULL,
    scd_start_time TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    scd_end_time TIMESTAMPTZ NULL,
    is_current_record BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_dim_job_lookup ON dim_job (job_requirement_id, is_current_record);

-- ----------------------------------------------------------------------------
-- Fact: fact_application_funnel
-- Tracks pipeline conversions, velocity, and recruitment costs
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_application_funnel (
    fact_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id BIGINT NOT NULL,
    candidate_dim_key BIGINT NOT NULL,
    organisation_dim_key BIGINT NOT NULL,
    job_dim_key BIGINT NOT NULL,
    applied_date_key INT NOT NULL,
    current_stage VARCHAR(30) NOT NULL,
    screened_date_key INT NULL,
    interviewed_date_key INT NULL,
    offered_date_key INT NULL,
    joined_date_key INT NULL,
    time_to_screen_hours INT NULL,
    time_to_interview_hours INT NULL,
    time_to_offer_days INT NULL,
    time_to_hire_days INT NULL,
    is_hired BOOLEAN NOT NULL DEFAULT FALSE,
    is_rejected BOOLEAN NOT NULL DEFAULT FALSE,
    offered_salary_amount DECIMAL(14, 2) NULL,
    placement_fee_amount DECIMAL(14, 2) NULL,
    CONSTRAINT fk_fact_app_cand FOREIGN KEY (candidate_dim_key) REFERENCES dim_candidate (candidate_dim_key),
    CONSTRAINT fk_fact_app_org FOREIGN KEY (organisation_dim_key) REFERENCES dim_organisation (organisation_dim_key),
    CONSTRAINT fk_fact_app_job FOREIGN KEY (job_dim_key) REFERENCES dim_job (job_dim_key),
    CONSTRAINT fk_fact_app_date FOREIGN KEY (applied_date_key) REFERENCES dim_date (date_key)
);

CREATE INDEX IF NOT EXISTS idx_fact_app_funnel ON fact_application_funnel (organisation_dim_key, applied_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_app_stage ON fact_application_funnel (current_stage, is_hired);

-- ----------------------------------------------------------------------------
-- Fact: fact_gig_engagement
-- Measures gig work economics, margins, fulfillment latency, and ratings
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_gig_engagement (
    fact_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gig_assignment_id UUID NOT NULL,
    organisation_dim_key BIGINT NOT NULL,
    start_date_key INT NOT NULL,
    end_date_key INT NULL,
    project_category VARCHAR(100) NOT NULL,
    agreed_budget_amount DECIMAL(14, 2) NOT NULL,
    reconciled_payout_amount DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    platform_fee_amount DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    engagement_duration_days INT NOT NULL,
    rating_score INT NULL,
    fulfillment_status VARCHAR(30) NOT NULL,
    CONSTRAINT fk_fact_gig_org FOREIGN KEY (organisation_dim_key) REFERENCES dim_organisation (organisation_dim_key),
    CONSTRAINT fk_fact_gig_date FOREIGN KEY (start_date_key) REFERENCES dim_date (date_key)
);

CREATE INDEX IF NOT EXISTS idx_fact_gig_engagement ON fact_gig_engagement (organisation_dim_key, start_date_key);

-- ----------------------------------------------------------------------------
-- Fact: fact_wallet_revenue
-- Revenue recognition and credit ledger analytics
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_wallet_revenue (
    fact_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_id BIGINT NOT NULL,
    organisation_dim_key BIGINT NOT NULL,
    date_key INT NOT NULL,
    revenue_stream_code VARCHAR(50) NOT NULL, -- 'subscription_fee', 'posting_credit_charge', 'download_credit_charge', 'outreach_charge'
    gross_revenue_amount DECIMAL(14, 2) NOT NULL,
    tax_collected_amount DECIMAL(14, 2) NOT NULL,
    net_revenue_amount DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    CONSTRAINT fk_fact_rev_org FOREIGN KEY (organisation_dim_key) REFERENCES dim_organisation (organisation_dim_key),
    CONSTRAINT fk_fact_rev_date FOREIGN KEY (date_key) REFERENCES dim_date (date_key)
);

CREATE INDEX IF NOT EXISTS idx_fact_wallet_rev ON fact_wallet_revenue (organisation_dim_key, date_key);

-- ----------------------------------------------------------------------------
-- Materialized Precomputed Aggregates (Rule Group 8: agg_ prefix)
-- Refreshed periodically for instant executive dashboard load
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agg_recruitment_kpis_daily (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_key INT NOT NULL,
    organisation_dim_key BIGINT NOT NULL,
    active_job_postings_count INT NOT NULL DEFAULT 0,
    applications_received_count INT NOT NULL DEFAULT 0,
    interviews_conducted_count INT NOT NULL DEFAULT 0,
    offers_extended_count INT NOT NULL DEFAULT 0,
    hires_completed_count INT NOT NULL DEFAULT 0,
    avg_time_to_hire_days DECIMAL(6, 2) NULL,
    total_spend_amount DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_agg_recruitment_daily UNIQUE (date_key, organisation_dim_key)
);

CREATE TABLE IF NOT EXISTS agg_gig_demand_monthly (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    year_month INT NOT NULL, -- e.g. 202610
    project_category VARCHAR(100) NOT NULL,
    total_requests_count INT NOT NULL DEFAULT 0,
    total_assignments_count INT NOT NULL DEFAULT 0,
    total_gross_spend_amount DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    avg_hourly_rate DECIMAL(10, 2) NULL,
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_agg_gig_monthly UNIQUE (year_month, project_category)
);
