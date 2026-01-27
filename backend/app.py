# E-WASTE RECYCLING MANAGEMENT SYSTEM
# app.py - Flask Application (Thin Backend Layer)

from flask import Flask, render_template, request, jsonify, redirect, url_for
from db import execute_query, call_procedure, call_function
import traceback

app = Flask(__name__)

# ============= HOMEPAGE =============
@app.route('/')
def index():
    """Main dashboard"""
    try:
        # Get summary statistics
        stats = execute_query("""
            SELECT 
                (SELECT COUNT(*) FROM users WHERE is_active = TRUE) as active_users,
                (SELECT COUNT(*) FROM pickup_requests WHERE status = 'pending') as pending_pickups,
                (SELECT COUNT(*) FROM pickup_requests WHERE status = 'completed') as completed_pickups,
                (SELECT COALESCE(SUM(total_weight_kg), 0) FROM pickup_requests WHERE status = 'completed') as total_weight,
                (SELECT COUNT(*) FROM recycling_batches WHERE status = 'open') as open_batches
        """)[0]
        
        return render_template('index.html', stats=stats)
    except Exception as e:
        return render_template('index.html', error=str(e))

# ============= PICKUP ROUTES =============
@app.route('/pickups')
def list_pickups():
    """List all pickup requests"""
    try:
        pickups = execute_query("SELECT * FROM v_pickup_summary ORDER BY pickup_id DESC")
        return render_template('list_pickups.html', pickups=pickups)
    except Exception as e:
        return f"Error: {e}"

@app.route('/create-pickup', methods=['GET', 'POST'])
def create_pickup():
    """Create new pickup request"""
    if request.method == 'GET':
        # Get users for dropdown
        users = execute_query("SELECT user_id, full_name, email FROM users WHERE is_active = TRUE")
        return render_template('create_pickup.html', users=users)
    
    try:
        # Get form data
        user_id = request.form['user_id']
        preferred_date = request.form['preferred_date']
        address = request.form['address']
        notes = request.form.get('notes', '')
        
        # Call stored procedure
        conn = __import__('db').get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "CALL create_pickup_request(%s, %s, %s, %s, NULL)",
            (user_id, preferred_date, address, notes)
        )
        conn.commit()
        cursor.close()
        conn.close()
        
        return redirect(url_for('list_pickups'))
    except Exception as e:
        return f"Error creating pickup: {e}<br>{traceback.format_exc()}"

# ============= ITEM ROUTES =============
@app.route('/add-items', methods=['GET', 'POST'])
def add_items():
    """Add items to pickup"""
    if request.method == 'GET':
        pickups = execute_query("""
            SELECT pickup_id, user_id, preferred_date, status 
            FROM pickup_requests 
            WHERE status IN ('pending', 'assigned')
            ORDER BY pickup_id DESC
        """)
        categories = execute_query("SELECT * FROM categories ORDER BY category_name")
        return render_template('add_items.html', pickups=pickups, categories=categories)
    
    try:
        # Get form data
        pickup_id = request.form['pickup_id']
        category_id = request.form['category_id']
        description = request.form['description']
        condition = request.form['condition']
        weight = request.form.get('estimated_weight')
        
        # Call stored procedure
        conn = __import__('db').get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "CALL add_item_to_pickup(%s, %s, %s, %s, %s, NULL, NULL)",
            (pickup_id, category_id, description, condition, weight if weight else None)
        )
        conn.commit()
        cursor.close()
        conn.close()
        
        return redirect(url_for('add_items'))
    except Exception as e:
        return f"Error adding item: {e}<br>{traceback.format_exc()}"

@app.route('/items')
def list_items():
    """List all items"""
    try:
        items = execute_query("SELECT * FROM v_item_details ORDER BY item_id DESC LIMIT 50")
        return render_template('list_items.html', items=items)
    except Exception as e:
        return f"Error: {e}"

# ============= ASSIGNMENT ROUTES =============
@app.route('/assign-pickup', methods=['GET', 'POST'])
def assign_pickup():
    """Assign pickup to staff"""
    if request.method == 'GET':
        # Get pending pickups
        pickups = execute_query("""
            SELECT p.pickup_id, p.user_id, u.full_name, p.preferred_date, 
                   p.total_weight_kg, p.pickup_address
            FROM pickup_requests p
            JOIN users u ON p.user_id = u.user_id
            WHERE p.status = 'pending'
            ORDER BY p.preferred_date
        """)
        
        # Get available staff
        staff = execute_query("""
            SELECT staff_id, staff_name, role, assigned_vehicle_id
            FROM staff_assignments 
            WHERE is_available = TRUE
        """)
        
        # Get available vehicles
        vehicles = execute_query("SELECT * FROM vehicles WHERE is_available = TRUE")
        
        # Get operational facilities
        facilities = execute_query("SELECT * FROM recycling_facilities WHERE is_operational = TRUE")
        
        return render_template('assign_pickup.html', 
                             pickups=pickups, 
                             staff=staff, 
                             vehicles=vehicles, 
                             facilities=facilities)
    
    try:
        pickup_id = request.form['pickup_id']
        staff_id = request.form['staff_id']
        vehicle_id = request.form['vehicle_id']
        facility_id = request.form['facility_id']
        
        conn = __import__('db').get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "CALL assign_pickup_to_staff(%s, %s, %s, %s, NULL)",
            (pickup_id, staff_id, vehicle_id, facility_id)
        )
        conn.commit()
        cursor.close()
        conn.close()
        
        return redirect(url_for('staff_dashboard'))
    except Exception as e:
        return f"Error assigning pickup: {e}<br>{traceback.format_exc()}"

