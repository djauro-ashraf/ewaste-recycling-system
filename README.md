# E-Waste Recycling Management System v3

## Architecture: 5-Role System

| Role | Login | What they do |
|------|-------|-------------|
| **Admin** | admin | System oversight, alert triage, fire/hire staff, issue warnings, see all logs |
| **Supervisor** | rahman / fatema | Assign driver+collector to pickups, process payments, manage batches |
| **Driver** | karim / jamal / noor | See assigned pickups, record item weights, mark as collected |
| **Collector** | sadia / sumon | Same as driver — both can mark pickups collected |
| **User** | alice / bob / clara / daud | Submit pickups, add items, request payment after window |

All demo passwords: **password123**

## Pickup Lifecycle

```
pending  →  supervisor_assigned  →  field_assigned  →  collected  →  completed
   ↑admin assigns supervisor          ↑supervisor assigns          ↑supervisor
                                       driver+collector              processes
                                                                      payment
```

## Key Business Rules (all enforced in DB)
- **Payment window**: After field collection, user must wait 72 hours. After that a "Request Payment" button appears.
- **Duplicate payment requests**: If user submits a second request while one is pending, it's flagged as duplicate and creates an admin alert.
- **Zero-value pickups**: `total_amount = 0` is fully valid. Not all e-waste has recyclable value.
- **Batch minimum**: A batch must contain items from ≥2 distinct pickups before processing can start.
- **Staff hierarchy**: Supervisors own vehicles and field staff. Only staff under a supervisor can be assigned to that supervisor's pickups.
- **Soft delete**: Firing a staff member sets `fired_at`, disables login — never hard-deletes history.
- **User status**: `active` | `idle` (no pickup 6mo) | `inactive` (12mo) | `suspended` (admin warning with severity=suspension)

## Database Setup

```bash
createdb ewaste_db
for f in database/0*.sql; do psql -d ewaste_db -f "$f"; done
```

## Run

```bash
pip install -r requirements.txt
python app.py
```

Open http://localhost:5000

## Environment Variables

| Variable | Default |
|----------|---------|
| DB_HOST | localhost |
| DB_NAME | ewaste_db |
| DB_USER | postgres |
| DB_PASSWORD | postgres |
| DB_PORT | 5432 |

## DB File Map

| File | Contents |
|------|----------|
| 01_tables.sql | 16 tables, normalized schema with JSONB columns |
| 02_constraints.sql | FK, CHECK, UNIQUE constraints |
| 03_indexes.sql | Performance + GIN indexes on JSONB columns |
| 04_views.sql | 10 views (v_pickup_full, v_supervisor_team, v_overdue_payments, ...) |
| 05_functions.sql | calculate_item_value, get_supervisor_stats (JSONB), estimate_batch_revenue (JSONB) |
| 06_procedures.sql | 10 procedures (full lifecycle + fire_staff, issue_warning, batch flow) |
| 07_triggers.sql | 9 triggers (audit, timestamps, facility load, duplicate payment, user status, alert generation) |
| 08_sample_data.sql | Demo data with real password hashes |

## Windows (PowerShell) Quick Start (PostgreSQL 18)

> Recommended Python: **3.12** (some DB wheels may fail on newer/preview Python builds).

### 1) Create + activate venv

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

### 2) Recreate database (clean)

```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -c "DROP DATABASE IF EXISTS ewaste_db;"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -c "CREATE DATABASE ewaste_db;"
```

### 3) Run SQL files in order

```powershell
$PSQL = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
& $PSQL -U postgres -d ewaste_db -f database\01_tables.sql
& $PSQL -U postgres -d ewaste_db -f database\02_constraints.sql
& $PSQL -U postgres -d ewaste_db -f database\03_indexes.sql
& $PSQL -U postgres -d ewaste_db -f database\04_views.sql
& $PSQL -U postgres -d ewaste_db -f database\05_functions.sql
& $PSQL -U postgres -d ewaste_db -f database\06_procedures.sql
& $PSQL -U postgres -d ewaste_db -f database\07_triggers.sql
& $PSQL -U postgres -d ewaste_db -f database\08_sample_data.sql
```

### 4) Configure `.env`

Create a `.env` file (or copy from `.env.example`) and set your Postgres credentials.

### 5) Run the app

```powershell
python app.py
```

Open: http://127.0.0.1:5000
