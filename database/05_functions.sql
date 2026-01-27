-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 05_functions.sql - Reusable Business Logic

-- Function 1: Calculate price for an item based on weight and category
CREATE OR REPLACE FUNCTION calculate_item_price(
    p_category_id INT,
    p_weight_kg DECIMAL
)
RETURNS DECIMAL AS $$
DECLARE
    v_price_per_kg DECIMAL;
    v_bonus_percentage DECIMAL;
    v_base_price DECIMAL;
    v_final_price DECIMAL;
BEGIN
    -- Get active pricing rule for this weight and category
    SELECT price_per_kg, bonus_percentage
    INTO v_price_per_kg, v_bonus_percentage
    FROM pricing_rules
    WHERE category_id = p_category_id
      AND is_active = TRUE
      AND p_weight_kg >= min_weight_kg
      AND (max_weight_kg IS NULL OR p_weight_kg <= max_weight_kg)
      AND CURRENT_DATE BETWEEN effective_from AND COALESCE(effective_to, CURRENT_DATE)
    ORDER BY min_weight_kg DESC
    LIMIT 1;
    
    -- If no pricing rule found, use base price from category
    IF v_price_per_kg IS NULL THEN
        SELECT base_price_per_kg INTO v_price_per_kg
        FROM categories
        WHERE category_id = p_category_id;
        
        v_bonus_percentage := 0;
    END IF;
    
    -- Calculate base price
    v_base_price := p_weight_kg * v_price_per_kg;
    
    -- Apply bonus
    v_final_price := v_base_price * (1 + v_bonus_percentage / 100);
    
    RETURN ROUND(v_final_price, 2);
END;
$$ LANGUAGE plpgsql;

-- Function 2: Calculate total weight for a pickup
CREATE OR REPLACE FUNCTION get_pickup_total_weight(p_pickup_id INT)
RETURNS DECIMAL AS $$
DECLARE
    v_total_weight DECIMAL;
BEGIN
    SELECT COALESCE(SUM(COALESCE(actual_weight_kg, estimated_weight_kg)), 0)
    INTO v_total_weight
    FROM items
    WHERE pickup_id = p_pickup_id;
    
    RETURN v_total_weight;
END;
$$ LANGUAGE plpgsql;

-- Function 3: Calculate total amount for a pickup
CREATE OR REPLACE FUNCTION get_pickup_total_amount(p_pickup_id INT)
RETURNS DECIMAL AS $$
DECLARE
    v_total_amount DECIMAL := 0;
    v_item RECORD;
BEGIN
    FOR v_item IN 
        SELECT category_id, COALESCE(actual_weight_kg, estimated_weight_kg) AS weight
        FROM items
        WHERE pickup_id = p_pickup_id
    LOOP
        v_total_amount := v_total_amount + calculate_item_price(v_item.category_id, v_item.weight);
    END LOOP;
    
    RETURN ROUND(v_total_amount, 2);
END;
$$ LANGUAGE plpgsql;

-- Function 4: Get hazard level for a pickup (highest among items)
CREATE OR REPLACE FUNCTION get_pickup_hazard_level(p_pickup_id INT)
RETURNS INT AS $$
DECLARE
    v_max_hazard INT;
BEGIN
    SELECT COALESCE(MAX(c.hazard_level), 0)
    INTO v_max_hazard
    FROM items i
    JOIN categories c ON i.category_id = c.category_id
    WHERE i.pickup_id = p_pickup_id;
    
    RETURN v_max_hazard;
END;
$$ LANGUAGE plpgsql;

