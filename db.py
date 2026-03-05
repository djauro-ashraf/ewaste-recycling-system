"""
db.py — PostgreSQL connection and query helpers
"""
import os
import psycopg2
import psycopg2.extras
from contextlib import contextmanager

DB_CONFIG = {
    'host':     os.environ.get('DB_HOST', 'localhost'),
    'dbname':   os.environ.get('DB_NAME', 'ewaste_db'),
    'user':     os.environ.get('DB_USER', 'postgres'),
    'password': os.environ.get('DB_PASSWORD', 'postgres'),
    'port':     int(os.environ.get('DB_PORT', 5432)),
}

@contextmanager
def get_conn():
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = False
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def _cursor(conn):
    return conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

def execute_query(sql, params=None):
    with get_conn() as conn:
        with _cursor(conn) as cur:
            cur.execute(sql, params or ())
            return [dict(r) for r in cur.fetchall()]

def execute_one(sql, params=None):
    with get_conn() as conn:
        with _cursor(conn) as cur:
            cur.execute(sql, params or ())
            row = cur.fetchone()
            return dict(row) if row else None

def execute_update(sql, params=None):
    with get_conn() as conn:
        with _cursor(conn) as cur:
            cur.execute(sql, params or ())
            return cur.rowcount

def set_app_user(conn, username):
    """Set session variable so triggers can record who made changes."""
    with conn.cursor() as cur:
        cur.execute("SELECT set_config('app.current_user', %s, TRUE)", (username,))

def call_proc(name, params, username=None):
    """
    Call a PostgreSQL stored procedure using CALL statement.
    params must include None placeholders for OUT parameters.
    Returns a dict of all OUT parameter values (or empty dict).
    """
    with get_conn() as conn:
        if username:
            set_app_user(conn, username)
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            placeholders = ', '.join(['%s'] * len(params))
            sql = f"CALL {name}({placeholders})"
            cur.execute(sql, list(params))
            try:
                row = cur.fetchone()
                return dict(row) if row else {}
            except Exception:
                return {}

def call_func(name, params):
    """Call a set-returning function; returns list of dicts."""
    placeholders = ','.join(['%s'] * len(params))
    sql = f"SELECT * FROM {name}({placeholders})"
    return execute_query(sql, params)
