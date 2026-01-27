-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 04_views.sql - Abstraction & Reporting Layer

-- View 1: Pickup Summary (complete pickup information)
CREATE OR REPLACE VIEW v_pickup_summary AS
SELECT 
    p.pickup_id,
    p.request_date,
    p.preferred_date,
    p.scheduled_time,
    p.status,
    u.user_id,
    u.full_name AS user_name,
    u.email AS user_email,
    u.phone AS user_phone,
    p.pickup_address,
    s.staff_name,
    s.contact_number AS staff_contact,
    v.vehicle_number,
    v.vehicle_type,
    f.facility_name,
    f.location AS facility_location,
    p.total_weight_kg,
    p.total_amount,
    p.completed_time,
    COUNT(DISTINCT i.item_id) AS item_count,
    COUNT(DISTINCT i.category_id) AS category_count
FROM pickup_requests p
JOIN users u ON p.user_id = u.user_id
LEFT JOIN staff_assignments s ON p.assigned_staff_id = s.staff_id
LEFT JOIN vehicles v ON p.assigned_vehicle_id = v.vehicle_id
LEFT JOIN recycling_facilities f ON p.assigned_facility_id = f.facility_id
LEFT JOIN items i ON p.pickup_id = i.pickup_id
GROUP BY 
    p.pickup_id, u.user_id, u.full_name, u.email, u.phone,
    s.staff_name, s.contact_number, v.vehicle_number, v.vehicle_type,
    f.facility_name, f.location;

-- View 2: Item Details (items with category and weight info)
CREATE OR REPLACE VIEW v_item_details AS
SELECT 
    i.item_id,
    i.pickup_id,
    p.request_date AS pickup_date,
    p.status AS pickup_status,
    u.full_name AS user_name,
    c.category_id,
    c.category_name,
    c.hazard_level,
    i.item_description,
    i.condition,
    i.estimated_weight_kg,
    i.actual_weight_kg,
    COALESCE(i.actual_weight_kg, i.estimated_weight_kg) AS effective_weight_kg,
    i.hazard_details,
    c.base_price_per_kg,
    COALESCE(i.actual_weight_kg, i.estimated_weight_kg) * c.base_price_per_kg AS estimated_value
FROM items i
JOIN pickup_requests p ON i.pickup_id = p.pickup_id
JOIN users u ON p.user_id = u.user_id
JOIN categories c ON i.category_id = c.category_id;

-- View 3: Payment Summary (payments with pickup info)
CREATE OR REPLACE VIEW v_payment_summary AS
SELECT 
    pay.payment_id,
    pay.pickup_id,
    p.request_date AS pickup_date,
    u.full_name AS user_name,
    u.email AS user_email,
    pay.amount,
    pay.payment_method,
    pay.payment_status,
    pay.transaction_reference,
    pay.processed_at,
    p.total_weight_kg,
    p.status AS pickup_status
FROM payments pay
JOIN pickup_requests p ON pay.pickup_id = p.pickup_id
JOIN users u ON p.user_id = u.user_id;

-- View 4: Batch Summary (recycling batches with items)
CREATE OR REPLACE VIEW v_batch_summary AS
SELECT 
    b.batch_id,
    b.batch_name,
    b.facility_id,
    f.facility_name,
    f.location AS facility_location,
    b.created_date,
    b.processing_start_date,
    b.processing_end_date,
    b.status,
    b.total_weight_kg,
    b.recovery_rate_percentage,
    COUNT(DISTINCT bi.item_id) AS item_count,
    COUNT(DISTINCT i.category_id) AS category_count,
    CASE 
        WHEN b.processing_end_date IS NOT NULL AND b.processing_start_date IS NOT NULL
        THEN b.processing_end_date - b.processing_start_date
        ELSE NULL
    END AS processing_days
FROM recycling_batches b
JOIN recycling_facilities f ON b.facility_id = f.facility_id
LEFT JOIN batch_items bi ON b.batch_id = bi.batch_id
LEFT JOIN items i ON bi.item_id = i.item_id
GROUP BY 
    b.batch_id, b.batch_name, f.facility_id, f.facility_name, 
    f.location, b.created_date, b.processing_start_date, 
    b.processing_end_date, b.status, b.total_weight_kg, 
    b.recovery_rate_percentage;

-- View 5: Staff Workload (staff assignments and current load)
CREATE OR REPLACE VIEW v_staff_workload AS
SELECT 
    s.staff_id,
    s.staff_name,
    s.role,
    s.contact_number,
    s.is_available,
    v.vehicle_number,
    v.vehicle_type,
    v.current_load_kg AS vehicle_load,
    v.capacity_kg AS vehicle_capacity,
    COUNT(DISTINCT p.pickup_id) AS assigned_pickups,
    COUNT(DISTINCT CASE WHEN p.status = 'pending' THEN p.pickup_id END) AS pending_pickups,
    COUNT(DISTINCT CASE WHEN p.status = 'assigned' THEN p.pickup_id END) AS active_pickups,
    COUNT(DISTINCT CASE WHEN p.status = 'completed' THEN p.pickup_id END) AS completed_pickups,
    SUM(CASE WHEN p.status IN ('assigned', 'collected') THEN p.total_weight_kg ELSE 0 END) AS current_load_kg
