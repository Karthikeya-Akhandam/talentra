-- ============================================================================
-- Talentra Schema: 10_subscriptions_wallet_ledger.sql
-- Modules: Subscriptions, Wallet, Payments and Download History (M09)
-- Standards: Rule Group 1, 2, 3, 4, 10 (Money, subscriptions, append-only history)
-- Key Features:
--   1. Non-overlapping subscription periods per licence via EXCLUDE USING gist (B47)
--   2. Append-only wallet ledger with reversal reference (B47, Rule 10)
--   3. Append-only profile download history with credit deduction audit (Rule 10)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: subscription_plan
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscription_plan (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_code VARCHAR(50) NOT NULL,
    plan_name VARCHAR(100) NOT NULL,
    tier_level VARCHAR(30) NOT NULL DEFAULT 'standard', -- 'starter', 'standard', 'enterprise', 'custom'
    billing_interval_code VARCHAR(30) NOT NULL DEFAULT 'monthly', -- 'monthly', 'quarterly', 'annual'
    price_amount DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    max_users_included INT NOT NULL DEFAULT 5,
    max_devices_per_user INT NOT NULL DEFAULT 2,
    monthly_job_postings_quota INT NOT NULL DEFAULT 10,
    monthly_profile_downloads_quota INT NOT NULL DEFAULT 100,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT uq_subscription_plan_code UNIQUE (plan_code),
    CONSTRAINT chk_plan_price CHECK (price_amount >= 0.00),
    CONSTRAINT chk_plan_users CHECK (max_users_included > 0),
    CONSTRAINT chk_plan_devices CHECK (max_devices_per_user > 0)
);

-- ----------------------------------------------------------------------------
-- Table: plan_entitlement
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS plan_entitlement (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_plan_id UUID NOT NULL,
    feature_key VARCHAR(100) NOT NULL, -- 'ai_matching', 'direct_consultant_sourcing', 'bulk_email_outreach', 'advanced_analytics'
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    quota_limit INT NULL,
    metadata JSONB NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_entitlement_plan FOREIGN KEY (subscription_plan_id) REFERENCES subscription_plan (id) ON DELETE CASCADE,
    CONSTRAINT uq_plan_entitlement UNIQUE (subscription_plan_id, feature_key)
);

-- ----------------------------------------------------------------------------
-- Table: subscription_period
-- Rule Group 10 & Milestone 14 (B47): Subscription periods must not overlap for
-- the same licence, enforced via EXCLUDE USING gist.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscription_period (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_licence_id UUID NOT NULL,
    subscription_plan_id UUID NOT NULL,
    period_window TSTZRANGE NOT NULL,
    period_status_code VARCHAR(30) NOT NULL DEFAULT 'active', -- 'active', 'renewed', 'expired', 'cancelled'
    is_auto_renew_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    payment_order_id UUID NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_sub_period_licence FOREIGN KEY (subscription_licence_id) REFERENCES subscription_licence (id) ON DELETE CASCADE,
    CONSTRAINT fk_sub_period_plan FOREIGN KEY (subscription_plan_id) REFERENCES subscription_plan (id) ON DELETE RESTRICT,
    CONSTRAINT ex_subscription_period_no_overlap EXCLUDE USING gist (
        subscription_licence_id WITH =,
        period_window WITH &&
    ) WHERE (period_status_code NOT IN ('cancelled', 'expired'))
);

CREATE INDEX IF NOT EXISTS idx_sub_period_licence ON subscription_period (subscription_licence_id);

-- ----------------------------------------------------------------------------
-- Table: payment_order (Rule Group 3: Fixed-precision decimal with currency)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payment_order (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    order_reference VARCHAR(100) NOT NULL,
    amount DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    order_type_code VARCHAR(50) NOT NULL, -- 'subscription_purchase', 'wallet_recharge', 'overage_charge'
    payment_gateway_code VARCHAR(50) NOT NULL DEFAULT 'STRIPE',
    gateway_transaction_reference VARCHAR(150) NULL,
    payment_status_code VARCHAR(30) NOT NULL DEFAULT 'pending', -- 'pending', 'authorized', 'captured', 'failed', 'refunded'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_payment_order_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE RESTRICT,
    CONSTRAINT uq_payment_order_ref UNIQUE (order_reference),
    CONSTRAINT chk_payment_amount CHECK (amount > 0.00)
);

CREATE INDEX IF NOT EXISTS idx_payment_order_org ON payment_order (organisation_id);
CREATE INDEX IF NOT EXISTS idx_payment_order_gateway_ref ON payment_order (gateway_transaction_reference);

-- ----------------------------------------------------------------------------
-- Table: invoice
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS invoice (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_order_id UUID NOT NULL,
    organisation_id UUID NOT NULL,
    invoice_number VARCHAR(100) NOT NULL,
    subtotal_amount DECIMAL(14, 2) NOT NULL,
    tax_amount DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    total_amount DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    invoice_status_code VARCHAR(30) NOT NULL DEFAULT 'issued', -- 'issued', 'paid', 'void', 'refunded'
    pdf_storage_path VARCHAR(500) NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paid_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT fk_invoice_order FOREIGN KEY (payment_order_id) REFERENCES payment_order (id) ON DELETE RESTRICT,
    CONSTRAINT fk_invoice_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE RESTRICT,
    CONSTRAINT uq_invoice_num UNIQUE (invoice_number),
    CONSTRAINT chk_invoice_total CHECK (total_amount = subtotal_amount + tax_amount)
);

