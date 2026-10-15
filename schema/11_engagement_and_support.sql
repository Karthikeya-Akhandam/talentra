-- ============================================================================
-- Talentra Schema: 11_engagement_and_support.sql
-- Modules: Notifications, Preferences, Community, Support, Referrals (M10), Shared Security (M12)
-- Standards: Rule Group 1, 2, 3, 4, 8
-- Key Features:
--   1. B57 Partitioned notification deliveries for high-volume write path
--   2. B50/B59 User and Company Block Lists
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: user_preference
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_preference (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    notification_frequency_code VARCHAR(30) NOT NULL DEFAULT 'instant', -- 'instant', 'daily_digest', 'weekly_summary', 'paused'
    is_email_channel_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    is_sms_channel_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    is_push_channel_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    is_whatsapp_channel_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_marketing_opt_in BOOLEAN NOT NULL DEFAULT FALSE,
    preferred_ui_language_code CHAR(2) NOT NULL DEFAULT 'en',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_preference_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_user_preference UNIQUE (user_id)
);

-- ----------------------------------------------------------------------------
-- Table: job_alert_preference
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_alert_preference (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    alert_name VARCHAR(150) NOT NULL,
    industry_id UUID NULL,
    job_role_id UUID NULL,
    city_id UUID NULL,
    min_salary_amount DECIMAL(14, 2) NULL,
    work_mode_id UUID NULL,
    alert_frequency_code VARCHAR(30) NOT NULL DEFAULT 'daily', -- 'instant', 'daily', 'weekly'
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_job_alert_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_job_alert_role FOREIGN KEY (job_role_id) REFERENCES job_role (id) ON DELETE SET NULL,
    CONSTRAINT fk_job_alert_city FOREIGN KEY (city_id) REFERENCES city (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_job_alert_user ON job_alert_preference (user_id);

-- ----------------------------------------------------------------------------
-- Table: user_privacy_setting
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_privacy_setting (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    profile_visibility_code VARCHAR(30) NOT NULL DEFAULT 'public', -- 'public', 'anonymous_search', 'hidden_to_current_employer', 'private'
    is_phone_number_masked BOOLEAN NOT NULL DEFAULT TRUE,
    is_email_address_masked BOOLEAN NOT NULL DEFAULT TRUE,
    allow_direct_recruiter_messages BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_privacy_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_user_privacy UNIQUE (user_id)
);

-- ----------------------------------------------------------------------------
-- Table: user_block_list (Candidate blocks specific recruiter or consultant)
-- Backlog B50, B59: Blocked party must not see the blocker's candidate profile
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_block_list (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_user_id UUID NOT NULL,
    blocked_user_id UUID NOT NULL,
    reason_code VARCHAR(50) NOT NULL DEFAULT 'unwanted_contact', -- 'unwanted_contact', 'harassment', 'privacy_concern', 'other'
    notes TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_block_blocker FOREIGN KEY (blocker_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_block_blocked FOREIGN KEY (blocked_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_block_no_self CHECK (blocker_user_id <> blocked_user_id),
    CONSTRAINT uq_user_block UNIQUE (blocker_user_id, blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_block_blocked ON user_block_list (blocked_user_id, blocker_user_id);

-- ----------------------------------------------------------------------------
-- Table: company_block_list (Candidate blocks entire employer organization)
-- Backlog B50, B59: Prevent current or unwanted employers from finding candidate
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS company_block_list (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_user_id UUID NOT NULL,
    blocked_organisation_id UUID NOT NULL,
    reason_code VARCHAR(50) NOT NULL DEFAULT 'current_employer', -- 'current_employer', 'past_dispute', 'privacy'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_comp_block_candidate FOREIGN KEY (candidate_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_comp_block_org FOREIGN KEY (blocked_organisation_id) REFERENCES organisation (id) ON DELETE CASCADE,
    CONSTRAINT uq_company_block UNIQUE (candidate_user_id, blocked_organisation_id)
);

CREATE INDEX IF NOT EXISTS idx_company_block_lookup ON company_block_list (blocked_organisation_id, candidate_user_id);

-- ----------------------------------------------------------------------------
-- Table: notification (Notification catalog and templates)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trigger_event_code VARCHAR(50) NOT NULL, -- 'job_applied', 'interview_scheduled', 'offer_extended', 'wallet_recharged', 'gig_matched'
    sender_user_id UUID NULL,
    title VARCHAR(200) NOT NULL,
    body_template TEXT NOT NULL,
    action_url VARCHAR(500) NULL,
    payload_data JSONB NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notification_trigger ON notification (trigger_event_code, created_at);

-- ----------------------------------------------------------------------------
-- Table: notification_delivery
-- Milestone 18: B57 - High-volume write path partitioned by range on created_at
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification_delivery (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    notification_id BIGINT NOT NULL,
    recipient_user_id UUID NOT NULL,
    channel_type_code VARCHAR(30) NOT NULL, -- 'in_app', 'email', 'sms', 'whatsapp', 'push'
    delivery_status_code VARCHAR(30) NOT NULL DEFAULT 'queued', -- 'queued', 'sent', 'delivered', 'read', 'failed', 'bounced'
    provider_reference_id VARCHAR(100) NULL,
    sent_at TIMESTAMPTZ NULL,
    delivered_at TIMESTAMPTZ NULL,
    read_at TIMESTAMPTZ NULL,
    failure_reason TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_notification_delivery PRIMARY KEY (id, created_at),
    CONSTRAINT fk_notif_deliv_notif FOREIGN KEY (notification_id) REFERENCES notification (id) ON DELETE CASCADE,
    CONSTRAINT fk_notif_deliv_recipient FOREIGN KEY (recipient_user_id) REFERENCES users (id) ON DELETE CASCADE
) PARTITION BY RANGE (created_at);

-- Partitions for High-Volume Write Path (Rule Group 8)
CREATE TABLE IF NOT EXISTS notification_delivery_p2026_q1 PARTITION OF notification_delivery
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS notification_delivery_p2026_q2 PARTITION OF notification_delivery
    FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS notification_delivery_p2026_q3 PARTITION OF notification_delivery
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS notification_delivery_p2026_q4 PARTITION OF notification_delivery
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS notification_delivery_default PARTITION OF notification_delivery
    DEFAULT;

CREATE INDEX IF NOT EXISTS idx_notif_deliv_recipient ON notification_delivery (recipient_user_id, delivery_status_code, created_at);

-- ----------------------------------------------------------------------------
-- Table: community_forum
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS community_forum (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(150) NOT NULL,
    slug VARCHAR(150) NOT NULL,
    description TEXT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    CONSTRAINT uq_forum_slug UNIQUE (slug)
);

-- ----------------------------------------------------------------------------
-- Table: community_post
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS community_post (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    community_forum_id UUID NOT NULL,
    author_user_id UUID NOT NULL,
    title VARCHAR(250) NOT NULL,
    content_body TEXT NOT NULL,
    upvotes_count INT NOT NULL DEFAULT 0,
    comments_count INT NOT NULL DEFAULT 0,
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    status_code VARCHAR(30) NOT NULL DEFAULT 'published', -- 'draft', 'published', 'flagged', 'hidden'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT fk_post_forum FOREIGN KEY (community_forum_id) REFERENCES community_forum (id) ON DELETE CASCADE,
    CONSTRAINT fk_post_author FOREIGN KEY (author_user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_post_forum_created ON community_post (community_forum_id, created_at) WHERE deleted_at IS NULL;

-- ----------------------------------------------------------------------------
-- Table: community_reaction
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS community_reaction (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    community_post_id UUID NOT NULL,
    user_id UUID NOT NULL,
    reaction_type_code VARCHAR(30) NOT NULL DEFAULT 'upvote', -- 'upvote', 'heart', 'insightful'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reaction_post FOREIGN KEY (community_post_id) REFERENCES community_post (id) ON DELETE CASCADE,
    CONSTRAINT fk_reaction_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_post_user_reaction UNIQUE (community_post_id, user_id, reaction_type_code)
);

-- ----------------------------------------------------------------------------
-- Table: support_ticket
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS support_ticket (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_reference VARCHAR(50) NOT NULL,
    user_id UUID NOT NULL,
    category_code VARCHAR(50) NOT NULL, -- 'billing_issue', 'account_access', 'technical_bug', 'verification_problem'
    subject VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    priority_code VARCHAR(30) NOT NULL DEFAULT 'medium', -- 'low', 'medium', 'high', 'urgent'
    status_code VARCHAR(30) NOT NULL DEFAULT 'open', -- 'open', 'assigned', 'waiting_customer', 'resolved', 'closed'
    assigned_agent_user_id UUID NULL,
    resolved_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID NULL,
    CONSTRAINT fk_ticket_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_ticket_agent FOREIGN KEY (assigned_agent_user_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT uq_ticket_ref UNIQUE (ticket_reference)
);

CREATE INDEX IF NOT EXISTS idx_ticket_user ON support_ticket (user_id);
CREATE INDEX IF NOT EXISTS idx_ticket_status ON support_ticket (status_code);

-- ----------------------------------------------------------------------------
-- Table: support_ticket_message
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS support_ticket_message (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    support_ticket_id UUID NOT NULL,
    sender_user_id UUID NOT NULL,
    message_text TEXT NOT NULL,
    is_internal_agent_note BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ticket_msg_ticket FOREIGN KEY (support_ticket_id) REFERENCES support_ticket (id) ON DELETE CASCADE,
    CONSTRAINT fk_ticket_msg_sender FOREIGN KEY (sender_user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ticket_msg_ticket ON support_ticket_message (support_ticket_id, created_at);

-- ----------------------------------------------------------------------------
-- Table: faq_item
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS faq_item (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category VARCHAR(100) NOT NULL,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- Table: candidate_referral
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS candidate_referral (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_user_id UUID NOT NULL,
    referred_email VARCHAR(254) NOT NULL,
    referral_code VARCHAR(50) NOT NULL,
    status_code VARCHAR(30) NOT NULL DEFAULT 'invited', -- 'invited', 'registered', 'profile_completed', 'placed', 'reward_paid'
    reward_credits_amount DECIMAL(14, 2) NOT NULL DEFAULT 50.00,
    registered_user_id UUID NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_referral_referrer FOREIGN KEY (referrer_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_referral_registered FOREIGN KEY (registered_user_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT uq_referral_code UNIQUE (referral_code)
);

CREATE INDEX IF NOT EXISTS idx_referral_referrer ON candidate_referral (referrer_user_id);
