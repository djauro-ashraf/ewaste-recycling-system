-- ============================================================
-- 05_functions.sql — Reusable Business-Logic Functions
-- ============================================================

-- ── calculate_item_value ──────────────────────────────────
-- Returns monetary payout for a single item (can be 0 for zero-value junk).
-- Uses pricing_rules if a match exists; falls back to category base price.
CREATE OR REPLACE FUNCTION calculate_item_value(p_item_id INT)
RETURNS DECIMAL(10,2) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_category_id INT;
    v_weight      DECIMAL(8,2);
    v_price       DECIMAL(8,2);
    v_bonus       DECIMAL(5,2) := 0;
BEGIN
    SELECT category_id,
           COALESCE(actual_weight_kg, estimated_weight_kg, 0)
    INTO   v_category_id, v_weight
    FROM   items WHERE item_id = p_item_id;

    IF NOT FOUND THEN RETURN 0; END IF;
    IF v_weight = 0 THEN RETURN 0; END IF;

    -- Best matching active pricing rule
    SELECT price_per_kg, COALESCE(bonus_percentage, 0)
    INTO   v_price, v_bonus
    FROM   pricing_rules
    WHERE  category_id   = v_category_id
      AND  is_active      = TRUE
      AND  min_weight_kg <= v_weight
      AND  (max_weight_kg IS NULL OR max_weight_kg >= v_weight)
      AND  effective_from <= CURRENT_DATE
      AND  (effective_to IS NULL OR effective_to >= CURRENT_DATE)
    ORDER  BY effective_from DESC
    LIMIT  1;

    -- Fallback to category base price (may be 0 for zero-value categories)
    IF v_price IS NULL THEN
        SELECT base_price_per_kg INTO v_price
        FROM   categories WHERE category_id = v_category_id;
    END IF;

    RETURN ROUND(v_weight * COALESCE(v_price, 0) * (1 + v_bonus / 100.0), 2);
END;
$$;


