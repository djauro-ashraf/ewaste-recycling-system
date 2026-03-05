-- ============================================================
-- 04_views.sql  —  All reusable query views
-- ============================================================

-- ── v_pickup_full ─────────────────────────────────────────
-- Master pickup view: all fields, all staff names, payment status
CREATE OR REPLACE VIEW v_pickup_full AS
SELECT
    p.pickup_id,
    p.user_id,
    u.full_name           AS user_name,
    u.phone               AS user_phone,
    u.email               AS user_email,
    p.preferred_date,
    p.pickup_address,
    p.status,
    p.total_weight_kg,
    p.total_amount,
    p.payment_due_by,
    p.payment_request_count,
    p.notes,
    p.request_date,
    p.scheduled_time,
    p.collected_at,
    p.collector_confirmed,
    p.collector_confirmed_at,
    p.driver_confirmed,
    p.driver_confirmed_at,
    p.completed_time,
    -- supervisor
    p.supervisor_id,
    sup.full_name         AS supervisor_name,
    -- driver
    p.driver_id,
    drv.full_name         AS driver_name,
    -- collector
    p.collector_id,
    col.full_name         AS collector_name,
    -- vehicle
    v.vehicle_number,
    v.vehicle_type,
    -- facility
    rf.facility_name,
    rf.location           AS facility_location,
    -- computed
    (SELECT COUNT(*) FROM items i WHERE i.pickup_id = p.pickup_id)
                          AS item_count,
    -- is payment overdue?
    (p.status = 'collected'
     AND p.payment_due_by < NOW()
     AND NOT EXISTS (SELECT 1 FROM payments py
                     WHERE py.pickup_id = p.pickup_id
                       AND py.payment_status = 'completed'))
                          AS payment_overdue,
    -- has pending payment request?
    EXISTS (SELECT 1 FROM payment_requests pr
            WHERE pr.pickup_id = p.pickup_id AND pr.status = 'pending')
                          AS has_pending_payment_request
FROM pickup_requests p
JOIN  users u   ON p.user_id    = u.user_id
LEFT JOIN staff sup ON p.supervisor_id = sup.staff_id
LEFT JOIN staff drv ON p.driver_id     = drv.staff_id
LEFT JOIN staff col ON p.collector_id  = col.staff_id
LEFT JOIN vehicles v ON p.assigned_vehicle_id = v.vehicle_id
LEFT JOIN recycling_facilities rf ON p.assigned_facility_id = rf.facility_id;


-- ── v_item_details ────────────────────────────────────────
CREATE OR REPLACE VIEW v_item_details AS
SELECT
    i.item_id,
    i.pickup_id,
    i.item_description,
    i.condition,
    i.estimated_weight_kg,
    i.actual_weight_kg,
    i.hazard_details,
    i.hazard_details->>'contains_mercury'  AS has_mercury,
    i.hazard_details->>'battery_count'     AS battery_count,
    i.created_at,
    c.category_name,
    c.base_price_per_kg,
    c.hazard_level,
    c.recyclability_percentage,
    c.material_composition,
    u.full_name     AS owner_name,
    p.status        AS pickup_status,
    p.supervisor_id,
    ROUND(
        COALESCE(i.actual_weight_kg, i.estimated_weight_kg, 0)
        * c.base_price_per_kg, 2
    ) AS estimated_value
FROM items i
JOIN categories      c ON i.category_id = c.category_id
JOIN pickup_requests p ON i.pickup_id   = p.pickup_id
JOIN users           u ON p.user_id     = u.user_id;


-- ── v_supervisor_team ─────────────────────────────────────
-- Each supervisor with their drivers, collectors, vehicles, and KPIs.
CREATE OR REPLACE VIEW v_supervisor_team AS
SELECT
    sup.staff_id                                 AS supervisor_id,
    sup.full_name                                AS supervisor_name,
    sup.contact_number                           AS supervisor_contact,
    sup.is_active                                AS supervisor_active,
    -- team counts
    COUNT(DISTINCT m.staff_id) FILTER (WHERE m.sub_role = 'driver')
                                                 AS driver_count,
    COUNT(DISTINCT m.staff_id) FILTER (WHERE m.sub_role = 'collector')
                                                 AS collector_count,
    COUNT(DISTINCT veh.vehicle_id)               AS vehicle_count,
    -- pickup KPIs
    COUNT(DISTINCT p.pickup_id)                  AS total_pickups,
    COUNT(DISTINCT p.pickup_id) FILTER (WHERE p.status = 'completed')
                                                 AS completed_pickups,
    COUNT(DISTINCT p.pickup_id) FILTER (WHERE p.status = 'collected')
                                                 AS pending_payment,
    COALESCE(SUM(p.total_weight_kg) FILTER (WHERE p.status = 'completed'), 0)
                                                 AS total_weight_kg,
    COALESCE(SUM(py.amount) FILTER (WHERE py.payment_status = 'completed'), 0)
                                                 AS total_paid_out
