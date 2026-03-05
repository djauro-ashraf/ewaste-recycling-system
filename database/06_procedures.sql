-- ============================================================
-- 06_procedures.sql — Stored Procedures
-- ============================================================

-- ── create_pickup_request ─────────────────────────────────
CREATE OR REPLACE PROCEDURE create_pickup_request(
    IN  p_user_id       INT,
    IN  p_preferred_date DATE,
    IN  p_address       TEXT,
    IN  p_notes         TEXT,
    OUT p_pickup_id     INT
) LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'User % not found or inactive.', p_user_id;
    END IF;
    IF p_preferred_date < CURRENT_DATE THEN
        RAISE EXCEPTION 'Preferred pickup date must be today or later.';
    END IF;
    INSERT INTO pickup_requests (user_id, preferred_date, pickup_address, notes)
    VALUES (p_user_id, p_preferred_date, p_address, p_notes)
    RETURNING pickup_id INTO p_pickup_id;
END;
$$;


-- ── add_item_to_pickup ────────────────────────────────────
CREATE OR REPLACE PROCEDURE add_item_to_pickup(
    IN  p_pickup_id      INT,
    IN  p_category_id    INT,
    IN  p_description    TEXT,
    IN  p_condition      VARCHAR(20),
    IN  p_est_weight     DECIMAL(8,2),
    IN  p_hazard_details JSONB,
    OUT p_item_id        INT
) LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pickup_requests
        WHERE  pickup_id = p_pickup_id
          AND  status IN ('pending','supervisor_assigned','field_assigned')
    ) THEN
        RAISE EXCEPTION 'Pickup % is not open for item addition.', p_pickup_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM categories WHERE category_id = p_category_id) THEN
        RAISE EXCEPTION 'Category % does not exist.', p_category_id;
    END IF;
    INSERT INTO items (pickup_id, category_id, item_description, condition,
                       estimated_weight_kg, hazard_details)
    VALUES (p_pickup_id, p_category_id, p_description, p_condition,
            p_est_weight, COALESCE(p_hazard_details, '{}'))
    RETURNING item_id INTO p_item_id;
END;
$$;


-- ── admin_assign_supervisor ───────────────────────────────
-- Admin assigns a supervisor to a pending pickup.
-- Supervisor then assigns field staff.
CREATE OR REPLACE PROCEDURE admin_assign_supervisor(
    IN  p_pickup_id      INT,
    IN  p_supervisor_id  INT,
    IN  p_facility_id    INT,
    OUT p_success        BOOLEAN
) LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pickup_requests WHERE pickup_id = p_pickup_id AND status = 'pending') THEN
        RAISE EXCEPTION 'Pickup % must be pending to assign supervisor.', p_pickup_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM staff WHERE staff_id = p_supervisor_id AND sub_role = 'supervisor' AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Staff % is not an active supervisor.', p_supervisor_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM recycling_facilities WHERE facility_id = p_facility_id AND is_operational = TRUE) THEN
        RAISE EXCEPTION 'Facility % is not operational.', p_facility_id;
    END IF;

    UPDATE pickup_requests
    SET    status               = 'supervisor_assigned',
           supervisor_id        = p_supervisor_id,
           assigned_facility_id = p_facility_id,
           updated_at           = NOW()
    WHERE  pickup_id = p_pickup_id;

    p_success := TRUE;
END;
$$;


