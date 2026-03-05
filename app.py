"""
app.py — E-Waste Recycling Management System v3
Roles: user | staff (supervisor / driver / collector) | admin
"""
import json
from flask import (Flask, render_template, request, redirect,
                   url_for, session, flash, jsonify)
from werkzeug.security import generate_password_hash, check_password_hash
from functools import wraps
from db import execute_query, execute_one, execute_update, call_proc, call_func, get_conn, set_app_user
from dotenv import load_dotenv
import os, psycopg2

load_dotenv()

app = Flask(__name__,
            template_folder='frontend/templates',
            static_folder='frontend/static')
app.secret_key = os.environ.get('FLASK_SECRET_KEY', 'ewaste_v3_secret')

# ─────────────────────────────────────────────
#  Auth helpers
# ─────────────────────────────────────────────

def login_required(f):
    @wraps(f)
    def dec(*a, **kw):
        if 'account_id' not in session:
            flash('Please log in.', 'warning')
            return redirect(url_for('login'))
        return f(*a, **kw)
    return dec

def role_required(*roles):
    def decorator(f):
        @wraps(f)
        def dec(*a, **kw):
            if 'account_id' not in session:
                flash('Please log in.', 'warning')
                return redirect(url_for('login'))
            if session.get('role') not in roles:
                flash('Access denied.', 'danger')
                return redirect(url_for('home'))
            return f(*a, **kw)
        return dec
    return decorator

def sub_role_required(*sub_roles):
    """For staff routes: additionally checks sub_role."""
    def decorator(f):
        @wraps(f)
        def dec(*a, **kw):
            if 'account_id' not in session:
                flash('Please log in.', 'warning')
                return redirect(url_for('login'))
            if session.get('role') != 'staff':
                flash('Staff access only.', 'danger')
                return redirect(url_for('home'))
            if session.get('sub_role') not in sub_roles:
                flash('Your staff role does not have access to this page.', 'danger')
                return redirect(url_for('home'))
            return f(*a, **kw)
        return dec
    return decorator

# ─────────────────────────────────────────────
#  Root
# ─────────────────────────────────────────────

@app.route('/')
def home():
    if 'account_id' not in session:
        return redirect(url_for('login'))
    role = session.get('role')
    sub  = session.get('sub_role')
    if role == 'admin':        return redirect(url_for('admin_dashboard'))
    if role == 'staff':
        if sub == 'supervisor': return redirect(url_for('sup_dashboard'))
        return redirect(url_for('field_dashboard'))
    return redirect(url_for('user_dashboard'))

# ─────────────────────────────────────────────
#  Authentication
# ─────────────────────────────────────────────

@app.route('/login', methods=['GET','POST'])
def login():
    if 'account_id' in session: return redirect(url_for('home'))
    if request.method == 'POST':
        username = request.form.get('username','').strip()
        password = request.form.get('password','')
        acc = execute_one(
            "SELECT a.*, s.sub_role FROM accounts a "
            "LEFT JOIN staff s ON a.staff_id = s.staff_id "
            "WHERE a.username = %s AND a.is_active = TRUE", (username,))
        if acc and check_password_hash(acc['password_hash'], password):
            session['account_id'] = acc['account_id']
            session['username']   = acc['username']
            session['role']       = acc['role']
            session['sub_role']   = acc.get('sub_role')   # supervisor|driver|collector|None
            session['user_id']    = acc['user_id']
            session['staff_id']   = acc['staff_id']
            session['full_name']  = acc['display_name']
            execute_update("UPDATE accounts SET last_login=NOW() WHERE account_id=%s",
                           (acc['account_id'],))
            flash(f"Welcome, {acc['display_name']}!", 'success')
            return redirect(url_for('home'))
        flash('Invalid credentials.', 'danger')
    return render_template('auth/login.html')

@app.route('/register', methods=['GET','POST'])
def register():
    if 'account_id' in session: return redirect(url_for('home'))
    if request.method == 'POST':
        try:
            fn  = request.form['full_name'].strip()
            em  = request.form['email'].strip().lower()
            ph  = request.form['phone'].strip()
            adr = request.form.get('address', request.form.get('pickup_address','')).strip()
            cty = request.form['city'].strip()
            un  = request.form['username'].strip()
            pw  = request.form['password']
            if execute_one("SELECT 1 FROM accounts WHERE username=%s", (un,)):
                flash('Username taken.', 'danger'); return render_template('auth/register.html')
            if execute_one("SELECT 1 FROM users WHERE email=%s", (em,)):
                flash('Email already registered.', 'danger'); return render_template('auth/register.html')
            user = execute_one(
                "INSERT INTO users (full_name,email,phone,address,city) VALUES(%s,%s,%s,%s,%s) RETURNING user_id",
                (fn, em, ph, adr, cty))
            execute_update(
                "INSERT INTO accounts (username,password_hash,role,user_id,display_name) VALUES(%s,%s,'user',%s,%s)",
                (un, generate_password_hash(pw), user['user_id'], fn))
            flash('Registered! Please log in.', 'success')
            return redirect(url_for('login'))
        except Exception as e:
            flash(f'Error: {e}', 'danger')
    return render_template('auth/register.html')

@app.route('/logout')
def logout():
    session.clear()
    flash('Logged out.', 'info')
    return redirect(url_for('login'))

# ═══════════════════════════════════════════════
#  USER ROUTES
# ═══════════════════════════════════════════════