FROM staff sup
LEFT JOIN staff            m   ON m.supervisor_id = sup.staff_id
LEFT JOIN vehicles         veh ON veh.supervisor_id = sup.staff_id
LEFT JOIN pickup_requests  p   ON p.supervisor_id = sup.staff_id
LEFT JOIN payments         py  ON py.pickup_id = p.pickup_id
WHERE sup.sub_role = 'supervisor'
GROUP BY sup.staff_id, sup.full_name, sup.contact_number, sup.is_active;


-- ── v_staff_full ──────────────────────────────────────────
-- All staff with their supervisor name, account username, and stats
CREATE OR REPLACE VIEW v_staff_full AS
SELECT
    s.staff_id,
    s.full_name,
    s.sub_role,
    s.contact_number,
    s.is_active,
    s.is_available,
    s.hired_at,
    s.fired_at,
    s.metadata,
    s.supervisor_id,
    sup.full_name    AS supervisor_name,
    a.username,
    a.last_login,
    a.account_id,
    -- warnings count
    (SELECT COUNT(*) FROM warnings w WHERE w.target_staff_id = s.staff_id)
                     AS warning_count
FROM staff s
LEFT JOIN staff    sup ON s.supervisor_id = sup.staff_id
LEFT JOIN accounts a   ON a.staff_id      = s.staff_id;


-- ── v_payment_requests_full ───────────────────────────────
CREATE OR REPLACE VIEW v_payment_requests_full AS
SELECT
    pr.request_id,
    pr.pickup_id,
    pr.user_id,
    pr.requested_at,
    pr.status,
    pr.is_duplicate,
    pr.admin_alerted,
    pr.notes,
    u.full_name          AS user_name,
    u.email              AS user_email,
    sup.full_name        AS supervisor_name,
    pr.supervisor_id,
    p.total_amount,
    p.payment_due_by,
    p.collected_at,
    p.status             AS pickup_status
FROM payment_requests pr
JOIN pickup_requests p   ON pr.pickup_id     = p.pickup_id
JOIN users           u   ON pr.user_id       = u.user_id
LEFT JOIN staff      sup ON pr.supervisor_id = sup.staff_id;


-- ── v_batch_full ──────────────────────────────────────────
CREATE OR REPLACE VIEW v_batch_full AS
SELECT
    b.batch_id,
    b.batch_name,
    b.status,
    b.created_date,
    b.processing_start_date,
    b.processing_end_date,
    b.total_weight_kg,
    b.recovery_rate_percentage,
    b.total_revenue,
    b.notes,
    rf.facility_name,
    rf.location              AS facility_location,
    sup.full_name            AS supervisor_name,
    b.supervisor_id,
    COUNT(DISTINCT bi.item_id)    AS item_count,
    COUNT(DISTINCT bi.pickup_id)  AS pickup_count,
    COALESCE(SUM(sr.total_value), 0) AS recorded_revenue,
    -- Live weight from items (before processing sets total_weight_kg)
    COALESCE((
        SELECT SUM(COALESCE(i2.actual_weight_kg, i2.estimated_weight_kg, 0))
        FROM batch_items bi2
        JOIN items i2 ON bi2.item_id = i2.item_id
        WHERE bi2.batch_id = b.batch_id
    ), 0) AS live_weight_kg
FROM recycling_batches  b
JOIN recycling_facilities rf ON b.facility_id  = rf.facility_id
LEFT JOIN staff         sup  ON b.supervisor_id = sup.staff_id
LEFT JOIN batch_items   bi   ON b.batch_id      = bi.batch_id
LEFT JOIN system_revenue sr  ON sr.batch_id     = b.batch_id
GROUP BY b.batch_id, b.batch_name, b.status, b.created_date,
         b.processing_start_date, b.processing_end_date,
         b.total_weight_kg, b.recovery_rate_percentage, b.total_revenue,
         b.notes, rf.facility_name, rf.location, sup.full_name, b.supervisor_id;