CREATE INDEX IF NOT EXISTS idx_invoice_org ON invoice (organisation_id);

-- ----------------------------------------------------------------------------
-- Table: refund
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS refund (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_order_id UUID NOT NULL,
    refund_reference VARCHAR(100) NOT NULL,
    refund_amount DECIMAL(14, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    refund_reason_code VARCHAR(50) NOT NULL, -- 'customer_request', 'duplicate_charge', 'fraudulent', 'system_cancellation'
    gateway_refund_token VARCHAR(150) NULL,
    refund_status_code VARCHAR(30) NOT NULL DEFAULT 'processed',
    processed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT fk_refund_order FOREIGN KEY (payment_order_id) REFERENCES payment_order (id) ON DELETE RESTRICT,
    CONSTRAINT uq_refund_reference UNIQUE (refund_reference),
    CONSTRAINT chk_refund_amount CHECK (refund_amount > 0.00)
);

-- ----------------------------------------------------------------------------
-- Table: wallet (Organization credit balance for postings, downloads, outreach)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wallet (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    credit_balance DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR',
    is_frozen BOOLEAN NOT NULL DEFAULT FALSE,
    last_recharged_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_wallet_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT uq_wallet_org UNIQUE (organisation_id),
    CONSTRAINT chk_wallet_balance CHECK (credit_balance >= 0.00)
);

-- ----------------------------------------------------------------------------
-- Table: wallet_ledger
-- Rule Group 10 & Milestone 14 (B47): Append-only. Corrections recorded as new
-- reversal entries referencing the original parent transaction. Never an update.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wallet_ledger (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    wallet_id UUID NOT NULL,
    transaction_type_code VARCHAR(50) NOT NULL, -- 'recharge', 'profile_download_deduction', 'job_posting_fee', 'outreach_deduction', 'reversal_credit', 'refund_debit'
    credit_delta DECIMAL(14, 2) NOT NULL, -- Positive for credits, negative for debits
    running_balance_after DECIMAL(14, 2) NOT NULL,
    parent_reversal_entry_id BIGINT NULL,
    reference_entity_name VARCHAR(100) NULL, -- 'job_requirement', 'candidate_profile', 'bulk_outreach_batch', 'payment_order'
    reference_entity_id VARCHAR(100) NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT fk_ledger_wallet FOREIGN KEY (wallet_id) REFERENCES wallet (id) ON DELETE RESTRICT,
    CONSTRAINT fk_ledger_reversal FOREIGN KEY (parent_reversal_entry_id) REFERENCES wallet_ledger (id) ON DELETE RESTRICT,
    CONSTRAINT chk_running_balance CHECK (running_balance_after >= 0.00)
);

CREATE INDEX IF NOT EXISTS idx_wallet_ledger_wallet ON wallet_ledger (wallet_id, created_at);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_ref ON wallet_ledger (reference_entity_name, reference_entity_id);

-- Anti-tamper trigger: Disallow UPDATE or DELETE on wallet_ledger
CREATE OR REPLACE FUNCTION fn_prevent_wallet_ledger_tamper()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'wallet_ledger is strictly append-only. UPDATE and DELETE operations are forbidden.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_wallet_ledger_no_update_delete ON wallet_ledger;
CREATE TRIGGER trg_wallet_ledger_no_update_delete
BEFORE UPDATE OR DELETE ON wallet_ledger
FOR EACH ROW EXECUTE FUNCTION fn_prevent_wallet_ledger_tamper();

-- ----------------------------------------------------------------------------
-- Table: profile_download_history
-- Rule Group 10: Append-only history carrying actor, subject, timestamp, and deduction
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS profile_download_history (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recruiter_user_id UUID NOT NULL,
    organisation_id UUID NOT NULL,
    candidate_profile_id UUID NOT NULL,
    resume_version_id BIGINT NULL,
    credit_deduction_amount DECIMAL(14, 2) NOT NULL DEFAULT 1.00,
    download_format VARCHAR(20) NOT NULL DEFAULT 'pdf', -- 'pdf', 'docx', 'json'
    ip_address VARCHAR(45) NULL,
    downloaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_dl_recruiter FOREIGN KEY (recruiter_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_dl_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_dl_candidate FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profile (id) ON DELETE RESTRICT,
    CONSTRAINT chk_dl_credit CHECK (credit_deduction_amount >= 0.00)
);

CREATE INDEX IF NOT EXISTS idx_dl_history_org ON profile_download_history (organisation_id, downloaded_at);
CREATE INDEX IF NOT EXISTS idx_dl_history_cand ON profile_download_history (candidate_profile_id);

-- Anti-tamper trigger for download history
DROP TRIGGER IF EXISTS trg_dl_history_no_update_delete ON profile_download_history;
CREATE TRIGGER trg_dl_history_no_update_delete
BEFORE UPDATE OR DELETE ON profile_download_history
FOR EACH ROW EXECUTE FUNCTION fn_prevent_wallet_ledger_tamper();
