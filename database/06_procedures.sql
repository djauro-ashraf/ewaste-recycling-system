-- =========================
-- 06_procedures.sql
-- Stored Procedures
-- =========================

-- 1. Schedule a new pickup request
CREATE OR REPLACE PROCEDURE schedule_pickup(
    p_user_id INT,
    p_request_date DATE,
    p_status VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO pickup_requests (user_id, request_date, status)
    VALUES (p_user_id, p_request_date, p_status);
END;
$$;


-- 2. Assign staff and vehicle to a pickup request
CREATE OR REPLACE PROCEDURE assign_vehicle_and_staff(
    p_request_id INT,
    p_staff_id INT,
    p_vehicle_id INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE pickup_requests
    SET assigned_staff_id = p_staff_id,
        assigned_vehicle_id = p_vehicle_id,
        status = 'ASSIGNED'
    WHERE request_id = p_request_id;
END;
$$;


-- 3. Create payment record for a pickup request
CREATE OR REPLACE PROCEDURE create_payment_record(
    p_request_id INT,
    p_payment_method VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    total_amount NUMERIC;
BEGIN
    total_amount := total_request_cost(p_request_id);

    INSERT INTO payments (request_id, amount, payment_method, payment_status)
    VALUES (p_request_id, total_amount, p_payment_method, 'PENDING');
END;
$$;


-- 4. Add item to recycling batch
CREATE OR REPLACE PROCEDURE add_item_to_batch(
    p_batch_id INT,
    p_item_id INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO batch_items (batch_id, item_id)
    VALUES (p_batch_id, p_item_id);
END;
$$;


-- 5. Create new recycling batch
CREATE OR REPLACE PROCEDURE create_recycling_batch(
    p_facility_id INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO recycling_batches (facility_id)
    VALUES (p_facility_id);
END;
$$;
