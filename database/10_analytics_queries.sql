-- Total pickups per user
SELECT 
    u.user_id,
    u.full_name,
    COUNT(pr.request_id) AS total_pickups
FROM users u
LEFT JOIN pickup_requests pr ON u.user_id = pr.user_id
GROUP BY u.user_id, u.full_name
ORDER BY total_pickups DESC;



SELECT
    c.category_name,
    SUM(w.weight_kg) AS total_weight_kg
FROM categories c
JOIN items i ON c.category_id = i.category_id
JOIN weight_records w ON i.item_id = w.item_id
GROUP BY c.category_name
ORDER BY total_weight_kg DESC;



SELECT
    DATE_TRUNC('month', pr.request_date) AS month,
    COUNT(pr.request_id) AS total_requests,
    SUM(COUNT(pr.request_id)) OVER (ORDER BY DATE_TRUNC('month', pr.request_date)) AS running_total
FROM pickup_requests pr
GROUP BY month
ORDER BY month;




SELECT
    u.full_name,
    pr.status,
    SUM(p.amount) AS total_amount
FROM payments p
JOIN pickup_requests pr ON p.request_id = pr.request_id
JOIN users u ON pr.user_id = u.user_id
GROUP BY ROLLUP (u.full_name, pr.status)
ORDER BY u.full_name, pr.status;




SELECT
    c.category_name,
    COUNT(i.item_id) AS total_items
FROM categories c
LEFT JOIN items i ON c.category_id = i.category_id
GROUP BY GROUPING SETS (
    (c.category_name),
    ()
);




SELECT category_name, total_items
FROM (
    SELECT
        c.category_name,
        COUNT(i.item_id) AS total_items
    FROM categories c
    JOIN items i ON c.category_id = i.category_id
    GROUP BY c.category_name
) AS category_counts
ORDER BY total_items DESC
LIMIT 3;




SELECT
    f.name AS facility_name,
    rb.batch_id,
    COUNT(bi.item_id) AS total_items
FROM recycling_batches rb
JOIN facilities f ON rb.facility_id = f.facility_id
LEFT JOIN batch_items bi ON rb.batch_id = bi.batch_id
GROUP BY f.name, rb.batch_id
ORDER BY f.name, rb.batch_id;




SELECT
    i.item_id,
    i.item_name,
    hazard_score(i.hazardous_info) AS hazard_score
FROM items i
WHERE hazard_score(i.hazardous_info) > 0
ORDER BY hazard_score DESC;




SELECT
    pr.request_id,
    AVG(w.weight_kg) AS avg_weight,
    AVG(AVG(w.weight_kg)) OVER () AS overall_avg_weight
FROM pickup_requests pr
JOIN items i ON pr.request_id = i.request_id
JOIN weight_records w ON i.item_id = w.item_id
GROUP BY pr.request_id;





SELECT
    s.full_name AS staff_name,
    COUNT(pr.request_id) AS assigned_requests
FROM staff s
LEFT JOIN pickup_requests pr ON s.staff_id = pr.assigned_staff_id
GROUP BY s.full_name
ORDER BY assigned_requests DESC;
