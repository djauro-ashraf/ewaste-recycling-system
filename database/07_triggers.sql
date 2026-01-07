-- =========================
-- Hazardous JSON Validation
-- =========================

CREATE OR REPLACE FUNCTION validate_hazardous_json()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.hazardous_info IS NOT NULL AND jsonb_typeof(NEW.hazardous_info) <> 'object' THEN
        RAISE EXCEPTION 'hazardous_info must be a valid JSON object';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_hazardous_json
BEFORE INSERT OR UPDATE ON items
FOR EACH ROW
EXECUTE FUNCTION validate_hazardous_json();





-- =========================
-- Audit Log Trigger
-- =========================

CREATE OR REPLACE FUNCTION audit_log_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_logs(entity_name, entity_id, action, performed_by)
        VALUES (TG_TABLE_NAME, NEW.item_id, 'INSERT', current_user);

        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_logs(entity_name, entity_id, action, performed_by)
        VALUES (TG_TABLE_NAME, NEW.item_id, 'UPDATE', current_user);

        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_logs(entity_name, entity_id, action, performed_by)
        VALUES (TG_TABLE_NAME, OLD.item_id, 'DELETE', current_user);

        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;




CREATE TRIGGER trg_audit_items
AFTER INSERT OR UPDATE OR DELETE ON items
FOR EACH ROW
EXECUTE FUNCTION audit_log_trigger();



-- =========================
-- Auto Assign Item to Latest Batch
-- =========================

CREATE OR REPLACE FUNCTION auto_assign_item_to_batch()
RETURNS TRIGGER AS $$
DECLARE
    latest_batch_id INT;
BEGIN
    SELECT batch_id
    INTO latest_batch_id
    FROM recycling_batches
    ORDER BY created_at DESC
    LIMIT 1;

    IF latest_batch_id IS NOT NULL THEN
        INSERT INTO batch_items (batch_id, item_id)
        VALUES (latest_batch_id, NEW.item_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_assign_item_batch
AFTER INSERT ON items
FOR EACH ROW
EXECUTE FUNCTION auto_assign_item_to_batch();
