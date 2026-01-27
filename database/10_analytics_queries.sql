-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 10_analytics_queries.sql - Advanced SQL & Reporting

-- QUERY 1: Monthly Pickup Statistics with Trends
SELECT 
    EXTRACT(YEAR FROM request_date) AS year,
    EXTRACT(MONTH FROM request_date) AS month,
    TO_CHAR(request_date, 'Month YYYY') AS period,
    COUNT(*) AS total_pickups,
    COUNT(*) FILTER (WHERE status = 'completed') AS completed_pickups,
    SUM(total_weight_kg) AS total_weight_kg,
    SUM(total_amount) AS total_amount,
    AVG(total_weight_kg) AS avg_weight_per_pickup,
    AVG(total_amount) AS avg_amount_per_pickup,
    -- Previous month comparison
    LAG(COUNT(*)) OVER (ORDER BY EXTRACT(YEAR FROM request_date), EXTRACT(MONTH FROM request_date)) AS prev_month_pickups,
    COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY EXTRACT(YEAR FROM request_date), EXTRACT(MONTH FROM request_date)) AS pickup_change
FROM pickup_requests
GROUP BY EXTRACT(YEAR FROM request_date), EXTRACT(MONTH FROM request_date), TO_CHAR(request_date, 'Month YYYY')
ORDER BY year DESC, month DESC;

-- QUERY 2: Category Performance Ranking
WITH category_metrics AS (
    SELECT 
        c.category_id,
        c.category_name,
        c.hazard_level,
        COUNT(DISTINCT i.item_id) AS total_items,
        SUM(COALESCE(i.actual_weight_kg, i.estimated_weight_kg)) AS total_weight,
        SUM(calculate_item_price(c.category_id, COALESCE(i.actual_weight_kg, i.estimated_weight_kg))) AS total_value,
        COUNT(DISTINCT i.pickup_id) AS total_pickups,
        AVG(COALESCE(i.actual_weight_kg, i.estimated_weight_kg)) AS avg_item_weight
    FROM categories c
    LEFT JOIN items i ON c.category_id = i.category_id
    GROUP BY c.category_id, c.category_name, c.hazard_level
)
SELECT 
    RANK() OVER (ORDER BY total_value DESC) AS value_rank,
    RANK() OVER (ORDER BY total_weight DESC) AS weight_rank,
    RANK() OVER (ORDER BY total_items DESC) AS volume_rank,
    category_name,
    hazard_level,
    total_items,
    ROUND(total_weight, 2) AS total_weight_kg,
    ROUND(total_value, 2) AS total_value_bdt,
    ROUND(avg_item_weight, 3) AS avg_weight_kg,
    total_pickups
FROM category_metrics
ORDER BY total_value DESC;

-- QUERY 3: User Engagement Analysis with RFM-style Scoring
WITH user_rfm AS (
    SELECT 
        u.user_id,
        u.full_name,
        u.city,
        COUNT(DISTINCT p.pickup_id) AS frequency,
        COALESCE(SUM(p.total_amount), 0) AS monetary,
        COALESCE(MAX(p.request_date), u.registered_at) AS last_pickup_date,
        CURRENT_DATE - COALESCE(MAX(p.request_date), u.registered_at)::date AS days_since_last_pickup,
        COALESCE(SUM(p.total_weight_kg), 0) AS total_weight
    FROM users u
    LEFT JOIN pickup_requests p ON u.user_id = p.user_id
    WHERE u.is_active = TRUE
    GROUP BY u.user_id, u.full_name, u.city, u.registered_at
)
SELECT 
    user_id,
    full_name,
    city,
    frequency AS total_pickups,
    ROUND(monetary, 2) AS total_earnings_bdt,
    ROUND(total_weight, 2) AS total_weight_kg,
    days_since_last_pickup,
    CASE 
        WHEN days_since_last_pickup <= 30 THEN 'Active'
        WHEN days_since_last_pickup <= 90 THEN 'Recent'
        WHEN days_since_last_pickup <= 180 THEN 'Dormant'
        ELSE 'Inactive'
    END AS engagement_status,
    NTILE(5) OVER (ORDER BY frequency DESC) AS frequency_quintile,
    NTILE(5) OVER (ORDER BY monetary DESC) AS monetary_quintile
FROM user_rfm
ORDER BY monetary DESC, frequency DESC;

-- QUERY 4: Facility Efficiency Analysis
SELECT 
    f.facility_id,
    f.facility_name,
    f.location,
    f.specialization,
    ROUND((f.current_load_kg / f.capacity_kg * 100), 2) AS capacity_utilization_pct,
    COUNT(DISTINCT b.batch_id) AS total_batches,
    COUNT(DISTINCT CASE WHEN b.status = 'completed' THEN b.batch_id END) AS completed_batches,
    COALESCE(AVG(CASE WHEN b.status = 'completed' THEN b.recovery_rate_percentage END), 0) AS avg_recovery_rate,
    COALESCE(SUM(CASE WHEN b.status = 'completed' THEN b.total_weight_kg END), 0) AS total_processed_kg,
    COALESCE(AVG(CASE 
        WHEN b.status = 'completed' 
        THEN b.processing_end_date - b.processing_start_date 
    END), 0) AS avg_processing_days,
    COUNT(DISTINCT p.pickup_id) AS total_assigned_pickups,
    -- Efficiency score (higher is better)
    ROUND(
        (COALESCE(AVG(CASE WHEN b.status = 'completed' THEN b.recovery_rate_percentage END), 0) * 0.5 +
         (COUNT(DISTINCT CASE WHEN b.status = 'completed' THEN b.batch_id END)::numeric / 
          NULLIF(COUNT(DISTINCT b.batch_id), 0) * 100) * 0.3 +
         (f.current_load_kg / f.capacity_kg * 100) * 0.2)
    , 2) AS efficiency_score