@app.route('/dashboard')
@role_required('user')
def user_dashboard():
    uid = session['user_id']
    stats = execute_one("""
        SELECT
            COUNT(*) FILTER (WHERE status='pending')             AS pending_count,
            COUNT(*) FILTER (WHERE status IN ('supervisor_assigned','field_assigned')) AS assigned_count,
            COUNT(*) FILTER (WHERE status='collected')           AS collected_count,
            COUNT(*) FILTER (WHERE status='completed')           AS completed_count,
            COALESCE(SUM(total_weight_kg) FILTER (WHERE status='completed'),0) AS total_weight,
            COALESCE(SUM(total_amount)    FILTER (WHERE status='completed'),0) AS total_earned
        FROM pickup_requests WHERE user_id=%s
    """, (uid,))
    recent = execute_query(
        "SELECT * FROM v_pickup_full WHERE user_id=%s ORDER BY pickup_id DESC LIMIT 5", (uid,))
    warnings = execute_query(
        "SELECT * FROM warnings WHERE target_user_id=%s ORDER BY issued_at DESC LIMIT 3", (uid,))
    return render_template('user/dashboard.html', stats=stats, recent=recent, warnings=warnings)

@app.route('/my-pickups')
@role_required('user')
def user_pickups():
    uid = session['user_id']
    pickups = execute_query(
        "SELECT * FROM v_pickup_full WHERE user_id=%s ORDER BY pickup_id DESC", (uid,))
    return render_template('user/pickups.html', pickups=pickups)

@app.route('/my-pickups/<int:pid>')
@role_required('user')
def user_pickup_detail(pid):
    uid = session['user_id']
    pickup = execute_one("SELECT * FROM v_pickup_full WHERE pickup_id=%s AND user_id=%s", (pid, uid))
    if not pickup: flash('Not found.','danger'); return redirect(url_for('user_pickups'))
    items = execute_query("SELECT * FROM v_item_details WHERE pickup_id=%s", (pid,))
    payment = execute_one("SELECT * FROM payments WHERE pickup_id=%s AND payment_status='completed'", (pid,))
    pay_req = execute_one(
        "SELECT * FROM payment_requests WHERE pickup_id=%s AND user_id=%s ORDER BY requested_at DESC LIMIT 1",
        (pid, uid))
    return render_template('user/pickup_detail.html',
                           pickup=pickup, items=items, payment=payment, pay_req=pay_req)

@app.route('/my-pickups/new', methods=['GET','POST'])
@role_required('user')
def user_new_pickup():
    if request.method == 'POST':
        try:
            result = call_proc('create_pickup_request', (
                session['user_id'],
                request.form['preferred_date'],
                request.form.get('address', request.form.get('pickup_address','')),
                request.form.get('notes',''),
                None
            ), username=session['username'])
            flash('Pickup request submitted!', 'success')
            return redirect(url_for('user_pickup_detail', pid=result.get('p_pickup_id')))
        except Exception as e:
            flash(f'Error: {e}', 'danger')
    return render_template('user/new_pickup.html')

@app.route('/my-pickups/<int:pid>/add-item', methods=['GET','POST'])
@role_required('user')
def user_add_item(pid):
    uid = session['user_id']
    pickup = execute_one(
        "SELECT * FROM pickup_requests WHERE pickup_id=%s AND user_id=%s AND status IN ('pending','supervisor_assigned','field_assigned')",
        (pid, uid))
    if not pickup: flash('Cannot add items to this pickup.','danger'); return redirect(url_for('user_pickups'))
    categories = execute_query("SELECT * FROM categories ORDER BY category_name")
    if request.method == 'POST':
        try:
            hazard = {}
            if request.form.get('contains_mercury') == '1': hazard['contains_mercury'] = True
            bc = request.form.get('battery_count','').strip()
            if bc: hazard['battery_count'] = int(bc)
            call_proc('add_item_to_pickup', (
                pid,
                int(request.form['category_id']),
                request.form['item_description'],
                request.form.get('condition') or None,
                float(request.form.get('estimated_weight') or 0) or None,
                json.dumps(hazard) if hazard else None,
                None
            ))
            flash('Item added.', 'success')
            return redirect(url_for('user_pickup_detail', pid=pid))
        except Exception as e:
            flash(f'Error: {e}', 'danger')
    return render_template('user/add_item.html', pickup=pickup, categories=categories)

@app.route('/my-pickups/<int:pid>/request-payment', methods=['POST'])
@role_required('user')
def user_request_payment(pid):
    try:
        result = call_proc('request_payment', (
            pid, session['user_id'],
            request.form.get('notes',''),
            None
        ), username=session['username'])
        flash('Payment request sent to your supervisor.', 'success')
    except Exception as e:
        flash(f'Cannot request payment: {e}', 'danger')
    return redirect(url_for('user_pickup_detail', pid=pid))

@app.route('/my-payments')
@role_required('user')
def user_payments():
    uid = session['user_id']
    payments = execute_query("""
        SELECT py.*, p.pickup_address, p.total_weight_kg, p.collected_at
        FROM payments py
        JOIN pickup_requests p ON py.pickup_id = p.pickup_id
        WHERE p.user_id = %s AND py.payment_status = 'completed'
        ORDER BY py.processed_at DESC
    """, (uid,))
    return render_template('user/payments.html', payments=payments)

# ═══════════════════════════════════════════════
#  FIELD STAFF ROUTES (driver & collector)
# ═══════════════════════════════════════════════