-- ── v_facility_capacity ───────────────────────────────────
CREATE OR REPLACE VIEW v_facility_capacity AS
SELECT
    facility_id,
    facility_name,
    location,
    specialization,
    capacity_kg,
    current_load_kg,
    capacity_kg - current_load_kg                        AS available_kg,
    ROUND(current_load_kg / NULLIF(capacity_kg,0) * 100, 1) AS utilisation_pct,
    is_operational
FROM recycling_facilities;


-- ── v_category_statistics ────────────────────────────────
CREATE OR REPLACE VIEW v_category_statistics AS
SELECT
    c.category_id,
    c.category_name,
    c.base_price_per_kg,
    c.hazard_level,
    c.recyclability_percentage,
    c.material_composition,
    COUNT(i.item_id)                                AS total_items,
    COALESCE(SUM(i.actual_weight_kg), 0)            AS total_weight_kg,
    ROUND(COALESCE(SUM(i.actual_weight_kg), 0)
          * c.base_price_per_kg, 2)                 AS total_payout_value,
    -- hazardous item count via JSONB
    COUNT(i.item_id) FILTER (
        WHERE (i.hazard_details->>'contains_mercury')::boolean = TRUE
    )                                               AS mercury_items
FROM categories c
LEFT JOIN items i ON c.category_id = i.category_id
GROUP BY c.category_id, c.category_name, c.base_price_per_kg,
         c.hazard_level, c.recyclability_percentage, c.material_composition;


-- ── v_system_revenue_summary ──────────────────────────────
-- Business income view: what we earn from processing
CREATE OR REPLACE VIEW v_system_revenue_summary AS
SELECT
    sr.material_type,
    COUNT(*)                       AS transaction_count,
    COALESCE(SUM(sr.weight_kg), 0) AS total_weight_kg,
    ROUND(AVG(sr.price_per_kg), 2) AS avg_price_per_kg,
    COALESCE(SUM(sr.total_value), 0) AS total_revenue,
    rf.facility_name,
    sr.facility_id
FROM system_revenue sr
JOIN recycling_facilities rf ON sr.facility_id = rf.facility_id
GROUP BY sr.material_type, sr.facility_id, rf.facility_name;


-- ── v_user_activity ───────────────────────────────────────
CREATE OR REPLACE VIEW v_user_activity AS
SELECT
    u.user_id,
    u.full_name,
    u.email,
    u.city,
    u.user_status,
    u.is_active,
    u.registered_at,
    u.last_pickup_at,
    COUNT(p.pickup_id)                                             AS total_pickups,
    COUNT(p.pickup_id) FILTER (WHERE p.status = 'completed')       AS completed_pickups,
    COALESCE(SUM(p.total_weight_kg) FILTER (WHERE p.status='completed'), 0) AS total_weight,
    COALESCE(SUM(p.total_amount)    FILTER (WHERE p.status='completed'), 0) AS total_earnings,
    (SELECT COUNT(*) FROM warnings w WHERE w.target_user_id = u.user_id) AS warning_count
FROM users u
LEFT JOIN pickup_requests p ON u.user_id = p.user_id
GROUP BY u.user_id, u.full_name, u.email, u.city, u.user_status,
         u.is_active, u.registered_at, u.last_pickup_at;


-- ── v_admin_alerts_active ─────────────────────────────────
CREATE OR REPLACE VIEW v_admin_alerts_active AS
SELECT *
FROM admin_alerts
WHERE is_resolved = FALSE
ORDER BY
    CASE severity
        WHEN 'critical' THEN 1
        WHEN 'high'     THEN 2
        WHEN 'medium'   THEN 3
        WHEN 'low'      THEN 4
    END,
    created_at DESC;


-- ── v_overdue_payments ────────────────────────────────────
CREATE OR REPLACE VIEW v_overdue_payments AS
SELECT
    p.pickup_id,
    p.user_id,
    u.full_name       AS user_name,
    u.phone           AS user_phone,
    p.total_amount,
    p.collected_at,
    p.payment_due_by,
    EXTRACT(EPOCH FROM (NOW() - p.payment_due_by)) / 3600 AS hours_overdue,
    p.supervisor_id,
    sup.full_name     AS supervisor_name,
    p.payment_request_count
FROM pickup_requests p
JOIN users u  ON p.user_id        = u.user_id
LEFT JOIN staff sup ON p.supervisor_id = sup.staff_id
WHERE p.status = 'collected'
  AND p.payment_due_by IS NOT NULL
  AND p.payment_due_by < NOW()
  AND NOT EXISTS (
      SELECT 1 FROM payments py
      WHERE py.pickup_id = p.pickup_id AND py.payment_status = 'completed'
  )
ORDER BY p.payment_due_by ASC;
