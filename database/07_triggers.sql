-- ============================================================
-- 07_triggers.sql — Automated Database Triggers (9 triggers)
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- T1: trg_audit_pickups
-- Full JSON snapshot of every change to pickup_requests.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_audit_pickups()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_values, new_values, changed_by)
    VALUES (
        'pickup_requests', TG_OP,
        COALESCE(NEW.pickup_id, OLD.pickup_id),
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE row_to_json(OLD)::JSONB END,
        CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE row_to_json(NEW)::JSONB END,
        current_setting('app.current_user', TRUE)
    );
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_audit_pickups
AFTER INSERT OR UPDATE OR DELETE ON pickup_requests
FOR EACH ROW EXECUTE FUNCTION fn_audit_pickups();


-- ────────────────────────────────────────────────────────────
-- T2: trg_audit_payments
-- Audit trail for every payment row change.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_audit_payments()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_values, new_values, changed_by)
    VALUES (
        'payments', TG_OP,
        COALESCE(NEW.payment_id, OLD.payment_id),
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE row_to_json(OLD)::JSONB END,
        CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE row_to_json(NEW)::JSONB END,
        current_setting('app.current_user', TRUE)
    );
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_audit_payments
AFTER INSERT OR UPDATE OR DELETE ON payments
FOR EACH ROW EXECUTE FUNCTION fn_audit_payments();


-- ────────────────────────────────────────────────────────────
-- T3: trg_pickup_updated_at
-- Auto-stamp updated_at on any pickup change.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_pickup_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_pickup_updated_at
BEFORE UPDATE ON pickup_requests
FOR EACH ROW EXECUTE FUNCTION fn_pickup_updated_at();


-- ────────────────────────────────────────────────────────────
-- T4: trg_update_facility_load
-- Adds/subtracts from facility current_load_kg when pickup
-- transitions to/from 'collected'.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_update_facility_load()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'collected' AND OLD.status IS DISTINCT FROM 'collected'
       AND NEW.assigned_facility_id IS NOT NULL THEN
        UPDATE recycling_facilities
        SET    current_load_kg = current_load_kg + NEW.total_weight_kg
        WHERE  facility_id = NEW.assigned_facility_id;

    ELSIF NEW.status = 'cancelled' AND OLD.status = 'collected'
          AND OLD.assigned_facility_id IS NOT NULL THEN
        UPDATE recycling_facilities
        SET    current_load_kg = GREATEST(0, current_load_kg - OLD.total_weight_kg)
        WHERE  facility_id = OLD.assigned_facility_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_facility_load
AFTER UPDATE ON pickup_requests
FOR EACH ROW EXECUTE FUNCTION fn_update_facility_load();


-- ────────────────────────────────────────────────────────────
-- T5: trg_prevent_duplicate_payment
-- Blocks double-payment at database level.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_prevent_duplicate_payment()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM payments
        WHERE  pickup_id = NEW.pickup_id AND payment_status = 'completed'
    ) THEN
        RAISE EXCEPTION 'Completed payment already exists for pickup %.', NEW.pickup_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_duplicate_payment
BEFORE INSERT ON payments
FOR EACH ROW EXECUTE FUNCTION fn_prevent_duplicate_payment();


-- ────────────────────────────────────────────────────────────
-- T6: trg_recalculate_pickup_totals
-- Whenever an item's actual_weight_kg changes, recompute the
-- pickup's total weight and total payout (0 allowed).
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_recalculate_pickup_totals()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_total_weight DECIMAL(10,2);
    v_total_amount DECIMAL(10,2) := 0;
    v_item         RECORD;
BEGIN
    SELECT COALESCE(SUM(actual_weight_kg), 0)
    INTO   v_total_weight
    FROM   items WHERE pickup_id = NEW.pickup_id;

    FOR v_item IN SELECT item_id FROM items WHERE pickup_id = NEW.pickup_id LOOP
        v_total_amount := v_total_amount + calculate_item_value(v_item.item_id);
    END LOOP;

    UPDATE pickup_requests
    SET    total_weight_kg = v_total_weight,
           total_amount    = v_total_amount
    WHERE  pickup_id = NEW.pickup_id;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_recalculate_pickup_totals
