-- ============================================================================
-- Talentra Schema: 04_candidate_profile_and_resumes.sql
-- Modules: Candidate Profile (M02), Tier 2 Expected Domains
-- Standards: Rule Group 1 (snake_case, singular), Rule Group 2 (Keys/Constraints),
--            Rule Group 3 (Standard Domains), Rule Group 4 (Audit/Lifecycle),
--            Rule Group 6 (Sensitive/Personal Data Classification)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: candidate_profile
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_profile (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    first_name VARCHAR(150) NOT NULL,
    last_name VARCHAR(150) NOT NULL,
    headline VARCHAR(250) NULL,
    date_of_birth DATE NULL,
    gender_code VARCHAR(20) NOT NULL DEFAULT 'undisclosed', -- 'male', 'female', 'non_binary', 'undisclosed'
    primary_email VARCHAR(254) NOT NULL,
    primary_phone_country_code VARCHAR(10) NULL,
    primary_phone_number VARCHAR(20) NULL,
    current_city_id UUID NULL,
    total_experience_months INT NOT NULL DEFAULT 0,
    current_salary_amount DECIMAL(14, 2) NULL,
    current_salary_currency CHAR(3) NOT NULL DEFAULT 'INR',
    expected_salary_amount DECIMAL(14, 2) NULL,
    expected_salary_currency CHAR(3) NOT NULL DEFAULT 'INR',
    notice_period_days INT NOT NULL DEFAULT 30,
    profile_summary TEXT NULL,
    profile_completion_percentage INT NOT NULL DEFAULT 0,
    is_actively_looking BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT fk_candidate_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_candidate_city FOREIGN KEY (current_city_id) REFERENCES city (id) ON DELETE SET NULL,
    CONSTRAINT uq_candidate_profile_user UNIQUE (user_id),
    CONSTRAINT chk_candidate_exp_months CHECK (total_experience_months >= 0),
    CONSTRAINT chk_candidate_completion CHECK (profile_completion_percentage >= 0 AND profile_completion_percentage <= 100),
    CONSTRAINT chk_candidate_notice_period CHECK (notice_period_days >= 0)
);

CREATE INDEX IF NOT EXISTS idx_candidate_city ON candidate_profile (current_city_id);
CREATE INDEX IF NOT EXISTS idx_candidate_exp ON candidate_profile (total_experience_months);
CREATE INDEX IF NOT EXISTS idx_candidate_active_lookup ON candidate_profile (is_actively_looking) WHERE deleted_at IS NULL;

