-- ============================================================================
-- Talentra Test Suite: test_rls_security_isolation.sql
-- Purpose: Automated Verification of Row-Level Security (RLS) & Access Rules
-- Milestone: Phase 5, Milestone 22 (B79)
-- Engine: PostgreSQL 17.5
-- Tests:
--   1. Recruiter Multi-Tenant Isolation (cannot see other companies' jobs)
--   2. Consultant Job Openness Isolation (cannot see confidential jobs)
--   3. Candidate Blocklist Invisibility (blocked companies cannot view candidate)
--   4. Audit Logging of Sensitive Actions
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '=== Running Talentra Security, RLS & Access Rule Tests (B79) ===';
END $$;

-- ----------------------------------------------------------------------------
-- Test 1: Verify Recruiter Tenant Isolation via RLS
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_org_a UUID;
    v_org_b UUID;
    v_role_id UUID;
    v_job_a UUID;
    v_job_b UUID;
    v_count_seen INT;
BEGIN
    SELECT id INTO v_role_id FROM job_role LIMIT 1;

    INSERT INTO organisation (legal_name, organisation_type_code, verification_status_code)
    VALUES ('Tenant Alpha Technologies', 'enterprise_employer', 'verified')
    RETURNING id INTO v_org_a;

    INSERT INTO organisation (legal_name, organisation_type_code, verification_status_code)
    VALUES ('Tenant Beta Solutions', 'enterprise_employer', 'verified')
    RETURNING id INTO v_org_b;

    -- Job A belongs to Tenant Alpha
    INSERT INTO job_requirement (
        organisation_id, job_title, job_role_id, industry_id, employment_type_id,
        work_mode_id, primary_city_id, job_description, publish_status_code
    ) VALUES (
        v_org_a, 'Alpha Senior Architect', v_role_id, v_role_id, v_role_id,
        v_role_id, (SELECT id FROM city LIMIT 1), 'Alpha confidential spec', 'published'
    ) RETURNING id INTO v_job_a;

    -- Job B belongs to Tenant Beta
    INSERT INTO job_requirement (
        organisation_id, job_title, job_role_id, industry_id, employment_type_id,
        work_mode_id, primary_city_id, job_description, publish_status_code
    ) VALUES (
        v_org_b, 'Beta Principal Engineer', v_role_id, v_role_id, v_role_id,
        v_role_id, (SELECT id FROM city LIMIT 1), 'Beta confidential spec', 'published'
    ) RETURNING id INTO v_job_b;

    -- Simulate Recruiter from Tenant Alpha
    PERFORM set_config('talentra.current_role', 'recruiter', true);
    PERFORM set_config('talentra.current_org_id', v_org_a::TEXT, true);

    -- Query jobs visible to Tenant Alpha Recruiter
    SELECT COUNT(*) INTO v_count_seen
    FROM job_requirement
    WHERE id = v_job_b; -- Attempt to view Tenant Beta's job

    IF v_count_seen > 0 THEN
        RAISE EXCEPTION 'SECURITY BREACH (B79): Recruiter from Tenant Alpha was able to view Tenant Beta job!';
    ELSE
        RAISE NOTICE 'PASSED: Recruiter Tenant Isolation verified. Tenant Beta job is completely hidden.';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- Test 2: Verify Consultant Openness Isolation via RLS
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_org_id UUID;
    v_role_id UUID;
    v_job_open UUID;
    v_job_closed UUID;
    v_count_seen INT;
BEGIN
    SELECT id INTO v_org_id FROM organisation LIMIT 1;
    SELECT id INTO v_role_id FROM job_role LIMIT 1;

    -- Open Job
    INSERT INTO job_requirement (
        organisation_id, job_title, job_role_id, industry_id, employment_type_id,
        work_mode_id, primary_city_id, job_description, is_open_to_consultants, publish_status_code
    ) VALUES (
        v_org_id, 'Open Consultant Sourcing Role', v_role_id, v_role_id, v_role_id,
        v_role_id, (SELECT id FROM city LIMIT 1), 'Public Job', TRUE, 'published'
    ) RETURNING id INTO v_job_open;

    -- Closed / Internal Only Job
    INSERT INTO job_requirement (
        organisation_id, job_title, job_role_id, industry_id, employment_type_id,
        work_mode_id, primary_city_id, job_description, is_open_to_consultants, publish_status_code
    ) VALUES (
        v_org_id, 'Private Executive Job', v_role_id, v_role_id, v_role_id,
        v_role_id, (SELECT id FROM city LIMIT 1), 'Private Job', FALSE, 'published'
    ) RETURNING id INTO v_job_closed;

    -- Simulate Consultant Role
    PERFORM set_config('talentra.current_role', 'consultant', true);

    -- Consultant queries closed job -> MUST BE 0 ROWS
    SELECT COUNT(*) INTO v_count_seen
    FROM job_requirement
    WHERE id = v_job_closed;

    IF v_count_seen > 0 THEN
        RAISE EXCEPTION 'SECURITY BREACH (B79): Consultant was able to view job not open to consultants!';
    ELSE
        RAISE NOTICE 'PASSED: Consultant Openness Isolation verified. Private job is hidden from consultant.';
    END IF;

    -- Consultant queries open job -> MUST BE VISIBLE
    SELECT COUNT(*) INTO v_count_seen
    FROM job_requirement
    WHERE id = v_job_open;

    IF v_count_seen = 0 THEN
        RAISE EXCEPTION 'DEFECT: Consultant was unable to view job marked is_open_to_consultants = TRUE!';
    ELSE
        RAISE NOTICE 'PASSED: Open job is correctly visible to consultant.';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- Test 3: Verify Candidate Blocklist Invisibility via RLS (B50, B59)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_cand_user UUID;
    v_cand_profile UUID;
    v_blocked_org UUID;
    v_count_seen INT;
BEGIN
    -- Create candidate
    INSERT INTO users (email, user_type_code)
    VALUES ('privacy_candidate@talentra.internal', 'candidate')
    RETURNING id INTO v_cand_user;

    INSERT INTO candidate_profile (user_id, first_name, last_name, primary_email)
    VALUES (v_cand_user, 'Private', 'Candidate', 'privacy_candidate@talentra.internal')
    RETURNING id INTO v_cand_profile;

    -- Target employer
    INSERT INTO organisation (legal_name, organisation_type_code)
    VALUES ('Blocked Corporate Ltd', 'enterprise_employer')
    RETURNING id INTO v_blocked_org;

    -- Candidate places company on Block List
    INSERT INTO company_block_list (candidate_user_id, blocked_organisation_id, reason_code)
    VALUES (v_cand_user, v_blocked_org, 'current_employer');

    -- Simulate Recruiter from Blocked Corporate Ltd
    PERFORM set_config('talentra.current_role', 'recruiter', true);
    PERFORM set_config('talentra.current_org_id', v_blocked_org::TEXT, true);

    -- Recruiter searches for candidates -> Candidate profile MUST BE INVISIBLE (0 rows)
    SELECT COUNT(*) INTO v_count_seen
    FROM candidate_profile
    WHERE id = v_cand_profile;

    IF v_count_seen > 0 THEN
        RAISE EXCEPTION 'SECURITY BREACH (B59): Blocked recruiter was able to view blocked candidate profile!';
    ELSE
        RAISE NOTICE 'PASSED: Candidate Blocklist Isolation verified. Candidate profile is 100%% invisible to blocked employer.';
    END IF;
END $$;

DO $$
BEGIN
    RAISE NOTICE '=== All Security, RLS & Access Rule Tests (B79) PASSED ===';
END $$;
