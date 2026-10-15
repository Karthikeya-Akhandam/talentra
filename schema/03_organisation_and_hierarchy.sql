-- ============================================================================
-- Talentra Schema: 03_organisation_and_hierarchy.sql
-- Modules: Organisation and Account (M05)
-- Standards: Rule Group 1 (snake_case, singular), Rule Group 2 (Keys/Constraints),
--            Rule Group 3 (Standard Domains), Rule Group 4 (Audit/Lifecycle),
--            Rule Group 6 (Sensitive Data: Tax IDs)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: organisation
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organisation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legal_name VARCHAR(200) NOT NULL,
    trade_name VARCHAR(200) NULL,
    organisation_type_code VARCHAR(50) NOT NULL, -- 'enterprise_employer', 'sme_employer', 'staffing_agency', 'consultancy', 'academic_institution'
    website_url VARCHAR(255) NULL,
    logo_storage_path VARCHAR(500) NULL,
    company_overview TEXT NULL,
    industry_id UUID NULL,
    employee_count_band VARCHAR(50) NOT NULL DEFAULT '11-50', -- '1-10', '11-50', '51-200', '201-1000', '1000+'
    founded_year INT NULL,
    verification_status_code VARCHAR(30) NOT NULL DEFAULT 'unverified', -- 'unverified', 'pending_review', 'verified', 'rejected'
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT fk_org_industry FOREIGN KEY (industry_id) REFERENCES industry (id) ON DELETE SET NULL,
    CONSTRAINT chk_org_founded_year CHECK (founded_year IS NULL OR (founded_year >= 1800 AND founded_year <= 2100))
);

CREATE INDEX IF NOT EXISTS idx_organisation_legal_name ON organisation (legal_name);
CREATE INDEX IF NOT EXISTS idx_organisation_verification ON organisation (verification_status_code) WHERE deleted_at IS NULL;

-- ----------------------------------------------------------------------------
-- Table: organisation_hierarchy
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organisation_hierarchy (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_organisation_id UUID NOT NULL,
    child_organisation_id UUID NOT NULL,
    relationship_type VARCHAR(50) NOT NULL DEFAULT 'subsidiary', -- 'subsidiary', 'regional_branch', 'franchise', 'client_client'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT fk_hierarchy_parent FOREIGN KEY (parent_organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT fk_hierarchy_child FOREIGN KEY (child_organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT chk_hierarchy_no_self_parent CHECK (parent_organisation_id <> child_organisation_id),
    CONSTRAINT uq_organisation_hierarchy UNIQUE (parent_organisation_id, child_organisation_id)
);

CREATE INDEX IF NOT EXISTS idx_org_hierarchy_child ON organisation_hierarchy (child_organisation_id);

-- ----------------------------------------------------------------------------
-- Table: organisation_location
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organisation_location (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    location_name VARCHAR(100) NOT NULL,
    is_headquarters BOOLEAN NOT NULL DEFAULT FALSE,
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255) NULL,
    city_id UUID NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    latitude DECIMAL(10, 7) NULL,
    longitude DECIMAL(10, 7) NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT fk_org_location_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT fk_org_location_city FOREIGN KEY (city_id) REFERENCES city (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_org_location_org_id ON organisation_location (organisation_id);

-- ----------------------------------------------------------------------------
-- Table: organisation_tax_identifier (Rule Group 6: Sensitive)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organisation_tax_identifier (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    country_iso_code CHAR(2) NOT NULL,
    identifier_type VARCHAR(50) NOT NULL, -- 'GSTIN', 'EIN', 'VAT', 'PAN', 'COMPANY_NUMBER'
    identifier_value VARCHAR(100) NOT NULL,
    verification_status_code VARCHAR(30) NOT NULL DEFAULT 'pending', -- 'pending', 'verified', 'flagged', 'rejected'
    verified_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_org_tax_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT uq_org_tax_identifier UNIQUE (country_iso_code, identifier_type, identifier_value)
);

CREATE INDEX IF NOT EXISTS idx_org_tax_identifier_org ON organisation_tax_identifier (organisation_id);

-- ----------------------------------------------------------------------------
-- Table: recruiter_mapping (Milestone 10: B34 - Effective-dated recruiter mapping)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recruiter_mapping (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    recruiter_user_id UUID NOT NULL,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMPTZ NULL,
    is_primary_contact BOOLEAN NOT NULL DEFAULT FALSE,
    mapping_status_code VARCHAR(30) NOT NULL DEFAULT 'active', -- 'active', 'inactive', 'transferred'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_recruiter_mapping_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT fk_recruiter_mapping_user FOREIGN KEY (recruiter_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_recruiter_mapping_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE INDEX IF NOT EXISTS idx_recruiter_mapping_lookup ON recruiter_mapping (recruiter_user_id, organisation_id, mapping_status_code);

-- ----------------------------------------------------------------------------
-- Table: account_profile
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS account_profile (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    account_number VARCHAR(50) NOT NULL,
    account_status_code VARCHAR(30) NOT NULL DEFAULT 'active', -- 'active', 'suspended', 'delinquent', 'closed'
    credit_limit_amount DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    credit_limit_currency CHAR(3) NOT NULL DEFAULT 'INR',
    billing_cycle_code VARCHAR(30) NOT NULL DEFAULT 'monthly', -- 'monthly', 'quarterly', 'annual'
    payment_terms_days INT NOT NULL DEFAULT 30,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_account_profile_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT uq_account_profile_org UNIQUE (organisation_id),
    CONSTRAINT uq_account_profile_num UNIQUE (account_number),
    CONSTRAINT chk_account_credit_limit CHECK (credit_limit_amount >= 0.00)
);

-- ----------------------------------------------------------------------------
-- Table: account_administrator
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS account_administrator (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_profile_id UUID NOT NULL,
    user_id UUID NOT NULL,
    is_primary_admin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT fk_account_admin_profile FOREIGN KEY (account_profile_id) REFERENCES account_profile (id) ON DELETE CASCADE,
    CONSTRAINT fk_account_admin_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_account_admin UNIQUE (account_profile_id, user_id)
);
