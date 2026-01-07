-- =========================
-- 03_indexes.sql
-- Performance Indexes
-- =========================

-- USERS
CREATE INDEX idx_users_email
ON users(email);

-- PICKUP REQUESTS
CREATE INDEX idx_pickup_requests_user
ON pickup_requests(user_id);

CREATE INDEX idx_pickup_requests_status
ON pickup_requests(status);

CREATE INDEX idx_pickup_requests_date
ON pickup_requests(request_date);

CREATE INDEX idx_pickup_requests_staff
ON pickup_requests(assigned_staff_id);

CREATE INDEX idx_pickup_requests_vehicle
ON pickup_requests(assigned_vehicle_id);

-- ITEMS
CREATE INDEX idx_items_request
ON items(request_id);

CREATE INDEX idx_items_category
ON items(category_id);

-- WEIGHT RECORDS
CREATE INDEX idx_weight_records_item
ON weight_records(item_id);

CREATE INDEX idx_weight_records_measured_at
ON weight_records(measured_at);

-- PAYMENTS
CREATE INDEX idx_payments_request
ON payments(request_id);

CREATE INDEX idx_payments_paid_at
ON payments(paid_at);

-- RECYCLING BATCHES
CREATE INDEX idx_recycling_batches_facility
ON recycling_batches(facility_id);

CREATE INDEX idx_recycling_batches_created_at
ON recycling_batches(created_at);

-- BATCH ITEMS
CREATE INDEX idx_batch_items_batch
ON batch_items(batch_id);

CREATE INDEX idx_batch_items_item
ON batch_items(item_id);

-- AUDIT LOGS
CREATE INDEX idx_audit_logs_entity
ON audit_logs(entity_name, entity_id);

CREATE INDEX idx_audit_logs_time
ON audit_logs(action_time);
