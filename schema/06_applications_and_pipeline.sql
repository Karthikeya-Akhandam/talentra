-- ============================================================================
-- Talentra Schema: 06_applications_and_pipeline.sql
-- Modules: Applications and Pipeline (M03), Tier 2 Shortlists/Bookmarks
-- Standards: Rule Group 1 (snake_case, singular), Rule Group 2 (Keys/Constraints),
--            Rule Group 3 (Standard Domains), Rule Group 4 (Audit/Lifecycle),
--            Rule Group 8 (Physical Partition Naming)
-- Scale: Partitioned table designed for 5M (laptop) -> 100M (full scale) applications
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: candidate_application (Partitioned by Range on applied_at)
-- In PostgreSQL partitioned tables, the partition key must be part of any unique/primary key.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_application (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id UUID NOT NULL,
    job_requirement_id UUID NOT NULL,
    resume_version_id BIGINT NULL,
    current_status_code VARCHAR(30) NOT NULL DEFAULT 'applied', -- 'applied', 'screened', 'shortlisted', 'interview_scheduled', 'offered', 'joined', 'rejected', 'withdrawn'
    cover_letter TEXT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_withdrawn BOOLEAN NOT NULL DEFAULT FALSE,
    withdrawn_reason VARCHAR(255) NULL,
    rejection_reason_code VARCHAR(50) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT pk_candidate_application PRIMARY KEY (id, applied_at),
    CONSTRAINT fk_app_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE RESTRICT,
    CONSTRAINT fk_app_job FOREIGN KEY (job_requirement_id) REFERENCES job_requirement (id) ON DELETE RESTRICT
) PARTITION BY RANGE (applied_at);

-- Partitions
CREATE TABLE IF NOT EXISTS candidate_application_p2025 PARTITION OF candidate_application
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS candidate_application_p2026 PARTITION OF candidate_application
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS candidate_application_p2027 PARTITION OF candidate_application
    FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2028-01-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS candidate_application_default PARTITION OF candidate_application
    DEFAULT;

CREATE INDEX IF NOT EXISTS idx_cand_app_candidate ON candidate_application (candidate_profile_id, applied_at);
CREATE INDEX IF NOT EXISTS idx_cand_app_job ON candidate_application (job_requirement_id, current_status_code, applied_at);

