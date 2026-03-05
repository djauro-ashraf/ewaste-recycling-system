-- ============================================================
-- E-WASTE RECYCLING MANAGEMENT SYSTEM  v3
-- 01_tables.sql  —  Full normalized schema
-- ============================================================

-- ── Drop in reverse dependency order ──────────────────────
DROP TABLE IF EXISTS admin_alerts       CASCADE;
DROP TABLE IF EXISTS system_revenue     CASCADE;
DROP TABLE IF EXISTS warnings           CASCADE;
DROP TABLE IF EXISTS payment_requests   CASCADE;
DROP TABLE IF EXISTS audit_log          CASCADE;
DROP TABLE IF EXISTS batch_items        CASCADE;
DROP TABLE IF EXISTS recycling_batches  CASCADE;
DROP TABLE IF EXISTS payments           CASCADE;
DROP TABLE IF EXISTS weight_records     CASCADE;
DROP TABLE IF EXISTS items              CASCADE;
DROP TABLE IF EXISTS pickup_requests    CASCADE;
DROP TABLE IF EXISTS pricing_rules      CASCADE;
DROP TABLE IF EXISTS categories         CASCADE;
DROP TABLE IF EXISTS accounts           CASCADE;
DROP TABLE IF EXISTS vehicles           CASCADE;
DROP TABLE IF EXISTS staff              CASCADE;
DROP TABLE IF EXISTS recycling_facilities CASCADE;
DROP TABLE IF EXISTS users              CASCADE;

-- ── users ─────────────────────────────────────────────────
-- Citizens who request e-waste pickups.
-- user_status is maintained by trigger based on pickup activity.
CREATE TABLE users (
    user_id       SERIAL PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(100) UNIQUE NOT NULL,
    phone         VARCHAR(20)  NOT NULL,
    address       TEXT         NOT NULL,
    city          VARCHAR(50)  NOT NULL,
    -- active=normal, idle=no pickup 6mo, inactive=no pickup 12mo, suspended=admin action
    user_status   VARCHAR(20)  NOT NULL DEFAULT 'active'
                  CHECK (user_status IN ('active','idle','inactive','suspended')),
    is_active     BOOLEAN      DEFAULT TRUE,   -- FALSE = cannot login
    registered_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    last_pickup_at TIMESTAMP,                  -- updated by trigger on pickup completion
    metadata      JSONB        DEFAULT '{}'    -- flexible extra user data
);