AFTER INSERT OR UPDATE OF actual_weight_kg ON items
FOR EACH ROW EXECUTE FUNCTION fn_recalculate_pickup_totals();


-- ────────────────────────────────────────────────────────────
-- T7: trg_payment_request_alert
-- When a user files a payment request:
--   - If it's a duplicate (another pending request exists) → alert admin as CRITICAL.
--   - If overdue >48h → alert admin as HIGH.
-- Also marks is_duplicate and admin_alerted on the row.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_payment_request_alert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_hours_overdue FLOAT;
    v_alert_type    VARCHAR(60);
    v_severity      VARCHAR(10);
    v_title         TEXT;
    v_desc          TEXT;
BEGIN
    -- Calculate how many hours overdue
    SELECT EXTRACT(EPOCH FROM (NOW() - p.payment_due_by)) / 3600
    INTO   v_hours_overdue
    FROM   pickup_requests p WHERE p.pickup_id = NEW.pickup_id;

    IF NEW.is_duplicate THEN
        v_alert_type := 'duplicate_payment_request';
        v_severity   := 'critical';
        v_title      := 'Duplicate Payment Request — Pickup #' || NEW.pickup_id;
        v_desc       := 'User has submitted another payment request for an already-pending payment. Supervisor may be ignoring it.';
    ELSE
        v_alert_type := 'payment_request_submitted';
        v_severity   := CASE WHEN v_hours_overdue > 48 THEN 'high' ELSE 'medium' END;
        v_title      := 'Payment Request — Pickup #' || NEW.pickup_id;
        v_desc       := 'User has requested payment. Overdue by ' || ROUND(v_hours_overdue::NUMERIC, 1) || ' hours.';
    END IF;

    INSERT INTO admin_alerts (alert_type, severity, title, description,
                              related_table, related_id, payload)
    VALUES (v_alert_type, v_severity, v_title, v_desc,
            'payment_requests', NEW.request_id,
            jsonb_build_object(
                'pickup_id',    NEW.pickup_id,
                'user_id',      NEW.user_id,
                'supervisor_id', NEW.supervisor_id,
                'hours_overdue', ROUND(v_hours_overdue::NUMERIC, 1),
                'is_duplicate', NEW.is_duplicate,
                'request_count', (
                    SELECT payment_request_count FROM pickup_requests WHERE pickup_id = NEW.pickup_id
                )
            ));

    -- Mark admin_alerted on the request row
    NEW.admin_alerted := TRUE;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_payment_request_alert
BEFORE INSERT ON payment_requests
FOR EACH ROW EXECUTE FUNCTION fn_payment_request_alert();


-- ────────────────────────────────────────────────────────────
-- T8: trg_user_status_on_pickup_complete
-- When a pickup is completed, update user's last_pickup_at and
-- recalculate user_status automatically.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_user_status_on_pickup_complete()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
        UPDATE users
        SET    last_pickup_at = NOW(),
               user_status    = calculate_user_status(NEW.user_id)
        WHERE  user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_user_status_on_pickup_complete
AFTER UPDATE ON pickup_requests
FOR EACH ROW EXECUTE FUNCTION fn_user_status_on_pickup_complete();


-- ────────────────────────────────────────────────────────────
-- T9: trg_enforce_staff_role_on_assignment
-- Prevents assigning the wrong sub_role to a pickup slot.
-- E.g. cannot put a supervisor into driver_id column.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_enforce_staff_roles()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.supervisor_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM staff WHERE staff_id = NEW.supervisor_id AND sub_role = 'supervisor') THEN
            RAISE EXCEPTION 'supervisor_id % must be a supervisor sub_role.', NEW.supervisor_id;
        END IF;
    END IF;
    IF NEW.driver_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM staff WHERE staff_id = NEW.driver_id AND sub_role = 'driver') THEN
            RAISE EXCEPTION 'driver_id % must be a driver sub_role.', NEW.driver_id;
        END IF;
    END IF;
    IF NEW.collector_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM staff WHERE staff_id = NEW.collector_id AND sub_role = 'collector') THEN
            RAISE EXCEPTION 'collector_id % must be a collector sub_role.', NEW.collector_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_staff_roles
BEFORE INSERT OR UPDATE ON pickup_requests
FOR EACH ROW EXECUTE FUNCTION fn_enforce_staff_roles();
