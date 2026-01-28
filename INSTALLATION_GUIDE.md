# Installation Guide
## E-Waste Recycling Management System

This guide will help you set up the system from scratch on your local machine.

---

## Prerequisites

Before starting, ensure you have:

1. **PostgreSQL 12 or higher** installed
2. **Python 3.8 or higher** installed
3. **pip** (Python package manager)
4. **Git** (optional, for cloning)
5. Basic command line knowledge

---

## Step-by-Step Installation

### Part 1: PostgreSQL Setup

#### Windows

1. **Download PostgreSQL:**
   - Go to https://www.postgresql.org/download/windows/
   - Download the installer
   - Run the installer

2. **During Installation:**
   - Remember the password you set for the `postgres` user
   - Keep default port 5432
   - Install pgAdmin (recommended for GUI management)

3. **Verify Installation:**
   ```cmd
   psql --version
   ```

#### macOS

1. **Install via Homebrew:**
   ```bash
   brew install postgresql@15
   brew services start postgresql@15
   ```

2. **Or Download:**
   - Go to https://www.postgresql.org/download/macosx/
   - Download and install

3. **Verify:**
   ```bash
   psql --version
   ```

#### Linux (Ubuntu/Debian)

```bash
# Update package list
sudo apt update

# Install PostgreSQL
sudo apt install postgresql postgresql-contrib

# Start service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Verify
psql --version
```

---

### Part 2: Database Creation

#### Option A: Automated Setup (Recommended)

1. **Download the Project:**
   ```bash
   cd /path/to/your/projects
   git clone <repository-url>  # or download and extract ZIP
   cd ewaste-system
   ```

2. **Make Setup Script Executable:**
   ```bash
   chmod +x setup_database.sh
   ```

3. **Run Setup Script:**
   ```bash
   ./setup_database.sh
   ```
   
4. **Follow Prompts:**
   - Enter PostgreSQL password
   - Confirm database recreation if it exists
   - Choose whether to run demo transactions

#### Option B: Manual Setup

1. **Create Database:**
   ```bash
   # Linux/macOS
   sudo -u postgres psql
   
   # Windows (in Command Prompt)
   psql -U postgres
   ```

2. **In PostgreSQL prompt:**
   ```sql
   CREATE DATABASE ewaste_db;
   \c ewaste_db
   \q
   ```

3. **Execute SQL Files in Order:**
   ```bash
   cd database
   
   psql -U postgres -d ewaste_db -f 01_tables.sql
   psql -U postgres -d ewaste_db -f 02_constraints.sql
   psql -U postgres -d ewaste_db -f 03_indexes.sql
   psql -U postgres -d ewaste_db -f 04_views.sql
   psql -U postgres -d ewaste_db -f 05_functions.sql
   psql -U postgres -d ewaste_db -f 06_procedures.sql
   psql -U postgres -d ewaste_db -f 07_triggers.sql
   psql -U postgres -d ewaste_db -f 08_sample_data.sql
   ```

4. **Verify Tables Created:**
   ```bash
   psql -U postgres -d ewaste_db -c "\dt"
   ```
   
   You should see 11 tables listed.

---

### Part 3: Python Backend Setup

1. **Navigate to Backend Directory:**
   ```bash
   cd backend
   ```

2. **Create Virtual Environment:**
   ```bash
   # Windows
   python -m venv venv
   venv\Scripts\activate
   
   # Linux/macOS
   python3 -m venv venv
   source venv/bin/activate
   ```
   
   Your prompt should now show `(venv)`.

3. **Install Dependencies:**
   ```bash
   pip install -r requirements.txt
   ```
   
   This installs:
   - Flask (web framework)
   - psycopg2-binary (PostgreSQL adapter)

4. **Configure Database Connection:**
   
   Open `db.py` and update if needed:
   ```python
   DB_CONFIG = {
       'host': 'localhost',
       'port': 5432,
       'database': 'ewaste_db',
       'user': 'postgres',
       'password': 'your_password_here'  # Change this!
   }
   ```
   
   **Or use environment variables:**
   ```bash
   # Linux/macOS
   export DB_PASSWORD=your_password
   
   # Windows
   set DB_PASSWORD=your_password
   ```

5. **Test Database Connection:**
   ```bash
   python
   >>> from db import get_connection
   >>> conn = get_connection()
   >>> print("Connected!" if conn else "Failed")
   >>> exit()
   ```

---

### Part 4: Running the Application

1. **Start Flask Server:**
   ```bash
   python app.py
   ```
   
   You should see:
   ```
   * Running on http://127.0.0.1:5000
   * Running on http://0.0.0.0:5000
   ```

2. **Access the System:**
   - Open your web browser
   - Go to: `http://localhost:5000`
   - You should see the dashboard

3. **Test the System:**
   - Click "Create Pickup Request"
   - Select a user and enter details
   - Submit and verify it appears in the pickups list
   - Try adding items, making payments, etc.

---

## Troubleshooting

### Problem: "psql: command not found"

**Solution:** PostgreSQL is not in your PATH.

**Windows:**
- Add to PATH: `C:\Program Files\PostgreSQL\15\bin`
- Restart terminal

**Linux/macOS:**
```bash
# Find PostgreSQL location
which psql
# or
find / -name psql 2>/dev/null
```

### Problem: "FATAL: password authentication failed"

**Solution:** Wrong database password.

