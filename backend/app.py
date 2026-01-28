# E-WASTE RECYCLING MANAGEMENT SYSTEM
# app.py - Flask Application

import os
import traceback
from flask import Flask, render_template, request, jsonify, redirect, url_for
from db import execute_query, call_procedure

# ================== FLASK CONFIG ==================
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

app = Flask(
    __name__,
    template_folder=os.path.join(BASE_DIR, 'frontend', 'templates'),
    static_folder=os.path.join(BASE_DIR, 'frontend', 'static')
)

# ================== HOMEPAGE ==================
@app.route('/')
def index():
    """Main dashboard"""
    try:
        stats = execute_query("""
            SELECT 
                (SELECT COUNT(*) FROM users WHERE is_active = TRUE) AS active_users,
                (SELECT COUNT(*) FROM pickup_requests WHERE status = 'pending') AS pending_pickups,
                (SELECT COUNT(*) FROM pickup_requests WHERE status = 'completed') AS completed_pickups,
                (SELECT COALESCE(SUM(total_weight_kg), 0) FROM pickup_requests WHERE status = 'completed') AS total_weight,
                (SELECT COUNT(*) FROM recycling_batches WHERE status = 'open') AS open_batches
        """)[0]

        return render_template('index.html', stats=stats)
    except Exception as e:
        return render_template('index.html', error=str(e), stats={
            'active_users': 0, 'pending_pickups': 0, 'completed_pickups': 0,
            'total_weight': 0, 'open_batches': 0
        })


# ================== PICKUP ROUTES ==================
@app.route('/pickups')
def list_pickups():
    try:
        pickups = execute_query(
            "SELECT * FROM v_pickup_summary ORDER BY pickup_id DESC"
        )
        return render_template('list_pickups.html', pickups=pickups)
    except Exception as e:
        return render_template('list_pickups.html', error=str(e), pickups=[])


@app.route('/create-pickup', methods=['GET', 'POST'])
def create_pickup():
    if request.method == 'GET':
        users = execute_query(
            "SELECT user_id, full_name, email FROM users WHERE is_active = TRUE"
        )
        return render_template('create_pickup.html', users=users)

    try:
        result = call_procedure(
            "create_pickup_request",
            (
                int(request.form['user_id']),
                request.form['preferred_date'],
                request.form['address'],
                request.form.get('notes', '')
            )
        )
        return redirect(url_for('list_pickups'))
    except Exception as e:
        return f"Error creating pickup: {e}<br>{traceback.format_exc()}"


@app.route('/complete-collection/<int:pickup_id>')
def complete_collection(pickup_id):
    try:
        call_procedure("complete_pickup_collection", (pickup_id,))
        return redirect(url_for('list_pickups'))
    except Exception as e:
        return f"Error completing collection: {e}"


# ================== ITEM ROUTES ==================
@app.route('/add-items', methods=['GET', 'POST'])
def add_items():
    if request.method == 'GET':
        pickups = execute_query("""
            SELECT pickup_id, user_id, preferred_date, status
            FROM pickup_requests
            WHERE status IN ('pending', 'assigned')
            ORDER BY pickup_id DESC
        """)
        categories = execute_query(
            "SELECT * FROM categories ORDER BY category_name"
        )
        return render_template('add_items.html', pickups=pickups, categories=categories)

    try:
        result = call_procedure(
            "add_item_to_pickup",
            (
                int(request.form['pickup_id']),
                int(request.form['category_id']),
                request.form['description'],
                request.form['condition'],
                float(request.form['estimated_weight']) if request.form.get('estimated_weight') else None
            )
        )
        return redirect(url_for('add_items'))
    except Exception as e:
        return f"Error adding item: {e}<br>{traceback.format_exc()}"


@app.route('/items')
def list_items():
    try:
        items = execute_query(
            "SELECT * FROM v_item_details ORDER BY item_id DESC LIMIT 100"
        )
        return render_template('list_items.html', items=items)
    except Exception as e:
        return render_template('list_items.html', error=str(e), items=[])