FROM recycling_facilities f
LEFT JOIN recycling_batches b ON f.facility_id = b.facility_id
LEFT JOIN pickup_requests p ON f.facility_id = p.assigned_facility_id
GROUP BY f.facility_id, f.facility_name, f.location, f.specialization, f.current_load_kg, f.capacity_kg
ORDER BY efficiency_score DESC;

-- QUERY 5: Staff Performance Dashboard
WITH staff_metrics AS (
    SELECT 
        s.staff_id,
        s.staff_name,
        s.role,
        COUNT(DISTINCT p.pickup_id) AS total_assigned,
        COUNT(DISTINCT CASE WHEN p.status = 'completed' THEN p.pickup_id END) AS completed_pickups,
        COUNT(DISTINCT CASE WHEN p.status = 'cancelled' THEN p.pickup_id END) AS cancelled_pickups,
        COALESCE(SUM(CASE WHEN p.status = 'completed' THEN p.total_weight_kg END), 0) AS total_weight_collected,
        COALESCE(SUM(CASE WHEN p.status = 'completed' THEN p.total_amount END), 0) AS total_value_collected,
        AVG(CASE 
            WHEN p.status = 'completed' AND p.completed_time IS NOT NULL 
            THEN EXTRACT(EPOCH FROM (p.completed_time - p.scheduled_time)) / 3600 
        END) AS avg_completion_hours
    FROM staff_assignments s
    LEFT JOIN pickup_requests p ON s.staff_id = p.assigned_staff_id
    GROUP BY s.staff_id, s.staff_name, s.role
)
SELECT 
    RANK() OVER (ORDER BY completed_pickups DESC) AS performance_rank,
    staff_id,
    staff_name,
    role,
    total_assigned,
    completed_pickups,
    cancelled_pickups,
    CASE 
        WHEN total_assigned > 0 
        THEN ROUND((completed_pickups::numeric / total_assigned * 100), 2)
        ELSE 0 
    END AS completion_rate_pct,
    ROUND(total_weight_collected, 2) AS weight_collected_kg,
    ROUND(total_value_collected, 2) AS value_collected_bdt,
    ROUND(COALESCE(avg_completion_hours, 0), 2) AS avg_completion_hours,
    CASE
        WHEN completed_pickups >= 10 AND completion_rate_pct >= 90 THEN 'Excellent'
        WHEN completed_pickups >= 5 AND completion_rate_pct >= 80 THEN 'Good'
        WHEN completed_pickups >= 3 THEN 'Average'
        ELSE 'Needs Improvement'
    END AS performance_rating
FROM staff_metrics
ORDER BY performance_rank;

-- QUERY 6: Payment Analysis by Method and Time
SELECT 
    payment_method,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount,
    COUNT(*) FILTER (WHERE payment_status = 'completed') AS completed_count,
    COUNT(*) FILTER (WHERE payment_status = 'pending') AS pending_count,
    COUNT(*) FILTER (WHERE payment_status = 'failed') AS failed_count,
    ROUND(
        COUNT(*) FILTER (WHERE payment_status = 'completed')::numeric / 
        COUNT(*)::numeric * 100, 
        2
    ) AS success_rate_pct
FROM payments
GROUP BY payment_method
ORDER BY total_amount DESC;

-- QUERY 7: Hazardous Material Tracking
SELECT 
    c.category_name,
    c.hazard_level,
    COUNT(DISTINCT i.item_id) AS item_count,
    COUNT(DISTINCT i.pickup_id) AS pickup_count,
    SUM(COALESCE(i.actual_weight_kg, i.estimated_weight_kg)) AS total_weight_kg,
    COUNT(DISTINCT CASE 
        WHEN i.hazard_details IS NOT NULL 
        THEN i.item_id 
    END) AS items_with_hazard_details,
    -- Extract specific hazard information from JSONB
    COUNT(DISTINCT CASE 
        WHEN i.hazard_details->>'leaking' = 'true' 
        THEN i.item_id 
    END) AS leaking_items,
    string_agg(DISTINCT f.facility_name, ', ') AS handling_facilities
FROM items i
JOIN categories c ON i.category_id = c.category_id
JOIN pickup_requests p ON i.pickup_id = p.pickup_id
LEFT JOIN recycling_facilities f ON p.assigned_facility_id = f.facility_id
WHERE c.hazard_level >= 3
GROUP BY c.category_id, c.category_name, c.hazard_level
ORDER BY c.hazard_level DESC, total_weight_kg DESC;

