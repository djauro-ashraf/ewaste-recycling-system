-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 07_triggers.sql - Automation & Auditing Layer (CORRECTED VERSION)

DROP TRIGGER IF EXISTS update_pickup_timestamp ON pickup_requests;
DROP TRIGGER IF EXISTS update_items_timestamp ON items;

DROP TRIGGER IF EXISTS prevent_weight_change_after_payment ON items;

DROP TRIGGER IF EXISTS audit_users_trigger ON users;
DROP TRIGGER IF EXISTS audit_pickup_requests_trigger ON pickup_requests;
DROP TRIGGER IF EXISTS audit_items_trigger ON items;
DROP TRIGGER IF EXISTS audit_payments_trigger ON payments;


DROP FUNCTION IF EXISTS set_updated_at() CASCADE;
DROP FUNCTION IF EXISTS prevent_weight_change_after_payment_fn() CASCADE;
DROP FUNCTION IF EXISTS audit_log_trigger_fn() CASCADE;

-- Trigger Function 1: Auto-update timestamp on record modification
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply timestamp trigger to pickup_requests
CREATE TRIGGER trg_pickup_update_timestamp
    BEFORE UPDATE ON pickup_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

-- Trigger Function 2: Audit log for pickup_requests table
CREATE OR REPLACE FUNCTION audit_log_pickup_changes()
RETURNS TRIGGER AS $$
DECLARE
    v_old_values JSONB;
    v_new_values JSONB;
    v_record_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_old_values := to_jsonb(OLD);
        v_new_values := NULL;
        v_record_id := OLD.pickup_id;
        
        INSERT INTO audit_log (table_name, operation, record_id, old_values, new_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, v_record_id, v_old_values, v_new_values, current_user);
        
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_values := to_jsonb(OLD);
        v_new_values := to_jsonb(NEW);
        v_record_id := NEW.pickup_id;
        
        -- Only log if something actually changed
        IF v_old_values IS DISTINCT FROM v_new_values THEN
            INSERT INTO audit_log (table_name, operation, record_id, old_values, new_values, changed_by)
            VALUES (TG_TABLE_NAME, TG_OP, v_record_id, v_old_values, v_new_values, current_user);
        END IF;
        
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        v_old_values := NULL;
        v_new_values := to_jsonb(NEW);
        v_record_id := NEW.pickup_id;
        
        INSERT INTO audit_log (table_name, operation, record_id, old_values, new_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, v_record_id, v_old_values, v_new_values, current_user);
        
        RETURN NEW;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Apply audit trigger to pickup_requests
CREATE TRIGGER trg_audit_pickup_requests
    AFTER INSERT OR UPDATE OR DELETE ON pickup_requests
    FOR EACH ROW
    EXECUTE FUNCTION audit_log_pickup_changes();

-- Trigger Function 3: Audit log for payments
CREATE OR REPLACE FUNCTION audit_log_payments()
RETURNS TRIGGER AS $$
DECLARE
    v_old_values JSONB;
    v_new_values JSONB;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_old_values := to_jsonb(OLD);
        INSERT INTO audit_log (table_name, operation, record_id, old_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, OLD.payment_id, v_old_values, current_user);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_values := to_jsonb(OLD);
        v_new_values := to_jsonb(NEW);
        IF v_old_values IS DISTINCT FROM v_new_values THEN
            INSERT INTO audit_log (table_name, operation, record_id, old_values, new_values, changed_by)
            VALUES (TG_TABLE_NAME, TG_OP, NEW.payment_id, v_old_values, v_new_values, current_user);
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        v_new_values := to_jsonb(NEW);
        INSERT INTO audit_log (table_name, operation, record_id, new_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.payment_id, v_new_values, current_user);
        RETURN NEW;
    END IF;
    RETURN NULL;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_payments
    AFTER INSERT OR UPDATE OR DELETE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION audit_log_payments();

