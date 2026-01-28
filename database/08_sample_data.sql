-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 08_sample_data.sql - Demonstration Dataset (CORRECTED VERSION)
-- ============================================
-- SAMPLE DATA SAFE RESET (DATA ONLY)
-- Keeps triggers, clears rows, resets IDs
-- ============================================


TRUNCATE TABLE
    audit_log,
    batch_items,
    recycling_batches,
    payments,
    weight_records,
    items,
    pickup_requests,
    pricing_rules,
    categories,
    staff_assignments,
    vehicles,
    recycling_facilities,
    users
RESTART IDENTITY CASCADE;

-- Insert Users
INSERT INTO users (full_name, email, phone, address, city) VALUES
('Ahmed Rahman', 'ahmed.rahman@email.com', '+880-1711-123456', 'House 12, Road 5, Dhanmondi', 'Dhaka'),
('Fatima Khan', 'fatima.khan@email.com', '+880-1812-234567', 'Flat 3B, Gulshan Avenue', 'Dhaka'),
('Mohammad Ali', 'mohammad.ali@email.com', '+880-1913-345678', 'Block C, Bashundhara R/A', 'Dhaka'),
('Ayesha Begum', 'ayesha.begum@email.com', '+880-1714-456789', 'House 45, Banani', 'Dhaka'),
('Karim Hossain', 'karim.h@email.com', '+880-1815-567890', 'Sector 11, Uttara', 'Dhaka');

-- Insert Recycling Facilities
INSERT INTO recycling_facilities (facility_name, location, capacity_kg, specialization) VALUES
('Green Tech Recycling Center', 'Tejgaon Industrial Area', 50000.00, 'electronics'),
('Eco Waste Solutions', 'Tongi', 30000.00, 'batteries'),
('Metro Recycling Hub', 'Gazipur', 40000.00, 'metals'),
('Digital Waste Processing', 'Savar', 35000.00, 'electronics');

-- Insert Vehicles
INSERT INTO vehicles (vehicle_number, vehicle_type, capacity_kg) VALUES
('DHK-GA-1234', 'pickup_truck', 2000.00),
('DHK-KA-5678', 'van', 1500.00),
('DHK-CHA-9012', 'pickup_truck', 2000.00),
('DHK-GA-3456', 'small_truck', 2500.00);

-- Insert Staff
INSERT INTO staff_assignments (staff_name, role, contact_number, assigned_vehicle_id) VALUES
('Rahim Mia', 'driver', '+880-1711-111111', 1),
('Salim Ahmed', 'driver', '+880-1812-222222', 2),
('Kamal Hossain', 'collector', '+880-1913-333333', 3),
('Jamal Uddin', 'driver', '+880-1714-444444', 4),
('Shahid Alam', 'supervisor', '+880-1815-555555', NULL);

-- Insert E-Waste Categories
INSERT INTO categories (category_name, description, base_price_per_kg, hazard_level, recyclability_percentage) VALUES
('Mobile Phones', 'Smartphones, feature phones, tablets', 45.00, 2, 75.00),
('Laptops', 'Notebooks, chromebooks, ultrabooks', 60.00, 2, 80.00),
('Desktop Computers', 'Desktop PCs, monitors, keyboards', 35.00, 2, 70.00),
('Batteries', 'Lithium-ion, lead-acid, alkaline batteries', 25.00, 5, 65.00),
('Televisions', 'LCD, LED, CRT televisions', 30.00, 3, 60.00),
('Home Appliances', 'Microwaves, toasters, fans', 20.00, 1, 55.00),
('Cables & Wires', 'Power cables, data cables, adapters', 15.00, 1, 85.00),
('Printers & Scanners', 'Inkjet, laser printers, scanners', 28.00, 2, 65.00);

-- Insert Pricing Rules (with volume-based bonuses)
INSERT INTO pricing_rules (category_id, min_weight_kg, max_weight_kg, price_per_kg, bonus_percentage, effective_from) VALUES
-- Mobile Phones
(1, 0, 5, 45.00, 0, '2025-01-01'),
(1, 5, 20, 50.00, 10, '2025-01-01'),
(1, 20, NULL, 55.00, 20, '2025-01-01'),
-- Laptops
(2, 0, 10, 60.00, 0, '2025-01-01'),
(2, 10, NULL, 65.00, 15, '2025-01-01'),
-- Batteries (flat rate due to hazard)
(4, 0, NULL, 25.00, 0, '2025-01-01'),
-- Desktop Computers
(3, 0, 15, 35.00, 0, '2025-01-01'),
(3, 15, NULL, 40.00, 10, '2025-01-01');

-- Create some pickup requests and items
-- Using DO block for complex workflow
DO $$
DECLARE
    v_pickup_id INT;
    v_item_id INT;
    v_payment_id INT;
    v_payment_amount DECIMAL;
    v_batch_id INT;
