-- ============================================================================
-- Talentra Test Suite: test_domain_rules_and_constraints.sql
-- Purpose: Automated validation of domain rules, keys, and constraints
-- Standards: Rule Groups 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '=== Running Talentra Domain Rules & Constraints Tests ===';
END $$;

-- ----------------------------------------------------------------------------
-- Test 1: Verify Check Constraints on Experience & Salary Ranges (Job Requirement)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_org_id UUID;
    v_role_id UUID;
    v_ind_id UUID;
    v_emp_type_id UUID;
    v_work_mode_id UUID;
    v_city_id UUID;
    v_job_id UUID;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    -- Setup dummy references if not present
    SELECT id INTO v_ind_id FROM industry LIMIT 1;
    IF v_ind_id IS NULL THEN
        INSERT INTO industry (code, name) VALUES ('TECH', 'Technology') RETURNING id INTO v_ind_id;
    END IF;

    SELECT id INTO v_role_id FROM job_role LIMIT 1;
    IF v_role_id IS NULL THEN
        INSERT INTO job_role (industry_id, code, title) VALUES (v_ind_id, 'SWE', 'Software Engineer') RETURNING id INTO v_role_id;
    END IF;

    SELECT id INTO v_emp_type_id FROM employment_type LIMIT 1;
    IF v_emp_type_id IS NULL THEN
        INSERT INTO employment_type (code, name) VALUES ('FT', 'Full Time') RETURNING id INTO v_emp_type_id;
    END IF;

    SELECT id INTO v_work_mode_id FROM work_mode LIMIT 1;
    IF v_work_mode_id IS NULL THEN
        INSERT INTO work_mode (code, name) VALUES ('REMOTE', 'Remote') RETURNING id INTO v_work_mode_id;
    END IF;

    -- Country, State, City
    DECLARE
        v_c_id UUID;
        v_s_id UUID;
    BEGIN
        SELECT id INTO v_c_id FROM country LIMIT 1;
        IF v_c_id IS NULL THEN
            INSERT INTO country (iso_code_2, iso_code_3, name, phone_dial_code, default_currency_code)
            VALUES ('IN', 'IND', 'India', '+91', 'INR') RETURNING id INTO v_c_id;
        END IF;

        SELECT id INTO v_s_id FROM state_province LIMIT 1;
        IF v_s_id IS NULL THEN
            INSERT INTO state_province (country_id, code, name) VALUES (v_c_id, 'KA', 'Karnataka') RETURNING id INTO v_s_id;
        END IF;

        SELECT id INTO v_city_id FROM city LIMIT 1;
        IF v_city_id IS NULL THEN
            INSERT INTO city (state_province_id, name, latitude, longitude) VALUES (v_s_id, 'Bengaluru', 12.9716, 77.5946) RETURNING id INTO v_city_id;
        END IF;
    END;

    SELECT id INTO v_org_id FROM organisation LIMIT 1;
    IF v_org_id IS NULL THEN
        INSERT INTO organisation (legal_name, organisation_type_code) VALUES ('Talentra Test Corp', 'enterprise_employer') RETURNING id INTO v_org_id;
    END IF;

    -- Test Negative: min_salary > max_salary should FAIL
    BEGIN
        INSERT INTO job_requirement (
            organisation_id, job_title, job_role_id, industry_id, employment_type_id,
            work_mode_id, primary_city_id, min_experience_months, max_experience_months,
            min_salary_amount, max_salary_amount, job_description
        ) VALUES (
            v_org_id, 'Senior Backend Dev', v_role_id, v_ind_id, v_emp_type_id,
            v_work_mode_id, v_city_id, 24, 60,
            1500000.00, 1000000.00, -- Invalid: min > max
            'Detailed job description'
        );
    EXCEPTION WHEN check_violation THEN
        v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'FAILED: chk_job_salary_range allowed min_salary > max_salary!';
    ELSE
        RAISE NOTICE 'PASSED: chk_job_salary_range properly rejected min_salary > max_salary.';
    END IF;

    -- Test Negative: max_experience < min_experience should FAIL
    v_error_caught := FALSE;
    BEGIN
        INSERT INTO job_requirement (
            organisation_id, job_title, job_role_id, industry_id, employment_type_id,
            work_mode_id, primary_city_id, min_experience_months, max_experience_months,
            min_salary_amount, max_salary_amount, job_description
        ) VALUES (
            v_org_id, 'Dev', v_role_id, v_ind_id, v_emp_type_id,
            v_work_mode_id, v_city_id, 48, 12, -- Invalid: min > max
            800000.00, 1200000.00,
            'Detailed job description'
        );
    EXCEPTION WHEN check_violation THEN
        v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'FAILED: chk_job_experience_range allowed max_experience < min_experience!';
    ELSE
        RAISE NOTICE 'PASSED: chk_job_experience_range properly rejected max_experience < min_experience.';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- Test 2: Verify Audit Log Append-Only Protection (Rule Group 4)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_audit_id BIGINT;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    INSERT INTO audit_log (entity_name, entity_id, action_type)
    VALUES ('test_entity', 'test_123', 'INSERT')
    RETURNING id INTO v_audit_id;

    -- Attempt UPDATE on audit_log -> MUST FAIL
    BEGIN
        UPDATE audit_log SET action_type = 'TAMPERED' WHERE id = v_audit_id;
    EXCEPTION WHEN OTHERS THEN
        v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'FAILED: audit_log allowed UPDATE operation!';
    ELSE
        RAISE NOTICE 'PASSED: audit_log correctly blocked UPDATE attempt.';
    END IF;

    -- Attempt DELETE on audit_log -> MUST FAIL
    v_error_caught := FALSE;
    BEGIN
        DELETE FROM audit_log WHERE id = v_audit_id;
    EXCEPTION WHEN OTHERS THEN
        v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'FAILED: audit_log allowed DELETE operation!';
    ELSE
        RAISE NOTICE 'PASSED: audit_log correctly blocked DELETE attempt.';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- Test 3: Verify Interview Schedule End > Start Check (Rule Group 3)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_error_caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        INSERT INTO interview_schedule (
            application_id, round_name, scheduled_start, scheduled_end
        ) VALUES (
            1, 'Technical Round',
            '2026-10-15 15:00:00+00',
            '2026-10-15 14:00:00+00' -- Invalid: end before start
        );
    EXCEPTION WHEN check_violation THEN
        v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'FAILED: interview_schedule allowed end time before start time!';
    ELSE
        RAISE NOTICE 'PASSED: interview_schedule correctly rejected end time before start time.';
    END IF;
END $$;

DO $$
BEGIN
    RAISE NOTICE '=== All Phase 1 Domain Rules & Constraints Tests PASSED ===';
END $$;
