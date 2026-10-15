-- ============================================================================
-- Talentra Schema: 05_job_lifecycle_and_questionnaires.sql
-- Modules: Job Requirement Lifecycle (M03)
-- Standards: Rule Group 1 (snake_case, singular), Rule Group 2 (Keys/Constraints),
--            Rule Group 3 (Standard Domains), Rule Group 4 (Audit/Lifecycle)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: job_requirement
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_requirement (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    job_title VARCHAR(200) NOT NULL,
    job_role_id UUID NOT NULL,
    industry_id UUID NOT NULL,
    employment_type_id UUID NOT NULL,
    work_mode_id UUID NOT NULL,
    primary_city_id UUID NOT NULL,
    vacancies_count INT NOT NULL DEFAULT 1,
    min_experience_months INT NOT NULL DEFAULT 0,
    max_experience_months INT NOT NULL DEFAULT 0,
    min_salary_amount DECIMAL(14, 2) NULL,
    max_salary_amount DECIMAL(14, 2) NULL,
    salary_currency CHAR(3) NOT NULL DEFAULT 'INR',
    job_description TEXT NOT NULL,
    key_responsibilities TEXT NULL,
    publish_status_code VARCHAR(30) NOT NULL DEFAULT 'draft', -- 'draft', 'pending_approval', 'published', 'paused', 'closed', 'cancelled'
    is_open_to_consultants BOOLEAN NOT NULL DEFAULT FALSE,
    published_at TIMESTAMPTZ NULL,
    expires_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT fk_job_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT fk_job_role FOREIGN KEY (job_role_id) REFERENCES job_role (id) ON DELETE RESTRICT,
    CONSTRAINT fk_job_industry FOREIGN KEY (industry_id) REFERENCES industry (id) ON DELETE RESTRICT,
    CONSTRAINT fk_job_employment_type FOREIGN KEY (employment_type_id) REFERENCES employment_type (id) ON DELETE RESTRICT,
    CONSTRAINT fk_job_work_mode FOREIGN KEY (work_mode_id) REFERENCES work_mode (id) ON DELETE RESTRICT,
    CONSTRAINT fk_job_city FOREIGN KEY (primary_city_id) REFERENCES city (id) ON DELETE RESTRICT,
    CONSTRAINT chk_job_vacancies CHECK (vacancies_count > 0),
    CONSTRAINT chk_job_experience_range CHECK (max_experience_months >= min_experience_months),
    CONSTRAINT chk_job_salary_range CHECK (
        (min_salary_amount IS NULL AND max_salary_amount IS NULL) OR
        (min_salary_amount IS NOT NULL AND max_salary_amount IS NOT NULL AND max_salary_amount >= min_salary_amount)
    )
);

CREATE INDEX IF NOT EXISTS idx_job_req_org_id ON job_requirement (organisation_id);
CREATE INDEX IF NOT EXISTS idx_job_req_publish_lookup ON job_requirement (publish_status_code, is_open_to_consultants) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_job_req_role_city ON job_requirement (job_role_id, primary_city_id);

-- ----------------------------------------------------------------------------
-- Table: job_position (Positions associated with a requirement)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_position (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_requirement_id UUID NOT NULL,
    position_code VARCHAR(50) NOT NULL,
    status_code VARCHAR(30) NOT NULL DEFAULT 'open', -- 'open', 'interviewing', 'offered', 'filled', 'cancelled'
    filled_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_position_job FOREIGN KEY (job_requirement_id) REFERENCES job_requirement (id) ON DELETE CASCADE,
    CONSTRAINT uq_job_position_code UNIQUE (job_requirement_id, position_code)
);

CREATE INDEX IF NOT EXISTS idx_job_position_job_id ON job_position (job_requirement_id);

-- ----------------------------------------------------------------------------
-- Table: job_requirement_skill
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_requirement_skill (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_requirement_id UUID NOT NULL,
    skill_id UUID NOT NULL,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    min_experience_months INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT fk_job_skill_job FOREIGN KEY (job_requirement_id) REFERENCES job_requirement (id) ON DELETE CASCADE,
    CONSTRAINT fk_job_skill_skill FOREIGN KEY (skill_id) REFERENCES skill (id) ON DELETE RESTRICT,
    CONSTRAINT uq_job_requirement_skill UNIQUE (job_requirement_id, skill_id),
    CONSTRAINT chk_job_skill_exp CHECK (min_experience_months >= 0)
);

CREATE INDEX IF NOT EXISTS idx_job_skill_skill_id ON job_requirement_skill (skill_id);

-- ----------------------------------------------------------------------------
-- Table: job_questionnaire
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_questionnaire (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_requirement_id UUID NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NULL,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_questionnaire_job FOREIGN KEY (job_requirement_id) REFERENCES job_requirement (id) ON DELETE CASCADE,
    CONSTRAINT uq_job_questionnaire UNIQUE (job_requirement_id)
);

-- ----------------------------------------------------------------------------
-- Table: job_questionnaire_question
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_questionnaire_question (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_questionnaire_id UUID NOT NULL,
    question_text TEXT NOT NULL,
    question_type VARCHAR(30) NOT NULL DEFAULT 'text', -- 'single_choice', 'multiple_choice', 'text', 'numeric', 'boolean'
    options_payload JSONB NULL,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_question_questionnaire FOREIGN KEY (job_questionnaire_id) REFERENCES job_questionnaire (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_question_questionnaire_id ON job_questionnaire_question (job_questionnaire_id, sort_order);
