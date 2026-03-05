-- ============================================================
-- 06b_procedures_extra.sql
-- Additional procedures called by the Flask app
-- ============================================================

CREATE OR REPLACE PROCEDURE create_recycling_batch_v2(
    IN  p_facility_id   INT,
    IN  p_batch_name    VARCHAR(100),
    IN  p_notes         TEXT,
    IN  p_supervisor_id INT,
    OUT p_batch_id      INT
) LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM recycling_facilities WHERE facility_id = p_facility_id AND is_operational) THEN
        RAISE EXCEPTION 'Facility % is not operational.', p_facility_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM staff WHERE staff_id = p_supervisor_id AND sub_role = 'supervisor' AND is_active) THEN
        RAISE EXCEPTION 'Supervisor % not found or inactive.', p_supervisor_id;
    END IF;

    INSERT INTO recycling_batches (facility_id, supervisor_id, batch_name, notes)
    VALUES (p_facility_id, p_supervisor_id, p_batch_name, p_notes)
    RETURNING batch_id INTO p_batch_id;
END;
$$;