@app.route('/field')
@sub_role_required('driver','collector')
def field_dashboard():
    sid = session['staff_id']
    sub_role = session.get('sub_role', '')
    if sub_role == 'collector':
        active_statuses = "('field_assigned')"
        done_statuses   = "('picked_up','collected','completed')"
    else:  # driver
        active_statuses = "('field_assigned','picked_up')"
        done_statuses   = "('delivered','collected','completed')"

    stats = execute_one(f"""
        SELECT
            COUNT(*) FILTER (WHERE status IN {active_statuses} AND scheduled_time::date = CURRENT_DATE) AS today_count,
            COUNT(*) FILTER (WHERE status IN {active_statuses}) AS pending_count,
            COUNT(*) FILTER (WHERE status IN {done_statuses})   AS done_count,
            COALESCE(SUM(total_weight_kg) FILTER (WHERE status IN {done_statuses}), 0) AS total_weight
        FROM v_pickup_full
        WHERE driver_id=%s OR collector_id=%s
    """, (sid, sid))
    open_assignments = execute_query(f"""
        SELECT * FROM v_pickup_full
        WHERE (driver_id=%s OR collector_id=%s) AND status IN {active_statuses}
        ORDER BY scheduled_time ASC LIMIT 10
    """, (sid, sid))
    return render_template('field/dashboard.html', stats=stats, open_assignments=open_assignments, sub_role=sub_role)

@app.route('/field/assignments')
@sub_role_required('driver','collector')
def field_assignments():
    sid = session['staff_id']
    sub_role = session.get('sub_role', '')
    if sub_role == 'collector':
        active_statuses = ('field_assigned',)
    else:
        active_statuses = ('field_assigned', 'picked_up')
    placeholders = ','.join(['%s'] * len(active_statuses))
    pickups = execute_query(
        f"SELECT * FROM v_pickup_full WHERE (driver_id=%s OR collector_id=%s) AND status IN ({placeholders}) ORDER BY scheduled_time ASC",
        [sid, sid] + list(active_statuses))
    return render_template('field/assignments.html', pickups=pickups, sub_role=sub_role)

@app.route('/field/collect/<int:pid>', methods=['GET','POST'])
@sub_role_required('collector')
def field_collect(pid):
    sid = session['staff_id']
    pickup = execute_one(
        "SELECT * FROM v_pickup_full WHERE pickup_id=%s AND collector_id=%s AND status='field_assigned'",
        (pid, sid))
    if not pickup: flash('Pickup not available for collection.','danger'); return redirect(url_for('field_assignments'))
    items = execute_query("SELECT * FROM v_item_details WHERE pickup_id=%s", (pid,))
    if request.method == 'POST':
        try:
            weights = []
            for item in items:
                w = request.form.get(f'weight_{item["item_id"]}','').strip()
                if w:
                    weights.append({'item_id': item['item_id'], 'weight': float(w)})
            if not weights:
                flash('Enter at least one item weight.', 'danger')
                return render_template('field/collect.html', pickup=pickup, items=items)
            call_proc('collect_pickup', (pid, sid, json.dumps(weights), None), username=session['username'])
            flash('Pickup collected! Waiting for driver to confirm delivery.', 'success')
            return redirect(url_for('field_assignments'))
        except Exception as e:
            flash(f'Error: {e}', 'danger')
    return render_template('field/collect.html', pickup=pickup, items=items)


@app.route('/field/deliver/<int:pid>', methods=['POST'])
@sub_role_required('driver')
def field_deliver(pid):
    sid = session['staff_id']
    try:
        call_proc('deliver_pickup', (pid, sid, None), username=session['username'])
        flash('Delivery confirmed! Payment window is now open.', 'success')
    except Exception as e:
        flash(f'Error: {e}', 'danger')
    return redirect(url_for('field_assignments'))

@app.route('/field/history')
@sub_role_required('driver','collector')
def field_history():
    sid = session['staff_id']
    sub_role = session.get('sub_role', '')
    if sub_role == 'collector':
        done_statuses = ('picked_up', 'collected', 'completed')
    else:
        done_statuses = ('delivered', 'collected', 'completed')
    placeholders = ','.join(['%s'] * len(done_statuses))
    pickups = execute_query(
        f"SELECT * FROM v_pickup_full WHERE (driver_id=%s OR collector_id=%s) AND status IN ({placeholders}) ORDER BY collected_at DESC LIMIT 100",
        [sid, sid] + list(done_statuses))
    return render_template('field/history.html', pickups=pickups)

@app.route('/supervisor/history')
@sub_role_required('supervisor')
def sup_history():
    sid = session['staff_id']
    pickups = execute_query("""
        SELECT * FROM v_pickup_full
        WHERE supervisor_id=%s AND status IN ('collected','completed')
        ORDER BY collected_at DESC LIMIT 100
    """, (sid,))
    payments = execute_query("""
        SELECT py.*, pf.user_name, pf.pickup_address
        FROM payments py
        JOIN v_pickup_full pf ON py.pickup_id = pf.pickup_id
        WHERE pf.supervisor_id = %s AND py.payment_status = 'completed'
        ORDER BY py.processed_at DESC LIMIT 100
    """, (sid,))
    return render_template('supervisor/history.html', pickups=pickups, payments=payments)

@app.route('/admin/history')
@role_required('admin')
def admin_history():
    pickups = execute_query(
        "SELECT * FROM v_pickup_full ORDER BY pickup_id DESC LIMIT 200")
    payments = execute_query("""
        SELECT py.*, pf.user_name, pf.pickup_address, pf.supervisor_name
        FROM payments py
        JOIN v_pickup_full pf ON py.pickup_id = pf.pickup_id
        ORDER BY py.processed_at DESC LIMIT 200
    """)
    return render_template('admin/history.html', pickups=pickups, payments=payments)

@app.route('/my-history')
@role_required('user')
def user_history():
    uid = session['user_id']
    pickups = execute_query(
        "SELECT * FROM v_pickup_full WHERE user_id=%s ORDER BY pickup_id DESC", (uid,))
    payments = execute_query("""
        SELECT py.*, pr.pickup_address
        FROM payments py
        JOIN pickup_requests pr ON py.pickup_id = pr.pickup_id
        WHERE pr.user_id = %s AND py.payment_status = 'completed'
        ORDER BY py.processed_at DESC
    """, (uid,))
    return render_template('user/history.html', pickups=pickups, payments=payments)

