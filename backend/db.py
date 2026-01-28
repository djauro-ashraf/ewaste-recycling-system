# E-WASTE RECYCLING MANAGEMENT SYSTEM
# db.py - Database Connection Layer

import os
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

# Load environment variables from .env
load_dotenv()

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', 5432)),
    'database': os.getenv('DB_NAME', 'ewaste_db'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', 'postgres')
}

def get_connection():
    """Create and return a database connection"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except Exception as e:
        print(f"Error connecting to database: {e}")
        print(f"Connection details: host={DB_CONFIG['host']}, port={DB_CONFIG['port']}, database={DB_CONFIG['database']}, user={DB_CONFIG['user']}")
        raise

def execute_query(query, params=None, fetch=True):
    """
    Execute a SELECT query and return results
    
    Args:
        query: SQL query string
        params: Query parameters (tuple)
        fetch: Whether to fetch results (default True)
    
    Returns:
        List of dictionaries (rows) or None
    """
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(query, params)
        
        if fetch:
            results = cursor.fetchall()
            return [dict(row) for row in results]
        else:
            conn.commit()
            return None
            
    except Exception as e:
        print(f"Query execution error: {e}")
        print(f"Query: {query}")
        print(f"Params: {params}")
        raise
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

def call_procedure(proc_name, params=None):
    """
    Call a stored procedure with OUT parameters
    
    Args:
        proc_name: Name of the procedure
        params: Procedure parameters (tuple)
    
    Returns:
        Result of the procedure call
    """
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Build CALL statement with proper placeholder count
        if params:
            # Count total parameters including OUT parameters
            if proc_name == "create_pickup_request":
                # Signature: (user_id, preferred_date, address, OUT pickup_id, notes)
                placeholders = "%s, %s, %s, NULL, %s"
                cursor.execute(f"CALL {proc_name}({placeholders})", params)
            elif proc_name == "add_item_to_pickup":
                # Signature: (pickup_id, category_id, description, OUT item_id, condition, weight, hazard)
                placeholders = "%s, %s, %s, NULL, %s, %s, NULL"
                cursor.execute(f"CALL {proc_name}({placeholders})", params)
            elif proc_name == "process_payment":
                # Signature: (pickup_id, method, OUT payment_id, OUT amount, transaction_ref)
                placeholders = "%s, %s, NULL, NULL, %s"
                cursor.execute(f"CALL {proc_name}({placeholders})", params)
            elif proc_name == "create_recycling_batch":
                # Signature: (facility_id, batch_name, OUT batch_id, notes)
                placeholders = "%s, %s, NULL, %s"
                cursor.execute(f"CALL {proc_name}({placeholders})", params)
            else:
                # For procedures without OUT parameters
                placeholders = ', '.join(['%s'] * len(params))
                cursor.execute(f"CALL {proc_name}({placeholders})", params)
        else:
            cursor.execute(f"CALL {proc_name}()")
        
        conn.commit()
        return {"status": "success"}
        
    except Exception as e:
        if conn:
            conn.rollback()
        print(f"Procedure execution error: {e}")
        print(f"Procedure: {proc_name}")
        print(f"Params: {params}")
        raise
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

def call_function(func_name, params=None):
    """
    Call a database function
    
    Args:
        func_name: Name of the function
        params: Function parameters (tuple)
    
    Returns:
        Function result
    """
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        
        # Build SELECT statement
        if params:
            placeholders = ', '.join(['%s'] * len(params))
            select_stmt = f"SELECT {func_name}({placeholders})"
            cursor.execute(select_stmt, params)
        else:
            select_stmt = f"SELECT {func_name}()"
            cursor.execute(select_stmt)
        
        result = cursor.fetchone()
        return result[0] if result else None
        
    except Exception as e:
        print(f"Function execution error: {e}")
        print(f"Function: {func_name}")
        print(f"Params: {params}")
        raise
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

def execute_transaction(statements):
    """
    Execute multiple statements in a transaction
    
    Args:
        statements: List of (query, params) tuples
    
    Returns:
        True if successful, False otherwise
    """
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        
        for query, params in statements:
            cursor.execute(query, params)
        
        conn.commit()
        return True
        
    except Exception as e:
        if conn:
            conn.rollback()
        print(f"Transaction error: {e}")
        raise
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
