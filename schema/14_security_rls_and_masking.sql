-- ============================================================================
-- Talentra Schema: 14_security_rls_and_masking.sql
-- Modules: Security, Privileges, Row Level Security (RLS) & PII Masking
-- Standards: Section 3 (Actors & Privileges), Rule Group 6 (Sensitive Data Classification),
--            Milestone 22 (B75, B76, B77, B78, B79)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Enable Row Level Security (RLS) on Core Protected Tables
-- ----------------------------------------------------------------------------
ALTER TABLE job_requirement ENABLE ROW LEVEL SECURITY;
ALTER TABLE candidate_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE candidate_application ENABLE ROW LEVEL SECURITY;
ALTER TABLE sourcing_request ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 2. Recruiter & Consultant Job Requirement Isolation Policies
-- Rule: "A recruiter may only see and act on job requirements assigned to their own company."
-- Rule: "A consultant may only work on job requirements that are open to consultants."
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS p_job_req_recruiter_isolation ON job_requirement;
CREATE POLICY p_job_req_recruiter_isolation ON job_requirement
FOR ALL
USING (
    -- Admin / SuperAdmin bypass
    current_setting('talentra.current_role', true) IN ('admin', 'super_admin')
    OR
    -- Recruiter sees only their own organisation's job requirements
    (
        current_setting('talentra.current_role', true) = 'recruiter'
        AND organisation_id = NULLIF(current_setting('talentra.current_org_id', true), '')::UUID
    )
    OR
    -- Consultant sees only published jobs that are open to consultants
    (
        current_setting('talentra.current_role', true) = 'consultant'
        AND is_open_to_consultants = TRUE
        AND publish_status_code = 'published'
        AND deleted_at IS NULL
    )
    OR
    -- Candidate sees only published jobs
    (
        current_setting('talentra.current_role', true) = 'candidate'
        AND publish_status_code = 'published'
        AND deleted_at IS NULL
    )
);

-- ----------------------------------------------------------------------------
-- 3. Candidate Profile Blocking Enforcement Policy (B50, B59)
-- Rule: "A candidate may block employers, recruiters, or consultants, and a
--        blocked party must not see that candidate."
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS p_candidate_profile_block_isolation ON candidate_profile;
CREATE POLICY p_candidate_profile_block_isolation ON candidate_profile
FOR ALL
USING (
    -- Admin / SuperAdmin bypass
    current_setting('talentra.current_role', true) IN ('admin', 'super_admin')
    OR
    -- Candidate always sees their own profile
    (
        user_id = NULLIF(current_setting('talentra.current_user_id', true), '')::UUID
    )
    OR
    -- Recruiters/Employers/Consultants can view UNLESS blocked
    (
        current_setting('talentra.current_role', true) IN ('recruiter', 'employer', 'consultant')
        AND is_actively_looking = TRUE
        AND deleted_at IS NULL
        -- Check 1: Must not be blocked at User Level (user_block_list)
        AND NOT EXISTS (
            SELECT 1 FROM user_block_list bl
            WHERE bl.blocker_user_id = candidate_profile.user_id
              AND bl.blocked_user_id = NULLIF(current_setting('talentra.current_user_id', true), '')::UUID
        )
        -- Check 2: Must not be blocked at Company Level (company_block_list)
        AND NOT EXISTS (
            SELECT 1 FROM company_block_list cbl
            WHERE cbl.candidate_user_id = candidate_profile.user_id
              AND cbl.blocked_organisation_id = NULLIF(current_setting('talentra.current_org_id', true), '')::UUID
        )
    )
);

-- ----------------------------------------------------------------------------
-- 4. Candidate Application Isolation Policy
-- Recruiter sees only applications for their company's jobs
-- Candidate sees only their own submitted applications
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS p_cand_app_isolation ON candidate_application;
CREATE POLICY p_cand_app_isolation ON candidate_application
FOR ALL
USING (
    -- Admin bypass
    current_setting('talentra.current_role', true) IN ('admin', 'super_admin')
    OR
    -- Recruiter sees only applications for jobs owned by their organisation
    (
        current_setting('talentra.current_role', true) = 'recruiter'
        AND EXISTS (
            SELECT 1 FROM job_requirement j
            WHERE j.id = candidate_application.job_requirement_id
              AND j.organisation_id = NULLIF(current_setting('talentra.current_org_id', true), '')::UUID
        )
    )
    OR
    -- Candidate sees only their own applications
    (
        current_setting('talentra.current_role', true) = 'candidate'
        AND EXISTS (
            SELECT 1 FROM candidate_profile cp
            WHERE cp.id = candidate_application.candidate_profile_id
              AND cp.user_id = NULLIF(current_setting('talentra.current_user_id', true), '')::UUID
        )
    )
);

-- ----------------------------------------------------------------------------
-- 5. Dynamic Data Masking Views (Rule Group 6: Sensitive Data)
-- Masks PII (email, phone, national tax IDs) for staff and non-privileged roles
-- ----------------------------------------------------------------------------

-- Masked Candidate View
CREATE OR REPLACE VIEW vw_candidate_profile_masked AS
SELECT 
    id,
    user_id,
    first_name,
    last_name,
    headline,
    -- Email Masking: j***@domain.com
    CONCAT(
        SUBSTRING(primary_email FROM 1 FOR 1),
        '***@',
        SPLIT_PART(primary_email, '@', 2)
    ) AS masked_email,
    -- Phone Masking: +91-XXXXX-9876
    CONCAT(
        COALESCE(primary_phone_country_code, '+91'),
        '-XXXXX-',
        RIGHT(primary_phone_number, 4)
    ) AS masked_phone,
    current_city_id,
    total_experience_months,
    current_salary_amount,
    current_salary_currency,
    expected_salary_amount,
    expected_salary_currency,
    notice_period_days,
    profile_summary,
    profile_completion_percentage,
    is_actively_looking,
    created_at,
    updated_at
FROM candidate_profile
WHERE deleted_at IS NULL;

-- Masked Organisation Tax View
CREATE OR REPLACE VIEW vw_organisation_tax_masked AS
SELECT 
    id,
    organisation_id,
    country_iso_code,
    identifier_type,
    -- Mask tax identifiers: Show first 2 and last 3 chars only
    CONCAT(
        SUBSTRING(identifier_value FROM 1 FOR 2),
        REPEAT('X', GREATEST(0, LENGTH(identifier_value) - 5)),
        RIGHT(identifier_value, 3)
    ) AS masked_tax_identifier,
    verification_status_code,
    verified_at
FROM organisation_tax_identifier;