# ═══════════════════════════════════════════════
#  SUPERVISOR ROUTES
# ═══════════════════════════════════════════════

@app.route('/supervisor')
@sub_role_required('supervisor')
def sup_dashboard():
    sid = session['staff_id']
    stats_rows = call_func('get_supervisor_stats', (sid,))
    stats = stats_rows[0] if stats_rows else {}
    needs_assignment = execute_query(
        "SELECT * FROM v_pickup_full WHERE supervisor_id=%s AND status='supervisor_assigned' ORDER BY preferred_date ASC",
        (sid,))
    in_progress = execute_query(
        """SELECT * FROM v_pickup_full
           WHERE supervisor_id=%s AND status IN ('field_assigned','picked_up','delivered')
           ORDER BY scheduled_time ASC""", (sid,))
    pay_requests = execute_query(
        "SELECT * FROM v_payment_requests_full WHERE supervisor_id=%s AND status='pending' ORDER BY requested_at DESC",
        (sid,))
    overdue = execute_query(
        "SELECT * FROM v_overdue_payments WHERE supervisor_id=%s", (sid,))
    team = execute_query(
        "SELECT * FROM staff WHERE supervisor_id=%s AND is_active ORDER BY sub_role, full_name", (sid,))
    vehicles = execute_query(
        "SELECT * FROM vehicles WHERE supervisor_id=%s ORDER BY vehicle_number", (sid,))
    return render_template('supervisor/dashboard.html',
                           stats=stats, needs_assignment=needs_assignment,
                           in_progress=in_progress,
                           pay_requests=pay_requests, overdue=overdue,
                           team=team, vehicles=vehicles)

@app.route('/supervisor/pickups')
@sub_role_required('supervisor')
def sup_pickups():
    sid  = session['staff_id']
    status_filter = request.args.get('status','')
    sql  = "SELECT * FROM v_pickup_full WHERE supervisor_id=%s"
    params = [sid]
    if status_filter:
        sql += " AND status=%s"; params.append(status_filter)
    sql += " ORDER BY pickup_id DESC"
    pickups = execute_query(sql, params)
    return render_template('supervisor/pickups.html', pickups=pickups, status_filter=status_filter)

@app.route('/supervisor/assign/<int:pid>', methods=['GET','POST'])
@sub_role_required('supervisor')
def sup_assign(pid):
    sid = session['staff_id']
    pickup = execute_one(
        "SELECT * FROM v_pickup_full WHERE pickup_id=%s AND supervisor_id=%s AND status='supervisor_assigned'",
        (pid, sid))
    if not pickup: flash('Not available for assignment.','danger'); return redirect(url_for('sup_pickups'))
    drivers    = execute_query("SELECT * FROM staff WHERE supervisor_id=%s AND sub_role='driver' AND is_active AND is_available ORDER BY full_name", (sid,))
    collectors = execute_query("SELECT * FROM staff WHERE supervisor_id=%s AND sub_role='collector' AND is_active AND is_available ORDER BY full_name", (sid,))
    vehicles   = execute_query("SELECT * FROM vehicles WHERE supervisor_id=%s AND is_available ORDER BY vehicle_number", (sid,))
    if request.method == 'POST':
        try:
            call_proc('supervisor_assign_field', (
                pid, sid,
                int(request.form['driver_id']),
                int(request.form['collector_id']),
                int(request.form['vehicle_id']),
                None
            ), username=session['username'])
            flash('Field team assigned!', 'success')
            return redirect(url_for('sup_pickups'))
        except Exception as e:
            flash(f'Error: {e}', 'danger')
    return render_template('supervisor/assign.html',
                           pickup=pickup, drivers=drivers, collectors=collectors, vehicles=vehicles)

@app.route('/supervisor/payments')
@sub_role_required('supervisor')
def sup_payments():
    sid = session['staff_id']
    pending = execute_query(
        "SELECT * FROM v_pickup_full WHERE supervisor_id=%s AND status='collected' ORDER BY collected_at ASC",
        (sid,))
    # Pre-calculate estimated payout for each pending pickup (for modal display)
    estimated = {}
    for p in pending:
        row = execute_one("""
            SELECT COALESCE(SUM(
                ROUND(COALESCE(i.actual_weight_kg, i.estimated_weight_kg, 0) * c.base_price_per_kg, 2)
            ), 0) AS est_total
            FROM items i
            JOIN categories c ON i.category_id = c.category_id
            WHERE i.pickup_id = %s
        """, (p['pickup_id'],))
        estimated[p['pickup_id']] = float(row['est_total']) if row and row['est_total'] is not None else 0.0
    history = execute_query("""
        SELECT py.*, pf.user_name, pf.total_weight_kg
        FROM payments py
        JOIN v_pickup_full pf ON py.pickup_id = pf.pickup_id
        WHERE pf.supervisor_id = %s AND py.payment_status = 'completed'
        ORDER BY py.processed_at DESC LIMIT 30
    """, (sid,))
    return render_template('supervisor/payments.html', pending=pending, history=history, estimated=estimated)

@app.route('/supervisor/process-payment', methods=['POST'])
@sub_role_required('supervisor')
def sup_process_payment():
    sid = session['staff_id']
    try:
        custom_raw = request.form.get('custom_amount', '').strip()
        custom_amount = float(custom_raw) if custom_raw else None
        result = call_proc('supervisor_process_payment', (
            int(request.form['pickup_id']),
            sid,
            request.form['payment_method'],
            request.form.get('txn_ref') or None,
            custom_amount,
            None, None
        ), username=session['username'])
        paid = result.get('p_amount')
        paid_str = f"৳{float(paid):.2f}" if paid is not None else "(see history)"
        flash(f'Payment of {paid_str} processed successfully.', 'success')
    except Exception as e:
        flash(f'Payment error: {e}', 'danger')
    return redirect(url_for('sup_payments'))

