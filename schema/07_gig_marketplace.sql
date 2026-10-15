-- ============================================================================
-- Talentra Schema: 07_gig_marketplace.sql
-- Modules: Gig Marketplace (M06) - Phase 2 (Milestones 7, 8, 9, 10; B26, B29, B32, B35)
-- Standards: Rule Group 1 (snake_case, singular), Rule Group 2 (Keys/Constraints),
--            Rule Group 3 (Standard Domains), Rule Group 4 (Audit/Lifecycle),
--            Rule Group 10 (Money and constraints)
-- Key Feature: PostgreSQL EXCLUDE USING gist to enforce that gig windows cannot
--              overlap for the same gig worker (Backlog B35).
-- ============================================================================

-- Ensure btree_gist extension is available
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ----------------------------------------------------------------------------
-- Table: gig_worker_profile
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gig_worker_profile (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    professional_headline VARCHAR(200) NOT NULL,
    profile_bio TEXT NULL,
    hourly_rate_amount DECIMAL(10, 2) NOT NULL,
    hourly_rate_currency CHAR(3) NOT NULL DEFAULT 'INR',
    daily_rate_amount DECIMAL(10, 2) NULL,
    primary_service_offering VARCHAR(255) NOT NULL,
    total_completed_gigs INT NOT NULL DEFAULT 0,
    average_rating DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    is_available_for_hire BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT fk_gig_worker_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_gig_worker_user UNIQUE (user_id),
    CONSTRAINT chk_gig_hourly_rate CHECK (hourly_rate_amount > 0.00),
    CONSTRAINT chk_gig_daily_rate CHECK (daily_rate_amount IS NULL OR daily_rate_amount > 0.00),
    CONSTRAINT chk_gig_rating CHECK (average_rating >= 0.00 AND average_rating <= 5.00),
    CONSTRAINT chk_gig_completed CHECK (total_completed_gigs >= 0)
);

CREATE INDEX IF NOT EXISTS idx_gig_worker_service ON gig_worker_profile (primary_service_offering);
CREATE INDEX IF NOT EXISTS idx_gig_worker_availability ON gig_worker_profile (is_available_for_hire) WHERE deleted_at IS NULL;

-- ----------------------------------------------------------------------------
-- Table: gig_availability_window (Worker's explicit working calendar slots)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gig_availability_window (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gig_worker_profile_id UUID NOT NULL,
    available_window TSTZRANGE NOT NULL,
    notes VARCHAR(255) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT fk_gig_avail_worker FOREIGN KEY (gig_worker_profile_id) REFERENCES gig_worker_profile (id) ON DELETE CASCADE,
    CONSTRAINT ex_gig_avail_no_overlap EXCLUDE USING gist (
        gig_worker_profile_id WITH =,
        available_window WITH &&
    )
);

CREATE INDEX IF NOT EXISTS idx_gig_avail_worker ON gig_availability_window (gig_worker_profile_id);

-- ----------------------------------------------------------------------------
-- Table: gig_request (Requisitions for short-duration project/gig work)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gig_request (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    project_category VARCHAR(100) NOT NULL,
    pricing_type_code VARCHAR(30) NOT NULL DEFAULT 'fixed_price', -- 'fixed_price', 'hourly_rate', 'milestone_based'
    budget_amount DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    gig_window TSTZRANGE NOT NULL,
    required_skills_summary VARCHAR(500) NULL,
    status_code VARCHAR(30) NOT NULL DEFAULT 'open', -- 'open', 'assigned', 'in_progress', 'completed', 'cancelled'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT fk_gig_req_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT chk_gig_budget CHECK (budget_amount > 0.00)
);

CREATE INDEX IF NOT EXISTS idx_gig_request_org ON gig_request (organisation_id);
CREATE INDEX IF NOT EXISTS idx_gig_request_status ON gig_request (status_code) WHERE deleted_at IS NULL;

-- ----------------------------------------------------------------------------
-- Table: gig_application (Unidirectional: Workers apply to gig requests)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gig_application (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gig_request_id UUID NOT NULL,
    gig_worker_profile_id UUID NOT NULL,
    bid_amount DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    pitch_note TEXT NULL,
    application_status_code VARCHAR(30) NOT NULL DEFAULT 'submitted', -- 'submitted', 'shortlisted', 'accepted', 'rejected', 'withdrawn'
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_gig_app_request FOREIGN KEY (gig_request_id) REFERENCES gig_request (id) ON DELETE CASCADE,
    CONSTRAINT fk_gig_app_worker FOREIGN KEY (gig_worker_profile_id) REFERENCES gig_worker_profile (id) ON DELETE RESTRICT,
    CONSTRAINT uq_gig_application UNIQUE (gig_request_id, gig_worker_profile_id),
    CONSTRAINT chk_gig_bid_amount CHECK (bid_amount > 0.00)
);

CREATE INDEX IF NOT EXISTS idx_gig_app_request ON gig_application (gig_request_id);
CREATE INDEX IF NOT EXISTS idx_gig_app_worker ON gig_application (gig_worker_profile_id);