# ================== ASSIGNMENT ROUTES ==================
@app.route('/assign-pickup', methods=['GET', 'POST'])
def assign_pickup():
    if request.method == 'GET':
        pickups = execute_query("""
            SELECT p.pickup_id, u.full_name, p.preferred_date,
                   p.total_weight_kg, p.pickup_address
            FROM pickup_requests p
            JOIN users u ON p.user_id = u.user_id
            WHERE p.status = 'pending'
            ORDER BY p.preferred_date
        """)

        staff = execute_query("""
            SELECT staff_id, staff_name, role
            FROM staff_assignments
            WHERE is_available = TRUE
        """)

        vehicles = execute_query(
            "SELECT * FROM vehicles WHERE is_available = TRUE"
        )

        facilities = execute_query(
            "SELECT * FROM recycling_facilities WHERE is_operational = TRUE"
        )

        return render_template(
            'assign_pickup.html',
            pickups=pickups,
            staff=staff,
            vehicles=vehicles,
            facilities=facilities
        )

    try:
        call_procedure(
            "assign_pickup_to_staff",
            (
                int(request.form['pickup_id']),
                int(request.form['staff_id']),
                int(request.form['vehicle_id']),
                int(request.form['facility_id'])
            )
        )
        return redirect(url_for('staff_dashboard'))
    except Exception as e:
        return f"Error assigning pickup: {e}<br>{traceback.format_exc()}"


# ================== STAFF DASHBOARD ==================
@app.route('/staff-dashboard')
def staff_dashboard():
    try:
        staff_workload = execute_query(
            "SELECT * FROM v_staff_workload ORDER BY assigned_pickups DESC"
        )
        assigned_pickups = execute_query("""
            SELECT * FROM v_pickup_summary
            WHERE status IN ('assigned', 'collected')
            ORDER BY scheduled_time
        """)

        return render_template(
            'staff_dashboard.html',
            staff=staff_workload,
            pickups=assigned_pickups
        )
    except Exception as e:
        return render_template('staff_dashboard.html', error=str(e), staff=[], pickups=[])


# ================== PAYMENTS ==================
@app.route('/payments')
def list_payments():
    try:
        payments = execute_query(
            "SELECT * FROM v_payment_summary ORDER BY payment_id DESC"
        )
        return render_template('list_payments.html', payments=payments)
    except Exception as e:
        return render_template('list_payments.html', error=str(e), payments=[])


@app.route('/make-payment', methods=['GET', 'POST'])
def make_payment():
    if request.method == 'GET':
        pickups = execute_query("""
            SELECT p.pickup_id, u.full_name, p.total_weight_kg,
                   p.total_amount, p.completed_time
            FROM pickup_requests p
            JOIN users u ON p.user_id = u.user_id
            WHERE p.status = 'collected'
            ORDER BY p.completed_time DESC
        """)
        return render_template('make_payment.html', pickups=pickups)

    try:
        call_procedure(
            "process_payment",
            (
                int(request.form['pickup_id']),
                request.form['payment_method'],
                request.form.get('transaction_ref')
            )
        )
        return redirect(url_for('list_payments'))
    except Exception as e:
        return f"Error processing payment: {e}<br>{traceback.format_exc()}"


# ================== BATCHES ==================
@app.route('/batches')
def list_batches():
    try:
        batches = execute_query(
            "SELECT * FROM v_batch_summary ORDER BY batch_id DESC"
        )
        return render_template('list_batches.html', batches=batches)
    except Exception as e:
        return render_template('list_batches.html', error=str(e), batches=[])


@app.route('/create-batch', methods=['GET', 'POST'])
def create_batch():
    if request.method == 'GET':
        facilities = execute_query(
            "SELECT * FROM recycling_facilities WHERE is_operational = TRUE"
        )
        return render_template('create_batch.html', facilities=facilities)

    try:
        call_procedure(
            "create_recycling_batch",
            (
                int(request.form['facility_id']),
                request.form['batch_name'],
                request.form.get('notes', '')
            )
        )
        return redirect(url_for('list_batches'))
    except Exception as e:
        return f"Error creating batch: {e}<br>{traceback.format_exc()}"


