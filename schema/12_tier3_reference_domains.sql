-- ============================================================================
-- Talentra Schema: 12_tier3_reference_domains.sql
-- Modules: Tier 3 Reference & Bonus Domains (Section 4)
-- Scope: Salary benchmarks, Company ratings, Trending jobs, Feature flags
-- Standards: Rule Group 1, 2, 3, 4, 8
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: salary_benchmark
-- Rule Group 2 & 3: Percentile ordering check constraints
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS salary_benchmark (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_role_id UUID NOT NULL,
    industry_id UUID NOT NULL,
    city_id UUID NOT NULL,
    experience_band VARCHAR(50) NOT NULL, -- '0-2_years', '3-5_years', '6-8_years', '9-12_years', '12+_years'
    percentile_10 DECIMAL(14, 2) NOT NULL,
    percentile_25 DECIMAL(14, 2) NOT NULL,
    percentile_50 DECIMAL(14, 2) NOT NULL, -- Median
    percentile_75 DECIMAL(14, 2) NOT NULL,
    percentile_90 DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    sample_size INT NOT NULL DEFAULT 100,
    benchmark_year INT NOT NULL DEFAULT 2026,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_bench_role FOREIGN KEY (job_role_id) REFERENCES job_role (id) ON DELETE CASCADE,
    CONSTRAINT fk_bench_ind FOREIGN KEY (industry_id) REFERENCES industry (id) ON DELETE CASCADE,
    CONSTRAINT fk_bench_city FOREIGN KEY (city_id) REFERENCES city (id) ON DELETE CASCADE,
    CONSTRAINT uq_salary_benchmark UNIQUE (job_role_id, industry_id, city_id, experience_band, benchmark_year),
    CONSTRAINT chk_benchmark_percentiles CHECK (
        percentile_10 <= percentile_25 AND
        percentile_25 <= percentile_50 AND
        percentile_50 <= percentile_75 AND
        percentile_75 <= percentile_90 AND
        percentile_10 > 0.00
    )
);

CREATE INDEX IF NOT EXISTS idx_salary_bench_lookup ON salary_benchmark (job_role_id, city_id, experience_band);

-- ----------------------------------------------------------------------------
-- Table: company_rating
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS company_rating (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    overall_rating DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    work_life_balance_rating DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    compensation_benefits_rating DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    career_growth_rating DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    culture_values_rating DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    total_reviews_count INT NOT NULL DEFAULT 0,
    last_updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_rating_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT uq_company_rating_org UNIQUE (organisation_id),
    CONSTRAINT chk_overall_rating CHECK (overall_rating >= 0.00 AND overall_rating <= 5.00)
);

-- ----------------------------------------------------------------------------
-- Table: company_review
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS company_review (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    reviewer_user_id UUID NOT NULL,
    headline VARCHAR(200) NOT NULL,
    pros_text TEXT NOT NULL,
    cons_text TEXT NOT NULL,
    advice_to_management TEXT NULL,
    rating_score INT NOT NULL,
    is_current_employee BOOLEAN NOT NULL DEFAULT TRUE,
    is_anonymous BOOLEAN NOT NULL DEFAULT TRUE,
    moderation_status_code VARCHAR(30) NOT NULL DEFAULT 'approved', -- 'pending', 'approved', 'rejected'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_review_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT fk_review_user FOREIGN KEY (reviewer_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_review_score CHECK (rating_score >= 1 AND rating_score <= 5)
);

CREATE INDEX IF NOT EXISTS idx_company_review_org ON company_review (organisation_id);

-- ----------------------------------------------------------------------------
-- Table: trending_job_snapshot
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trending_job_snapshot (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_date DATE NOT NULL,
    job_role_id UUID NOT NULL,
    active_postings_count INT NOT NULL,
    total_applications_count INT NOT NULL,
    average_offered_salary DECIMAL(14, 2) NOT NULL,
    growth_rate_percentage DECIMAL(5, 2) NOT NULL DEFAULT 0.00,
    top_in_demand_skills JSONB NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_trending_role FOREIGN KEY (job_role_id) REFERENCES job_role (id) ON DELETE CASCADE,
    CONSTRAINT uq_trending_snapshot UNIQUE (snapshot_date, job_role_id)
);

CREATE INDEX IF NOT EXISTS idx_trending_snapshot_date ON trending_job_snapshot (snapshot_date);

-- ----------------------------------------------------------------------------
-- Table: feature_flag
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS feature_flag (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    flag_key VARCHAR(100) NOT NULL,
    name VARCHAR(150) NOT NULL,
    description VARCHAR(255) NULL,
    is_globally_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    rollout_percentage INT NOT NULL DEFAULT 0,
    target_roles JSONB NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_feature_flag_key UNIQUE (flag_key),
    CONSTRAINT chk_rollout_pct CHECK (rollout_percentage >= 0 AND rollout_percentage <= 100)
);
