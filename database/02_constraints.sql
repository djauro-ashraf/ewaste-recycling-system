-- ============================================================
-- 02_constraints.sql
-- ============================================================

-- ── vehicles ──────────────────────────────────────────────
ALTER TABLE vehicles
    ADD CONSTRAINT fk_vehicle_supervisor
        FOREIGN KEY (supervisor_id) REFERENCES staff(staff_id),
    ADD CONSTRAINT chk_vehicle_load
        CHECK (current_load_kg <= capacity_kg),
    ADD CONSTRAINT chk_vehicle_capacity
        CHECK (capacity_kg > 0);

-- ── pickup_requests ───────────────────────────────────────
ALTER TABLE pickup_requests
    ADD CONSTRAINT fk_pickup_user
        FOREIGN KEY (user_id) REFERENCES users(user_id),
    ADD CONSTRAINT fk_pickup_supervisor
        FOREIGN KEY (supervisor_id) REFERENCES staff(staff_id),
    ADD CONSTRAINT fk_pickup_driver
        FOREIGN KEY (driver_id) REFERENCES staff(staff_id),
    ADD CONSTRAINT fk_pickup_collector
        FOREIGN KEY (collector_id) REFERENCES staff(staff_id),
    ADD CONSTRAINT fk_pickup_vehicle
        FOREIGN KEY (assigned_vehicle_id) REFERENCES vehicles(vehicle_id),
    ADD CONSTRAINT fk_pickup_facility
        FOREIGN KEY (assigned_facility_id) REFERENCES recycling_facilities(facility_id),
    ADD CONSTRAINT chk_pickup_weight
        CHECK (total_weight_kg >= 0),
    ADD CONSTRAINT chk_pickup_amount
        CHECK (total_amount >= 0);

-- ── Supervisor must actually be a supervisor ───────────────
-- Enforced via trigger (cannot do in FK alone without function)

-- ── items ─────────────────────────────────────────────────
ALTER TABLE items
    ADD CONSTRAINT fk_item_pickup
        FOREIGN KEY (pickup_id) REFERENCES pickup_requests(pickup_id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_item_category
        FOREIGN KEY (category_id) REFERENCES categories(category_id);

-- ── weight_records ────────────────────────────────────────
ALTER TABLE weight_records
    ADD CONSTRAINT fk_weight_item
        FOREIGN KEY (item_id) REFERENCES items(item_id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_weight_staff
        FOREIGN KEY (weighed_by) REFERENCES staff(staff_id),
    ADD CONSTRAINT chk_positive_kg
        CHECK (weight_kg > 0);

-- ── payments ──────────────────────────────────────────────
ALTER TABLE payments
    ADD CONSTRAINT fk_payment_pickup
        FOREIGN KEY (pickup_id) REFERENCES pickup_requests(pickup_id),
    ADD CONSTRAINT fk_payment_supervisor
        FOREIGN KEY (processed_by) REFERENCES staff(staff_id),
    ADD CONSTRAINT chk_payment_amount
        CHECK (amount >= 0);

-- ── payment_requests ──────────────────────────────────────
ALTER TABLE payment_requests
    ADD CONSTRAINT fk_pr_pickup
        FOREIGN KEY (pickup_id) REFERENCES pickup_requests(pickup_id),
    ADD CONSTRAINT fk_pr_user
        FOREIGN KEY (user_id) REFERENCES users(user_id),
    ADD CONSTRAINT fk_pr_supervisor
        FOREIGN KEY (supervisor_id) REFERENCES staff(staff_id);

-- ── recycling_batches ─────────────────────────────────────
ALTER TABLE recycling_batches
    ADD CONSTRAINT fk_batch_facility
        FOREIGN KEY (facility_id) REFERENCES recycling_facilities(facility_id),
    ADD CONSTRAINT fk_batch_supervisor
        FOREIGN KEY (supervisor_id) REFERENCES staff(staff_id),
    ADD CONSTRAINT chk_batch_revenue
        CHECK (total_revenue >= 0);

-- ── batch_items ───────────────────────────────────────────
ALTER TABLE batch_items
    ADD CONSTRAINT fk_bitem_batch
        FOREIGN KEY (batch_id) REFERENCES recycling_batches(batch_id),
    ADD CONSTRAINT fk_bitem_item
        FOREIGN KEY (item_id) REFERENCES items(item_id),
    ADD CONSTRAINT fk_bitem_pickup
        FOREIGN KEY (pickup_id) REFERENCES pickup_requests(pickup_id),
    ADD CONSTRAINT fk_bitem_staff
        FOREIGN KEY (added_by) REFERENCES staff(staff_id),
    ADD CONSTRAINT uq_batch_item UNIQUE (batch_id, item_id);

-- ── system_revenue ────────────────────────────────────────
ALTER TABLE system_revenue
    ADD CONSTRAINT fk_rev_batch
        FOREIGN KEY (batch_id) REFERENCES recycling_batches(batch_id),
    ADD CONSTRAINT fk_rev_facility
        FOREIGN KEY (facility_id) REFERENCES recycling_facilities(facility_id),
    ADD CONSTRAINT fk_rev_staff
        FOREIGN KEY (recorded_by) REFERENCES staff(staff_id),
    ADD CONSTRAINT chk_rev_weight
        CHECK (weight_kg > 0),
    ADD CONSTRAINT chk_rev_price
        CHECK (price_per_kg > 0);

-- ── warnings ──────────────────────────────────────────────
ALTER TABLE warnings
    ADD CONSTRAINT fk_warn_issuer
        FOREIGN KEY (issued_by) REFERENCES accounts(account_id),
    ADD CONSTRAINT fk_warn_user
        FOREIGN KEY (target_user_id) REFERENCES users(user_id),
    ADD CONSTRAINT fk_warn_staff
        FOREIGN KEY (target_staff_id) REFERENCES staff(staff_id),
    ADD CONSTRAINT chk_warn_target CHECK (
        (target_type = 'user'  AND target_user_id  IS NOT NULL AND target_staff_id IS NULL) OR
        (target_type = 'staff' AND target_staff_id IS NOT NULL AND target_user_id  IS NULL)
    );

-- ── pricing_rules ─────────────────────────────────────────
ALTER TABLE pricing_rules
    ADD CONSTRAINT fk_pricing_category
        FOREIGN KEY (category_id) REFERENCES categories(category_id),
    ADD CONSTRAINT chk_weight_range
        CHECK (max_weight_kg IS NULL OR max_weight_kg > min_weight_kg),
    ADD CONSTRAINT chk_date_range
        CHECK (effective_to IS NULL OR effective_to > effective_from);

-- ── recycling_facilities ──────────────────────────────────
ALTER TABLE recycling_facilities
    ADD CONSTRAINT chk_facility_load
        CHECK (current_load_kg <= capacity_kg),
    ADD CONSTRAINT chk_facility_capacity
        CHECK (capacity_kg > 0);
