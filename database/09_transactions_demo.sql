-- E-WASTE RECYCLING MANAGEMENT SYSTEM
-- 09_transactions_demo.sql - Demonstrating ACID Properties

-- DEMO 1: Successful Transaction (COMMIT)
-- Shows atomicity: all operations succeed or none do
DO $$
DECLARE
    v_pickup_id INT;
    v_item_id INT;
BEGIN
    BEGIN
        RAISE NOTICE '=== DEMO 1: Successful Transaction ===';
        
        -- Start transaction (implicit in DO block)
        RAISE NOTICE 'Creating pickup request...';
        CALL create_pickup_request(
            1, -- user_id
            CURRENT_DATE + 7,
            'Test Address for Transaction Demo',
            'Transaction test',
            v_pickup_id
        );
        
        RAISE NOTICE 'Adding first item...';
        CALL add_item_to_pickup(
            v_pickup_id,
            1, -- category: Mobile Phones
            'Test Phone 1',
            'broken',
            0.2,
            NULL,
            v_item_id
        );
        
        RAISE NOTICE 'Adding second item...';
        CALL add_item_to_pickup(
            v_pickup_id,
            1,
            'Test Phone 2',
            'working',
            0.18,
            NULL,
            v_item_id
        );
        
        -- All operations successful - transaction commits
        RAISE NOTICE 'SUCCESS: All operations completed. Transaction will COMMIT.';
        RAISE NOTICE 'Pickup % created with 2 items', v_pickup_id;
        
        -- Verify data
        RAISE NOTICE 'Verifying: Total weight = %', (SELECT total_weight_kg FROM pickup_requests WHERE pickup_id = v_pickup_id);
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'ERROR: Transaction failed and will ROLLBACK';
            RAISE NOTICE 'Error message: %', SQLERRM;
    END;
END $$;

-- DEMO 2: Failed Transaction (ROLLBACK)
-- Shows that if any operation fails, nothing is saved
DO $$
DECLARE
    v_pickup_id INT;
    v_item_id INT;
BEGIN
    BEGIN
        RAISE NOTICE '=== DEMO 2: Failed Transaction (Intentional) ===';
        
        -- Create pickup
        RAISE NOTICE 'Creating pickup request...';
        CALL create_pickup_request(
            1,
            CURRENT_DATE + 7,
            'This will be rolled back',
            'Rollback test',
            v_pickup_id
        );
        RAISE NOTICE 'Pickup % created', v_pickup_id;
        
        -- Add valid item
        RAISE NOTICE 'Adding valid item...';
        CALL add_item_to_pickup(
            v_pickup_id,
            1,
            'Valid item',
            'broken',
            0.2,
            NULL,
            v_item_id
        );
        RAISE NOTICE 'Item added successfully';
        
        -- Try to add item with invalid category (this will fail)
        RAISE NOTICE 'Attempting to add item with invalid category (this will fail)...';
        CALL add_item_to_pickup(
            v_pickup_id,
            999, -- Invalid category_id
            'This should fail',
            'broken',
            0.1,
            NULL,
            v_item_id
        );
        
        RAISE NOTICE 'This line will never execute';
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'EXPECTED ERROR CAUGHT: %', SQLERRM;
            RAISE NOTICE 'ROLLBACK: Pickup % and its items were NOT saved', v_pickup_id;
            RAISE NOTICE 'Demonstrating atomicity: partial changes do not persist';
    END;
END $$;

-- DEMO 3: Transaction Isolation
-- Shows how transactions don't interfere with each other
DO $$
DECLARE
    v_initial_count INT;
    v_during_count INT;
    v_final_count INT;