-- QUERY 8: Weight Discrepancy Analysis
WITH weight_comparison AS (
    SELECT 
        i.item_id,
        i.item_description,
        c.category_name,
        i.estimated_weight_kg,
        i.actual_weight_kg,
        ABS(COALESCE(i.actual_weight_kg, 0) - COALESCE(i.estimated_weight_kg, 0)) AS weight_difference,
        CASE 
            WHEN i.estimated_weight_kg > 0 
            THEN ABS((COALESCE(i.actual_weight_kg, 0) - i.estimated_weight_kg) / i.estimated_weight_kg * 100)
            ELSE 0 
        END AS difference_percentage
    FROM items i
    JOIN categories c ON i.category_id = c.category_id
    WHERE i.estimated_weight_kg IS NOT NULL 
      AND i.actual_weight_kg IS NOT NULL
)
SELECT 
    category_name,
    COUNT(*) AS items_weighed,
    ROUND(AVG(estimated_weight_kg), 3) AS avg_estimated_kg,
    ROUND(AVG(actual_weight_kg), 3) AS avg_actual_kg,
    ROUND(AVG(weight_difference), 3) AS avg_difference_kg,
    ROUND(AVG(difference_percentage), 2) AS avg_difference_pct,
    COUNT(*) FILTER (WHERE difference_percentage > 20) AS high_discrepancy_count
FROM weight_comparison
GROUP BY category_name
HAVING COUNT(*) >= 1
ORDER BY avg_difference_pct DESC;

-- QUERY 9: Time-Series Analysis - Daily Pickup Trends
WITH daily_stats AS (
    SELECT 
        request_date::date AS pickup_date,
        COUNT(*) AS daily_pickups,
        SUM(total_weight_kg) AS daily_weight,
        SUM(total_amount) AS daily_amount
    FROM pickup_requests
    WHERE request_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY request_date::date
)
SELECT 
    pickup_date,
    daily_pickups,
    ROUND(daily_weight, 2) AS weight_kg,
    ROUND(daily_amount, 2) AS amount_bdt,
    -- Moving averages
    ROUND(AVG(daily_pickups) OVER (
        ORDER BY pickup_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS pickup_7day_ma,
    ROUND(AVG(daily_weight) OVER (
        ORDER BY pickup_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS weight_7day_ma,
    -- Day of week pattern
    TO_CHAR(pickup_date, 'Day') AS day_of_week,
    -- Growth rate
    daily_pickups - LAG(daily_pickups) OVER (ORDER BY pickup_date) AS pickup_change
FROM daily_stats
ORDER BY pickup_date DESC;

-- QUERY 10: Comprehensive System Health Report
WITH system_stats AS (
    SELECT 
        (SELECT COUNT(*) FROM users WHERE is_active = TRUE) AS active_users,
        (SELECT COUNT(*) FROM pickup_requests) AS total_pickups,
        (SELECT COUNT(*) FROM pickup_requests WHERE status = 'pending') AS pending_pickups,
        (SELECT COUNT(*) FROM pickup_requests WHERE status = 'completed') AS completed_pickups,
        (SELECT SUM(total_weight_kg) FROM pickup_requests WHERE status = 'completed') AS total_weight_recycled,
        (SELECT SUM(total_amount) FROM pickup_requests WHERE status = 'completed') AS total_payments_made,
        (SELECT COUNT(*) FROM recycling_facilities WHERE is_operational = TRUE) AS operational_facilities,
        (SELECT COUNT(*) FROM staff_assignments WHERE is_available = TRUE) AS available_staff,
        (SELECT COUNT(*) FROM vehicles WHERE is_available = TRUE) AS available_vehicles,
        (SELECT COUNT(*) FROM recycling_batches WHERE status = 'completed') AS completed_batches,
        (SELECT AVG(capacity_kg - current_load_kg) FROM recycling_facilities WHERE is_operational = TRUE) AS avg_facility_capacity
)
SELECT 
    'System Health Report - ' || CURRENT_DATE AS report_title,
    active_users,
    total_pickups,
    pending_pickups,
    completed_pickups,
    ROUND((completed_pickups::numeric / NULLIF(total_pickups, 0) * 100), 2) AS completion_rate_pct,
    ROUND(total_weight_recycled, 2) AS total_weight_recycled_kg,
    ROUND(total_payments_made, 2) AS total_payments_bdt,
    operational_facilities,
    available_staff,
    available_vehicles,
    completed_batches,
    ROUND(avg_facility_capacity, 2) AS avg_available_capacity_kg
FROM system_stats;

-- Comments:
-- 1. Advanced SQL: window functions, CTEs, aggregations
-- 2. Ranking and trend analysis
-- 3. Moving averages for time series
-- 4. JSONB querying for flexible data
-- 5. Statistical functions (percentile, ntile)
-- 6. Complex filtering and grouping
-- 7. Self-referencing for period comparisons
-- 8. These queries demonstrate analytical capabilities
-- 9. All queries are ready for frontend display
-- 10. Shows database as business intelligence platform