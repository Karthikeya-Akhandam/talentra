-- ============================================================================
-- Talentra Schema: 08_licences_devices_sessions.sql
-- Modules: Licences, Seats, Devices and Sessions (M07) - Phase 3 (Milestones 11-14; B36, B39, B42, B45)
-- Standards: Rule Group 1, 2, 3, 4, 9 (Licensing, Devices, Sessions)
-- Key Feature: B45 Concurrency & device limits enforced at database layer
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: subscription_licence
-- Rule Group 9: Explicit positive integer check constraints on users and devices
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscription_licence (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id UUID NOT NULL,
    licence_key VARCHAR(100) NOT NULL,
    max_users INT NOT NULL DEFAULT 5,
    max_devices_per_user INT NOT NULL DEFAULT 2,
    status_code VARCHAR(30) NOT NULL DEFAULT 'active', -- 'active', 'expired', 'suspended', 'cancelled'
    valid_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT fk_licence_org FOREIGN KEY (organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT uq_licence_key UNIQUE (licence_key),
    CONSTRAINT chk_licence_max_users CHECK (max_users > 0),
    CONSTRAINT chk_licence_max_devices CHECK (max_devices_per_user > 0),
    CONSTRAINT chk_licence_valid_window CHECK (valid_until > valid_from)
);

CREATE INDEX IF NOT EXISTS idx_licence_org ON subscription_licence (organisation_id);

-- ----------------------------------------------------------------------------
-- Table: licence_seat_allocation
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS licence_seat_allocation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_licence_id UUID NOT NULL,
    user_id UUID NOT NULL,
    allocated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    allocated_by UUID NULL,
    revoked_at TIMESTAMPTZ NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT fk_seat_licence FOREIGN KEY (subscription_licence_id) REFERENCES subscription_licence (id) ON DELETE CASCADE,
    CONSTRAINT fk_seat_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_licence_active_user_seat 
ON licence_seat_allocation (subscription_licence_id, user_id) 
WHERE is_active = TRUE;

-- ----------------------------------------------------------------------------
-- Table: user_device (Registered devices per user)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_device (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    device_fingerprint_hash VARCHAR(150) NOT NULL,
    device_name VARCHAR(100) NOT NULL,
    device_type VARCHAR(50) NOT NULL DEFAULT 'desktop', -- 'desktop', 'laptop', 'mobile_android', 'mobile_ios', 'tablet'
    os_name VARCHAR(50) NULL,
    client_app_version VARCHAR(50) NULL,
    is_trusted BOOLEAN NOT NULL DEFAULT TRUE,
    first_registered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_device_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_user_device UNIQUE (user_id, device_fingerprint_hash)
);

CREATE INDEX IF NOT EXISTS idx_device_user ON user_device (user_id);

-- ----------------------------------------------------------------------------
-- Table: user_session
-- Rule Group 9: Active sessions with start, last_activity, end_time
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_session (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id UUID NOT NULL,
    user_device_id UUID NOT NULL,
    session_token_hash VARCHAR(255) NOT NULL,
    ip_address VARCHAR(45) NOT NULL,
    user_agent TEXT NULL,
    start_time TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_activity_time TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMPTZ NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    revocation_reason VARCHAR(100) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_session_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_session_device FOREIGN KEY (user_device_id) REFERENCES user_device (id) ON DELETE CASCADE,
    CONSTRAINT uq_session_token UNIQUE (session_token_hash)
);

CREATE INDEX IF NOT EXISTS idx_session_user_active ON user_session (user_id, is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_session_device ON user_session (user_device_id);

-- ----------------------------------------------------------------------------
-- Table: login_attempt
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS login_attempt (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email_attempted VARCHAR(254) NOT NULL,
    user_id UUID NULL,
    ip_address VARCHAR(45) NOT NULL,
    was_successful BOOLEAN NOT NULL,
    failure_reason_code VARCHAR(50) NULL, -- 'invalid_credentials', 'device_limit_exceeded', 'account_locked', 'unverified'
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_login_attempt_email ON login_attempt (email_attempted, attempted_at);

-- ----------------------------------------------------------------------------
-- Table: session_revocation_log (Audit of session and device revocation)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS session_revocation_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_session_id BIGINT NOT NULL,
    revoked_by_user_id UUID NOT NULL,
    reason_code VARCHAR(50) NOT NULL, -- 'device_limit_enforced', 'user_manual_logout', 'admin_forced', 'suspicious_activity'
    audit_note TEXT NULL,
    revoked_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- Function & Trigger: Enforce Concurrent Device Limits on Login (B45, Rule Group 9)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_enforce_concurrent_device_session_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_max_devices INT := 2; -- Default baseline
    v_active_session_count INT;
BEGIN
    -- Only check on active session insertion
    IF NEW.is_active = TRUE THEN
        -- Check if user belongs to an organisation with an active licence
        SELECT l.max_devices_per_user INTO v_max_devices
        FROM licence_seat_allocation sa
        JOIN subscription_licence l ON sa.subscription_licence_id = l.id
        WHERE sa.user_id = NEW.user_id
          AND sa.is_active = TRUE
          AND l.status_code = 'active'
          AND CURRENT_TIMESTAMP BETWEEN l.valid_from AND l.valid_until
        LIMIT 1;

        IF v_max_devices IS NULL THEN
            v_max_devices := 2; -- Default allowance
        END IF;

        -- Count currently active sessions for this user (excluding expired/revoked)
        SELECT COUNT(*) INTO v_active_session_count
        FROM user_session
        WHERE user_id = NEW.user_id
          AND is_active = TRUE
          AND end_time IS NULL;

        -- If limit reached or exceeded, log attempt in audit_log and revoke oldest active session
        IF v_active_session_count >= v_max_devices THEN
            -- Record limit hit in audit_log
            INSERT INTO audit_log (
                actor_user_id, entity_name, entity_id, action_type, diff_payload
            ) VALUES (
                NEW.user_id, 'user_session', NEW.user_device_id::TEXT, 'DEVICE_LIMIT_EXCEEDED',
                jsonb_build_object(
                    'active_count', v_active_session_count,
                    'max_allowed', v_max_devices,
                    'enforcement', 'auto_revoke_oldest'
                )
            );

            -- Automatically revoke the oldest active session to honor concurrent policy
            UPDATE user_session
            SET is_active = FALSE,
                end_time = CURRENT_TIMESTAMP,
                revocation_reason = 'device_limit_exceeded_auto_revoked'
            WHERE id = (
                SELECT id FROM user_session
                WHERE user_id = NEW.user_id AND is_active = TRUE AND end_time IS NULL
                ORDER BY start_time ASC
                LIMIT 1
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enforce_session_limit ON user_session;
CREATE TRIGGER trg_enforce_session_limit
BEFORE INSERT ON user_session
FOR EACH ROW EXECUTE FUNCTION fn_enforce_concurrent_device_session_limit();