-- ----------------------------------------------------------------------------
-- Table: candidate_contact_detail
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_contact_detail (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_profile_id UUID NOT NULL,
    contact_type VARCHAR(30) NOT NULL, -- 'alternate_email', 'secondary_phone', 'linkedin_url', 'github_url', 'portfolio_url'
    contact_value VARCHAR(255) NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_contact_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_candidate_contact ON candidate_contact_detail (candidate_profile_id);

-- ----------------------------------------------------------------------------
-- Table: candidate_education (Rule Group 2 & 3: Temporal date check)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_education (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_profile_id UUID NOT NULL,
    qualification_id UUID NOT NULL,
    institution_name VARCHAR(200) NOT NULL,
    field_of_study VARCHAR(150) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NULL,
    grade_or_percentage VARCHAR(30) NULL,
    is_highest_qualification BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_education_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT fk_education_qualification FOREIGN KEY (qualification_id) REFERENCES qualification (id) ON DELETE RESTRICT,
    CONSTRAINT chk_education_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_candidate_education_profile ON candidate_education (candidate_profile_id);

-- ----------------------------------------------------------------------------
-- Table: candidate_experience (Rule Group 2 & 3: Check end_date >= start_date)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_experience (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_profile_id UUID NOT NULL,
    company_name VARCHAR(200) NOT NULL,
    job_title VARCHAR(150) NOT NULL,
    job_role_id UUID NULL,
    employment_type_id UUID NULL,
    start_date DATE NOT NULL,
    end_date DATE NULL,
    is_current_job BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_experience_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT fk_experience_job_role FOREIGN KEY (job_role_id) REFERENCES job_role (id) ON DELETE SET NULL,
    CONSTRAINT fk_experience_emp_type FOREIGN KEY (employment_type_id) REFERENCES employment_type (id) ON DELETE SET NULL,
    CONSTRAINT chk_experience_dates CHECK (is_current_job = TRUE OR (end_date IS NOT NULL AND end_date >= start_date))
);

CREATE INDEX IF NOT EXISTS idx_candidate_exp_profile ON candidate_experience (candidate_profile_id);
CREATE INDEX IF NOT EXISTS idx_candidate_exp_role ON candidate_experience (job_role_id);

-- ----------------------------------------------------------------------------
-- Table: candidate_skill
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_skill (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_profile_id UUID NOT NULL,
    skill_id UUID NOT NULL,
    proficiency_level VARCHAR(30) NOT NULL DEFAULT 'intermediate', -- 'beginner', 'intermediate', 'advanced', 'expert'
    experience_months INT NOT NULL DEFAULT 0,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_candidate_skill_profile FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT fk_candidate_skill_skill FOREIGN KEY (skill_id) REFERENCES skill (id) ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_skill UNIQUE (candidate_profile_id, skill_id),
    CONSTRAINT chk_candidate_skill_exp CHECK (experience_months >= 0)
);

CREATE INDEX IF NOT EXISTS idx_candidate_skill_skill_id ON candidate_skill (skill_id);

-- ----------------------------------------------------------------------------
-- Table: candidate_language
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_language (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_profile_id UUID NOT NULL,
    language_id UUID NOT NULL,
    proficiency_level VARCHAR(30) NOT NULL DEFAULT 'professional_working', -- 'elementary', 'limited_working', 'professional_working', 'full_professional', 'native_bilingual'
    can_read BOOLEAN NOT NULL DEFAULT TRUE,
    can_write BOOLEAN NOT NULL DEFAULT TRUE,
    can_speak BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_candidate_lang_profile FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT fk_candidate_lang_lang FOREIGN KEY (language_id) REFERENCES language_lookup (id) ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_language UNIQUE (candidate_profile_id, language_id)
);

-- ----------------------------------------------------------------------------
-- Table: candidate_project
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_project (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_profile_id UUID NOT NULL,
    project_title VARCHAR(200) NOT NULL,
    client_or_institution VARCHAR(200) NULL,
    role_description VARCHAR(150) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NULL,
    project_outcome TEXT NULL,
    project_url VARCHAR(255) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_project_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT chk_project_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_candidate_project_profile ON candidate_project (candidate_profile_id);

-- ----------------------------------------------------------------------------
-- Table: resume_template
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS resume_template (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'modern', -- 'modern', 'executive', 'technical', 'academic'
    layout_structure JSONB NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_resume_template_name UNIQUE (name)
);

-- ----------------------------------------------------------------------------
-- Table: candidate_resume_version
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_resume_version (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id UUID NOT NULL,
    resume_template_id UUID NULL,
    version_number INT NOT NULL DEFAULT 1,
    resume_title VARCHAR(150) NOT NULL,
    file_storage_path VARCHAR(500) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL DEFAULT 'application/pdf',
    parsed_text TEXT NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT fk_resume_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT fk_resume_template FOREIGN KEY (resume_template_id) REFERENCES resume_template (id) ON DELETE SET NULL,
    CONSTRAINT chk_resume_file_size CHECK (file_size_bytes > 0)
);

CREATE INDEX IF NOT EXISTS idx_resume_candidate_profile ON candidate_resume_version (candidate_profile_id);

-- ----------------------------------------------------------------------------
-- Table: candidate_activity_log (Tier 2 Expected Domain)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_activity_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id UUID NOT NULL,
    activity_type VARCHAR(50) NOT NULL, -- 'login', 'profile_update', 'resume_download', 'job_view', 'search_executed'
    activity_metadata JSONB NULL,
    ip_address VARCHAR(45) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_activity_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_candidate_activity ON candidate_activity_log (candidate_profile_id, created_at);
