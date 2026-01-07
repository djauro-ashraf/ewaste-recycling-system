-- =========================
-- 04_views.sql
-- Commonly Used Views
-- =========================

-- 1. User Pickup Summary
-- Shows each user and how many pickup requests they have made
CREATE VIEW vw_user_pickup_summary AS
SELECT 
    u.user_id,
    u.full_name,
    u.email,
    COUNT(pr.request_id) AS total_requests
FROM users u
LEFT JOIN pickup_requests pr ON u.user_id = pr.user_id
GROUP BY u.user_id, u.full_name, u.email;


-- 2. Pickup Request Details View
-- Shows pickup request with user, staff, and vehicle info
CREATE VIEW vw_pickup_request_details AS
SELECT
    pr.request_id,
    pr.request_date,
    pr.status,
    u.full_name AS user_name,
    s.full_name AS staff_name,
    v.plate_number AS vehicle_plate
FROM pickup_requests pr
JOIN users u ON pr.user_id = u.user_id
LEFT JOIN staff s ON pr.assigned_staff_id = s.staff_id
LEFT JOIN vehicles v ON pr.assigned_vehicle_id = v.vehicle_id;


-- 3. Item Details View
-- Shows item with category and request info
CREATE VIEW vw_item_details AS
SELECT
    i.item_id,
    i.item_name,
    c.category_name,
    pr.request_id,
    pr.request_date,
    u.full_name AS user_name
FROM items i
JOIN categories c ON i.category_id = c.category_id
JOIN pickup_requests pr ON i.request_id = pr.request_id
JOIN users u ON pr.user_id = u.user_id;


-- 4. Weight and Item View
-- Shows item with its weight records
CREATE VIEW vw_item_weights AS
SELECT
    i.item_id,
    i.item_name,
    w.weight_kg,
    w.measured_at
FROM items i
JOIN weight_records w ON i.item_id = w.item_id;


-- 5. Payment Summary View
-- Shows payment with user and request info
CREATE VIEW vw_payment_summary AS
SELECT
    p.payment_id,
    p.amount,
    p.payment_status,
    p.paid_at,
    pr.request_id,
    u.full_name AS user_name
FROM payments p
JOIN pickup_requests pr ON p.request_id = pr.request_id
JOIN users u ON pr.user_id = u.user_id;


-- 6. Recycling Batch Overview
-- Shows batch with facility and number of items
CREATE VIEW vw_recycling_batch_overview AS
SELECT
    rb.batch_id,
    f.name AS facility_name,
    COUNT(bi.item_id) AS total_items,
    rb.created_at
FROM recycling_batches rb
JOIN facilities f ON rb.facility_id = f.facility_id
LEFT JOIN batch_items bi ON rb.batch_id = bi.batch_id
GROUP BY rb.batch_id, f.name, rb.created_at;
