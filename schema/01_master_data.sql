-- ============================================================================
-- Talentra Schema: 01_master_data.sql
-- Module: Master Data (M01)
-- Standards: Rule Group 1 (snake_case, singular), Rule Group 2 (Keys/Constraints),
--            Rule Group 3 (Standard Domains, UTF-8), Rule Group 4 (Audit/Lifecycle),
--            Rule Group 7 (Multilingual Data)
-- ============================================================================

-- Ensure required PostgreSQL extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Generic updated_at trigger function
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Table: country
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS country (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    iso_code_2 CHAR(2) NOT NULL,
    iso_code_3 CHAR(3) NOT NULL,
    name VARCHAR(150) NOT NULL,
    phone_dial_code VARCHAR(10) NOT NULL,
    default_currency_code CHAR(3) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_country_iso2 UNIQUE (iso_code_2),
    CONSTRAINT uq_country_iso3 UNIQUE (iso_code_3)
);

CREATE INDEX IF NOT EXISTS idx_country_name ON country (name);

-- ----------------------------------------------------------------------------
-- Table: state_province
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS state_province (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_id UUID NOT NULL,
    code VARCHAR(20) NOT NULL,
    name VARCHAR(150) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_state_country FOREIGN KEY (country_id) REFERENCES country (id) ON DELETE RESTRICT,
    CONSTRAINT uq_state_country_code UNIQUE (country_id, code)
);

CREATE INDEX IF NOT EXISTS idx_state_province_country_id ON state_province (country_id);

-- ----------------------------------------------------------------------------
-- Table: city
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS city (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    state_province_id UUID NOT NULL,
    name VARCHAR(150) NOT NULL,
    latitude DECIMAL(10, 7) NULL,
    longitude DECIMAL(10, 7) NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_city_state FOREIGN KEY (state_province_id) REFERENCES state_province (id) ON DELETE RESTRICT,
    CONSTRAINT chk_city_latitude CHECK (latitude IS NULL OR (latitude >= -90.0 AND latitude <= 90.0)),
    CONSTRAINT chk_city_longitude CHECK (longitude IS NULL OR (longitude >= -180.0 AND longitude <= 180.0))
);

CREATE INDEX IF NOT EXISTS idx_city_state_id ON city (state_province_id);
CREATE INDEX IF NOT EXISTS idx_city_name ON city (name);

-- ----------------------------------------------------------------------------
-- Table: industry
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS industry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_industry_code UNIQUE (code)
);

-- ----------------------------------------------------------------------------
-- Table: job_role
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_role (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    industry_id UUID NOT NULL,
    code VARCHAR(50) NOT NULL,
    title VARCHAR(150) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_job_role_industry FOREIGN KEY (industry_id) REFERENCES industry (id) ON DELETE RESTRICT,
    CONSTRAINT uq_job_role_code UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS idx_job_role_industry_id ON job_role (industry_id);

-- ----------------------------------------------------------------------------
-- Table: skill
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skill (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_skill_code UNIQUE (code),
    CONSTRAINT uq_skill_name UNIQUE (name)
);

CREATE INDEX IF NOT EXISTS idx_skill_category ON skill (category);

-- ----------------------------------------------------------------------------
-- Table: qualification
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS qualification (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    education_level VARCHAR(50) NOT NULL, -- 'high_school', 'diploma', 'undergraduate', 'postgraduate', 'doctorate'
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_qualification_code UNIQUE (code)
);

-- ----------------------------------------------------------------------------
-- Table: employment_type
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS employment_type (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) NOT NULL, -- 'permanent_full_time', 'general_contract', 'professional_contract', 'gig_work', 'apprentice', 'campus_fresher', 'managed_workforce'
    name VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_employment_type_code UNIQUE (code)
);

-- ----------------------------------------------------------------------------
-- Table: work_mode
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS work_mode (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(30) NOT NULL, -- 'on_site', 'remote', 'hybrid'
    name VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_work_mode_code UNIQUE (code)
);

-- ----------------------------------------------------------------------------
-- Table: language_lookup
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS language_lookup (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    iso_639_1 CHAR(2) NOT NULL,
    name VARCHAR(100) NOT NULL,
    native_name VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_language_iso UNIQUE (iso_639_1)
);

-- ----------------------------------------------------------------------------
-- Table: ui_translation_key & ui_translation (Rule Group 7)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ui_translation_key (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key_name VARCHAR(200) NOT NULL,
    module_name VARCHAR(100) NOT NULL,
    description VARCHAR(500) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_ui_translation_key_name UNIQUE (key_name)
);

CREATE TABLE IF NOT EXISTS ui_translation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    translation_key_id UUID NOT NULL,
    language_code CHAR(2) NOT NULL,
    translated_text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_ui_translation_key FOREIGN KEY (translation_key_id) REFERENCES ui_translation_key (id) ON DELETE CASCADE,
    CONSTRAINT uq_ui_translation_key_lang UNIQUE (translation_key_id, language_code)
);

CREATE INDEX IF NOT EXISTS idx_ui_translation_lookup ON ui_translation (language_code);