@app.route('/supervisor/pay-requests')
@sub_role_required('supervisor')
def sup_pay_requests():
    sid = session['staff_id']
    requests = execute_query(
        "SELECT * FROM v_payment_requests_full WHERE supervisor_id=%s ORDER BY requested_at DESC",
        (sid,))
    return render_template('supervisor/pay_requests.html', requests=requests)

@app.route('/supervisor/batches')
@sub_role_required('supervisor')
def sup_batches():
    sid = session['staff_id']
    batches = execute_query(
        "SELECT * FROM v_batch_full WHERE supervisor_id=%s ORDER BY batch_id DESC", (sid,))
    facilities = execute_query("SELECT * FROM recycling_facilities WHERE is_operational ORDER BY facility_name")
    return render_template('supervisor/batches.html', batches=batches, facilities=facilities)

@app.route('/supervisor/batches/create', methods=['POST'])
@sub_role_required('supervisor')
def sup_create_batch():
    sid = session['staff_id']
    try:
        result = call_proc('create_recycling_batch_v2', (
            int(request.form['facility_id']),
            request.form['batch_name'],
            request.form.get('notes',''),
            sid,
            None
        ), username=session['username'])
        flash(f"Batch created (ID: {result.get('p_batch_id','?')}).", 'success')
    except Exception as e:
        flash(f'Error: {e}', 'danger')
    return redirect(url_for('sup_batches'))

@app.route('/supervisor/batches/<int:bid>/add-items', methods=['GET','POST'])
@sub_role_required('supervisor')
def sup_batch_add_items(bid):
    sid = session['staff_id']
    batch = execute_one("SELECT * FROM v_batch_full WHERE batch_id=%s AND supervisor_id=%s AND status='open'", (bid, sid))
    if not batch: flash('Batch not available.','danger'); return redirect(url_for('sup_batches'))
    # Eligible: collected, delivered, or completed pickups under this supervisor
    # whose items aren't already in this batch
    eligible = execute_query("""
        SELECT i.item_id, i.item_description, i.actual_weight_kg,
               i.estimated_weight_kg,
               COALESCE(i.actual_weight_kg, i.estimated_weight_kg, 0) AS effective_weight,
               c.category_name, p.pickup_id, p.status AS pickup_status,
               u.full_name AS user_name
        FROM items i
        JOIN categories c ON i.category_id = c.category_id
        JOIN pickup_requests p ON i.pickup_id = p.pickup_id
        JOIN users u ON p.user_id = u.user_id
        WHERE p.supervisor_id = %s
          AND p.status IN ('delivered', 'collected')
          AND i.item_id NOT IN (SELECT item_id FROM batch_items WHERE batch_id = %s)
        ORDER BY p.status DESC, p.pickup_id, i.item_id
    """, (sid, bid))
    if request.method == 'POST':
        item_ids = request.form.getlist('item_ids')
        added = 0
        for iid in item_ids:
            # get pickup_id for this item
            row = execute_one("SELECT pickup_id FROM items WHERE item_id=%s", (int(iid),))
            if row:
                try:
                    execute_update(
                        "INSERT INTO batch_items (batch_id, item_id, pickup_id, added_by) VALUES (%s,%s,%s,%s)",
                        (bid, int(iid), row['pickup_id'], sid))
                    added += 1
                except Exception:
                    pass
        flash(f'{added} item(s) added to batch.', 'success')
        return redirect(url_for('sup_batch_add_items', bid=bid))
    batch_items = execute_query("""
        SELECT bi.item_id, i.item_description,
               i.actual_weight_kg, i.estimated_weight_kg,
               COALESCE(i.actual_weight_kg, i.estimated_weight_kg, 0) AS effective_weight,
               c.category_name, i.pickup_id,
               ROUND(COALESCE(i.actual_weight_kg, i.estimated_weight_kg, 0)
                     * c.base_price_per_kg, 2) AS est_value
        FROM batch_items bi
        JOIN items i ON bi.item_id = i.item_id
        JOIN categories c ON i.category_id = c.category_id
        WHERE bi.batch_id = %s
        ORDER BY i.pickup_id, i.item_id
    """, (bid,))
    batch_total_weight = sum(float(r['effective_weight'] or 0) for r in batch_items)
    batch_total_value  = sum(float(r['est_value'] or 0) for r in batch_items)
    return render_template('supervisor/batch_add_items.html',
                           batch=batch, available_items=eligible, batch_items=batch_items,
                           batch_total_weight=batch_total_weight, batch_total_value=batch_total_value)

@app.route('/supervisor/batches/<int:bid>/process', methods=['POST'])
@sub_role_required('supervisor')
def sup_process_batch(bid):
    sid = session['staff_id']
    try:
        call_proc('process_batch', (bid, sid, None), username=session['username'])
        flash('Batch moved to processing.', 'success')
    except Exception as e:
        flash(f'Error: {e}', 'danger')
    return redirect(url_for('sup_batches'))