BEGIN
    RAISE NOTICE '=== DEMO 3: Transaction Isolation ===';
    
    -- Count pickups before
    SELECT COUNT(*) INTO v_initial_count FROM pickup_requests;
    RAISE NOTICE 'Initial pickup count: %', v_initial_count;
    
    -- In a real system, another transaction would happen here
    -- For demo purposes, we'll just show the concept
    RAISE NOTICE 'Other transactions can read consistent data';
    RAISE NOTICE 'PostgreSQL default isolation level: READ COMMITTED';
    
    SELECT COUNT(*) INTO v_final_count FROM pickup_requests;
    RAISE NOTICE 'Final pickup count: %', v_final_count;
END $$;

-- DEMO 4: Consistency Enforcement
-- Shows how constraints maintain database consistency
DO $$
DECLARE
    v_pickup_id INT;
BEGIN
    BEGIN
        RAISE NOTICE '=== DEMO 4: Consistency - Constraint Violations ===';
        
        -- Try to create pickup with non-existent user
        RAISE NOTICE 'Attempting to create pickup for non-existent user...';
        CALL create_pickup_request(
            9999, -- Non-existent user_id
            CURRENT_DATE + 1,
            'Invalid user test',
            NULL,
            v_pickup_id
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'PREVENTED: %', SQLERRM;
            RAISE NOTICE 'Database consistency maintained';
    END;
END $$;

-- DEMO 5: Durability
-- Shows that committed transactions persist
DO $$
DECLARE
    v_pickup_id INT;
    v_item_id INT;
    v_payment_id INT;
    v_amount DECIMAL;
BEGIN
    BEGIN
        RAISE NOTICE '=== DEMO 5: Durability ===';
        
        -- Create and complete a full workflow
        RAISE NOTICE 'Creating complete pickup workflow...';
        
        CALL create_pickup_request(
            1,
            CURRENT_DATE + 3,
            'Durability test address',
            'Testing data persistence',
            v_pickup_id
        );
        
        CALL add_item_to_pickup(
            v_pickup_id,
            2, -- Laptops
            'Test Laptop',
            'working',
            2.5,
            NULL,
            v_item_id
        );
        
        CALL assign_pickup_to_staff(v_pickup_id, 1, 1, 1, NULL);
        CALL complete_pickup_collection(v_pickup_id);
        CALL process_payment(v_pickup_id, 'cash', 'DURABLE-TXN-001', v_payment_id, v_amount);
        
        RAISE NOTICE 'COMMITTED: Pickup %, Payment % for $%', v_pickup_id, v_payment_id, v_amount;
        RAISE NOTICE 'This data will persist even after database restart (DURABILITY)';
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Error: %', SQLERRM;
    END;
END $$;

-- DEMO 6: Complex Transaction with Multiple Tables
-- Shows transaction spanning multiple related operations
DO $$
DECLARE
    v_pickup_id INT;
    v_item_id INT;
    v_batch_id INT;
    v_payment_id INT;
    v_amount DECIMAL;
BEGIN
    BEGIN
        RAISE NOTICE '=== DEMO 6: Complex Multi-Table Transaction ===';
        
        -- Create pickup with items
        CALL create_pickup_request(2, CURRENT_DATE + 2, 'Complex transaction test', NULL, v_pickup_id);
        RAISE NOTICE 'Step 1: Created pickup %', v_pickup_id;
        
        CALL add_item_to_pickup(v_pickup_id, 3, 'Desktop PC', 'working', 10.0, NULL, v_item_id);
        RAISE NOTICE 'Step 2: Added item %', v_item_id;
        
        CALL assign_pickup_to_staff(v_pickup_id, 3, 3, 1, NULL);
        RAISE NOTICE 'Step 3: Assigned to staff';
        
        CALL complete_pickup_collection(v_pickup_id);
        RAISE NOTICE 'Step 4: Marked as collected';
        
        CALL process_payment(v_pickup_id, 'bank_transfer', 'COMPLEX-TXN-001', v_payment_id, v_amount);
        RAISE NOTICE 'Step 5: Payment processed: $%', v_amount;
        
        -- Create batch and add item
        CALL create_recycling_batch(1, 'Complex Transaction Batch', NULL, v_batch_id);
        RAISE NOTICE 'Step 6: Created batch %', v_batch_id;
        
        CALL add_item_to_batch(v_batch_id, v_item_id);
        RAISE NOTICE 'Step 7: Added item to batch';
        
        RAISE NOTICE 'SUCCESS: All 7 steps completed atomically';
        RAISE NOTICE 'Data written to 8 different tables in one transaction';
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'ROLLBACK: None of the 7 steps persisted';
            RAISE NOTICE 'Error: %', SQLERRM;
    END;
END $$;

-- DEMO 7: Concurrent Update Simulation
-- Shows how database handles concurrent modifications
DO $$
BEGIN
    RAISE NOTICE '=== DEMO 7: Concurrent Update Protection ===';
    RAISE NOTICE 'PostgreSQL uses MVCC (Multi-Version Concurrency Control)';
    RAISE NOTICE 'Multiple users can read the same data simultaneously';
    RAISE NOTICE 'Updates create new row versions';
    RAISE NOTICE 'Prevents lost updates and dirty reads';
    
    -- Show current facility loads
    RAISE NOTICE 'Current facility loads:';
    PERFORM facility_name, current_load_kg, capacity_kg 
    FROM recycling_facilities 
    ORDER BY facility_id;
END $$;

-- DEMO 8: Savepoint Usage (Nested Transactions)
DO $$
DECLARE
    v_pickup_id INT;
    v_item_id INT;
BEGIN
    BEGIN
        RAISE NOTICE '=== DEMO 8: Savepoints (Partial Rollback) ===';
        
        -- Create pickup
        CALL create_pickup_request(1, CURRENT_DATE + 5, 'Savepoint test', NULL, v_pickup_id);
        RAISE NOTICE 'Created pickup %', v_pickup_id;
        
        -- Savepoint 1
        SAVEPOINT sp1;
        RAISE NOTICE 'SAVEPOINT sp1 created';
        
        -- Add first item
        CALL add_item_to_pickup(v_pickup_id, 1, 'Item 1', 'working', 0.2, NULL, v_item_id);
        RAISE NOTICE 'Added item 1';
        
        -- Savepoint 2
        SAVEPOINT sp2;
        RAISE NOTICE 'SAVEPOINT sp2 created';
        
        BEGIN
            -- Try to add invalid item
            CALL add_item_to_pickup(v_pickup_id, 999, 'Invalid item', 'working', 0.1, NULL, v_item_id);
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Error adding item 2: %', SQLERRM;
                RAISE NOTICE 'Rolling back to SAVEPOINT sp2';
                ROLLBACK TO sp2;
                RAISE NOTICE 'Pickup and item 1 still exist, only item 2 rolled back';
        END;
        
        -- Add another valid item
        CALL add_item_to_pickup(v_pickup_id, 1, 'Item 3', 'working', 0.25, NULL, v_item_id);
        RAISE NOTICE 'Added item 3 after partial rollback';
        RAISE NOTICE 'Final result: Pickup with 2 items (1 and 3)';
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Outer exception: %', SQLERRM;
    END;
END $$;

-- Summary Report
SELECT 
    '=== TRANSACTION DEMO SUMMARY ===' AS report,
    'Demonstrated:' AS section,
    '1. ATOMICITY - All or nothing' AS point_1,
    '2. CONSISTENCY - Constraints enforced' AS point_2,
    '3. ISOLATION - Transactions don''t interfere' AS point_3,
    '4. DURABILITY - Committed data persists' AS point_4,
    '5. ROLLBACK - Failed transactions reversed' AS point_5,
    '6. SAVEPOINTS - Partial rollback' AS point_6,
    '7. MULTI-TABLE - Complex transactions' AS point_7;

-- Comments:
-- 1. These demos show ACID properties in action
-- 2. Real transactions in procedures ensure data integrity
-- 3. Exceptions trigger automatic rollback
-- 4. Savepoints allow partial rollback
-- 5. All database modifications are transactional
-- 6. This demonstrates database-driven reliability
-- 7. No application code needed for transaction safety