-- ── supervisor_assign_field ───────────────────────────────
-- Supervisor assigns driver + collector + vehicle from their own team.
CREATE OR REPLACE PROCEDURE supervisor_assign_field(
    IN  p_pickup_id    INT,
    IN  p_supervisor_id INT,   -- must match pickup's supervisor_id
    IN  p_driver_id    INT,
    IN  p_collector_id INT,
    IN  p_vehicle_id   INT,
    OUT p_success      BOOLEAN
) LANGUAGE plpgsql AS $$
BEGIN
    -- Pickup must be supervisor_assigned AND belong to this supervisor
    IF NOT EXISTS (
        SELECT 1 FROM pickup_requests
        WHERE pickup_id = p_pickup_id
          AND status = 'supervisor_assigned'
          AND supervisor_id = p_supervisor_id
    ) THEN
        RAISE EXCEPTION 'Pickup % is not available for field assignment by supervisor %.', p_pickup_id, p_supervisor_id;
    END IF;

    -- Driver must be under this supervisor
    IF NOT EXISTS (
        SELECT 1 FROM staff
        WHERE staff_id = p_driver_id AND sub_role = 'driver'
          AND supervisor_id = p_supervisor_id AND is_active = TRUE AND is_available = TRUE
    ) THEN
        RAISE EXCEPTION 'Driver % is not available under supervisor %.', p_driver_id, p_supervisor_id;
    END IF;

    -- Collector must be under this supervisor
    IF NOT EXISTS (
        SELECT 1 FROM staff
        WHERE staff_id = p_collector_id AND sub_role = 'collector'
          AND supervisor_id = p_supervisor_id AND is_active = TRUE AND is_available = TRUE
    ) THEN
        RAISE EXCEPTION 'Collector % is not available under supervisor %.', p_collector_id, p_supervisor_id;
    END IF;

    -- Vehicle must belong to this supervisor
    IF NOT EXISTS (
        SELECT 1 FROM vehicles
        WHERE vehicle_id = p_vehicle_id AND supervisor_id = p_supervisor_id AND is_available = TRUE
    ) THEN
        RAISE EXCEPTION 'Vehicle % does not belong to or is unavailable for supervisor %.', p_vehicle_id, p_supervisor_id;
    END IF;

    UPDATE pickup_requests
    SET    status              = 'field_assigned',
           driver_id           = p_driver_id,
           collector_id        = p_collector_id,
           assigned_vehicle_id = p_vehicle_id,
           scheduled_time      = NOW() + INTERVAL '2 hours',
           updated_at          = NOW()
    WHERE  pickup_id = p_pickup_id;

    p_success := TRUE;
END;
$$;


-- ── collect_pickup ────────────────────────────────────────
-- COLLECTOR confirms physical e-waste collection and records item weights.
-- Status: field_assigned -> picked_up
-- If driver also already confirmed (unusual but possible): -> collected
CREATE OR REPLACE PROCEDURE collect_pickup(
    IN p_pickup_id     INT,
    IN p_staff_id      INT,
    IN p_item_weights  JSONB,   -- [{"item_id":1,"weight":2.5}, ...]
    OUT p_success      BOOLEAN
) LANGUAGE plpgsql AS $$
DECLARE
    v_item    JSONB;
    v_iid     INT;
    v_wt      DECIMAL(8,2);
    v_drv_ok  BOOLEAN;
BEGIN
    -- Must be field_assigned and staff must be the COLLECTOR on this pickup
    IF NOT EXISTS (
        SELECT 1 FROM pickup_requests
        WHERE pickup_id = p_pickup_id
          AND status = 'field_assigned'
          AND collector_id = p_staff_id
    ) THEN
        RAISE EXCEPTION 'Pickup % is not available for collection by staff %.', p_pickup_id, p_staff_id;
    END IF;

    -- Apply each item weight
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_item_weights)
    LOOP
        v_iid := (v_item->>'item_id')::INT;
        v_wt  := (v_item->>'weight')::DECIMAL;
        UPDATE items SET actual_weight_kg = v_wt WHERE item_id = v_iid AND pickup_id = p_pickup_id;
        INSERT INTO weight_records (item_id, weighing_stage, weight_kg, weighed_by)
        VALUES (v_iid, 'pickup', v_wt, p_staff_id);
    END LOOP;

    -- Check if driver already confirmed delivery
    SELECT driver_confirmed INTO v_drv_ok FROM pickup_requests WHERE pickup_id = p_pickup_id;

    IF v_drv_ok THEN
        -- Both done: fully collected, open payment window
        UPDATE pickup_requests
        SET    status                  = 'collected',
               collector_confirmed     = TRUE,
               collector_confirmed_at  = NOW(),
               collected_at            = NOW(),
               payment_due_by          = NOW() + INTERVAL '72 hours',
               updated_at              = NOW()
        WHERE  pickup_id = p_pickup_id;
    ELSE
        -- Collector done, waiting for driver delivery
        UPDATE pickup_requests
        SET    status                  = 'picked_up',
               collector_confirmed     = TRUE,
               collector_confirmed_at  = NOW(),
               updated_at              = NOW()
        WHERE  pickup_id = p_pickup_id;
    END IF;

    p_success := TRUE;
END;
$$;