-- ----------------------------------------------------------------------------
-- Table: application_status_history (Audit of every pipeline transition)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS application_status_history (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id BIGINT NOT NULL,
    from_status_code VARCHAR(30) NOT NULL,
    to_status_code VARCHAR(30) NOT NULL,
    changed_by_user_id UUID NULL,
    transition_note TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_app_status_history_app ON application_status_history (application_id, created_at);

-- ----------------------------------------------------------------------------
-- Table: application_questionnaire_response
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS application_questionnaire_response (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id BIGINT NOT NULL,
    job_questionnaire_question_id UUID NOT NULL,
    answer_text TEXT NULL,
    answer_numeric DECIMAL(12, 2) NULL,
    answer_boolean BOOLEAN NULL,
    answer_payload JSONB NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_app_resp_question FOREIGN KEY (job_questionnaire_question_id) REFERENCES job_questionnaire_question (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_app_response_app_id ON application_questionnaire_response (application_id);

-- ----------------------------------------------------------------------------
-- Table: interview_schedule (Rule Group 2 & 3: end > start check)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS interview_schedule (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id BIGINT NOT NULL,
    round_number INT NOT NULL DEFAULT 1,
    round_name VARCHAR(100) NOT NULL, -- 'Technical Round 1', 'Managerial', 'HR Fit'
    scheduled_start TIMESTAMPTZ NOT NULL,
    scheduled_end TIMESTAMPTZ NOT NULL,
    interviewer_user_id UUID NULL,
    meeting_link VARCHAR(500) NULL,
    interview_status_code VARCHAR(30) NOT NULL DEFAULT 'scheduled', -- 'scheduled', 'completed', 'rescheduled', 'cancelled', 'no_show'
    feedback_summary TEXT NULL,
    rating_score INT NULL, -- 1 to 5 scale
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_interview_interviewer FOREIGN KEY (interviewer_user_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT chk_interview_time_window CHECK (scheduled_end > scheduled_start),
    CONSTRAINT chk_interview_rating CHECK (rating_score IS NULL OR (rating_score >= 1 AND rating_score <= 5))
);

CREATE INDEX IF NOT EXISTS idx_interview_app_id ON interview_schedule (application_id);
CREATE INDEX IF NOT EXISTS idx_interview_interviewer ON interview_schedule (interviewer_user_id, scheduled_start);

-- ----------------------------------------------------------------------------
-- Table: job_offer
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_offer (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id BIGINT NOT NULL,
    offer_letter_storage_path VARCHAR(500) NULL,
    offered_salary_amount DECIMAL(14, 2) NOT NULL,
    salary_currency CHAR(3) NOT NULL DEFAULT 'INR',
    joining_date DATE NOT NULL,
    acceptance_deadline DATE NOT NULL,
    offer_status_code VARCHAR(30) NOT NULL DEFAULT 'extended', -- 'draft', 'extended', 'accepted', 'declined', 'rescinded', 'expired'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT chk_offer_salary CHECK (offered_salary_amount > 0.00),
    CONSTRAINT chk_offer_dates CHECK (acceptance_deadline <= joining_date)
);

CREATE INDEX IF NOT EXISTS idx_job_offer_app_id ON job_offer (application_id);

-- ----------------------------------------------------------------------------
-- Table: placement_record (Successful hire record for billing and warranties)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS placement_record (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id BIGINT NOT NULL,
    actual_joined_date DATE NOT NULL,
    annual_compensation_amount DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    billing_rate_percentage DECIMAL(5, 2) NOT NULL DEFAULT 8.33,
    fee_invoiced_amount DECIMAL(14, 2) NOT NULL,
    guarantee_days INT NOT NULL DEFAULT 90,
    placement_status_code VARCHAR(30) NOT NULL DEFAULT 'active', -- 'active', 'retention_cleared', 'early_exit_clawback'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT chk_placement_comp CHECK (annual_compensation_amount > 0.00),
    CONSTRAINT chk_placement_fee CHECK (fee_invoiced_amount >= 0.00),
    CONSTRAINT chk_placement_guarantee CHECK (guarantee_days >= 0)
);

CREATE INDEX IF NOT EXISTS idx_placement_app_id ON placement_record (application_id);

-- ----------------------------------------------------------------------------
-- Table: recruiter_candidate_bookmark (Tier 2 Expected Domain)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recruiter_candidate_bookmark (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recruiter_user_id UUID NOT NULL,
    candidate_profile_id UUID NOT NULL,
    folder_name VARCHAR(100) NOT NULL DEFAULT 'Default',
    notes TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_bookmark_recruiter FOREIGN KEY (recruiter_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_bookmark_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT uq_recruiter_candidate_bookmark UNIQUE (recruiter_user_id, candidate_profile_id)
);

-- ----------------------------------------------------------------------------
-- Table: recruiter_job_shortlist (Tier 2 Expected Domain)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recruiter_job_shortlist (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_requirement_id UUID NOT NULL,
    candidate_profile_id UUID NOT NULL,
    shortlisted_by_user_id UUID NOT NULL,
    shortlist_stage VARCHAR(50) NOT NULL DEFAULT 'initial_review',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_shortlist_job FOREIGN KEY (job_requirement_id) REFERENCES job_requirement (id) ON DELETE CASCADE,
    CONSTRAINT fk_shortlist_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT fk_shortlist_user FOREIGN KEY (shortlisted_by_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_recruiter_job_shortlist UNIQUE (job_requirement_id, candidate_profile_id)
);
