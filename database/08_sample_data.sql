-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 08_sample_data.sql - Demonstration Dataset

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
(1, 0, 5, 45.00, 0, '2025-01-01'),
(1, 5, 20, 50.00, 10, '2025-01-01'),
(1, 20, NULL, 55.00, 20, '2025-01-01'),
(2, 0, 10, 60.00, 0, '2025-01-01'),
(2, 10, NULL, 65.00, 15, '2025-01-01'),
(4, 0, NULL, 25.00, 0, '2025-01-01'),
(3, 0, 15, 35.00, 0, '2025-01-01'),
(3, 15, NULL, 40.00, 10, '2025-01-01');

-- Create some pickup requests and items
DO $$
DECLARE
    v_pickup_id INT;
    v_item_id INT;
    v_payment_id INT;
    v_payment_amount DECIMAL;
    v_batch_id INT;
BEGIN
    -- Pickup 1
    CALL create_pickup_request(
    v_pickup_id,
    1,
    CURRENT_DATE + 2,
    'House 12, Road 5, Dhanmondi, Dhaka',
    'Old smartphones and chargers'
);


   CALL add_item_to_pickup(
    v_item_id,
    v_pickup_id,
    1,
    'Samsung Galaxy S10 (broken screen)',
    'broken',
    0.18,
    '{"screen_condition":"cracked","battery_health":"poor"}'
);


    CALL add_item_to_pickup(
        v_pickup_id, 1,
        'iPhone 7 (water damaged)',
        'broken', 0.15,
        '{"water_damage":true}',
        v_item_id
    );

    CALL add_item_to_pickup(
        v_pickup_id, 7,
        'Old charging cables and adapters',
        'working', 0.5,
        NULL,
        v_item_id
    );

    CALL assign_pickup_to_staff(v_pickup_id, 1, 1, 1, CURRENT_TIMESTAMP + INTERVAL '2 days');
    CALL complete_pickup_collection(v_pickup_id);
    CALL process_payment(
    v_payment_id,
    v_payment_amount,
    v_pickup_id,
    'bank_transfer',
    'TXN-2025-001'
);


    -- Pickup 2
    CALL create_pickup_request(
        2,
        CURRENT_DATE + 3,
        'Flat 3B, Gulshan Avenue, Dhaka',
        'Old laptop for recycling',
        v_pickup_id
    );

    CALL add_item_to_pickup(
        v_pickup_id, 2,
        'Dell Inspiron 15 (2015 model, working)',
        'working', 2.3,
        NULL,
        v_item_id
    );

    CALL add_item_to_pickup(
        v_pickup_id, 2,
        'HP Laptop charger',
        'working', 0.4,
        NULL,
        v_item_id
    );

    -- Pickup 3
    CALL create_pickup_request(
        3,
        CURRENT_DATE + 1,
        'Block C, Bashundhara R/A, Dhaka',
        'Complete desktop setup',
        v_pickup_id
    );

    CALL add_item_to_pickup(v_pickup_id, 3, 'Dell Desktop PC Tower', 'working', 8.5, NULL, v_item_id);
    CALL add_item_to_pickup(v_pickup_id, 3, 'Samsung 22" LCD Monitor', 'working', 4.2, NULL, v_item_id);
    CALL add_item_to_pickup(v_pickup_id, 3, 'Keyboard and Mouse', 'working', 0.8, NULL, v_item_id);

    CALL assign_pickup_to_staff(v_pickup_id, 2, 2, 1, CURRENT_TIMESTAMP + INTERVAL '1 day');

    -- Pickup 4
    CALL create_pickup_request(
        4,
        CURRENT_DATE + 4,
        'House 45, Banani, Dhaka',
        'Old TV and kitchen appliances',
        v_pickup_id
    );

    CALL add_item_to_pickup(v_pickup_id, 5, 'Sony 32" LCD TV (not working)', 'broken', 12.5, NULL, v_item_id);
    CALL add_item_to_pickup(v_pickup_id, 6, 'Old microwave oven', 'working', 8.0, NULL, v_item_id);

    -- Pickup 5
    CALL create_pickup_request(
        5,
        CURRENT_DATE + 5,
        'Sector 11, Uttara, Dhaka',
        'Old batteries collection',
        v_pickup_id
    );

    CALL add_item_to_pickup(
        v_pickup_id, 4,
        'Car battery (lead-acid)',
        'broken', 15.0,
        '{"type":"lead-acid","voltage":"12V","leaking":false}',
        v_item_id
    );

    CALL add_item_to_pickup(
        v_pickup_id, 4,
        'UPS batteries (2 units)',
        'broken', 12.0,
        '{"type":"sealed-lead-acid","count":2}',
        v_item_id
    );

    -- Create batch
    CALL create_recycling_batch(
    v_batch_id,
    1,
    'Electronics Batch Jan 2025',
    'First batch of the month - electronics focus'
);


    RAISE NOTICE 'Sample data inserted successfully';
    RAISE NOTICE 'Created % pickups', 5;
    RAISE NOTICE 'Created batch %', v_batch_id;
END $$;

-- Weight records
INSERT INTO weight_records (item_id, weighing_stage, weight_kg, weighed_by, notes) VALUES
(1, 'pickup', 0.175, 'Rahim Mia', 'Weighed at user location'),
(2, 'pickup', 0.148, 'Rahim Mia', 'Weighed at user location'),
(3, 'pickup', 0.52, 'Rahim Mia', 'Bundle of cables'),
(1, 'facility_in', 0.175, 'Facility Staff', 'Verified at facility'),
(2, 'facility_in', 0.148, 'Facility Staff', 'Verified at facility');

-- Update actual weights
UPDATE items SET actual_weight_kg = 0.175 WHERE item_id = 1;
UPDATE items SET actual_weight_kg = 0.148 WHERE item_id = 2;
UPDATE items SET actual_weight_kg = 0.52 WHERE item_id = 3;

-- Summary
SELECT 'Data Summary' AS info;
SELECT COUNT(*) AS total_users FROM users;
SELECT COUNT(*) AS total_facilities FROM recycling_facilities;
SELECT COUNT(*) AS total_vehicles FROM vehicles;
SELECT COUNT(*) AS total_staff FROM staff_assignments;
SELECT COUNT(*) AS total_categories FROM categories;
SELECT COUNT(*) AS total_pricing_rules FROM pricing_rules;
SELECT COUNT(*) AS total_pickups FROM pickup_requests;
SELECT COUNT(*) AS total_items FROM items;
SELECT COUNT(*) AS total_payments FROM payments;
SELECT COUNT(*) AS total_batches FROM recycling_batches;

-- Comments:
-- 1. Sample data includes realistic scenarios
-- 2. Different item types and conditions
-- 3. Complete workflows: request -> assign -> collect -> pay
-- 4. Some pickups in different states for testing
-- 5. JSONB hazard_details show flexibility
-- 6. Weight records at multiple stages
-- 7. High-hazard items trigger alerts
-- 8. Data suitable for screenshots and demos