-- ── deliver_pickup ─────────────────────────────────────────
-- DRIVER confirms delivery of e-waste to the recycling facility.
-- Collector MUST have confirmed physical collection first (status = 'picked_up').
-- Status: picked_up -> collected (payment window opens)
CREATE OR REPLACE PROCEDURE deliver_pickup(
    IN p_pickup_id  INT,
    IN p_staff_id   INT,
    OUT p_success   BOOLEAN
) LANGUAGE plpgsql AS $$
BEGIN
    -- Must be picked_up (collector confirmed) and staff must be the DRIVER
    IF NOT EXISTS (
        SELECT 1 FROM pickup_requests
        WHERE pickup_id = p_pickup_id
          AND status = 'picked_up'
          AND collector_confirmed = TRUE
          AND driver_id = p_staff_id
    ) THEN
        -- Give a clear reason so the flash message is helpful
        IF EXISTS (
            SELECT 1 FROM pickup_requests
            WHERE pickup_id = p_pickup_id AND driver_id = p_staff_id
              AND status = 'field_assigned'
        ) THEN
            RAISE EXCEPTION 'Cannot confirm delivery: the collector has not collected the items yet. Wait for the collector to complete their step first.';
        END IF;
        RAISE EXCEPTION 'Pickup % is not available for delivery confirmation by driver %.', p_pickup_id, p_staff_id;
    END IF;

    -- Collector already confirmed, driver now confirms -> fully collected
    UPDATE pickup_requests
    SET    status              = 'collected',
           driver_confirmed    = TRUE,
           driver_confirmed_at = NOW(),
           collected_at        = NOW(),
           payment_due_by      = NOW() + INTERVAL '72 hours',
           updated_at          = NOW()
    WHERE  pickup_id = p_pickup_id;

    p_success := TRUE;
END;
$$;


-- ── supervisor_process_payment ────────────────────────────
-- Supervisor processes payment for a collected pickup.
-- Amount can be 0 (zero-value junk is valid).
CREATE OR REPLACE PROCEDURE supervisor_process_payment(
    IN  p_pickup_id      INT,
    IN  p_supervisor_id  INT,
    IN  p_method         VARCHAR(30),
    IN  p_txn_ref        VARCHAR(100),
    IN  p_custom_amount  DECIMAL(10,2),   -- NULL = auto-calculate from items
    OUT p_payment_id     INT,
    OUT p_amount         DECIMAL(10,2)
) LANGUAGE plpgsql AS $$
DECLARE
    v_total  DECIMAL(10,2) := 0;
    v_item   RECORD;
BEGIN
    -- Must be collected and under this supervisor
    IF NOT EXISTS (
        SELECT 1 FROM pickup_requests
        WHERE pickup_id = p_pickup_id AND status = 'collected' AND supervisor_id = p_supervisor_id
    ) THEN
        RAISE EXCEPTION 'Pickup % is not a collected pickup under supervisor %.', p_pickup_id, p_supervisor_id;
    END IF;

    IF p_custom_amount IS NOT NULL AND p_custom_amount >= 0 THEN
        -- Supervisor provided a custom amount (override)
        v_total := p_custom_amount;
    ELSE
        -- Auto-calculate from items
        FOR v_item IN SELECT item_id FROM items WHERE pickup_id = p_pickup_id LOOP
            v_total := v_total + calculate_item_value(v_item.item_id);
        END LOOP;
    END IF;

    INSERT INTO payments (pickup_id, amount, payment_method, payment_status,
                          transaction_reference, processed_by)
    VALUES (p_pickup_id, v_total, p_method, 'completed', p_txn_ref, p_supervisor_id)
    RETURNING payment_id, amount INTO p_payment_id, p_amount;

    UPDATE pickup_requests
    SET    total_amount    = v_total,
           status          = 'completed',
           completed_time  = NOW(),
           updated_at      = NOW()
    WHERE  pickup_id = p_pickup_id;

    -- Resolve any open payment requests for this pickup
    UPDATE payment_requests
    SET status = 'resolved'
    WHERE pickup_id = p_pickup_id AND status = 'pending';

    -- Update user last_pickup_at
    UPDATE users u
    SET    last_pickup_at = NOW()
    FROM   pickup_requests p
    WHERE  p.pickup_id = p_pickup_id AND u.user_id = p.user_id;
END;
$$;


-- ── request_payment ───────────────────────────────────────
-- User requests payment after the payment_due_by window passes.
-- Duplicate requests generate an admin alert automatically (via trigger).
CREATE OR REPLACE PROCEDURE request_payment(
    IN  p_pickup_id  INT,
    IN  p_user_id    INT,
    IN  p_notes      TEXT,
    OUT p_request_id INT
) LANGUAGE plpgsql AS $$
DECLARE
    v_supervisor_id INT;
    v_due_by        TIMESTAMP;
    v_is_duplicate  BOOLEAN := FALSE;
