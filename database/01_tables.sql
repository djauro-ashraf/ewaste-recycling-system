-- =========================
-- 01_create_tables.sql
-- E-Waste Management System
-- =========================

-- USERS
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- STAFF
CREATE TABLE staff (
    staff_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(50),
    phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- VEHICLES
CREATE TABLE vehicles (
    vehicle_id SERIAL PRIMARY KEY,
    plate_number VARCHAR(20) UNIQUE NOT NULL,
    vehicle_type VARCHAR(50),
    capacity_kg NUMERIC(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- FACILITIES
CREATE TABLE facilities (
    facility_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    location TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- PICKUP REQUESTS
CREATE TABLE pickup_requests (
    request_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    request_date DATE NOT NULL,
    status VARCHAR(30) NOT NULL,
    assigned_staff_id INTEGER,
    assigned_vehicle_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- CATEGORIES
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(50) NOT NULL,
    description TEXT
);

-- ITEMS
CREATE TABLE items (
    item_id SERIAL PRIMARY KEY,
    request_id INTEGER NOT NULL,
    category_id INTEGER NOT NULL,
    item_name VARCHAR(100),
    hazardous_info JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- WEIGHT RECORDS
CREATE TABLE weight_records (
    weight_id SERIAL PRIMARY KEY,
    item_id INTEGER NOT NULL,
    weight_kg NUMERIC(10,2) NOT NULL,
    measured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- PAYMENTS
CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    request_id INTEGER NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    payment_method VARCHAR(30),
    payment_status VARCHAR(30),
    paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- RECYCLING BATCHES
CREATE TABLE recycling_batches (
    batch_id SERIAL PRIMARY KEY,
    facility_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- BATCH ITEMS (JUNCTION TABLE)
CREATE TABLE batch_items (
    batch_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    PRIMARY KEY (batch_id, item_id)
);

-- AUDIT LOGS
CREATE TABLE audit_logs (
    audit_id SERIAL PRIMARY KEY,
    entity_name VARCHAR(50),
    entity_id INTEGER,
    action VARCHAR(20),
    action_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    performed_by VARCHAR(100)
);