@app.route('/supervisor/batches/<int:bid>/complete', methods=['GET','POST'])
@sub_role_required('supervisor')
def sup_complete_batch(bid):
    sid = session['staff_id']
    batch = execute_one("SELECT * FROM v_batch_full WHERE batch_id=%s AND supervisor_id=%s AND status='processing'", (bid, sid))
    if not batch: flash('Batch not in processing.','danger'); return redirect(url_for('sup_batches'))
    if request.method == 'POST':
        try:
            materials = []
            for i in range(0, 8):
                mat  = request.form.get(f'material_{i}','').strip()
                wt   = request.form.get(f'weight_{i}','').strip()
                pr   = request.form.get(f'price_{i}','').strip()
                if mat and wt and pr:
                    materials.append({'material': mat, 'weight': float(wt), 'price_per_kg': float(pr)})
            rec = float(request.form.get('recovery_rate', 0))
            result = call_proc('complete_batch', (bid, rec, json.dumps(materials), sid, None), username=session['username'])
            flash(f"Batch completed. Revenue: ৳{result.get('p_total_revenue',0):.2f}", 'success')
            return redirect(url_for('sup_batches'))
        except Exception as e:
            flash(f'Error: {e}', 'danger')
    return render_template('supervisor/complete_batch.html', batch=batch)

@app.route('/supervisor/team')
@sub_role_required('supervisor')
def sup_team():
    sid = session['staff_id']
    team = execute_query("SELECT * FROM v_staff_full WHERE supervisor_id=%s AND sub_role IN ('driver','collector') ORDER BY sub_role, full_name", (sid,))
    vehicles = execute_query("SELECT * FROM vehicles WHERE supervisor_id=%s ORDER BY vehicle_number", (sid,))
    return render_template('supervisor/team.html', team=team, vehicles=vehicles)

# ═══════════════════════════════════════════════
#  ADMIN ROUTES
# ═══════════════════════════════════════════════

@app.route('/admin')
@role_required('admin')
def admin_dashboard():
    stats = execute_one("""
        SELECT
            (SELECT COUNT(*) FROM users WHERE is_active)                        AS total_users,
            (SELECT COUNT(*) FROM staff WHERE is_active AND sub_role='supervisor') AS supervisors,
            (SELECT COUNT(*) FROM staff WHERE is_active AND sub_role='driver')     AS drivers,
            (SELECT COUNT(*) FROM staff WHERE is_active AND sub_role='collector')  AS collectors,
            (SELECT COUNT(*) FROM pickup_requests WHERE status='pending')           AS pending,
            (SELECT COUNT(*) FROM pickup_requests WHERE status='supervisor_assigned') AS sup_assigned,
            (SELECT COUNT(*) FROM pickup_requests WHERE status='field_assigned')    AS field_assigned,
            (SELECT COUNT(*) FROM pickup_requests WHERE status='collected')         AS collected,
            (SELECT COUNT(*) FROM pickup_requests WHERE status='completed')         AS completed,
            (SELECT COALESCE(SUM(amount),0) FROM payments WHERE payment_status='completed') AS total_paid,
            (SELECT COALESCE(SUM(total_value),0) FROM system_revenue)               AS total_revenue,
            (SELECT COUNT(*) FROM admin_alerts WHERE NOT is_resolved)               AS unresolved_alerts,
            (SELECT COUNT(*) FROM v_overdue_payments)                               AS overdue_payments,
            (SELECT COUNT(*) FROM recycling_batches WHERE status='open')            AS open_batches
    """)
    alerts = execute_query(
        "SELECT * FROM v_admin_alerts_active LIMIT 10")
    recent_pickups = execute_query(
        "SELECT * FROM v_pickup_full ORDER BY pickup_id DESC LIMIT 8")
    supervisors = execute_query("SELECT * FROM v_supervisor_team ORDER BY supervisor_name")
    overdue = execute_query("SELECT * FROM v_overdue_payments LIMIT 10")
    return render_template('admin/dashboard.html', stats=stats, alerts=alerts,
                           recent_pickups=recent_pickups, supervisors=supervisors, overdue=overdue)

@app.route('/admin/pickups')
@role_required('admin')
def admin_pickups():
    sf  = request.args.get('status','')
    sid = request.args.get('supervisor_id','')
    sql = "SELECT * FROM v_pickup_full WHERE 1=1"
    params = []
    if sf:  sql += " AND status=%s";          params.append(sf)
    if sid: sql += " AND supervisor_id=%s";   params.append(int(sid))
    sql += " ORDER BY pickup_id DESC"
    pickups = execute_query(sql, params)
    supervisors = execute_query("SELECT staff_id, full_name FROM staff WHERE sub_role='supervisor' AND is_active ORDER BY full_name")
    return render_template('admin/pickups.html', pickups=pickups, status_filter=sf,
                           supervisors=supervisors, sup_filter=sid)

@app.route('/admin/assign-supervisor/<int:pid>', methods=['GET','POST'])
@role_required('admin')
def admin_assign_supervisor(pid):
    pickup = execute_one("SELECT * FROM v_pickup_full WHERE pickup_id=%s", (pid,))
    if not pickup: flash('Pickup not found.','danger'); return redirect(url_for('admin_pickups'))
    supervisors = execute_query("SELECT * FROM v_supervisor_team WHERE supervisor_active ORDER BY supervisor_name")
    facilities  = execute_query("SELECT * FROM v_facility_capacity WHERE is_operational ORDER BY facility_name")
    items = execute_query("SELECT * FROM v_item_details WHERE pickup_id=%s", (pid,))
    if request.method == 'POST':
        try:
            sup_id = request.form.get('supervisor_id', '').strip()
            fac_id = request.form.get('facility_id', '').strip()
            if not sup_id or not fac_id:
                flash('Please select both a supervisor and a facility.', 'danger')
                return render_template('admin/assign_supervisor.html',
                                       pickup=pickup, supervisors=supervisors, facilities=facilities)
            call_proc('admin_assign_supervisor', (
                pid, int(sup_id),
                int(fac_id), None
            ), username=session['username'])
            flash('Supervisor assigned.', 'success')
            return redirect(url_for('admin_pickups'))
        except Exception as e:
            flash(f'Error: {e}', 'danger')
    return render_template('admin/assign_supervisor.html',
                           pickup=pickup, supervisors=supervisors, facilities=facilities, items=items)