FROM staff_assignments s
LEFT JOIN vehicles v ON s.assigned_vehicle_id = v.vehicle_id
LEFT JOIN pickup_requests p ON s.staff_id = p.assigned_staff_id
GROUP BY 
    s.staff_id, s.staff_name, s.role, s.contact_number, s.is_available,
    v.vehicle_number, v.vehicle_type, v.current_load_kg, v.capacity_kg;

-- View 6: Facility Capacity Status
CREATE OR REPLACE VIEW v_facility_capacity AS
SELECT 
    f.facility_id,
    f.facility_name,
    f.location,
    f.specialization,
    f.capacity_kg,
    f.current_load_kg,
    f.capacity_kg - f.current_load_kg AS available_capacity_kg,
    ROUND((f.current_load_kg / f.capacity_kg * 100)::numeric, 2) AS capacity_usage_percent,
    f.is_operational,
    COUNT(DISTINCT b.batch_id) AS total_batches,
    COUNT(DISTINCT CASE WHEN b.status = 'open' THEN b.batch_id END) AS open_batches,
    COUNT(DISTINCT CASE WHEN b.status = 'processing' THEN b.batch_id END) AS processing_batches
FROM recycling_facilities f
LEFT JOIN recycling_batches b ON f.facility_id = b.facility_id
GROUP BY 
    f.facility_id, f.facility_name, f.location, f.specialization,
    f.capacity_kg, f.current_load_kg, f.is_operational;

-- View 7: Category Statistics (aggregated by category)
CREATE OR REPLACE VIEW v_category_statistics AS
SELECT 
    c.category_id,
    c.category_name,
    c.hazard_level,
    c.base_price_per_kg,
    c.recyclability_percentage,
    COUNT(DISTINCT i.item_id) AS total_items,
    COUNT(DISTINCT i.pickup_id) AS total_pickups,
    SUM(COALESCE(i.actual_weight_kg, i.estimated_weight_kg)) AS total_weight_kg,
    AVG(COALESCE(i.actual_weight_kg, i.estimated_weight_kg)) AS avg_weight_per_item_kg,
    SUM(COALESCE(i.actual_weight_kg, i.estimated_weight_kg) * c.base_price_per_kg) AS total_value
FROM categories c
LEFT JOIN items i ON c.category_id = i.category_id
GROUP BY 
    c.category_id, c.category_name, c.hazard_level, 
    c.base_price_per_kg, c.recyclability_percentage;

-- View 8: User Activity Summary
CREATE OR REPLACE VIEW v_user_activity AS
SELECT 
    u.user_id,
    u.full_name,
    u.email,
    u.phone,
    u.city,
    u.registered_at,
    u.is_active,
    COUNT(DISTINCT p.pickup_id) AS total_pickups,
    COUNT(DISTINCT CASE WHEN p.status = 'completed' THEN p.pickup_id END) AS completed_pickups,
    COUNT(DISTINCT CASE WHEN p.status = 'pending' THEN p.pickup_id END) AS pending_pickups,
    SUM(p.total_weight_kg) AS total_weight_recycled_kg,
    SUM(p.total_amount) AS total_earnings,
    MAX(p.request_date) AS last_pickup_date,
    COUNT(DISTINCT i.category_id) AS categories_recycled
FROM users u
LEFT JOIN pickup_requests p ON u.user_id = p.user_id
LEFT JOIN items i ON p.pickup_id = i.pickup_id
GROUP BY 
    u.user_id, u.full_name, u.email, u.phone, u.city, 
    u.registered_at, u.is_active;

-- View 9: Recent Audit Trail (last 100 changes)
CREATE OR REPLACE VIEW v_recent_audit_trail AS
SELECT 
    log_id,
    table_name,
    operation,
    record_id,
    old_values,
    new_values,
    changed_by,
    changed_at
FROM audit_log
ORDER BY changed_at DESC
LIMIT 100;

-- View 10: Weight Tracking History
CREATE OR REPLACE VIEW v_weight_tracking AS
SELECT 
    wr.weight_id,
    wr.item_id,
    i.item_description,
    c.category_name,
    p.pickup_id,
    u.full_name AS user_name,
    wr.weighing_stage,
    wr.weight_kg,
    wr.weighed_by,
    wr.weighed_at,
    i.estimated_weight_kg,
    i.actual_weight_kg
FROM weight_records wr
JOIN items i ON wr.item_id = i.item_id
JOIN categories c ON i.category_id = c.category_id
JOIN pickup_requests p ON i.pickup_id = p.pickup_id
JOIN users u ON p.user_id = u.user_id;

-- Comments explaining view design:
-- 1. Views hide complex JOINs from application layer
-- 2. Calculated fields (counts, sums, averages) computed in database
-- 3. LEFT JOINs used to include records even when related data missing
-- 4. Aggregations grouped appropriately for reporting
-- 5. COALESCEs handle NULL values gracefully
-- 6. Views serve as data access layer for frontend
-- 7. Each view represents a specific business need or report