BEGIN
    -- ========================================
    -- Pickup 1: Ahmed Rahman - Mobile phones
    -- ========================================
    RAISE NOTICE 'Creating Pickup 1: Mobile phones...';
    
    CALL create_pickup_request(
        1,
        CURRENT_DATE + 2,
        'House 12, Road 5, Dhanmondi, Dhaka',
        v_pickup_id,
        'Old smartphones and chargers'
    );
    
    RAISE NOTICE 'Pickup % created. Adding items...', v_pickup_id;
    
    -- Add items to pickup 1
    CALL add_item_to_pickup(
        v_pickup_id,
        1,
        'Samsung Galaxy S10 (broken screen)',
        v_item_id,
        'broken',
        0.18,
        '{"screen_condition": "cracked", "battery_health": "poor"}'::jsonb
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        1,
        'iPhone 7 (water damaged)',
        v_item_id,
        'broken',
        0.15,
        '{"water_damage": true}'::jsonb
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        7,
        'Old charging cables and adapters',
        v_item_id,
        'working',
        0.5,
        NULL
    );
    
    -- Complete workflow for pickup 1
    RAISE NOTICE 'Assigning pickup %...', v_pickup_id;
    CALL assign_pickup_to_staff(v_pickup_id, 1, 1, 1, (CURRENT_TIMESTAMP + INTERVAL '2 days')::TIMESTAMP);
    
    RAISE NOTICE 'Completing collection for pickup %...', v_pickup_id;
    CALL complete_pickup_collection(v_pickup_id);
    
    RAISE NOTICE 'Processing payment for pickup %...', v_pickup_id;
    CALL process_payment(
        v_pickup_id,
        'bank_transfer',
        v_payment_id,
        v_payment_amount,
        'TXN-2025-001'
    );
    RAISE NOTICE 'Payment % processed: Amount = %', v_payment_id, v_payment_amount;
    
    -- ========================================
    -- Pickup 2: Fatima Khan - Old laptop
    -- ========================================
    RAISE NOTICE 'Creating Pickup 2: Laptop...';
    
    CALL create_pickup_request(
        2,
        CURRENT_DATE + 3,
        'Flat 3B, Gulshan Avenue, Dhaka',
        v_pickup_id,
        'Old laptop for recycling'
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        2,
        'Dell Inspiron 15 (2015 model, working)',
        v_item_id,
        'working',
        2.3,
        NULL
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        2,
        'HP Laptop charger',
        v_item_id,
        'working',
        0.4,
        NULL
    );
    
    RAISE NOTICE 'Pickup % left in pending state', v_pickup_id;
    
    -- ========================================
    -- Pickup 3: Mohammad Ali - Desktop setup
    -- ========================================
    RAISE NOTICE 'Creating Pickup 3: Desktop computer...';
    
    CALL create_pickup_request(
        3,
        CURRENT_DATE + 1,
        'Block C, Bashundhara R/A, Dhaka',
        v_pickup_id,
        'Complete desktop setup'
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        3,
        'Dell Desktop PC Tower',
        v_item_id,
        'working',
        8.5,
        NULL
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        3,
        'Samsung 22" LCD Monitor',
        v_item_id,
        'working',
        4.2,
        NULL
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        3,
        'Keyboard and Mouse',
        v_item_id,
        'working',
        0.8,
        NULL
    );
    
    RAISE NOTICE 'Assigning pickup %...', v_pickup_id;
    CALL assign_pickup_to_staff(v_pickup_id, 2, 2, 1,  (CURRENT_TIMESTAMP + INTERVAL '2 days')::TIMESTAMP);
    RAISE NOTICE 'Pickup % left in assigned state', v_pickup_id;
    
    -- ========================================
    -- Pickup 4: Ayesha Begum - TV and appliances
    -- ========================================
    RAISE NOTICE 'Creating Pickup 4: TV and appliances...';
    
    CALL create_pickup_request(
        4,
        CURRENT_DATE + 4,
        'House 45, Banani, Dhaka',
        v_pickup_id,
        'Old TV and kitchen appliances'
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        5,
        'Sony 32" LCD TV (not working)',
        v_item_id,
        'broken',
        12.5,
        NULL
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        6,
        'Old microwave oven',
        v_item_id,
        'working',
        8.0,
        NULL
    );
    
    RAISE NOTICE 'Pickup % left in pending state', v_pickup_id;
    
    -- ========================================
    -- Pickup 5: Karim Hossain - Hazardous batteries
    -- ========================================
    RAISE NOTICE 'Creating Pickup 5: Hazardous batteries...';
    
    CALL create_pickup_request(
        5,
        CURRENT_DATE + 5,
        'Sector 11, Uttara, Dhaka',
        v_pickup_id,
        'Old batteries collection'
    );
    
    RAISE NOTICE 'Adding high-hazard items (should trigger alerts)...';
    
    CALL add_item_to_pickup(
        v_pickup_id,
        4,
        'Car battery (lead-acid)',
        v_item_id,
        'broken',
        15.0,
        '{"type": "lead-acid", "voltage": "12V", "leaking": false}'::jsonb
    );
    
    CALL add_item_to_pickup(
        v_pickup_id,
        4,
        'UPS batteries (2 units)',
        v_item_id,
        'broken',
        12.0,
        '{"type": "sealed-lead-acid", "count": 2}'::jsonb
    );
    
    RAISE NOTICE 'Pickup % left in pending state', v_pickup_id;
    
    -- ========================================
    -- Create a recycling batch
    -- ========================================
    RAISE NOTICE 'Creating recycling batch...';
    
    CALL create_recycling_batch(
        1,
        'Electronics Batch Jan 2025',
        v_batch_id,
        'First batch of the month - electronics focus'
    );
    
    RAISE NOTICE 'Batch % created successfully', v_batch_id;
    
    -- ========================================
    -- Summary
    -- ========================================
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Sample data insertion completed successfully!';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Created 5 pickups:';
    RAISE NOTICE '  - Pickup 1: Completed (with payment)';
    RAISE NOTICE '  - Pickup 2: Pending';
    RAISE NOTICE '  - Pickup 3: Assigned';
    RAISE NOTICE '  - Pickup 4: Pending';
    RAISE NOTICE '  - Pickup 5: Pending (high hazard)';
    RAISE NOTICE 'Created 1 recycling batch';
    RAISE NOTICE '==============================================';
    
