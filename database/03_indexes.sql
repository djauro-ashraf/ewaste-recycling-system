-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 03_indexes.sql - Performance Optimization

-- Indexes on Foreign Keys (for JOIN operations)

CREATE INDEX idx_staff_vehicle ON staff_assignments(assigned_vehicle_id);
CREATE INDEX idx_pricing_category ON pricing_rules(category_id);
CREATE INDEX idx_pickup_user ON pickup_requests(user_id);
CREATE INDEX idx_pickup_staff ON pickup_requests(assigned_staff_id);
CREATE INDEX idx_pickup_vehicle ON pickup_requests(assigned_vehicle_id);
CREATE INDEX idx_pickup_facility ON pickup_requests(assigned_facility_id);
CREATE INDEX idx_item_pickup ON items(pickup_id);
CREATE INDEX idx_item_category ON items(category_id);
CREATE INDEX idx_weight_item ON weight_records(item_id);
CREATE INDEX idx_payment_pickup ON payments(pickup_id);
CREATE INDEX idx_batch_facility ON recycling_batches(facility_id);
CREATE INDEX idx_batchitem_batch ON batch_items(batch_id);
CREATE INDEX idx_batchitem_item ON batch_items(item_id);

-- Indexes on Status Fields (frequently filtered)

CREATE INDEX idx_pickup_status ON pickup_requests(status);
CREATE INDEX idx_payment_status ON payments(payment_status);
CREATE INDEX idx_batch_status ON recycling_batches(status);
CREATE INDEX idx_user_active ON users(is_active);
CREATE INDEX idx_vehicle_available ON vehicles(is_available);
CREATE INDEX idx_staff_available ON staff_assignments(is_available);
CREATE INDEX idx_facility_operational ON recycling_facilities(is_operational);

-- Indexes on Date/Time Fields (for reporting and filtering)

CREATE INDEX idx_pickup_request_date ON pickup_requests(request_date);
CREATE INDEX idx_pickup_preferred_date ON pickup_requests(preferred_date);
CREATE INDEX idx_pickup_completed_time ON pickup_requests(completed_time);
CREATE INDEX idx_payment_processed_at ON payments(processed_at);
CREATE INDEX idx_batch_created_date ON recycling_batches(created_date);
CREATE INDEX idx_weight_weighed_at ON weight_records(weighed_at);
CREATE INDEX idx_user_registered_at ON users(registered_at);

-- Composite Indexes (for common query patterns)

-- Find pending pickups for a specific date range
CREATE INDEX idx_pickup_status_date ON pickup_requests(status, preferred_date);

-- Find active pricing rules for a category
CREATE INDEX idx_pricing_active_category ON pricing_rules(is_active, category_id, effective_from);

-- Find completed payments for a date range
CREATE INDEX idx_payment_status_date ON payments(payment_status, processed_at);

-- Find items by category and pickup
CREATE INDEX idx_item_category_pickup ON items(category_id, pickup_id);

-- Find open batches by facility
CREATE INDEX idx_batch_facility_status ON recycling_batches(facility_id, status);

-- Audit log queries by table and date
CREATE INDEX idx_audit_table_date ON audit_log(table_name, changed_at);

-- Partial Indexes (for specific filtered queries)

-- Only index active users
CREATE INDEX idx_active_users ON users(user_id) WHERE is_active = TRUE;

-- Only index available vehicles
CREATE INDEX idx_available_vehicles ON vehicles(vehicle_id) WHERE is_available = TRUE;

-- Only index available staff
CREATE INDEX idx_available_staff ON staff_assignments(staff_id) WHERE is_available = TRUE;

-- Only index operational facilities
CREATE INDEX idx_operational_facilities ON recycling_facilities(facility_id) WHERE is_operational = TRUE;

-- Only index pending pickups (most frequently queried)
CREATE INDEX idx_pending_pickups ON pickup_requests(pickup_id, preferred_date) WHERE status = 'pending';

-- Only index open batches (most frequently accessed)
CREATE INDEX idx_open_batches ON recycling_batches(batch_id, facility_id) WHERE status = 'open';

-- Text Search Indexes (for searching descriptions)

-- Full-text search on item descriptions
CREATE INDEX idx_item_description_fts ON items USING gin(to_tsvector('english', item_description));

-- Full-text search on facility names
CREATE INDEX idx_facility_name_fts ON recycling_facilities USING gin(to_tsvector('english', facility_name));

-- JSONB Indexes (for querying JSON fields)

-- Index hazard_details for efficient JSON queries
CREATE INDEX idx_item_hazard_details ON items USING gin(hazard_details);

-- Index audit log JSON fields
CREATE INDEX idx_audit_old_values ON audit_log USING gin(old_values);
CREATE INDEX idx_audit_new_values ON audit_log USING gin(new_values);

-- Expression Indexes (for computed columns used in queries)

-- Index for searching by user email (case-insensitive)
CREATE INDEX idx_user_email_lower ON users(LOWER(email));

-- Index for year-month grouping in reports
CREATE INDEX idx_pickup_year_month ON pickup_requests(
    EXTRACT(YEAR FROM request_date), 
    EXTRACT(MONTH FROM request_date)
);

-- Index for batch processing duration calculations
CREATE INDEX idx_batch_duration ON recycling_batches(
    (processing_end_date - processing_start_date)
) WHERE processing_end_date IS NOT NULL;

-- Unique Indexes (for enforcing business rules)

-- Transaction reference must be unique when present
CREATE UNIQUE INDEX idx_unique_transaction_ref 
ON payments(transaction_reference) 
WHERE transaction_reference IS NOT NULL;

-- Batch name must be unique per facility
CREATE UNIQUE INDEX idx_unique_batch_name 
ON recycling_batches(facility_id, batch_name);

-- Comments explaining index strategy:
-- 1. Foreign key indexes: speed up JOIN operations
-- 2. Status indexes: enable fast filtering by status
-- 3. Date indexes: support reporting queries and date ranges
-- 4. Composite indexes: optimize multi-column WHERE clauses
-- 5. Partial indexes: reduce index size for common filtered queries
-- 6. GIN indexes: enable full-text search and JSONB queries
-- 7. Expression indexes: support computed column queries
-- 8. Indexes chosen based on expected query patterns in views/procedures