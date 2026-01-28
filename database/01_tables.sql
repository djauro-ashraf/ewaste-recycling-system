-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 01_tables.sql - Core Database Structure

-- Drop existing tables if any
DROP TABLE IF EXISTS audit_log CASCADE;
DROP TABLE IF EXISTS batch_items CASCADE;
DROP TABLE IF EXISTS recycling_batches CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS weight_records CASCADE;
DROP TABLE IF EXISTS items CASCADE;
DROP TABLE IF EXISTS pickup_requests CASCADE;
DROP TABLE IF EXISTS pricing_rules CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS staff_assignments CASCADE;
DROP TABLE IF EXISTS vehicles CASCADE;
DROP TABLE IF EXISTS recycling_facilities CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Users table (citizens who request pickups)
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20) NOT NULL,
    address TEXT NOT NULL,
    city VARCHAR(50) NOT NULL,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- Recycling Facilities
CREATE TABLE recycling_facilities (
    facility_id SERIAL PRIMARY KEY,
    facility_name VARCHAR(100) NOT NULL,
    location VARCHAR(100) NOT NULL,
    capacity_kg DECIMAL(10,2) NOT NULL,
    current_load_kg DECIMAL(10,2) DEFAULT 0,
    specialization VARCHAR(50), -- electronics, batteries, metals, etc.
    is_operational BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Vehicles for pickup
CREATE TABLE vehicles (
    vehicle_id SERIAL PRIMARY KEY,
    vehicle_number VARCHAR(20) UNIQUE NOT NULL,
    vehicle_type VARCHAR(30) NOT NULL, -- truck, van, etc.
    capacity_kg DECIMAL(8,2) NOT NULL,
    current_load_kg DECIMAL(8,2) DEFAULT 0,
    is_available BOOLEAN DEFAULT TRUE,
    last_maintenance DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Staff/Drivers
CREATE TABLE staff_assignments (
    staff_id SERIAL PRIMARY KEY,
    staff_name VARCHAR(100) NOT NULL,
    role VARCHAR(30) NOT NULL, -- driver, collector, supervisor
    contact_number VARCHAR(20) NOT NULL,
    assigned_vehicle_id INT,
    is_available BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- E-Waste Categories
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    base_price_per_kg DECIMAL(8,2) NOT NULL,
    hazard_level INT CHECK (hazard_level BETWEEN 1 AND 5), -- 1=safe, 5=very hazardous
    recyclability_percentage DECIMAL(5,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pricing Rules (dynamic pricing based on conditions)
CREATE TABLE pricing_rules (
    rule_id SERIAL PRIMARY KEY,
    category_id INT NOT NULL,
    min_weight_kg DECIMAL(8,2) NOT NULL,
    max_weight_kg DECIMAL(8,2),
    price_per_kg DECIMAL(8,2) NOT NULL,
    bonus_percentage DECIMAL(5,2) DEFAULT 0,
    effective_from DATE NOT NULL,
    effective_to DATE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pickup Requests
CREATE TABLE pickup_requests (
    pickup_id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    request_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    preferred_date DATE NOT NULL,
    pickup_address TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending', -- pending, assigned, collected, completed, cancelled
    assigned_staff_id INT,
    assigned_vehicle_id INT,
    assigned_facility_id INT,
    scheduled_time TIMESTAMP,
    completed_time TIMESTAMP,
    total_weight_kg DECIMAL(10,2) DEFAULT 0,
    total_amount DECIMAL(10,2) DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Items in each pickup
CREATE TABLE items (
    item_id SERIAL PRIMARY KEY,
    pickup_id INT NOT NULL,
    category_id INT NOT NULL,
    item_description TEXT NOT NULL,
    condition VARCHAR(20), -- working, broken, repairable
    estimated_weight_kg DECIMAL(8,2),
    actual_weight_kg DECIMAL(8,2),
    hazard_details JSONB, -- store hazardous component details
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Weight Records (track weighing at different stages)
CREATE TABLE weight_records (
    weight_id SERIAL PRIMARY KEY,
    item_id INT NOT NULL,
    weighing_stage VARCHAR(30) NOT NULL, -- pickup, facility_in, facility_out
    weight_kg DECIMAL(8,2) NOT NULL,
    weighed_by VARCHAR(100),
    weighed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

-- Payments
CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    pickup_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_method VARCHAR(30) NOT NULL, -- bank_transfer, mobile_money, cash
    payment_status VARCHAR(20) DEFAULT 'pending', -- pending, completed, failed
    transaction_reference VARCHAR(100) UNIQUE,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

-- Recycling Batches (grouping items for processing)
CREATE TABLE recycling_batches (
    batch_id SERIAL PRIMARY KEY,
    facility_id INT NOT NULL,
    batch_name VARCHAR(100) NOT NULL,
    created_date DATE DEFAULT CURRENT_DATE,
    processing_start_date DATE,
    processing_end_date DATE,
    status VARCHAR(20) DEFAULT 'open', -- open, processing, completed
    total_weight_kg DECIMAL(10,2) DEFAULT 0,
    recovery_rate_percentage DECIMAL(5,2),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Batch Items (items assigned to batches)
CREATE TABLE batch_items (
    batch_item_id SERIAL PRIMARY KEY,
    batch_id INT NOT NULL,
    item_id INT NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processing_notes TEXT
);

-- Audit Log (track all important operations)
CREATE TABLE audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    operation VARCHAR(30) NOT NULL, -- INSERT, UPDATE, DELETE
    record_id INT NOT NULL,
    old_values JSONB,
    new_values JSONB,
    changed_by VARCHAR(100),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Comments explaining design decisions:
-- 1. SERIAL for all primary keys (auto-incrementing)
-- 2. JSONB for flexible hazard_details (can store different attributes per category)
-- 3. Separate weight_records table to track weight at multiple stages
-- 4. pricing_rules table allows dynamic pricing without code changes
-- 5. audit_log with JSONB to store complete state changes
-- 6. Status fields as VARCHAR for flexibility (can add new statuses)
-- 7. Timestamps on all important tables for tracking
-- 8. Boolean flags for availability/active status