-- ── recycling_facilities ──────────────────────────────────
CREATE TABLE recycling_facilities (
    facility_id      SERIAL PRIMARY KEY,
    facility_name    VARCHAR(100) NOT NULL,
    location         VARCHAR(100) NOT NULL,
    capacity_kg      DECIMAL(10,2) NOT NULL,
    current_load_kg  DECIMAL(10,2) DEFAULT 0,
    specialization   VARCHAR(50),
    is_operational   BOOLEAN DEFAULT TRUE,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── staff ─────────────────────────────────────────────────
-- Unified staff table with self-referencing supervisor hierarchy.
-- sub_role: supervisor | driver | collector
-- Drivers and collectors have supervisor_id pointing to their supervisor.
-- Supervisors have supervisor_id = NULL.
CREATE TABLE staff (
    staff_id        SERIAL PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    sub_role        VARCHAR(20)  NOT NULL
                    CHECK (sub_role IN ('supervisor','driver','collector')),
    contact_number  VARCHAR(20)  NOT NULL,
    supervisor_id   INT,          -- FK added post-creation (self-ref)
    is_active       BOOLEAN      DEFAULT TRUE,
    is_available    BOOLEAN      DEFAULT TRUE,   -- available for assignment today
    hired_at        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    fired_at        TIMESTAMP,                   -- soft-delete timestamp
    fired_by        INT,                         -- account_id of admin who fired
    metadata        JSONB        DEFAULT '{}'    -- e.g. {"license":"DL-12345","notes":"..."}
);

-- Self-referencing FK: driver/collector → supervisor
ALTER TABLE staff
    ADD CONSTRAINT fk_staff_supervisor
    FOREIGN KEY (supervisor_id) REFERENCES staff(staff_id);

-- ── vehicles ──────────────────────────────────────────────
-- Each vehicle belongs to a supervisor (who manages its usage).
CREATE TABLE vehicles (
    vehicle_id       SERIAL PRIMARY KEY,
    vehicle_number   VARCHAR(20) UNIQUE NOT NULL,
    vehicle_type     VARCHAR(30) NOT NULL,
    capacity_kg      DECIMAL(8,2) NOT NULL,
    current_load_kg  DECIMAL(8,2) DEFAULT 0,
    supervisor_id    INT,          -- FK → staff (supervisor who owns this vehicle)
    is_available     BOOLEAN DEFAULT TRUE,
    last_maintenance DATE,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── accounts ──────────────────────────────────────────────
-- Single credential store for all roles.
-- role: 'user' | 'staff' | 'admin'
-- For staff, sub_role is derived from staff.sub_role at login time.
CREATE TABLE accounts (
    account_id    SERIAL PRIMARY KEY,
    username      VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(10)  NOT NULL CHECK (role IN ('user','staff','admin')),
    user_id       INT REFERENCES users(user_id)  ON DELETE CASCADE,
    staff_id      INT REFERENCES staff(staff_id) ON DELETE CASCADE,
    display_name  VARCHAR(100) NOT NULL,
    is_active     BOOLEAN   DEFAULT TRUE,
    last_login    TIMESTAMP,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Exactly one of user_id/staff_id must be set (admin: neither)
    CONSTRAINT chk_account_entity CHECK (
        (role = 'user'  AND user_id  IS NOT NULL AND staff_id IS NULL) OR
        (role = 'staff' AND staff_id IS NOT NULL AND user_id  IS NULL) OR
        (role = 'admin' AND user_id  IS NULL     AND staff_id IS NULL)
    )
);

-- ── categories ────────────────────────────────────────────
CREATE TABLE categories (
    category_id              SERIAL PRIMARY KEY,
    category_name            VARCHAR(50) UNIQUE NOT NULL,
    description              TEXT,
    base_price_per_kg        DECIMAL(8,2) NOT NULL DEFAULT 0,
    hazard_level             INT DEFAULT 1 CHECK (hazard_level BETWEEN 1 AND 5),
    recyclability_percentage DECIMAL(5,2),
    -- JSONB: stores material breakdown for revenue calc
    -- e.g. {"copper_pct":8,"gold_ppm":200,"aluminum_pct":40}
    material_composition     JSONB DEFAULT '{}',
    created_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── pricing_rules ─────────────────────────────────────────
CREATE TABLE pricing_rules (
    rule_id          SERIAL PRIMARY KEY,
    category_id      INT          NOT NULL,
    min_weight_kg    DECIMAL(8,2) NOT NULL,
    max_weight_kg    DECIMAL(8,2),
    price_per_kg     DECIMAL(8,2) NOT NULL,
    bonus_percentage DECIMAL(5,2) DEFAULT 0,
    effective_from   DATE         NOT NULL,
    effective_to     DATE,
    is_active        BOOLEAN      DEFAULT TRUE,
    created_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- ── pickup_requests ───────────────────────────────────────
-- Full lifecycle: pending → supervisor_assigned → field_assigned
--                → collected → completed | cancelled
-- Three staff slots: supervisor oversees, driver transports, collector verifies items.
CREATE TABLE pickup_requests (
    pickup_id            SERIAL PRIMARY KEY,
    user_id              INT  NOT NULL,
    request_date         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    preferred_date       DATE      NOT NULL,
    pickup_address       TEXT      NOT NULL,
    status               VARCHAR(30) DEFAULT 'pending'
                         CHECK (status IN (
                             'pending',             -- user submitted
                             'supervisor_assigned', -- admin assigned supervisor
                             'field_assigned',      -- supervisor assigned driver+collector
                             'picked_up',           -- collector confirmed physical pickup + weights
                             'delivered',           -- driver confirmed delivery to facility
                             'collected',           -- both collector + driver done; payment window opens
                             'completed',           -- payment processed (complete for user)
                             'cancelled'
                         )),
    -- Staff assignment chain
    supervisor_id        INT,   -- set by admin
    driver_id            INT,   -- set by supervisor
    collector_id         INT,   -- set by supervisor
    assigned_vehicle_id  INT,
    assigned_facility_id INT,
    -- Timestamps
    scheduled_time       TIMESTAMP,
    collected_at         TIMESTAMP,   -- when field staff marked collected
    collector_confirmed  BOOLEAN   DEFAULT FALSE,  -- collector did physical pickup
    driver_confirmed     BOOLEAN   DEFAULT FALSE,  -- driver delivered to facility
    collector_confirmed_at TIMESTAMP,
    driver_confirmed_at  TIMESTAMP,
    completed_time       TIMESTAMP,   -- when payment processed
    -- Payment timing
    payment_due_by       TIMESTAMP,   -- collected_at + 3 days; after this user can request
    payment_request_count INT DEFAULT 0,  -- # times user has requested payment
    -- Financials (allow 0 for worthless e-waste)
    total_weight_kg      DECIMAL(10,2) DEFAULT 0,
    total_amount         DECIMAL(10,2) DEFAULT 0,  -- NOT NULL removed, 0 is valid
    notes                TEXT,
    -- Audit timestamps
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── items ─────────────────────────────────────────────────
CREATE TABLE items (
    item_id             SERIAL PRIMARY KEY,
    pickup_id           INT NOT NULL,
    category_id         INT NOT NULL,
    item_description    TEXT NOT NULL,
    condition           VARCHAR(20) CHECK (condition IN ('working','broken','repairable')),
    estimated_weight_kg DECIMAL(8,2),
    actual_weight_kg    DECIMAL(8,2),
    -- JSONB: flexible hazard / component data
    -- e.g. {"contains_mercury":true,"battery_count":2,"crt_kg":18.5}
    hazard_details      JSONB DEFAULT '{}',
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── weight_records ────────────────────────────────────────
CREATE TABLE weight_records (
    weight_id      SERIAL PRIMARY KEY,
    item_id        INT         NOT NULL,
    weighing_stage VARCHAR(30) NOT NULL CHECK (weighing_stage IN ('pickup','facility_in','facility_out')),
    weight_kg      DECIMAL(8,2) NOT NULL,
    weighed_by     INT,   -- staff_id
    weighed_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes          TEXT
);

-- ── payments ──────────────────────────────────────────────
-- amount can be 0 (zero-value pickups are valid).
-- Processed exclusively by supervisors.
CREATE TABLE payments (
    payment_id            SERIAL PRIMARY KEY,
    pickup_id             INT         NOT NULL,
    amount                DECIMAL(10,2) DEFAULT 0,   -- NOT NULL removed; 0 is valid
    payment_method        VARCHAR(30),
    payment_status        VARCHAR(20) DEFAULT 'pending'
                          CHECK (payment_status IN ('pending','completed','failed')),
    transaction_reference VARCHAR(100) UNIQUE,
    processed_by          INT,   -- staff_id of supervisor who processed
    processed_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes                 TEXT
);

-- ── payment_requests ──────────────────────────────────────
-- User-initiated "I haven't been paid" requests.
-- Duplicate requests auto-generate an admin_alert.
CREATE TABLE payment_requests (
    request_id     SERIAL PRIMARY KEY,
    pickup_id      INT NOT NULL,
    user_id        INT NOT NULL,
    supervisor_id  INT,         -- supervisor who handled the pickup
    requested_at   TIMESTAMP   DEFAULT NOW(),
    status         VARCHAR(20) DEFAULT 'pending'
                   CHECK (status IN ('pending','resolved','dismissed')),
    is_duplicate   BOOLEAN     DEFAULT FALSE,  -- TRUE if another request was already pending
    admin_alerted  BOOLEAN     DEFAULT FALSE,
    notes          TEXT
);

-- ── recycling_batches ─────────────────────────────────────
-- Minimum 2 distinct pickups required before processing can start.
-- Managed by a supervisor (who may differ from the pickup supervisor).
CREATE TABLE recycling_batches (
    batch_id                 SERIAL PRIMARY KEY,
    facility_id              INT NOT NULL,
    supervisor_id            INT,   -- supervisor responsible for batch
    batch_name               VARCHAR(100) NOT NULL,
    created_date             DATE    DEFAULT CURRENT_DATE,
    processing_start_date    DATE,
    processing_end_date      DATE,
    status                   VARCHAR(20) DEFAULT 'open'
                             CHECK (status IN ('open','processing','completed','cancelled')),
    total_weight_kg          DECIMAL(10,2) DEFAULT 0,
    recovery_rate_percentage DECIMAL(5,2),
    total_revenue            DECIMAL(12,2) DEFAULT 0,  -- sum of system_revenue for this batch
    notes                    TEXT,
    created_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── batch_items ───────────────────────────────────────────
CREATE TABLE batch_items (
    batch_item_id    SERIAL PRIMARY KEY,
    batch_id         INT NOT NULL,
    item_id          INT NOT NULL,
    pickup_id        INT NOT NULL,   -- denormalized for min-pickup check query
    added_by         INT,            -- staff_id
    added_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processing_notes TEXT
);

-- ── system_revenue ────────────────────────────────────────
-- Business income: what the facility earns from recovered materials.
-- Recorded per material type when a batch completes.
CREATE TABLE system_revenue (
    revenue_id    SERIAL PRIMARY KEY,
    batch_id      INT NOT NULL,
    facility_id   INT NOT NULL,
    material_type VARCHAR(50) NOT NULL,  -- e.g. 'copper','aluminum','gold','plastics'
    weight_kg     DECIMAL(10,2) NOT NULL,
    price_per_kg  DECIMAL(10,2) NOT NULL,
    total_value   DECIMAL(12,2) GENERATED ALWAYS AS (weight_kg * price_per_kg) STORED,
    recorded_by   INT,   -- staff_id
    recorded_at   TIMESTAMP DEFAULT NOW(),
    notes         TEXT
);

-- ── warnings ──────────────────────────────────────────────
-- Admin can issue warnings to users or staff.
CREATE TABLE warnings (
    warning_id       SERIAL PRIMARY KEY,
    issued_by        INT NOT NULL,   -- account_id of admin
    target_type      VARCHAR(10) NOT NULL CHECK (target_type IN ('user','staff')),
    target_user_id   INT,
    target_staff_id  INT,
    severity         VARCHAR(20) DEFAULT 'warning'
                     CHECK (severity IN ('notice','warning','final_warning','suspension')),
    message          TEXT NOT NULL,
    issued_at        TIMESTAMP DEFAULT NOW(),
    acknowledged_at  TIMESTAMP
);

-- ── admin_alerts ──────────────────────────────────────────
-- Auto-generated by triggers for anomalies; admin sees these highlighted.
CREATE TABLE admin_alerts (
    alert_id      SERIAL PRIMARY KEY,
    alert_type    VARCHAR(60) NOT NULL,
    -- e.g. 'duplicate_payment_request','payment_overdue','batch_underrun'
    -- 'staff_fired','zero_amount_payment','user_inactive'
    severity      VARCHAR(10) DEFAULT 'medium'
                  CHECK (severity IN ('low','medium','high','critical')),
    title         TEXT NOT NULL,
    description   TEXT,
    related_table VARCHAR(50),
    related_id    INT,
    payload       JSONB DEFAULT '{}',   -- rich context data
    is_resolved   BOOLEAN DEFAULT FALSE,
    created_at    TIMESTAMP DEFAULT NOW(),
    resolved_at   TIMESTAMP,
    resolved_by   INT   -- account_id
);

-- ── audit_log ─────────────────────────────────────────────
-- Append-only ledger. Covers pickup_requests + payments + payment_requests.
CREATE TABLE audit_log (
    log_id       SERIAL PRIMARY KEY,
    table_name   VARCHAR(50)  NOT NULL,
    operation    VARCHAR(30)  NOT NULL,
    record_id    INT          NOT NULL,
    old_values   JSONB,
    new_values   JSONB,
    changed_by   VARCHAR(100),   -- username or system
    ip_address   INET,
    changed_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