-- ── get_supervisor_stats ──────────────────────────────────
-- Returns KPI snapshot for one supervisor — used in admin reports.
CREATE OR REPLACE FUNCTION get_supervisor_stats(p_supervisor_id INT)
RETURNS TABLE (
    total_pickups       BIGINT,
    completed_pickups   BIGINT,
    collected_unpaid    BIGINT,
    total_weight_kg     DECIMAL,
    total_paid_out      DECIMAL,
    driver_count        BIGINT,
    collector_count     BIGINT,
    vehicle_count       BIGINT,
    overdue_payments    BIGINT
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(p.pickup_id),
        COUNT(p.pickup_id) FILTER (WHERE p.status = 'completed'),
        COUNT(p.pickup_id) FILTER (WHERE p.status = 'collected'),
        COALESCE(SUM(p.total_weight_kg) FILTER (WHERE p.status = 'completed'), 0),
        COALESCE(SUM(py.amount) FILTER (WHERE py.payment_status = 'completed'), 0),
        (SELECT COUNT(*) FROM staff WHERE supervisor_id = p_supervisor_id AND sub_role = 'driver' AND is_active),
        (SELECT COUNT(*) FROM staff WHERE supervisor_id = p_supervisor_id AND sub_role = 'collector' AND is_active),
        (SELECT COUNT(*) FROM vehicles WHERE supervisor_id = p_supervisor_id),
        (SELECT COUNT(*) FROM v_overdue_payments WHERE supervisor_id = p_supervisor_id)
    FROM pickup_requests  p
    LEFT JOIN payments py ON py.pickup_id = p.pickup_id
    WHERE p.supervisor_id = p_supervisor_id;
END;
$$;


-- ── get_user_stats ────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_user_stats(p_user_id INT)
RETURNS TABLE (
    total_pickups         BIGINT,
    completed_pickups     BIGINT,
    pending_pickups       BIGINT,
    total_weight_kg       DECIMAL,
    total_earned          DECIMAL,
    avg_pickup_value      DECIMAL,
    most_recycled_category VARCHAR,
    warning_count         BIGINT
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(p.pickup_id),
        COUNT(p.pickup_id) FILTER (WHERE p.status = 'completed'),
        COUNT(p.pickup_id) FILTER (WHERE p.status = 'pending'),
        COALESCE(SUM(p.total_weight_kg) FILTER (WHERE p.status = 'completed'), 0),
        COALESCE(SUM(p.total_amount)    FILTER (WHERE p.status = 'completed'), 0),
        COALESCE(AVG(p.total_amount)    FILTER (WHERE p.status = 'completed'), 0),
        (
            SELECT c.category_name
            FROM   items i
            JOIN   categories c ON i.category_id = c.category_id
            JOIN   pickup_requests px ON i.pickup_id = px.pickup_id
            WHERE  px.user_id = p_user_id
            GROUP  BY c.category_name
            ORDER  BY COUNT(*) DESC LIMIT 1
        ),
        (SELECT COUNT(*) FROM warnings w WHERE w.target_user_id = p_user_id)
    FROM pickup_requests p
    WHERE p.user_id = p_user_id;
END;
$$;


-- ── get_batch_pickup_count ────────────────────────────────
-- Returns how many distinct pickups are represented in a batch.
-- Used to enforce the minimum-2-pickup rule.
CREATE OR REPLACE FUNCTION get_batch_pickup_count(p_batch_id INT)
RETURNS BIGINT LANGUAGE sql STABLE AS $$
    SELECT COUNT(DISTINCT pickup_id) FROM batch_items WHERE batch_id = p_batch_id;
$$;


-- ── get_facility_available_capacity ───────────────────────
CREATE OR REPLACE FUNCTION get_facility_available_capacity(p_facility_id INT)
RETURNS DECIMAL(10,2) LANGUAGE sql STABLE AS $$
    SELECT capacity_kg - current_load_kg FROM recycling_facilities WHERE facility_id = p_facility_id;
$$;


-- ── format_weight ────────────────────────────────────────
CREATE OR REPLACE FUNCTION format_weight(p_kg DECIMAL)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_kg >= 1000 THEN ROUND(p_kg/1000, 2)::TEXT || ' t'
        ELSE ROUND(p_kg, 2)::TEXT || ' kg'
    END;
$$;


-- ── calculate_user_status ─────────────────────────────────
-- Computes what a user's status SHOULD be based on activity.
-- active   = last pickup within 6 months OR registered within 6 months
-- idle     = last pickup 6–12 months ago
-- inactive = last pickup >12 months ago or never signed up 12mo ago
-- suspended = preserved (admin override)
CREATE OR REPLACE FUNCTION calculate_user_status(p_user_id INT)
RETURNS VARCHAR(20) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_current_status VARCHAR(20);
    v_last_pickup    TIMESTAMP;
    v_registered     TIMESTAMP;
BEGIN
    SELECT user_status, last_pickup_at, registered_at
    INTO   v_current_status, v_last_pickup, v_registered
    FROM   users WHERE user_id = p_user_id;

    -- Never override suspension manually set by admin
    IF v_current_status = 'suspended' THEN RETURN 'suspended'; END IF;

    IF v_last_pickup IS NULL THEN
        -- Never had a pickup: idle if >6 months since registration
        IF v_registered < NOW() - INTERVAL '6 months' THEN RETURN 'inactive'; END IF;
        RETURN 'active';
    END IF;

    IF v_last_pickup >= NOW() - INTERVAL '6 months'  THEN RETURN 'active';   END IF;
    IF v_last_pickup >= NOW() - INTERVAL '12 months' THEN RETURN 'idle';     END IF;
    RETURN 'inactive';
END;
$$;


-- ── get_revenue_by_period ─────────────────────────────────
-- Monthly revenue breakdown from recycled materials (business income).
-- Uses JSONB aggregation for material breakdown per month.
CREATE OR REPLACE FUNCTION get_revenue_by_period(p_months INT DEFAULT 12)
RETURNS TABLE (
    period             TEXT,
    yr                 DOUBLE PRECISION,
    mo                 DOUBLE PRECISION,
    total_revenue      NUMERIC,
    material_breakdown JSONB
) LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT
            TO_CHAR(sr.recorded_at, 'Mon YYYY') AS period,
            EXTRACT(YEAR  FROM sr.recorded_at) AS yr,
            EXTRACT(MONTH FROM sr.recorded_at) AS mo,
            sr.material_type,
            SUM(sr.total_value)::NUMERIC AS material_value
        FROM system_revenue sr
        WHERE sr.recorded_at >= NOW() - (p_months || ' months')::INTERVAL
        GROUP BY
            TO_CHAR(sr.recorded_at, 'Mon YYYY'),
            EXTRACT(YEAR  FROM sr.recorded_at),
            EXTRACT(MONTH FROM sr.recorded_at),
            sr.material_type
    )
    SELECT
        b.period,
        b.yr,
        b.mo,
        SUM(b.material_value) AS total_revenue,
        COALESCE(jsonb_object_agg(b.material_type, ROUND(b.material_value, 2)), '{}'::jsonb) AS material_breakdown
    FROM base b
    GROUP BY b.period, b.yr, b.mo
    ORDER BY b.yr DESC, b.mo DESC;
$$;


-- ── get_hazardous_items_by_supervisor ─────────────────────
-- Advanced JSONB query: aggregates hazardous item stats per supervisor.
CREATE OR REPLACE FUNCTION get_hazardous_items_by_supervisor()
RETURNS TABLE (
    supervisor_id   INT,
    supervisor_name VARCHAR,
    total_hazardous BIGINT,
    mercury_count   BIGINT,
    total_batteries BIGINT,
    hazard_summary  JSONB
) LANGUAGE sql STABLE AS $$
    SELECT
        p.supervisor_id,
        s.full_name,
        COUNT(*),
        COUNT(*) FILTER (WHERE (i.hazard_details->>'contains_mercury')::boolean = TRUE),
        COALESCE(SUM((i.hazard_details->>'battery_count')::int) FILTER (
            WHERE i.hazard_details ? 'battery_count'
        ), 0),
        jsonb_build_object(
            'mercury_items',  COUNT(*) FILTER (WHERE (i.hazard_details->>'contains_mercury')::boolean = TRUE),
            'total_batteries', COALESCE(SUM((i.hazard_details->>'battery_count')::int) FILTER (WHERE i.hazard_details ? 'battery_count'), 0),
            'high_hazard_items', COUNT(*) FILTER (WHERE c.hazard_level >= 4)
        )
    FROM items i
    JOIN categories      c ON i.category_id  = c.category_id
    JOIN pickup_requests p ON i.pickup_id    = p.pickup_id
    JOIN staff           s ON p.supervisor_id = s.staff_id
    WHERE c.hazard_level >= 3
       OR (i.hazard_details->>'contains_mercury')::boolean = TRUE
    GROUP BY p.supervisor_id, s.full_name;
$$;