@app.route('/admin/staff')
@role_required('admin')
def admin_staff():
    supervisors = execute_query(
        "SELECT * FROM v_supervisor_team ORDER BY supervisor_name")
    all_staff = execute_query(
        "SELECT * FROM v_staff_full ORDER BY sub_role, full_name")
    return render_template('admin/staff.html', supervisors=supervisors, all_staff=all_staff)

@app.route('/admin/staff/create', methods=['POST'])
@role_required('admin')
def admin_create_staff():
    try:
        name    = request.form['full_name'].strip()
        sr      = request.form['sub_role']
        contact = request.form['contact_number'].strip()
        un      = request.form['username'].strip()
        pw      = request.form['password']
        sup_id  = request.form.get('supervisor_id') or None
        if sup_id: sup_id = int(sup_id)
        if sr in ('driver','collector') and not sup_id:
            flash('Driver/Collector must be assigned to a supervisor.', 'danger')
            return redirect(url_for('admin_staff'))
        if execute_one("SELECT 1 FROM accounts WHERE username=%s", (un,)):
            flash('Username taken.', 'danger'); return redirect(url_for('admin_staff'))
        staff = execute_one(
            "INSERT INTO staff (full_name,sub_role,contact_number,supervisor_id) VALUES(%s,%s,%s,%s) RETURNING staff_id",
            (name, sr, contact, sup_id))
        execute_update(
            "INSERT INTO accounts (username,password_hash,role,staff_id,display_name) VALUES(%s,%s,'staff',%s,%s)",
            (un, generate_password_hash(pw), staff['staff_id'], name))
        flash(f'{sr.title()} {name} created.', 'success')
    except Exception as e:
        flash(f'Error: {e}', 'danger')
    return redirect(url_for('admin_staff'))

@app.route('/admin/staff/fire/<int:sid>', methods=['POST'])
@role_required('admin')
def admin_fire_staff(sid):
    try:
        reason = request.form.get('reason','No reason given.')
        call_proc('fire_staff', (sid, session['account_id'], reason, None), username=session['username'])
        flash('Staff member fired.', 'success')
    except Exception as e:
        flash(f'Error: {e}', 'danger')
    return redirect(url_for('admin_staff'))

@app.route('/admin/vehicles')
@role_required('admin')
def admin_vehicles():
    vehicles    = execute_query("""
        SELECT v.*, s.full_name AS supervisor_name
        FROM vehicles v LEFT JOIN staff s ON v.supervisor_id = s.staff_id
        ORDER BY v.vehicle_number
    """)
    supervisors = execute_query("SELECT staff_id, full_name FROM staff WHERE sub_role='supervisor' AND is_active ORDER BY full_name")
    return render_template('admin/vehicles.html', vehicles=vehicles, supervisors=supervisors)

@app.route('/admin/vehicles/create', methods=['POST'])
@role_required('admin')
def admin_create_vehicle():
    try:
        result = call_proc('add_vehicle', (
            request.form['vehicle_number'].strip(),
            request.form['vehicle_type'],
            float(request.form['capacity_kg']),
            int(request.form['supervisor_id']),
            None
        ), username=session['username'])
        flash('Vehicle added.', 'success')
    except Exception as e:
        flash(f'Error: {e}', 'danger')
    return redirect(url_for('admin_vehicles'))

@app.route('/admin/users')
@role_required('admin')
def admin_users():
    users = execute_query("SELECT * FROM v_user_activity ORDER BY registered_at DESC")
    return render_template('admin/users.html', users=users)

@app.route('/admin/users/toggle/<int:uid>', methods=['POST'])
@role_required('admin')
def admin_toggle_user(uid):
    execute_update("UPDATE users SET is_active = NOT is_active WHERE user_id=%s", (uid,))
    execute_update("UPDATE accounts SET is_active = NOT is_active WHERE user_id=%s", (uid,))
    flash('User status toggled.', 'success')
    return redirect(url_for('admin_users'))

@app.route('/admin/warnings', methods=['GET','POST'])
@role_required('admin')
def admin_warnings():
    if request.method == 'POST':
        try:
            call_proc('issue_warning', (
                session['account_id'],
                request.form['target_type'],
                int(request.form['target_id']),
                request.form['severity'],
                request.form['message'],
                None
            ), username=session['username'])
            flash('Warning issued.', 'success')
        except Exception as e:
            flash(f'Error: {e}', 'danger')
        return redirect(url_for('admin_warnings'))
    warnings = execute_query("""
        SELECT w.*, a.display_name AS issued_by_name,
               u.full_name AS target_user_name,
               s.full_name AS target_staff_name,
               s.sub_role  AS target_sub_role
        FROM warnings w
        JOIN accounts a ON w.issued_by = a.account_id
        LEFT JOIN users u ON w.target_user_id = u.user_id
        LEFT JOIN staff  s ON w.target_staff_id = s.staff_id
        ORDER BY w.issued_at DESC
    """)
    users_list = execute_query("SELECT user_id, full_name FROM users WHERE is_active ORDER BY full_name")
    staff_list = execute_query("SELECT staff_id, full_name, sub_role FROM staff WHERE is_active ORDER BY full_name")
    users_json = [{'id': u['user_id'],  'name': u['full_name']} for u in users_list]
    staff_json = [{'id': s['staff_id'], 'name': f"{s['full_name']} ({s['sub_role']})"} for s in staff_list]
    return render_template('admin/warnings.html', warnings=warnings,
                           users_json=users_json, staff_json=staff_json)