END $$;

-- Insert weight records for completed pickup
INSERT INTO weight_records (item_id, weighing_stage, weight_kg, weighed_by, notes) VALUES
(1, 'pickup', 0.175, 'Rahim Mia', 'Weighed at user location'),
(2, 'pickup', 0.148, 'Rahim Mia', 'Weighed at user location'),
(3, 'pickup', 0.52, 'Rahim Mia', 'Bundle of cables'),
(1, 'facility_in', 0.175, 'Facility Staff', 'Verified at facility'),
(2, 'facility_in', 0.148, 'Facility Staff', 'Verified at facility');

-- Update actual weights for the completed pickup items
UPDATE items SET actual_weight_kg = 0.175 WHERE item_id = 1;
UPDATE items SET actual_weight_kg = 0.148 WHERE item_id = 2;
UPDATE items SET actual_weight_kg = 0.52 WHERE item_id = 3;

-- Summary queries
SELECT '========================================' AS info;
SELECT 'DATA SUMMARY' AS info;
SELECT '========================================' AS info;

SELECT 'Users' AS category, COUNT(*) AS count FROM users
UNION ALL
SELECT 'Recycling Facilities', COUNT(*) FROM recycling_facilities
UNION ALL
SELECT 'Vehicles', COUNT(*) FROM vehicles
UNION ALL
SELECT 'Staff Members', COUNT(*) FROM staff_assignments
UNION ALL
SELECT 'E-Waste Categories', COUNT(*) FROM categories
UNION ALL
SELECT 'Pricing Rules', COUNT(*) FROM pricing_rules
UNION ALL
SELECT 'Pickup Requests', COUNT(*) FROM pickup_requests
UNION ALL
SELECT 'Items', COUNT(*) FROM items
UNION ALL
SELECT 'Weight Records', COUNT(*) FROM weight_records
UNION ALL
SELECT 'Payments', COUNT(*) FROM payments
UNION ALL
SELECT 'Recycling Batches', COUNT(*) FROM recycling_batches;

-- Show pickup status distribution
SELECT '========================================' AS info;
SELECT 'PICKUP STATUS DISTRIBUTION' AS info;
SELECT '========================================' AS info;

SELECT 
    status,
    COUNT(*) AS count,
    SUM(total_weight_kg) AS total_weight_kg,
    SUM(total_amount) AS total_amount
FROM pickup_requests
GROUP BY status
ORDER BY status;

-- Show sample pickups with details
SELECT '========================================' AS info;
SELECT 'SAMPLE PICKUPS' AS info;
SELECT '========================================' AS info;

SELECT 
    p.pickup_id,
    u.full_name AS user,
    p.status,
    COUNT(i.item_id) AS items,
    p.total_weight_kg,
    p.total_amount
FROM pickup_requests p
JOIN users u ON p.user_id = u.user_id
LEFT JOIN items i ON p.pickup_id = i.pickup_id
GROUP BY p.pickup_id, u.full_name, p.status, p.total_weight_kg, p.total_amount
ORDER BY p.pickup_id;



-- Comments:
-- 1. All procedure calls now use correct parameter order (OUT parameters placed before DEFAULT parameters)
-- 2. Sample data creates diverse scenarios for testing
-- 3. Different pickup states: completed, assigned, pending
-- 4. High-hazard items trigger automatic alerts
-- 5. Complete workflow demonstrated: create -> add items -> assign -> collect -> pay
-- 6. Weight records show multi-stage weighing
-- 7. Summary queries help verify data insertion
-- 8. RAISE NOTICE statements provide clear progress feedback