-- Trigger Function 4: Validate status transitions
CREATE OR REPLACE FUNCTION validate_pickup_status_transition()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        IF NOT is_valid_status_transition(OLD.status, NEW.status) THEN
            RAISE EXCEPTION 'Invalid status transition from % to %', OLD.status, NEW.status;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_pickup_status
    BEFORE UPDATE ON pickup_requests
    FOR EACH ROW
    EXECUTE FUNCTION validate_pickup_status_transition();

-- Trigger Function 5: Prevent deletion of completed pickups
CREATE OR REPLACE FUNCTION prevent_completed_pickup_deletion()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'completed' THEN
        RAISE EXCEPTION 'Cannot delete completed pickup request %', OLD.pickup_id;
    END IF;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_completed_deletion
    BEFORE DELETE ON pickup_requests
    FOR EACH ROW
    EXECUTE FUNCTION prevent_completed_pickup_deletion();

-- Trigger Function 6: Alert on high hazard items
CREATE OR REPLACE FUNCTION alert_high_hazard_items()
RETURNS TRIGGER AS $$
DECLARE
    v_hazard_level INT;
BEGIN
    SELECT hazard_level INTO v_hazard_level
    FROM categories
    WHERE category_id = NEW.category_id;
    
    IF v_hazard_level >= 4 THEN
        RAISE NOTICE 'HIGH HAZARD ALERT: Item % (pickup %) contains hazardous material (level %)', 
            NEW.item_id, NEW.pickup_id, v_hazard_level;
        
        -- Log to audit
        INSERT INTO audit_log (table_name, operation, record_id, new_values, changed_by)
        VALUES ('items', 'HAZARD_ALERT', NEW.item_id, 
                jsonb_build_object('hazard_level', v_hazard_level, 'item_id', NEW.item_id, 'pickup_id', NEW.pickup_id),
                'system');
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_alert_hazard
    AFTER INSERT ON items
    FOR EACH ROW
    EXECUTE FUNCTION alert_high_hazard_items();

-- Trigger Function 7: Auto-calculate pickup totals when items change
-- NOTE: This is disabled by default because the procedures already handle this
-- Uncomment if you want automatic recalculation on direct table modifications
/*
CREATE OR REPLACE FUNCTION recalculate_pickup_totals()
RETURNS TRIGGER AS $$
DECLARE
    v_pickup_id INT;
BEGIN
    -- Determine which pickup to update
    IF TG_OP = 'DELETE' THEN
        v_pickup_id := OLD.pickup_id;
    ELSE
        v_pickup_id := NEW.pickup_id;
    END IF;
    
    -- Recalculate totals
    UPDATE pickup_requests
    SET total_weight_kg = get_pickup_total_weight(v_pickup_id),
        total_amount = get_pickup_total_amount(v_pickup_id),
        updated_at = CURRENT_TIMESTAMP
    WHERE pickup_id = v_pickup_id;
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recalc_pickup_totals
    AFTER INSERT OR UPDATE OR DELETE ON items
    FOR EACH ROW
    EXECUTE FUNCTION recalculate_pickup_totals();
*/

-- Trigger Function 8: Update batch weight when items added/removed
CREATE OR REPLACE FUNCTION update_batch_weight()
RETURNS TRIGGER AS $$
DECLARE
    v_batch_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_batch_id := OLD.batch_id;
    ELSE
        v_batch_id := NEW.batch_id;
    END IF;
    
    UPDATE recycling_batches
    SET total_weight_kg = get_batch_total_weight(v_batch_id)
    WHERE batch_id = v_batch_id;
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_batch_weight
    AFTER INSERT OR DELETE ON batch_items
    FOR EACH ROW
    EXECUTE FUNCTION update_batch_weight();

-- Trigger Function 9: Prevent batch modification when not open
CREATE OR REPLACE FUNCTION validate_batch_open()
RETURNS TRIGGER AS $$
DECLARE
    v_batch_status VARCHAR;