@app.route('/admin/alerts')
@role_required('admin')
def admin_alerts():
    severity_filter = request.args.get('severity', '')
    show_resolved   = request.args.get('resolved', '') == '1'
    sql = "SELECT * FROM admin_alerts WHERE 1=1"
    params = []
    if severity_filter: sql += " AND severity=%s"; params.append(severity_filter)
    if not show_resolved: sql += " AND is_resolved=FALSE"
    sql += " ORDER BY CASE severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END, created_at DESC"
    alerts = execute_query(sql, params or None)
    return render_template('admin/alerts.html', alerts=alerts,
                           severity_filter=severity_filter, show_resolved=show_resolved)

@app.route('/admin/alerts/resolve/<int:aid>', methods=['POST'])
@role_required('admin')
def admin_resolve_alert(aid):
    execute_update(
        "UPDATE admin_alerts SET is_resolved=TRUE, resolved_at=NOW(), resolved_by=%s WHERE alert_id=%s",
        (session['account_id'], aid))
    return redirect(url_for('admin_alerts'))

@app.route('/admin/logs')
@role_required('admin')
def admin_logs():
    table_f = request.args.get('table','')
    page    = int(request.args.get('page', 1))
    limit   = 50
    offset  = (page - 1) * limit
    sql = "SELECT * FROM audit_log WHERE 1=1"
    params = []
    if table_f: sql += " AND table_name=%s"; params.append(table_f)
    sql += " ORDER BY changed_at DESC LIMIT %s OFFSET %s"
    params += [limit, offset]
    logs  = execute_query(sql, params)
    total = execute_one("SELECT COUNT(*) AS c FROM audit_log" + (" WHERE table_name=%s" if table_f else ""),
                        ([table_f] if table_f else None))
    return render_template('admin/logs.html', logs=logs, table_filter=table_f,
                           page=page, total=total['c'] if total else 0, limit=limit)

@app.route('/admin/reports')
@role_required('admin')
def admin_reports():
    sup_stats = execute_query("SELECT * FROM v_supervisor_team ORDER BY total_pickups DESC")
    cat_stats = execute_query("SELECT * FROM v_category_statistics WHERE total_items>0 ORDER BY total_payout_value DESC")
    fac_cap   = execute_query("SELECT * FROM v_facility_capacity ORDER BY utilisation_pct DESC")
    user_top  = execute_query("SELECT * FROM v_user_activity WHERE total_pickups>0 ORDER BY total_earnings DESC LIMIT 15")
    rev_sum   = execute_query("SELECT * FROM v_system_revenue_summary ORDER BY total_revenue DESC")
    monthly   = execute_query("""
        SELECT TO_CHAR(request_date,'Mon YYYY') AS period,
               EXTRACT(YEAR FROM request_date) AS yr,
               EXTRACT(MONTH FROM request_date) AS mo,
               COUNT(*) AS total_pickups,
               COALESCE(SUM(total_weight_kg),0) AS total_weight,
               COALESCE(SUM(total_amount),0) AS total_payout
        FROM pickup_requests
        GROUP BY period, yr, mo ORDER BY yr DESC, mo DESC LIMIT 12
    """)
    return render_template('admin/reports.html',
                           sup_stats=sup_stats, cat_stats=cat_stats, fac_cap=fac_cap,
                           user_top=user_top, rev_sum=rev_sum, monthly=monthly)

@app.route('/admin/batches')
@role_required('admin')
def admin_batches():
    batches = execute_query("SELECT * FROM v_batch_full ORDER BY batch_id DESC")
    return render_template('admin/batches.html', batches=batches)

@app.route('/admin/batches/<int:bid>/force-process', methods=['POST'])
@role_required('admin')
def admin_force_process_batch(bid):
    try:
        call_proc('process_batch', (bid, None, None), username=session['username'])
        flash('Batch moved to processing.', 'success')
    except Exception as e:
        flash(f'Error: {e}', 'danger')
    return redirect(url_for('admin_batches'))

# ─────────────────────────────────────────────
#  API endpoints
# ─────────────────────────────────────────────

@app.route('/api/supervisor-stats/<int:sid>')
@role_required('admin')
def api_sup_stats(sid):
    rows = call_func('get_supervisor_stats', (sid,))
    return jsonify(rows[0] if rows else {})

@app.route('/api/facility-capacity/<int:fid>')
@login_required
def api_facility_capacity(fid):
    cap = execute_one("SELECT * FROM v_facility_capacity WHERE facility_id=%s", (fid,))
    return jsonify(cap or {})

# ─────────────────────────────────────────────
#  Context processor
# ─────────────────────────────────────────────

@app.context_processor
def inject_globals():
    unresolved = 0
    if session.get('role') == 'admin':
        try:
            row = execute_one("SELECT COUNT(*) AS c FROM admin_alerts WHERE NOT is_resolved")
            unresolved = row['c'] if row else 0
        except Exception:
            pass
    return dict(
        current_user={
            'account_id': session.get('account_id'),
            'username':   session.get('username'),
            'full_name':  session.get('full_name'),
            'role':       session.get('role'),
            'sub_role':   session.get('sub_role'),
            'user_id':    session.get('user_id'),
            'staff_id':   session.get('staff_id'),
        },
        unresolved_alerts=unresolved
    )

# ─────────────────────────────────────────────
#  Missing procedure stub in sample data
# ─────────────────────────────────────────────

def register_extra_procedures():
    """
    Registers helper procedure create_recycling_batch_v2 that also sets supervisor_id.
    Reads and executes 06b_extra.sql at startup.
    """
    import os
    sql_path = os.path.join(os.path.dirname(__file__), 'database', '06b_extra.sql')
    try:
        with open(sql_path) as f:
            sql = f.read()
        from db import get_conn
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(sql)
    except Exception as e:
        print(f'[startup] register_extra_procedures: {e}')

register_extra_procedures()

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)