-- Function 5: Check if vehicle has capacity for a pickup
CREATE OR REPLACE FUNCTION check_vehicle_capacity(
    p_vehicle_id INT,
    p_additional_weight DECIMAL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_capacity DECIMAL;
    v_current_load DECIMAL;
BEGIN
    SELECT capacity_kg, current_load_kg
    INTO v_capacity, v_current_load
    FROM vehicles
    WHERE vehicle_id = p_vehicle_id;
    
    RETURN (v_current_load + p_additional_weight) <= v_capacity;
END;
$$ LANGUAGE plpgsql;

-- Function 6: Check if facility has capacity for a batch
CREATE OR REPLACE FUNCTION check_facility_capacity(
    p_facility_id INT,
    p_additional_weight DECIMAL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_capacity DECIMAL;
    v_current_load DECIMAL;
BEGIN
    SELECT capacity_kg, current_load_kg
    INTO v_capacity, v_current_load
    FROM recycling_facilities
    WHERE facility_id = p_facility_id;
    
    RETURN (v_current_load + p_additional_weight) <= v_capacity;
END;
$$ LANGUAGE plpgsql;

-- Function 7: Find available staff for assignment
CREATE OR REPLACE FUNCTION find_available_staff(p_role VARCHAR DEFAULT 'driver')
RETURNS TABLE (
    staff_id INT,
    staff_name VARCHAR,
    vehicle_id INT,
    vehicle_capacity DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.staff_id,
        s.staff_name,
        v.vehicle_id,
        v.capacity_kg
    FROM staff_assignments s
    LEFT JOIN vehicles v ON s.assigned_vehicle_id = v.vehicle_id
    WHERE s.is_available = TRUE
      AND s.role = p_role
      AND (v.vehicle_id IS NULL OR v.is_available = TRUE)
    ORDER BY s.staff_id;
END;
$$ LANGUAGE plpgsql;

-- Function 8: Find suitable facility for a category
CREATE OR REPLACE FUNCTION find_suitable_facility(p_category_name VARCHAR)
RETURNS TABLE (
    facility_id INT,
    facility_name VARCHAR,
    available_capacity DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.facility_id,
        f.facility_name,
        f.capacity_kg - f.current_load_kg AS available_capacity
    FROM recycling_facilities f
    WHERE f.is_operational = TRUE
      AND (f.specialization IS NULL OR f.specialization ILIKE '%' || p_category_name || '%')
      AND f.current_load_kg < f.capacity_kg
    ORDER BY available_capacity DESC;
END;
$$ LANGUAGE plpgsql;

-- Function 9: Calculate batch total weight
CREATE OR REPLACE FUNCTION get_batch_total_weight(p_batch_id INT)
RETURNS DECIMAL AS $$
DECLARE
    v_total_weight DECIMAL;
BEGIN
    SELECT COALESCE(SUM(COALESCE(i.actual_weight_kg, i.estimated_weight_kg)), 0)
    INTO v_total_weight
    FROM batch_items bi
    JOIN items i ON bi.item_id = i.item_id
    WHERE bi.batch_id = p_batch_id;
    
    RETURN v_total_weight;
END;
$$ LANGUAGE plpgsql;

-- Function 10: Get average recovery rate for a facility
CREATE OR REPLACE FUNCTION get_facility_avg_recovery_rate(p_facility_id INT)
RETURNS DECIMAL AS $$
DECLARE
    v_avg_rate DECIMAL;
BEGIN
    SELECT COALESCE(AVG(recovery_rate_percentage), 0)
    INTO v_avg_rate
    FROM recycling_batches
    WHERE facility_id = p_facility_id
      AND status = 'completed'
      AND recovery_rate_percentage IS NOT NULL;
    
    RETURN ROUND(v_avg_rate, 2);
END;
$$ LANGUAGE plpgsql;

-- Function 11: Validate pickup status transition
CREATE OR REPLACE FUNCTION is_valid_status_transition(
    p_current_status VARCHAR,
    p_new_status VARCHAR
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Define valid state transitions
    RETURN CASE
        WHEN p_current_status = 'pending' AND p_new_status IN ('assigned', 'cancelled') THEN TRUE
        WHEN p_current_status = 'assigned' AND p_new_status IN ('collected', 'cancelled') THEN TRUE
        WHEN p_current_status = 'collected' AND p_new_status = 'completed' THEN TRUE
        WHEN p_current_status = 'cancelled' AND p_new_status = 'pending' THEN TRUE
        ELSE FALSE
    END;
END;
$$ LANGUAGE plpgsql;

-- Function 12: Get user statistics
CREATE OR REPLACE FUNCTION get_user_stats(p_user_id INT)
RETURNS TABLE (
    total_pickups BIGINT,
    total_weight DECIMAL,
    total_earnings DECIMAL,
    avg_weight_per_pickup DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(DISTINCT p.pickup_id)::BIGINT,
        COALESCE(SUM(p.total_weight_kg), 0),
        COALESCE(SUM(p.total_amount), 0),
        COALESCE(AVG(p.total_weight_kg), 0)
    FROM pickup_requests p
    WHERE p.user_id = p_user_id
      AND p.status = 'completed';
END;
$$ LANGUAGE plpgsql;

-- Function 13: Calculate recyclability score for an item
CREATE OR REPLACE FUNCTION calculate_recyclability_score(
    p_item_id INT
)
RETURNS DECIMAL AS $$
DECLARE
    v_recyclability DECIMAL;
    v_condition VARCHAR;
    v_hazard_level INT;
    v_score DECIMAL;
BEGIN
    SELECT 
        c.recyclability_percentage,
        i.condition,
        c.hazard_level
    INTO v_recyclability, v_condition, v_hazard_level
    FROM items i
    JOIN categories c ON i.category_id = c.category_id
    WHERE i.item_id = p_item_id;
    
    -- Base score from recyclability
    v_score := v_recyclability;
    
    -- Adjust for condition
    v_score := v_score * CASE v_condition
        WHEN 'working' THEN 1.2
        WHEN 'repairable' THEN 1.0
        WHEN 'broken' THEN 0.8
        ELSE 1.0
    END;
    
    -- Penalize for high hazard
    v_score := v_score * (1 - (v_hazard_level - 1) * 0.1);
    
    RETURN LEAST(ROUND(v_score, 2), 100.00);
END;
$$ LANGUAGE plpgsql;

-- Comments explaining function design:
-- 1. Functions encapsulate reusable calculations
-- 2. Price calculation supports dynamic pricing rules
-- 3. Capacity checks prevent overloading vehicles/facilities
-- 4. Finder functions help with resource allocation
-- 5. Validation functions enforce business rules
-- 6. Statistics functions support reporting
-- 7. All functions are deterministic where possible
-- 8. Functions return appropriate types (DECIMAL for money, BOOLEAN for checks)
-- 9. Functions use COALESCE to handle NULLs gracefully
-- 10. Functions are called by procedures and queries