BEGIN
    SELECT status INTO v_batch_status
    FROM recycling_batches
    WHERE batch_id = NEW.batch_id;
    
    IF v_batch_status != 'open' THEN
        RAISE EXCEPTION 'Cannot modify batch % with status %', NEW.batch_id, v_batch_status;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_batch_modification
    BEFORE INSERT ON batch_items
    FOR EACH ROW
    EXECUTE FUNCTION validate_batch_open();

-- Trigger Function 10: Log facility capacity warnings
CREATE OR REPLACE FUNCTION check_facility_capacity_warning()
RETURNS TRIGGER AS $$
DECLARE
    v_usage_percent DECIMAL;
BEGIN
    v_usage_percent := (NEW.current_load_kg / NEW.capacity_kg) * 100;
    
    IF v_usage_percent >= 90 THEN
       RAISE NOTICE 'CAPACITY WARNING: Facility % is at %%% capacity', 
             NEW.facility_id, 
             ROUND(v_usage_percent, 2);

        INSERT INTO audit_log (table_name, operation, record_id, new_values, changed_by)
        VALUES ('recycling_facilities', 'CAPACITY_WARNING', NEW.facility_id,
                jsonb_build_object('usage_percent', v_usage_percent, 'current_load', NEW.current_load_kg),
                'system');
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_facility_capacity_warning
    AFTER UPDATE ON recycling_facilities
    FOR EACH ROW
    WHEN (NEW.current_load_kg IS DISTINCT FROM OLD.current_load_kg)
    EXECUTE FUNCTION check_facility_capacity_warning();

-- Trigger Function 11: Prevent weight modification after payment
CREATE OR REPLACE FUNCTION prevent_weight_change_after_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_pickup_status VARCHAR;
BEGIN
    SELECT status INTO v_pickup_status
    FROM pickup_requests
    WHERE pickup_id = NEW.pickup_id;
    
    IF v_pickup_status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Cannot modify item % for pickup with status %', NEW.item_id, v_pickup_status;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_item_modification
    BEFORE UPDATE ON items
    FOR EACH ROW
    WHEN (OLD.actual_weight_kg IS DISTINCT FROM NEW.actual_weight_kg)
    EXECUTE FUNCTION prevent_weight_change_after_payment();

-- Trigger Function 12: Auto-assign batch number
CREATE OR REPLACE FUNCTION auto_assign_batch_number()
RETURNS TRIGGER AS $$
DECLARE
    v_batch_count INT;
    v_facility_code VARCHAR;
BEGIN
    IF NEW.batch_name IS NULL OR NEW.batch_name = '' THEN
        SELECT COUNT(*) + 1 INTO v_batch_count
        FROM recycling_batches
        WHERE facility_id = NEW.facility_id;
        
        SELECT LEFT(facility_name, 3) INTO v_facility_code
        FROM recycling_facilities
        WHERE facility_id = NEW.facility_id;
        
        NEW.batch_name := UPPER(v_facility_code) || '-' || 
                         TO_CHAR(CURRENT_DATE, 'YYYYMM') || '-' || 
                         LPAD(v_batch_count::TEXT, 3, '0');
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_batch_name
    BEFORE INSERT ON recycling_batches
    FOR EACH ROW
    EXECUTE FUNCTION auto_assign_batch_number();

-- Comments explaining trigger design:
-- 1. Triggers run automatically without application involvement
-- 2. Audit triggers log all changes to critical tables
-- 3. Validation triggers enforce business rules
-- 4. Prevention triggers stop invalid operations
-- 5. Alert triggers notify on important events
-- 6. Calculation triggers maintain computed values
-- 7. BEFORE triggers for validation, AFTER for logging
-- 8. Triggers use JSONB for flexible audit storage
-- 9. RAISE NOTICE for warnings, RAISE EXCEPTION for errors
-- 10. Fixed record_id extraction to use proper column names
-- 11. Disabled auto-recalc trigger as procedures handle this