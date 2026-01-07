-- =========================
-- 09_transactions_demo.sql
-- Transaction Control Demo
-- =========================

-- DEMO 1: Successful Transaction (COMMIT)
BEGIN;

INSERT INTO pickup_requests (user_id, request_date, status)
VALUES (1, CURRENT_DATE, 'PENDING');

INSERT INTO items (request_id, category_id, item_name, hazardous_info)
VALUES (currval('pickup_requests_request_id_seq'), 1, 'Old Laptop', '{"battery": true, "lead": false}');

INSERT INTO weight_records (item_id, weight_kg)
VALUES (currval('items_item_id_seq'), 2.50);

COMMIT;

-- After COMMIT, all changes are permanent
-- ---------------------------------------


-- DEMO 2: Failed Transaction (ROLLBACK)
BEGIN;

INSERT INTO pickup_requests (user_id, request_date, status)
VALUES (2, CURRENT_DATE, 'PENDING');

-- This will fail if category_id 999 does not exist
INSERT INTO items (request_id, category_id, item_name)
VALUES (currval('pickup_requests_request_id_seq'), 999, 'Broken Monitor');

-- Error will occur, so we rollback
ROLLBACK;

-- No data from this transaction is saved
-- ---------------------------------------


-- DEMO 3: SAVEPOINT usage
BEGIN;

INSERT INTO pickup_requests (user_id, request_date, status)
VALUES (3, CURRENT_DATE, 'PENDING');

SAVEPOINT before_item_insert;

-- Correct insert
INSERT INTO items (request_id, category_id, item_name)
VALUES (currval('pickup_requests_request_id_seq'), 1, 'Printer');

-- Faulty insert (simulate mistake)
INSERT INTO items (request_id, category_id, item_name)
VALUES (currval('pickup_requests_request_id_seq'), 999, 'Invalid Item');

-- Roll back only to savepoint, not whole transaction
ROLLBACK TO SAVEPOINT before_item_insert;

-- Continue safely
INSERT INTO items (request_id, category_id, item_name)
VALUES (currval('pickup_requests_request_id_seq'), 2, 'Scanner');

COMMIT;

-- Only valid items are committed
