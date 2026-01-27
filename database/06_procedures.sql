-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 06_procedures.sql - Business Workflow Engine (MOST IMPORTANT FILE)

-- Procedure 1: Create Pickup Request
CREATE OR REPLACE PROCEDURE create_pickup_request(
    OUT p_pickup_id INT,
    p_user_id INT,
    p_preferred_date DATE,
    p_pickup_address TEXT,
    p_notes TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Validate user exists and is active
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'User % does not exist or is inactive', p_user_id;
    END IF;

    -- Validate preferred date is not in the past
    IF p_preferred_date < CURRENT_DATE THEN
        RAISE EXCEPTION 'Preferred date cannot be in the past';
    END IF;

    -- Insert pickup request
    INSERT INTO pickup_requests (
        user_id, preferred_date, pickup_address, status, notes
    ) VALUES (
        p_user_id, p_preferred_date, p_pickup_address, 'pending', p_notes
    ) RETURNING pickup_id INTO p_pickup_id;

    RAISE NOTICE 'Pickup request % created successfully', p_pickup_id;
END;
$$;

-- Procedure 2: Add Item to Pickup
CREATE OR REPLACE PROCEDURE add_item_to_pickup(
    OUT p_item_id INT,
    p_pickup_id INT,
    p_category_id INT,
    p_item_description TEXT,
    p_condition VARCHAR DEFAULT 'broken',
    p_estimated_weight_kg DECIMAL DEFAULT NULL,
    p_hazard_details JSONB DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_pickup_status VARCHAR;
BEGIN
    -- Validate pickup exists and is in valid status
    SELECT status INTO v_pickup_status
    FROM pickup_requests
    WHERE pickup_id = p_pickup_id;

    IF v_pickup_status IS NULL THEN
        RAISE EXCEPTION 'Pickup request % does not exist', p_pickup_id;
    END IF;

    IF v_pickup_status NOT IN ('pending', 'assigned') THEN
        RAISE EXCEPTION 'Cannot add items to pickup with status %', v_pickup_status;
    END IF;

    -- Validate category exists
    IF NOT EXISTS (SELECT 1 FROM categories WHERE category_id = p_category_id) THEN
        RAISE EXCEPTION 'Category % does not exist', p_category_id;
    END IF;

    -- Insert item
    INSERT INTO items (
        pickup_id, category_id, item_description, condition,
        estimated_weight_kg, hazard_details
    ) VALUES (
        p_pickup_id, p_category_id, p_item_description, p_condition,
        p_estimated_weight_kg, p_hazard_details
    ) RETURNING item_id INTO p_item_id;

    -- Update pickup totals
    UPDATE pickup_requests
    SET total_weight_kg = get_pickup_total_weight(p_pickup_id),
        total_amount = get_pickup_total_amount(p_pickup_id),
        updated_at = CURRENT_TIMESTAMP
    WHERE pickup_id = p_pickup_id;

    RAISE NOTICE 'Item % added to pickup %', p_item_id, p_pickup_id;
END;
$$;

-- Procedure 3: Record Weight for Item
CREATE OR REPLACE PROCEDURE record_item_weight(
    p_item_id INT,
    p_weighing_stage VARCHAR,
    p_weight_kg DECIMAL,
    p_weighed_by VARCHAR DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_pickup_id INT;
BEGIN
    -- Validate item exists
    SELECT pickup_id INTO v_pickup_id
    FROM items
    WHERE item_id = p_item_id;

    IF v_pickup_id IS NULL THEN
        RAISE EXCEPTION 'Item % does not exist', p_item_id;
    END IF;

    -- Insert weight record
    INSERT INTO weight_records (
        item_id, weighing_stage, weight_kg, weighed_by, notes
    ) VALUES (
        p_item_id, p_weighing_stage, p_weight_kg, p_weighed_by, p_notes
    );

    -- Update actual weight in items table if this is the official weighing
    IF p_weighing_stage = 'pickup' THEN
        UPDATE items
        SET actual_weight_kg = p_weight_kg
        WHERE item_id = p_item_id;

        -- Recalculate pickup totals
        UPDATE pickup_requests
        SET total_weight_kg = get_pickup_total_weight(v_pickup_id),
            total_amount = get_pickup_total_amount(v_pickup_id),
            updated_at = CURRENT_TIMESTAMP
        WHERE pickup_id = v_pickup_id;
    END IF;

    RAISE NOTICE 'Weight recorded for item % at stage %', p_item_id, p_weighing_stage;
END;
$$;

-- Procedure 4: Assign Pickup to Staff
CREATE OR REPLACE PROCEDURE assign_pickup_to_staff(
    p_pickup_id INT,
    p_staff_id INT,
    p_vehicle_id INT,
    p_facility_id INT,
    p_scheduled_time TIMESTAMP DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_pickup_weight DECIMAL;
    v_current_status VARCHAR;
BEGIN
    -- Get current pickup info
    SELECT status, total_weight_kg
    INTO v_current_status, v_pickup_weight
    FROM pickup_requests
    WHERE pickup_id = p_pickup_id;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'Pickup % does not exist', p_pickup_id;
    END IF;

    IF v_current_status != 'pending' THEN
        RAISE EXCEPTION 'Pickup % is not in pending status', p_pickup_id;
    END IF;

    -- Validate staff is available
    IF NOT EXISTS (SELECT 1 FROM staff_assignments WHERE staff_id = p_staff_id AND is_available = TRUE) THEN
        RAISE EXCEPTION 'Staff % is not available', p_staff_id;
    END IF;

    -- Validate vehicle is available and has capacity
    IF NOT check_vehicle_capacity(p_vehicle_id, v_pickup_weight) THEN
        RAISE EXCEPTION 'Vehicle % does not have sufficient capacity', p_vehicle_id;
    END IF;

    -- Validate facility has capacity
    IF NOT check_facility_capacity(p_facility_id, v_pickup_weight) THEN
        RAISE EXCEPTION 'Facility % does not have sufficient capacity', p_facility_id;
    END IF;

    -- Update pickup request
    UPDATE pickup_requests
    SET assigned_staff_id = p_staff_id,
        assigned_vehicle_id = p_vehicle_id,
        assigned_facility_id = p_facility_id,
        scheduled_time = COALESCE(p_scheduled_time, CURRENT_TIMESTAMP + INTERVAL '1 day'),
        status = 'assigned',
        updated_at = CURRENT_TIMESTAMP
    WHERE pickup_id = p_pickup_id;

    -- Update staff availability
    UPDATE staff_assignments
    SET is_available = FALSE
    WHERE staff_id = p_staff_id;

    -- Update vehicle load
    UPDATE vehicles
    SET current_load_kg = current_load_kg + v_pickup_weight,
        is_available = FALSE
    WHERE vehicle_id = p_vehicle_id;

    RAISE NOTICE 'Pickup % assigned to staff %', p_pickup_id, p_staff_id;
END;
$$;

-- Procedure 5: Complete Pickup Collection
CREATE OR REPLACE PROCEDURE complete_pickup_collection(
    p_pickup_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
    v_weight DECIMAL;
    v_facility_id INT;
BEGIN
    -- Get pickup details
    SELECT status, total_weight_kg, assigned_facility_id
    INTO v_status, v_weight, v_facility_id
    FROM pickup_requests
    WHERE pickup_id = p_pickup_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Pickup % does not exist', p_pickup_id;
    END IF;

    IF v_status != 'assigned' THEN
        RAISE EXCEPTION 'Pickup % is not in assigned status', p_pickup_id;
    END IF;

    -- Update pickup status
    UPDATE pickup_requests
    SET status = 'collected',
        updated_at = CURRENT_TIMESTAMP
    WHERE pickup_id = p_pickup_id;

    -- Update facility load
    IF v_facility_id IS NOT NULL THEN
        UPDATE recycling_facilities
        SET current_load_kg = current_load_kg + v_weight
        WHERE facility_id = v_facility_id;
    END IF;

    RAISE NOTICE 'Pickup % marked as collected', p_pickup_id;
END;
$$;

-- Procedure 6: Process Payment
CREATE OR REPLACE PROCEDURE process_payment(
    OUT p_payment_id INT,
    OUT p_amount DECIMAL,
    p_pickup_id INT,
    p_payment_method VARCHAR,
    p_transaction_reference VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
    v_total_amount DECIMAL;
    v_vehicle_id INT;
    v_staff_id INT;
BEGIN
    -- Get pickup details
    SELECT status, total_amount, assigned_vehicle_id, assigned_staff_id
    INTO v_status, v_total_amount, v_vehicle_id, v_staff_id
    FROM pickup_requests
    WHERE pickup_id = p_pickup_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Pickup % does not exist', p_pickup_id;
    END IF;

    IF v_status != 'collected' THEN
        RAISE EXCEPTION 'Cannot process payment for pickup with status %', v_status;
    END IF;

    IF v_total_amount <= 0 THEN
        RAISE EXCEPTION 'Pickup % has no amount to pay', p_pickup_id;
    END IF;

    -- Insert payment record
    INSERT INTO payments (
        pickup_id, amount, payment_method, payment_status, transaction_reference
    ) VALUES (
        p_pickup_id, v_total_amount, p_payment_method, 'completed', p_transaction_reference
    ) RETURNING payment_id, amount INTO p_payment_id, p_amount;

    -- Update pickup status to completed
    UPDATE pickup_requests
    SET status = 'completed',
        completed_time = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE pickup_id = p_pickup_id;

    -- Free up staff and vehicle
    IF v_staff_id IS NOT NULL THEN
        UPDATE staff_assignments
        SET is_available = TRUE
        WHERE staff_id = v_staff_id;
    END IF;

    IF v_vehicle_id IS NOT NULL THEN
        UPDATE vehicles
        SET current_load_kg = 0,
            is_available = TRUE
        WHERE vehicle_id = v_vehicle_id;
    END IF;

    RAISE NOTICE 'Payment % processed for pickup %: $%', p_payment_id, p_pickup_id, p_amount;
END;
$$;

-- Procedure 7: Create Recycling Batch
CREATE OR REPLACE PROCEDURE create_recycling_batch(
    OUT p_batch_id INT,
    p_facility_id INT,
    p_batch_name VARCHAR,
    p_notes TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Validate facility exists and is operational
    IF NOT EXISTS (SELECT 1 FROM recycling_facilities WHERE facility_id = p_facility_id AND is_operational = TRUE) THEN
        RAISE EXCEPTION 'Facility % does not exist or is not operational', p_facility_id;
    END IF;

    -- Create batch
    INSERT INTO recycling_batches (
        facility_id, batch_name, status, notes
    ) VALUES (
        p_facility_id, p_batch_name, 'open', p_notes
    ) RETURNING batch_id INTO p_batch_id;

    RAISE NOTICE 'Batch % created at facility %', p_batch_id, p_facility_id;
END;
$$;

-- Procedure 8: Add Item to Batch
CREATE OR REPLACE PROCEDURE add_item_to_batch(
    p_batch_id INT,
    p_item_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_batch_status VARCHAR;
    v_item_pickup_status VARCHAR;
BEGIN
    -- Validate batch exists and is open
    SELECT status INTO v_batch_status
    FROM recycling_batches
    WHERE batch_id = p_batch_id;

    IF v_batch_status IS NULL THEN
        RAISE EXCEPTION 'Batch % does not exist', p_batch_id;
    END IF;

    IF v_batch_status != 'open' THEN
        RAISE EXCEPTION 'Batch % is not open for new items', p_batch_id;
    END IF;

    -- Validate item exists and pickup is completed
    SELECT p.status INTO v_item_pickup_status
    FROM items i
    JOIN pickup_requests p ON i.pickup_id = p.pickup_id
    WHERE i.item_id = p_item_id;

    IF v_item_pickup_status IS NULL THEN
        RAISE EXCEPTION 'Item % does not exist', p_item_id;
    END IF;

    IF v_item_pickup_status != 'completed' THEN
        RAISE EXCEPTION 'Item % pickup is not completed', p_item_id;
    END IF;

    -- Check if item is already in a batch
    IF EXISTS (SELECT 1 FROM batch_items WHERE item_id = p_item_id) THEN
        RAISE EXCEPTION 'Item % is already in a batch', p_item_id;
    END IF;

    -- Add item to batch
    INSERT INTO batch_items (batch_id, item_id)
    VALUES (p_batch_id, p_item_id);

    -- Update batch total weight
    UPDATE recycling_batches
    SET total_weight_kg = get_batch_total_weight(p_batch_id)
    WHERE batch_id = p_batch_id;

    RAISE NOTICE 'Item % added to batch %', p_item_id, p_batch_id;
END;
$$;

-- Procedure 9: Start Batch Processing
CREATE OR REPLACE PROCEDURE start_batch_processing(
    p_batch_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
BEGIN
    SELECT status INTO v_status
    FROM recycling_batches
    WHERE batch_id = p_batch_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Batch % does not exist', p_batch_id;
    END IF;

    IF v_status != 'open' THEN
        RAISE EXCEPTION 'Batch % is not in open status', p_batch_id;
    END IF;

    UPDATE recycling_batches
    SET status = 'processing',
        processing_start_date = CURRENT_DATE
    WHERE batch_id = p_batch_id;

    RAISE NOTICE 'Batch % processing started', p_batch_id;
END;
$$;

-- Procedure 10: Complete Batch Processing
CREATE OR REPLACE PROCEDURE complete_batch_processing(
    p_batch_id INT,
    p_recovery_rate_percentage DECIMAL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
    v_facility_id INT;
    v_weight DECIMAL;
BEGIN
    SELECT status, facility_id, total_weight_kg
    INTO v_status, v_facility_id, v_weight
    FROM recycling_batches
    WHERE batch_id = p_batch_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Batch % does not exist', p_batch_id;
    END IF;

    IF v_status != 'processing' THEN
        RAISE EXCEPTION 'Batch % is not in processing status', p_batch_id;
    END IF;

    UPDATE recycling_batches
    SET status = 'completed',
        processing_end_date = CURRENT_DATE,
        recovery_rate_percentage = p_recovery_rate_percentage
    WHERE batch_id = p_batch_id;

    -- Reduce facility load
    UPDATE recycling_facilities
    SET current_load_kg = GREATEST(current_load_kg - v_weight, 0)
    WHERE facility_id = v_facility_id;

    RAISE NOTICE 'Batch % completed with % recovery rate', p_batch_id, p_recovery_rate_percentage;
END;
$$;

-- Comments explaining procedure design:
-- 1. Each procedure represents a complete business workflow
-- 2. All validations happen inside procedures
-- 3. Multiple tables updated in single transaction
-- 4. OUT parameters return generated IDs
-- 5. RAISE EXCEPTION rolls back transaction on error
-- 6. RAISE NOTICE provides feedback on success
-- 7. Status transitions validated
-- 8. Referential integrity maintained
-- 9. Procedures call functions for calculations
-- 10. This is the core of the system's intelligence