# ============= STAFF DASHBOARD =============
@app.route('/staff-dashboard')
def staff_dashboard():
    """Staff workload dashboard"""
    try:
        staff_workload = execute_query("SELECT * FROM v_staff_workload ORDER BY assigned_pickups DESC")
        assigned_pickups = execute_query("""
            SELECT * FROM v_pickup_summary 
            WHERE status IN ('assigned', 'collected') 
            ORDER BY scheduled_time
        """)
        return render_template('staff_dashboard.html', 
                             staff=staff_workload, 
                             pickups=assigned_pickups)
    except Exception as e:
        return f"Error: {e}"

# ============= PAYMENT ROUTES =============
@app.route('/payments')
def list_payments():
    """List all payments"""
    try:
        payments = execute_query("SELECT * FROM v_payment_summary ORDER BY payment_id DESC")
        return render_template('list_payments.html', payments=payments)
    except Exception as e:
        return f"Error: {e}"

@app.route('/make-payment', methods=['GET', 'POST'])
def make_payment():
    """Process payment"""
    if request.method == 'GET':
        # Get collected pickups ready for payment
        pickups = execute_query("""
            SELECT p.pickup_id, p.user_id, u.full_name, p.total_weight_kg, 
                   p.total_amount, p.completed_time
            FROM pickup_requests p
            JOIN users u ON p.user_id = u.user_id
            WHERE p.status = 'collected'
            ORDER BY p.completed_time DESC
        """)
        return render_template('make_payment.html', pickups=pickups)
    
    try:
        pickup_id = request.form['pickup_id']
        payment_method = request.form['payment_method']
        transaction_ref = request.form.get('transaction_ref', None)
        
        conn = __import__('db').get_connection()
        cursor = conn.cursor()
        
        # Call procedure with OUT parameters
        cursor.execute(
            "CALL process_payment(%s, %s, %s, NULL, NULL)",
            (pickup_id, payment_method, transaction_ref)
        )
        conn.commit()
        cursor.close()
        conn.close()
        
        return redirect(url_for('list_payments'))
    except Exception as e:
        return f"Error processing payment: {e}<br>{traceback.format_exc()}"

# ============= BATCH ROUTES =============
@app.route('/batches')
def list_batches():
    """List recycling batches"""
    try:
        batches = execute_query("SELECT * FROM v_batch_summary ORDER BY batch_id DESC")
        return render_template('list_batches.html', batches=batches)
    except Exception as e:
        return f"Error: {e}"

@app.route('/create-batch', methods=['GET', 'POST'])
def create_batch():
    """Create recycling batch"""
    if request.method == 'GET':
        facilities = execute_query("SELECT * FROM recycling_facilities WHERE is_operational = TRUE")
        return render_template('create_batch.html', facilities=facilities)
    
    try:
        facility_id = request.form['facility_id']
        batch_name = request.form['batch_name']
        notes = request.form.get('notes', '')
        
        conn = __import__('db').get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "CALL create_recycling_batch(%s, %s, %s, NULL)",
            (facility_id, batch_name, notes)
        )
        conn.commit()
        cursor.close()
        conn.close()
        
        return redirect(url_for('list_batches'))
    except Exception as e:
        return f"Error creating batch: {e}<br>{traceback.format_exc()}"

# ============= REPORTS =============
@app.route('/reports')
def reports():
    """Analytics and reports page"""
    try:
        # Category statistics
        category_stats = execute_query("""
            SELECT * FROM v_category_statistics 
            WHERE total_items > 0 
            ORDER BY total_value DESC
        """)
        
        # Facility capacity
        facility_capacity = execute_query("SELECT * FROM v_facility_capacity")
        
        # User activity
        user_activity = execute_query("""
            SELECT * FROM v_user_activity 
            WHERE total_pickups > 0 
            ORDER BY total_earnings DESC 
            LIMIT 10
        """)
        
        # Monthly statistics
        monthly_stats = execute_query("""
            SELECT 
                TO_CHAR(request_date, 'Month YYYY') AS period,
                COUNT(*) AS total_pickups,
                SUM(total_weight_kg) AS total_weight,
                SUM(total_amount) AS total_amount
            FROM pickup_requests
            GROUP BY TO_CHAR(request_date, 'Month YYYY'), 
                     EXTRACT(YEAR FROM request_date), 
                     EXTRACT(MONTH FROM request_date)
            ORDER BY EXTRACT(YEAR FROM request_date) DESC, 
                     EXTRACT(MONTH FROM request_date) DESC
            LIMIT 6
        """)
        
        return render_template('reports.html',
                             category_stats=category_stats,
                             facility_capacity=facility_capacity,
                             user_activity=user_activity,
                             monthly_stats=monthly_stats)
    except Exception as e:
        return f"Error: {e}"

# ============= API ENDPOINTS (for AJAX) =============
@app.route('/api/pickup/<int:pickup_id>')
def api_get_pickup(pickup_id):
    """Get pickup details as JSON"""
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
    """Get user statistics"""
    try:
        stats = execute_query(
            "SELECT * FROM get_user_stats(%s)",
            (user_id,)
        )
        return jsonify(stats[0] if stats else {})
    except Exception as e:
        return jsonify({"error": str(e)})

# Run the application
if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)