@app.route('/batch/<int:batch_id>/add-items', methods=['GET', 'POST'])
def add_to_batch(batch_id):
    if request.method == 'GET':
        batch = execute_query(
            "SELECT * FROM v_batch_summary WHERE batch_id = %s",
            (batch_id,)
        )[0]
        
        available_items = execute_query("""
            SELECT i.item_id, i.item_description, c.category_name,
                   COALESCE(i.actual_weight_kg, i.estimated_weight_kg) as weight,
                   p.pickup_id, u.full_name
            FROM items i
            JOIN categories c ON i.category_id = c.category_id
            JOIN pickup_requests p ON i.pickup_id = p.pickup_id
            JOIN users u ON p.user_id = u.user_id
            WHERE p.status = 'completed'
              AND i.item_id NOT IN (SELECT item_id FROM batch_items)
            ORDER BY i.item_id DESC
        """)
        
        return render_template('add_to_batch.html', batch=batch, items=available_items)
    
    try:
        call_procedure(
            "add_item_to_batch",
            (batch_id, int(request.form['item_id']))
        )
        return redirect(url_for('add_to_batch', batch_id=batch_id))
    except Exception as e:
        return f"Error adding item to batch: {e}"


@app.route('/batch/<int:batch_id>/start')
def start_batch(batch_id):
    try:
        call_procedure("start_batch_processing", (batch_id,))
        return redirect(url_for('list_batches'))
    except Exception as e:
        return f"Error starting batch: {e}"


@app.route('/batch/<int:batch_id>/complete', methods=['GET', 'POST'])
def complete_batch(batch_id):
    if request.method == 'GET':
        batch = execute_query(
            "SELECT * FROM v_batch_summary WHERE batch_id = %s",
            (batch_id,)
        )[0]
        return render_template('complete_batch.html', batch=batch)
    
    try:
        call_procedure(
            "complete_batch_processing",
            (batch_id, float(request.form['recovery_rate']))
        )
        return redirect(url_for('list_batches'))
    except Exception as e:
        return f"Error completing batch: {e}"


# ================== REPORTS ==================
@app.route('/reports')
def reports():
    try:
        user_activity = execute_query(
            "SELECT * FROM v_user_activity ORDER BY total_weight_recycled_kg DESC"
        )
        
        category_stats = execute_query(
            "SELECT * FROM v_category_statistics ORDER BY total_weight_kg DESC"
        )
        
        facility_capacity = execute_query(
            "SELECT * FROM v_facility_capacity ORDER BY capacity_usage_percent DESC"
        )
        
        pickup_status = execute_query("""
            SELECT status, 
                   COUNT(*) as count,
                   SUM(total_weight_kg) as total_weight,
                   SUM(total_amount) as total_amount
            FROM pickup_requests
            GROUP BY status
            ORDER BY count DESC
        """)
        
        return render_template(
            'reports.html',
            user_activity=user_activity,
            category_stats=category_stats,
            facility_capacity=facility_capacity,
            pickup_status=pickup_status
        )
    except Exception as e:
        return render_template('reports.html', error=str(e),
                             user_activity=[], category_stats=[],
                             facility_capacity=[], pickup_status=[])


# ================== API ==================
@app.route('/api/pickup/<int:pickup_id>')
def api_get_pickup(pickup_id):
    try:
        pickup = execute_query(
            "SELECT * FROM v_pickup_summary WHERE pickup_id = %s",
            (pickup_id,)
        )
        return jsonify(pickup[0] if pickup else {})
    except Exception as e:
        return jsonify({"error": str(e)})


@app.route('/api/user-stats/<int:user_id>')
def api_user_stats(user_id):
    try:
        stats = execute_query(
            "SELECT * FROM get_user_stats(%s)",
            (user_id,)
        )
        return jsonify(stats[0] if stats else {})
    except Exception as e:
        return jsonify({"error": str(e)})


# ================== RUN ==================
if __name__ == '__main__':
    app.run(debug=True, host='127.0.0.1', port=5000)