BEGIN
    SELECT supervisor_id, payment_due_by
    INTO   v_supervisor_id, v_due_by
    FROM   pickup_requests
    WHERE  pickup_id = p_pickup_id AND user_id = p_user_id AND status = 'collected';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pickup % is not a collected pickup for user %.', p_pickup_id, p_user_id;
    END IF;

    IF v_due_by IS NULL OR NOW() < v_due_by THEN
        RAISE EXCEPTION 'Payment request window has not opened yet. Please wait until %.',
              COALESCE(v_due_by::TEXT, 'the scheduled time');
    END IF;

    -- Check if already-paid
    IF EXISTS (SELECT 1 FROM payments WHERE pickup_id = p_pickup_id AND payment_status = 'completed') THEN
        RAISE EXCEPTION 'Payment for pickup % has already been processed.', p_pickup_id;
    END IF;

    -- Check for existing pending request = duplicate
    IF EXISTS (SELECT 1 FROM payment_requests WHERE pickup_id = p_pickup_id AND status = 'pending') THEN
        v_is_duplicate := TRUE;
    END IF;

    INSERT INTO payment_requests (pickup_id, user_id, supervisor_id, notes, is_duplicate)
    VALUES (p_pickup_id, p_user_id, v_supervisor_id, p_notes, v_is_duplicate)
    RETURNING request_id INTO p_request_id;

    -- Increment counter on pickup
    UPDATE pickup_requests
    SET payment_request_count = payment_request_count + 1
    WHERE pickup_id = p_pickup_id;
END;
$$;


-- ── process_batch ─────────────────────────────────────────
-- Supervisor starts processing a batch (must have ≥2 distinct pickups).
-- Admin can also call this.
CREATE OR REPLACE PROCEDURE process_batch(
    IN  p_batch_id      INT,
    IN  p_supervisor_id INT,   -- NULL if admin is calling
    OUT p_success       BOOLEAN
) LANGUAGE plpgsql AS $$
DECLARE
    v_pickup_count BIGINT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM recycling_batches WHERE batch_id = p_batch_id AND status = 'open') THEN
        RAISE EXCEPTION 'Batch % is not in open status.', p_batch_id;
    END IF;

    -- Enforce minimum 2 distinct pickups
    SELECT get_batch_pickup_count(p_batch_id) INTO v_pickup_count;
    IF v_pickup_count < 2 THEN
        RAISE EXCEPTION 'Batch % must contain items from at least 2 distinct pickups (currently %). Add more items before processing.', p_batch_id, v_pickup_count;
    END IF;

    -- Recalculate total weight
    UPDATE recycling_batches
    SET    status                = 'processing',
           processing_start_date = CURRENT_DATE,
           total_weight_kg       = (
               SELECT COALESCE(SUM(i.actual_weight_kg), 0)
               FROM   batch_items bi
               JOIN   items i ON bi.item_id = i.item_id
               WHERE  bi.batch_id = p_batch_id
           ),
           supervisor_id = COALESCE(p_supervisor_id, supervisor_id)
    WHERE  batch_id = p_batch_id;

    p_success := TRUE;
END;
$$;


-- ── complete_batch ────────────────────────────────────────
-- Mark batch completed and record material recovery revenue.
CREATE OR REPLACE PROCEDURE complete_batch(
    IN  p_batch_id          INT,
    IN  p_recovery_rate     DECIMAL(5,2),
    IN  p_revenue_entries   JSONB,  -- [{"material":"copper","weight":12.5,"price_per_kg":8.50}]
    IN  p_recorded_by       INT,    -- staff_id
    OUT p_total_revenue     DECIMAL(12,2)
) LANGUAGE plpgsql AS $$
DECLARE
    v_entry  JSONB;
    v_total  DECIMAL(12,2) := 0;
    v_facility INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM recycling_batches WHERE batch_id = p_batch_id AND status = 'processing') THEN
        RAISE EXCEPTION 'Batch % must be in processing state to complete.', p_batch_id;
    END IF;

    SELECT facility_id INTO v_facility FROM recycling_batches WHERE batch_id = p_batch_id;

    -- Insert revenue entries
    FOR v_entry IN SELECT * FROM jsonb_array_elements(p_revenue_entries) LOOP
        INSERT INTO system_revenue (batch_id, facility_id, material_type, weight_kg, price_per_kg, recorded_by)
        VALUES (
            p_batch_id, v_facility,
            v_entry->>'material',
            (v_entry->>'weight')::DECIMAL,
            (v_entry->>'price_per_kg')::DECIMAL,
            p_recorded_by
        );
        v_total := v_total + ((v_entry->>'weight')::DECIMAL * (v_entry->>'price_per_kg')::DECIMAL);
    END LOOP;

    UPDATE recycling_batches
    SET    status                 = 'completed',
           processing_end_date    = CURRENT_DATE,
           recovery_rate_percentage = p_recovery_rate,
           total_revenue           = v_total
    WHERE  batch_id = p_batch_id;

    p_total_revenue := v_total;
