-- ============================================================================
-- Talentra Schema: 09_sourcing_and_consultants.sql
-- Modules: Sourcing and Consultant Requests (M08) - Phase 3 (Milestones 11-14; B37, B40, B43, B46)
-- Standards: Rule Group 1, 2, 3, 4
-- Key Feature: B46 Consultant can act ONLY on a requirement open to consultants
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: sourcing_request (Consultant requests to source for an employer job)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sourcing_request (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_requirement_id UUID NOT NULL,
    consultant_user_id UUID NOT NULL,
    employer_organisation_id UUID NOT NULL,
    request_direction_code VARCHAR(30) NOT NULL DEFAULT 'consultant_to_employer', -- 'consultant_to_employer', 'employer_to_consultant'
    status_code VARCHAR(30) NOT NULL DEFAULT 'pending', -- 'pending', 'accepted', 'declined', 'withdrawn', 'completed'
    proposed_commission_rate DECIMAL(5, 2) NULL,
    terms_note TEXT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMPTZ NULL,
    response_reason_note TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_sourcing_job FOREIGN KEY (job_requirement_id) REFERENCES job_requirement (id) ON DELETE CASCADE,
    CONSTRAINT fk_sourcing_consultant FOREIGN KEY (consultant_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_sourcing_org FOREIGN KEY (employer_organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT uq_sourcing_request UNIQUE (job_requirement_id, consultant_user_id),
    CONSTRAINT chk_commission_rate CHECK (proposed_commission_rate IS NULL OR (proposed_commission_rate >= 0.00 AND proposed_commission_rate <= 100.00))
);

CREATE INDEX IF NOT EXISTS idx_sourcing_req_job ON sourcing_request (job_requirement_id);
CREATE INDEX IF NOT EXISTS idx_sourcing_req_consultant ON sourcing_request (consultant_user_id);
CREATE INDEX IF NOT EXISTS idx_sourcing_req_org ON sourcing_request (employer_organisation_id);

-- ----------------------------------------------------------------------------
-- Trigger: Enforce Consultant Openness Rule (B46)
-- A consultant can act only on a requirement open to consultants
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_enforce_consultant_openness()
RETURNS TRIGGER AS $$
DECLARE
    v_is_open BOOLEAN;
    v_publish_status VARCHAR(30);
BEGIN
    SELECT is_open_to_consultants, publish_status_code
    INTO v_is_open, v_publish_status
    FROM job_requirement
    WHERE id = NEW.job_requirement_id;

    IF v_is_open IS NOT TRUE THEN
        RAISE EXCEPTION 'Constraint Violation (B46): Job requirement % is not open to consultants.', NEW.job_requirement_id;
    END IF;

    IF v_publish_status <> 'published' THEN
        RAISE EXCEPTION 'Constraint Violation (B46): Job requirement % is not in published status (status: %).', NEW.job_requirement_id, v_publish_status;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_consultant_openness ON sourcing_request;
CREATE TRIGGER trg_check_consultant_openness
BEFORE INSERT ON sourcing_request
FOR EACH ROW EXECUTE FUNCTION fn_enforce_consultant_openness();

-- ----------------------------------------------------------------------------
-- Table: sourcing_candidate_shortlist
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sourcing_candidate_shortlist (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sourcing_request_id UUID NOT NULL,
    candidate_profile_id UUID NOT NULL,
    consultant_recommendation_note TEXT NULL,
    submission_status_code VARCHAR(30) NOT NULL DEFAULT 'submitted', -- 'submitted', 'reviewed_by_employer', 'interviewed', 'hired', 'rejected'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT fk_sourcing_shortlist_req FOREIGN KEY (sourcing_request_id) REFERENCES sourcing_request (id) ON DELETE CASCADE,
    CONSTRAINT fk_sourcing_shortlist_cand FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT uq_sourcing_candidate UNIQUE (sourcing_request_id, candidate_profile_id)
);

CREATE INDEX IF NOT EXISTS idx_sourcing_shortlist_cand ON sourcing_candidate_shortlist (candidate_profile_id);

-- ----------------------------------------------------------------------------
-- Table: bulk_outreach_batch
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bulk_outreach_batch (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_user_id UUID NOT NULL,
    organisation_id UUID NOT NULL,
    job_requirement_id UUID NULL,
    campaign_name VARCHAR(200) NOT NULL,
    channel_type_code VARCHAR(30) NOT NULL DEFAULT 'email', -- 'email', 'sms', 'platform_message', 'whatsapp'
    message_subject VARCHAR(255) NULL,
    message_template_body TEXT NOT NULL,
    total_recipients_count INT NOT NULL DEFAULT 0,
    credits_deducted_amount DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    batch_status_code VARCHAR(30) NOT NULL DEFAULT 'queued', -- 'queued', 'processing', 'completed', 'partially_failed'
    dispatched_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_outreach_sender FOREIGN KEY (sender_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_outreach_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT fk_outreach_job FOREIGN KEY (job_requirement_id) REFERENCES job_requirement (id) ON DELETE SET NULL,
    CONSTRAINT chk_outreach_recipients CHECK (total_recipients_count >= 0),
    CONSTRAINT chk_outreach_credits CHECK (credits_deducted_amount >= 0.00)
);

CREATE INDEX IF NOT EXISTS idx_bulk_outreach_org ON bulk_outreach_batch (organisation_id);

-- ----------------------------------------------------------------------------
-- Table: bulk_outreach_recipient
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bulk_outreach_recipient (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bulk_outreach_batch_id UUID NOT NULL,
    candidate_profile_id UUID NOT NULL,
    delivery_status_code VARCHAR(30) NOT NULL DEFAULT 'pending', -- 'pending', 'sent', 'delivered', 'opened', 'clicked', 'responded', 'bounced'
    sent_at TIMESTAMPTZ NULL,
    opened_at TIMESTAMPTZ NULL,
    responded_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_outreach_recip_batch FOREIGN KEY (bulk_outreach_batch_id) REFERENCES bulk_outreach_batch (id) ON DELETE CASCADE,
    CONSTRAINT fk_outreach_recip_cand FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE CASCADE,
    CONSTRAINT uq_outreach_batch_cand UNIQUE (bulk_outreach_batch_id, candidate_profile_id)
);

CREATE INDEX IF NOT EXISTS idx_outreach_recip_cand ON bulk_outreach_recipient (candidate_profile_id);
