-- ============================================================
-- 08_sample_data.sql — Demo Data
-- All passwords: password123
-- Hashes generated with werkzeug pbkdf2:sha256
-- ============================================================

-- ── Facilities ────────────────────────────────────────────
INSERT INTO recycling_facilities (facility_name, location, capacity_kg, specialization) VALUES
('GreenTech Dhaka',    'Mirpur, Dhaka',        50000, 'electronics'),
('EcoRecycle Ctg',     'Agrabad, Chittagong',  30000, 'batteries'),
('MetalHub Gazipur',   'Gazipur Industrial',   80000, 'metals'),
('SafeDispose Sylhet', 'Sylhet City',          20000, 'hazardous');

-- ── Categories ────────────────────────────────────────────
INSERT INTO categories (category_name, description, base_price_per_kg, hazard_level, recyclability_percentage, material_composition) VALUES
('Laptops',      'Portable computers',          38, 2, 72.0, '{"copper_pct":8,"aluminum_pct":35,"plastics_pct":25,"gold_ppm":150}'),
('Smartphones',  'Mobile phones & tablets',     45, 2, 68.0, '{"copper_pct":15,"gold_ppm":350,"silver_ppm":1500,"cobalt_pct":5}'),
('Batteries',    'All battery types',           55, 4, 45.0, '{"lithium_pct":7,"cobalt_pct":12,"nickel_pct":15}'),
('CRT Monitors', 'Old tube monitors/TVs',       15, 5, 30.0, '{"lead_pct":4,"glass_pct":65,"copper_pct":3}'),
('Printers',     'Inkjet and laser printers',   22, 2, 55.0, '{"plastics_pct":60,"copper_pct":5,"steel_pct":20}'),
('Cables & PCB', 'Wiring and circuit boards',   60, 3, 80.0, '{"copper_pct":25,"gold_ppm":500,"tin_pct":5}'),
('Refrigerators','Fridges and ACs',             18, 3, 65.0, '{"steel_pct":55,"copper_pct":8,"aluminum_pct":10}'),
('Zero-Value',   'Items with no recyclable value', 0, 1, 5.0, '{}');

-- ── Pricing Rules ─────────────────────────────────────────
INSERT INTO pricing_rules (category_id, min_weight_kg, max_weight_kg, price_per_kg, bonus_percentage, effective_from) VALUES
(1, 5.0,  NULL, 42, 5,  '2025-01-01'),  -- Laptop bulk bonus
(2, 0.5,  NULL, 50, 10, '2025-01-01'),  -- Smartphone bonus
(3, 10.0, NULL, 65, 15, '2025-01-01'),  -- Battery bulk
(6, 1.0,  NULL, 70, 0,  '2025-01-01');  -- PCB standard

-- ── Staff: 2 supervisors ──────────────────────────────────
INSERT INTO staff (full_name, sub_role, contact_number) VALUES
('Rahman Hossain', 'supervisor', '01711-000001'),  -- staff_id=1
('Fatema Khatun',  'supervisor', '01711-000002');  -- staff_id=2

-- ── Staff: drivers under supervisors ─────────────────────
INSERT INTO staff (full_name, sub_role, contact_number, supervisor_id) VALUES
('Karim Uddin',    'driver',    '01711-000003', 1),  -- id=3
('Jamal Ahmed',    'driver',    '01711-000004', 1),  -- id=4
('Noor Islam',     'driver',    '01711-000005', 2),  -- id=5
('Habib Rahman',   'driver',    '01711-000006', 2);  -- id=6

-- ── Staff: collectors under supervisors ──────────────────
INSERT INTO staff (full_name, sub_role, contact_number, supervisor_id) VALUES
('Sadia Begum',    'collector', '01711-000007', 1),  -- id=7
('Mita Akter',     'collector', '01711-000008', 1),  -- id=8
('Sumon Mia',      'collector', '01711-000009', 2),  -- id=9
('Ritu Das',       'collector', '01711-000010', 2);  -- id=10

-- ── Vehicles (under supervisors) ─────────────────────────
INSERT INTO vehicles (vehicle_number, vehicle_type, capacity_kg, supervisor_id) VALUES
('DHK-TRK-001', 'truck', 2000, 1),
('DHK-VAN-002', 'van',    800, 1),
('CTG-TRK-001', 'truck', 2000, 2),
('CTG-VAN-002', 'van',    800, 2);

-- All demo passwords: password123
-- Hash generated: scrypt:32768:8:1 (werkzeug default)
DO $$
DECLARE h TEXT := 'scrypt:32768:8:1$g6Zc4hZJzr6rx2g2$76fbc10a1d6d29b52ffa3cc550f98b5b7d8ab256a7abee7f46026710bbe7d8dc9566a75b522a467c6433900ed3d975d07bc1373859e09bc35e29852e3594150e';
BEGIN

INSERT INTO accounts (username, password_hash, role, display_name) VALUES ('admin', h, 'admin', 'System Admin');

INSERT INTO accounts (username, password_hash, role, staff_id, display_name) VALUES
('rahman', h, 'staff', 1, 'Rahman Hossain'),
('fatema', h, 'staff', 2, 'Fatema Khatun'),
('karim',  h, 'staff', 3, 'Karim Uddin'),
('jamal',  h, 'staff', 4, 'Jamal Ahmed'),
('noor',   h, 'staff', 5, 'Noor Islam'),
('sadia',  h, 'staff', 7, 'Sadia Begum'),
('sumon',  h, 'staff', 9, 'Sumon Mia');

INSERT INTO users (full_name, email, phone, address, city) VALUES
('Alice Rahman', 'alice@mail.com', '01800-100001', '45 Dhanmondi, Dhaka',   'Dhaka'),
('Bob Hasan',    'bob@mail.com',   '01800-100002', '12 GEC Circle, Ctg',    'Chittagong'),
('Clara Ahmed',  'clara@mail.com', '01800-100003', '7 Shahjalal Road, Syl', 'Sylhet'),
('Daud Mia',     'daud@mail.com',  '01800-100004', '3 Basabo, Dhaka',       'Dhaka');

INSERT INTO accounts (username, password_hash, role, user_id, display_name) VALUES
('alice', h, 'user', 1, 'Alice Rahman'),
('bob',   h, 'user', 2, 'Bob Hasan'),
('clara', h, 'user', 3, 'Clara Ahmed'),
('daud',  h, 'user', 4, 'Daud Mia');

END $$;

-- NOTE: The sample password hashes above are placeholders.
-- When you run the app for the first time, register fresh accounts
-- via the web form, or run this Python snippet to generate correct hashes:
--
-- from werkzeug.security import generate_password_hash
-- print(generate_password_hash('password123'))
-- Then UPDATE accounts SET password_hash = '<output>' WHERE username = 'admin';