1. Check your password
2. Or reset it:
   ```bash
   sudo -u postgres psql
   ALTER USER postgres PASSWORD 'new_password';
   ```

### Problem: "FATAL: database does not exist"

**Solution:** Database not created.

```bash
psql -U postgres -c "CREATE DATABASE ewaste_db;"
```

### Problem: "Module 'psycopg2' not found"

**Solution:** Dependencies not installed.

```bash
pip install psycopg2-binary
# or
pip install -r requirements.txt
```

### Problem: "Port 5000 already in use"

**Solution:** Another app using port 5000.

**Change port in app.py:**
```python
if __name__ == '__main__':
    app.run(debug=True, port=5001)  # Changed to 5001
```

### Problem: "Connection refused to localhost:5432"

**Solution:** PostgreSQL not running.

```bash
# Linux
sudo systemctl start postgresql

# macOS
brew services start postgresql

# Windows
# Start from Services or pgAdmin
```

### Problem: SQL files fail to execute

**Solution:** Check for syntax errors or missing dependencies.

1. Run files one by one
2. Check error messages
3. Ensure files are executed in correct order (01, 02, 03...)

---

## Verification Checklist

After installation, verify:

- [ ] PostgreSQL is running
- [ ] Database `ewaste_db` exists
- [ ] 11 tables created
- [ ] 10 views created
- [ ] Sample data loaded (5 users, 5 pickups)
- [ ] Python virtual environment activated
- [ ] Flask server starts without errors
- [ ] Can access http://localhost:5000
- [ ] Dashboard shows statistics
- [ ] Can create pickup request
- [ ] Can add items

---

## Testing the Database Layer

You can test the database independently:

```bash
psql -U postgres -d ewaste_db
```

### Test Queries:

```sql
-- Check sample data
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM pickup_requests;
SELECT COUNT(*) FROM items;

-- Test a view
SELECT * FROM v_pickup_summary LIMIT 5;

-- Test a function
SELECT calculate_item_price(1, 0.5);  -- category_id=1, weight=0.5kg

-- Test a procedure (creates pickup #6)
CALL create_pickup_request(1, '2025-02-15', 'Test Address', NULL, NULL);

-- Check audit log
SELECT * FROM audit_log ORDER BY log_id DESC LIMIT 10;

-- Test analytics
SELECT * FROM v_category_statistics;
```

---

## File Structure Check

Ensure your directory looks like this:

```
ewaste-system/
├── README.md
├── PROJECT_SUMMARY.md
├── INSTALLATION_GUIDE.md
├── setup_database.sh
├── database/
│   ├── 01_tables.sql
│   ├── 02_constraints.sql
│   ├── 03_indexes.sql
│   ├── 04_views.sql
│   ├── 05_functions.sql
│   ├── 06_procedures.sql
│   ├── 07_triggers.sql
│   ├── 08_sample_data.sql
│   ├── 09_transactions_demo.sql
│   └── 10_analytics_queries.sql
├── backend/
│   ├── app.py
│   ├── db.py
│   ├── requirements.txt
│   └── venv/  (created after setup)
└── frontend/
    ├── templates/
    │   ├── base.html
    │   ├── index.html
    │   ├── create_pickup.html
    │   ├── add_items.html
    │   ├── list_pickups.html
    │   └── reports.html
    └── static/
        └── style.css
```

---

## Next Steps After Installation

1. **Explore the Dashboard:**
   - View system statistics
   - Check existing pickups

2. **Create Test Data:**
   - Create new pickup request
   - Add various items
   - Assign to staff
   - Process payment

3. **View Reports:**
   - Check category performance
   - Review facility capacity
   - See user activity

4. **Explore Database:**
   - Open pgAdmin or use psql
   - Examine views, functions, procedures
   - Check audit log

5. **Test Workflows:**
   - Complete end-to-end pickup process
   - Create recycling batches
   - Monitor staff workload

---

## Getting Help

If you encounter issues:

1. **Check Error Messages:**
   - Terminal output for backend errors
   - PostgreSQL logs for database errors
   - Browser console for frontend errors

2. **Verify Prerequisites:**
   - PostgreSQL version: `psql --version`
   - Python version: `python --version`
   - Dependencies installed: `pip list`

3. **Database Connection:**
   - Can you connect with psql?
   - Is password correct?
   - Is PostgreSQL running?

4. **Common Issues:**
   - Check firewall settings
   - Verify port availability
   - Ensure sufficient permissions

---

## Production Deployment Notes

This is a demo system. For production:

1. **Security:**
   - Use strong database passwords
   - Enable SSL for PostgreSQL
   - Implement user authentication
   - Add input sanitization

2. **Performance:**
   - Enable query caching
   - Add connection pooling
   - Consider read replicas
   - Optimize slow queries

3. **Monitoring:**
   - Set up logging
   - Monitor database performance
   - Track error rates
   - Alert on capacity issues

4. **Backup:**
   - Regular database backups
   - Test restore procedures
   - Off-site backup storage

---

## Uninstallation

To completely remove the system:

1. **Drop Database:**
   ```sql
   DROP DATABASE IF EXISTS ewaste_db;
   ```

2. **Remove Files:**
   ```bash
   cd ..
   rm -rf ewaste-system
   ```

3. **Uninstall Python Packages:**
   ```bash
   deactivate  # exit virtual environment
   rm -rf backend/venv
   ```

---

**Installation complete! You now have a fully functional database-driven e-waste management system.**