END;
$$;


-- ── fire_staff ────────────────────────────────────────────
-- Admin soft-deletes a staff member. Disables their account.
CREATE OR REPLACE PROCEDURE fire_staff(
    IN  p_staff_id  INT,
    IN  p_admin_account_id INT,
    IN  p_reason    TEXT,
    OUT p_success   BOOLEAN
) LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM staff WHERE staff_id = p_staff_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Staff % not found or already inactive.', p_staff_id;
    END IF;

    UPDATE staff
    SET    is_active    = FALSE,
           is_available = FALSE,
           fired_at     = NOW(),
           fired_by     = p_admin_account_id
    WHERE  staff_id = p_staff_id;

    -- Disable login
    UPDATE accounts SET is_active = FALSE WHERE staff_id = p_staff_id;

    -- Log to audit
    INSERT INTO audit_log (table_name, operation, record_id, new_values, changed_by)
    VALUES ('staff', 'FIRE', p_staff_id,
            jsonb_build_object('staff_id', p_staff_id, 'fired_by', p_admin_account_id, 'reason', p_reason),
            (SELECT username FROM accounts WHERE account_id = p_admin_account_id));

    -- Create admin alert
    INSERT INTO admin_alerts (alert_type, severity, title, description, related_table, related_id, payload)
    VALUES ('staff_fired', 'medium', 'Staff Member Fired',
            'A staff member was deactivated.',
            'staff', p_staff_id,
            jsonb_build_object('staff_id', p_staff_id, 'reason', p_reason, 'fired_by', p_admin_account_id));

    p_success := TRUE;
END;
$$;


-- ── issue_warning ─────────────────────────────────────────
CREATE OR REPLACE PROCEDURE issue_warning(
    IN  p_admin_account_id INT,
    IN  p_target_type      VARCHAR(10),
    IN  p_target_id        INT,      -- user_id or staff_id
    IN  p_severity         VARCHAR(20),
    IN  p_message          TEXT,
    OUT p_warning_id       INT
) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO warnings (issued_by, target_type, target_user_id, target_staff_id, severity, message)
    VALUES (
        p_admin_account_id,
        p_target_type,
        CASE WHEN p_target_type = 'user'  THEN p_target_id ELSE NULL END,
        CASE WHEN p_target_type = 'staff' THEN p_target_id ELSE NULL END,
        p_severity,
        p_message
    )
    RETURNING warning_id INTO p_warning_id;

    -- Suspension severity automatically suspends user
    IF p_target_type = 'user' AND p_severity = 'suspension' THEN
        UPDATE users SET user_status = 'suspended', is_active = FALSE WHERE user_id = p_target_id;
        UPDATE accounts SET is_active = FALSE WHERE user_id = p_target_id;
    END IF;
END;
$$;


-- ── add_vehicle ───────────────────────────────────────────
-- Admin adds a vehicle and assigns it to a supervisor.
CREATE OR REPLACE PROCEDURE add_vehicle(
    IN  p_vehicle_number VARCHAR(20),
    IN  p_vehicle_type   VARCHAR(30),
    IN  p_capacity_kg    DECIMAL(8,2),
    IN  p_supervisor_id  INT,
    OUT p_vehicle_id     INT
) LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM staff WHERE staff_id = p_supervisor_id AND sub_role = 'supervisor' AND is_active) THEN
        RAISE EXCEPTION 'Supervisor % not found or inactive.', p_supervisor_id;
    END IF;
    INSERT INTO vehicles (vehicle_number, vehicle_type, capacity_kg, supervisor_id)
    VALUES (p_vehicle_number, p_vehicle_type, p_capacity_kg, p_supervisor_id)
    RETURNING vehicle_id INTO p_vehicle_id;
END;
$$;
