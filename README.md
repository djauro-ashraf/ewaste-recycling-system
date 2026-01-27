# E-Waste Recycling Management System

## 🎯 Project Overview

This is a **database-driven** e-waste recycling management system where:
- **Database = The System** (contains all logic, rules, and workflows)
- **Backend = Simple Connector** (just forwards requests to database)
- **Frontend = Demo Interface** (only displays database results)

## 📁 Project Structure

```
ewaste-system/
├── database/
│   ├── 01_tables.sql          # Core schema & entities
│   ├── 02_constraints.sql     # Foreign keys & business rules
│   ├── 03_indexes.sql         # Performance optimization
│   ├── 04_views.sql           # Reporting abstraction layer
│   ├── 05_functions.sql       # Reusable calculations
│   ├── 06_procedures.sql      # Business workflow engine
│   ├── 07_triggers.sql        # Automation & auditing
│   ├── 08_sample_data.sql     # Demonstration data
│   ├── 09_transactions_demo.sql # ACID properties demo
│   └── 10_analytics_queries.sql # Advanced analytics
│
├── backend/
│   ├── app.py                 # Flask application
│   ├── db.py                  # Database connection layer
│   └── requirements.txt       # Python dependencies
│
└── frontend/
    ├── templates/
    │   ├── base.html
    │   ├── index.html
    │   ├── create_pickup.html
    │   ├── add_items.html
    │   ├── assign_pickup.html
    │   ├── make_payment.html
    │   ├── list_pickups.html
    │   ├── list_items.html
    │   ├── list_payments.html
    │   ├── list_batches.html
    │   ├── create_batch.html
    │   ├── staff_dashboard.html
    │   └── reports.html
    └── static/
        └── style.css
```

## 🚀 Setup Instructions

### 1. Database Setup (PostgreSQL)

**Step 1:** Create Database
```bash
# Login to PostgreSQL
psql -U postgres

# Create database
CREATE DATABASE ewaste_db;

# Connect to the database
\c ewaste_db
```

**Step 2:** Execute SQL Files in Order
```bash
# From the database directory, run each file in sequence:
psql -U postgres -d ewaste_db -f 01_tables.sql
psql -U postgres -d ewaste_db -f 02_constraints.sql
psql -U postgres -d ewaste_db -f 03_indexes.sql
psql -U postgres -d ewaste_db -f 04_views.sql
psql -U postgres -d ewaste_db -f 05_functions.sql
psql -U postgres -d ewaste_db -f 06_procedures.sql
psql -U postgres -d ewaste_db -f 07_triggers.sql
psql -U postgres -d ewaste_db -f 08_sample_data.sql

# Optional: Run demos
psql -U postgres -d ewaste_db -f 09_transactions_demo.sql
```

**Alternative:** Run All at Once
```bash
cat database/*.sql | psql -U postgres -d ewaste_db
```

### 2. Backend Setup (Python)

**Step 1:** Create Virtual Environment
```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

**Step 2:** Install Dependencies
```bash
pip install flask psycopg2-binary
```

Create `requirements.txt`:
```
Flask==3.0.0
psycopg2-binary==2.9.9
```

**Step 3:** Configure Database Connection

Edit `db.py` or set environment variables:
```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=ewaste_db
export DB_USER=postgres
export DB_PASSWORD=your_password
```

**Step 4:** Run the Application
```bash
python app.py
```

The application will run on `http://localhost:5000`

### 3. Access the System

Open your browser and go to:
```
http://localhost:5000
```

## 📊 Database Architecture

### Core Tables
- **users** - Citizens who request pickups
- **categories** - E-waste types (phones, laptops, etc.)
- **pickup_requests** - Collection requests
- **items** - Individual e-waste items
- **weight_records** - Weight tracking at different stages
- **payments** - Payment transactions
- **recycling_batches** - Grouped items for processing
- **recycling_facilities** - Processing centers
- **vehicles** - Collection vehicles
- **staff_assignments** - Staff/drivers
- **pricing_rules** - Dynamic pricing configuration
- **audit_log** - Complete change history

### Key Features

