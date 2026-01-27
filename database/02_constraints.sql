-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 02_constraints.sql - Referential Integrity & Business Rules

-- Foreign Key Constraints (Define Relationships)

-- Staff Assignment references Vehicle
ALTER TABLE staff_assignments
    ADD CONSTRAINT fk_staff_vehicle
    FOREIGN KEY (assigned_vehicle_id) 
    REFERENCES vehicles(vehicle_id)
    ON DELETE SET NULL
    ON UPDATE CASCADE;

-- Pricing Rules reference Categories
ALTER TABLE pricing_rules
    ADD CONSTRAINT fk_pricing_category
    FOREIGN KEY (category_id)
    REFERENCES categories(category_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;

-- Pickup Requests references
ALTER TABLE pickup_requests
    ADD CONSTRAINT fk_pickup_user
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,
    
    ADD CONSTRAINT fk_pickup_staff
    FOREIGN KEY (assigned_staff_id)
    REFERENCES staff_assignments(staff_id)
    ON DELETE SET NULL
    ON UPDATE CASCADE,
    
    ADD CONSTRAINT fk_pickup_vehicle
    FOREIGN KEY (assigned_vehicle_id)
    REFERENCES vehicles(vehicle_id)
    ON DELETE SET NULL
    ON UPDATE CASCADE,
    
    ADD CONSTRAINT fk_pickup_facility
    FOREIGN KEY (assigned_facility_id)
    REFERENCES recycling_facilities(facility_id)
    ON DELETE SET NULL
    ON UPDATE CASCADE;

-- Items references
ALTER TABLE items
    ADD CONSTRAINT fk_item_pickup
    FOREIGN KEY (pickup_id)
    REFERENCES pickup_requests(pickup_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
    
    ADD CONSTRAINT fk_item_category
    FOREIGN KEY (category_id)
    REFERENCES categories(category_id)
    ON DELETE RESTRICT
    ON UPDATE CASCADE;

-- Weight Records reference Items
ALTER TABLE weight_records
    ADD CONSTRAINT fk_weight_item
    FOREIGN KEY (item_id)
    REFERENCES items(item_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;

-- Payments reference Pickup Requests
ALTER TABLE payments
    ADD CONSTRAINT fk_payment_pickup
    FOREIGN KEY (pickup_id)
    REFERENCES pickup_requests(pickup_id)
    ON DELETE RESTRICT
    ON UPDATE CASCADE;

-- Recycling Batches reference Facilities
ALTER TABLE recycling_batches
    ADD CONSTRAINT fk_batch_facility
    FOREIGN KEY (facility_id)
    REFERENCES recycling_facilities(facility_id)
    ON DELETE RESTRICT
    ON UPDATE CASCADE;

-- Batch Items references
ALTER TABLE batch_items
    ADD CONSTRAINT fk_batchitem_batch
    FOREIGN KEY (batch_id)
    REFERENCES recycling_batches(batch_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
    
    ADD CONSTRAINT fk_batchitem_item
    FOREIGN KEY (item_id)
    REFERENCES items(item_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;

-- CHECK Constraints (Business Rules)

-- Users
ALTER TABLE users
    ADD CONSTRAINT chk_user_email_format
    CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- Vehicles
ALTER TABLE vehicles
    ADD CONSTRAINT chk_vehicle_capacity_positive
    CHECK (capacity_kg > 0),
    
    ADD CONSTRAINT chk_vehicle_load_valid
    CHECK (current_load_kg >= 0 AND current_load_kg <= capacity_kg);

-- Recycling Facilities
ALTER TABLE recycling_facilities
    ADD CONSTRAINT chk_facility_capacity_positive
    CHECK (capacity_kg > 0),
    
    ADD CONSTRAINT chk_facility_load_valid
    CHECK (current_load_kg >= 0 AND current_load_kg <= capacity_kg);

-- Categories
ALTER TABLE categories
    ADD CONSTRAINT chk_category_price_positive
    CHECK (base_price_per_kg > 0),
    
    ADD CONSTRAINT chk_recyclability_percentage
    CHECK (recyclability_percentage >= 0 AND recyclability_percentage <= 100);

-- Pricing Rules
ALTER TABLE pricing_rules
    ADD CONSTRAINT chk_pricing_weight_range
    CHECK (min_weight_kg >= 0 AND (max_weight_kg IS NULL OR max_weight_kg > min_weight_kg)),
    
    ADD CONSTRAINT chk_pricing_price_positive
    CHECK (price_per_kg > 0),
    
    ADD CONSTRAINT chk_pricing_bonus_valid
    CHECK (bonus_percentage >= 0 AND bonus_percentage <= 100),
    
    ADD CONSTRAINT chk_pricing_dates
    CHECK (effective_to IS NULL OR effective_to >= effective_from);

-- Pickup Requests
ALTER TABLE pickup_requests
    ADD CONSTRAINT chk_pickup_status
    CHECK (status IN ('pending', 'assigned', 'collected', 'completed', 'cancelled')),
    
    ADD CONSTRAINT chk_pickup_weight_positive
    CHECK (total_weight_kg >= 0),
    
    ADD CONSTRAINT chk_pickup_amount_positive
    CHECK (total_amount >= 0),
    
    ADD CONSTRAINT chk_pickup_dates
    CHECK (completed_time IS NULL OR completed_time >= request_date);

-- Items
ALTER TABLE items
    ADD CONSTRAINT chk_item_condition
    CHECK (condition IN ('working', 'broken', 'repairable')),
    
    ADD CONSTRAINT chk_item_weights_positive
    CHECK (
        (estimated_weight_kg IS NULL OR estimated_weight_kg > 0) AND
        (actual_weight_kg IS NULL OR actual_weight_kg > 0)
    );

-- Weight Records
ALTER TABLE weight_records
    ADD CONSTRAINT chk_weight_stage
    CHECK (weighing_stage IN ('pickup', 'facility_in', 'facility_out')),
    
    ADD CONSTRAINT chk_weight_positive
    CHECK (weight_kg > 0);

-- Payments
ALTER TABLE payments
    ADD CONSTRAINT chk_payment_amount_positive
    CHECK (amount > 0),
    
    ADD CONSTRAINT chk_payment_method
    CHECK (payment_method IN ('bank_transfer', 'mobile_money', 'cash', 'check')),
    
    ADD CONSTRAINT chk_payment_status
    CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded'));

-- Recycling Batches
ALTER TABLE recycling_batches
    ADD CONSTRAINT chk_batch_status
    CHECK (status IN ('open', 'processing', 'completed', 'closed')),
    
    ADD CONSTRAINT chk_batch_weight_positive
    CHECK (total_weight_kg >= 0),
    
    ADD CONSTRAINT chk_batch_recovery_rate
    CHECK (recovery_rate_percentage IS NULL OR 
           (recovery_rate_percentage >= 0 AND recovery_rate_percentage <= 100)),
    
    ADD CONSTRAINT chk_batch_dates
    CHECK (
        (processing_start_date IS NULL OR processing_start_date >= created_date) AND
        (processing_end_date IS NULL OR processing_end_date >= processing_start_date)
    );

-- Audit Log
ALTER TABLE audit_log
    ADD CONSTRAINT chk_audit_operation
    CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE'));

-- UNIQUE Constraints (Beyond Primary Keys)

-- Ensure each item is only in one batch
ALTER TABLE batch_items
    ADD CONSTRAINT unique_item_per_batch
    UNIQUE (item_id);

-- Ensure pricing rules don't overlap for same category/weight/date
CREATE UNIQUE INDEX idx_unique_active_pricing 
ON pricing_rules(category_id, min_weight_kg, effective_from) 
WHERE is_active = TRUE;

-- Comments explaining constraint decisions:
-- 1. ON DELETE RESTRICT: prevents deletion of referenced records (users, categories)
-- 2. ON DELETE CASCADE: automatically deletes dependent records (items when pickup deleted)
-- 3. ON DELETE SET NULL: preserves record but removes reference (staff assignment)
-- 4. CHECK constraints enforce business rules at database level
-- 5. Status fields restricted to valid values only
-- 6. Weight/amount/percentage fields validated for logical ranges
-- 7. Date constraints ensure chronological consistency