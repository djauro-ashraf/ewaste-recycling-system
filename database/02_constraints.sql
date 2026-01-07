-- =========================
-- 02_constraints.sql
-- Foreign Key Constraints
-- =========================

-- PICKUP REQUEST → USER
ALTER TABLE pickup_requests
ADD CONSTRAINT fk_pickup_user
FOREIGN KEY (user_id)
REFERENCES users(user_id)
ON DELETE CASCADE;

-- PICKUP REQUEST → STAFF
ALTER TABLE pickup_requests
ADD CONSTRAINT fk_pickup_staff
FOREIGN KEY (assigned_staff_id)
REFERENCES staff(staff_id)
ON DELETE SET NULL;

-- PICKUP REQUEST → VEHICLE
ALTER TABLE pickup_requests
ADD CONSTRAINT fk_pickup_vehicle
FOREIGN KEY (assigned_vehicle_id)
REFERENCES vehicles(vehicle_id)
ON DELETE SET NULL;

-- ITEM → PICKUP REQUEST
ALTER TABLE items
ADD CONSTRAINT fk_item_request
FOREIGN KEY (request_id)
REFERENCES pickup_requests(request_id)
ON DELETE CASCADE;

-- ITEM → CATEGORY
ALTER TABLE items
ADD CONSTRAINT fk_item_category
FOREIGN KEY (category_id)
REFERENCES categories(category_id)
ON DELETE RESTRICT;

-- WEIGHT RECORD → ITEM
ALTER TABLE weight_records
ADD CONSTRAINT fk_weight_item
FOREIGN KEY (item_id)
REFERENCES items(item_id)
ON DELETE CASCADE;

-- PAYMENT → PICKUP REQUEST
ALTER TABLE payments
ADD CONSTRAINT fk_payment_request
FOREIGN KEY (request_id)
REFERENCES pickup_requests(request_id)
ON DELETE CASCADE;

-- RECYCLING BATCH → FACILITY
ALTER TABLE recycling_batches
ADD CONSTRAINT fk_batch_facility
FOREIGN KEY (facility_id)
REFERENCES facilities(facility_id)
ON DELETE RESTRICT;

-- BATCH ITEMS → BATCH
ALTER TABLE batch_items
ADD CONSTRAINT fk_batch_items_batch
FOREIGN KEY (batch_id)
REFERENCES recycling_batches(batch_id)
ON DELETE CASCADE;

-- BATCH ITEMS → ITEM
ALTER TABLE batch_items
ADD CONSTRAINT fk_batch_items_item
FOREIGN KEY (item_id)
REFERENCES items(item_id)
ON DELETE CASCADE;