#### 1. Stored Procedures (Workflows)
- `create_pickup_request()` - Create new pickup
- `add_item_to_pickup()` - Add items with auto-pricing
- `assign_pickup_to_staff()` - Assign resources
- `complete_pickup_collection()` - Mark as collected
- `process_payment()` - Handle payments
- `create_recycling_batch()` - Create batches
- `add_item_to_batch()` - Assign items to batches

#### 2. Functions (Calculations)
- `calculate_item_price()` - Dynamic pricing
- `get_pickup_total_weight()` - Weight aggregation
- `check_vehicle_capacity()` - Capacity validation
- `find_available_staff()` - Resource finder
- `calculate_recyclability_score()` - Item scoring

#### 3. Triggers (Automation)
- Auto-update timestamps
- Audit log all changes
- Alert on high-hazard items
- Validate status transitions
- Prevent invalid operations
- Recalculate totals automatically

#### 4. Views (Reporting)
- `v_pickup_summary` - Complete pickup information
- `v_item_details` - Items with categories
- `v_payment_summary` - Payment records
- `v_batch_summary` - Batch information
- `v_staff_workload` - Staff performance
- `v_facility_capacity` - Capacity status
- `v_category_statistics` - Category analytics
- `v_user_activity` - User engagement

## 🎯 Usage Examples

### Create Pickup Request
1. Go to "Create Pickup Request"
2. Select user
3. Choose preferred date
4. Enter address
5. Submit → Calls `create_pickup_request()` procedure

### Add Items
1. Go to "Add Items"
2. Select pickup request
3. Choose category
4. Enter description and weight
5. Submit → Calls `add_item_to_pickup()` procedure
6. Database automatically:
   - Calculates price using pricing rules
   - Updates pickup totals
   - Logs change in audit table
   - Triggers hazard alert if needed

### Process Payment
1. Go to "Process Payment"
2. Select collected pickup
3. Choose payment method
4. Submit → Calls `process_payment()` procedure
5. Database automatically:
   - Creates payment record
   - Updates pickup status to completed
   - Frees staff and vehicle
   - Logs transaction

## 📈 Analytics & Reports

View comprehensive reports:
- Category performance rankings
- Facility capacity utilization
- Top users by earnings
- Monthly trends
- Staff performance
- Hazardous material tracking
- Weight discrepancy analysis

All reports use views and advanced SQL queries (window functions, CTEs, aggregations).

## 🧪 Testing ACID Properties

Run the transaction demos:
```bash
psql -U postgres -d ewaste_db -f 09_transactions_demo.sql
```

This demonstrates:
- **Atomicity** - All or nothing
- **Consistency** - Constraints enforced
- **Isolation** - No interference
- **Durability** - Committed data persists

## 🎓 Academic Highlights

### Database Features Demonstrated
✅ Complex relational schema (11 tables)  
✅ Foreign keys with different ON DELETE behaviors  
✅ CHECK constraints for business rules  
✅ Composite and partial indexes  
✅ JSONB for flexible data  
✅ Views for abstraction  
✅ User-defined functions  
✅ Stored procedures with transactions  
✅ Triggers for automation  
✅ Audit logging  
✅ Window functions & CTEs  
✅ Advanced analytics queries  

### Why This Design?
This architecture demonstrates that **the database can be the system**, not just storage. All business intelligence lives in PostgreSQL:
- Procedures enforce workflows
- Functions encapsulate logic
- Triggers ensure consistency
- Views provide reports
- The application is just a thin UI layer

## 🔧 Troubleshooting

### Database Connection Failed
- Check PostgreSQL is running: `sudo systemctl status postgresql`
- Verify credentials in `db.py`
- Check firewall settings

### SQL Files Not Loading
- Ensure proper order (01, 02, 03...)
- Check for syntax errors: `psql -U postgres -d ewaste_db < file.sql`

### Flask Not Starting
- Activate virtual environment
- Install dependencies: `pip install -r requirements.txt`
- Check port 5000 is available

## 📝 Notes

- This is a **demonstration system** focused on database design
- UI is intentionally simple to emphasize database layer
- All business logic is in SQL, not application code
- Sample data included for testing

## 📜 License

Educational project - free to use for learning purposes.

---

**Built with:** PostgreSQL 15+ | Python 3.8+ | Flask | HTML/CSS