-- ============================================================
-- 03_indexes.sql
-- ============================================================

-- pickup_requests
CREATE INDEX idx_pickup_user_id     ON pickup_requests(user_id);
CREATE INDEX idx_pickup_status      ON pickup_requests(status);
CREATE INDEX idx_pickup_supervisor  ON pickup_requests(supervisor_id);
CREATE INDEX idx_pickup_driver      ON pickup_requests(driver_id);
CREATE INDEX idx_pickup_collector   ON pickup_requests(collector_id);
CREATE INDEX idx_pickup_date        ON pickup_requests(preferred_date);
CREATE INDEX idx_pickup_payment_due ON pickup_requests(payment_due_by) WHERE status = 'collected';

-- items
CREATE INDEX idx_item_pickup        ON items(pickup_id);
CREATE INDEX idx_item_category      ON items(category_id);

-- weight_records
CREATE INDEX idx_weight_item        ON weight_records(item_id);

-- payments
CREATE INDEX idx_payment_pickup     ON payments(pickup_id);
CREATE INDEX idx_payment_status     ON payments(payment_status);
CREATE INDEX idx_payment_supervisor ON payments(processed_by);

-- payment_requests
CREATE INDEX idx_pr_pickup          ON payment_requests(pickup_id);
CREATE INDEX idx_pr_supervisor      ON payment_requests(supervisor_id);
CREATE INDEX idx_pr_status          ON payment_requests(status);

-- batch_items
CREATE INDEX idx_bitem_batch        ON batch_items(batch_id);
CREATE INDEX idx_bitem_pickup       ON batch_items(pickup_id);

-- staff hierarchy
CREATE INDEX idx_staff_supervisor   ON staff(supervisor_id);
CREATE INDEX idx_staff_sub_role     ON staff(sub_role);

-- vehicles
CREATE INDEX idx_vehicle_supervisor ON vehicles(supervisor_id);

-- system_revenue
CREATE INDEX idx_revenue_batch      ON system_revenue(batch_id);
CREATE INDEX idx_revenue_facility   ON system_revenue(facility_id);

-- admin_alerts
CREATE INDEX idx_alert_type         ON admin_alerts(alert_type);
CREATE INDEX idx_alert_unresolved   ON admin_alerts(is_resolved) WHERE is_resolved = FALSE;
CREATE INDEX idx_alert_created      ON admin_alerts(created_at DESC);

-- audit_log
CREATE INDEX idx_audit_table        ON audit_log(table_name);
CREATE INDEX idx_audit_record       ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_at           ON audit_log(changed_at DESC);

-- warnings
CREATE INDEX idx_warn_user          ON warnings(target_user_id);
CREATE INDEX idx_warn_staff         ON warnings(target_staff_id);

-- pricing active lookup
CREATE INDEX idx_pricing_active     ON pricing_rules(category_id, is_active);

-- JSONB GIN index for flexible queries on hazard_details and metadata
CREATE INDEX idx_item_hazard_gin    ON items USING GIN (hazard_details);
CREATE INDEX idx_user_metadata_gin  ON users USING GIN (metadata);
CREATE INDEX idx_staff_metadata_gin ON staff USING GIN (metadata);
CREATE INDEX idx_alert_payload_gin  ON admin_alerts USING GIN (payload);
