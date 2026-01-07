-- =========================
-- 05_functions.sql
-- Custom Functions
-- =========================

-- 1. Calculate price based on weight
-- Simple rate: 10 currency units per kg
CREATE OR REPLACE FUNCTION calculate_weight_price(p_item_id INT)
RETURNS NUMERIC AS $$
DECLARE
    total_weight NUMERIC;
    price NUMERIC;
BEGIN
    SELECT SUM(weight_kg)
    INTO total_weight
    FROM weight_records
    WHERE item_id = p_item_id;

    IF total_weight IS NULL THEN
        RETURN 0;
    END IF;

    price := total_weight * 10;  -- rate per kg
    RETURN price;
END;
$$ LANGUAGE plpgsql;


-- 2. Total cost of a pickup request (sum of all its items)
CREATE OR REPLACE FUNCTION total_request_cost(p_request_id INT)
RETURNS NUMERIC AS $$
DECLARE
    total_cost NUMERIC;
BEGIN
    SELECT SUM(calculate_weight_price(i.item_id))
    INTO total_cost
    FROM items i
    WHERE i.request_id = p_request_id;

    IF total_cost IS NULL THEN
        RETURN 0;
    END IF;

    RETURN total_cost;
END;
$$ LANGUAGE plpgsql;


-- 3. Hazard score based on JSON data
-- Example JSON: {"battery": true, "mercury": false, "lead": true}
CREATE OR REPLACE FUNCTION hazard_score(p_hazard_json JSONB)
RETURNS INT AS $$
DECLARE
    score INT := 0;
BEGIN
    IF p_hazard_json ? 'battery' AND p_hazard_json->>'battery' = 'true' THEN
        score := score + 2;
    END IF;

    IF p_hazard_json ? 'mercury' AND p_hazard_json->>'mercury' = 'true' THEN
        score := score + 3;
    END IF;

    IF p_hazard_json ? 'lead' AND p_hazard_json->>'lead' = 'true' THEN
        score := score + 2;
    END IF;

    RETURN score;
END;
$$ LANGUAGE plpgsql;


-- 4. Get total weight of a pickup request
CREATE OR REPLACE FUNCTION total_request_weight(p_request_id INT)
RETURNS NUMERIC AS $$
DECLARE
    total_weight NUMERIC;
BEGIN
    SELECT SUM(w.weight_kg)
    INTO total_weight
    FROM items i
    JOIN weight_records w ON i.item_id = w.item_id
    WHERE i.request_id = p_request_id;

    IF total_weight IS NULL THEN
        RETURN 0;
    END IF;

    RETURN total_weight;
END;
$$ LANGUAGE plpgsql;


-- 5. Check if an item is hazardous (boolean helper)
CREATE OR REPLACE FUNCTION is_item_hazardous(p_item_id INT)
RETURNS BOOLEAN AS $$
DECLARE
    hazard_json JSONB;
BEGIN
    SELECT hazardous_info
    INTO hazard_json
    FROM items
    WHERE item_id = p_item_id;

    IF hazard_json IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN hazard_score(hazard_json) > 0;
END;
$$ LANGUAGE plpgsql;