-- ----------------------------------------------------------------------------
-- Table: gig_assignment
-- Milestone 10: B35 - Gig windows cannot overlap for the same gig worker
-- Enforced via EXCLUDE USING gist (gig_worker_profile_id WITH =, assignment_window WITH &&)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gig_assignment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gig_request_id UUID NOT NULL,
    gig_worker_profile_id UUID NOT NULL,
    gig_application_id UUID NOT NULL,
    agreed_amount DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    assignment_window TSTZRANGE NOT NULL,
    assignment_status_code VARCHAR(30) NOT NULL DEFAULT 'assigned', -- 'assigned', 'in_fulfillment', 'completed', 'cancelled', 'disputed'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_gig_assign_request FOREIGN KEY (gig_request_id) REFERENCES gig_request (id) ON DELETE RESTRICT,
    CONSTRAINT fk_gig_assign_worker FOREIGN KEY (gig_worker_profile_id) REFERENCES gig_worker_profile (id) ON DELETE RESTRICT,
    CONSTRAINT fk_gig_assign_app FOREIGN KEY (gig_application_id) REFERENCES gig_application (id) ON DELETE RESTRICT,
    CONSTRAINT uq_gig_assignment_app UNIQUE (gig_application_id),
    CONSTRAINT chk_gig_agreed_amount CHECK (agreed_amount > 0.00),
    CONSTRAINT ex_gig_assignment_no_overlap EXCLUDE USING gist (
        gig_worker_profile_id WITH =,
        assignment_window WITH &&
    ) WHERE (assignment_status_code NOT IN ('cancelled', 'disputed'))
);

CREATE INDEX IF NOT EXISTS idx_gig_assignment_worker ON gig_assignment (gig_worker_profile_id);
CREATE INDEX IF NOT EXISTS idx_gig_assignment_request ON gig_assignment (gig_request_id);

-- ----------------------------------------------------------------------------
-- Table: gig_external_handoff (Integration boundary with external fulfillment system)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gig_external_handoff (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gig_assignment_id UUID NOT NULL,
    external_system_code VARCHAR(50) NOT NULL DEFAULT 'WORKFORCE_EXT',
    external_contract_uuid VARCHAR(100) NOT NULL,
    handoff_status_code VARCHAR(50) NOT NULL DEFAULT 'handed_off', -- 'handed_off', 'active_fulfillment', 'completed_external', 'reconciled'
    handoff_initiated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_reconciled_at TIMESTAMPTZ NULL,
    sync_metadata JSONB NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_gig_handoff_assignment FOREIGN KEY (gig_assignment_id) REFERENCES gig_assignment (id) ON DELETE CASCADE,
    CONSTRAINT uq_gig_handoff_contract UNIQUE (external_contract_uuid),
    CONSTRAINT uq_gig_handoff_assignment UNIQUE (gig_assignment_id)
);

-- ----------------------------------------------------------------------------
-- Table: gig_external_earning (External system reconciled financial figures)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gig_external_earning (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gig_assignment_id UUID NOT NULL,
    estimated_earning_amount DECIMAL(14, 2) NOT NULL,
    actual_total_earning_amount DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    projected_earning_amount DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    external_invoice_reference VARCHAR(100) NULL,
    reconciled_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_gig_earning_assignment FOREIGN KEY (gig_assignment_id) REFERENCES gig_assignment (id) ON DELETE CASCADE,
    CONSTRAINT uq_gig_earning_assignment UNIQUE (gig_assignment_id),
    CONSTRAINT chk_gig_estimated_earning CHECK (estimated_earning_amount >= 0.00),
    CONSTRAINT chk_gig_actual_earning CHECK (actual_total_earning_amount >= 0.00)
);

-- ----------------------------------------------------------------------------
-- Table: gig_requester_worker_list (Favourite & Blacklist management)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gig_requester_worker_list (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    gig_worker_profile_id UUID NOT NULL,
    list_type_code VARCHAR(20) NOT NULL, -- 'favourite', 'blacklist'
    reason_note TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_org_worker_list_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT fk_org_worker_list_worker FOREIGN KEY (gig_worker_profile_id) REFERENCES gig_worker_profile (id) ON DELETE CASCADE,
    CONSTRAINT uq_gig_requester_worker_list UNIQUE (organisation_id, gig_worker_profile_id),
    CONSTRAINT chk_gig_list_type CHECK (list_type_code IN ('favourite', 'blacklist'))
);

CREATE INDEX IF NOT EXISTS idx_gig_list_org_type ON gig_requester_worker_list (organisation_id, list_type_code);

-- ----------------------------------------------------------------------------
-- Table: gig_rating (Requesters and workers rate completed gigs)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gig_rating (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gig_assignment_id UUID NOT NULL,
    rated_by_user_id UUID NOT NULL,
    rating_score INT NOT NULL,
    review_comments TEXT NULL,
    is_from_requester BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_gig_rating_assignment FOREIGN KEY (gig_assignment_id) REFERENCES gig_assignment (id) ON DELETE CASCADE,
    CONSTRAINT fk_gig_rating_user FOREIGN KEY (rated_by_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_gig_rating_assignment_party UNIQUE (gig_assignment_id, is_from_requester),
    CONSTRAINT chk_gig_rating_range CHECK (rating_score >= 1 AND rating_score <= 5)
);

CREATE INDEX IF NOT EXISTS idx_gig_rating_assignment ON gig_rating (gig_assignment_id);
